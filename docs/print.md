# Printing

`/Print Printer` or `/Print File` chooses the destination, then the print menu
stays open: Range, Line, Page, Options, Clear, Align, Go, Quit.  The text made by
`Go` is collected and sent when you leave the menu.

- **Printer** sends the text to the print command.  By default that is `lp` (CUPS);
  set `MKSPREAD_PRINT_COMMAND` to use another (the text is given on its standard
  input), e.g. `lpr -P office` or `cat > out.txt`.  The setup string comes first.
- **File** asks for a name (`.PRN` is added; Cancel/Replace if it exists) and
  appends each print job to it.

## Layout
- Page length 66 by default.  A page is: top margin lines, the header, two blank
  lines, the text, two blank lines, the footer, bottom margin lines; with the
  defaults 56 lines of text.  The header and footer lines are always reserved.
- The text is `Right - Left` characters wide, indented by the left margin (default 4
  and 76).  A wider range is printed in groups of columns, the first group down
  all pages, then the next; border columns come first in every group, border rows
  at the top of every page.
- Header/Footer: `left|centre|right`, `#` = page number, `@` = date.
- Rows whose first cell (in the print range) is a label with the `|` prefix are
  not printed; `|::` is a page break.  `/Worksheet Page` inserts such a row.
- Options Other: As-Displayed prints cells as on the screen; Cell-Formulas
  prints one line per cell, `A1: (F2) [W12] contents`; Unformatted leaves out
  margins, headers, footers, borders and page breaks.
- Setup string: `\nnn` is the byte with decimal code nnn.

The print range, header, footer, setup string, margins, page length, borders and
Formatted/Unformatted are saved in `.WK1` files and restored by File Retrieve (a file
without them gets the defaults).  Cell-Formulas is not saved (no known record), and
neither is the paper position or the print destination.  Header and footer strings
that hold control characters (left-over memory in some old files) are ignored.
The paper position is remembered between jobs (as in the original): Go does not
finish the last page; `Page` does, and `Align` says the paper is at the top.  A job
that starts mid-page has no top margin or header (the page already has one).

## Checking against the original program
`make printsheet` writes `private-samples/PRINT.WK1` (13 print jobs, macro `\R`) and
the `.PRN` files mkspread makes for the same keystrokes in `private-samples/printexp/`.
Run `\R` in the original program (delete old `P*.PRN` first), copy its files to a
folder, then `python3 tests/cmp_print.py private-samples/printexp <folder>`.
