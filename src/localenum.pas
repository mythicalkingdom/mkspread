{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }

{ Numbers and formulas as text in the punctuation of /Worksheet Global Default
  Other International Punctuation.  Inside the program and in worksheet files a
  number has a decimal point and the arguments of a function are separated by
  commas; what is typed, shown for editing or imported from text uses the chosen
  separators.  A range written A1..B2 is the same everywhere. }
unit localenum;
{$mode objfpc}{$H+}

interface

{ typed text -> the canonical form (outside quotes) }
function LocalToCanonical(const s: string): string;
{ the canonical form -> what the user would type }
function CanonicalToLocal(const s: string): string;
{ does this character start a number in the current punctuation? }
function StartsNumber(ch: Char): Boolean;

implementation

uses dates, sheet;

function Convert(const s: string; toLocal: Boolean): string;
var
  i: Integer;
  ch, quote: Char;
  dec, arg: Char;
begin
  dec := Intl.Decimal;
  arg := Intl.ArgSep;
  if (dec = '.') and (arg = ',') then exit(s);
  Result := s;
  quote := #0;
  i := 1;
  while i <= Length(Result) do
  begin
    ch := Result[i];
    if quote <> #0 then
    begin
      if ch = quote then quote := #0;
    end
    else if (ch = '"') or (ch = '''') then
      quote := ch
    else if (ch = '.') and (((i < Length(Result)) and (Result[i + 1] = '.')) or ((i > 1) and (Result[i - 1] = '.'))) then
      { the range operator stays }
    else if toLocal then
    begin
      if ch = '.' then Result[i] := dec
      else if ch = ',' then Result[i] := arg;
    end
    else
    begin
      if ch = dec then Result[i] := '.'
      else if ch = arg then Result[i] := ',';
    end;
    Inc(i);
  end;
end;

function LocalToCanonical(const s: string): string;
begin
  Result := Convert(s, False);
end;

function CanonicalToLocal(const s: string): string;
begin
  Result := Convert(s, True);
end;

function StartsNumber(ch: Char): Boolean;
begin
  Result := (ch in ValueStarts) or (ch = Intl.Decimal);
end;

end.
