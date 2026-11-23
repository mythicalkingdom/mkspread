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

{ Importing text files: a line per label, or numbers and quoted text split
  into columns (the classic behaviour), or proper CSV. }
unit textimport;
{$mode objfpc}{$H+}

interface

uses Classes, sheet;

{ Each line becomes a label in column toC, starting at row toR. }
function ImportLines(sh: TSheet; const fn: string; toR, toC: Integer): string;

{ Numbers and text in quotes become cells along the row; other text on a line
  is ignored.  Files ending .CSV are read as comma separated values instead:
  every non-empty field is imported, numbers as numbers and the rest as labels. }
function ImportNumbers(sh: TSheet; const fn: string; toR, toC: Integer): string;

{ the lines of a file, with the right character set and line ends handled }
function ReadTextLines(const fn: string; lines: TStrings): string;

{ fields of one CSV record }
procedure SplitCsv(const line: string; fields: TStrings);

implementation

uses SysUtils, charsets, formula, dates;

{ comma separated fields, or semicolons when the decimal separator is a comma }
function FieldSeparator: Char;
begin
  if Intl.Decimal = ',' then Result := ';' else Result := ',';
end;

{ a field as a number: the decimal separator of the chosen punctuation is accepted }
function FieldNumber(const s: string; out d: Double): Boolean;
var
  t: string;
begin
  t := Trim(s);
  if Intl.Decimal <> '.' then t := StringReplace(t, Intl.Decimal, '.', []);
  Result := IsNumberLiteral(t, d);
end;

function ReadTextLines(const fn: string; lines: TStrings): string;
var
  fs: TFileStream;
  raw, text: string;
  i, start: Integer;
begin
  Result := '';
  try
    fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  except
    exit('Cannot open ' + ExtractFileName(fn));
  end;
  try
    SetLength(raw, fs.Size);
    if Length(raw) > 0 then fs.ReadBuffer(raw[1], Length(raw));
  finally
    fs.Free;
  end;
  if (Length(raw) >= 3) and (raw[1] = #$EF) and (raw[2] = #$BB) and (raw[3] = #$BF) then
    Delete(raw, 1, 3);
  { a DOS end-of-file marker ends the text }
  i := Pos(#26, raw);
  if i > 0 then SetLength(raw, i - 1);
  text := DecodeTextBytes(raw);
  lines.Clear;
  start := 1;
  i := 1;
  while i <= Length(text) do
  begin
    if (text[i] = #13) or (text[i] = #10) then
    begin
      lines.Add(Copy(text, start, i - start));
      if (text[i] = #13) and (i < Length(text)) and (text[i + 1] = #10) then Inc(i);
      start := i + 1;
    end;
    Inc(i);
  end;
  if start <= Length(text) then lines.Add(Copy(text, start, MaxInt));
end;

function ImportLines(sh: TSheet; const fn: string; toR, toC: Integer): string;
var
  lines: TStringList;
  i: Integer;
  t: string;
begin
  lines := TStringList.Create;
  try
    Result := ReadTextLines(fn, lines);
    if Result <> '' then exit;
    if toR + lines.Count - 1 > MaxRow then
      exit('The file has more lines than fit below the pointer');
    for i := 0 to lines.Count - 1 do
    begin
      t := lines[i];
      if t = '' then continue;
      if Length(t) > 240 then SetLength(t, 240);
      { a label whatever it starts with: always the default-prefix label }
      sh.Put(toR + i, toC, sh.GlobalLabelPrefix + t);
    end;
  finally
    lines.Free;
  end;
end;

procedure SplitCsv(const line: string; fields: TStrings);
var
  i: Integer;
  cur: string;
  inQ, wasQ: Boolean;
begin
  fields.Clear;
  cur := '';
  inQ := False;
  wasQ := False;
  i := 1;
  while i <= Length(line) do
  begin
    if inQ then
    begin
      if line[i] = '"' then
      begin
        if (i < Length(line)) and (line[i + 1] = '"') then
        begin
          cur := cur + '"';
          Inc(i);
        end
        else
          inQ := False;
      end
      else
        cur := cur + line[i];
    end
    else if line[i] = '"' then
    begin
      inQ := True;
      wasQ := True;
    end
    else if line[i] = FieldSeparator then
    begin
      if wasQ then fields.AddObject(cur, TObject(1)) else fields.AddObject(cur, nil);
      cur := '';
      wasQ := False;
    end
    else
      cur := cur + line[i];
    Inc(i);
  end;
  if wasQ then fields.AddObject(cur, TObject(1)) else fields.AddObject(cur, nil);
end;

function LooksNumeric(const s: string; out d: Double): Boolean;
begin
  Result := FieldNumber(s, d);
end;

procedure PutField(sh: TSheet; r, c: Integer; const s: string; quoted: Boolean);
var
  d: Double;
begin
  if (not quoted) and LooksNumeric(s, d) then
    sh.Put(r, c, NumToRaw(d))
  else if s <> '' then
  begin
    if Length(s) > 240 then
      sh.Put(r, c, sh.GlobalLabelPrefix + Copy(s, 1, 240))
    else
      sh.Put(r, c, sh.GlobalLabelPrefix + s);
  end;
end;

function ImportCsv(sh: TSheet; lines: TStrings; toR, toC: Integer): string;
var
  i, k: Integer;
  fields: TStringList;
begin
  Result := '';
  fields := TStringList.Create;
  try
    for i := 0 to lines.Count - 1 do
    begin
      if toR + i > MaxRow then exit('The file has more lines than fit below the pointer');
      if lines[i] = '' then continue;
      SplitCsv(lines[i], fields);
      for k := 0 to fields.Count - 1 do
      begin
        if toC + k > MaxCol then
        begin
          Result := 'Some columns did not fit and were not imported';
          break;
        end;
        PutField(sh, toR + i, toC + k, fields[k], fields.Objects[k] <> nil);
      end;
    end;
  finally
    fields.Free;
  end;
end;

{ classic "numbers" import: fields are separated by spaces, tabs or commas;
  a field in quotes is a label, a numeric field is a number, anything else is
  skipped }
function ImportClassic(sh: TSheet; lines: TStrings; toR, toC: Integer): string;
var
  i, k, col: Integer;
  t, f: string;
  d: Double;
  q: Char;
begin
  Result := '';
  for i := 0 to lines.Count - 1 do
  begin
    if toR + i > MaxRow then exit('The file has more lines than fit below the pointer');
    t := lines[i];
    col := 0;
    k := 1;
    while k <= Length(t) do
    begin
      if t[k] in [' ', #9, FieldSeparator] then begin Inc(k); continue; end;
      if t[k] in ['"', ''''] then
      begin
        q := t[k];
        f := '';
        Inc(k);
        while (k <= Length(t)) and (t[k] <> q) do
        begin
          f := f + t[k];
          Inc(k);
        end;
        Inc(k);
        if toC + col <= MaxCol then PutField(sh, toR + i, toC + col, f, True);
        Inc(col);
      end
      else
      begin
        f := '';
        while (k <= Length(t)) and not (t[k] in [' ', #9, FieldSeparator]) do
        begin
          f := f + t[k];
          Inc(k);
        end;
        if FieldNumber(f, d) then
        begin
          if toC + col <= MaxCol then sh.Put(toR + i, toC + col, NumToRaw(d));
          Inc(col);
        end;
      end;
    end;
  end;
end;

function ImportNumbers(sh: TSheet; const fn: string; toR, toC: Integer): string;
var
  lines: TStringList;
begin
  lines := TStringList.Create;
  try
    Result := ReadTextLines(fn, lines);
    if Result <> '' then exit;
    if UpperCase(ExtractFileExt(fn)) = '.CSV' then
      Result := ImportCsv(sh, lines, toR, toC)
    else
      Result := ImportClassic(sh, lines, toR, toC);
  finally
    lines.Free;
  end;
end;

end.
