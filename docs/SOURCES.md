# Clean-room statement

mkspread is an independent implementation.  It is written from public
documentation of file formats (`.WK1`, `.WKS`), from observable behaviour of
the classic DOS spreadsheet interface, and from user knowledge.  No code,
help text, or other material from any commercial product is copied.  Help
screens are original and compiled in.  Record here every outside document
used, with where it came from, when it is used.

## Documents used

- Lotus Development Corporation, *Worksheet File Format* (electronic edition,
  December 1984) and its 2-19-85 addendum: record types and layouts, the
  formula (reverse Polish) code and the opcode list, the cell format byte.
  Read as text mirrored in the SheetJS "notes" repository
  (`oss.sheetjs.com/notes/lotus/WSFF1.TXT` to `WSFF5.TXT`).  This describes
  the original release; the release 2 `.WK1` differences below were found by
  inspecting sample files.
- Wikipedia, *Lotus International Character Set*: the 0x80..0xFF table for
  `charsets.pas`.  Cells the table leaves blank are treated as undefined; the
  Unicode identity of a few symbol cells in 0x80..0x9F is inferred from their
  glyphs.
- Sample worksheet files supplied by the project owner (22 `.WK1` files kept in
  an untracked, git-ignored `private-samples/` folder).  Inspected to confirm
  release 2 details that the 1984 document does not give: the BOF version, the
  32-byte WINDOW1 record, the relative-reference bit flags and signed offsets,
  that a formula's leading `+` is not stored, opcode numbers seen in use, and
  the record order of a real file.  The samples are used only by
  `tests/test_samples.pas`, which prints cell addresses and counts, never cell
  contents.  Header, footer and graph records in the samples contain leftover
  memory fragments rather than clean defaults; they were deliberately not
  copied and this program does not write those records.

- Print records (PRANGE 0x1A, FOOTER 0x25, HEADER 0x26, SETUP 0x27, MARGINS 0x28, TITLES 0x2A, UNFORMATTED 0x30): layouts from the same *Worksheet File Format* text (WSFF2), confirmed by reading the print margins, ranges and setup strings of the sample files (for example margins 0/132/60 and setup `\015`).  The sample files' header and footer contents are not used.
