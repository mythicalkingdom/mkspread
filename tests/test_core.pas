{ Unit tests for the terminal-independent core: storage, formatting, menus,
  key queue and the controller driven purely by logical keys. }
program test_core;
{$mode objfpc}{$H+}

uses SysUtils, Classes, Math, fn_time, keys, editops, charsets, wk1, textimport, formula, sheet, cellfmt, dates, menutree, menudata, session, commands, controller;

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
  CheckStr(ValueText(c, sh, 20), '01-Jan-2000', 'date D1 (four digits from 2000)');
  c.Fmt := MakeFormat(fkDate, 4);
  CheckStr(ValueText(c, sh, 20), '01/01/2000', 'date D4 (four digits from 2000)');
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
  CheckBad('@SUM()', 1);
  CheckBad('(1+2', 5);
  CheckBad('+"abc', 0);
  CheckCompile('+a1b', '+A1B');
  CheckCompile('@sum(total)', '@SUM(TOTAL)');
  CheckBad('+1abc', 0);
  CheckBad('+$A', 0);
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
  CheckStr(EvalA1('+"a"+1'), '1', 'a string in arithmetic counts as zero (observed)');
  CheckStr(EvalA1('+"abc"="ABC"'), '1', 'text comparison ignores case (assumed)');
  CheckStr(EvalA1('@NA'), 'NA', 'NA');
  CheckStr(EvalA1('@NA+1'), 'NA', 'NA propagates');
  CheckStr(EvalA1('@ERR+@NA'), 'ERR', 'ERR beats NA');
  CheckStr(EvalA1('@PI*2'), '6.2831853072', 'pi (General shows 10 decimals)');
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

{ ---- editing operations ---- }
function RawAt(S: TSession; r, c: Integer): string;
begin
  if S.Sheet.Find(r, c) = nil then Result := '(empty)' else Result := S.Sheet.Find(r, c).Raw;
end;

procedure TestEditOps;
var
  S: TSession;
  msg: string;
  i: Integer;
begin
  { ---- copy: relative, absolute, mixed ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '5');
  S.Sheet.Put(1, 2, '+A1*2');
  S.Sheet.Put(1, 3, '+$A$1+$A1+A$1');
  msg := CopyRange(S.Sheet, NormRange(1, 2, 1, 3), NormRange(2, 2, 2, 2));
  CheckStr(msg, '', 'copy succeeds');
  CheckStr(RawAt(S, 2, 2), '+A2*2', 'relative reference shifts with the copy');
  CheckStr(RawAt(S, 2, 3), '+$A$1+$A2+A$1', 'absolute and mixed references');
  { a single cell fills the whole target }
  CopyRange(S.Sheet, NormRange(1, 1, 1, 1), NormRange(5, 4, 7, 5));
  CheckInt(S.Sheet.Count, 3 + 2 + 6, 'one cell filled six target cells');
  CheckStr(RawAt(S, 7, 5), '5', 'last target cell');
  { a row is repeated down the target }
  CopyRange(S.Sheet, NormRange(1, 1, 1, 2), NormRange(10, 1, 12, 1));
  CheckStr(RawAt(S, 10, 2), '+A10*2', 'row copy, first row');
  CheckStr(RawAt(S, 12, 2), '+A12*2', 'row copy, third row');
  { a column is repeated across the target }
  S.Sheet.Put(20, 1, '1');
  S.Sheet.Put(21, 1, '2');
  CopyRange(S.Sheet, NormRange(20, 1, 21, 1), NormRange(20, 3, 20, 4));
  CheckStr(RawAt(S, 21, 4), '2', 'column copy across');
  { a block uses only the target's top left }
  CopyRange(S.Sheet, NormRange(20, 1, 21, 1), NormRange(30, 1, 40, 5));
  CheckStr(RawAt(S, 31, 1), '2', 'block copy lands once');
  Check(S.Sheet.Find(32, 1) = nil, 'block copy is not repeated');
  { empty source cells clear the target }
  S.Sheet.Put(50, 2, '9');
  CopyRange(S.Sheet, NormRange(60, 1, 60, 1), NormRange(50, 2, 50, 2));
  Check(S.Sheet.Find(50, 2) = nil, 'copying an empty cell clears the target');
  { copying to overlapping cells works on a snapshot }
  S.Sheet.Clear;
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '+A1+1');
  S.Sheet.Put(3, 1, '+A2+1');
  CopyRange(S.Sheet, NormRange(1, 1, 3, 1), NormRange(2, 1, 2, 1));
  CheckStr(RawAt(S, 2, 1), '1', 'overlap: first copied cell');
  CheckStr(RawAt(S, 3, 1), '+A2+1', 'overlap: second copied cell');
  CheckStr(RawAt(S, 4, 1), '+A3+1', 'overlap: third copied cell');
  { copy off the edge of the sheet turns the reference into an error }
  S.Sheet.Clear;
  S.Sheet.Put(1, 1, '+IV1');
  CopyRange(S.Sheet, NormRange(1, 1, 1, 1), NormRange(1, 2, 1, 2));
  CheckStr(RawAt(S, 1, 2), '+@ERR', 'reference pushed off the sheet');
  { formats are copied }
  S.Sheet.Put(5, 5, '3').Fmt := MakeFormat(fkCurrency, 2);
  CopyRange(S.Sheet, NormRange(5, 5, 5, 5), NormRange(6, 5, 6, 5));
  CheckStr(FormatTag(S.Sheet.Find(6, 5).Fmt), 'C2', 'copy keeps the format');
  S.Free;

  { ---- move ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '+A1');
  S.Sheet.Put(1, 2, '+A1+A2');
  S.Sheet.Put(5, 5, '7');
  S.Sheet.Put(6, 6, '+E5');
  msg := MoveRange(S.Sheet, NormRange(1, 1, 2, 1), 1, 3);
  CheckStr(msg, '', 'move succeeds');
  Check(S.Sheet.Find(1, 1) = nil, 'source vacated');
  CheckStr(RawAt(S, 1, 3), '1', 'moved cell');
  CheckStr(RawAt(S, 2, 3), '+C1', 'moved formula follows the cells it refers to');
  CheckStr(RawAt(S, 1, 2), '+C1+C2', 'other formulas follow moved cells');
  { references to overwritten cells become errors }
  MoveRange(S.Sheet, NormRange(1, 3, 1, 3), 5, 5);
  CheckStr(RawAt(S, 5, 5), '1', 'moved over an existing cell');
  CheckStr(RawAt(S, 6, 6), '+@ERR', 'reference to an overwritten cell is an error');
  CheckStr(RawAt(S, 1, 2), '+E5+C2', 'reference to the moved cell follows it');
  CheckStr(MoveRange(S.Sheet, NormRange(1, 1, 3, 3), MaxRow, 1), 'Cannot move there: it would leave the worksheet', 'move off the sheet refused');
  S.Free;

  { ---- insert and delete rows ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '2');
  S.Sheet.Put(3, 1, '+A1+A2');
  S.Sheet.Put(5, 1, '@SUM(A1..A3)');
  S.Sheet.SetName('ALL', NormRange(1, 1, 3, 1));
  S.Sheet.SetName('LAST', NormRange(3, 1, 3, 1));
  msg := InsertRows(S.Sheet, 2, 2);
  CheckStr(msg, '', 'insert rows');
  CheckStr(RawAt(S, 1, 1), '1', 'row above the insert stays');
  Check(S.Sheet.Find(2, 1) = nil, 'inserted row is empty');
  CheckStr(RawAt(S, 4, 1), '2', 'row below moved down');
  CheckStr(RawAt(S, 5, 1), '+A1+A4', 'formula references follow');
  CheckStr(RawAt(S, 7, 1), '@SUM(A1..A5)', 'a range grows when rows are inserted inside it');
  Check(S.Sheet.FindName('ALL', S.PendRange) and (S.PendRange.R2 = 5), 'range name grows');
  Check(S.Sheet.FindName('LAST', S.PendRange) and (S.PendRange.R1 = 5), 'range name moves');
  msg := DeleteRows(S.Sheet, 2, 3);
  CheckStr(msg, '', 'delete rows');
  CheckStr(RawAt(S, 2, 1), '2', 'rows below move up');
  CheckStr(RawAt(S, 3, 1), '+A1+A2', 'references into the deleted rows move to survivors');
  CheckStr(RawAt(S, 5, 1), '@SUM(A1..A3)', 'range shrinks');
  DeleteRows(S.Sheet, 2, 2);
  CheckStr(RawAt(S, 2, 1), '+A1+@ERR', 'reference to a deleted cell is an error');
  Check(not S.Sheet.FindName('LAST', S.PendRange) or (S.PendRange.R1 >= 1), 'name still sane');
  S.Sheet.Put(1, 3, '@SUM(A2..A2)');
  DeleteRows(S.Sheet, 2, 2);
  CheckStr(RawAt(S, 1, 3), '@SUM(@ERR)', 'a range that is entirely deleted is an error');
  S.Free;

  { ---- insert and delete columns ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(1, 2, '2');
  S.Sheet.Put(1, 3, '+A1+B1');
  S.Sheet.SetColWidth(2, 20);
  S.Sheet.SetColWidth(3, 12);
  InsertCols(S.Sheet, 2, 1);
  CheckStr(RawAt(S, 1, 3), '2', 'column moved right');
  CheckStr(RawAt(S, 1, 4), '+A1+C1', 'column insert rewrites references');
  CheckInt(S.Sheet.ColWidth(2), 9, 'inserted column has the default width');
  CheckInt(S.Sheet.ColWidth(3), 20, 'column widths move with their columns');
  CheckInt(S.Sheet.ColWidth(4), 12, 'widths shift');
  DeleteCols(S.Sheet, 2, 2);
  CheckStr(RawAt(S, 1, 2), '2', 'column moved back');
  CheckInt(S.Sheet.ColWidth(2), 20, 'width restored on delete');
  DeleteCols(S.Sheet, 2, 2);
  CheckStr(RawAt(S, 1, 2), '+A1+@ERR', 'deleting a referenced column');
  S.Free;

  { insert would push cells off the sheet }
  S := TSession.Create;
  S.Sheet.Put(MaxRow, 1, '1');
  CheckStr(InsertRows(S.Sheet, 1, 1), 'Worksheet full: cannot insert that many rows', 'insert refused when the sheet is full');
  Check(S.Sheet.Find(MaxRow, 1) <> nil, 'nothing was lost');
  S.Free;

  { ---- value and transpose ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '2');
  S.Sheet.Put(1, 2, '+A1*3');
  S.Sheet.Put(1, 3, '''txt');
  S.Sheet.Put(2, 1, '+"a"&"b"');
  S.Calc.Recalc;
  ValuesRange(S.Sheet, NormRange(1, 1, 2, 3), 5, 1);
  CheckStr(RawAt(S, 5, 2), '6', 'Range Value turns a formula into its value');
  CheckStr(RawAt(S, 5, 3), '''txt', 'labels copied');
  CheckStr(RawAt(S, 6, 1), '''ab', 'text result becomes a label');
  TransposeRange(S.Sheet, NormRange(1, 1, 2, 3), 10, 1);
  CheckStr(RawAt(S, 10, 1), '2', 'transpose: top left');
  CheckStr(RawAt(S, 11, 1), '6', 'transpose: row becomes column');
  CheckStr(RawAt(S, 12, 1), '''txt', 'transpose: third');
  CheckStr(RawAt(S, 10, 2), '''ab', 'transpose: second row');
  S.Free;

  { ---- range names in formulas ---- }
  S := TSession.Create;
  S.Sheet.Put(1, 1, '4');
  S.Sheet.Put(2, 1, '6');
  S.Sheet.Put(3, 1, '10');
  S.Sheet.SetName('PRICES', NormRange(1, 1, 3, 1));
  S.Sheet.SetName('FIRST', NormRange(1, 1, 1, 1));
  S.Sheet.Put(1, 3, '@SUM(prices)');
  S.Sheet.Put(2, 3, '+first*2');
  S.Sheet.Put(3, 3, '+prices');
  S.Sheet.Put(4, 3, '+nothing');
  S.Calc.Recalc;
  CheckStr(Shown(S, 1, 3), '20', 'a name as a range argument');
  CheckStr(Shown(S, 2, 3), '8', 'a single-cell name as a value');
  CheckStr(Shown(S, 3, 3), 'ERR', 'a multi-cell name outside a function');
  CheckStr(Shown(S, 4, 3), 'ERR', 'an undefined name');
  CheckStr(RawAt(S, 1, 3), '@SUM(PRICES)', 'names are stored upper case');
  S.Sheet.DeleteName('prices');
  S.Calc.Recalc;
  CheckStr(Shown(S, 1, 3), 'ERR', 'deleting a name breaks the formulas that use it');
  S.Sheet.SetName('PRICES', NormRange(1, 1, 2, 1));
  S.Calc.Recalc;
  CheckStr(Shown(S, 1, 3), '10', 'defining it again repairs them');
  Check(IsValidName('Total_1') and IsValidName('_x'), 'valid names');
  Check(not IsValidName('A1') and not IsValidName('1abc') and not IsValidName('a b') and not IsValidName('ABCDEFGHIJKLMNOP'), 'invalid names');
  Check(IsValidName('IW1') and IsValidName('A1B'), 'only real cell addresses are rejected');
  S.Free;

  { performance sanity: inserting a row in a sheet with many formulas }
  S := TSession.Create;
  for i := 1 to 3000 do S.Sheet.Put(i, 1, '+A' + IntToStr(i + 1) + '+1');
  S.Sheet.Put(3001, 1, '1');
  InsertRows(S.Sheet, 1, 1);
  CheckStr(RawAt(S, 2, 1), '+A3+1', 'many formulas rewritten');
  CheckStr(RawAt(S, 3002, 1), '1', 'last cell moved');
  S.Free;
end;

{ ---- character sets, file formats, import, /File ---- }
function Bytes(const hex: string): TBytes;
var
  i: Integer;
begin
  SetLength(Result, Length(hex) div 2);
  for i := 0 to High(Result) do Result[i] := StrToInt('$' + Copy(hex, i * 2 + 1, 2));
end;

function ToHex(const b: TBytes): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(b) do Result := Result + IntToHex(b[i], 2);
end;

procedure WriteBytesFile(const fn: string; const b: TBytes);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(fn, fmCreate);
  if Length(b) > 0 then fs.WriteBuffer(b[0], Length(b));
  fs.Free;
end;

procedure WriteTextFile(const fn, s: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(fn, fmCreate);
  if s <> '' then fs.WriteBuffer(s[1], Length(s));
  fs.Free;
end;

procedure TestCharsets;
begin
  CheckStr(LicsToUtf8('abc 123'), 'abc 123', 'ASCII is unchanged');
  CheckStr(LicsToUtf8(#$E9), UTF8Encode(WideChar($E9)), 'LICS e acute');
  CheckStr(LicsToUtf8(#$D7), UTF8Encode(WideChar($152)), 'LICS has OE at D7, not multiply');
  CheckStr(LicsToUtf8(#$A4), UTF8Encode(WideChar($201C)), 'LICS A4 is a double quote');
  CheckStr(LicsToUtf8(#$FF), UTF8Encode(WideChar($FFFD)), 'undefined LICS byte');
  CheckStr(Utf8ToLics(UTF8Encode(WideChar($E9))), #$E9, 'e acute back to LICS');
  CheckStr(Utf8ToLics(UTF8Encode(WideChar($152))), #$D7, 'OE back to LICS');
  CheckStr(Utf8ToLics(UTF8Encode(WideChar($4E2D))), '?', 'no LICS equivalent');
  CheckStr(Cp437ToUtf8(#$C4), UTF8Encode(WideChar($2500)), 'CP437 box drawing');
  CheckStr(Cp437ToUtf8(#$82), UTF8Encode(WideChar($E9)), 'CP437 e acute');
  CheckStr(Utf8ToCp437(UTF8Encode(WideChar($2500))), #$C4, 'box drawing back');
  Check(IsValidUtf8('plain') and IsValidUtf8(UTF8Encode(WideChar($E9))), 'valid UTF-8');
  Check(not IsValidUtf8(#$E9'x') and not IsValidUtf8(#$C3), 'invalid UTF-8');
  CheckStr(DecodeTextBytes(#$82), UTF8Encode(WideChar($E9)), 'unknown bytes are read as CP437');
  CheckStr(DecodeTextBytes(UTF8Encode(WideChar($E9))), UTF8Encode(WideChar($E9)), 'UTF-8 is kept');
end;

procedure TestFormatBytes;
var
  f: TCellFormat;
  b: Integer;
begin
  CheckInt(FormatToByte(MakeFormat(fkCurrency, 2)), $A2, 'currency 2 (protected) is A2');
  CheckStr(FormatTag(ByteToFormat($22)), 'C2', 'byte 22 is currency 2');
  CheckStr(FormatTag(ByteToFormat($F4)), 'D3', 'byte F4 is month-year');
  CheckStr(FormatTag(ByteToFormat($71)), 'G', 'byte 71 is general');
  Check(ByteToFormat($FF).UseGlobal and ByteToFormat($7F).UseGlobal, 'special 15 follows the global format');
  CheckStr(FormatTag(ByteToFormat($C2)), ',2', 'byte C2 is comma 2');
  CheckStr(FormatTag(ByteToFormat($A0)), 'C0', 'byte A0 is currency 0');
  CheckInt(FormatToByte(ByteToFormat($C1)), $C1, 'comma 1 round trip');
  for b := $00 to $FF do
  begin
    f := ByteToFormat(b);
    if f.UseGlobal or ((b shr 4) and 7 in [5, 6]) then continue;
    if (b and $7F) = FormatToByte(f) and $7F then continue;
    Inc(Fails);
    Inc(Total);
    WriteLn('FAIL: format byte ', IntToHex(b, 2), ' does not round trip');
    break;
  end;
end;

procedure TestRpn;
var
  f: TFormula;
  pos: Integer;
  txt: string;
  sh: TSheet;
begin
  sh := TSheet.Create;
  CompileFormula('+A1*2', f, pos);
  CheckStr(ToHex(EncodeFormula(f, sh, 1, 2)), '01FF80008005' + '0200' + '0B03', 'relative reference and integer constant');
  f.Free;
  CompileFormula('@SUM(C4..O4)', f, pos);
  CheckStr(ToHex(EncodeFormula(f, sh, 4, 16)), '02F3800080FF8000805001' + '03', 'relative range with a count byte');
  f.Free;
  CompileFormula('@STD(A1..A2)', f, pos);
  CheckStr(ToHex(EncodeFormula(f, sh, 3, 3)), '02FE80FE9FFE80FF9F' + '58' + '01' + '03', '@STD is a list function with a count byte');
  f.Free;
  CompileFormula('@N(G7)', f, pos);
  CheckStr(ToHex(EncodeFormula(f, sh, 1, 1)), '020680068006800680' + '70' + '03', 'a single cell where a range is expected is stored as a range');
  f.Free;
  CompileFormula('+$A$1+B$2', f, pos);
  CheckStr(ToHex(EncodeFormula(f, sh, 3, 3)), '010000000001FF8001000903', 'absolute and mixed');
  f.Free;
end;

procedure TestRpnDecode;
var
  txt: string;
begin
  Check(DecodeFormula(Bytes('01008000800FF' + '0'), 1, 1, txt) = False, 'truncated code is refused');
  Check(DecodeFormula(Bytes('010080FB9F' + '0503020B03'), 9, 4, txt), 'sample formula decodes');
  CheckStr(txt, '+D4*515', 'sample formula text');
  Check(DecodeFormula(Bytes('02F38000' + '80FF800080' + '500103'), 4, 16, txt), 'sample range formula decodes');
  CheckStr(txt, '@SUM(C4..O4)', 'sample range text');
  Check(not DecodeFormula(Bytes('05010003'), 1, 1, txt) = False, 'integer constant');
  Check(DecodeFormula(Bytes('020680068006800680' + '7003'), 1, 1, txt) and (txt = '@N(G7)'), 'a range of one cell reads back as a cell');
  { function codes as stored by the original program (a worksheet it saved) }
  Check(DecodeFormula(Bytes('056400' + '007B14AE47E17A843F' + '05B004' + '75' + '03'), 1, 1, txt), 'TERM decodes');
  CheckStr(txt, '@TERM(100,0.01,1200)', 'TERM is code 117');
  Check(DecodeFormula(Bytes('05D007' + '05E803' + '050A00' + '74' + '03'), 3, 1, txt), 'RATE decodes');
  CheckStr(txt, '@RATE(2000,1000,10)', 'RATE is code 116');
  Check(DecodeFormula(Bytes('05E803' + '056400' + '050900' + '77' + '03'), 4, 1, txt), 'SLN decodes');
  CheckStr(txt, '@SLN(1000,100,9)', 'SLN is code 119');
  Check(DecodeFormula(Bytes('05E803' + '056400' + '050300' + '050100' + '78' + '03'), 5, 1, txt), 'SYD decodes');
  CheckStr(txt, '@SYD(1000,100,3,1)', 'SYD is code 120');
  Check(DecodeFormula(Bytes('05E803' + '056400' + '050500' + '050100' + '79' + '03'), 6, 1, txt), 'DDB decodes');
  CheckStr(txt, '@DDB(1000,100,5,1)', 'DDB is code 121');
  Check(DecodeFormula(Bytes('00' + '9A9999999999B93F' + '05D007' + '05E803' + '76' + '03'), 2, 1, txt), 'CTERM decodes');
  CheckStr(txt, '@CTERM(0.1,2000,1000)', 'CTERM is code 118');
  { a range argument written with 14-bit relative offsets, as that program does }
  Check(DecodeFormula(Bytes('02FFBFFFBFFFBFFFBF' + '70' + '03'), 2, 2, txt), 'sign-extended 14-bit offsets decode');
  CheckStr(txt, '@N(A1)', 'N is code 112');
  Check(DecodeFormula(Bytes('0661646472657373' + '00' + '4F' + '03'), 1, 2, txt), '@CELLPOINTER decodes');
  CheckStr(txt, '@CELLPOINTER("address")', 'CELLPOINTER is code 79');
  Check(DecodeFormula(Bytes('37' + '03'), 1, 1, txt) and (txt = '@NOW'), '@NOW is code 55');
  Check(not DecodeFormula(Bytes('7F03'), 1, 1, txt), 'unknown opcode is refused');
  Check(not DecodeFormula(Bytes('0903'), 1, 1, txt), 'operator without operands is refused');
  Check(not DecodeFormula(Bytes('0501000502000003'), 1, 1, txt), 'two values left on the stack is refused');
end;

function TmpDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'mkspread_test_' + IntToStr(GetProcessID);
  ForceDirectories(Result);
end;

procedure CleanDir(const d: string);
var
  sr: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(d) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then DeleteFile(IncludeTrailingPathDelimiter(d) + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  SysUtils.RemoveDir(d);
end;

{ the body of the first record of the given type in a file, '' if none }
function RecordBody(const fn: string; op: Integer): TBytes;
var
  fs: TFileStream;
  buf: TBytes;
  p, t, ln: Integer;
begin
  SetLength(Result, 0);
  fs := TFileStream.Create(fn, fmOpenRead);
  SetLength(buf, fs.Size);
  fs.ReadBuffer(buf[0], Length(buf));
  fs.Free;
  p := 0;
  while p + 4 <= Length(buf) do
  begin
    t := buf[p] or (buf[p + 1] shl 8);
    ln := buf[p + 2] or (buf[p + 3] shl 8);
    if t = op then
    begin
      SetLength(Result, ln);
      if ln > 0 then Move(buf[p + 4], Result[0], ln);
      exit;
    end;
    Inc(p, 4 + ln);
  end;
end;

procedure TestWk1RoundTrip;
var
  A, B: TSession;
  info: TFileInfo;
  warn: TStringList;
  dir, fn, msg: string;
  i: Integer;
  cell: TCell;
  names: array[0..13] of TFormatKind;
  win: TBytes;
begin
  dir := TmpDir;
  fn := dir + '/rt.wk1';
  A := TSession.Create;
  B := TSession.Create;
  warn := TStringList.Create;
  try
    A.Sheet.Put(1, 1, '''left');
    A.Sheet.Put(2, 1, '"right');
    A.Sheet.Put(3, 1, '^center');
    A.Sheet.Put(4, 1, '\=');
    A.Sheet.Put(5, 1, '''caf' + UTF8Encode(WideChar($E9)) + ' ' + UTF8Encode(WideChar($152)));
    A.Sheet.Put(1, 2, '42');
    A.Sheet.Put(2, 2, '-7');
    A.Sheet.Put(3, 2, '3.14159265358979');
    A.Sheet.Put(4, 2, '123456789012');
    A.Sheet.Put(5, 2, '0.1');
    A.Sheet.Put(1, 3, '+B1*2');
    A.Sheet.Put(2, 3, '@SUM(B1..B5)');
    A.Sheet.Put(3, 3, '+$B$1+B$2+$B3');
    A.Sheet.Put(4, 3, '+"x"&A1');
    A.Sheet.Put(5, 3, '#NOT#(B1>3)#OR#B2<0');
    A.Sheet.Put(6, 3, '@ROUND(B3,2)');
    A.Sheet.Put(7, 3, '@PMT(1000,0.01,12)');
    A.Sheet.Put(8, 3, '@NA');
    A.Sheet.Put(9, 3, '@ERR');
    A.Sheet.Put(10, 3, '-(B1+B2)^2');
    A.Sheet.Put(11, 3, '@SUM(B1,B2,5)');
    A.Sheet.SetName('PRICES', NormRange(1, 2, 3, 2));
    A.Sheet.Put(12, 3, '@SUM(prices)');
    A.Sheet.Put(13, 3, '1/3');
    A.Sheet.Put(1, 4, '').Fmt := MakeFormat(fkHidden, 0);
    A.Sheet.Put(2, 4, '5').Fmt := MakeFormat(fkCurrency, 2);
    A.Sheet.Put(3, 4, '5').Fmt := MakeFormat(fkSci, 3);
    A.Sheet.Put(4, 4, '5').Fmt := MakeFormat(fkPercent, 1);
    A.Sheet.Put(5, 4, '5').Fmt := MakeFormat(fkComma, 0);
    A.Sheet.Put(6, 4, '36526').Fmt := MakeFormat(fkDate, 1);
    A.Sheet.Put(7, 4, '0.5').Fmt := MakeFormat(fkDate, 7);
    A.Sheet.Put(8, 4, '3').Fmt := MakeFormat(fkPlusMinus, 0);
    A.Sheet.Put(9, 4, '3').Fmt := MakeFormat(fkText, 0);
    A.Sheet.SetColWidth(2, 14);
    A.Sheet.SetColWidth(5, 3);
    A.Sheet.GlobalWidth := 11;
    A.Sheet.GlobalFmt := MakeFormat(fkFixed, 2);
    A.Sheet.GlobalLabelPrefix := '"';
    A.Sheet.RecalcOrder := roRowwise;
    A.Sheet.RecalcManual := True;
    A.Sheet.Iterations := 4;
    A.Sheet.TitleR1 := 1; A.Sheet.TitleR2 := 2;
    A.Sheet.TitleC1 := 1; A.Sheet.TitleC2 := 1;
    A.Calc.Recalc;
    FillChar(info, SizeOf(info), 0);
    info.CursorCol := 3; info.CursorRow := 6; info.LeftCol := 1; info.TopRow := 1;
    msg := SaveWorksheet(fn, A.Sheet, False, info, warn);
    CheckStr(msg, '', 'save succeeds');
    win := RecordBody(fn, 7);
    CheckInt(Length(win), 32, 'WINDOW1 is 32 bytes');
    CheckInt(win[24], 4, 'the row-number border is shown (width 4)');
    CheckInt(win[26], 4, 'the column-letter border is shown (height 4)');
    CheckInt(win[28], 72, 'window width');
    CheckInt(win[16], 1, 'title columns are counted in WINDOW1');
    CheckInt(win[18], 2, 'title rows are counted in WINDOW1');
    CheckInt(win[20], 0, 'first title column');
    CheckInt(win[22], 0, 'first title row');
    CheckStr(ToHex(RecordBody(fn, $2A)), 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 'the TITLES record is the (unset) print border');
    CheckInt(warn.Count, 0, 'save raised no warnings');

    msg := LoadWorksheet(fn, B.Sheet, warn, info);
    CheckStr(msg, '', 'load succeeds');
    CheckInt(info.Version, $0406, 'written as release 2');
    CheckInt(info.CursorCol, 3, 'cursor column kept');
    CheckInt(info.CursorRow, 6, 'cursor row kept');
    CheckInt(info.FormulasLost, 0, 'every formula came back');
    for i := 1 to 5 do
      CheckStr(B.Sheet.Find(i, 1).Raw, A.Sheet.Find(i, 1).Raw, 'label ' + IntToStr(i));
    for i := 1 to 5 do
      CheckStr(B.Sheet.Find(i, 2).Raw, A.Sheet.Find(i, 2).Raw, 'number ' + IntToStr(i));
    for i := 1 to 13 do
      if i <> 12 then CheckStr(B.Sheet.Find(i, 3).Raw, A.Sheet.Find(i, 3).Raw, 'formula ' + IntToStr(i));
    CheckStr(B.Sheet.Find(12, 3).Raw, '@SUM($B$1..$B$3)', 'range names are saved as addresses');
    B.Calc.Recalc;
    CheckStr(Shown(B, 1, 3), Shown(A, 1, 3), 'formula value after loading');
    CheckStr(Shown(B, 4, 3), Shown(A, 4, 3), 'string formula after loading');
    CheckStr(Shown(B, 7, 3), Shown(A, 7, 3), 'PMT after loading');
    CheckStr(Shown(B, 8, 3), 'NA', 'NA after loading');
    CheckStr(Shown(B, 9, 3), 'ERR', 'ERR after loading');
    for i := 1 to 9 do
    begin
      cell := A.Sheet.Find(i, 4);
      CheckStr(FormatTag(B.Sheet.Find(i, 4).Fmt), FormatTag(cell.Fmt), 'format of row ' + IntToStr(i));
    end;
    CheckInt(B.Sheet.ColWidth(2), 14, 'column width');
    CheckInt(B.Sheet.ColWidth(5), 3, 'second column width');
    CheckInt(B.Sheet.ColWidth(1), 11, 'global width');
    CheckStr(FormatTag(B.Sheet.GlobalFmt), 'F2', 'global format');
    CheckStr(B.Sheet.GlobalLabelPrefix, '"', 'global label prefix');
    Check(B.Sheet.RecalcOrder = roRowwise, 'recalculation order');
    Check(B.Sheet.RecalcManual, 'manual recalculation');
    CheckInt(B.Sheet.Iterations, 4, 'iteration count');
    CheckInt(B.Sheet.TitleR2, 2, 'title rows');
    CheckInt(B.Sheet.TitleC2, 1, 'title columns');
    Check(B.Sheet.FindName('PRICES', B.PendRange) and (B.PendRange.R2 = 3) and (B.PendRange.C1 = 2), 'range name saved');

    { the original release format }
    msg := SaveWorksheet(dir + '/rt.wks', A.Sheet, True, info, warn);
    CheckStr(msg, '', 'WKS save');
    B.Sheet.Reset;
    msg := LoadWorksheet(dir + '/rt.wks', B.Sheet, warn, info);
    CheckStr(msg, '', 'WKS load');
    CheckInt(info.Version, $0404, 'WKS version');
    CheckStr(B.Sheet.Find(1, 3).Raw, '+B1*2', 'WKS formula');
    CheckStr(B.Sheet.Find(5, 1).Raw, A.Sheet.Find(5, 1).Raw, 'WKS label');

    { damaged and foreign files }
    WriteTextFile(dir + '/junk.wk1', 'this is not a worksheet');
    CheckStr(LoadWorksheet(dir + '/junk.wk1', B.Sheet, nil, info), 'Not a worksheet file', 'junk is refused');
    Check(B.Sheet.Find(1, 3) <> nil, 'a refused file leaves the sheet alone');
    WriteBytesFile(dir + '/sym.wk1', Bytes('00000200' + '0504' + '0100' + '0000'));
    CheckStr(LoadWorksheet(dir + '/sym.wk1', B.Sheet, nil, info), 'Symphony files are not supported', 'Symphony is refused');
    CheckStr(LoadWorksheet(dir + '/missing.wk1', B.Sheet, nil, info), 'Cannot open missing.wk1', 'missing file');
    { truncated in the middle of a record: the earlier records still load }
    WriteBytesFile(dir + '/trunc.wk1', Bytes('0000020006040D000700' + '000000000000' ));
    warn.Clear;
    CheckStr(LoadWorksheet(dir + '/trunc.wk1', B.Sheet, warn, info), '', 'truncated file loads what it can');
    Check(warn.Count > 0, 'and says so');
    { a formula with an opcode we do not know keeps its value }
    WriteBytesFile(dir + '/odd.wk1', Bytes('0000020006040E000D00' + '00' + '0000' + '0000' + '0000000000002440' +
      '10001B00' + '00' + '0000' + '0100' + '0000000000002840' + '0300' + '7F03' + '000000000000000000'));
    warn.Clear;
    msg := LoadWorksheet(dir + '/odd.wk1', B.Sheet, warn, info);
    CheckStr(msg, '', 'odd file loads');
  finally
    warn.Free;
    A.Free;
    B.Free;
    CleanDir(dir);
  end;
end;

procedure TestImport;
var
  S: TSession;
  dir: string;
  msg: string;
begin
  dir := TmpDir;
  S := TSession.Create;
  try
    WriteTextFile(dir + '/lines.txt', 'first line'#13#10'  second'#10#10'caf' + #$82 + #13#10#26'ignored');
    CheckStr(ImportLines(S.Sheet, dir + '/lines.txt', 2, 3), '', 'import lines');
    CheckStr(RawAt(S, 2, 3), '''first line', 'first line is a label');
    CheckStr(RawAt(S, 3, 3), '''  second', 'spaces are kept');
    Check(S.Sheet.Find(4, 3) = nil, 'blank line leaves the cell empty');
    CheckStr(RawAt(S, 5, 3), '''caf' + UTF8Encode(WideChar($E9)), 'CP437 text is converted');
    Check(S.Sheet.Find(6, 3) = nil, 'text after the DOS end-of-file mark is ignored');
    S.Sheet.GlobalLabelPrefix := '"';
    ImportLines(S.Sheet, dir + '/lines.txt', 20, 1);
    CheckStr(RawAt(S, 20, 1), '"first line', 'lines use the global label prefix');

    WriteTextFile(dir + '/nums.prn', '1 2.5 "name" ' + '''x y'' 7 junk -3,4'#13#10'"q"'#13#10);
    S.Sheet.Clear;
    CheckStr(ImportNumbers(S.Sheet, dir + '/nums.prn', 1, 1), '', 'import numbers');
    CheckStr(RawAt(S, 1, 1), '1', 'first number');
    CheckStr(RawAt(S, 1, 2), '2.5', 'second number');
    CheckStr(RawAt(S, 1, 3), '"name', 'quoted text is a label');
    CheckStr(RawAt(S, 1, 4), '"x y', 'single-quoted text too');
    CheckStr(RawAt(S, 1, 5), '7', 'number after quoted text');
    CheckStr(RawAt(S, 1, 6), '-3', 'junk is skipped, comma separates');
    CheckStr(RawAt(S, 1, 7), '4', 'next number');
    CheckStr(RawAt(S, 2, 1), '"q', 'second line');

    WriteTextFile(dir + '/data.csv', 'name,qty,price'#13#10'"Smith, J",3,4.5'#13#10'plain,,"12"'#13#10'"say ""hi""",-1,x'#13#10);
    S.Sheet.Clear;
    S.Sheet.GlobalLabelPrefix := '''';
    CheckStr(ImportNumbers(S.Sheet, dir + '/data.csv', 1, 1), '', 'import CSV');
    CheckStr(RawAt(S, 1, 1), '''name', 'CSV header');
    CheckStr(RawAt(S, 2, 1), '''Smith, J', 'comma inside quotes');
    CheckStr(RawAt(S, 2, 2), '3', 'CSV number');
    CheckStr(RawAt(S, 2, 3), '4.5', 'CSV decimal');
    Check(S.Sheet.Find(3, 2) = nil, 'empty field leaves the cell empty');
    CheckStr(RawAt(S, 3, 3), '''12', 'a quoted number stays text');
    CheckStr(RawAt(S, 4, 1), '''say "hi"', 'doubled quotes');
    CheckStr(RawAt(S, 4, 3), '''x', 'unquoted text in CSV is a label');
    msg := ImportNumbers(S.Sheet, dir + '/nothere.csv', 1, 1);
    CheckStr(msg, 'Cannot open nothere.csv', 'missing import file');
  finally
    S.Free;
    CleanDir(dir);
  end;
end;

procedure TestFileCommands;
var
  dir, old: string;
  S2: TSession;
  Ctl2: TController;
  Cmds2: TCommands;
  q: TKeyQueue;

  procedure Go(const keys: string);
  begin
    q.PushString(keys);
    while not q.Empty do Ctl2.HandleKey(q.Pop);
  end;

begin
  dir := TmpDir;
  old := GetCurrentDir;
  SetCurrentDir(dir);
  S2 := TSession.Create;
  Cmds2 := TCommands.Create;
  RegisterCoreCommands(Cmds2);
  Ctl2 := TController.Create(S2, Cmds2);
  q := TKeyQueue.Create;
  try
    S2.Sheet.Put(1, 1, '5');
    S2.Sheet.Put(2, 1, '+A1*3');
    S2.Sheet.Put(1, 2, '''label');
    S2.Calc.Recalc;

    Go('/fs');
    Check((S2.Mode = mPrompt) and S2.PromptIsText, 'save asks for a name');
    CheckStr(S2.PromptText, 'Enter name of file to save:', 'save prompt text');
    Go('budget'#13);
    Check(FileExists(dir + '/budget.WK1'), 'the extension is added');
    CheckStr(S2.FileName, 'budget.WK1', 'the session remembers the file');
    CheckStr(S2.Msg, 'Saved budget.WK1', 'saved message');

    { saving over a file asks first }
    Go('/fs');
    CheckStr(S2.Entry, 'budget.WK1', 'the prompt offers the current name');
    Go(#13);
    Check(S2.Mode = mNames, 'asks whether to replace');
    CheckStr(S2.NameChoices.CommaText, 'Cancel,Replace', 'cancel or replace');
    Go(#27);
    Check(S2.Mode = mReady, 'esc cancels the question');
    S2.Sheet.Put(3, 1, '99');
    Go('/fs'#13);
    Ctl2.HandleKey(kRight);
    Ctl2.HandleKey(kEnter);
    Check(S2.Mode = mReady, 'replace saved the file');
    CheckStr(S2.Msg, 'Saved budget.WK1', 'replaced message');

    { retrieve into a fresh session }
    S2.Sheet.Reset;
    S2.Calc.Recalc;
    Check(S2.Sheet.Count = 0, 'sheet erased');
    Go('/fr');
    Go('BUDGET'#13);
    CheckStr(RawAt(S2, 1, 1), '5', 'retrieved a number');
    CheckStr(RawAt(S2, 2, 1), '+A1*3', 'retrieved a formula');
    CheckStr(Shown(S2, 2, 1), '15', 'formula calculated after retrieve');
    CheckStr(RawAt(S2, 1, 2), '''label', 'retrieved a label');
    Check(not S2.HasUndo, 'retrieve clears undo');
    Go('/fr');
    Go('nothing'#13);
    CheckStr(S2.Msg, 'File not found: nothing', 'missing file message');
    Check(S2.Sheet.Count > 0, 'a missing file leaves the sheet alone');
    WriteTextFile(dir + '/bad.wk1', 'not a worksheet');
    Go('/fr');
    Go('bad.wk1'#13);
    CheckStr(S2.Msg, 'Not a worksheet file', 'bad file message');
    Check(S2.Sheet.Count > 0, 'a refused file leaves the sheet alone');

    { F3 lists the files }
    Go('/fr');
    Go(#0);
    Ctl2.HandleKey(kF1 + 2);
    Check(S2.Mode = mNames, 'F3 lists files');
    CheckStr(S2.NameChoices.CommaText, 'bad.wk1,budget.WK1', 'only worksheet files are listed');
    Ctl2.HandleKey(kEsc);
    Ctl2.HandleKey(kEsc);

    { import }
    WriteTextFile(dir + '/in.txt', 'alpha'#10'beta'#10);
    S2.CurRow := 10;
    S2.CurCol := 2;
    Go('/fit');
    Go('in.txt'#13);
    CheckStr(RawAt(S2, 10, 2), '''alpha', 'import text at the pointer');
    CheckStr(RawAt(S2, 11, 2), '''beta', 'second line');
    Ctl2.HandleKey(kAltF1 + 3);
    Check(S2.Sheet.Find(10, 2) = nil, 'undo removes the import');

    { xtract values, then combine }
    Go('/fxv');
    Go('part'#13);
    Check(S2.Mode = mPoint, 'xtract asks for a range');
    Go('a1.a2'#13);
    Check(FileExists(dir + '/part.WK1'), 'xtract wrote a file');
    S2.Sheet.Reset;
    S2.CurRow := 1; S2.CurCol := 1;
    Go('/fr');
    Go('part'#13);
    CheckStr(RawAt(S2, 2, 1), '15', 'xtract values turned the formula into its value');
    S2.Sheet.Put(2, 1, '100');
    Go('/fcaE');
    Go('part'#13);
    CheckStr(RawAt(S2, 2, 1), '115', 'combine add adds the numbers');
    Go('/fcsE');
    Go('part'#13);
    CheckStr(RawAt(S2, 2, 1), '100', 'combine subtract subtracts them');
    S2.Sheet.Put(5, 5, '''keep');
    S2.CurRow := 5;
    S2.CurCol := 5;
    Go('/fccE');
    Go('part'#13);
    CheckStr(RawAt(S2, 5, 5), '5', 'combine copy puts the file at the pointer');
    CheckStr(RawAt(S2, 6, 5), '15', 'second row');
    Ctl2.HandleKey(kAltF1 + 3);
    CheckStr(RawAt(S2, 5, 5), '''keep', 'undo of combine');

    { directory, list, erase }
    Go('/fd');
    CheckStr(S2.Entry, dir, 'directory prompt shows the current directory');
    Ctl2.HandleKey(kEsc);
    Go('/flw');
    Check(S2.Mode = mNames, 'list shows files');
    Ctl2.HandleKey(kEsc);
    Go('/few');
    Go('part'#13);
    Check(not FileExists(dir + '/part.WK1'), 'erase deleted the file');
    CheckStr(S2.Msg, 'Erased part.WK1', 'erase message');
  finally
    SetCurrentDir(old);
    q.Free;
    Ctl2.Free;
    Cmds2.Free;
    S2.Free;
    CleanDir(dir);
  end;
end;

{ ---- @functions ---- }
function FixedClock: Double;
begin
  Result := 36526.5;          { 1-Jan-2000, noon }
end;

function NumA1(const f: string): Double;
var
  X: TSession;
begin
  X := TSession.Create;
  try
    X.Sheet.Put(1, 1, f);
    X.Calc.Recalc;
    if X.Sheet.Find(1, 1).Val.Kind = vkNum then Result := X.Sheet.Find(1, 1).Val.Num
    else Result := NaN;
  finally
    X.Free;
  end;
end;

procedure CheckNum(const f: string; want: Double);
begin
  Inc(Total);
  if IsNan(NumA1(f)) or (Abs(NumA1(f) - want) > 1e-6 * (1 + Abs(want))) then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', f, ': got ', EvalA1(f), ' want ', want:0:9);
  end;
end;

procedure CheckText(const f, want: string);
begin
  CheckStr(EvalA1(f), want, f);
end;

procedure TestFunctions;
const
  StatData: array[0..7] of Integer = (2, 4, 4, 4, 5, 5, 7, 9);
var
  X: TSession;
  i: Integer;
  w: TStringList;
  info: TFileInfo;
  dir: string;
  msg: string;
begin
  fn_time.ClockNow := @FixedClock;

  { math }
  CheckNum('@ABS(-3)', 3);
  CheckNum('@INT(-3.7)', -3);
  CheckNum('@SQRT(16)', 4);
  CheckText('@SQRT(-1)', 'ERR');
  CheckNum('@LOG(100)', 2);
  CheckText('@LOG(0)', 'ERR');
  CheckNum('@LN(1)', 0);
  CheckNum('@EXP(0)', 1);
  CheckText('@EXP(1000)', 'ERR');
  CheckNum('@PI', Pi);
  CheckNum('@SIN(0)', 0);
  CheckNum('@COS(0)', 1);
  CheckNum('@TAN(0)', 0);
  CheckNum('@ATAN(1)*4', Pi);
  CheckNum('@ATAN2(1,1)', Pi / 4);
  CheckNum('@ATAN2(-1,0)', Pi);
  CheckNum('@ASIN(1)', Pi / 2);
  CheckText('@ASIN(2)', 'ERR');
  CheckNum('@ACOS(1)', 0);
  CheckNum('@MOD(7,3)', 1);
  CheckNum('@MOD(-7,3)', -1);
  CheckText('@MOD(5,0)', 'ERR');
  CheckNum('@ROUND(2.5,0)', 3);
  CheckNum('@ROUND(-2.5,0)', -3);
  CheckNum('@ROUND(1234.5678,2)', 1234.57);
  CheckNum('@ROUND(1234,-2)', 1200);
  CheckNum('@RAND#AND#1', 1);

  { logic }
  CheckNum('@IF(1,5,6)', 5);
  CheckNum('@IF(0,5,6)', 6);
  CheckNum('@IF(1,5,1/0)', 5);
  CheckNum('@CHOOSE(1,10,20,30)', 20);
  CheckNum('@CHOOSE(0,10,20,30)', 10);
  CheckText('@CHOOSE(5,1,2)', 'ERR');
  CheckNum('@ISNA(@NA)', 1);
  CheckNum('@ISNA(@ERR)', 0);
  CheckNum('@ISERR(@ERR)', 1);
  CheckNum('@ISERR(5)', 0);
  CheckNum('@ISNUMBER(5)', 1);
  CheckNum('@ISNUMBER("a")', 0);
  CheckNum('@ISSTRING("a")', 1);
  CheckNum('@TRUE+@FALSE', 1);

  { text }
  CheckNum('@LENGTH("hello")', 5);
  CheckText('@LEFT("hello",2)', 'he');
  CheckText('@RIGHT("hello",2)', 'lo');
  CheckText('@RIGHT("hi",9)', 'hi');
  CheckText('@MID("hello",1,3)', 'ell');
  CheckText('@MID("hello",9,3)', '');
  CheckText('@REPEAT("ab",3)', 'ababab');
  CheckText('@UPPER("abc")', 'ABC');
  CheckText('@LOWER("ABC")', 'abc');
  CheckText('@PROPER("hello wORLD 3x")', 'Hello World 3X');
  CheckText('@TRIM("  a   b  ")', 'a b');
  CheckNum('@EXACT("a","A")', 0);
  CheckNum('@EXACT("a","a")', 1);
  CheckText('@REPLACE("abcdef",1,2,"XY")', 'aXYdef');
  CheckNum('@FIND("c","abcabc",0)', 2);
  CheckNum('@FIND("c","abcabc",3)', 5);
  CheckText('@FIND("z","abc",0)', 'ERR');
  CheckText('@STRING(3.14159,2)', '3.14');
  CheckNum('@VALUE("12.5")', 12.5);
  CheckText('@VALUE("abc")', 'ERR');
  CheckText('@CHAR(65)', 'A');
  CheckNum('@CODE("A")', 65);
  CheckNum('@CODE(@CHAR(233))', 233);

  { dates and times (clock fixed at 1-Jan-2000 noon) }
  CheckNum('@DATE(100,1,1)', 36526);
  CheckNum('@DATE(96,2,29)', 35124);
  CheckText('@DATE(96,2,30)', 'ERR');
  CheckText('@DATE(1996,1,1)', 'ERR');
  CheckNum('@DAY(35124)', 29);
  CheckNum('@MONTH(35124)', 2);
  CheckNum('@YEAR(35124)', 96);
  CheckNum('@NOW', 36526.5);
  CheckNum('@TIME(12,0,0)', 0.5);
  CheckText('@TIME(24,0,0)', 'ERR');
  CheckNum('@HOUR(0.75)', 18);
  CheckNum('@MINUTE(@TIME(1,23,45))', 23);
  CheckNum('@SECOND(@TIME(1,23,45))', 45);
  CheckNum('@DATEVALUE("29-Feb-96")', 35124);
  CheckNum('@DATEVALUE("2/29/96")', 35124);
  CheckNum('@DATEVALUE("Mar-96")', 35125);
  CheckNum('@DATEVALUE("15-Jun")', 36692);
  CheckText('@DATEVALUE("nonsense")', 'ERR');
  CheckNum('@TIMEVALUE("1:30 PM")', 0.5625);
  CheckNum('@TIMEVALUE("13:30:00")', 0.5625);
  CheckNum('@TIMEVALUE("12:00 AM")', 0);

  { financial }
  CheckNum('@PMT(1000,0.01,12)', 1000 * 0.01 / (1 - Power(1.01, -12)));
  CheckNum('@PV(100,0.01,12)', 100 * (1 - Power(1.01, -12)) / 0.01);
  CheckNum('@FV(100,0.01,12)', 100 * (Power(1.01, 12) - 1) / 0.01);
  CheckNum('@PV(100,0,12)', 1200);
  CheckNum('@TERM(100,0.01,1200)', Ln(1 + 1200 * 0.01 / 100) / Ln(1.01));
  CheckNum('@CTERM(0.1,2000,1000)', Ln(2) / Ln(1.1));
  CheckNum('@RATE(2000,1000,10)', Power(2, 0.1) - 1);
  CheckNum('@SLN(1000,100,9)', 100);
  CheckNum('@SYD(1000,100,3,1)', 450);
  CheckNum('@SYD(1000,100,3,3)', 150);
  CheckNum('@DDB(1000,100,5,1)', 400);
  CheckNum('@DDB(1000,100,5,2)', 240);
  CheckNum('@DDB(1000,100,5,5)', 29.6);
  CheckText('@SLN(1,1,0)', 'ERR');

  { statistics, lookup, information, database }
  X := TSession.Create;
  try
    for i := 1 to 8 do X.Sheet.Put(i, 2, IntToStr(StatData[i - 1]));
    X.Sheet.Put(1, 4, '4');
    X.Sheet.Put(2, 4, '6');
    X.Sheet.Put(3, 4, '''text');
    X.Sheet.Put(1, 5, '-100');
    X.Sheet.Put(2, 5, '60');
    X.Sheet.Put(3, 5, '60');
    X.Sheet.Put(1, 6, '10'); X.Sheet.Put(1, 7, '1');
    X.Sheet.Put(2, 6, '20'); X.Sheet.Put(2, 7, '2');
    X.Sheet.Put(3, 6, '30'); X.Sheet.Put(3, 7, '3');
    X.Sheet.Put(5, 6, '''a'); X.Sheet.Put(5, 7, '''b');
    X.Sheet.Put(6, 6, '5'); X.Sheet.Put(6, 7, '6');
    X.Sheet.Put(2, 9, '7').Fmt := MakeFormat(fkCurrency, 2);
    X.Sheet.SetColWidth(9, 14);
    X.Sheet.Put(3, 9, '''lbl');
    { database: names in column K, amounts in L }
    X.Sheet.Put(1, 11, '''Name'); X.Sheet.Put(1, 12, '''Amt');
    X.Sheet.Put(2, 11, '''Smith'); X.Sheet.Put(2, 12, '10');
    X.Sheet.Put(3, 11, '''Smyth'); X.Sheet.Put(3, 12, '20');
    X.Sheet.Put(4, 11, '''Jones'); X.Sheet.Put(4, 12, '30');
    X.Sheet.Put(5, 11, '''Smith'); X.Sheet.Put(5, 12, '40');
    X.Sheet.Put(10, 11, '''Name'); X.Sheet.Put(11, 11, '''Smith');
    X.Sheet.Put(10, 13, '''Name'); X.Sheet.Put(11, 13, '''Sm?th'); X.Sheet.Put(12, 13, '''Jones');
    X.Sheet.Put(10, 14, '''Amt'); X.Sheet.Put(11, 14, '''>15');
    X.Sheet.Put(1, 15, '@AVG(B1..B8)');
    X.Sheet.Put(2, 15, '@STD(B1..B8)');
    X.Sheet.Put(3, 15, '@VAR(B1..B8)');
    X.Sheet.Put(4, 15, '@AVG(D1..D4)');
    X.Sheet.Put(5, 15, '@COUNT(D1..D4)');
    X.Sheet.Put(6, 15, '@MIN(D1..D4)');
    X.Sheet.Put(7, 15, '@MAX(D1..D4)');
    X.Sheet.Put(8, 15, '@NPV(0.1,D1..D2)');
    X.Sheet.Put(9, 15, '@IRR(0.1,E1..E3)');
    X.Sheet.Put(10, 15, '@VLOOKUP(25,F1..G3,1)');
    X.Sheet.Put(11, 15, '@VLOOKUP(5,F1..G3,1)');
    X.Sheet.Put(8, 6, '10'); X.Sheet.Put(8, 7, '20'); X.Sheet.Put(8, 8, '30');
    X.Sheet.Put(9, 6, '1'); X.Sheet.Put(9, 7, '2'); X.Sheet.Put(9, 8, '3');
    X.Sheet.Put(12, 15, '@HLOOKUP(25,F8..H9,1)');
    X.Sheet.Put(13, 15, '@VLOOKUP("a",F5..G6,1)');
    X.Sheet.Put(14, 15, '@INDEX(F1..G3,1,2)');
    X.Sheet.Put(15, 15, '@COLS(F1..G3)*10+@ROWS(F1..G3)');
    X.Sheet.Put(16, 15, '@N(D3)+@N(D2)');
    X.Sheet.Put(17, 15, '+@S(D3)&@S(D2)');
    X.Sheet.Put(18, 15, '@CELL("address",C7)');
    X.Sheet.Put(19, 15, '@CELL("col",C7)*100+@CELL("row",C7)');
    X.Sheet.Put(20, 15, '@CELL("type",D1)');
    X.Sheet.Put(21, 15, '@CELL("type",D3)');
    X.Sheet.Put(22, 15, '@CELL("type",D9)');
    X.Sheet.Put(23, 15, '@CELL("format",I2)');
    X.Sheet.Put(24, 15, '@CELL("width",I2)');
    X.Sheet.Put(25, 15, '@CELL("prefix",I3)');
    X.Sheet.Put(26, 15, '@CELLPOINTER("address")');
    X.Sheet.Put(27, 15, '@@("D2")*2');
    X.Sheet.Put(28, 15, '@DSUM(K1..L5,1,K10..K11)');
    X.Sheet.Put(29, 15, '@DCOUNT(K1..L5,1,K10..K11)');
    X.Sheet.Put(30, 15, '@DSUM(K1..L5,1,M10..M12)');
    X.Sheet.Put(31, 15, '@DAVG(K1..L5,1,N10..N11)');
    X.Sheet.Put(32, 15, '@DMAX(K1..L5,1,K10..K11)');
    X.Sheet.Put(33, 15, '@DMIN(K1..L5,1,K10..K11)');
    X.Sheet.Put(34, 15, '@DSTD(K1..L5,1,K10..K11)');
    X.Sheet.Put(35, 15, '@DSUM(K1..L5,1,N10..N11)');
    X.Sheet.Put(36, 15, '@DSUM(K1..L5,5,K10..K11)');
    X.Sheet.PointerRow := 4;
    X.Sheet.PointerCol := 2;
    X.Calc.Recalc;
    CheckStr(Shown(X, 1, 15), '5', 'AVG');
    CheckStr(Shown(X, 2, 15), '2', 'STD is the population deviation');
    CheckStr(Shown(X, 3, 15), '4', 'VAR is the population variance');
    CheckStr(Shown(X, 4, 15), '3.3333333333', 'AVG counts text as zero');
    CheckStr(Shown(X, 5, 15), '3', 'COUNT counts every non-empty cell');
    CheckStr(Shown(X, 6, 15), '0', 'MIN treats text as zero');
    CheckStr(Shown(X, 7, 15), '6', 'MAX');
    Check(Abs(X.Sheet.Find(8, 15).Val.Num - (4 / 1.1 + 6 / 1.21)) < 1e-9, 'NPV');
    Check(Abs(X.Sheet.Find(9, 15).Val.Num - 0.1306623863) < 1e-8, 'IRR');
    CheckStr(Shown(X, 10, 15), '2', 'VLOOKUP finds the last key not above x');
    CheckStr(Shown(X, 11, 15), 'ERR', 'VLOOKUP below the first key is ERR (as in the original)');
    CheckStr(Shown(X, 12, 15), '2', 'HLOOKUP');
    CheckStr(Shown(X, 13, 15), 'b', 'VLOOKUP with text is an exact match');
    CheckStr(Shown(X, 14, 15), '3', 'INDEX');
    CheckStr(Shown(X, 15, 15), '23', 'COLS and ROWS');
    CheckStr(Shown(X, 16, 15), '6', 'N');
    CheckStr(Shown(X, 17, 15), 'text', 'S');
    CheckStr(Shown(X, 18, 15), '$C$7', 'CELL address');
    CheckStr(Shown(X, 19, 15), '307', 'CELL col and row');
    CheckStr(Shown(X, 20, 15), 'v', 'CELL type value');
    CheckStr(Shown(X, 21, 15), 'l', 'CELL type label');
    CheckStr(Shown(X, 22, 15), 'b', 'CELL type blank');
    CheckStr(Shown(X, 23, 15), 'C2', 'CELL format');
    CheckStr(Shown(X, 24, 15), '14', 'CELL width');
    CheckStr(Shown(X, 25, 15), '''', 'CELL prefix');
    CheckStr(Shown(X, 26, 15), '$B$4', 'CELLPOINTER');
    CheckStr(Shown(X, 27, 15), '12', '@@');
    CheckStr(Shown(X, 28, 15), '50', 'DSUM with a text criterion');
    CheckStr(Shown(X, 29, 15), '2', 'DCOUNT');
    CheckStr(Shown(X, 30, 15), '100', 'DSUM with wildcard rows (or)');
    CheckStr(Shown(X, 31, 15), 'ERR', 'a > in a label criterion is not an operator: nothing matches');
    CheckStr(Shown(X, 32, 15), '40', 'DMAX');
    CheckStr(Shown(X, 33, 15), '10', 'DMIN');
    CheckStr(Shown(X, 34, 15), '15', 'DSTD');
    CheckStr(Shown(X, 35, 15), '0', 'DSUM with a label that merely starts with >');
    CheckStr(Shown(X, 36, 15), 'ERR', 'DSUM with a field outside the table');
  finally
    X.Free;
  end;

  { function formulas through the file format }
  dir := TmpDir;
  X := TSession.Create;
  w := TStringList.Create;
  try
    X.Sheet.Put(1, 1, '@CHOOSE(1,10,20,30)');
    X.Sheet.Put(2, 1, '@IF(@ISNA(@NA),@LENGTH("abc"),0)');
    X.Sheet.Put(3, 1, '@@("A1")+@SUM(1,2)');
    X.Sheet.Put(4, 1, '@SLN(1000,100,9)');
    X.Calc.Recalc;
    FillChar(info, SizeOf(info), 0);
    info.CursorCol := 1; info.CursorRow := 1; info.LeftCol := 1; info.TopRow := 1;
    msg := SaveWorksheet(dir + '/f.wk1', X.Sheet, False, info, w);
    CheckStr(msg, '', 'save formulas with functions');
    X.Sheet.Reset;
    msg := LoadWorksheet(dir + '/f.wk1', X.Sheet, nil, info);
    CheckStr(msg, '', 'load them back');
    X.Calc.Recalc;
    CheckStr(X.Sheet.Find(1, 1).Raw, '@CHOOSE(1,10,20,30)', 'list function round trip');
    CheckStr(Shown(X, 1, 1), '20', 'CHOOSE value after the file');
    CheckStr(X.Sheet.Find(2, 1).Raw, '@IF(@ISNA(@NA),@LENGTH("abc"),0)', 'nested functions');
    CheckStr(Shown(X, 2, 1), '3', 'nested value');
    CheckStr(X.Sheet.Find(3, 1).Raw, '@@("A1")+@SUM(1,2)', '@@ round trip');
    CheckStr(X.Sheet.Find(4, 1).Raw, '@SLN(1000,100,9)', 'financial functions have file codes now');
    CheckInt(w.Count, 0, 'so saving them raises no warning');
  finally
    w.Free;
    X.Free;
    CleanDir(dir);
  end;
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


  { ---- phase 5: editing commands from the keyboard ---- }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  S.Sheet.Put(1, 1, '5');
  S.Sheet.Put(1, 2, '+A1*2');
  S.Calc.Recalc;
  Feed('/c');
  Check(S.Mode = mPoint, '/Copy asks for the FROM range');
  Feed('b1'#13);
  Check(S.Mode = mPoint, '/Copy then asks for the TO range');
  Feed('b2.b4'#13);
  Check(S.Mode = mReady, '/Copy done');
  CheckStr(RawAt(S, 3, 2), '+A3*2', 'copied with adjusted reference');
  CheckStr(RawAt(S, 4, 2), '+A4*2', 'copied down the target');
  Ctl.HandleKey(kAltF1 + 3);
  Check(S.Sheet.Find(2, 2) = nil, 'undo removes the whole copy');
  Ctl.HandleKey(kAltF1 + 3);
  CheckStr(RawAt(S, 4, 2), '+A4*2', 'redo brings it back');
  Ctl.HandleKey(kAltF1 + 3);

  Feed('/m');
  Feed('a1'#13'd1'#13);
  CheckStr(RawAt(S, 1, 4), '5', '/Move moved the cell');
  CheckStr(RawAt(S, 1, 2), '+D1*2', '/Move updated the formula');
  Ctl.HandleKey(kAltF1 + 3);
  CheckStr(RawAt(S, 1, 1), '5', 'undo of a move');
  CheckStr(RawAt(S, 1, 2), '+A1*2', 'undo restores references');

  Feed('/wir');
  Feed('a2'#13);
  CheckStr(RawAt(S, 1, 2), '+A1*2', 'row above the insert point is unchanged');
  S.Sheet.Put(3, 1, '+A1');
  Feed('/wdr');
  Feed('a2'#13);
  CheckStr(RawAt(S, 2, 1), '+A1', 'row deleted');
  Feed('/wic');
  Feed('a1'#13);
  CheckStr(RawAt(S, 1, 2), '5', 'column inserted');
  CheckStr(RawAt(S, 1, 3), '+B1*2', 'column insert adjusts formulas');
  Feed('/wdc');
  Feed('a1'#13);
  CheckStr(RawAt(S, 1, 1), '5', 'column deleted');

  { range names from the keyboard }
  Feed('/rnc');
  Check((S.Mode = mPrompt) and S.PromptIsText, 'name prompt is a text prompt');
  Feed('rate'#13);
  Check(S.Mode = mPoint, 'then the range');
  Feed('a1'#13);
  Check(S.Sheet.FindName('RATE', S.PendRange), 'name created');
  Feed('/rnc');
  Feed('1bad'#13);
  Check(S.Mode = mReady, 'invalid name refused');
  CheckStr(S.Msg, 'Invalid range name', 'with a message');
  Feed('/rnc');
  Feed('other'#13'b1.b2'#13);
  Check(S.Sheet.NameCount = 2, 'second name');

  { F3 lists the names while pointing }
  Feed('/c');
  Ctl.HandleKey(kF1 + 2);
  Check(S.Mode = mNames, 'F3 lists names');
  CheckInt(S.NameChoices.Count, 2, 'both names listed');
  CheckStr(S.NameChoices[0], 'OTHER', 'names are sorted');
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kEnter);
  Check(S.Mode = mPoint, 'picking a name accepts the range');
  Ctl.HandleKey(kEsc);
  Ctl.HandleKey(kEsc);
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'esc leaves the prompt');

  { typing a name where a range is expected }
  Feed('/re');
  Feed('rate'#13);
  Check(S.Sheet.Find(1, 1) = nil, 'range erase accepts a name');

  Feed('/rnd');
  Feed('rate'#13);
  Check(not S.Sheet.FindName('RATE', S.PendRange), 'name deleted');
  Feed('/rnd');
  Feed('rate'#13);
  CheckStr(S.Msg, 'Range name not found', 'deleting a missing name');
  Feed('/rnr');
  CheckInt(S.Sheet.NameCount, 0, 'names reset');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.NameCount, 1, 'undo restores the names');

  { names from labels }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  S.Sheet.Put(1, 1, '''Sales');
  S.Sheet.Put(1, 2, '100');
  S.Sheet.Put(2, 1, '''Cost');
  S.Sheet.Put(2, 2, '40');
  Feed('/rnlr');
  Feed('a1.a2'#13);
  Check(S.Sheet.FindName('SALES', S.PendRange) and (S.PendRange.C1 = 2) and (S.PendRange.R1 = 1), 'label names the cell to its right');
  S.Sheet.Put(4, 1, '+sales-cost');
  S.Calc.Recalc;
  CheckStr(Shown(S, 4, 1), '60', 'formula using label-derived names');
  Feed('/rnt');
  Feed('d1'#13);
  CheckStr(RawAt(S, 1, 4), '''COST', 'name table lists names');
  CheckStr(RawAt(S, 2, 4), '''SALES', 'sorted');
  CheckStr(RawAt(S, 2, 5), '''B1', 'with their ranges');

  { titles }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  S.CurRow := 3;
  S.CurCol := 2;
  S.Normalize;
  Feed('/wtb');
  CheckInt(S.Sheet.TitleR2, 2, 'rows above the pointer are titles');
  CheckInt(S.Sheet.TitleC2, 1, 'columns left of the pointer are titles');
  CheckInt(S.TopRow, 3, 'scrolling starts at the pointer row');
  CheckInt(S.ScrollRows, 18, 'two rows are taken by titles');
  Ctl.HandleKey(kPgDn);
  CheckInt(S.CurRow, 21, 'page down scrolls the free rows only');
  CheckInt(S.TopRow, 21, 'titles stay out of the scrolling');
  Ctl.HandleKey(kUp);
  CheckInt(S.TopRow, 20, 'scrolls back one row');
  S.CurRow := 1;
  S.Normalize;
  CheckInt(S.TopRow, 20, 'moving into the title rows does not scroll');
  Feed('/wtc');
  CheckInt(S.Sheet.TitleR2, 0, 'titles cleared');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.TitleR2, 2, 'undo restores titles');
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '2');
  InsertRows(S.Sheet, 1, 1);
  CheckInt(S.Sheet.TitleR2, 3, 'inserting above the titles moves them');

  S.Free;
  Cmds.Free;
end;

begin
  TestSheet;
  TestJournal;
  TestFormat;
  TestDates;
  TestFormulas;
  TestEditOps;
  TestFunctions;
  TestCharsets;
  TestFormatBytes;
  TestRpn;
  TestRpnDecode;
  TestWk1RoundTrip;
  TestImport;
  TestFileCommands;
  TestMenus;
  TestKeys;
  TestController;
  WriteLn(Total - Fails, '/', Total, ' checks passed');
  if Fails > 0 then Halt(1);
end.
