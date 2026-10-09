# FSL Lessons Learned ? CSV Parsing & JSON Serialisation Pattern

Derived from the working `BankTransfer:convertCSVFile` service. Apply these rules for any future service that parses delimited text and produces a JSON output.

---

## 1. `pub.list:sizeOfList` pollutes the pipeline with a stale `fromList`

`pub.list:sizeOfList` natively outputs **two** pipeline variables, not one:
- `size` (String) ? the count you want
- `fromList` ? **the original input list echoed back**

If `sizeOfList` is called before a loop that uses `pub.list:appendToDocumentList`, the stale `fromList` (typed as a String[]) is injected by IS into `appendToDocumentList`'s `toList` parameter, causing:

```
java.lang.ClassCastException: [Ljava.lang.String; incompatible with [Lcom.wm.data.IData;
```

**Fix: always call `sizeOfList` AFTER the loop**, measuring the accumulated Document List (`toList`) rather than the input String array. At that point no stale String[] is in the pipeline.

```fsl
// ? WRONG ? sizeOfList before the loop leaves fromList (String[]) in the pipeline
INVOKE pub.list:sizeOfList { ... }   // fromList = rowList String[] now in pipeline
LOOP {
    INVOKE pub.list:appendToDocumentList { ... }   // ClassCastException!
}

// ? CORRECT ? sizeOfList after the loop, measuring the Document List
LOOP {
    INVOKE pub.list:appendToDocumentList { ... }   // toList Document List built up cleanly
}
INVOKE pub.list:sizeOfList {
    input {
        mapSource { recordList toList {}; }
        mapTarget { recordList fromList; }
        copy toList -> fromList;
    }
    output {
        mapSource { String size; }
        mapTarget { String transferCount; }
        copy size -> transferCount;
    }
}
```

---

## 2. Extracting current element in a LOOP over String[] (`$iterationCount`)

When looping over a `String[]` array (e.g. `rowList`), Integration Server does not automatically extract the scalar current element into the pipeline as a simple `String`. Referencing `rowList` directly as a scalar input will pass `null`, resulting in errors like `[ISS.0086.9249] Missing Parameter: inString`.

**Fix: explicitly extract the current row into a scalar variable at the start of each iteration using `set (variable)` with `$iterationCount`.**

```fsl
LOOP {
    inputArray: "/rowList"
    MAP {
        mapSource {
            String[] rowList;
        }
        mapTarget {
            String currentRow;
        }
        set (variable) currentRow = "%rowList[$iterationCount]%";
    }
    // Now use currentRow safely in subsequent steps
}
```

---

## 3. Pipe-delimited tokenize produces rows with leading/trailing whitespace

`pub.string:tokenize` with `delim = "|"` splits on the pipe character but does **not** trim the resulting tokens. Input like:

```
header | row1 | row2
```

produces `" row1 "` and `" row2 "` ? leading space included. If these are then tokenized by `,`, the first field of every data row will have a leading space.

**Fix: always trim each row with `pub.string:trim` before the comma-tokenize step.**

```fsl
INVOKE pub.string:trim {
    input {
        mapSource { String currentRow; }
        mapTarget { String inString; String `type`; }
        copy currentRow -> inString;
        set `type` = "both";
    }
    output {
        mapSource { String `value`; }
        mapTarget { String trimmedRow; }
        copy `value` -> trimmedRow;
    }
}
```

Note: `type` is a reserved FSL keyword ? backticks required everywhere it appears.

---

## 4. Skipping the header row ? strip it before the LOOP, do not use `$iterationCount`

**Do NOT use `IF (%$iterationCount% != "0")` to skip the header row.** This pattern is unreliable because IS stores `$iterationCount` as a Java integer, not a String. String equality comparisons (`!= "0"`) and numeric comparisons (`> "0"`) both behave inconsistently when one operand is an integer type ? in practice the guard either passes the header through or blocks all rows depending on IS version and context.

**Fix: strip the header before the LOOP** using `pub.string:indexOf` + `pub.math:addInts` + `pub.string:substring`. This removes the header row from the string entirely before tokenizing into rows, so the LOOP only ever sees data rows and needs no guard at all.

```fsl
// Step 1 ? find the first record separator
INVOKE pub.string:indexOf {
    input {
        mapSource { String csvString; }
        mapTarget { String inString; String subString; }
        copy csvString -> inString;
        set subString = "|";
    }
    output {
        mapSource { String `value`; }
        mapTarget { String pipeIndex; }
        copy `value` -> pipeIndex;
    }
}
// Step 2 ? advance one character past the separator
INVOKE pub.math:addInts {
    input {
        mapSource { String pipeIndex; }
        mapTarget { String num1; String num2; }
        copy pipeIndex -> num1;
        set num2 = "1";
    }
    output {
        mapSource { String `value`; }
        mapTarget { String dataStart; }
        copy `value` -> dataStart;
    }
}
// Step 3 ? chop off the header
INVOKE pub.string:substring {
    input {
        mapSource { String csvString; String dataStart; }
        mapTarget { String inString; String beginIndex; String endIndex; }
        copy csvString -> inString;
        copy dataStart -> beginIndex;
        set endIndex = "";
    }
    output {
        mapSource { String `value`; }
        mapTarget { String dataRows; }
        copy `value` -> dataRows;
    }
}
// Step 4 ? tokenize data rows only; LOOP needs no header-skip guard
INVOKE pub.string:tokenize {
    input {
        mapSource { String dataRows; }
        mapTarget { String inString; String delim; }
        copy dataRows -> inString;
        set delim = "|";
    }
    output {
        mapSource { String[] valueList; }
        mapTarget { String[] rowList; }
        copy valueList -> rowList;
    }
}
LOOP {
    inputArray: "/rowList"
    // every row here is a data row ? no IF guard required
}
```

**BP-002 note:** `pub.string:indexOf`, `pub.math:addInts`, and `pub.string:substring` all output a pipeline variable named `value` (reserved keyword). Each successive INVOKE must explicitly re-declare `String \`value\`` in its `mapTarget` to override the stale value left by the previous call.

---

## 5. Building a Document List accumulator with `pub.list:appendToDocumentList`

- On the **first iteration** `toList` is absent from the pipeline ? IS creates a new Document List automatically. No pre-seeding required.
- On subsequent iterations `toList` (the native output from the previous call) is already in the pipeline and IS appends to it.
- **Never** `copy toList -> someOtherName` inside the LOOP output block and then try to use `someOtherName` in later iterations ? the native `toList` is what IS continues to append to.
- **Never drop `toList` inside the LOOP** (BP-008) ? it is the live accumulator.

```fsl
INVOKE pub.list:appendToDocumentList {
    input {
        mapSource {
            recordList toList {};
            record transferRecord {};
        }
        mapTarget {
            recordList toList;
            record fromItem;
        }
        copy toList -> toList;
        copy transferRecord -> fromItem;
    }
    output {
        mapSource { recordList toList {}; }
        mapTarget { recordList transferAccum {}; }
        copy toList -> transferAccum;
    }
}
```

After the loop, `toList` (and `transferAccum`) both hold the full Document List. Use `toList` directly in subsequent steps ? it requires no intermediate renaming.

---

## 6. Serialising a Document List to JSON ? wrap it first

`pub.json:documentToJSONString` takes a `document` (Document / IData), not a Document List directly. Passing a Document List to `document` produces a flat serialisation rather than a proper JSON array under a named key.

**Pattern: create a wrapper document with a named child `recordList`, then pass the wrapper.**

```fsl
// Step 1 ? build wrapper document
MAP {
    mapSource {
        recordList toList {};
    }
    mapTarget {
        record data {
            recordList transactions {};
        };
    }
    copy toList -> data/transactions;
}

// Step 2 ? serialise wrapper
INVOKE pub.json:documentToJSONString {
    input {
        mapSource { record data {}; }
        mapTarget { record `document`; }
        copy data -> `document`;
    }
    output {
        mapSource { String jsonString; }
        mapTarget { String transfersJSON; }
        copy jsonString -> transfersJSON;
    }
}
```

Output JSON shape:
```json
{
  "transactions": [
    { "transferDate": "2025-10-13", "fromAccount": "GB24-13356886", ... },
    ...
  ]
}
```

Note: `document` is a reserved FSL keyword ? backticks required in `mapTarget`.

---

## 7. BP-002 ? stale `inString` and `delim` when tokenizing twice

The first `pub.string:tokenize` (pipe split) leaves `inString` and `delim` in the pipeline. The second call inside the LOOP (comma split) must **explicitly override both** in its `mapTarget`:

```fsl
mapTarget {
    String inString;   // override stale value from pipe-split
    String delim;      // override stale "|" with ","
}
copy trimmedRow -> inString;
set delim = ",";
```

Without the explicit override IS silently injects the stale values and the comma-split never runs correctly.

---

## 8. Extracting positional fields from a String[] using `set (variable)`

After tokenizing a row by comma, use `set (variable)` with array index notation to extract each field by position ? no inner LOOP required:

```fsl
MAP {
    mapTarget {
        String transferDate;
        String fromAccount;
        // ...
    }
    set (variable) transferDate = "%fieldList[0]%";
    set (variable) fromAccount  = "%fieldList[1]%";
    // ...
}
```

A plain `set` (without `(variable)`) assigns the literal string `"%fieldList[0]%"` ? it does NOT evaluate the path. Always use `set (variable)` for runtime substitution.

---

## Complete verified flow structure

```
pub.string:indexOf (subString="|")       ? pipeIndex
pub.math:addInts (pipeIndex + "1")       ? dataStart
pub.string:substring (dataStart ? end)  ? dataRows   (header stripped)
pub.string:tokenize (dataRows, delim="|") ? rowList (String[], data rows only)
LOOP over rowList                        (no header-skip guard needed)
  MAP set (variable) currentRow          ? currentRow = "%rowList[$iterationCount]%"
  pub.string:trim                        ? trimmedRow
  pub.string:tokenize (delim=",")        ? fieldList (String[])
  MAP set (variable) x6                 ? flat field variables
  MAP copy into record                   ? transferRecord (Document)
  pub.list:appendToDocumentList          ? toList (Document List)
pub.list:sizeOfList (toList)             ? transferCount
MAP copy toList ? data/transactions      ? data (Document)
pub.json:documentToJSONString (data)     ? transfersJSON
```

