# Compatibility notes: behaviour not yet verified

Everything here was written from general knowledge of the classic behaviour,
not checked against real files or macros.  When the `.WK1`/`.WKS` sample
corpus is available, verify each item and move it to "confirmed".

## Formulas (phase 4)
- Operator precedence, highest first: `^`; unary `+ -`; `* /`; `+ - &`;
  comparisons; `#NOT#`; `#AND# #OR#`.  `^` is left to right (`2^3^2` = 64) and
  binds tighter than unary minus (`-2^2` = -4).
- Unary plus returns its operand unchanged, including text.
- A label counts as 0 in arithmetic; an empty cell is 0 (or "" with `&`).
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
