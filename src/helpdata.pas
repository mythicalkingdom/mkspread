{ The help screens, compiled into the program.  Each topic has an id, a title,
  the text (lines separated by | in the source) and the ids of related topics.
  All text is original to mkspread. }
unit helpdata;

{$mode objfpc}{$H+}

interface

function HelpCount: Integer;
function HelpIndexOf(const id: string): Integer;      { -1 when there is no such topic }
function HelpId(i: Integer): string;
function HelpTitle(i: Integer): string;
function HelpBody(i: Integer): string;                 { lines separated by #10 }
function HelpRelated(i: Integer): string;              { ids separated by commas }

{ the topic for a menu position such as "Range Format Fixed" }
function HelpForMenu(const path: string): string;

{ replaces the text of a topic that is made while the program runs (the Status screen) }
procedure HelpSetTopic(const id, title, body: string);

implementation

uses SysUtils;

type
  THelpTopic = record
    Id, Title, Body, Related: string;
  end;

var
  Topics: array of THelpTopic;

procedure T(const id, title, body, related: string);
var
  n: Integer;
begin
  n := Length(Topics);
  SetLength(Topics, n + 1);
  Topics[n].Id := id;
  Topics[n].Title := title;
  Topics[n].Body := StringReplace(body, '|', #10, [rfReplaceAll]);
  Topics[n].Related := related;
end;

function HelpCount: Integer;
begin
  Result := Length(Topics);
end;

function HelpIndexOf(const id: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Topics) do
    if Topics[i].Id = id then exit(i);
  Result := -1;
end;

function HelpId(i: Integer): string; begin Result := Topics[i].Id; end;
function HelpTitle(i: Integer): string; begin Result := Topics[i].Title; end;
function HelpBody(i: Integer): string; begin Result := Topics[i].Body; end;
function HelpRelated(i: Integer): string; begin Result := Topics[i].Related; end;

procedure HelpSetTopic(const id, title, body: string);
var
  i: Integer;
begin
  i := HelpIndexOf(id);
  if i < 0 then
  begin
    i := Length(Topics);
    SetLength(Topics, i + 1);
    Topics[i].Id := id;
    Topics[i].Related := '';
  end;
  Topics[i].Title := title;
  Topics[i].Body := body;
end;

function HelpForMenu(const path: string): string;
var
  p: string;
  k: Integer;
begin
  p := LowerCase(path);
  if Pos('print printer', p) = 1 then p := 'print' + Copy(p, 14, MaxInt)
  else if Pos('print file', p) = 1 then p := 'print' + Copy(p, 11, MaxInt);
  while p <> '' do
  begin
    if HelpIndexOf('m:' + p) >= 0 then exit('m:' + p);
    k := Length(p);
    while (k > 0) and (p[k] <> ' ') do Dec(k);
    p := Copy(p, 1, k - 1);
  end;
  Result := 'menus';
end;

procedure Build;
begin
  T('index', 'Help Index',
    'Choose a topic with the arrow keys and press Enter.|Esc leaves help; Backspace goes back to the previous screen.',
    'basics,screen,modes,keys,fkeys,entry,editing,formulas,ranges,functions,menus,' +
    'm:worksheet,m:range,m:copy,m:move,m:file,m:data,m:print,m:graph,m:system,m:quit,' +
    'filefmt,recovery,macros,learn,recalc,dates,undo,errors,about');

  T('basics', 'Getting started',
    'mkspread is a spreadsheet for the terminal.  The worksheet is a grid of cells:|' +
    'columns A to IV and rows 1 to 8192.  Move the pointer with the arrow keys,|' +
    'type something and press Enter to put it in the cell.|' +
    '|' +
    'A number or a formula (starting with + - @ ( . # $ or a digit) is a value;|' +
    'anything else is a label.  Start a label with an apostrophe to make it text|' +
    'that looks like a number.|' +
    '|' +
    'Press / (or <) to open the menu.  Type the first letter of a command, or|' +
    'move to it with the arrow keys and press Enter.  Esc steps back, Ctrl-C|' +
    'leaves the menu.|' +
    '|' +
    'The commands work like the classic Release 2 spreadsheet menus, so the|' +
    'keystrokes of old macros and habits carry over.',
    'screen,keys,entry,menus');

  T('screen', 'The screen',
    'Line 1   the pointer address and its contents, and the mode indicator.|' +
    'Line 2   what you are typing, or the menu choices.|' +
    'Line 3   a note about the highlighted menu choice, or more of the entry.|' +
    'Line 4+  the column letters, row numbers and the cells.|' +
    'Bottom   the date and time, messages, and status indicators.|' +
    '|' +
    'Status indicators:|' +
    '  CALC  the worksheet needs recalculating (press F9)|' +
    '  CIRC  a formula refers to itself|' +
    '  UNDO  Alt-F4 would undo the last change|' +
    '  END   the End key was pressed|' +
    '  CMD   a macro is running or waiting|' +
    '  STEP  step mode is on;  LEARN  keystrokes are being recorded',
    'modes,basics');

  T('modes', 'Mode indicators',
    'READY   waiting for a command or an entry|' +
    'LABEL   typing a label            VALUE   typing a number or formula|' +
    'EDIT    editing an entry (F2) or answering a prompt|' +
    'MENU    a menu is open            POINT   choosing a cell or range|' +
    'NAMES   choosing from a list of names or files|' +
    'FIND    stepping through records (Data Query Find)|' +
    'HELP    reading these screens',
    'screen,ranges');

  T('keys', 'Moving around',
    'Arrow keys      one cell            PgUp / PgDn       one screen up / down|' +
    'Ctrl-Right/Left one screen sideways  Tab / Shift-Tab   same, in one key|' +
    'Home            cell A1                Ctrl-Home   also cell A1|' +
    'End + arrow     to the end of a block of filled cells, or the next one|' +
    'End Home        the last cell that holds anything|' +
    'F5 (GOTO)       type an address or a range name and jump there|' +
    '|' +
    'Alt-F3 lists range names to run as macros.  Alt-F4 (or Ctrl-U) undoes the last|' +
    'change.  Ctrl-C (Ctrl-Break) stops what is happening and returns to READY.',
    'fkeys,ranges');

  T('fkeys', 'Function keys',
    'F1  help                        F6  switch to the other window|' +
    'F2  edit the current cell       F7  repeat the last Data Query|' +
    'F3  list names or files         F8  repeat the last Data Table|' +
    'F4  absolute / relative cycle   F9  recalculate|' +
    'F5  go to a cell                F10 graph (graphs are not supported)|' +
    '|' +
    'Alt-F2  STEP on or off          Alt-F4  undo|' +
    'Alt-F3  run a macro by name     Alt-F5  LEARN on or off|' +
    'Alt-A .. Alt-Z  run the macro named \A .. \Z|' +
    '|' +
    'Some terminals keep Alt and function keys for themselves.  Run mkspread with|' +
    '--keytest to see what your terminal sends.',
    'macros,keys');

  T('entry', 'Entering data',
    'Type and press Enter.  What the first character is decides the kind:|' +
    '  digit + - . ( @ # $   a value (number or formula)|' +
    '  anything else         a label, stored with the label prefix '' (left)|' +
    '|' +
    'Label prefixes:  '' left  " right  ^ centre  \ repeat  (vertical bar: no print)|' +
    'Type one first to choose the alignment; /Worksheet Global Label-Prefix sets|' +
    'the default.  Text that looks like a number needs a prefix.|' +
    '|' +
    'Esc cancels an entry, Backspace deletes a character, F2 edits it.|' +
    'In a formula, after an operator, ( or comma, an arrow key points at a cell|' +
    'instead of ending the entry (POINT): the address is typed for you.  Press .|' +
    'to anchor a range, F4 to make the reference absolute, then go on typing.|' +
    'An arrow key ends the entry and moves the pointer.',
    'editing,formulas');

  T('editing', 'Editing a cell (F2)',
    'F2 puts the cell contents on line 2 for editing.|' +
    '  Left / Right    move one character     Home / End   start / end|' +
    '  Backspace       delete to the left     Del          delete here|' +
    '  Enter           store the result       Esc          give up|' +
    '  Up / Down       store the result and move the pointer|' +
    '|' +
    'F4 cycles the reference next to the cursor: A1, $A$1, A$1, $A1.|' +
    'If a formula is wrong, mkspread leaves you in EDIT mode at the problem.',
    'entry,formulas');

  T('formulas', 'Formulas and operators',
    'A formula starts with + or - or ( or @ and may use:|' +
    '  ^            power                  (highest)|' +
    '  - +          unary minus, plus|' +
    '  * /          multiply, divide|' +
    '  + -          add, subtract|' +
    '  = <> < > <= >=   comparisons (1 for true, 0 for false)|' +
    '  #NOT#  #AND#  #OR#               logical        (lowest)|' +
    '  &            joins strings|' +
    'Use parentheses to change the order.  Cell references (B7, $B$7), ranges|' +
    '(B7..D9) and range names may appear anywhere a number can.|' +
    'Text used in arithmetic counts as 0.  Strings are written between quotes.|' +
    'A circular reference shows CIRC; an error value shows ERR or NA.',
    'functions,ranges,recalc,errors');

  T('ranges', 'Cells, ranges and names',
    'A cell is a column letter and a row number: C5.  A range is two corners:|' +
    'B2..D9 (a single dot also works at a prompt).  Put $ before the letter or|' +
    'number to keep it fixed when the formula is copied: $B$2.|' +
    '|' +
    'Where a prompt asks for a range you are in POINT mode.  Either type the|' +
    'address, or press . to anchor a corner and extend it with the arrow keys,|' +
    'then press Enter.  Esc un-anchors, then cancels.  F3 lists range names.|' +
    '|' +
    '/Range Name Create gives a range a name (up to 15 characters).  A name may|' +
    'be used in formulas and at any range prompt.  A name of a backslash and a|' +
    'letter (\A) is a macro.',
    'm:range name,formulas,macros');

  T('functions', '@Functions',
    'A function is written @NAME(arguments).  Choose a family:',
    'fn-math,fn-string,fn-date,fn-fin,fn-logic,fn-stat,formulas');

  T('fn-math', 'Math functions',
    '@ABS(x)  @INT(x)  @SQRT(x)  @MOD(x,y)  @ROUND(x,places)  @EXP(x)|' +
    '@LN(x)  @LOG(x)  @PI|' +
    '@SIN(x)  @COS(x)  @TAN(x)  @ASIN(x)  @ACOS(x)  @ATAN(x)  @ATAN2(x,y)|' +
    '@RAND   a random number from 0 up to 1|' +
    '@SUM(list)  @AVG(list)  @COUNT(list)  @MIN(list)  @MAX(list)|' +
    '@VAR(list)  @STD(list)    (population variance and standard deviation)|' +
    '|' +
    'A list holds numbers, cells and ranges separated by commas.  Labels in a|' +
    'range count as 0 in @SUM and @AVG and are counted by @COUNT.',
    'functions,fn-stat');

  T('fn-string', 'String functions',
    '@LEFT(s,n)  @RIGHT(s,n)  @MID(s,start,n)  @LENGTH(s)  @REPEAT(s,n)|' +
    '@UPPER(s)  @LOWER(s)  @PROPER(s)  @TRIM(s)  @CLEAN(s)|' +
    '@FIND(search,s,start)   position of a substring, counting from 0|' +
    '@REPLACE(s,start,n,new)  @EXACT(a,b)  @STRING(x,places)  @VALUE(s)|' +
    '@CHAR(code)  @CODE(s)   character set conversions|' +
    '@S(range)  @N(range)    the text / number in the first cell of a range|' +
    '|' +
    'Join strings with &.  The first position in a string is 0 in @FIND and|' +
    '@MID, as in the original program.',
    'functions,formulas');

  T('fn-date', 'Date and time functions',
    'Dates are serial numbers: 1 is 1 January 1900 (the original program counts|' +
    'a non-existent 29 February 1900, and so do we).  Times are fractions of a day.|' +
    '@DATE(y,m,d)  @DATEVALUE(s)  @NOW  @DAY(n)  @MONTH(n)  @YEAR(n)|' +
    '@TIME(h,m,s)  @TIMEVALUE(s)  @HOUR(n)  @MINUTE(n)  @SECOND(n)|' +
    '|' +
    '/Range Format Date shows a serial number as a date or a time.',
    'dates,functions');

  T('fn-fin', 'Financial functions',
    '@PMT(principal,rate,term)   payment per period of a loan|' +
    '@PV(payment,rate,term)      present value of a series of payments|' +
    '@FV(payment,rate,term)      future value of a series of payments|' +
    '@NPV(rate,range)  @IRR(guess,range)  @RATE(fv,pv,term)  @TERM(pmt,rate,fv)|' +
    '@CTERM(rate,fv,pv)  @SLN(cost,salvage,life)  @SYD(cost,salvage,life,period)|' +
    '@DDB(cost,salvage,life,period)|' +
    '|' +
    'Rates are per period, written as a decimal (0.01 for 1 percent).',
    'functions');

  T('fn-logic', 'Logical and special functions',
    '@IF(test,true-value,false-value)   @TRUE  @FALSE|' +
    '@ISNUMBER(x)  @ISSTRING(x)  @ISERR(x)  @ISNA(x)  @NA  @ERR|' +
    '@CHOOSE(n,v0,v1,...)   the nth value, counting from 0|' +
    '@VLOOKUP(key,range,column)  @HLOOKUP(key,range,row)  @INDEX(range,col,row)|' +
    '@COLS(range)  @ROWS(range)  @CELL("attr",range)  @CELLPOINTER("attr")|' +
    '|' +
    'The lookup functions need the first column (row) sorted ascending.',
    'functions,errors');

  T('fn-stat', 'Database functions',
    '@DSUM(range,field,criteria)  @DAVG  @DCOUNT  @DMIN  @DMAX  @DVAR  @DSTD|' +
    '|' +
    'range     the database: field names in the first row, records below|' +
    'field     which column to total, counting from 0|' +
    'criteria  a range whose first row names fields and whose other rows hold|' +
    '          the tests (the same criteria /Data Query uses)',
    'm:data query,functions');

  T('menus', 'Using the menus',
    'Press / to open the main menu: Worksheet, Range, Copy, Move, File, Print,|' +
    'Graph, Data, System, Quit.  Line 3 describes the highlighted choice.|' +
    '  Left / Right / Space  move the highlight    Enter  choose it|' +
    '  first letter          choose it at once      Esc    back one level|' +
    '  Ctrl-C                leave the menu|' +
    'Choices that need a range open POINT mode; others ask a question on line 2.|' +
    'Press F1 in a menu for help on the highlighted choice.',
    'm:worksheet,m:range,m:copy,m:move,m:file,m:data,ranges');

  T('m:worksheet', 'Worksheet commands',
    'Global     settings for the whole worksheet: Format, Label-Prefix,|' +
    '           Column-Width, Recalculation, Protection, Zero (hide zeros)|' +
    'Insert     blank Column(s) or Row(s) at the pointer|' +
    'Delete     remove Column(s) or Row(s)|' +
    'Column     Set-Width, Reset-Width, Hide, Display for columns|' +
    'Erase      clear the whole worksheet (asks first)|' +
    'Titles     keep rows and/or columns on the screen while scrolling|' +
    'Status     show the settings      Page  insert a page break row|' +
    'Learn      choose where LEARN records keystrokes (see Recording)|' +
    'Window     split the screen: Horizontal or Vertical at the pointer, Sync or|' +
    '           Unsync scrolling, Clear; F6 moves to the other window',
    'm:worksheet global,m:range,learn');

  T('m:worksheet global', 'Worksheet Global',
    'Format          the default number format for all cells (see Range Format)|' +
    'Label-Prefix    default alignment of new labels|' +
    'Column-Width    the default width, 1 to 240|' +
    'Recalculation   Natural, Columnwise or Rowwise order; Automatic or Manual;|' +
    '                Iteration sets how many passes a circular reference gets|' +
    'Protection      Enable or Disable (kept for compatibility)|' +
    'Default         printer, directory, international formats, clock, undo|' +
    'Zero            choose whether zero values are shown or left blank',
    'm:range format,recalc');

  T('m:worksheet global default', 'Worksheet Global Default',
    'Settings that last: Update saves them in ~/.config/mkspread/mkspread.conf.|' +
    'Printer     Interface, Auto-LF, Left, Right, Top, Bottom, Pg-Length, Wait,|' +
    '            Setup (the starting values of /Print) and Name (the print queue,|' +
    '            used as lp -d)|' +
    'Directory   the folder files are read from and saved in|' +
    'Status      show all the settings         Update  save them|' +
    'Other       International: Punctuation A-H (decimal, thousands, argument|' +
    '            separators), Currency symbol and Prefix/Suffix, Date A-D and Time|' +
    '            A-D (the D4/D5 and D8/D9 formats), Negative Parentheses or Sign|' +
    '            Clock: Standard, International or None     Undo: Enable/Disable|' +
    '            Help and Beep are kept for compatibility',
    'm:worksheet global,m:print')

  ;
  T('m:range', 'Range commands',
    'Format   how numbers look in the range          Label    align labels|' +
    'Erase    clear the range                        Name     give names to ranges|' +
    'Justify  wrap a long label into a paragraph     Prot / Unprot   protection|' +
    'Input    (not implemented)               Value    turn formulas into values|' +
    'Trans    copy a range, swapping rows and columns',
    'm:range format,m:range name,m:copy')

  ;
  T('m:range format', 'Range Format',
    'Fixed      a set number of decimals (Fixed 2: 1234.50)|' +
    'Sci        scientific notation (1.23E+03)|' +
    'Currency   a currency symbol, commas and decimals; negatives in parentheses|' +
    'Comma      thousands separators and decimals; negatives in parentheses|' +
    'General    as many digits as fit (the default)|' +
    '+/-        a bar of + or - signs, one per unit (a quick graph)|' +
    'Percent    multiply by 100 and add a % sign|' +
    'Date       1 DD-MMM-YY   2 DD-MMM   3 MMM-YY   4 and 5 full date, 6-9 times|' +
    'Text       show formulas as typed        Hidden   show nothing|' +
    'Reset      back to the global format|' +
    'Numbers too wide for the column are shown as a row of asterisks.',
    'm:worksheet global,dates')

  ;
  T('m:range name', 'Range Name',
    'Create   name a range (Enter after choosing it)|' +
    'Delete   remove a name         Reset   remove all names|' +
    'Labels   name cells after labels in neighbouring cells (Right, Down, Left, Up)|' +
    'Table    write a list of names and their ranges into the worksheet|' +
    'Names are up to 15 characters, without spaces or operators.  A name made of|' +
    'a backslash and one letter or digit is a macro, run with Alt plus the letter.',
    'ranges,macros')

  ;
  T('m:copy', 'Copy',
    'Copy asks for the range to copy FROM and the place to copy TO.  Relative|' +
    'references in formulas shift to the new place; absolute ones ($A$1) stay.|' +
    'The TO range may be a single cell (the top left corner of the copy) or a|' +
    'larger range, in which case the source is repeated to fill it.',
    'm:move,ranges')

  ;
  T('m:move', 'Move',
    'Move relocates a range.  Formulas that refer to the moved cells follow them,|' +
    'and the moved formulas keep pointing at the same cells.  The old cells are|' +
    'emptied.  Anything in the destination is replaced.',
    'm:copy')

  ;
  T('m:file', 'File commands',
    'Retrieve   load a worksheet (replaces the current one)|' +
    'Save       write the worksheet; Replace or Cancel if the file exists|' +
    'Combine    bring part or all of another file into this one: Copy, Add,|' +
    '           Subtract; Entire-File or a named/specified range|' +
    'Xtract     save a range as a new file: Formulas or Values|' +
    'Erase      delete a file     List   show files     Directory   change folder|' +
    'Import     read a text file: Text (each line a label) or Numbers (columns)|' +
    '|' +
    'The file prompts list the files and folders at once.  Enter picks one, a|' +
    'letter starts typing a name, Esc switches to typing, F3 lists them again.',
    'filefmt,m:quit')

  ;
  T('m:print', 'Print',
    'Printer or File chooses where the text goes (File asks for a name; .PRN is|' +
    'added).  Then:  Range  the cells to print        Line  one blank line|' +
    '  Page   skip to the next page      Align  paper is at the top of a page|' +
    '  Go     print the range            Quit   leave (the text is sent now)|' +
    '  Options  Header, Footer, Margins, Borders, Setup, Pg-Length, Other|' +
    '  Clear    All, Range, Borders or Format (back to the default layout)|' +
    'Output for the printer goes to the print command (lp); set the environment|' +
    'variable MKSPREAD_PRINT_COMMAND to use another, such as lpr -P name.',
    'm:print options,m:print layout,m:file')

  ;
  T('m:print options', 'Print Options',
    'Header / Footer   text for the top and bottom of each page.  Split it with|' +
    '                  | into left, centre and right parts; # is the page number|' +
    '                  and @ today''s date:   Report|Sales|Page #|' +
    'Margins           Left 4, Right 76, Top 2, Bottom 2 (the defaults)|' +
    'Borders           Columns / Rows printed again on every page|' +
    'Setup             printer codes sent first; \015 is the byte with decimal|' +
    '                  code 15, so \027E sends Escape and E|' +
    'Pg-Length         lines per page (default 66)|' +
    'Other             As-Displayed or Cell-Formulas; Formatted or Unformatted|' +
    '                  (Unformatted: no headers, footers or page breaks)',
    'm:print,m:print layout')

  ;
  T('m:print layout', 'How pages are laid out',
    'A page has the top margin, the header, two blank lines, the text (56 lines on|' +
    'a 66-line page), two blank lines, the footer and the bottom margin.  Text is|' +
    'as wide as the right margin minus the left margin: wider ranges are printed in|' +
    'groups of columns, the first group down all the pages, then the next group.|' +
    'In the print range, a row whose first cell is a label starting with the|' +
    'vertical bar prefix is not printed, and one that holds |:: starts a new page|' +
    '(/Worksheet Page puts such a row above the pointer).  Go leaves the last page|' +
    'unfinished; Page finishes it.  The paper position is kept between jobs.',
    'm:print options,m:print')

  ;
  T('m:graph', 'Graph',
    'Graphs are not supported.  The menu is kept so the keystrokes of old macros|' +
    'still line up.  Use Data Distribution, Data Regression and Range Format|' +
    '+/- for simple summaries.',
    'm:data')

  ;
  T('m:data', 'Data commands',
    'Fill          fill a range with a sequence of numbers|' +
    'Table         what-if tables with one or two input cells|' +
    'Sort          rearrange rows by one or two keys|' +
    'Query         find, extract, unique and delete records by criteria|' +
    'Distribution  count how many values fall in each bin|' +
    'Matrix        invert and multiply matrices|' +
    'Regression    least-squares line through the data|' +
    'Parse         split long labels into columns',
    'm:data fill,m:data table,m:data sort,m:data query,m:data distribution,m:data matrix,m:data regression,m:data parse')

  ;
  T('m:data fill', 'Data Fill',
    'Asks for the range, then Start (default 0), Step (1) and Stop (8191).|' +
    'The range is emptied and filled down the first column, then the next, until|' +
    'the stop value is passed.  The values you used become the next defaults.|' +
    'Dates are numbers, so a date start and a step of 1 fill consecutive days.',
    'm:data')

  ;
  T('m:data table', 'Data Table',
    'Table 1  Values go down the first column of the table range, formulas along|' +
    '         the row above them.  You give one input cell; each value is put in|' +
    '         it and the formulas are recalculated into the table.|' +
    'Table 2  One formula in the top left corner, values across the top row and|' +
    '         down the left column.  Input cell 1 takes the left column, input|' +
    '         cell 2 the top row.|' +
    'Reset forgets the table.  F8 runs the last table again.',
    'm:data')

  ;
  T('m:data sort', 'Data Sort',
    'Data-Range   the rows to sort (all the columns, not just the key)|' +
    'Primary-Key  any cell in the key column, then A (up) or D (down)|' +
    'Secondary-Key  breaks ties in the primary key|' +
    'Reset  forget the settings     Go  sort     Quit  leave the menu|' +
    'Order: empty cells, then labels (ignoring case), then numbers; descending|' +
    'is the reverse.  Formulas move with their rows like a Copy.',
    'm:data')

  ;
  T('m:data query', 'Data Query',
    'Input     the database: field names in the first row, records below|' +
    'Criteria  a range: the first row names fields, each row below is an|' +
    '          alternative (OR); the cells within a row must all be true (AND)|' +
    'Output    the field names to extract, with room for records below|' +
    'Find      step through the matching records (FIND mode: Up/Down, Esc)|' +
    'Extract   copy matching records to the output range   Unique  drop duplicates|' +
    'Delete    remove matching records (asks first)        Reset  clear settings|' +
    'Criteria text matches ignoring case; ? and * are wildcards, ~ means not.|' +
    'Give the output range several rows; with only the field names row, every row|' +
    'below it is cleared and used.  F7 repeats the last Query.',
    'm:data,fn-stat')

  ;
  T('m:data distribution', 'Data Distribution',
    'Asks for the values range and the bin range (one column of upper limits).|' +
    'The counts go in the column to the right of the bins: how many values are|' +
    'at most the first bin, then up to the second, and so on.  One extra cell|' +
    'counts the values larger than the last bin.  Text and empty cells are|' +
    'ignored.',
    'm:data')

  ;
  T('m:data matrix', 'Data Matrix',
    'Invert    asks for a square range (at most 90 by 90) and where to put the|' +
    '          inverse.  A matrix that cannot be inverted gives an error.|' +
    'Multiply  asks for two ranges and the output cell; the number of columns|' +
    '          in the first must equal the rows in the second.',
    'm:data')

  ;
  T('m:data regression', 'Data Regression',
    'X-Range  one or more columns of independent values|' +
    'Y-Range  the dependent values (one column of the same length)|' +
    'Output-Range  the top left cell of the report|' +
    'Intercept  Compute (the default) or Zero (force the line through 0)|' +
    'Go  writes the constant, standard error of Y, R squared, number of|' +
    'observations, degrees of freedom, the X coefficients and their errors.',
    'm:data')

  ;
  T('m:data parse', 'Data Parse',
    'Splits long labels (for instance text imported from a file) into cells.|' +
    'A format line is a label with the vertical bar prefix, placed above the text:|' +
    '  L label   V value   D date   T time   S skip   > the rest of the field|' +
    '  * a blank gap|' +
    'Format-Line Create builds one from the label under the pointer; Edit changes|' +
    'it.|' +
    'Input-Column  the column holding the format line and the labels (the first|' +
    'cell must be a format line)   Output-Range  the top left cell for the pieces|' +
    'Go splits every label using the nearest format line above it.',
    'm:data,m:file')

  ;
  T('m:system', 'System',
    'System would leave the program for the operating system and return.|' +
    'It is not available yet; use your terminal for now.',
    'm:quit')

  ;
  T('m:quit', 'Quit',
    'Quit asks No or Yes.  Yes ends the program; unsaved changes are lost, so use|' +
    'File Save first.',
    'm:file')

  ;
  T('filefmt', 'File formats',
    'Native files are .WK1 worksheets (Release 2 compatible).  .WKS files are read|' +
    'and written too.  Text and CSV files come in with File Import and Data Parse.|' +
    'A file given on the command line is opened when the program starts, and the|' +
    'macro named \0 in it runs automatically.|' +
    'Formulas, formats, column widths, range names, titles and cell protection of|' +
    'the usual kinds are kept.  Characters are stored in the original character|' +
    'set and shown as UTF-8.',
    'm:file')

  ;
  T('recovery', 'Recovery and autosave',
    'While a worksheet has unsaved changes mkspread keeps a copy in|' +
    '~/.local/state/mkspread/recover.  A normal exit removes it; if the program,|' +
    'the terminal or the SSH connection dies, the next start asks whether to|' +
    'Recover it, Discard it or decide Later.|' +
    'Autosave (off by default) saves a worksheet that has a file name to that file|' +
    'every N minutes: start with --autosave=N or put autosave = N in|' +
    '~/.config/mkspread/mkspread.conf.  The same file sets recovery = seconds and|' +
    'expand = yes.  Save with /File Save as usual; that also settles the copy.',
    'm:file,filefmt')

  ;
  T('macros', 'Macros',
    'A macro is text in worksheet cells that mkspread types for you.  Name the|' +
    'first cell with /Range Name Create: \A runs with Alt-A; any name runs with|' +
    'Alt-F3.  ~ is Enter and {DOWN}, {EDIT}, {GOTO}... are keys.  Commands such|' +
    'as {IF}, {BRANCH}, {FOR}, {LET}, {GETLABEL}, {MENUBRANCH} give macros logic.|' +
    'The macro runs until a cell that is empty or not text.  Ctrl-Break stops it.|' +
    'See docs/macros.md for the full list of keys and commands.',
    'learn,fkeys')

  ;
  T('learn', 'Recording (LEARN) and STEP',
    '/Worksheet Learn Range chooses where keystrokes are recorded.  Alt-F5 turns|' +
    'recording on and off; the keys you type are written as macro text, starting|' +
    'at the first empty cell of that range.  Name the first cell \A to keep it.|' +
    'Alt-F2 turns STEP on: a macro then waits before every keystroke, showing its|' +
    'line with > at the position.  Any key steps; Alt-F2 again lets it run.',
    'macros')

  ;
  T('recalc', 'Recalculation',
    'Natural   a cell is calculated after the cells it depends on|' +
    'Columnwise / Rowwise   left to right within each column / row|' +
    'Automatic recalculates after every change; Manual waits for F9 (CALC shows).|' +
    'Iteration repeats the calculation a number of times, which a circular|' +
    'reference needs.  Without iteration a cycle shows CIRC.',
    'm:worksheet global,formulas')

  ;
  T('dates', 'Dates and times',
    'Dates are counted in days from 1 January 1900 (day 1).  Format a cell with|' +
    '/Range Format Date to see it as a date.  @DATE(1990,12,25) gives the number;|' +
    'adding 7 gives the same weekday next week.  Times are a fraction of a day,|' +
    'so 0.5 is noon; @NOW is the date plus the time.',
    'fn-date,m:range format')

  ;
  T('undo', 'Undo',
    'Alt-F4 (or Ctrl-U) undoes the last change (one level).  UNDO at the|' +
    'bottom shows when it is available.  Pressing it again redoes the change.|' +
    'Loading a file clears the undo information.',
    'keys')

  ;
  T('errors', 'Error values and messages',
    'ERR   a calculation was impossible (division by zero, a bad argument, a|' +
    '      deleted cell).  It spreads to formulas that use the cell.|' +
    'NA    a value that is not available (@NA, a failed lookup).|' +
    '*****  the number is too wide for the column: widen it with /Worksheet|' +
    '      Column Set-Width or use another format.|' +
    'A message at the bottom of the screen goes away at the next key.',
    'formulas,fn-logic')

  ;
  T('about', 'About mkspread',
    'mkspread is a spreadsheet for the terminal, written in Free Pascal.|' +
    'It follows the look, menus and keystrokes of the classic Release 2|' +
    'spreadsheets so that their users, files and macros feel at home.|' +
    'It is free software under the GNU General Public License, version 3 or later,|' +
    'with no warranty.  It is not connected with the makers of any other product.',
    'basics');
end;

initialization
  Build;
end.
