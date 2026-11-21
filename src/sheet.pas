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
  LabelPrefixes = ['''', '"', '^', '\'];
  MaxCol = 256;
  MaxRow = 8192;

type
  TFormatKind = (fkGeneral, fkFixed, fkSci, fkCurrency, fkComma, fkPercent,
                 fkPlusMinus, fkDate, fkText, fkHidden);

  { Dec is the number of decimal places; for fkDate it is the date/time
    format number: 1..5 date formats D1..D5, 6..9 time formats D6..D9. }
  TCellFormat = record
    Kind: TFormatKind;
    Dec: Integer;
    UseGlobal: Boolean;     { True: follow the worksheet's global format }
  end;

  TCell = class
  public
    Raw: string;      { as typed, including label prefix ' " ^ \ }
    Cache: string;    { computed value text (formulas); '' when none }
    Fmt: TCellFormat;
    constructor Create;
  end;

  TCellMap = specialize TDictionary<Int64, TCell>;

  { What a cell looked like at some moment (Exists = False: it was empty). }
  TCellState = record
    Exists: Boolean;
    Raw, Cache: string;
    Fmt: TCellFormat;
  end;
  TCellStateMap = specialize TDictionary<Int64, TCellState>;
  TWidthMap = specialize TDictionary<Integer, Integer>;

  TSheetGlobals = record
    Width: Integer;
    Fmt: TCellFormat;
    LabelPrefix: Char;
    ZeroDisplay: Boolean;
  end;

  { The "before" picture of everything one command changed: only the cells and
    column widths it touched, plus the worksheet-wide settings.  Reverting a
    change set returns the opposite change set, so undo can be undone. }
  TChangeSet = class
  public
    Cells: TCellStateMap;
    Widths: TWidthMap;
    Globals: TSheetGlobals;
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;           { cells + widths recorded }
  end;

  TSheet = class
  private
    FCells: TCellMap;
    FColWd: array[1..MaxCol] of Integer;   { 0 = use global width }
    function StateOf(key: Int64): TCellState;
    procedure ApplyState(key: Int64; const st: TCellState);
    procedure Touch(r, c: Integer);        { remember a cell before it changes }
    function GlobalsNow: TSheetGlobals;
    function Key(r, c: Integer): Int64; inline;
    function GetCount: Integer;
  public
    GlobalWidth: Integer;
    GlobalFmt: TCellFormat;
    GlobalLabelPrefix: Char;
    ZeroDisplay: Boolean;         { False: zero values are shown blank }
    { While set, every change is recorded here first (see TChangeSet).  The
      owner starts a group before a command and clears the property after. }
    Journal: TChangeSet;
    constructor Create;
    destructor Destroy; override;
    function Find(r, c: Integer): TCell;          { nil when empty }
    function Put(r, c: Integer; const raw: string): TCell;
    procedure Remove(r, c: Integer);
    procedure Clear;                              { cells and column widths }
    procedure SetLabelAlignment(ch: Char; all: Boolean; r1, c1, r2, c2: Integer);
    { Start recording a change group; the sheet keeps a reference in Journal. }
    function BeginChange: TChangeSet;
    { Undo/redo: put the sheet back as cs describes and return the change set
      that undoes that in turn.  The caller owns both. }
    function Revert(cs: TChangeSet): TChangeSet;
    procedure SetCellFormat(r, c: Integer; const fmt: TCellFormat; makeIt: Boolean);
    function NonEmpty(r, c: Integer): Boolean;    { has contents, not just a format }
    procedure UsedExtent(out maxR, maxC: Integer);
    function ColWidth(c: Integer): Integer;
    function ColWidthIsSet(c: Integer): Boolean;
    function ColWidthSetting(c: Integer): Integer;   { 0 = following the global width }
    procedure SetColWidth(c, w: Integer);         { 0 resets to global }
    property Count: Integer read GetCount;
  end;

function MakeFormat(k: TFormatKind; dec: Integer): TCellFormat;
function InBounds(r, c: Integer): Boolean;
function ColLetter(c: Integer): string;
function ParseAddr(const s: string; out c, r: Integer): Boolean;

implementation

constructor TChangeSet.Create;
begin
  inherited Create;
  Cells := TCellStateMap.Create;
  Widths := TWidthMap.Create;
end;

destructor TChangeSet.Destroy;
begin
  Cells.Free;
  Widths.Free;
  inherited Destroy;
end;

function TChangeSet.Count: Integer;
begin
  Result := Cells.Count + Widths.Count;
end;

function MakeFormat(k: TFormatKind; dec: Integer): TCellFormat;
begin
  Result.Kind := k;
  Result.Dec := dec;
  Result.UseGlobal := False;
end;

constructor TCell.Create;
begin
  inherited Create;
  Fmt := MakeFormat(fkGeneral, 0);
  Fmt.UseGlobal := True;
end;

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
  GlobalFmt := MakeFormat(fkGeneral, 0);
  GlobalLabelPrefix := '''';
  ZeroDisplay := True;
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
  Touch(r, c);
  Result := Find(r, c);
  if Result = nil then
  begin
    Result := TCell.Create;
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
    Touch(r, c);
    FCells.Remove(Key(r, c));
    cell.Free;
  end;
end;

procedure TSheet.Clear;
var
  cell: TCell;
  k: Int64;
  c: Integer;
begin
  if Journal <> nil then
  begin
    for k in FCells.Keys do Touch(Integer(k shr 16), Integer(k and $FFFF));
    for c := 1 to MaxCol do
      if (FColWd[c] <> 0) and not Journal.Widths.ContainsKey(c) then
        Journal.Widths.Add(c, FColWd[c]);
  end;
  for cell in FCells.Values do cell.Free;
  FCells.Clear;
  FillChar(FColWd, SizeOf(FColWd), 0);
end;

{ Change the prefix of existing labels to ch (repeating labels keep theirs).
  With all=True the rectangle is ignored. }
procedure TSheet.SetLabelAlignment(ch: Char; all: Boolean; r1, c1, r2, c2: Integer);
var
  pair: TCellMap.TDictionaryPair;
  r, c: Integer;
begin
  for pair in FCells do
  begin
    r := Integer(pair.Key shr 16);
    c := Integer(pair.Key and $FFFF);
    if not all and ((r < r1) or (r > r2) or (c < c1) or (c > c2)) then continue;
    if (pair.Value.Raw <> '') and (pair.Value.Raw[1] in ['''', '"', '^']) then
    begin
      Touch(r, c);
      pair.Value.Raw[1] := ch;
    end;
  end;
end;

function TSheet.GlobalsNow: TSheetGlobals;
begin
  Result.Width := GlobalWidth;
  Result.Fmt := GlobalFmt;
  Result.LabelPrefix := GlobalLabelPrefix;
  Result.ZeroDisplay := ZeroDisplay;
end;

function TSheet.StateOf(key: Int64): TCellState;
var
  cell: TCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Raw := '';
  Result.Cache := '';
  if FCells.TryGetValue(key, cell) then
  begin
    Result.Exists := True;
    Result.Raw := cell.Raw;
    Result.Cache := cell.Cache;
    Result.Fmt := cell.Fmt;
  end;
end;

procedure TSheet.ApplyState(key: Int64; const st: TCellState);
var
  cell: TCell;
begin
  if not st.Exists then
  begin
    if FCells.TryGetValue(key, cell) then
    begin
      FCells.Remove(key);
      cell.Free;
    end;
    exit;
  end;
  if not FCells.TryGetValue(key, cell) then
  begin
    cell := TCell.Create;
    FCells.Add(key, cell);
  end;
  cell.Raw := st.Raw;
  cell.Cache := st.Cache;
  cell.Fmt := st.Fmt;
end;

procedure TSheet.Touch(r, c: Integer);
var
  k: Int64;
begin
  if Journal = nil then exit;
  k := Key(r, c);
  if not Journal.Cells.ContainsKey(k) then Journal.Cells.Add(k, StateOf(k));
end;

function TSheet.BeginChange: TChangeSet;
begin
  Result := TChangeSet.Create;
  Result.Globals := GlobalsNow;
  Journal := Result;
end;

function TSheet.Revert(cs: TChangeSet): TChangeSet;
var
  pair: TCellStateMap.TDictionaryPair;
  wp: TWidthMap.TDictionaryPair;
begin
  Journal := nil;                          { never record while reverting }
  Result := TChangeSet.Create;
  Result.Globals := GlobalsNow;
  for pair in cs.Cells do
  begin
    Result.Cells.Add(pair.Key, StateOf(pair.Key));
    ApplyState(pair.Key, pair.Value);
  end;
  for wp in cs.Widths do
  begin
    Result.Widths.Add(wp.Key, FColWd[wp.Key]);
    FColWd[wp.Key] := wp.Value;
  end;
  GlobalWidth := cs.Globals.Width;
  GlobalFmt := cs.Globals.Fmt;
  GlobalLabelPrefix := cs.Globals.LabelPrefix;
  ZeroDisplay := cs.Globals.ZeroDisplay;
end;

procedure TSheet.SetCellFormat(r, c: Integer; const fmt: TCellFormat; makeIt: Boolean);
var
  cell: TCell;
begin
  cell := Find(r, c);
  if cell = nil then
  begin
    if not makeIt then exit;
    cell := Put(r, c, '');
  end
  else
    Touch(r, c);
  cell.Fmt := fmt;
end;

function TSheet.NonEmpty(r, c: Integer): Boolean;
var
  cell: TCell;
begin
  cell := Find(r, c);
  Result := (cell <> nil) and (cell.Raw <> '');
end;

procedure TSheet.UsedExtent(out maxR, maxC: Integer);
var
  pair: TCellMap.TDictionaryPair;
  r, c: Integer;
begin
  maxR := 1;
  maxC := 1;
  for pair in FCells do
  begin
    if pair.Value.Raw = '' then continue;
    r := Integer(pair.Key shr 16);
    c := Integer(pair.Key and $FFFF);
    if r > maxR then maxR := r;
    if c > maxC then maxC := c;
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

function TSheet.ColWidthSetting(c: Integer): Integer;
begin
  Result := FColWd[c];
end;

procedure TSheet.SetColWidth(c, w: Integer);
begin
  if (Journal <> nil) and not Journal.Widths.ContainsKey(c) then
    Journal.Widths.Add(c, FColWd[c]);
  FColWd[c] := w;
end;

end.
