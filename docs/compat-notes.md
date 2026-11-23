# Compatibility notes: behaviour not yet verified

Everything here was written from general knowledge of the classic behaviour,
not checked against real files or macros.  When the `.WK1`/`.WKS` sample
corpus is available, verify each item and move it to "confirmed".

## Formulas (phase 4)
- Operator precedence, highest first: `^`; unary `+ -`; `* /`; `+ - &`;
  comparisons; `#NOT#`; `#AND# #OR#`.  This order is **confirmed** by the
  original file-format document's precedence table (`&` is not in it; it is
  placed with `+ -` by assumption).  `^` left to right and `-2^2` = -4 follow
  from that table.
- Unary plus returns its operand unchanged, including text.
- A label counts as 0 in arithmetic; an empty cell is 0 (or "" with `&`).
  **Observed:** a string literal in arithmetic is 0 too (`+"a"+1` = 1).
- `&` refuses numbers (ERR); a string literal in arithmetic is ERR.
- Text comparison ignores case; text never compares with numbers (ERR).
- ERR beats NA when both are present.
- `@SUM` ignores text in ranges.
- Spaces are accepted inside formulas and removed in the stored form.
- Recalculation always covers every formula (no incremental recalculation).
  Columnwise and rowwise order sweep the formula cells once per iteration;
  natural order follows dependencies and flags circular references (CIRC).

## Display (phase 3)
- Date formats D1-D5 and time formats D6-D9 layouts.
- General format rounding and when it switches to scientific notation.
- Undo is enabled by default.

## Editing commands (phase 5)
- Copy: a single cell fills the whole TO range; a single row is repeated down
  it; a single column is repeated across it; any other block is copied once at
  the TO range's top left.  Copying a blank cell clears the target cell.
- Copy: a relative reference pushed off the edge of the sheet becomes `@ERR`.
- Move: references to cells that the move overwrote become `@ERR`; references
  into the moved block follow it.  Range corners follow individually.
- Delete: a reference to a deleted cell becomes `@ERR`; a range shrinks around
  deleted rows or columns and becomes `@ERR` only when all of it is deleted.
  Insert: a range grows when rows or columns are inserted inside it.
- Range names: up to 15 letters, digits and underscores, not starting with a
  digit and not a cell address; stored upper case.  A formula using an
  undefined name shows ERR until the name exists (it is not rejected on entry).
  A multi-cell name used outside a function is ERR.  A name whose range is
  entirely deleted disappears.
- `/Range Value` and `/Range Trans` keep values only; a text result becomes a
  label; ERR and NA leave the cell empty.
- Titles: frozen rows start at the top screen row at the moment of the
  command; deleting rows or columns that include titles clears that title.
- Not implemented: `/Worksheet Window` (needs a two-pane renderer).

## Files (phase 6)
Confirmed against 22 real release 2 files: BOF `0604`; record layouts for cells,
column widths, titles, window, labels; the format byte; relative references
(bit 15 set = relative, low 8 bits of a column / 13 of a row = signed offset
from the formula's cell); a leading `+` is not stored; `@SUM`, `@ROUND`, `@PMT`
opcodes; 543 formulas decode, re-encode to identical bytes and recalculate to
the stored values.

Assumed, not yet checked against real files:
- Files this program writes have not been opened by the original program.
  Optional records (print setup, graph, header, footer, 0x96) are not written.
- The protection bit is always written set (the default); protection is not
  tracked, so "unprotected" cells lose that flag on load.
- Global zero display, `/Range Prot` and similar settings are not saved.
- Range names used in formulas are written as the addresses they stand for
  (the format has no name token); on reading they stay addresses.
- Formulas that produce text are written with a STRING (0x33) record after the
  FORMULA record, and read back the same way.
- Function opcode numbers other than 56, 63 and 80 come from the 1985 addendum;
  argument counts of fixed-argument functions are my reading of the function
  definitions, `@CHOOSE` is treated as a list function and `@VAR`/`@STD` as
  one-argument functions.  A formula that does not decode cleanly is kept as
  its stored value, with a warning.
- `.WKS` (original format) is read and written with the same record layouts;
  only the BOF and the 31-byte WINDOW record differ.
- A range stored with its corners in the "wrong" order (`D34..C36`) is read as
  `C34..D36` and written back that way.
- Whole numbers are written as INTEGER records when they fit in 16 bits; some
  files store the same numbers as NUMBER records.  Both read back the same.
- Text import: a DOS end-of-file mark ends the text; text that is not valid
  UTF-8 is read as code page 437.  In the classic "Numbers" import unquoted
  non-numeric text is skipped; for `.CSV` files every field is imported.
- `/File Combine` copies non-blank cells only; Add and Subtract change only
  numeric cells and leave labels alone.
- `/File Xtract` puts the extracted range at A1 and copies formulas like
  `/Copy` does.

## @functions (phase 7)
All assumptions below are exercised by `MKTEST.WK1` (see `make testsheet`):
open it in the original program, recalculate, and read the total of
differences in A3.
- Function names and file opcodes are from the 1985 document, confirmed for
  `@SUM`, `@ROUND` and `@PMT` by sample files.  `@TERM`, `@CTERM`, `@RATE`,
  `@SLN`, `@SYD`, `@DDB` have no known file code: formulas using them are
  saved as their value (with a warning).
- Indexes in `@MID`, `@REPLACE`, `@FIND`, `@CHOOSE`, `@INDEX` count from 0.
- `@AVG`, `@MIN`, `@MAX`, `@VAR`, `@STD` treat text in a range as zero and
  ignore blank cells; `@COUNT` counts every non-blank cell, text included;
  `@VAR` and `@STD` are population statistics; `@SUM` ignores text.
- `@ISERR(@NA)` is 0 and `@ISNA(@ERR)` is 0.  `@ISNUMBER` of a blank cell is 1.
- `@INT` truncates toward zero; `@MOD` takes the sign of the first argument;
  `@ROUND` rounds half away from zero; `@ATAN2(x,y)` is the angle of (x,y).
- `@DATE` needs a year of 0..199 (1900..2099); `@YEAR` returns year-1900;
  serial 60 is the 29-Feb-1900 leap-year quirk.
- `@DATEVALUE` reads `DD-MMM-YY`, `DD-MMM`, `MMM-YY`, `MM/DD/YY`, `MM/DD`;
  missing years mean the current year.
- `@VLOOKUP`/`@HLOOKUP`: numbers find the last key not above the value (NA
  below the first); text needs an exact match, ignoring case.
- Database functions: criteria rows are alternatives, cells in a row all must
  hold; text criteria are exact (case-insensitive, `?` and `*` wildcards, `~`
  negates).  **Observed in the original program:** a label such as `>15` is
  not a comparison; it matches no record.  Formula criteria are not supported.
- **Observed in the original program:** `@VLOOKUP` of a value below the first
  key is ERR (not NA); a function argument that is a range is stored as a
  range token even for one cell (`@N(G7)` is `@N(G7..G7)` in the file), and
  `@N`, `@S`, `@CELL` returned ERR when it was stored as a plain reference.
- `@NPV` and `@IRR` use the numeric cells of the range in row-major order and
  skip blanks and text.
- `@@("A1")` is the contents of the cell named by the text; `@CALL` is ERR.

## Observed in the original program (from the MKTEST worksheets)
Confirmed by running the generated worksheets in DOS Lotus:
- Precedence and every operator row of MKTEST agree, including `2^3^2` = 64,
  `-2^2` = -4, text comparison ignoring case, `&`.
- A string in arithmetic counts as zero (`+"a"+1` = 1).
- General format shows up to 10 decimals (`0.1234567891`).
- Date formats D1, D3 and D4 show a four-digit year from 2000 on
  (`01-Jan-2000`, `Jan-2000`, `01/01/2000`); D2 and D5 have no year.
- The `+/-` format is left-aligned.
- Label prefixes (left, right, center, repeat) and LICS accents
  (`café £°Ñ`) display as expected.
- `@VLOOKUP` below the first key is ERR; single-cell range arguments are stored
  as range tokens; a `>` in a database label criterion is not an operator.
- Probable (to be re-checked with the next MKT7.WK1): `@VAR` and `@STD` are
  list functions with an argument-count byte; with one stored as a fixed
  function the original reported "Number stack full".

## File layout fixes found by running files in the original program
- WINDOW1 (record 7) is 32 bytes; the row-number and column-letter border
  widths are at offsets 24 and 26 (4 and 4); a zero hides the border.  An
  earlier version wrote these fields in the wrong order and the original
  program showed no row numbers or column letters.
- Frozen worksheet titles are stored in WINDOW1 (title column count at 16,
  title row count at 18, first title column at 20, first title row at 22), not
  in the TITLES record, which holds the print borders (written as unset).
- `tests/test_samples.pas` now also compares the length of every record type
  this program writes with the same record in each real file.

## Confirmed from a worksheet created in the original program (`tst1.wk1`)
- File codes: `@RATE` 116, `@TERM` 117, `@CTERM` 118, `@SLN` 119, `@SYD` 120,
  `@DDB` 121; also `@CELLPOINTER` 79, `@S` 111, `@N` 112, `@@` 115, `@NOW` 55
  (all as in the 1985 table).  Their results match this program's.
- `@TODAY` is not accepted by that version (it has `@@`, so probably 2.2 or
  later).
- A formula that returns text is a FORMULA record whose cached number is a NaN
  with a non-zero fraction, followed by a STRING (0x33) record holding the text.
- That version writes relative offsets sign-extended to 14 bits (a column one to
  the left is 0xBFFF); the older sample files use 8 bits for columns and 13 for
  rows with zero fill.  Both are read; this program writes the older form.
- The `Text` format and the `+/-` format are left-aligned.  Time formats D6 to
  D9, the 29-Feb-1900 display and `Hidden` match.

## Macros (phase 8)
Written from knowledge of the classic behaviour; to be checked in the original
program:
- A macro ends at the first empty cell or non-text cell; text formulas count as
  text.
- `{IF}` false skips the rest of its cell and continues at the next cell down.
- A bare word in `{LET}` is text unless it names a range.
- `{GET}` stores the typed character as a label; special keys as `{UP}` etc.
- Esc in a `{MENUBRANCH}` ends the macro.
- `{LOOK}` always stores an empty label; `{WAIT}`, `{BEEP}`, `{ONERROR}` do
  nothing.
- Keys typed by the user during `{?}` go to the worksheet exactly as typed.
- Changes made directly by macro commands are not undoable.
