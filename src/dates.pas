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

{ Date and time serial numbers, the way the classic DOS spreadsheets count
  them: day 1 is 1-Jan-1900 and 1900 is (wrongly) treated as a leap year, so
  serial 60 is the non-existent 29-Feb-1900.  The quirk is kept on purpose so
  that macros and files that depend on serial numbers keep working. }
unit dates;
{$mode objfpc}{$H+}

interface

const
  MaxSerial = 73050;               { 31-Dec-2099 }

type
  { /Worksheet Global Default Other International }
  TIntl = record
    Decimal, Thousands: Char;       { punctuation in displayed numbers }
    ArgSep: Char;                   { separates the arguments of a function }
    CurrencySym: string;
    CurrencyAfter: Boolean;         { the symbol follows the number }
    NegParen: Boolean;              { negatives in parentheses (False: a minus sign) }
    DateStyle: Integer;             { 0 MM/DD/YY, 1 DD/MM/YY, 2 DD.MM.YY, 3 YY-MM-DD }
    TimeStyle: Integer;             { 0 HH:MM:SS, 1 HH.MM.SS, 2 HH,MM,SS, 3 HHhMMmSSs }
  end;

var
  Intl: TIntl;

procedure ResetIntl;

function SerialToDate(serial: Integer; out y, m, d: Integer): Boolean;
function DateToSerial(y, m, d: Integer): Integer;       { 0 when invalid }

{ kind 1..5 = date formats D1..D5, 6..9 = time formats D6..D9 }
function FormatSerial(value: Double; kind: Integer): string;

implementation

uses SysUtils;

const
  MonthNames: array[1..12] of string =
    ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

function SerialToDate(serial: Integer; out y, m, d: Integer): Boolean;
var
  dt: TDateTime;
  yy, mm, dd: Word;
begin
  Result := (serial >= 1) and (serial <= MaxSerial);
  y := 0; m := 0; d := 0;
  if not Result then exit;
  if serial = 60 then
  begin
    y := 1900; m := 2; d := 29;
    exit;
  end;
  if serial < 60 then dt := serial + 1 else dt := serial;   { Delphi day 0 = 30-Dec-1899 }
  DecodeDate(dt, yy, mm, dd);
  y := yy; m := mm; d := dd;
end;

function DateToSerial(y, m, d: Integer): Integer;
var
  dt: TDateTime;
begin
  Result := 0;
  if (y = 1900) and (m = 2) and (d = 29) then exit(60);
  if (y < 1900) or (y > 2099) or (m < 1) or (m > 12) or (d < 1) then exit;
  if not TryEncodeDate(y, m, d, dt) then exit;
  Result := Trunc(dt);
  if Result < 60 then Dec(Result);
end;

function Two(n: Integer): string;
begin
  Result := Format('%.2d', [n]);
end;

{ two digits, but four from the year 2000 on (as the original program showed) }
function YearText(y: Integer): string;
begin
  if y >= 2000 then Result := IntToStr(y) else Result := Two(y mod 100);
end;

procedure ResetIntl;
begin
  Intl.Decimal := '.';
  Intl.Thousands := ',';
  Intl.ArgSep := ',';
  Intl.CurrencySym := '$';
  Intl.CurrencyAfter := False;
  Intl.NegParen := True;
  Intl.DateStyle := 0;
  Intl.TimeStyle := 0;
end;

function FormatSerial(value: Double; kind: Integer): string;
var
  y, m, d, secs, h, mi, se, h12: Integer;
  ampm: string;
begin
  if kind <= 5 then
  begin
    if not SerialToDate(Trunc(value), y, m, d) then exit('ERR');
    case kind of
      1: Result := Two(d) + '-' + MonthNames[m] + '-' + YearText(y);
      2: Result := Two(d) + '-' + MonthNames[m];
      3: Result := MonthNames[m] + '-' + YearText(y);
      4: case Intl.DateStyle of
           1: Result := Two(d) + '/' + Two(m) + '/' + YearText(y);
           2: Result := Two(d) + '.' + Two(m) + '.' + YearText(y);
           3: Result := YearText(y) + '-' + Two(m) + '-' + Two(d);
         else Result := Two(m) + '/' + Two(d) + '/' + YearText(y);
         end;
      5: case Intl.DateStyle of
           1: Result := Two(d) + '/' + Two(m);
           2: Result := Two(d) + '.' + Two(m);
           3: Result := Two(m) + '-' + Two(d);
         else Result := Two(m) + '/' + Two(d);
         end;
    end;
  end
  else
  begin
    secs := Round(Frac(Abs(value)) * 86400) mod 86400;
    h := secs div 3600;
    mi := (secs div 60) mod 60;
    se := secs mod 60;
    if h >= 12 then ampm := 'PM' else ampm := 'AM';
    h12 := h mod 12;
    if h12 = 0 then h12 := 12;
    case kind of
      6: Result := Two(h12) + ':' + Two(mi) + ':' + Two(se) + ' ' + ampm;
      7: Result := Two(h12) + ':' + Two(mi) + ' ' + ampm;
      8: case Intl.TimeStyle of
           1: Result := Two(h) + '.' + Two(mi) + '.' + Two(se);
           2: Result := Two(h) + ',' + Two(mi) + ',' + Two(se);
           3: Result := Two(h) + 'h' + Two(mi) + 'm' + Two(se) + 's';
         else Result := Two(h) + ':' + Two(mi) + ':' + Two(se);
         end;
      9: case Intl.TimeStyle of
           1: Result := Two(h) + '.' + Two(mi);
           2: Result := Two(h) + ',' + Two(mi);
           3: Result := Two(h) + 'h' + Two(mi) + 'm';
         else Result := Two(h) + ':' + Two(mi);
         end;
    end;
  end;
end;

initialization
  ResetIntl;
end.
