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

uses SysUtils, Classes, Generics.Collections, formula;

const
  LabelPrefixes = ['''', '"', '^', '\'];
  ValueStarts   = ['0'..'9', '+', '-', '.', '@', '(', '#', '$'];
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

  TRecalcOrder = (roNatural, roColumnwise, roRowwise);

  TRange = record
    R1, C1, R2, C2: Integer;
  end;

  TNameMap = specialize TDictionary<string, TRange>;

  TCell = class
  public
    Raw: string;         { as typed (formulas in canonical form), including label prefix ' " ^ \ }
    Fmt: TCellFormat;
    Formula: TFormula;   { compiled Raw when it is a formula, else nil }
    Val: TValue;         { last computed value of a formula }
    Row, Col: Integer;
    Pass: Integer;       { recalculation bookkeeping }
    Visiting: Boolean;
    constructor Create;
    destructor Destroy; override;
    { Sets Raw and, if it is a formula, compiles it. }
    procedure SetRaw(const s: string);
  end;

  TCellVisitor = procedure(cell: TCell; data: Pointer);

  TCellMap = specialize TDictionary<Int64, TCell>;

  { What a cell looked like at some moment (Exists = False: it was empty). }
  TCellState = record
    Exists: Boolean;
    Raw: string;
    Fmt: TCellFormat;
  end;
  TCellStateMap = specialize TDictionary<Int64, TCellState>;
  TWidthMap = specialize TDictionary<Integer, Integer>;

  TSheetGlobals = record
    Width: Integer;
    Fmt: TCellFormat;
    LabelPrefix: Char;
    ZeroDisplay: Boolean;
    RecalcOrder: TRecalcOrder;
    RecalcManual: Boolean;
    Iterations: Integer;
    TitleR1, TitleR2, TitleC1, TitleC2: Integer;
  end;

  { The "before" picture of everything one command changed: only the cells and
    column widths it touched, plus the worksheet-wide settings.  Reverting a
    change set returns the opposite change set, so undo can be undone. }
  TChangeSet = class
  public
    Cells: TCellStateMap;
    Widths: TWidthMap;
    Globals: TSheetGlobals;
    Names: TNameMap;                   { the range names as they were }
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;           { cells + widths recorded }
  end;

  TSheet = class
  private
    FCells: TCellMap;
    FColWd: array[1..MaxCol] of Integer;   { 0 = use global width }
    FNames: TNameMap;
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
    RecalcOrder: TRecalcOrder;
    RecalcManual: Boolean;        { True: recalculate only on F9 }
    Iterations: Integer;          { recalculation passes, 1..50 }
    Changed: Boolean;             { cell contents changed since the owner last looked }
    { Frozen titles: rows R1..R2 / columns C1..C2 stay on screen; 0 = none. }
    TitleR1, TitleR2, TitleC1, TitleC2: Integer;
    { While set, every change is recorded here first (see TChangeSet).  The
      owner starts a group before a command and clears the property after. }
    Journal: TChangeSet;
    constructor Create;
    destructor Destroy; override;
    function Find(r, c: Integer): TCell;          { nil when empty }
    function Put(r, c: Integer; const raw: string): TCell;
    procedure Remove(r, c: Integer);
    procedure Clear;                              { cells and column widths }
    procedure Reset;                              { cells, names and every setting }
    procedure SetLabelAlignment(ch: Char; all: Boolean; r1, c1, r2, c2: Integer);
    { Start recording a change group; the sheet keeps a reference in Journal. }
    function BeginChange: TChangeSet;
    { Undo/redo: put the sheet back as cs describes and return the change set
      that undoes that in turn.  The caller owns both. }
    function Revert(cs: TChangeSet): TChangeSet;
    procedure SetCellFormat(r, c: Integer; const fmt: TCellFormat; makeIt: Boolean);
    function NonEmpty(r, c: Integer): Boolean;    { has contents, not just a format }
    { range names (stored upper case) }
    function FindName(const name: string; out r: TRange): Boolean;
    procedure SetName(const name: string; const r: TRange);
    procedure DeleteName(const name: string);
    procedure ClearNames;
    function NameCount: Integer;
    procedure NameList(list: TStrings);           { sorted }
    procedure RemapNames(m: TRefMapper);          { names follow their cells }
    procedure CopyNamesTo(dest: TNameMap);
    procedure UsedExtent(out maxR, maxC: Integer);
    procedure EachCell(visit: TCellVisitor; data: Pointer);
    function ColWidth(c: Integer): Integer;
    function ColWidthIsSet(c: Integer): Boolean;
    function ColWidthSetting(c: Integer): Integer;   { 0 = following the global width }
    procedure SetColWidth(c, w: Integer);         { 0 resets to global }
    property Count: Integer read GetCount;
  end;

function NormRange(r1, c1, r2, c2: Integer): TRange;
function MakeFormat(k: TFormatKind; dec: Integer): TCellFormat;
function InBounds(r, c: Integer): Boolean;
function ColLetter(c: Integer): string;
function ParseAddr(const s: string; out c, r: Integer): Boolean;
{ "A1", "A1..C5", "a1.c5" or a range name -> normalised range }
function ParseRangeText(sh: TSheet; const s: string; out r: TRange): Boolean;

implementation

function ParseRangeText(sh: TSheet; const s: string; out r: TRange): Boolean;
var
  p, q, c1, r1, c2, r2: Integer;
  t: string;
begin
  t := Trim(s);
  p := Pos('.', t);
  if p = 0 then
  begin
    { a range name, or a single cell address }
    if IsValidName(t) and sh.FindName(t, r) then exit(True);
    Result := ParseAddr(t, c1, r1);
    c2 := c1;
    r2 := r1;
  end
  else
  begin
    q := p;
    while (q <= Length(t)) and (t[q] = '.') do Inc(q);
    Result := ParseAddr(Copy(t, 1, p - 1), c1, r1) and ParseAddr(Copy(t, q, MaxInt), c2, r2);
  end;
  if Result then r := NormRange(r1, c1, r2, c2);
end;

constructor TChangeSet.Create;
begin
  inherited Create;
  Cells := TCellStateMap.Create;
  Widths := TWidthMap.Create;
  Names := TNameMap.Create;
end;

destructor TChangeSet.Destroy;
begin
  Cells.Free;
  Widths.Free;
  Names.Free;
  inherited Destroy;
end;

function TChangeSet.Count: Integer;
begin
  Result := Cells.Count + Widths.Count;
end;

function NormRange(r1, c1, r2, c2: Integer): TRange;
begin
  if r1 <= r2 then begin Result.R1 := r1; Result.R2 := r2; end
  else begin Result.R1 := r2; Result.R2 := r1; end;
  if c1 <= c2 then begin Result.C1 := c1; Result.C2 := c2; end
  else begin Result.C1 := c2; Result.C2 := c1; end;
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
  Val := NumValue(0);
end;

destructor TCell.Destroy;
begin
  Formula.Free;
  inherited Destroy;
end;

procedure TCell.SetRaw(const s: string);
var
  f: TFormula;
  d: Double;
  pos: Integer;
begin
  Raw := s;
  FreeAndNil(Formula);
  if (s = '') or not (s[1] in ValueStarts) or IsNumberLiteral(s, d) then exit;
  if CompileFormula(s, f, pos) then
  begin
    Formula := f;
    Raw := f.Text;
  end;
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
  FNames := TNameMap.Create;
  GlobalWidth := 9;
  GlobalFmt := MakeFormat(fkGeneral, 0);
  GlobalLabelPrefix := '''';
  ZeroDisplay := True;
  Iterations := 1;
end;

destructor TSheet.Destroy;
begin
  Clear;
  FCells.Free;
  FNames.Free;
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
    Result.Row := r;
    Result.Col := c;
    FCells.Add(Key(r, c), Result);
  end;
  Result.SetRaw(raw);
  Changed := True;
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
    Changed := True;
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
  Changed := True;
  FillChar(FColWd, SizeOf(FColWd), 0);
end;

{ Change the prefix of existing labels to ch (repeating labels keep theirs).
  With all=True the rectangle is ignored. }
procedure TSheet.Reset;
begin
  Journal := nil;
  Clear;
  FNames.Clear;
  GlobalWidth := 9;
  GlobalFmt := MakeFormat(fkGeneral, 0);
  GlobalLabelPrefix := '''';
  ZeroDisplay := True;
  RecalcOrder := roNatural;
  RecalcManual := False;
  Iterations := 1;
  TitleR1 := 0; TitleR2 := 0; TitleC1 := 0; TitleC2 := 0;
  Changed := True;
end;

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
  Result.RecalcOrder := RecalcOrder;
  Result.RecalcManual := RecalcManual;
  Result.Iterations := Iterations;
  Result.TitleR1 := TitleR1;
  Result.TitleR2 := TitleR2;
  Result.TitleC1 := TitleC1;
  Result.TitleC2 := TitleC2;
end;

function TSheet.StateOf(key: Int64): TCellState;
var
  cell: TCell;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Raw := '';
  if FCells.TryGetValue(key, cell) then
  begin
    Result.Exists := True;
    Result.Raw := cell.Raw;
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
    Changed := True;
    exit;
  end;
  if not FCells.TryGetValue(key, cell) then
  begin
    cell := TCell.Create;
    cell.Row := Integer(key shr 16);
    cell.Col := Integer(key and $FFFF);
    FCells.Add(key, cell);
  end;
  cell.SetRaw(st.Raw);
  cell.Fmt := st.Fmt;
  Changed := True;
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
  CopyNamesTo(Result.Names);
  Journal := Result;
end;

function TSheet.Revert(cs: TChangeSet): TChangeSet;
var
  pair: TCellStateMap.TDictionaryPair;
  wp: TWidthMap.TDictionaryPair;
  np: TNameMap.TDictionaryPair;
begin
  Journal := nil;                          { never record while reverting }
  Result := TChangeSet.Create;
  Result.Globals := GlobalsNow;
  CopyNamesTo(Result.Names);
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
  RecalcOrder := cs.Globals.RecalcOrder;
  RecalcManual := cs.Globals.RecalcManual;
  Iterations := cs.Globals.Iterations;
  TitleR1 := cs.Globals.TitleR1;
  TitleR2 := cs.Globals.TitleR2;
  TitleC1 := cs.Globals.TitleC1;
  TitleC2 := cs.Globals.TitleC2;
  FNames.Clear;
  for np in cs.Names do FNames.Add(np.Key, np.Value);
  Changed := True;
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

procedure TSheet.CopyNamesTo(dest: TNameMap);
var
  np: TNameMap.TDictionaryPair;
begin
  dest.Clear;
  for np in FNames do dest.Add(np.Key, np.Value);
end;

function TSheet.FindName(const name: string; out r: TRange): Boolean;
begin
  Result := FNames.TryGetValue(UpperCase(name), r);
end;

procedure TSheet.SetName(const name: string; const r: TRange);
begin
  FNames.AddOrSetValue(UpperCase(name), r);
  Changed := True;
end;

procedure TSheet.DeleteName(const name: string);
begin
  FNames.Remove(UpperCase(name));
  Changed := True;
end;

procedure TSheet.ClearNames;
begin
  FNames.Clear;
  Changed := True;
end;

function TSheet.NameCount: Integer;
begin
  Result := FNames.Count;
end;

procedure TSheet.NameList(list: TStrings);
var
  np: TNameMap.TDictionaryPair;
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    for np in FNames do sl.Add(np.Key);
    sl.Sort;
    list.Assign(sl);
  finally
    sl.Free;
  end;
end;

procedure TSheet.RemapNames(m: TRefMapper);
var
  np: TNameMap.TDictionaryPair;
  keys: TStringList;
  i: Integer;
  r: TRange;
  r1, c1, r2, c2: Integer;
begin
  keys := TStringList.Create;
  try
    for np in FNames do keys.Add(np.Key);
    for i := 0 to keys.Count - 1 do
    begin
      r := FNames[keys[i]];
      r1 := r.R1; c1 := r.C1; r2 := r.R2; c2 := r.C2;
      if m.MapRange(r1, c1, r2, c2, False, False, False, False) then
        FNames[keys[i]] := NormRange(r1, c1, r2, c2)
      else
        FNames.Remove(keys[i]);
    end;
  finally
    keys.Free;
  end;
  Changed := True;
end;

function TSheet.NonEmpty(r, c: Integer): Boolean;
var
  cell: TCell;
begin
  cell := Find(r, c);
  Result := (cell <> nil) and (cell.Raw <> '');
end;

procedure TSheet.EachCell(visit: TCellVisitor; data: Pointer);
var
  cell: TCell;
begin
  for cell in FCells.Values do visit(cell, data);
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
