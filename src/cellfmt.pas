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

{ Turning stored cell contents into the text shown on screen. }
unit cellfmt;
{$mode objfpc}{$H+}

interface

uses sheet;

const
  ValueStarts   = ['0'..'9', '+', '-', '.', '@', '(', '#', '$'];

function IsLabel(cell: TCell): Boolean;

{ The numeric value of a cell, when it has one (a number, or a formula that
  has a computed value). }
function CellNumber(cell: TCell; out d: Double): Boolean;

function EffectiveFormat(cell: TCell; sh: TSheet): TCellFormat;

{ "F2", "C0", ",2", "G", "+", "D1" ... (no parentheses) }
function FormatTag(const f: TCellFormat): string;

function FormatNumber(d: Double; const f: TCellFormat; width: Integer): string;

{ What a value cell displays in a column of the given width (before the
  overflow check that turns too-wide text into asterisks). }
function ValueText(cell: TCell; sh: TSheet; width: Integer): string;

{ Number as stored: shortest text that reads back as the same value (15 digits). }
function NumToRaw(d: Double): string;

implementation

uses SysUtils, Math, dates;

function IsLabel(cell: TCell): Boolean;
begin
  Result := (cell.Raw <> '') and (cell.Raw[1] in LabelPrefixes);
end;

function CellNumber(cell: TCell; out d: Double): Boolean;
var
  s: string;
  code: Integer;
begin
  d := 0;
  s := cell.Cache;
  if s = '' then s := cell.Raw;
  if (s = '') or (s[1] in LabelPrefixes) or (s[1] in ['$', '%', '&', 'x', 'X']) then exit(False);
  Val(s, d, code);
  Result := code = 0;
end;

function EffectiveFormat(cell: TCell; sh: TSheet): TCellFormat;
begin
  if cell.Fmt.UseGlobal then Result := sh.GlobalFmt else Result := cell.Fmt;
end;

function FormatTag(const f: TCellFormat): string;
begin
  case f.Kind of
    fkGeneral:  Result := 'G';
    fkFixed:    Result := 'F' + IntToStr(f.Dec);
    fkSci:      Result := 'S' + IntToStr(f.Dec);
    fkCurrency: Result := 'C' + IntToStr(f.Dec);
    fkComma:    Result := ',' + IntToStr(f.Dec);
    fkPercent:  Result := 'P' + IntToStr(f.Dec);
    fkPlusMinus: Result := '+';
    fkDate:     Result := 'D' + IntToStr(f.Dec);
    fkText:     Result := 'T';
    fkHidden:   Result := 'H';
  end;
end;

function NumToRaw(d: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(d, ffGeneral, 15, 0, fs);
end;

function Commas(const digits: string): string;
var
  k: Integer;
begin
  Result := digits;
  k := Length(Result) - 2;
  while k > 1 do
  begin
    Insert(',', Result, k);
    Dec(k, 3);
  end;
end;

{ fixed-point text of |d| with dec decimals, optionally with thousands commas }
function FixedAbs(d: Double; dec: Integer; withCommas: Boolean): string;
var
  s, ip, fp: string;
  k: Integer;
begin
  Str(Abs(d):0:dec, s);
  k := Pos('.', s);
  if k > 0 then
  begin
    ip := Copy(s, 1, k - 1);
    fp := Copy(s, k, MaxInt);
  end
  else
  begin
    ip := s;
    fp := '';
  end;
  if withCommas then ip := Commas(ip);
  Result := ip + fp;
end;

function SciText(d: Double; dec: Integer): string;
var
  e: Integer;
  m: Double;
  ms: string;
begin
  if d = 0 then
  begin
    e := 0;
    m := 0;
  end
  else
  begin
    e := Floor(Log10(Abs(d)));
    m := d / Power(10, e);
    Str(Abs(m):0:dec, ms);
    if StrToFloat(ms) >= 10 then       { rounding carried: 9.99 -> 10.0 }
    begin
      Inc(e);
      m := d / Power(10, e);
    end;
  end;
  Str(m:0:dec, ms);
  if e < 0 then Result := ms + 'E-' else Result := ms + 'E+';
  if Abs(e) < 10 then Result := Result + '0';
  Result := Result + IntToStr(Abs(e));
end;

function GeneralText(d: Double; width: Integer): string;
var
  ip: Int64;
  intDigits, neg, avail: Integer;
  s: string;
begin
  if d = 0 then exit('0');
  if d < 0 then neg := 1 else neg := 0;
  if Abs(d) >= 1e15 then
    intDigits := 99
  else
  begin
    ip := Trunc(Abs(d));
    intDigits := Length(IntToStr(ip));
  end;
  if intDigits + neg <= width then
  begin
    avail := width - neg - intDigits - 1;
    if avail > 9 then avail := 9;
    if avail < 0 then avail := 0;
    Str(d:0:avail, s);
    if Pos('.', s) > 0 then
    begin
      while s[Length(s)] = '0' do Delete(s, Length(s), 1);
      if s[Length(s)] = '.' then Delete(s, Length(s), 1);
    end;
    if (s <> '0') and (s <> '-0') then exit(s);
  end;
  avail := width - neg - 6;
  if avail < 0 then avail := 0;
  if avail > 5 then avail := 5;
  Result := SciText(d, avail);
  { trim the mantissa's trailing zeros }
  s := Copy(Result, 1, Pos('E', Result) - 1);
  if Pos('.', s) > 0 then
  begin
    while s[Length(s)] = '0' do Delete(s, Length(s), 1);
    if s[Length(s)] = '.' then Delete(s, Length(s), 1);
  end;
  Result := s + Copy(Result, Pos('E', Result), MaxInt);
end;

function FormatNumber(d: Double; const f: TCellFormat; width: Integer): string;
var
  n: Integer;
begin
  case f.Kind of
    fkGeneral: Result := GeneralText(d, width);
    fkFixed:
      begin
        Result := FixedAbs(d, f.Dec, False);
        if d < 0 then Result := '-' + Result;
      end;
    fkSci: Result := SciText(d, f.Dec);
    fkCurrency:
      begin
        Result := '$' + FixedAbs(d, f.Dec, True);
        if d < 0 then Result := '(' + Result + ')';
      end;
    fkComma:
      begin
        Result := FixedAbs(d, f.Dec, True);
        if d < 0 then Result := '(' + Result + ')';
      end;
    fkPercent:
      begin
        Result := FixedAbs(d * 100, f.Dec, False) + '%';
        if d < 0 then Result := '-' + Result;
      end;
    fkPlusMinus:
      begin
        n := Round(Abs(d));
        if n > 240 then n := 240;
        if n = 0 then Result := '.'
        else if d > 0 then Result := StringOfChar('+', n)
        else Result := StringOfChar('-', n);
      end;
    fkDate: Result := FormatSerial(d, f.Dec);
  else
    Result := GeneralText(d, width);
  end;
end;

function ValueText(cell: TCell; sh: TSheet; width: Integer): string;
var
  f: TCellFormat;
  d: Double;
begin
  f := EffectiveFormat(cell, sh);
  if f.Kind = fkHidden then exit('');
  if f.Kind = fkText then exit(cell.Raw);
  if CellNumber(cell, d) then
  begin
    if (d = 0) and not sh.ZeroDisplay then exit('');
    Result := FormatNumber(d, f, width);
  end
  else if cell.Cache <> '' then
    Result := cell.Cache
  else
    Result := cell.Raw;
end;

end.
