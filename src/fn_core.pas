{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>. }

{ @functions: math, logic, text, lookup and cell information. }
unit fn_core;
{$mode objfpc}{$H+}

interface

implementation

uses SysUtils, Math, formula, sheet, charsets;

{ ------------------------------------------------------------------ helpers }

function U(const s: string): UnicodeString;
begin
  Result := UTF8Decode(s);
end;

function FromU(const u: UnicodeString): string;
begin
  Result := UTF8Encode(u);
end;

function Flag(b: Boolean): TValue;
begin
  if b then Result := NumValue(1) else Result := NumValue(0);
end;

{ one numeric argument, one result }
type
  TMath1 = function(x: Double; out ok: Boolean): Double;

function Apply1(const args: TNodeArray; src: TCellSource; f: TMath1): TValue;
var
  x, y: Double;
  bad: TValue;
  ok: Boolean;
begin
  if not ArgNumber(args[0], src, x, bad) then exit(bad);
  ok := True;
  y := f(x, ok);
  if not ok then exit(ErrValue);
  Result := NumValue(y);
end;

{ ------------------------------------------------------------------ math }

function M_Abs(x: Double; out ok: Boolean): Double; begin ok := True; Result := Abs(x); end;
function M_Int(x: Double; out ok: Boolean): Double; begin ok := True; Result := Int(x); end;
function M_Sqrt(x: Double; out ok: Boolean): Double; begin ok := x >= 0; if ok then Result := Sqrt(x) else Result := 0; end;
function M_Log(x: Double; out ok: Boolean): Double; begin ok := x > 0; if ok then Result := Ln(x) / Ln(10) else Result := 0; end;
function M_Ln(x: Double; out ok: Boolean): Double; begin ok := x > 0; if ok then Result := Ln(x) else Result := 0; end;
function M_Exp(x: Double; out ok: Boolean): Double; begin ok := x < 709; if ok then Result := Exp(x) else Result := 0; end;
function M_Sin(x: Double; out ok: Boolean): Double; begin ok := True; Result := Sin(x); end;
function M_Cos(x: Double; out ok: Boolean): Double; begin ok := True; Result := Cos(x); end;
function M_Tan(x: Double; out ok: Boolean): Double; begin ok := True; Result := Sin(x) / Cos(x); end;
function M_Atan(x: Double; out ok: Boolean): Double; begin ok := True; Result := ArcTan(x); end;
function M_Asin(x: Double; out ok: Boolean): Double; begin ok := Abs(x) <= 1; if ok then Result := ArcSin(x) else Result := 0; end;
function M_Acos(x: Double; out ok: Boolean): Double; begin ok := Abs(x) <= 1; if ok then Result := ArcCos(x) else Result := 0; end;

function FnAbs(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Abs); end;
function FnInt(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Int); end;
function FnSqrt(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Sqrt); end;
function FnLog(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Log); end;
function FnLn(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Ln); end;
function FnExp(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Exp); end;
function FnSin(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Sin); end;
function FnCos(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Cos); end;
function FnTan(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Tan); end;
function FnAtan(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Atan); end;
function FnAsin(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Asin); end;
function FnAcos(const a: TNodeArray; s: TCellSource): TValue; begin Result := Apply1(a, s, @M_Acos); end;

function FnPi(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NumValue(Pi);
end;

{ @ATAN2(x, y): the angle of the point (x, y), -pi..pi }
function FnAtan2(const a: TNodeArray; s: TCellSource): TValue;
var
  x, y: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if not ArgNumber(a[1], s, y, bad) then exit(bad);
  if (x = 0) and (y = 0) then exit(ErrValue);
  Result := NumValue(ArcTan2(y, x));
end;

{ the remainder takes the sign of x }
function FnMod(const a: TNodeArray; s: TCellSource): TValue;
var
  x, y: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if not ArgNumber(a[1], s, y, bad) then exit(bad);
  if y = 0 then exit(ErrValue);
  Result := NumValue(x - y * Int(x / y));
end;

function FnRand(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NumValue(Random);
end;

function FnRound(const a: TNodeArray; s: TCellSource): TValue;
var
  x, n, scale: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if not ArgNumber(a[1], s, n, bad) then exit(bad);
  n := Trunc(n);
  if Abs(n) > 300 then exit(ErrValue);
  scale := Power(10, n);
  if x >= 0 then Result := NumValue(Int(x * scale + 0.5) / scale)
  else Result := NumValue(-Int(-x * scale + 0.5) / scale);
end;

{ ------------------------------------------------------------------ logic }

function FnNA(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NAValue;
end;

function FnErr(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := ErrValue;
end;

function FnTrue(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NumValue(1);
end;

function FnFalse(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NumValue(0);
end;

function FnIsNA(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Flag(a[0].Eval(s).Kind = vkNA);
end;

function FnIsErr(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Flag(a[0].Eval(s).Kind = vkErr);
end;

function FnIsNumber(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Flag(a[0].Eval(s).Kind = vkNum);
end;

function FnIsString(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Flag(a[0].Eval(s).Kind = vkStr);
end;

function FnIf(const a: TNodeArray; s: TCellSource): TValue;
var
  c: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, c, bad) then exit(bad);
  if c <> 0 then Result := a[1].Eval(s) else Result := a[2].Eval(s);
end;

{ @CHOOSE(x, v0, v1, ...): x counts from 0 }
function FnChoose(const a: TNodeArray; s: TCellSource): TValue;
var
  x: Double;
  bad: TValue;
  i: Integer;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  i := Trunc(x);
  if (i < 0) or (i > High(a) - 1) then exit(ErrValue);
  Result := a[i + 1].Eval(s);
end;

{ ------------------------------------------------------------------ text }

function FnLength(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  Result := NumValue(Length(U(t)));
end;

function FnLeft(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  n: Double;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not ArgNumber(a[1], s, n, bad) then exit(bad);
  if n < 0 then exit(ErrValue);
  Result := StrValue(FromU(Copy(U(t), 1, Trunc(n))));
end;

function FnRight(const a: TNodeArray; s: TCellSource): TValue;
var
  t: UnicodeString;
  str: string;
  n: Double;
  bad: TValue;
  k: Integer;
begin
  if not ArgString(a[0], s, str, bad) then exit(bad);
  if not ArgNumber(a[1], s, n, bad) then exit(bad);
  if n < 0 then exit(ErrValue);
  t := U(str);
  k := Trunc(n);
  if k >= Length(t) then exit(StrValue(str));
  Result := StrValue(FromU(Copy(t, Length(t) - k + 1, k)));
end;

{ @MID(string, start, count): start counts from 0 }
function FnMid(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  st, n: Double;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not ArgNumber(a[1], s, st, bad) then exit(bad);
  if not ArgNumber(a[2], s, n, bad) then exit(bad);
  if (st < 0) or (n < 0) then exit(ErrValue);
  Result := StrValue(FromU(Copy(U(t), Trunc(st) + 1, Trunc(n))));
end;

function FnRepeat(const a: TNodeArray; s: TCellSource): TValue;
var
  t, r: string;
  n: Double;
  bad: TValue;
  i: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not ArgNumber(a[1], s, n, bad) then exit(bad);
  if (n < 0) or (n * Length(t) > 240) then exit(ErrValue);
  r := '';
  for i := 1 to Trunc(n) do r := r + t;
  Result := StrValue(r);
end;

function FnUpper(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  Result := StrValue(FromU(UpperCase(U(t))));
end;

function FnLower(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  Result := StrValue(FromU(LowerCase(U(t))));
end;

function FnProper(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  w: UnicodeString;
  bad: TValue;
  i: Integer;
  startOfWord: Boolean;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  w := U(t);
  startOfWord := True;
  for i := 1 to Length(w) do
  begin
    if (w[i] < #128) and (Chr(Ord(w[i])) in ['A'..'Z', 'a'..'z']) then
    begin
      if startOfWord then w[i] := WideChar(Ord(w[i]) and $DF)
      else w[i] := WideChar(Ord(w[i]) or $20);
      startOfWord := False;
    end
    else
      startOfWord := not (w[i] >= #128);           { anything but a letter starts a new word }
  end;
  Result := StrValue(FromU(w));
end;

{ leading and trailing spaces go, runs of spaces inside become one }
function FnTrim(const a: TNodeArray; s: TCellSource): TValue;
var
  t, r: string;
  bad: TValue;
  i: Integer;
  prevSpace: Boolean;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  r := '';
  prevSpace := True;
  for i := 1 to Length(t) do
    if t[i] = ' ' then
    begin
      if not prevSpace then r := r + ' ';
      prevSpace := True;
    end
    else
    begin
      r := r + t[i];
      prevSpace := False;
    end;
  if (r <> '') and (r[Length(r)] = ' ') then SetLength(r, Length(r) - 1);
  Result := StrValue(r);
end;

{ removes the non-printing characters }
function FnClean(const a: TNodeArray; s: TCellSource): TValue;
var
  t, r: string;
  bad: TValue;
  i: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  r := '';
  for i := 1 to Length(t) do
    if (t[i] >= ' ') and (t[i] <> #127) then r := r + t[i];
  Result := StrValue(r);
end;

function FnExact(const a: TNodeArray; s: TCellSource): TValue;
var
  x, y: string;
  bad: TValue;
begin
  if not ArgString(a[0], s, x, bad) then exit(bad);
  if not ArgString(a[1], s, y, bad) then exit(bad);
  Result := Flag(x = y);
end;

{ @REPLACE(original, start, count, new): start counts from 0 }
function FnReplace(const a: TNodeArray; s: TCellSource): TValue;
var
  o, nw: string;
  st, n: Double;
  bad: TValue;
  w: UnicodeString;
begin
  if not ArgString(a[0], s, o, bad) then exit(bad);
  if not ArgNumber(a[1], s, st, bad) then exit(bad);
  if not ArgNumber(a[2], s, n, bad) then exit(bad);
  if not ArgString(a[3], s, nw, bad) then exit(bad);
  if (st < 0) or (n < 0) then exit(ErrValue);
  w := U(o);
  if Trunc(st) > Length(w) then st := Length(w);
  Delete(w, Trunc(st) + 1, Trunc(n));
  Insert(U(nw), w, Trunc(st) + 1);
  Result := StrValue(FromU(w));
end;

{ @FIND(search, string, start): position counted from 0, case sensitive }
function FnFind(const a: TNodeArray; s: TCellSource): TValue;
var
  needle, hay: string;
  st: Double;
  bad: TValue;
  p: Integer;
  h: UnicodeString;
begin
  if not ArgString(a[0], s, needle, bad) then exit(bad);
  if not ArgString(a[1], s, hay, bad) then exit(bad);
  if not ArgNumber(a[2], s, st, bad) then exit(bad);
  h := U(hay);
  if (st < 0) or (Trunc(st) > Length(h)) then exit(ErrValue);
  h := Copy(h, Trunc(st) + 1, MaxInt);
  p := Pos(U(needle), h);
  if p = 0 then exit(ErrValue);
  Result := NumValue(Trunc(st) + p - 1);
end;

{ @STRING(x, n): x with n decimal places, no thousands separators }
function FnString(const a: TNodeArray; s: TCellSource): TValue;
var
  x, n: Double;
  bad: TValue;
  t: string;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if not ArgNumber(a[1], s, n, bad) then exit(bad);
  if (n < 0) or (n > 15) then exit(ErrValue);
  Str(x:0:Trunc(n), t);
  Result := StrValue(t);
end;

function FnValue(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  d: Double;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  t := Trim(t);
  if t = '' then exit(NumValue(0));
  if IsNumberLiteral(t, d) then exit(NumValue(d));
  Result := ErrValue;
end;

function FnChar(const a: TNodeArray; s: TCellSource): TValue;
var
  n: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, n, bad) then exit(bad);
  if (n < 1) or (n > 255) then exit(ErrValue);
  Result := StrValue(LicsToUtf8(Chr(Trunc(n))));
end;

function FnCode(const a: TNodeArray; s: TCellSource): TValue;
var
  t, l: string;
  bad: TValue;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if t = '' then exit(ErrValue);
  l := Utf8ToLics(FromU(Copy(U(t), 1, 1)));
  Result := NumValue(Ord(l[1]));
end;

{ the first cell of an argument: @N is its number (0 for text), @S its text }
function FnN(const a: TNodeArray; s: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
  v: TValue;
begin
  if RectOf(a[0], s, r1, c1, r2, c2) then v := s.CellValue(r1, c1) else v := a[0].Eval(s);
  if v.Kind = vkErr then exit(ErrValue);
  if v.Kind = vkNA then exit(NAValue);
  if v.Kind = vkNum then Result := NumValue(v.Num) else Result := NumValue(0);
end;

function FnS(const a: TNodeArray; s: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
  v: TValue;
begin
  if RectOf(a[0], s, r1, c1, r2, c2) then v := s.CellValue(r1, c1) else v := a[0].Eval(s);
  if v.Kind = vkErr then exit(ErrValue);
  if v.Kind = vkNA then exit(NAValue);
  if v.Kind = vkStr then Result := StrValue(v.Str) else Result := StrValue('');
end;

{ @@(text): the contents of the cell whose address (or range name) is in text }
function FnIndirect(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
  c, r, r1, c1, r2, c2: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  t := StringReplace(Trim(t), '$', '', [rfReplaceAll]);
  if ParseAddr(t, c, r) then exit(s.CellValue(r, c));
  if IsValidName(t) and s.LookupName(UpperCase(t), r1, c1, r2, c2) and (r1 = r2) and (c1 = c2) then
    exit(s.CellValue(r1, c1));
  Result := ErrValue;
end;

function FnCall(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := ErrValue;                  { external routines are not supported }
end;

{ ------------------------------------------------------------------ lookup, information }

function FnCols(const a: TNodeArray; s: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
begin
  if not RectOf(a[0], s, r1, c1, r2, c2) then exit(ErrValue);
  Result := NumValue(c2 - c1 + 1);
end;

function FnRows(const a: TNodeArray; s: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
begin
  if not RectOf(a[0], s, r1, c1, r2, c2) then exit(ErrValue);
  Result := NumValue(r2 - r1 + 1);
end;

{ @INDEX(range, column, row): both counted from 0 }
function FnIndex(const a: TNodeArray; s: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
  cx, ry: Double;
  bad: TValue;
begin
  if not RectOf(a[0], s, r1, c1, r2, c2) then exit(ErrValue);
  if not ArgNumber(a[1], s, cx, bad) then exit(bad);
  if not ArgNumber(a[2], s, ry, bad) then exit(bad);
  if (cx < 0) or (ry < 0) or (c1 + Trunc(cx) > c2) or (r1 + Trunc(ry) > r2) then exit(ErrValue);
  Result := s.CellValue(r1 + Trunc(ry), c1 + Trunc(cx));
end;

{ Looks x up in the first column (vertical) or row (horizontal) of the range:
  the last entry not greater than x for numbers, an exact match for text.  The
  answer is in the same row or column, offset further along. }
function Lookup(const a: TNodeArray; s: TCellSource; vertical: Boolean): TValue;
var
  r1, c1, r2, c2, i, last, hit, off: Integer;
  x: TValue;
  off_: Double;
  bad: TValue;
  v: TValue;
  n: Integer;
begin
  if not RectOf(a[1], s, r1, c1, r2, c2) then exit(ErrValue);
  x := a[0].Eval(s);
  if x.Kind = vkErr then exit(ErrValue);
  if x.Kind = vkNA then exit(NAValue);
  if not ArgNumber(a[2], s, off_, bad) then exit(bad);
  off := Trunc(off_);
  if vertical then n := r2 - r1 + 1 else n := c2 - c1 + 1;
  if (off < 0) or (vertical and (c1 + off > c2)) or (not vertical and (r1 + off > r2)) then exit(ErrValue);
  hit := -1;
  last := n - 1;
  for i := 0 to last do
  begin
    if vertical then v := s.CellValue(r1 + i, c1) else v := s.CellValue(r1, c1 + i);
    if v.IsEmpty then continue;
    if x.Kind = vkStr then
    begin
      if (v.Kind = vkStr) and (CompareText(v.Str, x.Str) = 0) then begin hit := i; break; end;
    end
    else if v.Kind = vkNum then
    begin
      if v.Num <= x.Num then hit := i else break;
    end;
  end;
  if hit < 0 then exit(NAValue);
  if vertical then Result := s.CellValue(r1 + hit, c1 + off)
  else Result := s.CellValue(r1 + off, c1 + hit);
end;

function FnVlookup(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Lookup(a, s, True);
end;

function FnHlookup(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := Lookup(a, s, False);
end;

function CellInfoOf(const attr: string; s: TCellSource; r, c: Integer): TValue;
begin
  Result := s.CellInfo(LowerCase(attr), r, c);
end;

function FnCell(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
  r1, c1, r2, c2: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not RectOf(a[1], s, r1, c1, r2, c2) then exit(ErrValue);
  Result := CellInfoOf(t, s, r1, c1);
end;

function FnCellPointer(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
  r, c: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  s.PointerCell(r, c);
  Result := CellInfoOf(t, s, r, c);
end;

initialization
  { name, min args, max args, file opcode, list function? }
  RegisterFunc('NA', 0, 0, 31, False, @FnNA);
  RegisterFunc('ERR', 0, 0, 32, False, @FnErr);
  RegisterFunc('ABS', 1, 1, 33, False, @FnAbs);
  RegisterFunc('INT', 1, 1, 34, False, @FnInt);
  RegisterFunc('SQRT', 1, 1, 35, False, @FnSqrt);
  RegisterFunc('LOG', 1, 1, 36, False, @FnLog);
  RegisterFunc('LN', 1, 1, 37, False, @FnLn);
  RegisterFunc('PI', 0, 0, 38, False, @FnPi);
  RegisterFunc('SIN', 1, 1, 39, False, @FnSin);
  RegisterFunc('COS', 1, 1, 40, False, @FnCos);
  RegisterFunc('TAN', 1, 1, 41, False, @FnTan);
  RegisterFunc('ATAN2', 2, 2, 42, False, @FnAtan2);
  RegisterFunc('ATAN', 1, 1, 43, False, @FnAtan);
  RegisterFunc('ASIN', 1, 1, 44, False, @FnAsin);
  RegisterFunc('ACOS', 1, 1, 45, False, @FnAcos);
  RegisterFunc('EXP', 1, 1, 46, False, @FnExp);
  RegisterFunc('MOD', 2, 2, 47, False, @FnMod);
  RegisterFunc('CHOOSE', 2, 255, 48, True, @FnChoose);
  RegisterFunc('ISNA', 1, 1, 49, False, @FnIsNA);
  RegisterFunc('ISERR', 1, 1, 50, False, @FnIsErr);
  RegisterFunc('FALSE', 0, 0, 51, False, @FnFalse);
  RegisterFunc('TRUE', 0, 0, 52, False, @FnTrue);
  RegisterFunc('RAND', 0, 0, 53, False, @FnRand);
  RegisterFunc('IF', 3, 3, 59, False, @FnIf);
  RegisterFunc('ROUND', 2, 2, 63, False, @FnRound);
  RegisterFunc('ISNUMBER', 1, 1, 68, False, @FnIsNumber);
  RegisterFunc('ISSTRING', 1, 1, 69, False, @FnIsString);
  RegisterFunc('LENGTH', 1, 1, 70, False, @FnLength);
  RegisterFunc('VALUE', 1, 1, 71, False, @FnValue);
  RegisterFunc('STRING', 2, 2, 72, False, @FnString);
  RegisterFunc('MID', 3, 3, 73, False, @FnMid);
  RegisterFunc('CHAR', 1, 1, 74, False, @FnChar);
  RegisterFunc('CODE', 1, 1, 75, False, @FnCode);
  RegisterFunc('FIND', 3, 3, 76, False, @FnFind);
  RegisterFunc('CELLPOINTER', 1, 1, 79, False, @FnCellPointer);
  RegisterFunc('VLOOKUP', 3, 3, 85, False, @FnVlookup);
  RegisterFunc('HLOOKUP', 3, 3, 90, False, @FnHlookup);
  RegisterFunc('INDEX', 3, 3, 98, False, @FnIndex);
  RegisterFunc('COLS', 1, 1, 99, False, @FnCols);
  RegisterFunc('ROWS', 1, 1, 100, False, @FnRows);
  RegisterFunc('REPEAT', 2, 2, 101, False, @FnRepeat);
  RegisterFunc('UPPER', 1, 1, 102, False, @FnUpper);
  RegisterFunc('LOWER', 1, 1, 103, False, @FnLower);
  RegisterFunc('LEFT', 2, 2, 104, False, @FnLeft);
  RegisterFunc('RIGHT', 2, 2, 105, False, @FnRight);
  RegisterFunc('REPLACE', 4, 4, 106, False, @FnReplace);
  RegisterFunc('PROPER', 1, 1, 107, False, @FnProper);
  RegisterFunc('CELL', 2, 2, 108, False, @FnCell);
  RegisterFunc('TRIM', 1, 1, 109, False, @FnTrim);
  RegisterFunc('CLEAN', 1, 1, 110, False, @FnClean);
  RegisterFunc('S', 1, 1, 111, False, @FnS);
  RegisterFunc('N', 1, 1, 112, False, @FnN);
  RegisterFunc('EXACT', 2, 2, 113, False, @FnExact);
  RegisterFunc('CALL', 1, 1, 114, False, @FnCall);
  RegisterFunc('@', 1, 1, 115, False, @FnIndirect);
  Randomize;
end.
