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

{ @functions: dates and times.  Dates are serial numbers (see dates.pas). }
unit fn_time;
{$mode objfpc}{$H+}

interface

var
  { the clock @NOW reads; tests replace it }
  ClockNow: function: Double;

implementation

uses SysUtils, Math, formula, dates;

function SystemClock: Double;
begin
  Result := Now;
end;

{ ------------------------------------------------------------------ parsing text }

const
  Months: array[1..12] of string =
    ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');

function MonthOf(const s: string): Integer;
var
  i: Integer;
begin
  for i := 1 to 12 do
    if s = Months[i] then exit(i);
  Result := 0;
end;

function Digits(const s: string; out n: Integer): Boolean;
begin
  Result := (s <> '') and (Length(s) <= 4);
  if Result then
    n := StrToIntDef(s, -1);
  Result := Result and (n >= 0);
end;

{ the date formats: DD-MMM-YY, DD-MMM, MMM-YY, MM/DD/YY, MM/DD }
function ParseDate(const text: string; out serial: Integer): Boolean;
var
  t: string;
  parts: TStringArray;
  d, m, y, cy, cm, cd: Integer;
  nowD: Word;
  yy, mm, dd: Word;
begin
  Result := False;
  t := UpperCase(Trim(text));
  DecodeDate(ClockNow(), yy, mm, dd);
  cy := yy - 1900;
  if Pos('/', t) > 0 then
  begin
    parts := t.Split(['/']);
    if (Length(parts) < 2) or (Length(parts) > 3) then exit;
    if not (Digits(parts[0], m) and Digits(parts[1], d)) then exit;
    if Length(parts) = 3 then
    begin
      if not Digits(parts[2], y) then exit;
    end
    else
      y := cy;
  end
  else
  begin
    parts := t.Split(['-']);
    if Length(parts) = 3 then
    begin
      if not (Digits(parts[0], d) and Digits(parts[2], y)) then exit;
      m := MonthOf(parts[1]);
    end
    else if Length(parts) = 2 then
    begin
      if Digits(parts[0], d) then
      begin
        m := MonthOf(parts[1]);
        y := cy;
      end
      else
      begin
        m := MonthOf(parts[0]);
        d := 1;
        if not Digits(parts[1], y) then exit;
      end;
    end
    else
      exit;
  end;
  if m = 0 then exit;
  if y < 100 then y := y + 1900;
  serial := DateToSerial(y, m, d);
  Result := serial > 0;
end;

function ParseTime(const text: string; out fraction: Double): Boolean;
var
  t, ap: string;
  parts: TStringArray;
  h, mi, se, p: Integer;
begin
  Result := False;
  t := UpperCase(Trim(text));
  ap := '';
  if (Length(t) > 2) and (Copy(t, Length(t) - 1, 2) = 'AM') then ap := 'AM'
  else if (Length(t) > 2) and (Copy(t, Length(t) - 1, 2) = 'PM') then ap := 'PM';
  if ap <> '' then t := Trim(Copy(t, 1, Length(t) - 2));
  parts := t.Split([':']);
  if (Length(parts) < 2) or (Length(parts) > 3) then exit;
  if not (Digits(parts[0], h) and Digits(parts[1], mi)) then exit;
  se := 0;
  if (Length(parts) = 3) and not Digits(parts[2], se) then exit;
  if (mi > 59) or (se > 59) then exit;
  if ap <> '' then
  begin
    if (h < 1) or (h > 12) then exit;
    if h = 12 then h := 0;
    if ap = 'PM' then Inc(h, 12);
  end;
  if h > 23 then exit;
  p := h * 3600 + mi * 60 + se;
  fraction := p / 86400;
  Result := True;
end;

{ ------------------------------------------------------------------ functions }

{ @DATE(year, month, day): the year is counted from 1900 (0..199) }
function FnDate(const a: TNodeArray; s: TCellSource): TValue;
var
  y, m, d: Double;
  bad: TValue;
  n: Integer;
begin
  if not ArgNumber(a[0], s, y, bad) then exit(bad);
  if not ArgNumber(a[1], s, m, bad) then exit(bad);
  if not ArgNumber(a[2], s, d, bad) then exit(bad);
  y := Trunc(y); m := Trunc(m); d := Trunc(d);
  if (y < 0) or (y > 199) or (m < 1) or (m > 12) or (d < 1) or (d > 31) then exit(ErrValue);
  n := DateToSerial(Trunc(y) + 1900, Trunc(m), Trunc(d));
  if n = 0 then exit(ErrValue);
  Result := NumValue(n);
end;

function DatePart(const a: TNodeArray; s: TCellSource; which: Integer): TValue;
var
  x: Double;
  bad: TValue;
  y, m, d: Integer;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if not SerialToDate(Trunc(x), y, m, d) then exit(ErrValue);
  case which of
    1: Result := NumValue(d);
    2: Result := NumValue(m);
  else
    Result := NumValue(y - 1900);
  end;
end;

function FnDay(const a: TNodeArray; s: TCellSource): TValue; begin Result := DatePart(a, s, 1); end;
function FnMonth(const a: TNodeArray; s: TCellSource): TValue; begin Result := DatePart(a, s, 2); end;
function FnYear(const a: TNodeArray; s: TCellSource): TValue; begin Result := DatePart(a, s, 3); end;

function FnNow(const a: TNodeArray; s: TCellSource): TValue;
begin
  Result := NumValue(ClockNow());
end;

function FnTime(const a: TNodeArray; s: TCellSource): TValue;
var
  h, m, sec: Double;
  bad: TValue;
begin
  if not ArgNumber(a[0], s, h, bad) then exit(bad);
  if not ArgNumber(a[1], s, m, bad) then exit(bad);
  if not ArgNumber(a[2], s, sec, bad) then exit(bad);
  h := Trunc(h); m := Trunc(m); sec := Trunc(sec);
  if (h < 0) or (h > 23) or (m < 0) or (m > 59) or (sec < 0) or (sec > 59) then exit(ErrValue);
  Result := NumValue((h * 3600 + m * 60 + sec) / 86400);
end;

function TimePart(const a: TNodeArray; s: TCellSource; which: Integer): TValue;
var
  x: Double;
  bad: TValue;
  secs: Integer;
begin
  if not ArgNumber(a[0], s, x, bad) then exit(bad);
  if x < 0 then exit(ErrValue);
  secs := Round(Frac(x) * 86400) mod 86400;
  case which of
    1: Result := NumValue(secs div 3600);
    2: Result := NumValue((secs div 60) mod 60);
  else
    Result := NumValue(secs mod 60);
  end;
end;

function FnHour(const a: TNodeArray; s: TCellSource): TValue; begin Result := TimePart(a, s, 1); end;
function FnMinute(const a: TNodeArray; s: TCellSource): TValue; begin Result := TimePart(a, s, 2); end;
function FnSecond(const a: TNodeArray; s: TCellSource): TValue; begin Result := TimePart(a, s, 3); end;

function FnDateValue(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
  n: Integer;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not ParseDate(t, n) then exit(ErrValue);
  Result := NumValue(n);
end;

function FnTimeValue(const a: TNodeArray; s: TCellSource): TValue;
var
  t: string;
  bad: TValue;
  f: Double;
begin
  if not ArgString(a[0], s, t, bad) then exit(bad);
  if not ParseTime(t, f) then exit(ErrValue);
  Result := NumValue(f);
end;

initialization
  ClockNow := @SystemClock;
  RegisterFunc('DATE', 3, 3, 54, False, @FnDate);
  RegisterFunc('NOW', 0, 0, 55, False, @FnNow);
  RegisterFunc('DAY', 1, 1, 60, False, @FnDay);
  RegisterFunc('MONTH', 1, 1, 61, False, @FnMonth);
  RegisterFunc('YEAR', 1, 1, 62, False, @FnYear);
  RegisterFunc('TIME', 3, 3, 64, False, @FnTime);
  RegisterFunc('HOUR', 1, 1, 65, False, @FnHour);
  RegisterFunc('MINUTE', 1, 1, 66, False, @FnMinute);
  RegisterFunc('SECOND', 1, 1, 67, False, @FnSecond);
  RegisterFunc('DATEVALUE', 1, 1, 77, False, @FnDateValue);
  RegisterFunc('TIMEVALUE', 1, 1, 78, False, @FnTimeValue);
end.
