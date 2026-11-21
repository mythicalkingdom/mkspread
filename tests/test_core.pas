{ Unit tests for the terminal-independent core: storage, formatting, menus,
  key queue and the controller driven purely by logical keys. }
program test_core;
{$mode objfpc}{$H+}

uses SysUtils, keys, formula, sheet, cellfmt, dates, menutree, menudata, session, commands, controller;

var
  Fails, Total: Integer;

procedure Check(cond: Boolean; const what: string);
begin
  Inc(Total);
  if not cond then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what);
  end;
end;

procedure CheckStr(const got, want, what: string);
begin
  Inc(Total);
  if got <> want then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what, ': got "', got, '" want "', want, '"');
  end;
end;

procedure CheckInt(got, want: Integer; const what: string);
begin
  Inc(Total);
  if got <> want then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what, ': got ', got, ' want ', want);
  end;
end;

{ ---- sheet ---- }
procedure TestSheet;
var
  sh: TSheet;
  c: TCell;
  r, col: Integer;
begin
  sh := TSheet.Create;
  Check(sh.Find(1, 1) = nil, 'empty sheet has no cells');
  sh.Put(1, 1, '''a');
  sh.Put(MaxRow, MaxCol, '5');
  CheckInt(sh.Count, 2, 'sparse count');
  CheckStr(sh.Find(MaxRow, MaxCol).Raw, '5', 'far corner stored');
  sh.UsedExtent(r, col);
  CheckInt(r, MaxRow, 'extent row');
  CheckInt(col, MaxCol, 'extent col');
  sh.Put(1, 1, '''b');
  CheckInt(sh.Count, 2, 'overwrite does not add');
  c := sh.Find(1, 1);
  CheckStr(c.Raw, '''b', 'overwrite value');
  sh.Remove(1, 1);
  Check(sh.Find(1, 1) = nil, 'remove');
  CheckInt(sh.ColWidth(3), 9, 'default width');
  sh.SetColWidth(3, 23);
  CheckInt(sh.ColWidth(3), 23, 'set width');
  Check(sh.ColWidthIsSet(3), 'width flagged');
  sh.Free;

  CheckStr(ColLetter(1), 'A', 'col A');
  CheckStr(ColLetter(26), 'Z', 'col Z');
  CheckStr(ColLetter(27), 'AA', 'col AA');
  CheckStr(ColLetter(256), 'IV', 'col IV');
  Check(ParseAddr('iv8192', col, r) and (col = 256) and (r = 8192), 'parse IV8192');
  Check(not ParseAddr('IW1', col, r), 'IW1 out of range');
  Check(not ParseAddr('A8193', col, r), 'row out of range');
  Check(not ParseAddr('12', col, r), 'digits only');
end;

{ ---- change journal ---- }
procedure TestJournal;
var
  sh: TSheet;
  a, b: TChangeSet;
  i: Integer;
begin
  sh := TSheet.Create;
  for i := 1 to 5000 do sh.Put(i, 1, IntToStr(i));
  sh.Put(1, 2, '''one');
  a := sh.BeginChange;
  sh.Put(1, 2, '''uno');
  sh.Journal := nil;
  CheckInt(a.Count, 1, 'journal records only the touched cell, not 5000');
  b := sh.Revert(a);
  CheckStr(sh.Find(1, 2).Raw, '''one', 'revert restores text');
  a.Free;
  a := sh.Revert(b);
  CheckStr(sh.Find(1, 2).Raw, '''uno', 'reverting the revert redoes');
  a.Free;
  b.Free;

  a := sh.BeginChange;
  sh.Put(1, 2, '''dos');           { touched twice: the first state wins }
  sh.Put(1, 2, '''tres');
  sh.Remove(2, 1);
  sh.Put(808, 3, 'new');
  sh.SetColWidth(4, 20);
  sh.SetColWidth(4, 25);
  sh.GlobalWidth := 12;
  sh.GlobalFmt := MakeFormat(fkFixed, 3);
  sh.SetCellFormat(3, 1, MakeFormat(fkSci, 1), False);
  sh.Journal := nil;
  CheckInt(a.Count, 5, 'journal counts cells and widths once each');
  b := sh.Revert(a);
  CheckStr(sh.Find(1, 2).Raw, '''uno', 'first state wins');
  CheckStr(sh.Find(2, 1).Raw, '2', 'removed cell is back');
  Check(sh.Find(808, 3) = nil, 'added cell is gone');
  CheckInt(sh.ColWidth(4), 9, 'width restored');
  CheckInt(sh.GlobalWidth, 9, 'global width restored');
  CheckStr(FormatTag(sh.GlobalFmt), 'G', 'global format restored');
  Check(sh.Find(3, 1).Fmt.UseGlobal, 'cell format restored');
  CheckInt(sh.Count, 5001, 'cell count back to what it was');
  a.Free;
  a := sh.Revert(b);
  CheckStr(sh.Find(1, 2).Raw, '''tres', 'redo text');
  Check(sh.Find(2, 1) = nil, 'redo removal');
  CheckInt(sh.ColWidth(4), 25, 'redo width');
  CheckStr(FormatTag(sh.GlobalFmt), 'F3', 'redo global format');
  a.Free;
  b.Free;

  { erasing the sheet is a journalled change too }
  a := sh.BeginChange;
  sh.Clear;
  sh.Journal := nil;
  CheckInt(sh.Count, 0, 'cleared');
  b := sh.Revert(a);
  CheckInt(sh.Count, 5001, 'clear undone');
  CheckInt(sh.ColWidth(4), 25, 'widths back after clear undone');
  a.Free;
  b.Free;
  sh.Free;
end;

{ ---- display formatting ---- }
procedure TestFormat;
var
  c: TCell;
  sh: TSheet;
  f: TCellFormat;
begin
  sh := TSheet.Create;
  c := TCell.Create;
  c.SetRaw('3.50');
  CheckStr(ValueText(c, sh, 9), '3.5', 'general trims zeros');
  c.Raw := '0.1234567891234';
  CheckStr(ValueText(c, sh, 9), '0.1234568', 'general fits the column width');
  c.Raw := '1234567890123';
  CheckStr(ValueText(c, sh, 9), '1.235E+12', 'general falls back to scientific');
  c.Raw := '-12345';
  CheckStr(ValueText(c, sh, 9), '-12345', 'negative general');

  c.Fmt := MakeFormat(fkCurrency, 2);
  c.Raw := '1234567.891';
  CheckStr(ValueText(c, sh, 20), '$1,234,567.89', 'currency commas');
  c.Raw := '-5';
  CheckStr(ValueText(c, sh, 20), '($5.00)', 'currency negative');
  c.SetRaw('@SUM(A1..A3)');
  c.Val := NumValue(10.99);
  CheckStr(ValueText(c, sh, 20), '$10.99', 'formula value is formatted');
  c.SetRaw('1');

  c.Raw := '1234.5';
  c.Fmt := MakeFormat(fkFixed, 0);
  CheckStr(ValueText(c, sh, 20), '1235', 'fixed 0');
  c.Fmt := MakeFormat(fkFixed, 3);
  CheckStr(ValueText(c, sh, 20), '1234.500', 'fixed 3');
  c.Fmt := MakeFormat(fkComma, 1);
  CheckStr(ValueText(c, sh, 20), '1,234.5', 'comma 1');
  c.Fmt := MakeFormat(fkSci, 2);
  CheckStr(ValueText(c, sh, 20), '1.23E+03', 'sci 2');
  c.Raw := '0.00012';
  CheckStr(ValueText(c, sh, 20), '1.20E-04', 'sci small');
  c.Raw := '0.256';
  c.Fmt := MakeFormat(fkPercent, 1);
  CheckStr(ValueText(c, sh, 20), '25.6%', 'percent');
  c.Raw := '3';
  c.Fmt := MakeFormat(fkPlusMinus, 0);
  CheckStr(ValueText(c, sh, 20), '+++', 'plus-minus');
  c.Raw := '-2';
  CheckStr(ValueText(c, sh, 20), '--', 'plus-minus negative');
  c.Raw := '0';
  CheckStr(ValueText(c, sh, 20), '.', 'plus-minus zero');
  c.Raw := '12.5';
  c.Fmt := MakeFormat(fkText, 0);
  CheckStr(ValueText(c, sh, 20), '12.5', 'text format shows contents');
  c.Fmt := MakeFormat(fkHidden, 0);
  CheckStr(ValueText(c, sh, 20), '', 'hidden');
  c.Fmt := MakeFormat(fkDate, 1);
  c.Raw := '36526';
  CheckStr(ValueText(c, sh, 20), '01-Jan-00', 'date D1');
  c.Fmt := MakeFormat(fkDate, 4);
  CheckStr(ValueText(c, sh, 20), '01/01/00', 'date D4');
  c.Fmt := MakeFormat(fkDate, 6);
  c.Raw := '0.5625';
  CheckStr(ValueText(c, sh, 20), '01:30:00 PM', 'time D6');
  c.Fmt := MakeFormat(fkDate, 9);
  CheckStr(ValueText(c, sh, 20), '13:30', 'time D9');

  { global format and zero suppression }
  c.Fmt.UseGlobal := True;
  c.Raw := '0';
  sh.GlobalFmt := MakeFormat(fkFixed, 2);
  CheckStr(ValueText(c, sh, 9), '0.00', 'cell follows global format');
  sh.ZeroDisplay := False;
  CheckStr(ValueText(c, sh, 9), '', 'zero suppressed');
  f := EffectiveFormat(c, sh);
  CheckStr(FormatTag(f), 'F2', 'tag');
  CheckStr(FormatTag(MakeFormat(fkComma, 0)), ',0', 'comma tag');
  CheckStr(FormatTag(MakeFormat(fkDate, 7)), 'D7', 'time tag');

  c.SetRaw('$12');
  sh.ZeroDisplay := True;
  CheckStr(ValueText(c, sh, 9), 'ERR', 'text that is not a number or formula shows ERR');
  CheckStr(NumToRaw(3.26), '3.26', 'number stored shortest');
  c.Free;
  sh.Free;
end;

{ ---- formulas ---- }
function Shown(S: TSession; r, c: Integer): string;
var
  cell: TCell;
begin
  cell := S.Sheet.Find(r, c);
  if cell = nil then exit('(empty)');
  Result := ValueText(cell, S.Sheet, 30);
end;

{ puts f in A1 of a fresh sheet and returns what A1 displays }
function EvalA1(const f: string): string;
var
  X: TSession;
begin
  X := TSession.Create;
  try
    X.Sheet.Put(1, 1, f);
    X.Calc.Recalc;
    Result := Shown(X, 1, 1);
  finally
    X.Free;
  end;
end;

procedure CheckCompile(const src, canon: string);
var
  f: TFormula;
  pos: Integer;
begin
  Inc(Total);
  if not CompileFormula(src, f, pos) then
  begin
    Inc(Fails);
    WriteLn('FAIL: compile ', src, ' failed at ', pos);
    exit;
  end;
  if f.Text <> canon then
  begin
    Inc(Fails);
    WriteLn('FAIL: canonical form of ', src, ': got ', f.Text, ' want ', canon);
  end;
  f.Free;
end;

procedure CheckBad(const src: string; wantPos: Integer);
var
  f: TFormula;
  pos: Integer;
begin
  Inc(Total);
  if CompileFormula(src, f, pos) then
  begin
    Inc(Fails);
    WriteLn('FAIL: should not compile: ', src);
    f.Free;
  end
  else if (wantPos > 0) and (pos <> wantPos) then
  begin
    Inc(Fails);
    WriteLn('FAIL: error position of ', src, ': got ', pos, ' want ', wantPos);
  end;
end;

procedure TestFormulas;
var
  X: TSession;
  i: Integer;
begin
  CheckCompile('+a1 + b2', '+A1+B2');
  CheckCompile('@sum( a1 , 5 )', '@SUM(A1,5)');
  CheckCompile('@sum(a3.a1)', '@SUM(A1..A3)');
  CheckCompile('@SUM(B2..A1)', '@SUM(A1..B2)');
  CheckCompile('$a$1+B$2+$C3', '$A$1+B$2+$C3');
  CheckCompile('(1+2)*3', '(1+2)*3');
  CheckCompile('+"hi"&A1', '+"hi"&A1');
  CheckCompile('1#and#2<3', '1#AND#2<3');
  CheckCompile('#not#A1', '#NOT#A1');
  CheckCompile('@pi', '@PI');
  CheckCompile('2^-1', '2^-1');
  CheckCompile('.5+1E2', '0.5+100');
  CheckBad('1+', 3);
  CheckBad('@FOO(1)', 1);
  CheckBad('12abc', 3);
  CheckBad('+A1B', 0);
  CheckBad('@SUM()', 1);
  CheckBad('(1+2', 5);
  CheckBad('+"abc', 0);
  CheckBad('+IV8193', 0);
  CheckBad('+IW1', 0);
  CheckBad('abc', 1);
  CheckBad('1 2', 3);

  { arithmetic and precedence }
  CheckStr(EvalA1('+1+2*3'), '7', 'precedence');
  CheckStr(EvalA1('(1+2)*3'), '9', 'parentheses');
  CheckStr(EvalA1('2^3^2'), '64', 'exponent is left to right');
  CheckStr(EvalA1('-2^2'), '-4', 'exponent binds tighter than unary minus (assumed)');
  CheckStr(EvalA1('2^-1'), '0.5', 'negative exponent');
  CheckStr(EvalA1('10/4'), '2.5', 'division');
  CheckStr(EvalA1('1/0'), 'ERR', 'division by zero');
  CheckStr(EvalA1('0^0'), 'ERR', 'zero to the zero');
  CheckStr(EvalA1('(-8)^0.5'), 'ERR', 'fractional power of a negative');
  CheckStr(EvalA1('10-4-3'), '3', 'subtraction is left to right');
  CheckStr(EvalA1('+3>2'), '1', 'comparison true');
  CheckStr(EvalA1('+2>3'), '0', 'comparison false');
  CheckStr(EvalA1('1<2#AND#2<3'), '1', 'and');
  CheckStr(EvalA1('0#OR#0'), '0', 'or');
  CheckStr(EvalA1('#NOT#0'), '1', 'not');
  CheckStr(EvalA1('1+2>2'), '1', 'arithmetic before comparison');
  CheckStr(EvalA1('+"a"&"b"'), 'ab', 'string concatenation');
  CheckStr(EvalA1('+"a"+1'), 'ERR', 'string literal in arithmetic is an error');
  CheckStr(EvalA1('+"abc"="ABC"'), '1', 'text comparison ignores case (assumed)');
  CheckStr(EvalA1('@NA'), 'NA', 'NA');
  CheckStr(EvalA1('@NA+1'), 'NA', 'NA propagates');
  CheckStr(EvalA1('@ERR+@NA'), 'ERR', 'ERR beats NA');
  CheckStr(EvalA1('@PI*2'), '6.283185307', 'pi');
  CheckStr(EvalA1('@SUM(1,2,3)'), '6', 'sum of numbers');
  CheckStr(EvalA1('+A1..A2'), 'ERR', 'range outside a function');

  { references, labels, empty cells }
  X := TSession.Create;
  X.Sheet.Put(1, 2, '4');
  X.Sheet.Put(2, 2, '6');
  X.Sheet.Put(3, 2, '''text');
  X.Sheet.Put(4, 2, '"right');
  X.Sheet.Put(1, 1, '@SUM(B1..B4)');
  X.Sheet.Put(2, 1, '+B1*B2');
  X.Sheet.Put(3, 1, '+B3+1');
  X.Sheet.Put(4, 1, '+C9+1');
  X.Sheet.Put(5, 1, '+B3&"!"');
  X.Sheet.Put(6, 1, '+B1&"!"');
  X.Sheet.Put(7, 1, '+C9&"x"');
  X.Sheet.Put(8, 1, '@SUM(B1..B2,10)');
  X.Sheet.Put(9, 1, '@SUM(B1..IV8192)');
  X.Calc.Recalc;
  CheckStr(Shown(X, 1, 1), '10', 'sum ignores labels');
  CheckStr(Shown(X, 2, 1), '24', 'cell references');
  CheckStr(Shown(X, 3, 1), '1', 'label counts as zero in arithmetic');
  CheckStr(Shown(X, 4, 1), '1', 'empty cell counts as zero');
  CheckStr(Shown(X, 5, 1), 'text!', 'label in string formula');
  CheckStr(Shown(X, 6, 1), 'ERR', 'number in string formula is an error');
  CheckStr(Shown(X, 7, 1), 'x', 'empty cell is empty text in string formula');
  CheckStr(Shown(X, 8, 1), '20', 'mixed range and number arguments');
  CheckStr(Shown(X, 9, 1), '10', 'huge range is walked sparsely');
  Check(not X.Calc.Circular, 'no circular reference');
  { a formula that produced text is displayed as text }
  CheckStr(Shown(X, 5, 1), 'text!', 'text result');
  { changing a precedent updates dependents }
  X.Sheet.Put(1, 2, '10');
  X.Calc.Recalc;
  CheckStr(Shown(X, 1, 1), '16', 'dependents follow their precedents');
  X.Free;

  { recalculation order: natural handles forward references }
  X := TSession.Create;
  X.Sheet.Put(1, 1, '+B1');
  X.Sheet.Put(1, 2, '+C1');
  X.Sheet.Put(1, 3, '5');
  X.Calc.Recalc;
  CheckStr(Shown(X, 1, 1), '5', 'natural order resolves forward references');
  X.Sheet.RecalcOrder := roColumnwise;
  X.Sheet.Put(1, 3, '7');
  X.Calc.Recalc;
  CheckStr(Shown(X, 1, 1), '5', 'columnwise one pass uses stale values');
  X.Sheet.Iterations := 3;
  X.Calc.Recalc;
  CheckStr(Shown(X, 1, 1), '7', 'more iterations settle it');
  X.Free;

  { circular references }
  X := TSession.Create;
  X.Sheet.Put(1, 1, '+B1');
  X.Sheet.Put(1, 2, '+A1');
  X.Calc.Recalc;
  Check(X.Calc.Circular, 'circular reference detected');
  X.Sheet.Put(1, 2, '3');
  X.Calc.Recalc;
  Check(not X.Calc.Circular, 'circular flag clears when fixed');
  CheckStr(Shown(X, 1, 1), '3', 'value after the cycle is broken');
  X.Sheet.Put(2, 1, '+A2+1');
  X.Calc.Recalc;
  Check(X.Calc.Circular, 'self reference is circular');
  X.Free;

  { manual recalculation }
  X := TSession.Create;
  X.Sheet.RecalcManual := True;
  X.Sheet.Put(1, 1, '1+1');
  X.Calc.SheetChanged;
  Check(X.Calc.NeedsCalc, 'manual mode flags CALC');
  CheckStr(Shown(X, 1, 1), '0', 'not recalculated yet');
  X.Calc.Recalc;
  Check(not X.Calc.NeedsCalc, 'recalc clears CALC');
  CheckStr(Shown(X, 1, 1), '2', 'recalculated on demand');
  X.Free;

  { a long chain: natural order recurses, still fine }
  X := TSession.Create;
  X.Sheet.Put(1, 1, '1');
  for i := 2 to 5000 do X.Sheet.Put(i, 1, '+A' + IntToStr(i - 1) + '+1');
  X.Calc.Recalc;
  CheckStr(Shown(X, 5000, 1), '5000', 'chain of 5000 dependent formulas');
  X.Free;
end;

{ ---- dates (serial numbers, including the 1900 leap-year quirk) ---- }
procedure TestDates;
var
  y, m, d: Integer;
begin
  Check(SerialToDate(1, y, m, d) and (y = 1900) and (m = 1) and (d = 1), 'serial 1');
  Check(SerialToDate(59, y, m, d) and (m = 2) and (d = 28), 'serial 59 is 28-Feb-1900');
  Check(SerialToDate(60, y, m, d) and (m = 2) and (d = 29), 'serial 60 is the phantom 29-Feb-1900');
  Check(SerialToDate(61, y, m, d) and (m = 3) and (d = 1), 'serial 61 is 1-Mar-1900');
  Check(SerialToDate(36526, y, m, d) and (y = 2000) and (m = 1) and (d = 1), 'serial 36526 is 1-Jan-2000');
  Check(not SerialToDate(0, y, m, d), 'serial 0 invalid');
  Check(SerialToDate(MaxSerial, y, m, d) and (y = 2099) and (m = 12) and (d = 31), 'last serial');
  CheckInt(DateToSerial(2000, 1, 1), 36526, 'date to serial');
  CheckInt(DateToSerial(1900, 2, 29), 60, 'phantom day to serial');
  CheckInt(DateToSerial(1900, 3, 1), 61, '1-Mar-1900 to serial');
  CheckInt(DateToSerial(1900, 1, 1), 1, '1-Jan-1900 to serial');
  CheckStr(FormatSerial(60, 1), '29-Feb-00', 'phantom day formatted');
  CheckStr(FormatSerial(0, 1), 'ERR', 'invalid date');
end;

{ ---- menus ---- }
procedure TestMenus;
var
  t: TMenuTree;
begin
  t := BuildMenuTree;
  CheckInt(t.Root.Count, 10, 'ten main menu items');
  CheckStr(t.Root.KidsText,
    'Worksheet, Range, Copy, Move, File, Print, Graph, Data, System, Quit', 'main menu order');
  CheckStr(t.Root[0].PanelText,
    'Global, Insert, Delete, Column, Erase, Titles, Window, Status, Page', 'worksheet panel text');
  CheckStr(t.Root[9][1].PanelText,
    'End the session (Answer Yes only if you have saved your work)', 'quit yes help');
  CheckInt(t.Root.FindByInitial('r'), 1, 'initial R finds Range');
  CheckInt(t.Root.FindByInitial('z'), -1, 'no initial Z');
  t.Free;
end;

{ ---- keys ---- }
procedure TestKeys;
var
  q: TKeyQueue;
  i: Integer;
begin
  q := TKeyQueue.Create;
  Check(q.Empty, 'new queue empty');
  for i := 1 to 100 do q.Push(i);
  CheckInt(q.Pop, 1, 'fifo first');
  for i := 2 to 100 do q.Pop;
  Check(q.Empty, 'drained');
  q.PushString('a' + UTF8Encode(WideChar($E9)));
  CheckInt(q.Pop, Ord('a'), 'string key a');
  CheckInt(q.Pop, $E9, 'utf-8 decoded');
  q.Free;
  CheckStr(KeyName(kF1 + 4), 'F5', 'F5 name');
  CheckStr(KeyName(kAltF1 + 3), 'Alt-F4', 'Alt-F4 name');
  CheckStr(KeyName(MakeAlt('x')), 'Alt-X', 'Alt-X name');
  CheckStr(KeyName(kCtrlRight), 'Ctrl-Right', 'Ctrl-Right name');
  CheckInt(Canonical(21), kAltF1 + 3, 'Ctrl-U is Undo');
  Check(MapCount > 20, 'mapping table populated');
end;

{ ---- controller ---- }
var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;

procedure NewSession;
begin
  S.Free;
  S := TSession.Create;
end;

procedure Feed(const keystr: string);
var
  q: TKeyQueue;
begin
  q := TKeyQueue.Create;
  q.PushString(keystr);
  while not q.Empty do Ctl.HandleKey(q.Pop);
  q.Free;
end;

procedure TestController;
begin
  S := nil;
  NewSession;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);

  { menus and stubs }
  Feed('/');
  Check(S.Mode = mMenu, 'slash opens menu');
  Feed('wgpe');
  Check(S.Mode = mReady, 'leaf returns to ready');
  CheckStr(S.Msg, '[stub] /Worksheet Global Protection Enable', 'stub message');

  Feed('/');
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kRight);
  CheckInt(S.MenuIdx[0], 2, 'right arrow moves highlight');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'esc at top level leaves menu');
  Feed('/wg');
  CheckInt(S.MenuDepth, 2, 'two levels down');
  Ctl.HandleKey(kEsc);
  CheckInt(S.MenuDepth, 1, 'esc goes up one level');
  Ctl.HandleKey(kBreak);
  Check(S.Mode = mReady, 'break leaves menu from any level');

  Feed('/qn');
  Check(not S.Quitting, 'quit no');
  Feed('/qy');
  Check(S.Quitting, 'quit yes');
  S.Quitting := False;

  { entry }
  Feed('hello'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''hello', 'label gets default prefix');
  Check(S.Mode = mReady, 'enter returns to ready');
  Ctl.HandleKey(kDown);
  Feed('12.5'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '12.5', 'number stored');
  Feed('"abc'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '"abc', 'explicit prefix kept');
  Feed('x');
  Check(S.Mode = mLabel, 'letter starts label mode');
  Ctl.HandleKey(kEsc);
  Check(S.Sheet.Find(2, 1).Raw = '"abc', 'esc cancels entry');
  Feed('7');
  Check(S.Mode = mValue, 'digit starts value mode');
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 3, 'arrow commits entry and moves');
  CheckStr(S.Sheet.Find(2, 1).Raw, '7', 'arrow committed value');
  Feed(UTF8Encode(WideChar($E9)) + 'te' + #13);
  CheckStr(S.Sheet.Find(3, 1).Raw, '''' + UTF8Encode(WideChar($E9)) + 'te', 'utf-8 label');
  Feed('ab');
  Ctl.HandleKey(kBackspace);
  CheckStr(S.Entry, 'a', 'backspace');
  Ctl.HandleKey(kEsc);

  { goto }
  Ctl.HandleKey(kF1 + 4);
  Check(S.Mode = mGoto, 'F5 starts goto');
  Feed('c10'#13);
  CheckInt(S.CurCol, 3, 'goto column');
  CheckInt(S.CurRow, 10, 'goto row');
  Ctl.HandleKey(kHome);
  CheckInt(S.CurRow * 100 + S.CurCol, 101, 'home goes to A1');

  { end-jump over a contiguous block }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '1');
  S.Sheet.Put(3, 1, '1');
  S.Sheet.Put(8, 1, '1');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 3, 'end-down stops at end of block');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 8, 'end-down jumps to next block');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, MaxRow, 'end-down runs to the edge');

  { scrolling }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  Ctl.HandleKey(kPgDn);
  CheckInt(S.CurRow, 21, 'pgdn moves a screen');
  CheckInt(S.TopRow, 21, 'pgdn scrolls a screen');
  Ctl.HandleKey(kTab);
  CheckInt(S.LeftCol, 9, 'tab moves right a screen');


  { ---- phase 3 ---- }
  NewSession;
  Ctl := TController.Create(S, Cmds);

  { EDIT mode (F2) }
  S.Sheet.Put(1, 1, '''abcd');
  Ctl.HandleKey(kF1 + 1);
  Check(S.Mode = mEdit, 'F2 enters edit');
  CheckStr(S.Entry, '''abcd', 'edit shows contents with prefix');
  Ctl.HandleKey(kLeft);
  Ctl.HandleKey(kLeft);
  Feed('XY');
  CheckStr(S.Entry, '''abXYcd', 'insert at cursor');
  Ctl.HandleKey(kBackspace);
  CheckStr(S.Entry, '''abXcd', 'backspace in edit');
  Ctl.HandleKey(kDel);
  CheckStr(S.Entry, '''abXd', 'delete in edit');
  Ctl.HandleKey(kHome);
  Ctl.HandleKey(kRight);
  Feed('Z');
  CheckStr(S.Entry, '''ZabXd', 'home then right');
  Ctl.HandleKey(kEnter);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''ZabXd', 'edit committed');
  Ctl.HandleKey(kF1 + 1);
  Ctl.HandleKey(kEsc);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''ZabXd', 'esc cancels edit');
  Ctl.HandleKey(kDown);
  Feed('ab');
  Ctl.HandleKey(kF1 + 1);
  Check(S.Mode = mEdit, 'F2 during entry');
  CheckStr(S.Entry, '''ab', 'entry carried into edit with prefix');
  Ctl.HandleKey(kEsc);

  { numbers are normalised }
  Feed('007.50'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '7.5', 'number normalised');

  { /Range Format Currency 2 over A2..A3 via POINT mode }
  S.Sheet.Put(3, 1, '1234.5');
  S.CurRow := 2;
  Feed('/rfc');
  Check(S.Mode = mPrompt, 'decimal places prompt');
  Feed(#13);
  Check(S.Mode = mPoint, 'range prompt follows');
  Ctl.HandleKey(Ord('.'));
  Ctl.HandleKey(kDown);
  Ctl.HandleKey(kEnter);
  Check(S.Mode = mReady, 'range accepted');
  CheckInt(S.CurRow, 2, 'pointer returns to where it was');
  CheckStr(FormatTag(S.Sheet.Find(3, 1).Fmt), 'C2', 'second cell formatted');
  CheckStr(FormatTag(S.Sheet.Find(2, 1).Fmt), 'C2', 'first cell formatted');
  Check(S.Sheet.Find(1, 1).Fmt.UseGlobal, 'unselected cell unchanged');

  { typing a range }
  Feed('/rfr');
  Check(S.Mode = mPoint, 'reset asks for a range');
  Feed('a1.a3'#13);
  Check(S.Sheet.Find(2, 1).Fmt.UseGlobal, 'reset returns cell to global format');

  { Undo }
  Check(S.HasUndo, 'undo available after commands');
  Ctl.HandleKey(kAltF1 + 3);
  CheckStr(FormatTag(S.Sheet.Find(2, 1).Fmt), 'C2', 'undo restores formats');
  Ctl.HandleKey(kAltF1 + 3);
  Check(S.Sheet.Find(2, 1).Fmt.UseGlobal, 'undo again redoes');

  { column widths with live preview }
  S.CurCol := 2;
  Feed('/wcs');
  Check(S.Mode = mPrompt, 'width prompt');
  CheckStr(S.Entry, '9', 'default is current width');
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kRight);
  CheckInt(S.Sheet.ColWidth(2), 11, 'arrows preview the width');
  Ctl.HandleKey(kEsc);
  CheckInt(S.Sheet.ColWidth(2), 9, 'esc restores the width');
  Feed('/wcs');
  Feed(#8'20'#13);
  CheckInt(S.Sheet.ColWidth(2), 20, 'width set');
  Check(S.Sheet.ColWidthIsSet(2), 'width flagged as set');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.ColWidth(2), 9, 'undo restores width');
  Feed('/wcs');
  Feed(#8'999'#13);
  Check(S.Mode = mPrompt, 'out-of-range width is refused');
  Ctl.HandleKey(kEsc);
  S.Sheet.SetColWidth(2, 15);
  Feed('/wcr');
  CheckInt(S.Sheet.ColWidth(2), 9, 'reset-width');
  Feed('/wgc');
  Feed(#8#8'12'#13);
  CheckInt(S.Sheet.GlobalWidth, 12, 'global width');

  { label prefixes }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  Feed('/wglr');
  Feed('hi'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '"hi', 'global right alignment applies to new labels');
  S.Sheet.Put(2, 1, '''left');
  S.Sheet.Put(3, 1, '\-');
  Feed('/wglc');
  CheckStr(S.Sheet.Find(1, 1).Raw, '^hi', 'global label-prefix changes existing labels');
  CheckStr(S.Sheet.Find(2, 1).Raw, '^left', 'existing label changed');
  CheckStr(S.Sheet.Find(3, 1).Raw, '\-', 'repeating label untouched');
  Feed('/rll');
  Feed('a1.a1'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''hi', 'range label left');
  CheckStr(S.Sheet.Find(2, 1).Raw, '^left', 'outside range unchanged');

  { erase }
  Feed('/re');
  Check(S.Mode = mPoint, 'range erase prompts');
  Feed('a1.a2'#13);
  Check(S.Sheet.Find(1, 1) = nil, 'range erased');
  Check(S.Sheet.Find(3, 1) <> nil, 'rest kept');
  Feed('/wen');
  Check(S.Sheet.Find(3, 1) <> nil, 'worksheet erase No keeps data');
  Feed('/wey');
  CheckInt(S.Sheet.Count, 0, 'worksheet erase Yes');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.Count, 1, 'undo of worksheet erase');

  { zero display }
  Feed('/wgzy');
  Check(not S.Sheet.ZeroDisplay, 'zero hidden');
  Feed('/wgzn');
  Check(S.Sheet.ZeroDisplay, 'zero shown');

  { global formats }
  Feed('/wgfp');
  Feed(#8'1'#13);
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'P1', 'global percent 1');
  Feed('/wgfg');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'G', 'global general');
  Feed('/wgfd1');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'D1', 'global date 1');
  Feed('/wgfdt3');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'D8', 'global time 3 is D8');

  Feed('/rfg');
  Check(S.Mode = mPoint, 'range format general prompts');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'esc cancels range prompt');


  { ---- phase 4: formulas through the keyboard ---- }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  Feed('5'#13);
  Ctl.HandleKey(kDown);
  Feed('+a1*2'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '+A1*2', 'formula stored in canonical form');
  CheckStr(ValueText(S.Sheet.Find(2, 1), S.Sheet, 9), '10', 'formula calculated on entry');
  Ctl.HandleKey(kUp);
  Feed('7'#13);
  CheckStr(ValueText(S.Sheet.Find(2, 1), S.Sheet, 9), '14', 'dependents recalculated automatically');
  Ctl.HandleKey(kAltF1 + 3);
  CheckStr(ValueText(S.Sheet.Find(2, 1), S.Sheet, 9), '10', 'undo recalculates');
  Ctl.HandleKey(kDown);
  Ctl.HandleKey(kDown);
  Feed('1+'#13);
  Check(S.Mode = mEdit, 'invalid formula opens EDIT mode');
  CheckInt(S.EditPos, 2, 'cursor at the problem');
  CheckStr(S.Entry, '1+', 'entry kept for correction');
  Feed('1'#13);
  Check(S.Mode = mReady, 'corrected formula accepted');
  Check(S.Sheet.Find(3, 1) <> nil, 'corrected formula stored');
  CheckStr(Shown(S, 3, 1), '2', 'corrected formula value');
  Feed('12abc'#13);
  Check(S.Mode = mEdit, 'number followed by text is refused');
  Ctl.HandleKey(kEsc);
  Check(S.Sheet.Find(4, 1) = nil, 'refused entry stores nothing');
  Ctl.HandleKey(kDown);
  Feed('+a1'#13);

  { recalculation settings from the menu }
  Feed('/wgrm');
  Check(S.Sheet.RecalcManual, 'manual recalculation');
  S.CurRow := 1;
  Feed('9'#13);
  Check(S.Calc.NeedsCalc, 'CALC pending in manual mode');
  CheckStr(ValueText(S.Sheet.Find(2, 1), S.Sheet, 9), '10', 'not recalculated yet');
  Ctl.HandleKey(kF1 + 8);
  CheckStr(ValueText(S.Sheet.Find(2, 1), S.Sheet, 9), '18', 'F9 recalculates');
  Check(not S.Calc.NeedsCalc, 'F9 clears CALC');
  Feed('/wgra');
  Check(not S.Sheet.RecalcManual, 'automatic recalculation');
  Feed('/wgrr');
  Check(S.Sheet.RecalcOrder = roRowwise, 'rowwise');
  Feed('/wgrc');
  Check(S.Sheet.RecalcOrder = roColumnwise, 'columnwise');
  Feed('/wgrn');
  Check(S.Sheet.RecalcOrder = roNatural, 'natural');
  Feed('/wgri');
  Check(S.Mode = mPrompt, 'iteration prompt');
  Feed(#8'5'#13);
  CheckInt(S.Sheet.Iterations, 5, 'iteration count');
  Feed('/wgri');
  Feed(#8'99'#13);
  Check(S.Mode = mPrompt, 'iteration count above 50 refused');
  Ctl.HandleKey(kEsc);
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.Iterations, 1, 'undo restores the iteration count');

  { a circular reference is flagged }
  S.CurRow := 10;
  Feed('+b10'#13);
  Ctl.HandleKey(kRight);
  Feed('+a10'#13);
  Check(S.Calc.Circular, 'circular reference flagged after entry');

  S.Free;
  Cmds.Free;
end;

begin
  TestSheet;
  TestJournal;
  TestFormat;
  TestDates;
  TestFormulas;
  TestMenus;
  TestKeys;
  TestController;
  WriteLn(Total - Fails, '/', Total, ' checks passed');
  if Fails > 0 then Halt(1);
end.
