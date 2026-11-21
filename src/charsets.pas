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

{ Character set conversion.  Inside the program text is UTF-8.  Worksheet
  files store labels in LICS (the Lotus International Character Set); DOS text
  files are usually code page 437.

  LICS 0x20..0x7E is ASCII.  The 0x80..0x9F cells hold combining accents and a
  few symbols; cells the published table leaves blank, and 0xFF, are undefined
  and convert to U+FFFD.  Characters with no LICS equivalent become '?'. }
unit charsets;
{$mode objfpc}{$H+}

interface

function LicsToUtf8(const s: string): string;
function Utf8ToLics(const s: string): string;
function Cp437ToUtf8(const s: string): string;
function Utf8ToCp437(const s: string): string;
function IsValidUtf8(const s: string): Boolean;
{ text of unknown origin: UTF-8 when it is valid UTF-8, otherwise code page 437 }
function DecodeTextBytes(const s: string): string;

implementation

const
  Lics: array[0..127] of Word = (
    { 80 } $0300, $0301, $0302, $0308, $0303, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    { 90 } $0300, $0301, $0302, $0308, $0303, $0131, $0331, $25B2, $25BC, 0, $00A0, $2190, 0, 0, 0, 0,
    { A0 } $0192, $00A1, $00A2, $00A3, $201C, $00A5, $20A7, $00A7, $00A4, $00A9, $00AA, $00AB, $0394, $03C0, $2265, $00F7,
    { B0 } $00B0, $00B1, $00B2, $00B3, $201E, $00B5, $00B6, $00B7, $2122, $00B9, $00BA, $00BB, $00BC, $00BD, $2264, $00BF,
    { C0 } $00C0, $00C1, $00C2, $00C3, $00C4, $00C5, $00C6, $00C7, $00C8, $00C9, $00CA, $00CB, $00CC, $00CD, $00CE, $00CF,
    { D0 } $00D0, $00D1, $00D2, $00D3, $00D4, $00D5, $00D6, $0152, $00D8, $00D9, $00DA, $00DB, $00DC, $0178, $00DE, $00DF,
    { E0 } $00E0, $00E1, $00E2, $00E3, $00E4, $00E5, $00E6, $00E7, $00E8, $00E9, $00EA, $00EB, $00EC, $00ED, $00EE, $00EF,
    { F0 } $00F0, $00F1, $00F2, $00F3, $00F4, $00F5, $00F6, $0153, $00F8, $00F9, $00FA, $00FB, $00FC, $00FF, $00FE, 0);

  Cp437: array[0..127] of Word = (
    { 80 } $00C7, $00FC, $00E9, $00E2, $00E4, $00E0, $00E5, $00E7, $00EA, $00EB, $00E8, $00EF, $00EE, $00EC, $00C4, $00C5,
    { 90 } $00C9, $00E6, $00C6, $00F4, $00F6, $00F2, $00FB, $00F9, $00FF, $00D6, $00DC, $00A2, $00A3, $00A5, $20A7, $0192,
    { A0 } $00E1, $00ED, $00F3, $00FA, $00F1, $00D1, $00AA, $00BA, $00BF, $2310, $00AC, $00BD, $00BC, $00A1, $00AB, $00BB,
    { B0 } $2591, $2592, $2593, $2502, $2524, $2561, $2562, $2556, $2555, $2563, $2551, $2557, $255D, $255C, $255B, $2510,
    { C0 } $2514, $2534, $252C, $251C, $2500, $253C, $255E, $255F, $255A, $2554, $2569, $2566, $2560, $2550, $256C, $2567,
    { D0 } $2568, $2564, $2565, $2559, $2558, $2552, $2553, $256B, $256A, $2518, $250C, $2588, $2584, $258C, $2590, $2580,
    { E0 } $03B1, $00DF, $0393, $03C0, $03A3, $03C3, $00B5, $03C4, $03A6, $0398, $03A9, $03B4, $221E, $03C6, $03B5, $2229,
    { F0 } $2261, $00B1, $2265, $2264, $2320, $2321, $00F7, $2248, $00B0, $2219, $00B7, $221A, $207F, $00B2, $25A0, $00A0);

function ToUtf8(const s: string; const tbl: array of Word): string;
var
  i: Integer;
  b: Byte;
  cp: Word;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    if b < $80 then
      Result := Result + s[i]
    else
    begin
      cp := tbl[b - $80];
      if cp = 0 then cp := $FFFD;
      Result := Result + UTF8Encode(WideChar(cp));
    end;
  end;
end;

function FromUtf8(const s: string; const tbl: array of Word): string;
var
  u: UnicodeString;
  i, j: Integer;
  found: Boolean;
begin
  Result := '';
  u := UTF8Decode(s);
  for i := 1 to Length(u) do
  begin
    if Ord(u[i]) < $80 then
    begin
      Result := Result + Chr(Ord(u[i]));
      continue;
    end;
    found := False;
    for j := 0 to 127 do
      if (tbl[j] <> 0) and (tbl[j] = Ord(u[i])) then
      begin
        Result := Result + Chr($80 + j);
        found := True;
        break;
      end;
    if not found then Result := Result + '?';
  end;
end;

function LicsToUtf8(const s: string): string;
begin
  Result := ToUtf8(s, Lics);
end;

function Utf8ToLics(const s: string): string;
begin
  Result := FromUtf8(s, Lics);
end;

function Cp437ToUtf8(const s: string): string;
begin
  Result := ToUtf8(s, Cp437);
end;

function Utf8ToCp437(const s: string): string;
begin
  Result := FromUtf8(s, Cp437);
end;

function IsValidUtf8(const s: string): Boolean;
var
  i, n, k: Integer;
  b: Byte;
begin
  Result := True;
  i := 1;
  while i <= Length(s) do
  begin
    b := Ord(s[i]);
    if b < $80 then n := 0
    else if (b and $E0) = $C0 then n := 1
    else if (b and $F0) = $E0 then n := 2
    else if (b and $F8) = $F0 then n := 3
    else exit(False);
    if (n > 0) and (b < $C2) then exit(False);
    if i + n > Length(s) then exit(False);
    for k := 1 to n do
      if (Ord(s[i + k]) and $C0) <> $80 then exit(False);
    Inc(i, n + 1);
  end;
end;

function DecodeTextBytes(const s: string): string;
begin
  if IsValidUtf8(s) then Result := s else Result := Cp437ToUtf8(s);
end;

end.
