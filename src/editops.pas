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

{ Structural editing of a worksheet: copy, move, insert, delete, transpose and
  convert-to-values, with the reference rewriting each one needs.  Every
  change goes through the sheet's journalled methods, so Undo covers it. }
unit editops;
{$mode objfpc}{$H+}

interface

uses sheet;

const
  MaxEditCells = 300000;

{ Each returns '' on success or a short message describing why it refused. }
function CopyRange(sh: TSheet; const src, dst: TRange): string;
function MoveRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
function ValuesRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
function TransposeRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
function InsertRows(sh: TSheet; at, count: Integer): string;
function InsertCols(sh: TSheet; at, count: Integer): string;
function DeleteRows(sh: TSheet; r1, r2: Integer): string;
function DeleteCols(sh: TSheet; c1, c2: Integer): string;

implementation

uses Classes, SysUtils, formula, cellfmt;

type
  TSnap = record
    Exists: Boolean;
    Raw: string;
    Fmt: TCellFormat;
    Formula: TFormula;     { not owned: only valid while the source cell lives }
  end;
  TSnapArray = array of TSnap;

{ ---------------------------------------------------------------- mappers }

type
  TCopyMapper = class(TRefMapper)
  public
    DR, DC: Integer;
    function MapCell(var r, c: Integer; absR, absC: Boolean): Boolean; override;
  end;

  TMoveMapper = class(TRefMapper)
  public
    Src, Dst: TRange;
    DR, DC: Integer;
    function MapCell(var r, c: Integer; absR, absC: Boolean): Boolean; override;
  end;

  TInsertMapper = class(TRefMapper)
  public
    IsRow: Boolean;
    At, Count: Integer;
    function MapCell(var r, c: Integer; absR, absC: Boolean): Boolean; override;
  end;

  TDeleteMapper = class(TRefMapper)
  public
    IsRow: Boolean;
    First, Last: Integer;
    function MapCell(var r, c: Integer; absR, absC: Boolean): Boolean; override;
    function MapRange(var r1, c1, r2, c2: Integer; absR1, absC1, absR2, absC2: Boolean): Boolean; override;
  end;

function TCopyMapper.MapCell(var r, c: Integer; absR, absC: Boolean): Boolean;
begin
  if not absR then Inc(r, DR);
  if not absC then Inc(c, DC);
  Result := InBounds(r, c);
end;

function InRect(const g: TRange; r, c: Integer): Boolean;
begin
  Result := (r >= g.R1) and (r <= g.R2) and (c >= g.C1) and (c <= g.C2);
end;

{ References into the moved block follow it; references to cells the move
  overwrote (and that were not themselves moved) become ERR. }
function TMoveMapper.MapCell(var r, c: Integer; absR, absC: Boolean): Boolean;
begin
  Result := True;
  if InRect(Src, r, c) then
  begin
    Inc(r, DR);
    Inc(c, DC);
  end
  else if InRect(Dst, r, c) then
    Result := False;
end;

function TInsertMapper.MapCell(var r, c: Integer; absR, absC: Boolean): Boolean;
begin
  if IsRow then
  begin
    if r >= At then Inc(r, Count);
  end
  else if c >= At then Inc(c, Count);
  Result := InBounds(r, c);
end;

function TDeleteMapper.MapCell(var r, c: Integer; absR, absC: Boolean): Boolean;
var
  v: ^Integer;
begin
  if IsRow then v := @r else v := @c;
  Result := True;
  if (v^ >= First) and (v^ <= Last) then
    Result := False
  else if v^ > Last then
    Dec(v^, Last - First + 1);
end;

{ A range shrinks around deleted cells; it is only lost if all of it goes. }
function TDeleteMapper.MapRange(var r1, c1, r2, c2: Integer; absR1, absC1, absR2, absC2: Boolean): Boolean;
var
  a, b, n: Integer;
begin
  if IsRow then begin a := r1; b := r2; end else begin a := c1; b := c2; end;
  n := Last - First + 1;
  if (a >= First) and (b <= Last) then exit(False);        { wholly deleted }
  if a > Last then Dec(a, n)
  else if a >= First then a := First;                       { start was inside: first survivor }
  if b > Last then Dec(b, n)
  else if b >= First then b := First - 1;                   { end was inside: last survivor }
  if IsRow then begin r1 := a; r2 := b; end else begin c1 := a; c2 := b; end;
  Result := a <= b;
end;

{ ---------------------------------------------------------------- helpers }

procedure Snapshot(sh: TSheet; const g: TRange; out snap: TSnapArray);
var
  r, c, i, w: Integer;
  cell: TCell;
begin
  w := g.C2 - g.C1 + 1;
  SetLength(snap, (g.R2 - g.R1 + 1) * w);
  i := 0;
  for r := g.R1 to g.R2 do
    for c := g.C1 to g.C2 do
    begin
      cell := sh.Find(r, c);
      snap[i].Exists := cell <> nil;
      snap[i].Formula := nil;
      if cell <> nil then
      begin
        snap[i].Raw := cell.Raw;
        snap[i].Fmt := cell.Fmt;
        { the formula object dies with a removed cell, so keep only its text }
      end
      else
        snap[i].Raw := '';
      Inc(i);
    end;
end;

procedure Store(sh: TSheet; r, c: Integer; const s: TSnap; const raw: string);
var
  cell: TCell;
begin
  if not s.Exists then
  begin
    sh.Remove(r, c);
    exit;
  end;
  cell := sh.Put(r, c, raw);
  cell.Fmt := s.Fmt;
end;

function SizeOf(const g: TRange): Int64;
begin
  Result := Int64(g.R2 - g.R1 + 1) * (g.C2 - g.C1 + 1);
end;

{ text of a snapshot's formula after mapping, or the raw text when it is not one }
function MappedRaw(const raw: string; m: TRefMapper): string;
var
  f: TFormula;
  pos: Integer;
  d: Double;
begin
  Result := raw;
  if (raw = '') or not (raw[1] in ValueStarts) or IsNumberLiteral(raw, d) then exit;
  if CompileFormula(raw, f, pos) then
  begin
    Result := f.MappedText(m);
    f.Free;
  end;
end;

{ Re-map every formula in the sheet (and the range names) with m. }
type
  TRewriteCtx = record
    List: TList;
  end;
  PRewriteCtx = ^TRewriteCtx;

procedure CollectFormulas(cell: TCell; data: Pointer);
begin
  if cell.Formula <> nil then PRewriteCtx(data)^.List.Add(cell);
end;

procedure RewriteAll(sh: TSheet; m: TRefMapper);
var
  ctx: TRewriteCtx;
  cells: TList;
  i: Integer;
  cell: TCell;
  fresh: string;
  rows, cols: TList;
  r, c: Integer;
  txt: TStringList;
begin
  cells := TList.Create;
  txt := TStringList.Create;
  rows := TList.Create;
  cols := TList.Create;
  try
    ctx.List := cells;
    sh.EachCell(@CollectFormulas, @ctx);
    { work out every new text first: Put replaces the formula objects }
    for i := 0 to cells.Count - 1 do
    begin
      cell := TCell(cells[i]);
      txt.Add(cell.Formula.MappedText(m));
      rows.Add(Pointer(PtrInt(cell.Row)));
      cols.Add(Pointer(PtrInt(cell.Col)));
    end;
    for i := 0 to cells.Count - 1 do
    begin
      r := PtrInt(rows[i]);
      c := PtrInt(cols[i]);
      cell := sh.Find(r, c);
      if (cell <> nil) and (cell.Raw <> txt[i]) then
      begin
        fresh := txt[i];
        sh.Put(r, c, fresh);
      end;
    end;
    sh.RemapNames(m);
  finally
    cols.Free;
    rows.Free;
    txt.Free;
    cells.Free;
  end;
end;

{ ---------------------------------------------------------------- copy }

function CopyRange(sh: TSheet; const src, dst: TRange): string;
var
  h, w, tr, tc, i, j, k, nr, nc, rowsT, colsT: Integer;
  snap: TSnapArray;
  m: TCopyMapper;
  targetsR, targetsC: array of Integer;
  nT, t: Integer;
  texts: array of string;
begin
  Result := '';
  h := src.R2 - src.R1 + 1;
  w := src.C2 - src.C1 + 1;
  rowsT := dst.R2 - dst.R1 + 1;
  colsT := dst.C2 - dst.C1 + 1;
  { where copies go: every cell for a single-cell source, along the target
    for a single row or column source, otherwise just the top left }
  nT := 0;
  SetLength(targetsR, 0);
  SetLength(targetsC, 0);
  if (h = 1) and (w = 1) then
    { one cell fills the whole target }
  else if h = 1 then
    colsT := 1                       { a row is repeated down the target }
  else if w = 1 then
    rowsT := 1                       { a column is repeated across the target }
  else
  begin
    rowsT := 1;                      { a block: only the target's top left counts }
    colsT := 1;
  end;
  if Int64(rowsT) * colsT * h * w > MaxEditCells then exit('Range too large for this version');
  SetLength(targetsR, rowsT * colsT);
  SetLength(targetsC, rowsT * colsT);
  for i := 0 to rowsT - 1 do
    for j := 0 to colsT - 1 do
    begin
      targetsR[nT] := dst.R1 + i * h;
      targetsC[nT] := dst.C1 + j * w;
      Inc(nT);
    end;

  Snapshot(sh, src, snap);
  m := TCopyMapper.Create;
  try
    { compute everything before writing: the target may overlap the source }
    SetLength(texts, nT * h * w);
    k := 0;
    for t := 0 to nT - 1 do
    begin
      m.DR := targetsR[t] - src.R1;
      m.DC := targetsC[t] - src.C1;
      for i := 0 to h * w - 1 do
      begin
        if snap[i].Exists then texts[k] := MappedRaw(snap[i].Raw, m) else texts[k] := '';
        Inc(k);
      end;
    end;
    k := 0;
    for t := 0 to nT - 1 do
      for i := 0 to h - 1 do
        for j := 0 to w - 1 do
        begin
          nr := targetsR[t] + i;
          nc := targetsC[t] + j;
          if InBounds(nr, nc) then Store(sh, nr, nc, snap[i * w + j], texts[k]);
          Inc(k);
        end;
  finally
    m.Free;
  end;
end;

{ ---------------------------------------------------------------- move }

function MoveRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
var
  h, w, i, j: Integer;
  snap: TSnapArray;
  m: TMoveMapper;
begin
  Result := '';
  h := src.R2 - src.R1 + 1;
  w := src.C2 - src.C1 + 1;
  if (toR + h - 1 > MaxRow) or (toC + w - 1 > MaxCol) then exit('Cannot move there: it would leave the worksheet');
  if (toR = src.R1) and (toC = src.C1) then exit;
  if Int64(h) * w > MaxEditCells then exit('Range too large for this version');
  Snapshot(sh, src, snap);
  m := TMoveMapper.Create;
  try
    m.Src := src;
    m.Dst := NormRange(toR, toC, toR + h - 1, toC + w - 1);
    m.DR := toR - src.R1;
    m.DC := toC - src.C1;
    for i := 0 to h - 1 do
      for j := 0 to w - 1 do
        sh.Remove(src.R1 + i, src.C1 + j);
    for i := 0 to h - 1 do
      for j := 0 to w - 1 do
        Store(sh, toR + i, toC + j, snap[i * w + j], snap[i * w + j].Raw);
    { cells vacated by the move are not "overwritten": only the destination
      cells that were not part of the source are }
    RewriteAll(sh, m);
  finally
    m.Free;
  end;
end;

{ ---------------------------------------------------------------- value, transpose }

function ValuesRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
var
  h, w, i, j: Integer;
  snap: TSnapArray;
  vals: array of string;
  cell: TCell;
  d: Double;
  p: Char;
  t: string;
begin
  Result := '';
  h := src.R2 - src.R1 + 1;
  w := src.C2 - src.C1 + 1;
  if (toR + h - 1 > MaxRow) or (toC + w - 1 > MaxCol) then exit('Cannot copy there: it would leave the worksheet');
  if Int64(h) * w > MaxEditCells then exit('Range too large for this version');
  Snapshot(sh, src, snap);
  SetLength(vals, h * w);
  for i := 0 to h - 1 do
    for j := 0 to w - 1 do
    begin
      cell := sh.Find(src.R1 + i, src.C1 + j);
      vals[i * w + j] := '';
      if cell = nil then continue;
      if cell.Formula <> nil then
      begin
        if CellNumber(cell, d) then vals[i * w + j] := NumToRaw(d)
        else if TextOf(cell, p, t) then vals[i * w + j] := '''' + t
        else vals[i * w + j] := '';             { ERR / NA have no value to keep }
      end
      else
        vals[i * w + j] := cell.Raw;
    end;
  for i := 0 to h - 1 do
    for j := 0 to w - 1 do
    begin
      if snap[i * w + j].Exists then
        Store(sh, toR + i, toC + j, snap[i * w + j], vals[i * w + j])
      else
        sh.Remove(toR + i, toC + j);
    end;
end;

function TransposeRange(sh: TSheet; const src: TRange; toR, toC: Integer): string;
var
  h, w, i, j: Integer;
  snap: TSnapArray;
  vals: array of string;
  cell: TCell;
  d: Double;
  p: Char;
  t: string;
begin
  Result := '';
  h := src.R2 - src.R1 + 1;
  w := src.C2 - src.C1 + 1;
  if (toR + w - 1 > MaxRow) or (toC + h - 1 > MaxCol) then exit('Cannot copy there: it would leave the worksheet');
  if Int64(h) * w > MaxEditCells then exit('Range too large for this version');
  Snapshot(sh, src, snap);
  SetLength(vals, h * w);
  for i := 0 to h - 1 do
    for j := 0 to w - 1 do
    begin
      cell := sh.Find(src.R1 + i, src.C1 + j);
      vals[i * w + j] := '';
      if cell = nil then continue;
      { transposing, like Range Value, keeps values rather than formulas }
      if cell.Formula <> nil then
      begin
        if CellNumber(cell, d) then vals[i * w + j] := NumToRaw(d)
        else if TextOf(cell, p, t) then vals[i * w + j] := '''' + t;
      end
      else
        vals[i * w + j] := cell.Raw;
    end;
  for i := 0 to h - 1 do
    for j := 0 to w - 1 do
      Store(sh, toR + j, toC + i, snap[i * w + j], vals[i * w + j]);
end;

{ ---------------------------------------------------------------- insert, delete }

procedure AdjustTitles(sh: TSheet; isRow: Boolean; at, count: Integer);
begin
  { count > 0: insert before 'at'; count < 0: delete -count lines starting at 'at' }
  if isRow then
  begin
    if sh.TitleR2 = 0 then exit;
    if count > 0 then
    begin
      if sh.TitleR1 >= at then Inc(sh.TitleR1, count);
      if sh.TitleR2 >= at then Inc(sh.TitleR2, count);
    end
    else
      sh.TitleR1 := 0;
    if count < 0 then sh.TitleR2 := 0;
  end
  else
  begin
    if sh.TitleC2 = 0 then exit;
    if count > 0 then
    begin
      if sh.TitleC1 >= at then Inc(sh.TitleC1, count);
      if sh.TitleC2 >= at then Inc(sh.TitleC2, count);
    end
    else
    begin
      sh.TitleC1 := 0;
      sh.TitleC2 := 0;
    end;
  end;
end;

type
  TShiftItem = record
    R, C: Integer;
    Snap: TSnap;
  end;
  TShiftList = array of TShiftItem;

type
  TDetachCtx = record
    IsRow: Boolean;
    First, Last: Integer;
    Items: ^TShiftList;
    N: Integer;
  end;
  PDetachCtx = ^TDetachCtx;

procedure CollectInLines(cell: TCell; data: Pointer);
var
  ctx: PDetachCtx;
  v: Integer;
begin
  ctx := PDetachCtx(data);
  if ctx^.IsRow then v := cell.Row else v := cell.Col;
  if (v < ctx^.First) or (v > ctx^.Last) then exit;
  SetLength(ctx^.Items^, ctx^.N + 1);
  with ctx^.Items^[ctx^.N] do
  begin
    R := cell.Row;
    C := cell.Col;
    Snap.Exists := True;
    Snap.Raw := cell.Raw;
    Snap.Fmt := cell.Fmt;
    Snap.Formula := nil;
  end;
  Inc(ctx^.N);
end;

{ Collects every stored cell in rows (or columns) first..last. }
procedure Detach(sh: TSheet; isRow: Boolean; first, last: Integer; out items: TShiftList);
var
  ctx: TDetachCtx;
begin
  SetLength(items, 0);
  ctx.IsRow := isRow;
  ctx.First := first;
  ctx.Last := last;
  ctx.Items := @items;
  ctx.N := 0;
  sh.EachCell(@CollectInLines, @ctx);
end;

function InsertRows(sh: TSheet; at, count: Integer): string;
var
  items: TShiftList;
  i, maxR, maxC: Integer;
  m: TInsertMapper;
begin
  Result := '';
  sh.UsedExtent(maxR, maxC);
  if maxR + count > MaxRow then exit('Worksheet full: cannot insert that many rows');
  Detach(sh, True, at, MaxRow, items);
  for i := 0 to High(items) do sh.Remove(items[i].R, items[i].C);
  for i := 0 to High(items) do
    Store(sh, items[i].R + count, items[i].C, items[i].Snap, items[i].Snap.Raw);
  m := TInsertMapper.Create;
  try
    m.IsRow := True;
    m.At := at;
    m.Count := count;
    RewriteAll(sh, m);
  finally
    m.Free;
  end;
  AdjustTitles(sh, True, at, count);
end;

function InsertCols(sh: TSheet; at, count: Integer): string;
var
  items: TShiftList;
  i, maxR, maxC, c: Integer;
  m: TInsertMapper;
begin
  Result := '';
  sh.UsedExtent(maxR, maxC);
  if maxC + count > MaxCol then exit('Worksheet full: cannot insert that many columns');
  for c := MaxCol downto at + count do
    if sh.ColWidthSetting(c) <> sh.ColWidthSetting(c - count) then
      sh.SetColWidth(c, sh.ColWidthSetting(c - count));
  for c := at to at + count - 1 do
    if sh.ColWidthSetting(c) <> 0 then sh.SetColWidth(c, 0);
  Detach(sh, False, at, MaxCol, items);
  for i := 0 to High(items) do sh.Remove(items[i].R, items[i].C);
  for i := 0 to High(items) do
    Store(sh, items[i].R, items[i].C + count, items[i].Snap, items[i].Snap.Raw);
  m := TInsertMapper.Create;
  try
    m.IsRow := False;
    m.At := at;
    m.Count := count;
    RewriteAll(sh, m);
  finally
    m.Free;
  end;
  AdjustTitles(sh, False, at, count);
end;

function DeleteRows(sh: TSheet; r1, r2: Integer): string;
var
  items: TShiftList;
  i, n: Integer;
  m: TDeleteMapper;
begin
  Result := '';
  n := r2 - r1 + 1;
  Detach(sh, True, r1, MaxRow, items);
  for i := 0 to High(items) do sh.Remove(items[i].R, items[i].C);
  for i := 0 to High(items) do
    if items[i].R > r2 then
      Store(sh, items[i].R - n, items[i].C, items[i].Snap, items[i].Snap.Raw);
  m := TDeleteMapper.Create;
  try
    m.IsRow := True;
    m.First := r1;
    m.Last := r2;
    RewriteAll(sh, m);
  finally
    m.Free;
  end;
  AdjustTitles(sh, True, r1, -n);
end;

function DeleteCols(sh: TSheet; c1, c2: Integer): string;
var
  items: TShiftList;
  i, n, c: Integer;
  m: TDeleteMapper;
begin
  Result := '';
  n := c2 - c1 + 1;
  Detach(sh, False, c1, MaxCol, items);
  for i := 0 to High(items) do sh.Remove(items[i].R, items[i].C);
  for i := 0 to High(items) do
    if items[i].C > c2 then
      Store(sh, items[i].R, items[i].C - n, items[i].Snap, items[i].Snap.Raw);
  for c := c1 to MaxCol do
    if c + n <= MaxCol then
    begin
      if sh.ColWidthSetting(c) <> sh.ColWidthSetting(c + n) then
        sh.SetColWidth(c, sh.ColWidthSetting(c + n));
    end
    else if sh.ColWidthSetting(c) <> 0 then
      sh.SetColWidth(c, 0);
  m := TDeleteMapper.Create;
  try
    m.IsRow := False;
    m.First := c1;
    m.Last := c2;
    RewriteAll(sh, m);
  finally
    m.Free;
  end;
  AdjustTitles(sh, False, c1, -n);
end;

end.
