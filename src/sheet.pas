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

{ The worksheet: sparse cell storage and per-column settings.  No UI. }
unit sheet;
{$mode objfpc}{$H+}

interface

uses SysUtils, Generics.Collections;

const
  MaxCol = 256;
  MaxRow = 8192;

type
  TCell = class
  public
    Raw: string;      { as typed, including label prefix ' " ^ \ }
    Cache: string;    { computed value text (formulas); '' when none }
    Fmt: Integer;     { -1 = general, >= 0 = currency with that many decimals }
  end;

  TCellMap = specialize TDictionary<Int64, TCell>;

  TSheet = class
  private
    FCells: TCellMap;
    FColWd: array[1..MaxCol] of Integer;   { 0 = use global width }
    function Key(r, c: Integer): Int64; inline;
    function GetCount: Integer;
  public
    GlobalWidth: Integer;
    constructor Create;
    destructor Destroy; override;
    function Find(r, c: Integer): TCell;          { nil when empty }
    function Put(r, c: Integer; const raw: string): TCell;
    procedure Remove(r, c: Integer);
    procedure Clear;
    procedure UsedExtent(out maxR, maxC: Integer);
    function ColWidth(c: Integer): Integer;
    function ColWidthIsSet(c: Integer): Boolean;
    procedure SetColWidth(c, w: Integer);         { 0 resets to global }
    property Count: Integer read GetCount;
  end;

function InBounds(r, c: Integer): Boolean;
function ColLetter(c: Integer): string;
function ParseAddr(const s: string; out c, r: Integer): Boolean;

implementation

function InBounds(r, c: Integer): Boolean;
begin
  Result := (r >= 1) and (r <= MaxRow) and (c >= 1) and (c <= MaxCol);
end;

function ColLetter(c: Integer): string;
begin
  if c <= 26 then
    Result := Chr(64 + c)
  else
    Result := Chr(64 + (c - 1) div 26) + Chr(65 + (c - 1) mod 26);
end;

function ParseAddr(const s: string; out c, r: Integer): Boolean;
var
  i: Integer;
  u: string;
begin
  u := UpperCase(Trim(s));
  c := 0;
  r := 0;
  i := 1;
  while (i <= Length(u)) and (u[i] in ['A'..'Z']) do
  begin
    c := c * 26 + Ord(u[i]) - 64;
    Inc(i);
  end;
  Result := (i > 1) and (i <= Length(u)) and (i <= 3) and (c <= MaxCol);
  if not Result then exit;
  r := StrToIntDef(Copy(u, i, 9), 0);
  Result := (r >= 1) and (r <= MaxRow);
end;

constructor TSheet.Create;
begin
  inherited Create;
  FCells := TCellMap.Create;
  GlobalWidth := 9;
end;

destructor TSheet.Destroy;
begin
  Clear;
  FCells.Free;
  inherited Destroy;
end;

function TSheet.Key(r, c: Integer): Int64;
begin
  Result := (Int64(r) shl 16) or c;
end;

function TSheet.GetCount: Integer;
begin
  Result := FCells.Count;
end;

function TSheet.Find(r, c: Integer): TCell;
begin
  if not FCells.TryGetValue(Key(r, c), Result) then Result := nil;
end;

function TSheet.Put(r, c: Integer; const raw: string): TCell;
begin
  Result := Find(r, c);
  if Result = nil then
  begin
    Result := TCell.Create;
    Result.Fmt := -1;
    FCells.Add(Key(r, c), Result);
  end;
  Result.Raw := raw;
  Result.Cache := '';
end;

procedure TSheet.Remove(r, c: Integer);
var
  cell: TCell;
begin
  cell := Find(r, c);
  if cell <> nil then
  begin
    FCells.Remove(Key(r, c));
    cell.Free;
  end;
end;

procedure TSheet.Clear;
var
  cell: TCell;
begin
  for cell in FCells.Values do cell.Free;
  FCells.Clear;
  FillChar(FColWd, SizeOf(FColWd), 0);
end;

procedure TSheet.UsedExtent(out maxR, maxC: Integer);
var
  k: Int64;
begin
  maxR := 1;
  maxC := 1;
  for k in FCells.Keys do
  begin
    if Integer(k shr 16) > maxR then maxR := Integer(k shr 16);
    if Integer(k and $FFFF) > maxC then maxC := Integer(k and $FFFF);
  end;
end;

function TSheet.ColWidth(c: Integer): Integer;
begin
  if FColWd[c] = 0 then Result := GlobalWidth else Result := FColWd[c];
end;

function TSheet.ColWidthIsSet(c: Integer): Boolean;
begin
  Result := FColWd[c] <> 0;
end;

procedure TSheet.SetColWidth(c, w: Integer);
begin
  FColWd[c] := w;
end;

end.
