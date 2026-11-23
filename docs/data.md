# /Data commands

| Command | What it does |
|---|---|
| `/Data Fill` | Fill a range down each column in turn with Start, Step, Stop (defaults 0, 1, 8191). |
| `/Data Table 1` | One-variable what-if table: values down the first column, formulas along the first row, one input cell. |
| `/Data Table 2` | Two-variable table: the formula in the corner, row values and column values, two input cells. |
| `/Data Table Reset`, F8 | Forget the table / run the last one again. |
| `/Data Sort` | Data-Range, Primary-Key, Secondary-Key (any cell in the key column, then A or D), Reset, Go. |
| `/Data Query` | Input (field names in the first row), Criteria, Output (field names), Find, Extract, Unique, Delete, Reset. |
| `/Data Distribution` | Frequency counts of a values range in the bins of a bin column; counts go in the column to the right, with one extra cell for "more". |
| `/Data Matrix` | Invert (square, at most 90 by 90) and Multiply; the output range's top left corner is used. |
| `/Data Regression` | X-Range (one or more columns), Y-Range, Output-Range, Intercept Compute or Zero, Reset, Go. |
| `/Data Parse` | Format-Line Create/Edit, Input-Column, Output-Range, Reset, Go: split long labels into cells. |

## Details
- **Sort:** numbers come before text, text in character order (capitals first),
  empty cells always last; ties keep their order.  Formulas move with their rows
  and keep pointing at their own row (relative references shift like /Copy).
- **Query criteria** work like the database functions: the first row of the
  criteria range names fields, each further row is an alternative, all filled
  cells of a row must hold.  Text is matched exactly, ignoring case, with `?`
  and `*` wildcards and `~` for "not"; a number matches an equal number.
  Comparison operators written in a label (`>15`) are not operators.
  Extract copies values (formulas become their values) into the output range
  under its field names, in the output's column order; an output range with more
  than one row limits the number of records.
- **Find** (`FIND` mode): Down/Right and Up/Left step through the matching
  records, Home and End go to the first and last, Esc or Enter leave and put the
  pointer back.
- **Delete** asks Cancel/Delete, removes matching records and closes the gap.
- **Table:** each substitution recalculates the whole worksheet; the answers are
  stored as plain values and the input cells are put back.  `/Data Table` needs
  the table range, then the input cell(s); F8 repeats it.
- **Regression output** (at the output cell): `Regression Output:`, `Constant`,
  `Std Err of Y Est`, `R Squared`, `No. of Observations`, `Degrees of Freedom`
  (labels in the first column, values three columns right), then `X Coefficient(s)`
  and `Std Err of Coef.` with one value per X column.  If Y is a single row the
  observations are taken along rows.
- **Parse:** a format line is a label starting with `|` whose characters line
  up with the text below it: `L` label, `V` value, `D` date, `T` time, `S` skip,
  each followed by `>` for the rest of its width, `*` for a gap.
  `Format-Line Create` builds one from the label under the pointer.  Go splits
  every label in the input column using the nearest format line above it.

The settings of Sort, Query, Table, Regression and Parse are remembered while
the program runs but are not saved in worksheet files.
