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
