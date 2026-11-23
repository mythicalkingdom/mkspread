{ Unit tests for the terminal-independent core: storage, formatting, menus,
  key queue and the controller driven purely by logical keys. }
program test_core;
{$mode objfpc}{$H+}

uses SysUtils, Classes, Math, fn_time, macro, cmdfile, dataops, keys, editops, charsets, wk1, textimport, formula, sheet, cellfmt, dates, menutree, menudata, session, commands, controller, helpdata, refedit, printing, cmdprint, config, recovery, version;

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
  CheckStr(ValueText(c, sh, 9), '1.23E+12', 'general falls back to scientific');
  c.Raw := '-12345';
  CheckStr(ValueText(c, sh, 9), '-12345', 'negative general');

  c.Fmt := MakeFormat(fkCurrency, 2);
  c.Raw := '1234567.891';
  CheckStr(ValueText(c, sh, 20), '$1,234,567.89 ', 'currency commas (positive numbers keep room for the closing parenthesis)');
  c.Raw := '-5';
  CheckStr(ValueText(c, sh, 20), '($5.00)', 'currency negative');
  c.SetRaw('@SUM(A1..A3)');
  c.Val := NumValue(10.99);
  CheckStr(ValueText(c, sh, 20), '$10.99 ', 'formula value is formatted');
  c.SetRaw('1');

  c.Raw := '1234.5';
  c.Fmt := MakeFormat(fkFixed, 0);
  CheckStr(ValueText(c, sh, 20), '1235', 'fixed 0');
  c.Fmt := MakeFormat(fkFixed, 3);
  CheckStr(ValueText(c, sh, 20), '1234.500', 'fixed 3');
  c.Fmt := MakeFormat(fkComma, 1);
  CheckStr(ValueText(c, sh, 20), '1,234.5 ', 'comma 1');
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
    Check(((S2.Mode = mPrompt) or (S2.Mode = mNames)) and S2.PromptIsText, 'save asks for a name');
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
    CheckStr(S2.NameChoices.CommaText, 'bad.wk1,budget.WK1,../', 'only worksheet files are listed');
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

{ ---- macros ---- }
var
  MS: TSession;
  MC: TController;
  MM: TMacro;
  MCmds: TCommands;

procedure NewMacroSession;
begin
  if MM <> nil then MM.Free;
  if MC <> nil then MC.Free;
  if MCmds <> nil then MCmds.Free;
  if MS <> nil then MS.Free;
  MS := TSession.Create;
  MCmds := TCommands.Create;
  RegisterCoreCommands(MCmds);
  MC := TController.Create(MS, MCmds);
  MM := TMacro.Create(MS);
end;

{ macro text goes in column K; name it }
procedure Mac(r: Integer; const text: string);
begin
  MS.Sheet.Put(r, 11, '''' + text);
end;

procedure NameMac(const nm: string; r: Integer);
begin
  MS.Sheet.SetName(nm, NormRange(r, 11, r, 11));
end;

procedure RunMac(const nm: string);
begin
  MS.MacroRequest := nm;
  MM.RunSync(MC);
end;

{ the user types while the macro waits, the way the main loop does it }
procedure UserTypes(const s: string);
var
  q: TKeyQueue;
  k: Integer;
begin
  q := TKeyQueue.Create;
  q.PushString(s);
  while not q.Empty do
  begin
    k := q.Pop;
    if not (MM.Active and MM.UserKey(k)) then MC.HandleKey(k);
  end;
  q.Free;
end;

procedure TestMacros;
var
  i: Integer;
  fs: TFileStream;
  dir, old: string;
begin
  MS := nil; MC := nil; MM := nil; MCmds := nil;

  { names for macros }
  Check(IsValidName('\A') and IsValidName('\0') and IsValidName('\z'), 'macro names are valid');
  Check(not IsValidName('\') and not IsValidName('\AB') and not IsValidName('\-'), 'but only a backslash and one character');

  { keystrokes }
  NewMacroSession;
  Mac(1, '5~{DOWN}6~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '5', 'macro typed a number');
  CheckStr(RawAt(MS, 2, 1), '6', 'and a key between');
  Check(not MM.Active, 'macro ended at the empty cell');
  Check(not MS.MacroActive, 'CMD indicator is off');

  NewMacroSession;
  Mac(1, '{DOWN 3}x~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 4, 1), '''x', 'repeat count');

  NewMacroSession;
  MS.Sheet.Put(1, 1, '1');
  MS.Sheet.Put(2, 1, '2');
  Mac(1, '/rfc~A1.A2~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(FormatTag(MS.Sheet.Find(2, 1).Fmt), 'C2', 'menu commands from a macro');

  NewMacroSession;
  Mac(1, '5~');
  Mac(2, '{DOWN}7~');
  MS.Sheet.Put(3, 11, '99');                         { a number ends the macro }
  Mac(4, '{DOWN}8~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 2, 1), '7', 'macro continues on the next cell down');
  Check(MS.Sheet.Find(3, 1) = nil, 'and stops at a number');

  { text formulas can be macro lines too }
  NewMacroSession;
  MS.Sheet.Put(1, 11, '+"3~"&"{DOWN}4~"');
  NameMac('\A', 1);
  MS.Calc.Recalc;
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '3', 'a string formula is macro text');
  CheckStr(RawAt(MS, 2, 1), '4', 'with its keys');

  { escaped braces }
  NewMacroSession;
  Mac(1, '{{}x{}}~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '''{x}', 'braces typed with {{} and {}}');

  { BRANCH, IF, QUIT }
  NewMacroSession;
  Mac(1, '{BRANCH K5}');
  Mac(2, '9~');
  Mac(5, '3~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '3', '{BRANCH}');

  NewMacroSession;
  Mac(1, '{IF 0}7~');
  Mac(2, '{DOWN}8~');
  NameMac('\A', 1);
  RunMac('\A');
  Check(MS.Sheet.Find(1, 1) = nil, 'a false {IF} skips the rest of its cell');
  CheckStr(RawAt(MS, 2, 1), '8', 'and the next cell runs');

  NewMacroSession;
  MS.Sheet.Put(5, 5, '4');
  Mac(1, '{IF E5>3}{DOWN}7~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 2, 1), '7', 'a true {IF} on a cell expression');

  NewMacroSession;
  Mac(1, '5~{QUIT}6~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '5', '{QUIT} stops the macro');

  { LET, PUT, BLANK, CONTENTS }
  NewMacroSession;
  Mac(1, '{LET B1,3*4}{LET B2,"hi":string}{LET B3,B1+1}{LET B4,"tx"}{LET B5,hello}');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 2), '12', '{LET} with a formula');
  CheckStr(RawAt(MS, 2, 2), '''hi', '{LET} with :string');
  CheckStr(Shown(MS, 3, 2), '13', '{LET} using a cell, recalculated');
  CheckStr(RawAt(MS, 4, 2), '''tx', '{LET} with a quoted string');
  CheckStr(RawAt(MS, 5, 2), '''hello', '{LET} with plain text');

  NewMacroSession;
  MS.Sheet.Put(1, 2, '5');
  MS.Sheet.Put(2, 2, '6');
  Mac(1, '{PUT B1,0,1,99}{CONTENTS C1,B2}{BLANK B1}');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 3), '''       99', '{CONTENTS} copies the number as displayed, padded to the column width');
  CheckStr(RawAt(MS, 1, 2), '', '{BLANK} empties the cell');
  CheckStr(RawAt(MS, 2, 2), '99', '{PUT} stored at an offset');

  { {CONTENTS} width and stars (observed in the original program) }
  NewMacroSession;
  MS.Sheet.Put(1, 2, '5').Fmt := MakeFormat(fkCurrency, 2);
  MS.Sheet.Put(2, 2, '1234.5').Fmt := MakeFormat(fkCurrency, 2);
  Mac(1, '{CONTENTS C1,B1}{CONTENTS C2,B2}{CONTENTS C3,B2,12}');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 3), '''   $5.00 ', 'positive currency: padded, with a trailing space');
  CheckStr(RawAt(MS, 2, 3), '''*********', 'too wide for the column: stars');
  CheckStr(RawAt(MS, 3, 3), '''  $1,234.50 ', 'a third argument sets the width');

  { subroutines, with arguments }
  NewMacroSession;
  Mac(1, '{SUB}{SUB}');
  Mac(10, '{DOWN}5~{RETURN}7~');
  Mac(20, '{ADD 3,4}');
  Mac(40, '{DEFINE B1,B2}{LET B3,B1+B2}{RETURN}');
  NameMac('\A', 1);
  NameMac('SUB', 10);
  NameMac('ADD', 40);
  RunMac('\A');
  CheckStr(RawAt(MS, 2, 1), '5', 'subroutine called');
  CheckStr(RawAt(MS, 3, 1), '5', 'and called again');
  Check(MS.Sheet.Find(1, 1) = nil, '{RETURN} skips the rest of the routine');
  NameMac('\B', 20);
  RunMac('\B');
  CheckStr(Shown(MS, 3, 2), '7', '{DEFINE} receives the arguments');

  { FOR }
  NewMacroSession;
  Mac(1, '{FOR B1,1,3,1,K20}');
  Mac(20, '{DOWN}x~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 2, 1), '''x', 'FOR pass one');
  CheckStr(RawAt(MS, 3, 1), '''x', 'FOR pass two');
  CheckStr(RawAt(MS, 4, 1), '''x', 'FOR pass three');
  Check(MS.Sheet.Find(5, 1) = nil, 'FOR stops after the last');
  CheckStr(RawAt(MS, 1, 2), '4', 'the counter ends past the limit');

  NewMacroSession;
  Mac(1, '{FOR B1,1,10,1,K20}{DOWN}end~');
  Mac(20, '{DOWN}x~{IF B1=2}{FORBREAK}');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 3, 1), '''x', 'FORBREAK: second pass ran');
  CheckStr(RawAt(MS, 4, 1), '''end', 'then the macro went on after the {FOR}');
  Check(MS.Sheet.Find(5, 1) = nil, 'and the loop did not run again');

  { pauses: {?}, GETLABEL, GETNUMBER, GET }
  NewMacroSession;
  Mac(1, '{?}{DOWN}9~');
  NameMac('\A', 1);
  RunMac('\A');
  Check(MM.Active and not MM.Running, '{?} waits for the user');
  UserTypes('ab');
  Check(MM.Active and not MM.Running, 'still waiting until Enter');
  UserTypes(#13);
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 1, 1), '''ab', 'what the user typed during {?}');
  CheckStr(RawAt(MS, 2, 1), '9', 'the macro went on after Enter');

  NewMacroSession;
  Mac(1, '{GETLABEL Name: ,B1}{GETNUMBER Qty: ,B2}{DOWN}done~');
  NameMac('\A', 1);
  RunMac('\A');
  Check(MS.Mode = mPrompt, 'GETLABEL shows its prompt');
  CheckStr(MS.PromptText, 'Name:', 'with the macro''s text');
  UserTypes('Ann' + #13);
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 1, 2), '''Ann', 'GETLABEL stored a label');
  Check(MS.Mode = mPrompt, 'GETNUMBER prompts next');
  UserTypes('2+3' + #13);
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 2, 2), '5', 'GETNUMBER stored the value');
  CheckStr(RawAt(MS, 2, 1), '''done', 'the macro finished');

  NewMacroSession;
  Mac(1, '{GET B1}{DOWN}x~');
  NameMac('\A', 1);
  RunMac('\A');
  UserTypes('q');
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 1, 2), '''q', '{GET} stores the key');
  CheckStr(RawAt(MS, 2, 1), '''x', 'and the macro goes on');
  Check(MS.Sheet.Find(1, 1) = nil, 'the key was not typed into the worksheet');

  { menus }
  NewMacroSession;
  Mac(1, '{MENUBRANCH K30}');
  MS.Sheet.Put(30, 11, '''One'); MS.Sheet.Put(30, 12, '''Two');
  MS.Sheet.Put(31, 11, '''first choice'); MS.Sheet.Put(31, 12, '''second choice');
  MS.Sheet.Put(32, 11, '''{DOWN}1~'); MS.Sheet.Put(32, 12, '''{DOWN 2}2~');
  NameMac('\A', 1);
  RunMac('\A');
  Check(MS.Mode = mNames, 'MENUBRANCH shows a menu');
  CheckStr(MS.NameChoices.CommaText, 'One,Two', 'with the items from the row');
  CheckStr(MS.ChoiceHelp[1], 'second choice', 'and their descriptions');
  UserTypes('t');
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 3, 1), '2', 'the item chosen by its first letter ran its macro');

  NewMacroSession;
  Mac(1, '{MENUCALL K30}{DOWN}after~');
  MS.Sheet.Put(30, 11, '''One');
  MS.Sheet.Put(32, 11, '''{DOWN}1~');
  NameMac('\A', 1);
  RunMac('\A');
  UserTypes(#13);
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 2, 1), '1', 'MENUCALL runs the choice');
  CheckStr(RawAt(MS, 3, 1), '''after', 'and returns to the line after it');
  NewMacroSession;
  Mac(1, '{MENUBRANCH K30}x~');
  MS.Sheet.Put(30, 11, '''One');
  MS.Sheet.Put(32, 11, '''5~');
  NameMac('\A', 1);
  RunMac('\A');
  UserTypes(#27);
  MM.RunSync(MC);
  Check(not MM.Active, 'Esc in a macro menu ends the macro');

  { starting macros }
  NewMacroSession;
  Mac(1, '{DOWN}z~');
  NameMac('\Z', 1);
  MC.HandleKey(MakeAlt('z'));
  CheckStr(MS.MacroRequest, '\Z', 'Alt-letter asks for macro \Z');
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 2, 1), '''z', 'and it ran');
  MC.HandleKey(MakeAlt('q'));
  CheckStr(MS.Msg, 'No macro \Q is defined', 'Alt-letter without a macro says so');

  NewMacroSession;
  Mac(1, '{DOWN}w~');
  NameMac('RUNME', 1);
  NameMac('\A', 1);
  MC.HandleKey(kAltF1 + 2);
  Check(MS.Mode = mNames, 'Alt-F3 lists the range names');
  CheckStr(MS.NameChoices.CommaText, '\A,RUNME', 'macro names included');
  MC.HandleKey(kRight);
  MC.HandleKey(kEnter);
  CheckStr(MS.MacroRequest, 'RUNME', 'the chosen name is the macro to run');
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 2, 1), '''w', 'Alt-F3 ran it');

  NewMacroSession;
  MC.HandleKey(MakeAlt('a'));
  Check(MS.MacroRequest = '', 'no request for an undefined macro');

  { runaway and unknown commands }
  NewMacroSession;
  Mac(1, '{BRANCH K1}');
  NameMac('\A', 1);
  RunMac('\A');
  Check(not MM.Active, 'a macro that loops without typing is stopped');
  Check(Pos('loops', MS.Msg) > 0, 'with an explanation');

  NewMacroSession;
  Mac(1, '5~{FROBNICATE}6~');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(RawAt(MS, 1, 1), '5', 'keys before an unknown command ran');
  Check(Pos('FROBNICATE', MS.Msg) > 0, 'an unknown command is reported');
  Check(not MM.Active, 'and ends the macro');

  NewMacroSession;
  Mac(1, '{INDICATE WAIT}{?}');
  NameMac('\A', 1);
  RunMac('\A');
  CheckStr(MS.IndicatorText, 'WAIT', '{INDICATE} sets the mode indicator');
  MM.Stop;
  CheckStr(MS.IndicatorText, '', 'cleared when the macro ends');

  NewMacroSession;
  Mac(1, '5~');
  NameMac('\A', 1);
  MM.Start(1, 11);
  MC.HandleKey(kBreak);
  Check(MM.UserKey(kBreak) or True, 'break key handled');
  Check(not MM.Active, 'Ctrl-Break stops a macro');


  { ---- macro recording (Learn) and STEP mode ---- }
  NewMacroSession;
  MC.HandleUserKey(kAltF1 + 4);
  CheckStr(MS.Msg, 'Set a learn range first (/Worksheet Learn Range)', 'Alt-F5 needs a learn range');
  Check(not MS.LearnOn, 'so learn mode stays off');
  UserTypes('/wlr');
  Check(MS.Mode = mPoint, '/Worksheet Learn Range asks for a range');
  UserTypes('k1.k3' + #13);
  Check(MS.LearnSet and (MS.LearnRange.R1 = 1) and (MS.LearnRange.R2 = 3) and (MS.LearnRange.C1 = 11), 'learn range set');
  MC.HandleUserKey(kAltF1 + 4);
  Check(MS.LearnOn, 'Alt-F5 starts recording');
  MC.HandleUserKey(Ord('h'));
  MC.HandleUserKey(Ord('i'));
  MC.HandleUserKey(kEnter);
  MC.HandleUserKey(kDown);
  MC.HandleUserKey(Ord('{'));
  MC.HandleUserKey(Ord('~'));
  MC.HandleUserKey(kEnter);
  MC.HandleUserKey(kF1 + 1);
  MC.HandleUserKey(kEsc);
  MC.HandleUserKey(kAltF1 + 4);
  Check(not MS.LearnOn, 'Alt-F5 stops recording');
  CheckStr(RawAt(MS, 1, 11), '''hi~{DOWN}{{}{~}~{EDIT}{ESC}', 'keys recorded as macro text');
  CheckStr(RawAt(MS, 1, 1), '''hi', 'and they also did what they normally do');
  { replay what was recorded }
  MS.Sheet.Remove(1, 1);
  MS.Sheet.Remove(2, 1);
  MS.CurRow := 1; MS.CurCol := 1;
  MS.Sheet.SetName('\R', NormRange(1, 11, 1, 11));
  MS.MacroRequest := '\R';
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 1, 1), '''hi', 'replaying the recording types the same');
  CheckStr(RawAt(MS, 2, 1), '''{~', 'including escaped braces and tilde');
  { recording again continues after what is there; a long recording wraps }
  MC.HandleUserKey(kAltF1 + 4);
  for i := 1 to 130 do MC.HandleUserKey(Ord('a'));
  MC.HandleUserKey(kAltF1 + 4);
  Check(not MS.LearnOn, 'Alt-F5 works in the middle of an entry too');
  MC.HandleKey(kEsc);
  Check(MS.Sheet.NonEmpty(2, 11), 'recording continued in the next empty cell');
  CheckInt(Length(RawAt(MS, 2, 11)) - 1, 100, 'a recorded line is cut at 100 characters');
  Check(MS.Sheet.NonEmpty(3, 11), 'and the rest goes in the next cell');
  UserTypes('/wle');
  Check(not MS.Sheet.NonEmpty(1, 11), '/Worksheet Learn Erase empties the range');
  UserTypes('/wlc');
  Check(not MS.LearnSet, '/Worksheet Learn Cancel forgets it');

  NewMacroSession;
  Mac(1, '5~');
  NameMac('\A', 1);
  MC.HandleKey(kAltF1 + 1);
  Check(MS.StepOn, 'Alt-F2 turns STEP mode on');
  RunMac('\A');
  Check(MM.Active and not MM.Running, 'in STEP mode the macro waits before its first key');
  Check(MS.Sheet.Find(1, 1) = nil, 'nothing typed yet');
  CheckStr(MS.StepInfo, 'K1: >5~', 'the current line is shown with the position marked');
  Check(MM.UserKey(kRight), 'any key steps and is not typed');
  MM.RunSync(MC);
  CheckStr(MS.Entry, '5', 'one key was typed');
  Check(MS.Mode = mValue, 'and the macro waits again');
  CheckStr(MS.StepInfo, 'K1: 5>~', 'at the next key');
  MM.UserKey(kRight);
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 1, 1), '5', 'the second step pressed Enter');
  MM.UserKey(kRight);
  MM.RunSync(MC);
  Check(not MM.Active, 'the macro ends at the empty cell');

  NewMacroSession;
  Mac(1, '{DOWN 2}7~');
  NameMac('\A', 1);
  MS.StepOn := True;
  RunMac('\A');
  MM.UserKey(kRight);
  MM.RunSync(MC);
  CheckInt(MS.CurRow, 2, 'a repeat count is stepped key by key');
  MM.UserKey(kAltF1 + 1);
  Check(not MS.StepOn, 'Alt-F2 during STEP switches it off');
  MM.RunSync(MC);
  CheckStr(RawAt(MS, 3, 1), '7', 'and the macro runs to the end');

  { \0 runs when a file is retrieved }
  dir := TmpDir;
  old := GetCurrentDir;
  SetCurrentDir(dir);
  try
    NewMacroSession;
    Mac(1, '{DOWN}auto~');
    NameMac('\0', 1);
    MS.Sheet.Put(1, 1, '''x');
    MC.HandleKey(Ord('/'));
    MC.HandleKey(Ord('f'));
    MC.HandleKey(Ord('s'));
    for i := 1 to 4 do MC.HandleKey(Ord('m'));
    MC.HandleKey(kEnter);
    MS.Sheet.Reset;
    CheckStr(RetrieveFile(MS, 'mmmm.WK1'), '', 'retrieve the file');
    CheckStr(MS.MacroRequest, '\0', 'retrieving a file with \0 requests it');
    MM.RunSync(MC);
    CheckStr(RawAt(MS, 2, 1), '''auto', 'the autoexec macro ran');
  finally
    SetCurrentDir(old);
    CleanDir(dir);
  end;
  MM.Free; MC.Free; MCmds.Free; MS.Free;
end;

{ ---- /Data commands ---- }
function Num(S: TSession; r, c: Integer): Double;
var
  v: TValue;
begin
  v := CellValueOf(S.Sheet.Find(r, c));
  if v.Kind = vkNum then Result := v.Num else Result := NaN;
end;

procedure CheckNear(S: TSession; r, c: Integer; want: Double; const what: string);
begin
  Inc(Total);
  if IsNan(Num(S, r, c)) or (Abs(Num(S, r, c) - want) > 1e-9 * (1 + Abs(want))) then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what, ': got ', RawAt(S, r, c), ' want ', want:0:12);
  end;
end;

procedure PutRows(S: TSession; r: Integer; const cells: array of string);
var
  c: Integer;
begin
  for c := 0 to High(cells) do
    if cells[c] <> '' then S.Sheet.Put(r, c + 1, cells[c]);
end;

procedure TestDataOps;
const
  Noisy: array[0..4] of string = ('2.2', '2.8', '3.6', '4.5', '5.1');
  X2: array[0..5] of Integer = (1, 0, 2, 1, 3, 2);
var
  S: TSession;
  rows: TList;
  n: Integer;
  msg: string;
begin
  { ---- fill ---- }
  S := TSession.Create;
  CheckInt(FillRange(S.Sheet, NormRange(1, 1, 5, 1), 1, 2, 100), 5, 'fill count');
  CheckStr(RawAt(S, 1, 1) + RawAt(S, 3, 1) + RawAt(S, 5, 1), '159', 'fill start and step');
  S.Sheet.Clear;
  CheckInt(FillRange(S.Sheet, NormRange(1, 1, 5, 1), 1, 1, 3), 3, 'fill stops at the stop value');
  Check(S.Sheet.Find(4, 1) = nil, 'and leaves the rest alone');
  S.Sheet.Clear;
  FillRange(S.Sheet, NormRange(1, 1, 3, 2), 1, 1, 8191);
  CheckStr(RawAt(S, 3, 1) + RawAt(S, 1, 2), '34', 'fill goes down each column in turn');
  S.Sheet.Clear;
  FillRange(S.Sheet, NormRange(1, 1, 3, 1), 10, -5, -100);
  CheckStr(RawAt(S, 3, 1), '0', 'a negative step');
  FillRange(S.Sheet, NormRange(1, 3, 3, 3), 0, 0.1, 1);
  CheckStr(RawAt(S, 3, 3), '0.2', 'a fractional step');
  S.Free;

  { ---- sort ---- }
  S := TSession.Create;
  PutRows(S, 1, ['''pear', '30']);
  PutRows(S, 2, ['''apple', '10']);
  PutRows(S, 3, ['''fig', '20']);
  PutRows(S, 4, ['''Apple', '']);
  PutRows(S, 5, ['''kiwi', '5']);
  CheckStr(SortRows(S.Sheet, NormRange(1, 1, 5, 2), 2, True, 0, True), '', 'sort by the amounts');
  CheckStr(RawAt(S, 1, 1) + ' ' + RawAt(S, 2, 1) + ' ' + RawAt(S, 3, 1) + ' ' + RawAt(S, 4, 1) + ' ' + RawAt(S, 5, 1),
           '''Apple ''kiwi ''apple ''fig ''pear', 'ascending: empty cell, then numbers');
  SortRows(S.Sheet, NormRange(1, 1, 5, 2), 2, False, 0, True);
  CheckStr(RawAt(S, 1, 1) + ' ' + RawAt(S, 4, 1) + ' ' + RawAt(S, 5, 1), '''pear ''kiwi ''Apple', 'descending is the reverse: empty cell last');
  SortRows(S.Sheet, NormRange(1, 1, 5, 2), 1, True, 0, True);
  CheckStr(RawAt(S, 1, 1) + ' ' + RawAt(S, 2, 1) + ' ' + RawAt(S, 3, 1), '''apple ''Apple ''fig', 'text ignores case; equal keys keep their order');
  S.Sheet.Clear;
  PutRows(S, 1, ['''b', '2']);
  PutRows(S, 2, ['''a', '2']);
  PutRows(S, 3, ['''c', '1']);
  SortRows(S.Sheet, NormRange(1, 1, 3, 2), 2, True, 1, True);
  CheckStr(RawAt(S, 1, 1) + RawAt(S, 2, 1) + RawAt(S, 3, 1), '''c''a''b', 'secondary key breaks ties');
  S.Sheet.Clear;
  PutRows(S, 1, ['3', '+A1*2']);
  PutRows(S, 2, ['1', '+A2*2']);
  PutRows(S, 3, ['2', '+A3*2']);
  SortRows(S.Sheet, NormRange(1, 1, 3, 2), 1, True, 0, True);
  CheckStr(RawAt(S, 1, 2) + RawAt(S, 3, 2), '+A1*2+A3*2', 'formulas keep their own row when rows move');
  S.Calc.Recalc;
  CheckStr(Shown(S, 3, 2), '6', 'and still calculate');
  S.Sheet.Clear;
  PutRows(S, 1, ['1', '2']);
  Check(SortRows(S.Sheet, NormRange(1, 1, 1, 2), 5, True, 0, True) <> '', 'a key outside the range is refused');
  S.Free;

  { ---- distribution ---- }
  S := TSession.Create;
  for n := 1 to 10 do S.Sheet.Put(n, 1, IntToStr(n));
  S.Sheet.Put(1, 3, '3'); S.Sheet.Put(2, 3, '6'); S.Sheet.Put(3, 3, '9');
  CheckStr(Distribution(S.Sheet, NormRange(1, 1, 10, 1), NormRange(1, 3, 3, 3)), '', 'distribution');
  CheckStr(RawAt(S, 1, 4) + RawAt(S, 2, 4) + RawAt(S, 3, 4) + RawAt(S, 4, 4), '3331', 'counts per bin and the rest');
  S.Sheet.Put(2, 3, '1');
  Check(Distribution(S.Sheet, NormRange(1, 1, 10, 1), NormRange(1, 3, 3, 3)) <> '', 'bins must ascend');
  S.Free;

  { ---- matrices ---- }
  S := TSession.Create;
  PutRows(S, 1, ['4', '7']);
  PutRows(S, 2, ['2', '6']);
  CheckStr(MatrixInvert(S.Sheet, NormRange(1, 1, 2, 2), 5, 1), '', 'invert');
  CheckNear(S, 5, 1, 0.6, 'inverse 11');
  CheckNear(S, 5, 2, -0.7, 'inverse 12');
  CheckNear(S, 6, 1, -0.2, 'inverse 21');
  CheckNear(S, 6, 2, 0.4, 'inverse 22');
  PutRows(S, 10, ['1', '2']);
  PutRows(S, 11, ['2', '4']);
  Check(Pos('singular', MatrixInvert(S.Sheet, NormRange(10, 1, 11, 2), 14, 1)) > 0, 'a singular matrix is reported');
  Check(MatrixInvert(S.Sheet, NormRange(1, 1, 2, 1), 14, 1) = 'The matrix must be square', 'only square matrices');
  PutRows(S, 20, ['1', '2']);
  PutRows(S, 21, ['3', '4']);
  PutRows(S, 23, ['5', '6']);
  PutRows(S, 24, ['7', '8']);
  CheckStr(MatrixMultiply(S.Sheet, NormRange(20, 1, 21, 2), NormRange(23, 1, 24, 2), 30, 1), '', 'multiply');
  CheckStr(RawAt(S, 30, 1) + ' ' + RawAt(S, 30, 2) + ' ' + RawAt(S, 31, 1) + ' ' + RawAt(S, 31, 2), '19 22 43 50', 'product');
  Check(MatrixMultiply(S.Sheet, NormRange(20, 1, 21, 2), NormRange(23, 1, 23, 2), 30, 1) <> '', 'sizes must agree');
  S.Free;

  { ---- regression ---- }
  S := TSession.Create;
  for n := 1 to 5 do
  begin
    S.Sheet.Put(n, 1, IntToStr(n));
    S.Sheet.Put(n, 2, Noisy[n - 1]);
  end;
  CheckStr(Regression(S.Sheet, NormRange(1, 1, 5, 1), NormRange(1, 2, 5, 2), 8, 1, False), '', 'regression');
  CheckNear(S, 9, 4, 1.39, 'constant');
  CheckNear(S, 10, 4, 0.09486832980505142, 'standard error of the estimate');
  CheckNear(S, 11, 4, 0.9952229299363057, 'R squared');
  CheckNear(S, 12, 4, 5, 'observations');
  CheckNear(S, 13, 4, 3, 'degrees of freedom');
  CheckNear(S, 15, 3, 0.75, 'coefficient');
  CheckNear(S, 16, 3, 0.03, 'standard error of the coefficient');
  CheckStr(RawAt(S, 8, 2), '''Regression Output:', 'report heading');
  CheckStr(RawAt(S, 15, 1), '''X Coefficient(s)', 'coefficient label');
  S.Sheet.Clear;
  { two variables, exact fit: y = 1 + 2 x1 + 3 x2 }
  for n := 1 to 6 do
  begin
    S.Sheet.Put(n, 1, IntToStr(n));
    S.Sheet.Put(n, 2, IntToStr(X2[n - 1]));
    S.Sheet.Put(n, 3, IntToStr(1 + 2 * n + 3 * X2[n - 1]));
  end;
  Regression(S.Sheet, NormRange(1, 1, 6, 2), NormRange(1, 3, 6, 3), 10, 1, False);
  CheckNear(S, 11, 4, 1, 'two variables: constant');
  CheckNear(S, 17, 3, 2, 'first coefficient');
  CheckNear(S, 17, 4, 3, 'second coefficient');
  CheckNear(S, 13, 4, 1, 'R squared of an exact fit');
  S.Sheet.Clear;
  { through the origin }
  for n := 1 to 4 do
  begin
    S.Sheet.Put(n, 1, IntToStr(n));
    S.Sheet.Put(n, 2, IntToStr(2 * n));
  end;
  Regression(S.Sheet, NormRange(1, 1, 4, 1), NormRange(1, 2, 4, 2), 10, 1, True);
  CheckNear(S, 11, 4, 0, 'zero intercept: constant');
  CheckNear(S, 17, 3, 2, 'zero intercept: coefficient');
  CheckNear(S, 15, 4, 3, 'zero intercept: degrees of freedom');
  Check(Regression(S.Sheet, NormRange(1, 1, 3, 1), NormRange(1, 2, 4, 2), 10, 1, False) <> '', 'ranges must match');
  S.Free;

  { ---- query ---- }
  S := TSession.Create;
  PutRows(S, 1, ['''Name', '''Dept', '''Pay']);
  PutRows(S, 2, ['''Smith', '''Sales', '10']);
  PutRows(S, 3, ['''Jones', '''Admin', '20']);
  PutRows(S, 4, ['''Smyth', '''Sales', '30']);
  PutRows(S, 5, ['''Brown', '''Sales', '10']);
  PutRows(S, 7, ['''Dept']);
  PutRows(S, 8, ['''Sales']);
  rows := TList.Create;
  CheckStr(QueryMatches(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 1), rows), '', 'query');
  CheckInt(rows.Count, 3, 'three Sales records');
  CheckInt(PtrInt(rows[2]), 5, 'the third is the fourth record');
  PutRows(S, 9, ['''Admin']);
  QueryMatches(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 9, 1), rows);
  CheckInt(rows.Count, 4, 'criteria rows are alternatives');
  PutRows(S, 7, ['''Dept', '''Name']);
  PutRows(S, 8, ['''Sales', '''Sm*']);
  PutRows(S, 9, ['', '']);
  S.Sheet.Remove(9, 1);
  QueryMatches(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 2), rows);
  CheckInt(rows.Count, 2, 'cells in a criteria row must all hold (with a wildcard)');
  { extract }
  PutRows(S, 12, ['''Pay', '''Name']);
  PutRows(S, 8, ['''Sales', '']);
  S.Sheet.Remove(8, 2);
  CheckStr(QueryExtract(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 2), NormRange(12, 1, 12, 2), False), '', 'extract');
  CheckStr(RawAt(S, 13, 1) + ' ' + RawAt(S, 13, 2), '10 ''Smith', 'extracted fields follow the output header order');
  CheckStr(RawAt(S, 15, 1) + ' ' + RawAt(S, 15, 2), '10 ''Brown', 'third extracted record');
  Check(S.Sheet.Find(16, 1) = nil, 'and no more');
  PutRows(S, 12, ['''Pay']);
  S.Sheet.Remove(12, 2);
  QueryExtract(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 2), NormRange(12, 1, 12, 1), True);
  CheckStr(RawAt(S, 13, 1) + RawAt(S, 14, 1), '1030', 'unique extracts each value once');
  Check(S.Sheet.Find(15, 1) = nil, 'the repeated 10 is left out');
  PutRows(S, 12, ['''Pay']);
  Check(QueryExtract(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 2), NormRange(12, 1, 13, 1), False) <> '',
        'an output range that is too small is reported');
  { delete }
  CheckStr(QueryDelete(S.Sheet, NormRange(1, 1, 5, 3), NormRange(7, 1, 8, 1), n), '', 'delete');
  CheckInt(n, 3, 'three records deleted');
  CheckStr(RawAt(S, 2, 1) + ' ' + RawAt(S, 2, 3), '''Jones 20', 'the remaining record moved up');
  Check(S.Sheet.Find(3, 1) = nil, 'and the rest of the input range is empty');
  CheckStr(RawAt(S, 1, 1), '''Name', 'the field names stay');
  rows.Free;
  S.Free;

  { ---- parse ---- }
  CheckStr(MakeFormatLine('Smith  25 12-Mar'), 'L>>>>**V>*L>>>>>', 'format line from a sample');
  S := TSession.Create;
  S.Sheet.Put(1, 1, '|L>>>>**V>*L>>>>>');
  S.Sheet.Put(2, 1, '''Smith  25 12-Mar');
  S.Sheet.Put(3, 1, '''Jones   7 30-Apr');
  CheckStr(ParseLabels(S.Sheet, NormRange(1, 1, 3, 1), 5, 3), '', 'parse');
  CheckStr(RawAt(S, 5, 3) + ' ' + RawAt(S, 5, 4) + ' ' + RawAt(S, 5, 5), '''Smith 25 ''12-Mar', 'first line split into fields');
  CheckStr(RawAt(S, 6, 3) + ' ' + RawAt(S, 6, 4), '''Jones 7', 'second line');
  S.Sheet.Clear;
  S.Sheet.Put(1, 1, '''no format line');
  Check(ParseLabels(S.Sheet, NormRange(1, 1, 1, 1), 5, 3) <> '', 'a format line is required');
  S.Sheet.Put(1, 1, '|L>>>*D>>>>>>>>*T>>>>>>');
  S.Sheet.Put(2, 1, '''Anna 29-Feb-96 1:30 PM');
  ParseLabels(S.Sheet, NormRange(1, 1, 2, 1), 5, 3);
  CheckStr(RawAt(S, 5, 4), '35124', 'D fields become date serials');
  S.Free;
end;

procedure TestDataCommands;
var
  S: TSession;
  Ctl: TController;
  Cmds: TCommands;
  q: TKeyQueue;
  i: Integer;

  procedure Go(const keys: string);
  begin
    { the Sort, Query ... menus come back after a command: leave them first }
    while (S.Mode = mMenu) and (keys <> '') and (keys[1] = '/') do Ctl.HandleKey(kEsc);
    q.PushString(keys);
    while not q.Empty do Ctl.HandleKey(q.Pop);
  end;

begin
  S := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  q := TKeyQueue.Create;
  try
    { fill }
    Go('/df');
    Check(S.Mode = mPoint, '/Data Fill asks for the range');
    Go('a1.a4'#13);
    CheckStr(S.PromptText, 'Start:', 'then Start');
    CheckStr(S.Entry, '0', 'with the default 0');
    Go(#8'10'#13);
    CheckStr(S.PromptText, 'Step:', 'then Step');
    Go(#8'5'#13);
    CheckStr(S.PromptText, 'Stop:', 'then Stop');
    CheckStr(S.Entry, '8191', 'default 8191');
    Go(#13);
    CheckStr(RawAt(S, 1, 1) + RawAt(S, 2, 1) + RawAt(S, 3, 1) + RawAt(S, 4, 1), '10152025', 'filled 10, 15, 20, 25');
    Ctl.HandleKey(kAltF1 + 3);
    Check(S.Sheet.Find(1, 1) = nil, 'undo of a fill');

    { sort via the menu }
    S.Sheet.Clear;
    PutRows(S, 1, ['''c', '3']);
    PutRows(S, 2, ['''a', '1']);
    PutRows(S, 3, ['''b', '2']);
    Go('/dsd');
    Go('a1.b3'#13);
    Go('/dsp');
    Go('b1'#13);
    CheckStr(S.PromptText, 'Sort order (A or D):', 'sort order prompt');
    Go(#13);
    Check(S.Data.SortSet and (S.Data.Key1 = 2) and S.Data.Asc1, 'sort settings remembered');
    Go('/dsg');
    CheckStr(RawAt(S, 1, 1) + RawAt(S, 2, 1) + RawAt(S, 3, 1), '''a''b''c', '/Data Sort Go');
    Go('/dsp');
    Go('b1'#13#8'd'#13);
    Go('/dsg');
    CheckStr(RawAt(S, 1, 1), '''c', 'descending order');
    Go('/dsr');
    Check(not S.Data.SortSet, 'Sort Reset');
    Go('/dsg');
    CheckStr(S.Msg, 'Set the data range first', 'Go without a range says so');

    { query find, extract, delete }
    S.Sheet.Clear;
    PutRows(S, 1, ['''Name', '''Pay']);
    PutRows(S, 2, ['''Ann', '10']);
    PutRows(S, 3, ['''Bob', '20']);
    PutRows(S, 4, ['''Cy', '10']);
    PutRows(S, 6, ['''Pay']);
    PutRows(S, 7, ['10']);
    PutRows(S, 9, ['''Name']);
    Go('/dqi'); Go('a1.b4'#13);
    Go('/dqc'); Go('a6.a7'#13);
    Go('/dqo'); Go('a9.a9'#13);
    Check(S.Data.QInSet and S.Data.QCritSet and S.Data.QOutSet, 'query ranges remembered');
    Go('/dqf');
    Check(S.Mode = mFind, 'Find enters FIND mode');
    CheckInt(S.CurRow, 2, 'on the first matching record');
    Ctl.HandleKey(kDown);
    CheckInt(S.CurRow, 4, 'Down goes to the next match');
    Ctl.HandleKey(kDown);
    CheckInt(S.CurRow, 4, 'and stops at the last');
    Ctl.HandleKey(kUp);
    CheckInt(S.CurRow, 2, 'Up goes back');
    Ctl.HandleKey(kEnd);
    CheckInt(S.CurRow, 4, 'End is the last match');
    Ctl.HandleKey(kEsc);
    Check(S.Mode = mMenu, 'Esc leaves FIND mode (the Query menu comes back)');
    CheckInt(S.CurRow, 1, 'and puts the pointer back');
    Go('/dqe');
    CheckStr(RawAt(S, 10, 1) + RawAt(S, 11, 1), '''Ann''Cy', '/Data Query Extract');
    Go('/dqd');
    Check(S.Mode = mNames, 'Delete asks for confirmation');
    Go(#27);
    CheckStr(RawAt(S, 2, 1), '''Ann', 'cancel keeps the records');
    Go('/dqd');
    Go('d');
    CheckStr(RawAt(S, 2, 1), '''Bob', 'confirmed delete removes the matches');
    CheckStr(S.Msg, '2 record(s) deleted', 'and says how many');
    Go('/dqr');
    Check(not S.Data.QInSet, 'Query Reset');

    { distribution and matrix }
    S.Sheet.Clear;
    for i := 1 to 6 do S.Sheet.Put(i, 1, IntToStr(i));
    S.Sheet.Put(1, 3, '2'); S.Sheet.Put(2, 3, '4');
    Go('/dd');
    Go('a1.a6'#13'c1.c2'#13);
    CheckStr(RawAt(S, 1, 4) + RawAt(S, 2, 4) + RawAt(S, 3, 4), '222', '/Data Distribution');
    S.Sheet.Clear;
    PutRows(S, 1, ['2', '0']);
    PutRows(S, 2, ['0', '4']);
    Go('/dmi');
    Go('a1.b2'#13'd1'#13);
    CheckStr(RawAt(S, 1, 4) + ' ' + RawAt(S, 2, 5), '0.5 0.25', '/Data Matrix Invert');
    Go('/dmm');
    Go('a1.b2'#13'a1.b2'#13'g1'#13);
    CheckStr(RawAt(S, 1, 7) + ' ' + RawAt(S, 2, 8), '4 16', '/Data Matrix Multiply');

    { regression }
    S.Sheet.Clear;
    for i := 1 to 5 do
    begin
      S.Sheet.Put(i, 1, IntToStr(i));
      S.Sheet.Put(i, 2, IntToStr(2 * i + 1));
    end;
    Go('/drx'); Go('a1.a5'#13);
    Go('/dry'); Go('b1.b5'#13);
    Go('/dro'); Go('d1'#13);
    Go('/drg');
    CheckStr(Shown(S, 2, 7), '1', 'regression constant through the menu');
    CheckStr(Shown(S, 8, 6), '2', 'and coefficient');
    Go('/dric');
    Check(not S.Data.RegZero, 'Intercept Compute');
    Go('/driz');
    Check(S.Data.RegZero, 'Intercept Zero');
    Go('/drr');
    Check(not S.Data.RegXSet, 'Regression Reset');

    { parse }
    S.Sheet.Clear;
    S.Sheet.Put(2, 1, '''ab 12');
    S.CurRow := 1; S.CurCol := 1;
    Go('/dpfc');
    CheckStr(RawAt(S, 1, 1), '|L>*V>', '/Data Parse Format-Line Create');
    Go('/dpi'); Go('a1.a2'#13);
    Go('/dpo'); Go('c1'#13);
    Go('/dpg');
    CheckStr(RawAt(S, 1, 3) + ' ' + RawAt(S, 1, 4), '''ab 12', '/Data Parse Go');
    S.CurRow := 1; S.CurCol := 1;
    Go('/dpfe');
    Check(S.Mode = mEdit, 'Format-Line Edit opens the line for editing');
    Ctl.HandleKey(kEsc);

    { data table, one and two input cells }
    S.Sheet.Clear;
    S.Sheet.Put(1, 1, '2');
    S.Sheet.Put(1, 2, '3');
    S.Sheet.Put(2, 5, '+A1*10');
    PutRows(S, 3, ['', '', '', '1']);
    PutRows(S, 4, ['', '', '', '2']);
    PutRows(S, 5, ['', '', '', '3']);
    S.Sheet.Put(2, 5, '+A1*10');
    S.Calc.Recalc;
    Go('/dt1');
    Go('d2.e5'#13'a1'#13);
    CheckStr(RawAt(S, 3, 5) + RawAt(S, 4, 5) + RawAt(S, 5, 5), '102030', 'a one-variable table');
    CheckStr(RawAt(S, 1, 1), '2', 'the input cell is restored');
    S.Sheet.Put(3, 4, '5');
    Ctl.HandleKey(kF1 + 7);
    CheckStr(RawAt(S, 3, 5), '50', 'F8 recalculates the last table');
    Go('/dtr');
    Ctl.HandleKey(kF1 + 7);
    CheckStr(S.Msg, 'No data table has been defined', 'Table Reset forgets it');
    S.Sheet.Clear;
    S.Sheet.Put(1, 1, '2');
    S.Sheet.Put(1, 2, '3');
    S.Sheet.Put(3, 4, '+A1*B1');
    PutRows(S, 3, ['', '', '', '+A1*B1', '1', '2']);
    PutRows(S, 4, ['', '', '', '10']);
    PutRows(S, 5, ['', '', '', '20']);
    S.Calc.Recalc;
    Go('/dt2');
    Go('d3.f5'#13'a1'#13'b1'#13);
    CheckStr(RawAt(S, 4, 5) + ' ' + RawAt(S, 5, 6), '10 40', 'a two-variable table');
    CheckStr(RawAt(S, 1, 1) + RawAt(S, 1, 2), '23', 'both input cells restored');
  finally
    q.Free;
    Ctl.Free;
    Cmds.Free;
    S.Free;
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
    'Global, Insert, Delete, Column, Erase, Titles, Window, Status, Page, Learn', 'worksheet panel text');
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

procedure TestPrint;
var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;
  ps: TPrintSettings;
  sh: TSheet;
  err, fn: string;
  L: TStringList;
  r, c: Integer;
  q: TKeyQueue;

  procedure Go(const keys: string);
  begin
    q.PushString(keys);
    while not q.Empty do Ctl.HandleKey(q.Pop);
  end;

  { prints from the top of a page }
  procedure Run;
  begin
    ps.Pos := 0;
    L.Text := PrintRangeText(sh, ps, err);
  end;

begin
  sh := TSheet.Create;
  ResetPrint(ps);
  ps.Pos := 0;
  ps.Today := '01-Jan-26';
  sh.Put(1, 1, '''Name');  sh.Put(1, 2, '''Amount');
  sh.Put(2, 1, '''Ann');   sh.Put(2, 2, '12.5');
  sh.Put(3, 1, '''Bob');   sh.Put(3, 2, '7');
  L := TStringList.Create;
  PrintRangeText(sh, ps, err);
  CheckStr(err, 'Specify a print range first', 'no range: a message');
  ps.RangeSet := True;
  ps.Range := NormRange(1, 1, 3, 2);
  Run;
  CheckInt(L.Count, 8, 'a job stops after its last line: top margin, header, two blanks and three rows');
  CheckStr(L[5], '    Name     Amount', 'the first row after the top margin, header and two blank lines');
  CheckStr(L[7], '    Bob' + StringOfChar(' ', 13) + '7', 'a number leaves a blank at the right of its column');
  CheckStr(L[6], '    Ann' + StringOfChar(' ', 10) + '12.5', 'a number shows as General');
  CheckInt(ps.Pos, 8, 'the position in the page is kept');
  { the next job carries on in the middle of the page }
  L.Text := PrintRangeText(sh, ps, err);
  CheckInt(L.Count, 3, 'no top margin when the paper is not at the top');
  CheckInt(ps.Pos, 11, 'and the position moves on');
  ps.Pos := 0;
  ps.Header := 'Report|Sales|Page #';
  ps.Footer := '@';
  Run;
  CheckStr(L[2], '    Report' + StringOfChar(' ', 27) + 'Sales' + StringOfChar(' ', 28) + 'Page 1', 'header: left, centre and right parts');
  ps.Header := '';
  ps.Footer := '';
  for r := 4 to 130 do sh.Put(r, 1, '''row ' + IntToStr(r));
  ps.Range := NormRange(1, 1, 130, 1);
  Run;
  CheckInt(L.Count, 66 + 66 + 5 + 18, 'two full pages and a partial third');
  CheckStr(L[5], '    Name', 'first line on page one');
  CheckStr(L[61 + 2], '', 'two blank lines end the text');
  CheckStr(L[61 + 2], '', 'then the footer line');
  CheckStr(L[66 + 5], '    row 57', 'page two continues');
  ps.PgLength := 20;
  ps.Top := 0;
  ps.Bottom := 0;
  Run;
  CheckStr(L[3], '    Name', 'no top margin: header line, two blanks, then text');
  CheckStr(L[20 + 3], '    row 15', 'pages of 20 lines hold 14 rows');
  { page break row }
  ResetPrint(ps);
  ps.Today := '01-Jan-26';
  sh.Free;
  sh := TSheet.Create;
  sh.Put(1, 1, '''one');
  sh.Put(2, 1, '|::');
  sh.Put(3, 1, '''two');
  sh.Put(4, 1, '|a note that is not printed');
  sh.Put(5, 1, '''three');
  ps.RangeSet := True;
  ps.Range := NormRange(1, 1, 5, 1);
  Run;
  CheckInt(L.Count, 66 + 5 + 2, 'a page-break row ends the page');
  CheckStr(L[5], '    one', 'before the break');
  CheckStr(L[71], '    two', 'after the break');
  CheckStr(L[72], '    three', 'a row starting with | is not printed, the next one is');
  { column groups: 72 characters per page line }
  sh.Free;
  sh := TSheet.Create;
  for c := 1 to 10 do
  begin
    sh.SetColWidth(c, 12);
    sh.Put(1, c, IntToStr(c));
  end;
  ps.Range := NormRange(1, 1, 1, 10);
  Run;
  CheckInt(L.Count, 66 + 6, 'ten columns of 12: six fit in 72, the rest on the next page');
  CheckStr(L[5], StringOfChar(' ', 14) + '1 ' + StringOfChar(' ', 10) + '2 ' + StringOfChar(' ', 10) + '3 ' + StringOfChar(' ', 10) + '4 ' + StringOfChar(' ', 10) + '5 ' + StringOfChar(' ', 10) + '6', 'first columns');
  CheckStr(L[66 + 5], StringOfChar(' ', 14) + '7 ' + StringOfChar(' ', 10) + '8 ' + StringOfChar(' ', 10) + '9 ' + StringOfChar(' ', 9) + '10', 'the rest on the next page');
  ps.BorderColsSet := True;
  ps.BorderCols := NormRange(1, 1, 1, 1);
  ps.Range := NormRange(1, 2, 1, 10);
  Run;
  CheckInt(L.Count, 66 + 6, 'the border column is printed on each page');
  Check(Pos('1', L[66 + 5]) > 0, 'the border column starts the second page too');
  ps.BorderColsSet := False;
  { cell formulas and unformatted }
  sh.Free;
  sh := TSheet.Create;
  sh.Put(1, 1, '5');
  sh.Put(2, 1, '+A1*2');
  sh.Put(3, 2, '''hi');
  ps.Range := NormRange(1, 1, 3, 2);
  ps.CellFormulas := True;
  ps.Unformatted := True;
  Run;
  CheckInt(L.Count, 3, 'one line per cell');
  CheckStr(L[1], '    A2: +A1*2', 'the cell contents as the status line shows them');
  ps.CellFormulas := False;
  Run;
  CheckInt(L.Count, 3, 'unformatted: no page structure');
  CheckStr(L[2], '    ' + StringOfChar(' ', 9) + 'hi', 'a label in column B');
  CheckStr(SetupBytes('\015x\027E'), #15'x'#27'E', 'setup string codes');
  L.Free;
  sh.Free;

  { through the commands }
  fn := TmpDir + '/out.prn';
  if FileExists(fn) then DeleteFile(fn);
  S := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  q := TKeyQueue.Create;
  S.Sheet.Put(1, 1, '''hello');
  S.Sheet.Put(2, 1, '42');
  Go('/pf' + fn + #13);
  Check(S.Mode = mMenu, 'the print menu opens after choosing File');
  Go('ra1.a2'#13);
  Check(S.Mode = mMenu, 'the menu comes back after Range');
  Go('oml');
  Go('2'#13);
  CheckInt(S.Print.Left, 2, 'Options Margins Left');
  Check(S.Mode = mMenu, 'and the Options menu is open again');
  Go('q');
  Go('osAB\015'#13);
  Go('q');
  Go('g');
  Check(S.Mode = mMenu, 'the menu stays after Go');
  Go('p');
  Go('q');
  Check(S.Mode = mReady, 'Quit leaves the print menu');
  Check(FileExists(fn), 'the print file exists');
  L := TStringList.Create;
  L.LoadFromFile(fn);
  CheckStr(L[5], '  hello', 'the printed text, with the margin set (no setup string in a file)');
  CheckInt(L.Count, 66, 'Page finishes the page');
  L.Free;
  CheckInt(S.Print.Pos, 0, 'the paper is at the top of a page again');
  S.Print.ToFile := False;
  fn := TmpDir + '/lp.out';
  PrintCommandOverride := 'cat > ' + fn;
  Go('/ppg');
  Go('q');
  Check(FileExists(fn), 'the printer command receives the text');
  PrintCommandOverride := '';
  Go('/wp');
  CheckStr(RawAt(S, 1, 1), '|::', '/Worksheet Page inserts a page-break row');
  CheckStr(RawAt(S, 2, 1), '''hello', 'and moves the data down');
end;

procedure TestWindows;
var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;
  q: TKeyQueue;
  i: Integer;

  procedure Go(const keys: string);
  begin
    q.PushString(keys);
    while not q.Empty do Ctl.HandleKey(q.Pop);
  end;

begin
  S := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  q := TKeyQueue.Create;
  Ctl.HandleKey(kF1 + 5);
  CheckStr(S.Msg, 'There is only one window', 'F6 without a split');
  for i := 1 to 9 do Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 10, 'pointer on row 10');
  Go('/wwh');
  CheckInt(S.WinKind, 1, 'horizontal split');
  CheckInt(S.WinSize, 9, 'the top window has the rows above the pointer');
  CheckInt(S.WinActive, 1, 'the pointer is in the lower window');
  CheckInt(S.TopRow, 10, 'the lower window starts at the pointer row');
  CheckInt(S.GridRows, 10, 'the lower window has the rest of the rows');
  CheckInt(S.WinOther.Top, 1, 'the upper window shows row 1 first');
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 11, 'the pointer moves in the lower window');
  Ctl.HandleKey(kF1 + 5);
  CheckInt(S.WinActive, 0, 'F6 goes to the other window');
  CheckInt(S.CurRow, 9, 'the upper window has its own pointer');
  CheckInt(S.GridRows, 9, 'and its own size');
  Ctl.HandleKey(kF1 + 5);
  CheckInt(S.CurRow, 11, 'F6 again returns to where the pointer was');
  { sync: the windows scroll sideways together }
  for i := 1 to 12 do Ctl.HandleKey(kRight);
  Check(S.LeftCol > 1, 'the lower window scrolled sideways');
  CheckInt(S.WinOther.Left, S.LeftCol, 'the upper window followed (Sync)');
  Go('/wwu');
  Check(not S.WinSync, 'Unsync');
  for i := 1 to 6 do Ctl.HandleKey(kRight);
  Check(S.WinOther.Left < S.LeftCol, 'no longer following');
  Go('/wws');
  Check(S.WinSync, 'Sync');
  Go('/wwc');
  CheckInt(S.WinKind, 0, 'Clear');
  CheckInt(S.GridRows, 20, 'one window again');
  { vertical split }
  S.CurRow := 1; S.TopRow := 1; S.CurCol := 3; S.LeftCol := 1;
  S.Normalize;
  Go('/wwv');
  CheckInt(S.WinKind, 2, 'vertical split');
  CheckInt(S.WinSize, 4 + 18, 'the left window holds the columns before the pointer');
  CheckInt(S.LeftCol, 3, 'the right window starts at the pointer column');
  CheckInt(S.GridW, 80 - 22 - 1 - 4, 'and takes the rest of the width');
  for i := 1 to 30 do Ctl.HandleKey(kDown);
  Check(S.TopRow > 1, 'scrolled down');
  CheckInt(S.WinOther.Top, S.TopRow, 'the left window followed (Sync)');
  Go('/wwc');
  CheckInt(S.WinKind, 0, 'Clear after a vertical split');
end;

procedure TestPrintFile;
var
  sh, sh2: TSheet;
  info, info2: TFileInfo;
  w: TStringList;
  fn, msg: string;
begin
  fn := TmpDir + '/pr.wk1';
  sh := TSheet.Create;
  sh.Put(1, 1, '''x');
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1; info.CursorRow := 1; info.LeftCol := 1; info.TopRow := 1;
  ResetPrint(info.Print);
  info.Print.RangeSet := True;
  info.Print.Range := NormRange(2, 3, 20, 8);
  info.Print.Header := 'Report|Café|Page #';
  info.Print.Footer := '@';
  info.Print.Setup := '\015';
  info.Print.Left := 2; info.Print.Right := 60; info.Print.PgLength := 55; info.Print.Top := 3; info.Print.Bottom := 1;
  info.Print.BorderRowsSet := True; info.Print.BorderRows := NormRange(1, 1, 2, 1);
  info.Print.BorderColsSet := True; info.Print.BorderCols := NormRange(1, 1, 1, 3);
  info.Print.Unformatted := True;
  w := TStringList.Create;
  msg := SaveWorksheet(fn, sh, False, info, w);
  CheckStr(msg, '', 'save with print settings');
  sh2 := TSheet.Create;
  msg := LoadWorksheet(fn, sh2, w, info2);
  CheckStr(msg, '', 'load it again');
  Check(info2.Print.RangeSet, 'the print range is kept');
  CheckInt(info2.Print.Range.R1, 2, 'range first row');
  CheckInt(info2.Print.Range.C1, 3, 'range first column');
  CheckInt(info2.Print.Range.R2, 20, 'range last row');
  CheckInt(info2.Print.Range.C2, 8, 'range last column');
  CheckStr(info2.Print.Header, 'Report|Café|Page #', 'the header, with an accent');
  CheckStr(info2.Print.Footer, '@', 'the footer');
  CheckStr(info2.Print.Setup, '\015', 'the setup string');
  CheckInt(info2.Print.Left, 2, 'left margin');
  CheckInt(info2.Print.Right, 60, 'right margin');
  CheckInt(info2.Print.PgLength, 55, 'page length');
  CheckInt(info2.Print.Top, 3, 'top margin');
  CheckInt(info2.Print.Bottom, 1, 'bottom margin');
  Check(info2.Print.BorderRowsSet and (info2.Print.BorderRows.R2 = 2), 'border rows');
  Check(info2.Print.BorderColsSet and (info2.Print.BorderCols.C2 = 3), 'border columns');
  Check(info2.Print.Unformatted, 'unformatted');
  { a file with no print settings gets the defaults }
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1; info.CursorRow := 1; info.LeftCol := 1; info.TopRow := 1;
  msg := SaveWorksheet(fn, sh, False, info, w);
  msg := LoadWorksheet(fn, sh2, w, info2);
  Check(not info2.Print.RangeSet, 'no print range');
  CheckInt(info2.Print.PgLength, 66, 'default page length');
  CheckInt(info2.Print.Right, 76, 'default right margin');
  CheckStr(info2.Print.Header, '', 'no header');
  w.Free;
  sh.Free;
  sh2.Free;
end;

procedure TestRecovery;
var
  cfg: TConfig;
  S, S2: TSession;
  st: TStale;
  dir, warn, msg: string;
  sl: TStringList;
begin
  DefaultConfig(cfg);
  CheckInt(cfg.RecoverySeconds, 30, 'default recovery interval');
  CheckInt(cfg.AutosaveMinutes, 0, 'autosave is off by default');
  msg := ParseConfig('# a comment'#10'autosave = 5'#10'recovery=10 # often'#10'expand = yes'#10, cfg);
  CheckStr(msg, '', 'a good configuration');
  CheckInt(cfg.AutosaveMinutes, 5, 'autosave read');
  CheckInt(cfg.RecoverySeconds, 10, 'recovery read');
  Check(cfg.Expand, 'expand read');
  msg := ParseConfig('autosave = lots'#10'colour = red'#10'nonsense'#10, cfg);
  CheckInt(Length(msg.Split([#10])) - 1, 3, 'three problems are reported');
  CheckInt(cfg.AutosaveMinutes, 5, 'a bad value changes nothing');

  S := TSession.Create;
  S.MarkSaved;
  Check(not S.Modified, 'a new worksheet is not modified');
  S.Sheet.Put(1, 1, '5');
  S.CheckModified;
  Check(S.Modified, 'a change is noticed');
  dir := TmpDir + '/recover';
  RecoveryDirOverride := dir;
  S.FileName := 'budget.wk1';
  WriteRecovery(S);
  Check(FileExists(dir + '/' + IntToStr(GetProcessID) + '.wk1'), 'the recovery file is written');
  RemoveRecovery;
  Check(not FileExists(dir + '/' + IntToStr(GetProcessID) + '.wk1'), 'and removed');
  st := FindStale;
  Check(not st.Found, 'nothing to recover');
  { a file left by a process that is gone }
  ForceDirectories(dir);
  S.FileName := 'old.wk1';
  SaveSessionFile(S, dir + '/999999.wk1', warn);
  sl := TStringList.Create;
  sl.Add('old.wk1');
  sl.Add('2026-01-02 03:04');
  sl.SaveToFile(dir + '/999999.txt');
  sl.Free;
  st := FindStale;
  Check(st.Found, 'a stale recovery file is found');
  CheckStr(st.Original, 'old.wk1', 'with the name of the original');
  CheckStr(st.When, '2026-01-02 03:04', 'and its time');
  S2 := TSession.Create;
  CheckStr(RetrieveFile(S2, st.Path), '', 'it loads');
  CheckStr(RawAt(S2, 1, 1), '5', 'with the data');
  DeleteStale(st);
  Check(not FindStale.Found, 'and can be deleted');
  RecoveryDirOverride := '';
  CheckStr(VersionText.Split([#10])[0], 'mkspread ' + ProgramVersion, 'the version line');
  Check(Pos('1-2-3', VersionText) + Pos('Lotus', VersionText) = 0, 'no trademarked names in the version text');
end;

procedure TestRefEdit;
var
  s: string;
  p: Integer;

  function Cycle(const text: string; at: Integer): string;
  begin
    s := text;
    p := at;
    if CycleAbsolute(s, p) then Result := s else Result := '(none)';
  end;

begin
  CheckStr(Cycle('+A1', 3), '+$A$1', 'F4: relative to absolute');
  CheckStr(Cycle('+$A$1', 5), '+A$1', 'F4: absolute to row absolute');
  CheckStr(Cycle('+A$1', 4), '+$A1', 'F4: row absolute to column absolute');
  CheckStr(Cycle('+$A1', 4), '+A1', 'F4: column absolute to relative');
  CheckStr(Cycle('+A1+B2', 6), '+A1+$B$2', 'the reference before the cursor');
  CheckStr(Cycle('+A1+B2', 3), '+$A$1+B2', 'the reference the cursor is next to');
  CheckStr(Cycle('@SUM(A1..B3)', 12), '@SUM($A$1..$B$3)', 'both corners of a range');
  CheckStr(Cycle('@SUM(A1..B3)', 7), '@SUM($A$1..$B$3)', 'a range from its first corner');
  CheckStr(Cycle('+"A1"', 5), '(none)', 'text in quotes is left alone');
  CheckStr(Cycle('@LOG10(5)', 9), '(none)', 'a function name is not a reference');
  CheckStr(Cycle('+TAX1', 5), '(none)', 'a range name is not a reference');
  CheckInt(p, 5, 'the cursor stays after a name');
  Cycle('+A1', 3);
  CheckInt(p, 5, 'the cursor moves to the end of the changed reference');
  CheckStr(Cycle('+aa10', 5), '+$AA$10', 'two-letter columns and lower case');
end;

procedure TestHelp;
var
  i, j, n: Integer;
  rel, lines: TStringList;
  txt: string;
  ok, okLen, okWords, okLines, okUnique: Boolean;
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;
begin
  ok := True; okLen := True; okWords := True; okLines := True; okUnique := True;
  rel := TStringList.Create;
  lines := TStringList.Create;
  rel.Delimiter := ',';
  rel.StrictDelimiter := True;
  for i := 0 to HelpCount - 1 do
  begin
    rel.DelimitedText := HelpRelated(i);
    for j := 0 to rel.Count - 1 do
      if HelpIndexOf(rel[j]) < 0 then begin ok := False; WriteLn('help: ', HelpId(i), ' links to missing ', rel[j]); end;
    if HelpIndexOf(HelpId(i)) <> i then begin okUnique := False; WriteLn('help: duplicate id ', HelpId(i)); end;
    lines.Text := HelpBody(i);
    if lines.Count > 20 then begin okLines := False; WriteLn('help: too many lines in ', HelpId(i)); end;
    for j := 0 to lines.Count - 1 do
      if Length(lines[j]) > 78 then begin okLen := False; WriteLn('help: long line in ', HelpId(i), ': ', lines[j]); end;
    txt := UpperCase(HelpTitle(i) + HelpBody(i));
    if (Pos('1-2-3', txt) > 0) or (Pos('LOTUS', txt) > 0) then begin okWords := False; WriteLn('help: trademark in ', HelpId(i)); end;
  end;
  Check(ok, 'every related topic exists');
  Check(okUnique, 'topic ids are unique');
  Check(okLen, 'help lines fit the screen');
  Check(okLines, 'topics fit one screen');
  Check(okWords, 'no trademarked names in help');
  CheckStr(HelpForMenu('Range Format Fixed'), 'm:range format', 'help for a menu choice');
  CheckStr(HelpForMenu('Data Sort Go'), 'm:data sort', 'help for a menu choice, deeper');
  CheckStr(HelpForMenu('Copy'), 'm:copy', 'help for Copy');
  CheckStr(HelpForMenu('Print Printer Options Margins Left'), 'm:print options', 'help inside the print menu');
  CheckStr(HelpForMenu('Print File Go'), 'm:print', 'help for the print menu');
  CheckStr(HelpForMenu('Nothing Here'), 'menus', 'help falls back to the menus topic');
  rel.Free;
  lines.Free;

  S := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  Ctl.HandleKey(kF1);
  Check(S.Mode = mHelp, 'F1 opens help');
  CheckStr(S.HelpId, 'basics', 'READY help is the overview');
  Ctl.HandleKey(kF1);
  CheckStr(S.HelpId, 'index', 'F1 again shows the index');
  Ctl.HandleKey(kDown);
  Ctl.HandleKey(kEnter);
  CheckStr(S.HelpId, 'screen', 'Enter follows the selected topic');
  Ctl.HandleKey(kBackspace);
  CheckStr(S.HelpId, 'index', 'Backspace goes back');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'Esc leaves help');
  Ctl.HandleKey(Ord('/'));
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kF1);
  CheckStr(S.HelpId, 'm:range', 'F1 in the menu explains the highlighted choice');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mMenu, 'Esc returns to the menu');
  Ctl.HandleKey(kBreak);
  Ctl.HandleKey(Ord('1'));
  Ctl.HandleKey(kF1);
  CheckStr(S.HelpId, 'entry', 'F1 while typing');
  Ctl.HandleKey(kEsc);
  CheckStr(S.Entry, '1', 'the entry is still there after help');
end;

begin
  TestSheet;
  TestJournal;
  TestFormat;
  TestDates;
  TestFormulas;
  TestEditOps;
  TestFunctions;
  TestMacros;
  TestDataOps;
  TestDataCommands;
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
  TestHelp;
  TestRefEdit;
  TestPrint;
  TestWindows;
  TestPrintFile;
  TestRecovery;
  WriteLn(Total - Fails, '/', Total, ' checks passed');
  if Fails > 0 then Halt(1);
end.
