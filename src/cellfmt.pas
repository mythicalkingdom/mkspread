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
  LabelPrefixes = ['''', '"', '^', '\'];

function IsLabel(cell: TCell): Boolean;
function ValueText(cell: TCell): string;

implementation

uses SysUtils;

function IsLabel(cell: TCell): Boolean;
begin
  Result := (cell.Raw <> '') and (cell.Raw[1] in LabelPrefixes);
end;

function ValueText(cell: TCell): string;
var
  s, ip, fp: string;
  d: Double;
  code, k: Integer;
  neg: Boolean;
begin
  s := cell.Cache;
  if s = '' then s := cell.Raw;
  if (s = '') or (s[1] in ['$', '%', '&']) then exit(s);
  Val(s, d, code);
  if code <> 0 then exit(s);
  if cell.Fmt >= 0 then
  begin
    neg := d < 0;
    Str(Abs(d):0:cell.Fmt, s);
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
    k := Length(ip) - 2;
    while k > 1 do
    begin
      Insert(',', ip, k);
      Dec(k, 3);
    end;
    s := '$' + ip + fp;
    if neg then s := '(' + s + ')';
    Result := s;
  end
  else
  begin
    Str(d:0:9, s);
    if Pos('.', s) > 0 then
    begin
      while s[Length(s)] = '0' do Delete(s, Length(s), 1);
      if s[Length(s)] = '.' then Delete(s, Length(s), 1);
    end;
    Result := s;
  end;
end;

end.
