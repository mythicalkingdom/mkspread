program mkspread;
{ A Lotus 1-2-3 Release 2.x look-alike (screen + menus only).
  Phase 1: every menu command is a stub.
  Usage: mkspread          start with an empty worksheet
         mkspread demo     start with the sample sheet from the screenshot }
{$mode objfpc}{$H+}

uses Crt, SysUtils;

const
  MaxCol   = 256;
  MaxRow   = 8192;
  GridX    = 5;          { first screen column of the worksheet area }
  GridW    = 76;         { characters available for columns }
  GridRows = 20;

  aNorm = $07;           { light grey on black }
  aHi   = $30;           { black on cyan }
  aMsg  = $0E;           { yellow on black }

  kUp = 1072; kDown = 1080; kLeft = 1075; kRight = 1077;
  kHome = 1071; kEnd = 1079; kPgUp = 1073; kPgDn = 1081;
  kF1 = 1059; kF2 = 1060; kF3 = 1061; kF4 = 1062; kF5 = 1063;
  kF6 = 1064; kF7 = 1065; kF8 = 1066; kF9 = 1067; kF10 = 1068;
  kCtrlRight = 1116; kCtrlLeft = 1115; kShiftTab = 1015;
  kEnter = 13; kEsc = 27; kTab = 9;

type
  TNode = record
    Name, Help: string;
    Kids: array of Integer;
  end;
  TCell = record
    R, C: Integer;
    Raw, Cache: string;      { Raw includes label prefix; Cache = computed value }
    Fmt: Integer;            { -1 general, >=0 currency with that many decimals }
  end;
  TMode = (mReady, mLabel, mValue, mMenu, mGoto);

var
  Nodes: array of TNode;
  NodeCnt: Integer;
  Stk: array[0..15] of Integer;

  Cells: array of TCell;
  CellCnt: Integer = 0;
  ColWd: array[1..MaxCol] of Integer;   { 0 = global default }
  GlobalW: Integer = 9;

  CurCol: Integer = 1;
  CurRow: Integer = 1;
  LeftCol: Integer = 1;
  TopRow: Integer = 1;

  Mode: TMode = mReady;
  Entry, Msg: string;
  EndMode: Boolean = False;
  Quitting: Boolean = False;

  MenuStk: array[0..15] of Integer;
  MenuIdx: array[0..15] of Integer;
  MenuDepth: Integer = 0;

{ ------------------------------------------------------------------ menus }

procedure A(d: Integer; const s: string);
var
  p, n: Integer;
begin
  if NodeCnt = Length(Nodes) then SetLength(Nodes, NodeCnt * 2 + 16);
  n := NodeCnt;
  Inc(NodeCnt);
  p := Pos('|', s);
  if p > 0 then
  begin
    Nodes[n].Name := Copy(s, 1, p - 1);
    Nodes[n].Help := Copy(s, p + 1, 999);
  end
  else
  begin
    Nodes[n].Name := s;
    Nodes[n].Help := '';
  end;
  SetLength(Nodes[n].Kids, 0);
  Stk[d] := n;
  with Nodes[Stk[d - 1]] do
  begin
    SetLength(Kids, Length(Kids) + 1);
    Kids[High(Kids)] := n;
  end;
end;

procedure FormatMenu(d: Integer);
begin
  A(d, 'Fixed|Fixed number of decimal places (x.xx)');
  A(d, 'Sci|Exponential format (x.xxE+xx)');
  A(d, 'Currency|Currency format ($x,xxx.xx)');
  A(d, ',|Comma format (x,xxx.xx)');
  A(d, 'General|Standard format (x.xx or x.xxExx)');
  A(d, '+/-|Horizontal bar graph format (+++ or ---)');
  A(d, 'Percent|Percent format (x.xx%)');
  A(d, 'Date|Date and Time formats (all types)');
  A(d + 1, '1|DD-MMM-YY');
  A(d + 1, '2|DD-MMM');
  A(d + 1, '3|MMM-YY');
  A(d + 1, '4|Full International date format');
  A(d + 1, '5|Partial International date format');
  A(d + 1, 'Time|Time formats');
  A(d + 2, '1|HH:MM:SS AM/PM');
  A(d + 2, '2|HH:MM AM/PM');
  A(d + 2, '3|Full International time format');
  A(d + 2, '4|Partial International time format');
  A(d, 'Text|Display the formula in the cell, not its value');
  A(d, 'Hidden|Do not display the contents of the cell');
end;

procedure LabelMenu(d: Integer);
begin
  A(d, 'Left|Left-align labels');
  A(d, 'Right|Right-align labels');
  A(d, 'Center|Center labels');
end;

procedure PrintMenu(d: Integer);
begin
  A(d, 'Range|Specify a print range');
  A(d, 'Line|Advance paper one line');
  A(d, 'Page|Advance paper to top of next page');
  A(d, 'Options|Specify headers, footers, margins, borders, setup string');
  A(d + 1, 'Header|Create a header');
  A(d + 1, 'Footer|Create a footer');
  A(d + 1, 'Margins|Change margins');
  A(d + 2, 'Left|Set left margin');
  A(d + 2, 'Right|Set right margin');
  A(d + 2, 'Top|Set top margin');
  A(d + 2, 'Bottom|Set bottom margin');
  A(d + 1, 'Borders|Print specified columns or rows on each page');
  A(d + 2, 'Columns|Specify border columns');
  A(d + 2, 'Rows|Specify border rows');
  A(d + 1, 'Setup|Enter a printer setup string');
  A(d + 1, 'Pg-Length|Set the number of lines per page');
  A(d + 1, 'Other|Specify how to print the data');
  A(d + 2, 'As-Displayed|Print the range as it appears on the screen');
  A(d + 2, 'Cell-Formulas|Print each cell''s contents, one per line');
  A(d + 2, 'Formatted|Print headers, footers and page breaks');
  A(d + 2, 'Unformatted|Do not print headers, footers or page breaks');
  A(d + 1, 'Quit|Return to the previous menu');
  A(d, 'Clear|Reset some or all print options');
  A(d + 1, 'All|Cancel all print settings');
  A(d + 1, 'Range|Cancel the print range');
  A(d + 1, 'Borders|Cancel border columns and rows');
  A(d + 1, 'Format|Restore default margins, page length and setup');
  A(d, 'Align|Tell 1-2-3 the paper is at the top of a page');
  A(d, 'Go|Print the specified range');
  A(d, 'Quit|Return to READY mode');
end;

procedure DataRangeMenu(d: Integer);
var
  c: Char;
begin
  for c := 'A' to 'F' do
    A(d, c + '|Specify the ' + c + ' data range');
end;

procedure BuildMenus;
var
  c: Char;
begin
  SetLength(Nodes, 128);
  NodeCnt := 1;                       { node 0 is the root }
  Nodes[0].Name := '';
  Nodes[0].Help := '';
  SetLength(Nodes[0].Kids, 0);
  Stk[0] := 0;

  { ---- Worksheet ---- }
  A(1, 'Worksheet');
  A(2, 'Global|Set worksheet-wide options');
  A(3, 'Format|Set the global cell display format');
  FormatMenu(4);
  A(3, 'Label-Prefix|Set the global label alignment');
  LabelMenu(4);
  A(3, 'Column-Width|Set the width for all columns');
  A(3, 'Recalculation|Set recalculation order and method');
  A(4, 'Natural|Recalculate cells that others depend on first');
  A(4, 'Columnwise|Recalculate column by column');
  A(4, 'Rowwise|Recalculate row by row');
  A(4, 'Automatic|Recalculate every time entries change');
  A(4, 'Manual|Recalculate only when F9 (CALC) is pressed');
  A(4, 'Iteration|Specify the number of recalculation passes');
  A(3, 'Protection|Turn worksheet protection on or off');
  A(4, 'Enable|Turn worksheet protection on');
  A(4, 'Disable|Turn worksheet protection off');
  A(3, 'Default|Set default printer, directory and other options');
  A(4, 'Printer|Specify printer interface and default settings');
  A(4, 'Directory|Specify the default directory');
  A(4, 'Status|Display the current default settings');
  A(4, 'Update|Save the current default settings');
  A(4, 'Other|International, Help, Clock, Undo, Beep');
  A(4, 'Quit|Return to READY mode');
  A(3, 'Zero|Display or suppress zero values');
  A(4, 'No|Display zero values normally');
  A(4, 'Yes|Do not display zero values');
  A(2, 'Insert|Insert blank columns or rows');
  A(3, 'Column|Insert blank columns to the left of the cell pointer');
  A(3, 'Row|Insert blank rows above the cell pointer');
  A(2, 'Delete|Delete entire columns or rows');
  A(3, 'Column|Delete columns');
  A(3, 'Row|Delete rows');
  A(2, 'Column|Set or reset the width of columns');
  A(3, 'Set-Width|Specify the width of the current column');
  A(3, 'Reset-Width|Return the current column to the global width');
  A(3, 'Hide|Hide a range of columns');
  A(3, 'Display|Redisplay a range of hidden columns');
  A(2, 'Erase|Erase the entire worksheet from memory');
  A(3, 'No|Do not erase the worksheet; return to READY mode');
  A(3, 'Yes|Erase the entire worksheet and reset all settings');
  A(2, 'Titles|Freeze rows and columns as titles');
  A(3, 'Both|Freeze all rows above and columns to the left of the cell pointer');
  A(3, 'Horizontal|Freeze all rows above the cell pointer');
  A(3, 'Vertical|Freeze all columns to the left of the cell pointer');
  A(3, 'Clear|Unfreeze all title rows and columns');
  A(2, 'Window|Split the screen into two windows');
  A(3, 'Horizontal|Split the screen horizontally at the current row');
  A(3, 'Vertical|Split the screen vertically at the current column');
  A(3, 'Sync|Synchronize scrolling in the two windows');
  A(3, 'Unsync|Scroll the two windows independently');
  A(3, 'Clear|Return to a single full-screen window');
  A(2, 'Status|Display the current global settings');
  A(2, 'Page|Insert a page-break row above the cell pointer');

  { ---- Range ---- }
  A(1, 'Range');
  A(2, 'Format|Set the display format of a range');
  FormatMenu(3);
  A(3, 'Reset|Return the range to the global format');
  A(2, 'Label|Set label alignment for a range');
  LabelMenu(3);
  A(2, 'Erase|Erase a cell or range of cells');
  A(2, 'Name|Create, delete or modify range names');
  A(3, 'Create|Create or modify a range name');
  A(3, 'Delete|Delete a range name');
  A(3, 'Labels|Create range names from adjacent labels');
  A(4, 'Right|Name the cell to the right of each label');
  A(4, 'Down|Name the cell below each label');
  A(4, 'Left|Name the cell to the left of each label');
  A(4, 'Up|Name the cell above each label');
  A(3, 'Reset|Delete all range names');
  A(3, 'Table|Create a table of range names in the worksheet');
  A(2, 'Justify|Adjust a long label to fit a specified range');
  A(2, 'Prot|Prevent changes to a range when protection is on');
  A(2, 'Unprot|Allow changes to a range when protection is on');
  A(2, 'Input|Restrict the cell pointer to unprotected cells in a range');
  A(2, 'Value|Copy a range, converting formulas to values');
  A(2, 'Trans|Copy a range, switching columns and rows');

  { ---- Copy / Move ---- }
  A(1, 'Copy|Copy a cell or range of cells');
  A(1, 'Move|Move a cell or range of cells');

  { ---- File ---- }
  A(1, 'File');
  A(2, 'Retrieve|Erase the worksheet and display a file from disk');
  A(2, 'Save|Store the entire worksheet in a file on disk');
  A(2, 'Combine|Incorporate part or all of a file into the worksheet');
  for c := 'C' to 'E' do
  begin
    case c of
      'C': A(3, 'Copy|Copy data from a file over the current data');
      'D': A(3, 'Add|Add values from a file to values in the worksheet');
      'E': A(3, 'Subtract|Subtract values in a file from the worksheet');
    end;
    A(4, 'Entire-File|Combine the entire file');
    A(4, 'Named/Specified-Range|Combine a named or specified range');
  end;
  A(2, 'Xtract|Save part of the worksheet in a file');
  A(3, 'Formulas|Save data in the range as formulas');
  A(3, 'Values|Save data in the range as values');
  A(2, 'Erase|Erase a file from disk');
  A(3, 'Worksheet|Erase a worksheet file');
  A(3, 'Print|Erase a print file');
  A(3, 'Graph|Erase a graph file');
  A(3, 'Other|Erase any other file');
  A(2, 'List|Display the names of files in the current directory');
  A(3, 'Worksheet|List worksheet files');
  A(3, 'Print|List print files');
  A(3, 'Graph|List graph files');
  A(3, 'Other|List all files');
  A(2, 'Import|Read text or numbers from a text file');
  A(3, 'Text|Import each line as a long label');
  A(3, 'Numbers|Import numbers as values and text as labels');
  A(2, 'Directory|Display and change the current directory');

  { ---- Print ---- }
  A(1, 'Print');
  A(2, 'Printer|Send output directly to a printer');
  PrintMenu(3);
  A(2, 'File|Send output to a text file');
  PrintMenu(3);

  { ---- Graph ---- }
  A(1, 'Graph');
  A(2, 'Type|Select the type of graph');
  A(3, 'Line|Line graph');
  A(3, 'Bar|Bar graph');
  A(3, 'XY|XY graph');
  A(3, 'Stack-Bar|Stacked bar graph');
  A(3, 'Pie|Pie chart');
  A(2, 'X|Specify the X-axis data range');
  DataRangeMenu(2);
  A(2, 'Reset|Cancel graph settings');
  A(3, 'Graph|Cancel all graph settings');
  A(3, 'X|Cancel the X data range');
  DataRangeMenu(3);
  A(3, 'Quit|Return to the previous menu');
  A(2, 'View|Display the current graph');
  A(2, 'Save|Save the graph in a file for printing');
  A(2, 'Options|Set legends, titles, grid, scale and other options');
  A(3, 'Legend|Create legends for data ranges');
  DataRangeMenu(4);
  A(4, 'Range|Specify a range of legends');
  A(3, 'Format|Set lines and/or symbols for data ranges');
  A(4, 'Graph|Apply to all data ranges');
  DataRangeMenu(4);
  A(4, 'Quit|Return to the previous menu');
  A(3, 'Titles|Create graph titles');
  A(4, 'First|Enter the first line of the graph title');
  A(4, 'Second|Enter the second line of the graph title');
  A(4, 'X-Axis|Enter the X-axis title');
  A(4, 'Y-Axis|Enter the Y-axis title');
  A(3, 'Grid|Draw grid lines');
  A(4, 'Horizontal|Draw horizontal grid lines');
  A(4, 'Vertical|Draw vertical grid lines');
  A(4, 'Both|Draw both horizontal and vertical grid lines');
  A(4, 'Clear|Remove grid lines');
  A(3, 'Scale|Set axis scaling');
  A(4, 'Y-Scale|Set scaling for the Y axis');
  A(4, 'X-Scale|Set scaling for the X axis');
  A(4, 'Skip|Display every nth label on the X axis');
  A(3, 'Color|Display the graph in color');
  A(3, 'B&W|Display the graph in black and white');
  A(3, 'Data-Labels|Label data points with worksheet values');
  A(4, 'A|Label points in the A range');
  A(4, 'B|Label points in the B range');
  A(4, 'C|Label points in the C range');
  A(4, 'D|Label points in the D range');
  A(4, 'E|Label points in the E range');
  A(4, 'F|Label points in the F range');
  A(4, 'Group|Label all data ranges');
  A(4, 'Quit|Return to the previous menu');
  A(3, 'Quit|Return to the previous menu');
  A(2, 'Name|Create, use or delete named graphs');
  A(3, 'Use|Make a named graph current');
  A(3, 'Create|Name the current graph');
  A(3, 'Delete|Delete a named graph');
  A(3, 'Reset|Delete all named graphs');
  A(2, 'Quit|Return to READY mode');

  { ---- Data ---- }
  A(1, 'Data');
  A(2, 'Fill|Fill a range with a sequence of values');
  A(2, 'Table|Create a table of values for one or two variables');
  A(3, '1|Create a table using one input cell');
  A(3, '2|Create a table using two input cells');
  A(3, 'Reset|Cancel table settings');
  A(2, 'Sort|Sort database records');
  A(3, 'Data-Range|Specify the range to sort');
  A(3, 'Primary-Key|Specify the primary sort key');
  A(3, 'Secondary-Key|Specify the secondary sort key');
  A(3, 'Reset|Cancel sort settings');
  A(3, 'Go|Sort the data');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Query|Find or edit records that match given criteria');
  A(3, 'Input|Specify the input range');
  A(3, 'Criteria|Specify the criteria range');
  A(3, 'Output|Specify the output range');
  A(3, 'Find|Highlight each matching record');
  A(3, 'Extract|Copy matching records to the output range');
  A(3, 'Unique|Copy unique matching records to the output range');
  A(3, 'Delete|Delete matching records from the input range');
  A(3, 'Reset|Cancel query settings');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Distribution|Create a frequency distribution');
  A(2, 'Matrix|Invert or multiply matrices');
  A(3, 'Invert|Invert a matrix');
  A(3, 'Multiply|Multiply two matrices');
  A(2, 'Regression|Calculate a linear regression');
  A(3, 'X-Range|Specify the independent variables');
  A(3, 'Y-Range|Specify the dependent variable');
  A(3, 'Output-Range|Specify where to put the results');
  A(3, 'Intercept|Compute or force the intercept to zero');
  A(4, 'Compute|Calculate the intercept');
  A(4, 'Zero|Force the intercept to zero');
  A(3, 'Reset|Cancel regression settings');
  A(3, 'Go|Calculate the regression');
  A(3, 'Quit|Return to READY mode');
  A(2, 'Parse|Convert a column of long labels into separate cells');
  A(3, 'Format-Line|Create or edit a format line');
  A(3, 'Input-Column|Specify the column of labels to parse');
  A(3, 'Output-Range|Specify where to put the parsed data');
  A(3, 'Reset|Cancel parse settings');
  A(3, 'Go|Parse the labels');
  A(3, 'Quit|Return to READY mode');

  { ---- System / Quit ---- }
  A(1, 'System|Leave 1-2-3 temporarily and use the operating system');
  A(1, 'Quit|End the 1-2-3 session');
  A(2, 'No|Do not end the 1-2-3 session; return to READY mode');
  A(2, 'Yes|End the 1-2-3 session (Answer Yes only if you have saved your work)');
end;

{ ------------------------------------------------------------------ cells }

function FindCell(r, c: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to CellCnt - 1 do
    if (Cells[i].R = r) and (Cells[i].C = c) then exit(i);
  Result := -1;
end;

function SetCell(r, c: Integer; const raw: string): Integer;
begin
  Result := FindCell(r, c);
  if Result < 0 then
  begin
    if CellCnt = Length(Cells) then SetLength(Cells, CellCnt * 2 + 64);
    Result := CellCnt;
    Inc(CellCnt);
    Cells[Result].R := r;
    Cells[Result].C := c;
    Cells[Result].Fmt := -1;
  end;
  Cells[Result].Raw := raw;
  Cells[Result].Cache := '';
end;

function ColW(c: Integer): Integer;
begin
  if ColWd[c] = 0 then Result := GlobalW else Result := ColWd[c];
end;

function ColLetter(c: Integer): string;
begin
  if c <= 26 then
    Result := Chr(64 + c)
  else
    Result := Chr(64 + (c - 1) div 26) + Chr(65 + (c - 1) mod 26);
end;

function ParseAddr(const s: string; out c, r: Integer): Boolean;
var
  i: Integer;
  u: string;
begin
  u := UpperCase(Trim(s));
  c := 0;
  i := 1;
  while (i <= Length(u)) and (u[i] in ['A'..'Z']) do
  begin
    c := c * 26 + Ord(u[i]) - 64;
    Inc(i);
  end;
  Result := (i > 1) and (i <= Length(u)) and (i <= 3) and (c <= MaxCol);
  if not Result then exit;
  r := StrToIntDef(Copy(u, i, 9), 0);
  Result := (r >= 1) and (r <= MaxRow);
end;

function ValueText(i: Integer): string;
var
  s, ip, fp: string;
  d: Double;
  code, k: Integer;
  neg: Boolean;
begin
  s := Cells[i].Cache;
  if s = '' then s := Cells[i].Raw;
  if (s = '') or (s[1] in ['$', '%', '&']) then exit(s);
  Val(s, d, code);
  if code <> 0 then exit(s);
  if Cells[i].Fmt >= 0 then
  begin
    neg := d < 0;
    Str(Abs(d):0:Cells[i].Fmt, s);
    k := Pos('.', s);
    if k > 0 then
    begin
      ip := Copy(s, 1, k - 1);
      fp := Copy(s, k, 99);
    end
    else
    begin
      ip := s;
      fp := '';
    end;
    k := Length(ip) - 2;
    while k > 1 do
    begin
      Insert(',', ip, k);
      Dec(k, 3);
    end;
    s := '$' + ip + fp;
    if neg then s := '(' + s + ')';
    Result := s;
  end
  else
  begin
    Str(d:0:9, s);
    if Pos('.', s) > 0 then
    begin
      while s[Length(s)] = '0' do Delete(s, Length(s), 1);
      if s[Length(s)] = '.' then Delete(s, Length(s), 1);
    end;
    Result := s;
  end;
end;

procedure LoadDemo;
  procedure L(r, c: Integer; const s: string);
  begin
    SetCell(r, c, s);
  end;
  procedure V(r, c: Integer; const s: string; const cache: string);
  var
    i: Integer;
  begin
    i := SetCell(r, c, s);
    Cells[i].Fmt := 2;
    Cells[i].Cache := cache;
  end;
begin
  ColWd[10] := 1;
  ColWd[11] := 23;
  ColWd[14] := 24;
  L(1, 11, '''     Variable Costs/Unit');
  L(1, 14, '''          Fixed Costs');
  L(2, 11, '''Description');
  L(2, 12, '"Cost/Unit');
  L(2, 14, '''Description');
  L(3, 11, '\=');
  L(3, 12, '\=');
  L(3, 14, '\=');
  L(4, 11, '''Materials');       V(4, 12, '3.26', '');
  L(5, 11, '''Contract Labor');  V(5, 12, '3.75', '');
  L(6, 11, '''Energy');          V(6, 12, '1.45', '');
  L(7, 11, '''Sales Commissions'); V(7, 12, '2.21', '');
  L(8, 11, '''Freight');         V(8, 12, '0.32', '');
  L(9, 12, '\-');
  L(10, 11, '''Total');          V(10, 12, '@SUM(L4:L8)', '10.99');
  L(4, 14, '''Plant Operation');
  L(5, 14, '''Salaries');
  L(6, 14, '''Administration');
  L(7, 14, '''Sales & Marketing');
  L(8, 14, '''Research & Development');
  CurCol := 11; CurRow := 4; LeftCol := 10; TopRow := 1;
end;

{ ------------------------------------------------------------------ view }

function RightColOf(left: Integer): Integer;
var
  w, c: Integer;
begin
  c := left;
  w := ColW(c);
  while (c < MaxCol) and (w + ColW(c + 1) <= GridW) do
  begin
    Inc(c);
    Inc(w, ColW(c));
  end;
  Result := c;
end;

procedure Normalize;
begin
  if CurCol < 1 then CurCol := 1;
  if CurCol > MaxCol then CurCol := MaxCol;
  if CurRow < 1 then CurRow := 1;
  if CurRow > MaxRow then CurRow := MaxRow;
  if CurCol < LeftCol then LeftCol := CurCol;
  while (LeftCol < CurCol) and (RightColOf(LeftCol) < CurCol) do Inc(LeftCol);
  if CurRow < TopRow then TopRow := CurRow;
  if CurRow > TopRow + GridRows - 1 then TopRow := CurRow - GridRows + 1;
  if TopRow < 1 then TopRow := 1;
  if TopRow > MaxRow - GridRows + 1 then TopRow := MaxRow - GridRows + 1;
end;

procedure Put(x, y: Integer; attr: Byte; const s: string);
begin
  if s = '' then exit;
  GotoXY(x, y);
  TextAttr := attr;
  Write(s);
end;

function PadR(const s: string; n: Integer): string;
begin
  if Length(s) >= n then Result := Copy(s, 1, n)
  else Result := s + StringOfChar(' ', n - Length(s));
end;

procedure DrawRow(r, y, rc: Integer);
var
  buf, t: string;
  c, c2, x, w, i, k, av, hx, hw: Integer;
  pre: Char;

  procedure PutBuf(pos: Integer; const s: string);
  var
    j: Integer;
  begin
    for j := 1 to Length(s) do
      if (pos + j - 1 >= 1) and (pos + j - 1 <= GridW) then
        buf[pos + j - 1] := s[j];
  end;

begin
  buf := StringOfChar(' ', GridW);
  hx := 0; hw := 0;
  x := 1;
  for c := LeftCol to rc do
  begin
    w := ColW(c);
    if (r = CurRow) and (c = CurCol) then
    begin
      hx := x;
      hw := w;
    end;
    i := FindCell(r, c);
    if i >= 0 then
    begin
      if Cells[i].Raw = '' then
        t := ''
      else if (Cells[i].Raw[1] in ['''', '"', '^', '\']) then
      begin
        { label }
        pre := Cells[i].Raw[1];
        t := Copy(Cells[i].Raw, 2, 999);
        case pre of
          '''':
            begin
              av := w;
              c2 := c + 1;
              while (c2 <= rc) and (FindCell(r, c2) < 0) do
              begin
                Inc(av, ColW(c2));
                Inc(c2);
              end;
              PutBuf(x, Copy(t, 1, av));
            end;
          '"':
            begin
              t := Copy(t, 1, w);
              PutBuf(x + w - Length(t), t);
            end;
          '^':
            begin
              t := Copy(t, 1, w);
              PutBuf(x + (w - Length(t)) div 2, t);
            end;
          '\':
            if t <> '' then
              for k := 1 to w do
                buf[x + k - 1] := t[((k - 1) mod Length(t)) + 1];
        end;
      end
      else
      begin
        { value }
        t := ValueText(i);
        if Length(t) > w then t := StringOfChar('*', w);
        PutBuf(x + w - Length(t), t);
      end;
    end;
    Inc(x, w);
  end;
  Put(GridX, y, aNorm, buf);
  if hw > 0 then Put(GridX + hx - 1, y, aHi, Copy(buf, hx, hw));
end;

procedure DrawMenu;
var
  d, i, x, n, kid: Integer;
  s: string;
begin
  d := MenuDepth;
  n := Length(Nodes[MenuStk[d]].Kids);
  x := 1;
  for i := 0 to n - 1 do
  begin
    kid := Nodes[MenuStk[d]].Kids[i];
    s := Nodes[kid].Name;
    if x + Length(s) > 80 then break;
    if i = MenuIdx[d] then Put(x, 2, aHi, s) else Put(x, 2, aNorm, s);
    Inc(x, Length(s) + 2);
  end;
  kid := Nodes[MenuStk[d]].Kids[MenuIdx[d]];
  if Length(Nodes[kid].Kids) > 0 then
  begin
    s := '';
    for i := 0 to High(Nodes[kid].Kids) do
    begin
      if i > 0 then s := s + ', ';
      s := s + Nodes[Nodes[kid].Kids[i]].Name;
    end;
  end
  else
    s := Nodes[kid].Help;
  Put(1, 3, aNorm, Copy(s, 1, 80));
end;

procedure Redraw;
var
  s, mname, es: string;
  i, c, x, w, rc, r, cx: Integer;
begin
  Normalize;
  CursorOff;
  rc := RightColOf(LeftCol);

  { line 1: cell status + mode indicator }
  s := ColLetter(CurCol) + IntToStr(CurRow) + ':';
  i := FindCell(CurRow, CurCol);
  if (i >= 0) and (Cells[i].Fmt >= 0) then s := s + ' (C' + IntToStr(Cells[i].Fmt) + ')';
  if ColWd[CurCol] <> 0 then s := s + ' [W' + IntToStr(ColWd[CurCol]) + ']';
  if i >= 0 then s := s + ' ' + Cells[i].Raw;
  case Mode of
    mReady: mname := 'READY';
    mLabel: mname := 'LABEL';
    mValue: mname := 'VALUE';
    mMenu:  mname := 'MENU';
    mGoto:  mname := 'POINT';
  end;
  Put(1, 1, aNorm, PadR(s, 80 - Length(mname) - 1));
  Put(81 - Length(mname), 1, aHi, mname);

  { lines 2-3: control panel }
  Put(1, 2, aNorm, StringOfChar(' ', 80));
  Put(1, 3, aNorm, StringOfChar(' ', 80));
  cx := 0;
  case Mode of
    mMenu: DrawMenu;
    mLabel, mValue:
      begin
        es := Entry;
        if (Mode = mLabel) and (Entry <> '') and not (Entry[1] in ['''', '"', '^', '\']) then
          es := '''' + Entry
        else if (Mode = mLabel) and (Entry = '') then
          es := '''';
        if Length(es) > 79 then es := Copy(es, Length(es) - 78, 79);
        Put(1, 2, aNorm, es);
        cx := Length(es) + 1;
      end;
    mGoto:
      begin
        es := 'Enter address to go to: ' + Entry;
        Put(1, 2, aNorm, es);
        cx := Length(es) + 1;
      end;
  end;

  { line 4: column letters }
  Put(1, 4, aHi, StringOfChar(' ', 80));
  x := GridX;
  for c := LeftCol to rc do
  begin
    w := ColW(c);
    s := ColLetter(c);
    Put(x + (w - Length(s)) div 2, 4, aHi, s);
    Inc(x, w);
  end;

  { lines 5-24: rows }
  for r := TopRow to TopRow + GridRows - 1 do
  begin
    Put(1, 5 + r - TopRow, aHi, PadR(IntToStr(r), 4));
    DrawRow(r, 5 + r - TopRow, rc);
  end;

  { line 25: clock, stub message, indicators (never touch column 80) }
  Put(1, 25, aNorm, StringOfChar(' ', 79));
  Put(1, 25, aNorm, UpperCase(FormatDateTime('dd-mmm-yy hh:nn AM/PM', Now)));
  if Msg <> '' then Put(23, 25, aMsg, Copy(Msg, 1, 55));
  if EndMode then Put(75, 25, aNorm, 'END');

  if cx > 0 then
  begin
    if cx > 80 then cx := 80;
    GotoXY(cx, 2);
    TextAttr := aNorm;
    CursorOn;
  end;
end;

{ ------------------------------------------------------------------ input }

function GetKey: Integer;
var
  c: Char;
begin
  c := ReadKey;
  if c = #0 then Result := 1000 + Ord(ReadKey) else Result := Ord(c);
end;

procedure MoveCur(dr, dc: Integer);
begin
  Inc(CurRow, dr);
  Inc(CurCol, dc);
  Normalize;
end;

function NE(r, c: Integer): Boolean;
begin
  Result := FindCell(r, c) >= 0;
end;

function InB(r, c: Integer): Boolean;
begin
  Result := (r >= 1) and (r <= MaxRow) and (c >= 1) and (c <= MaxCol);
end;

procedure EndJump(dr, dc: Integer);
var
  r, c: Integer;
begin
  r := CurRow; c := CurCol;
  if InB(r + dr, c + dc) and NE(r, c) and NE(r + dr, c + dc) then
  begin
    while InB(r + dr, c + dc) and NE(r + dr, c + dc) do
    begin
      Inc(r, dr); Inc(c, dc);
    end;
  end
  else
  begin
    while InB(r + dr, c + dc) do
    begin
      Inc(r, dr); Inc(c, dc);
      if NE(r, c) then break;
    end;
  end;
  CurRow := r; CurCol := c;
  Normalize;
end;

procedure GoUsedEnd;
var
  i, mr, mc: Integer;
begin
  mr := 1; mc := 1;
  for i := 0 to CellCnt - 1 do
  begin
    if Cells[i].R > mr then mr := Cells[i].R;
    if Cells[i].C > mc then mc := Cells[i].C;
  end;
  CurRow := mr; CurCol := mc;
  Normalize;
end;

procedure BigRight;
var
  rc, off: Integer;
begin
  rc := RightColOf(LeftCol);
  if rc >= MaxCol then exit;
  off := CurCol - LeftCol;
  LeftCol := rc + 1;
  CurCol := LeftCol + off;
  if CurCol > RightColOf(LeftCol) then CurCol := RightColOf(LeftCol);
  Normalize;
end;

procedure BigLeft;
var
  nl, w, off: Integer;
begin
  if LeftCol <= 1 then begin CurCol := 1; exit; end;
  nl := LeftCol; w := 0;
  while (nl > 1) and (w + ColW(nl - 1) <= GridW) do
  begin
    Dec(nl);
    Inc(w, ColW(nl));
  end;
  if nl = LeftCol then Dec(nl);
  off := CurCol - LeftCol;
  LeftCol := nl;
  CurCol := nl + off;
  if CurCol > RightColOf(nl) then CurCol := RightColOf(nl);
  Normalize;
end;

procedure OpenMenu;
begin
  Mode := mMenu;
  MenuDepth := 0;
  MenuStk[0] := 0;
  MenuIdx[0] := 0;
end;

procedure StubKey(const name: string);
begin
  Msg := '[stub] ' + name + ' not implemented';
end;

procedure DoReady(k: Integer);
var
  em: Boolean;
begin
  if k = kEnd then
  begin
    EndMode := not EndMode;
    exit;
  end;
  em := EndMode;
  EndMode := False;
  if (k = Ord('/')) or (k = Ord('<')) then begin OpenMenu; exit; end;
  case k of
    kUp:    if em then EndJump(-1, 0) else MoveCur(-1, 0);
    kDown:  if em then EndJump(1, 0) else MoveCur(1, 0);
    kLeft:  if em then EndJump(0, -1) else MoveCur(0, -1);
    kRight: if em then EndJump(0, 1) else MoveCur(0, 1);
    kHome:
      if em then GoUsedEnd
      else begin CurCol := 1; CurRow := 1; LeftCol := 1; TopRow := 1; end;
    kPgUp:
      begin
        Dec(CurRow, GridRows); Dec(TopRow, GridRows);
        if CurRow < 1 then CurRow := 1;
        if TopRow < 1 then TopRow := 1;
        Normalize;
      end;
    kPgDn:
      begin
        Inc(CurRow, GridRows); Inc(TopRow, GridRows);
        Normalize;
      end;
    kTab, kCtrlRight: BigRight;
    kShiftTab, kCtrlLeft: BigLeft;
    kF1: StubKey('F1 (HELP)');
    kF2: StubKey('F2 (EDIT)');
    kF3: StubKey('F3 (NAME)');
    kF4: StubKey('F4 (ABS)');
    kF5: begin Mode := mGoto; Entry := ''; end;
    kF6: StubKey('F6 (WINDOW)');
    kF7: StubKey('F7 (QUERY)');
    kF8: StubKey('F8 (TABLE)');
    kF9: StubKey('F9 (CALC)');
    kF10: StubKey('F10 (GRAPH)');
    32..126:
      begin
        if Chr(k) in ['0'..'9', '+', '-', '.', '@', '(', '#', '$'] then
          Mode := mValue
        else
          Mode := mLabel;
        Entry := Chr(k);
      end;
  end;
end;

procedure Commit;
var
  raw: string;
begin
  if Entry <> '' then
  begin
    raw := Entry;
    if (Mode = mLabel) and not (raw[1] in ['''', '"', '^', '\']) then
      raw := '''' + raw;
    SetCell(CurRow, CurCol, raw);
  end;
  Mode := mReady;
end;

procedure DoEntry(k: Integer);
begin
  case k of
    kEnter: Commit;
    kEsc: begin Mode := mReady; Entry := ''; end;
    8, 127: if Entry <> '' then Delete(Entry, Length(Entry), 1);
    kUp:    begin Commit; MoveCur(-1, 0); end;
    kDown:  begin Commit; MoveCur(1, 0); end;
    kLeft:  begin Commit; MoveCur(0, -1); end;
    kRight: begin Commit; MoveCur(0, 1); end;
    kPgUp, kPgDn, kHome, kTab, kShiftTab:
      begin
        Commit;
        DoReady(k);
      end;
    32..126, 128..255:
      if Length(Entry) < 240 then Entry := Entry + Chr(k);
  end;
end;

procedure DoGoto(k: Integer);
var
  c, r: Integer;
begin
  case k of
    kEnter:
      begin
        if ParseAddr(Entry, c, r) then
        begin
          CurCol := c; CurRow := r;
          Mode := mReady;
        end
        else
        begin
          Mode := mReady;
          Msg := 'Invalid cell or range address';
        end;
      end;
    kEsc: Mode := mReady;
    8, 127: if Entry <> '' then Delete(Entry, Length(Entry), 1);
    32..126: if Length(Entry) < 12 then Entry := Entry + Chr(k);
  end;
end;

procedure SelectItem(i: Integer);
var
  d, kid, j: Integer;
  path: string;
begin
  d := MenuDepth;
  MenuIdx[d] := i;
  kid := Nodes[MenuStk[d]].Kids[i];
  if Length(Nodes[kid].Kids) > 0 then
  begin
    Inc(MenuDepth);
    MenuStk[MenuDepth] := kid;
    MenuIdx[MenuDepth] := 0;
    exit;
  end;
  path := '';
  for j := 0 to d do
    path := path + ' ' + Nodes[Nodes[MenuStk[j]].Kids[MenuIdx[j]]].Name;
  Mode := mReady;
  if path = ' Quit Yes' then Quitting := True
  else if path = ' Quit No' then { nothing }
  else Msg := '[stub] /' + Trim(path);
end;

procedure DoMenu(k: Integer);
var
  d, n, i: Integer;
begin
  d := MenuDepth;
  n := Length(Nodes[MenuStk[d]].Kids);
  case k of
    kRight, 32: MenuIdx[d] := (MenuIdx[d] + 1) mod n;
    kLeft: MenuIdx[d] := (MenuIdx[d] + n - 1) mod n;
    kHome: MenuIdx[d] := 0;
    kEnd: MenuIdx[d] := n - 1;
    kEnter: SelectItem(MenuIdx[d]);
    kEsc, 8, 127: if d = 0 then Mode := mReady else Dec(MenuDepth);
    3: Mode := mReady;
    33..126:
      for i := 0 to n - 1 do
        if UpCase(Nodes[Nodes[MenuStk[d]].Kids[i]].Name[1]) = UpCase(Chr(k)) then
        begin
          SelectItem(i);
          break;
        end;
  end;
end;

{ ------------------------------------------------------------------ main }

var
  k: Integer;

begin
  if (ScreenWidth < 80) or (ScreenHeight < 25) then
  begin
    WriteLn('mkspread needs a terminal of at least 80x25 (this one is ',
            ScreenWidth, 'x', ScreenHeight, ').');
    Halt(1);
  end;
  CheckBreak := False;
  FillChar(ColWd, SizeOf(ColWd), 0);
  BuildMenus;
  if (ParamCount > 0) and (LowerCase(ParamStr(1)) = 'demo') then LoadDemo;

  TextAttr := aNorm;
  ClrScr;
  repeat
    Redraw;
    k := GetKey;
    Msg := '';
    case Mode of
      mReady: DoReady(k);
      mLabel, mValue: DoEntry(k);
      mMenu: DoMenu(k);
      mGoto: DoGoto(k);
    end;
  until Quitting;

  TextAttr := aNorm;
  ClrScr;
  CursorOn;
end.
