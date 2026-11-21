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

{ Editing UTF-8 strings by character position. }
unit u8edit;
{$mode objfpc}{$H+}

interface

function U8Len(const s: string): Integer;
{ pos is the number of characters before the insertion point (0 = at start) }
procedure U8Insert(var s: string; pos: Integer; const ch: string);
procedure U8DeleteAt(var s: string; pos: Integer);      { delete the char after pos }
function U8Copy(const s: string; first, count: Integer): string;   { 1-based, in characters }

implementation

function ByteOffset(const s: string; chars: Integer): Integer;
var
  i, n: Integer;
begin
  { returns the 1-based byte index of the character at 0-based index chars }
  i := 1;
  n := 0;
  while (i <= Length(s)) and (n < chars) do
  begin
    Inc(i);
    while (i <= Length(s)) and ((Ord(s[i]) and $C0) = $80) do Inc(i);
    Inc(n);
  end;
  Result := i;
end;

function U8Len(const s: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(s) do
    if (Ord(s[i]) and $C0) <> $80 then Inc(Result);
end;

procedure U8Insert(var s: string; pos: Integer; const ch: string);
begin
  Insert(ch, s, ByteOffset(s, pos));
end;

procedure U8DeleteAt(var s: string; pos: Integer);
var
  a, b: Integer;
begin
  a := ByteOffset(s, pos);
  if a > Length(s) then exit;
  b := ByteOffset(s, pos + 1);
  Delete(s, a, b - a);
end;

function U8Copy(const s: string; first, count: Integer): string;
var
  a, b: Integer;
begin
  a := ByteOffset(s, first - 1);
  b := ByteOffset(s, first - 1 + count);
  Result := Copy(s, a, b - a);
end;

end.
