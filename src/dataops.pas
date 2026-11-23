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

{ The arithmetic behind the /Data commands, free of prompts and screens: fill,
  sort, query, distribution, matrices, regression and parse. }
unit dataops;
{$mode objfpc}{$H+}

interface

uses Classes, sheet;

{ Fills g with start, start+step, ... down each column in turn, stopping at stop
  or the end of the range.  Returns how many cells were filled. }
function FillRange(sh: TSheet; const g: TRange; start, step, stop: Double): Integer;

{ Sorts the rows of g by the column keyCol (and keyCol2 when > 0): numbers before
  empty cells, labels (ignoring case), numbers. }
function SortRows(sh: TSheet; const g: TRange; keyCol: Integer; asc: Boolean;
                  keyCol2: Integer; asc2: Boolean): string;

{ Frequency distribution: counts of the values in each bin of the bins column,
  written in the column to its right, with one extra cell for "more". }
function Distribution(sh: TSheet; const values, bins: TRange): string;

function MatrixInvert(sh: TSheet; const src: TRange; toR, toC: Integer): string;
function MatrixMultiply(sh: TSheet; const a, b: TRange; toR, toC: Integer): string;

{ Linear regression of y on the columns of x; the report goes at (toR, toC). }
function Regression(sh: TSheet; const xr, yr: TRange; toR, toC: Integer; zeroIntercept: Boolean): string;

{ ---- /Data Query: the first row of input holds field names ---- }
{ rows (absolute row numbers) of the input records that meet the criteria }
function QueryMatches(sh: TSheet; const input, crit: TRange; rows: TList): string;
function QueryExtract(sh: TSheet; const input, crit, outp: TRange; unique: Boolean): string;
function QueryDelete(sh: TSheet; const input, crit: TRange; out deleted: Integer): string;

{ ---- /Data Parse ---- }
{ a format line (without the leading |) for the sample text }
function MakeFormatLine(const sample: string): string;
{ splits the labels of the input column into cells using the format lines in it }
function ParseLabels(sh: TSheet; const input: TRange; toR, toC: Integer): string;

implementation

uses SysUtils, Math, formula, cellfmt, editops, fn_fin, fn_time;

{ ------------------------------------------------------------------ fill }

function FillRange(sh: TSheet; const g: TRange; start, step, stop: Double): Integer;
var
  r, c: Integer;
  v: Double;
begin
  Result := 0;
  v := start;
  for c := g.C1 to g.C2 do        { the original program empties the range first }
    for r := g.R1 to g.R2 do sh.Remove(r, c);
  for c := g.C1 to g.C2 do
    for r := g.R1 to g.R2 do
    begin
      if ((step >= 0) and (v > stop)) or ((step < 0) and (v < stop)) then exit;
      sh.Put(r, c, NumToRaw(v));
      Inc(Result);
      v := v + step;
    end;
end;

{ ------------------------------------------------------------------ sort }

type
  TSortKey = record
    Kind: Integer;                 { 0 empty, 1 number, 2 text }
    Num: Double;
    Txt: string;
  end;

function KeyOf(sh: TSheet; r, c: Integer): TSortKey;
var
  v: TValue;
begin
  Result.Kind := 0;
  Result.Num := 0;
  Result.Txt := '';
  v := CellValueOf(sh.Find(r, c));
  if v.IsEmpty then exit;
  case v.Kind of
    vkNum: begin Result.Kind := 1; Result.Num := v.Num; end;
    vkStr: begin Result.Kind := 2; Result.Txt := v.Str; end;
  else
    Result.Kind := 2;
  end;
end;

function KindRank(kind: Integer): Integer;
begin
  case kind of
    1: Result := 2;
    2: Result := 1;
  else
    Result := 0;
  end;
end;

{ < 0, 0, > 0.  Ascending: empty cells, then labels (ignoring case), then numbers;
  descending is exactly the reverse (as seen in the original program). }
function CompareKeys(const a, b: TSortKey; asc: Boolean): Integer;
begin
  if a.Kind <> b.Kind then
  begin
    { rank: empty 0, text 1, number 2 (Kind: 0 empty, 1 number, 2 text) }
    Result := KindRank(a.Kind) - KindRank(b.Kind);
  end
  else if a.Kind = 1 then
  begin
    if a.Num < b.Num then Result := -1 else if a.Num > b.Num then Result := 1 else Result := 0;
  end
  else if a.Kind = 2 then
    Result := CompareText(a.Txt, b.Txt)
  else
    Result := 0;
  if not asc then Result := -Result;
end;

function SortRows(sh: TSheet; const g: TRange; keyCol: Integer; asc: Boolean;
                  keyCol2: Integer; asc2: Boolean): string;
var
  n, i, j, t: Integer;
  k1, k2: array of TSortKey;
  order: array of Integer;
  cmp: Integer;
begin
  Result := '';
  if (keyCol < g.C1) or (keyCol > g.C2) then exit('The sort key is outside the data range');
  if (keyCol2 > 0) and ((keyCol2 < g.C1) or (keyCol2 > g.C2)) then exit('The second key is outside the data range');
  n := g.R2 - g.R1 + 1;
  SetLength(k1, n);
  SetLength(k2, n);
  SetLength(order, n);
  for i := 0 to n - 1 do
  begin
    order[i] := i;
    k1[i] := KeyOf(sh, g.R1 + i, keyCol);
    if keyCol2 > 0 then k2[i] := KeyOf(sh, g.R1 + i, keyCol2);
  end;
  { insertion sort: stable, and fine for worksheet sizes }
  for i := 1 to n - 1 do
  begin
    t := order[i];
    j := i - 1;
    while j >= 0 do
    begin
      cmp := CompareKeys(k1[order[j]], k1[t], asc);
      if (cmp = 0) and (keyCol2 > 0) then cmp := CompareKeys(k2[order[j]], k2[t], asc2);
      if cmp <= 0 then break;
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := t;
  end;
  Result := ReorderRows(sh, g, order);
end;

{ ------------------------------------------------------------------ distribution }

function Distribution(sh: TSheet; const values, bins: TRange): string;
var
  nb, i, r, c, bi: Integer;
  b: array of Double;
  cnt: array of Integer;
  v: TValue;
begin
  Result := '';
  if bins.C1 <> bins.C2 then exit('The bin range must be a single column');
  if bins.C2 >= MaxCol then exit('There is no room to the right of the bin range');
  nb := bins.R2 - bins.R1 + 1;
  SetLength(b, nb);
  SetLength(cnt, nb + 1);
  for i := 0 to nb - 1 do
  begin
    v := CellValueOf(sh.Find(bins.R1 + i, bins.C1));
    if (v.Kind <> vkNum) or v.IsEmpty then exit('Bin values must be numbers');
    if (i > 0) and (v.Num < b[i - 1]) then exit('Bin values must be in ascending order');
    b[i] := v.Num;
  end;
  if bins.R2 + 1 > MaxRow then exit('There is no room below the bin range');
  for r := values.R1 to values.R2 do
    for c := values.C1 to values.C2 do
    begin
      v := CellValueOf(sh.Find(r, c));
      if (v.Kind <> vkNum) or v.IsEmpty then continue;           { text and blanks are ignored }
      bi := nb;
      for i := 0 to nb - 1 do
        if v.Num <= b[i] then begin bi := i; break; end;
      Inc(cnt[bi]);
    end;
  for i := 0 to nb do
    sh.Put(bins.R1 + i, bins.C2 + 1, IntToStr(cnt[i]));
end;

{ ------------------------------------------------------------------ matrices }

type
  TMat = array of array of Double;

function ReadMatrix(sh: TSheet; const g: TRange; out m: TMat): Boolean;
var
  i, j: Integer;
  v: TValue;
begin
  Result := False;
  SetLength(m, g.R2 - g.R1 + 1, g.C2 - g.C1 + 1);
  for i := 0 to High(m) do
    for j := 0 to High(m[i]) do
    begin
      v := CellValueOf(sh.Find(g.R1 + i, g.C1 + j));
      if (v.Kind <> vkNum) then exit;
      m[i][j] := v.Num;
    end;
  Result := True;
end;

function WriteMatrix(sh: TSheet; const m: TMat; toR, toC: Integer): string;
var
  i, j: Integer;
begin
  Result := '';
  if (Length(m) = 0) or (toR + Length(m) - 1 > MaxRow) or (toC + Length(m[0]) - 1 > MaxCol) then
    exit('The result does not fit on the worksheet');
  for i := 0 to High(m) do
    for j := 0 to High(m[i]) do
      sh.Put(toR + i, toC + j, NumToRaw(m[i][j]));
end;

{ Gauss-Jordan with partial pivoting; False if singular }
function Invert(var a: TMat): Boolean;
var
  n, i, j, k, p: Integer;
  inv: TMat;
  t, f: Double;
begin
  n := Length(a);
  SetLength(inv, n, n);
  for i := 0 to n - 1 do
    for j := 0 to n - 1 do
      if i = j then inv[i][j] := 1 else inv[i][j] := 0;
  for k := 0 to n - 1 do
  begin
    p := k;
    for i := k + 1 to n - 1 do
      if Abs(a[i][k]) > Abs(a[p][k]) then p := i;
    if Abs(a[p][k]) < 1e-12 then exit(False);
    if p <> k then
      for j := 0 to n - 1 do
      begin
        t := a[k][j]; a[k][j] := a[p][j]; a[p][j] := t;
        t := inv[k][j]; inv[k][j] := inv[p][j]; inv[p][j] := t;
      end;
    f := a[k][k];
    for j := 0 to n - 1 do
    begin
      a[k][j] := a[k][j] / f;
      inv[k][j] := inv[k][j] / f;
    end;
    for i := 0 to n - 1 do
      if i <> k then
      begin
        f := a[i][k];
        if f <> 0 then
          for j := 0 to n - 1 do
          begin
            a[i][j] := a[i][j] - f * a[k][j];
            inv[i][j] := inv[i][j] - f * inv[k][j];
          end;
      end;
  end;
  a := inv;
  Result := True;
end;

function MatrixInvert(sh: TSheet; const src: TRange; toR, toC: Integer): string;
var
  m: TMat;
begin
  if (src.R2 - src.R1) <> (src.C2 - src.C1) then exit('The matrix must be square');
  if src.R2 - src.R1 + 1 > 90 then exit('A matrix can be at most 90 by 90');
  if not ReadMatrix(sh, src, m) then exit('Matrix cells must contain numbers');
  if not Invert(m) then exit('The matrix is singular and cannot be inverted');
  Result := WriteMatrix(sh, m, toR, toC);
end;

function MatrixMultiply(sh: TSheet; const a, b: TRange; toR, toC: Integer): string;
var
  x, y, p: TMat;
  i, j, k: Integer;
begin
  if (a.C2 - a.C1) <> (b.R2 - b.R1) then
    exit('The columns of the first matrix must equal the rows of the second');
  if not (ReadMatrix(sh, a, x) and ReadMatrix(sh, b, y)) then exit('Matrix cells must contain numbers');
  SetLength(p, Length(x), Length(y[0]));
  for i := 0 to High(x) do
    for j := 0 to High(y[0]) do
    begin
      p[i][j] := 0;
      for k := 0 to High(y) do p[i][j] := p[i][j] + x[i][k] * y[k][j];
    end;
  Result := WriteMatrix(sh, p, toR, toC);
end;

{ ------------------------------------------------------------------ regression }

function Regression(sh: TSheet; const xr, yr: TRange; toR, toC: Integer; zeroIntercept: Boolean): string;
var
  x, y: TMat;
  rowsAreObs: Boolean;
  n, k, p, i, j, l, df: Integer;
  xm: TMat;                         { design matrix, n by p }
  xtx, inv: TMat;
  xty, beta: array of Double;
  sse, sst, ymean, fit, sigma2, r2, resid: Double;
  yv: array of Double;
  lines: array[0..8] of string;
  coef: array of Double;
  se: array of Double;
begin
  if not (ReadMatrix(sh, xr, x) and ReadMatrix(sh, yr, y)) then exit('Regression ranges must contain numbers');
  { observations run down the columns, unless y is a single row }
  if (Length(y) = 1) and (Length(y[0]) > 1) then
  begin
    rowsAreObs := False;
    n := Length(y[0]);
    k := Length(x);
    if Length(x[0]) <> n then exit('The X and Y ranges must have the same number of observations');
  end
  else
  begin
    rowsAreObs := True;
    if Length(y[0]) <> 1 then exit('The Y range must be a single column or row');
    n := Length(y);
    k := Length(x[0]);
    if Length(x) <> n then exit('The X and Y ranges must have the same number of observations');
  end;
  if k > 16 then exit('At most 16 X variables');
  if zeroIntercept then p := k else p := k + 1;
  if n <= p then exit('There are too few observations');
  SetLength(yv, n);
  SetLength(xm, n, p);
  for i := 0 to n - 1 do
  begin
    if rowsAreObs then yv[i] := y[i][0] else yv[i] := y[0][i];
    j := 0;
    if not zeroIntercept then begin xm[i][0] := 1; j := 1; end;
    for l := 0 to k - 1 do
    begin
      if rowsAreObs then xm[i][j + l] := x[i][l] else xm[i][j + l] := x[l][i];
    end;
  end;
  SetLength(xtx, p, p);
  SetLength(xty, p);
  for j := 0 to p - 1 do
  begin
    xty[j] := 0;
    for i := 0 to n - 1 do xty[j] := xty[j] + xm[i][j] * yv[i];
    for l := 0 to p - 1 do
    begin
      xtx[j][l] := 0;
      for i := 0 to n - 1 do xtx[j][l] := xtx[j][l] + xm[i][j] * xm[i][l];
    end;
  end;
  inv := xtx;
  if not Invert(inv) then exit('The X values are linearly dependent: no regression');
  SetLength(beta, p);
  for j := 0 to p - 1 do
  begin
    beta[j] := 0;
    for l := 0 to p - 1 do beta[j] := beta[j] + inv[j][l] * xty[l];
  end;
  ymean := 0;
  for i := 0 to n - 1 do ymean := ymean + yv[i];
  ymean := ymean / n;
  sse := 0;
  sst := 0;
  for i := 0 to n - 1 do
  begin
    fit := 0;
    for j := 0 to p - 1 do fit := fit + xm[i][j] * beta[j];
    resid := yv[i] - fit;
    sse := sse + resid * resid;
    sst := sst + Sqr(yv[i] - ymean);
  end;
  df := n - p;
  sigma2 := sse / df;
  if sst > 0 then r2 := 1 - sse / sst else r2 := 0;
  SetLength(coef, k);
  SetLength(se, k);
  for l := 0 to k - 1 do
  begin
    j := l;
    if not zeroIntercept then j := l + 1;
    coef[l] := beta[j];
    se[l] := Sqrt(Max(0, sigma2 * inv[j][j]));
  end;
  if toR + 8 > MaxRow then exit('The report does not fit below the output cell');
  if toC + 2 + k > MaxCol then exit('The report does not fit to the right of the output cell');
  sh.Put(toR, toC + 1, '''Regression Output:');
  sh.Put(toR + 1, toC, '''Constant');
  if zeroIntercept then sh.Put(toR + 1, toC + 3, '0') else sh.Put(toR + 1, toC + 3, NumToRaw(beta[0]));
  sh.Put(toR + 2, toC, '''Std Err of Y Est');
  sh.Put(toR + 2, toC + 3, NumToRaw(Sqrt(sigma2)));
  sh.Put(toR + 3, toC, '''R Squared');
  sh.Put(toR + 3, toC + 3, NumToRaw(r2));
  sh.Put(toR + 4, toC, '''No. of Observations');
  sh.Put(toR + 4, toC + 3, IntToStr(n));
  sh.Put(toR + 5, toC, '''Degrees of Freedom');
  sh.Put(toR + 5, toC + 3, IntToStr(df));
  sh.Put(toR + 7, toC, '''X Coefficient(s)');
  sh.Put(toR + 8, toC, '''Std Err of Coef.');
  for l := 0 to k - 1 do
  begin
    sh.Put(toR + 7, toC + 2 + l, NumToRaw(coef[l]));
    sh.Put(toR + 8, toC + 2 + l, NumToRaw(se[l]));
  end;
  Result := '';
end;

{ ------------------------------------------------------------------ query }

type
  TCritMap = array of Integer;        { criteria column -> input column, -1 none }

function FieldColumn(sh: TSheet; const input: TRange; const name: TValue): Integer;
var
  c: Integer;
  v: TValue;
begin
  Result := -1;
  if name.Kind <> vkStr then exit;
  for c := input.C1 to input.C2 do
  begin
    v := CellValueOf(sh.Find(input.R1, c));
    if (v.Kind = vkStr) and (CompareText(v.Str, name.Str) = 0) then exit(c);
  end;
end;

function RecordMeets(sh: TSheet; const input, crit: TRange; const map: TCritMap; r: Integer): Boolean;
var
  cr, k: Integer;
  hdr: TValue;
  rowOk: Boolean;
begin
  if crit.R2 <= crit.R1 then exit(True);                  { no criteria rows: every record }
  for cr := crit.R1 + 1 to crit.R2 do
  begin
    rowOk := True;
    for k := 0 to High(map) do
    begin
      hdr := CellValueOf(sh.Find(cr, crit.C1 + k));
      if hdr.IsEmpty then continue;
      if (map[k] < 0) or not DbCriterionMet(hdr, CellValueOf(sh.Find(r, map[k]))) then
      begin
        rowOk := False;
        break;
      end;
    end;
    if rowOk then exit(True);
  end;
  Result := False;
end;

function BuildMap(sh: TSheet; const input, crit: TRange): TCritMap;
var
  k: Integer;
begin
  SetLength(Result, crit.C2 - crit.C1 + 1);
  for k := 0 to High(Result) do
    Result[k] := FieldColumn(sh, input, CellValueOf(sh.Find(crit.R1, crit.C1 + k)));
end;

function QueryMatches(sh: TSheet; const input, crit: TRange; rows: TList): string;
var
  map: TCritMap;
  r: Integer;
begin
  Result := '';
  rows.Clear;
  if input.R2 <= input.R1 then exit('The input range needs field names and at least one record');
  map := BuildMap(sh, input, crit);
  for r := input.R1 + 1 to input.R2 do
    if RecordMeets(sh, input, crit, map, r) then rows.Add(Pointer(PtrInt(r)));
end;

function QueryExtract(sh: TSheet; const input, crit, outp: TRange; unique: Boolean): string;
var
  rows: TList;
  msg: string;
  fcols: array of Integer;
  c, k, i, j, outRow, maxRows: Integer;
  v: TValue;
  seen: TStringList;
  sig: string;
  cell: TCell;
begin
  rows := TList.Create;
  seen := TStringList.Create;
  try
    msg := QueryMatches(sh, input, crit, rows);
    if msg <> '' then exit(msg);
    SetLength(fcols, outp.C2 - outp.C1 + 1);
    for k := 0 to High(fcols) do
      fcols[k] := FieldColumn(sh, input, CellValueOf(sh.Find(outp.R1, outp.C1 + k)));
    if outp.R2 > outp.R1 then maxRows := outp.R2 - outp.R1 else maxRows := MaxRow - outp.R1;
    { clear the area under the field names }
    for c := outp.C1 to outp.C2 do
      for i := outp.R1 + 1 to outp.R1 + maxRows do
        if sh.Find(i, c) <> nil then sh.Remove(i, c);
    outRow := outp.R1;
    for i := 0 to rows.Count - 1 do
    begin
      sig := '';
      for k := 0 to High(fcols) do
      begin
        if fcols[k] < 0 then v := EmptyValue else v := CellValueOf(sh.Find(PtrInt(rows[i]), fcols[k]));
        case v.Kind of
          vkNum: sig := sig + #1 + NumToRaw(v.Num);
          vkStr: sig := sig + #2 + v.Str;
        else
          sig := sig + #3;
        end;
        sig := sig + #0;
      end;
      if unique then
      begin
        if seen.IndexOf(sig) >= 0 then continue;
        seen.Add(sig);
      end;
      if outRow - outp.R1 >= maxRows then exit('There are more matching records than the output range holds');
      Inc(outRow);
      for k := 0 to High(fcols) do
      begin
        if fcols[k] < 0 then continue;
        cell := sh.Find(PtrInt(rows[i]), fcols[k]);
        v := CellValueOf(cell);
        if v.IsEmpty then continue;
        case v.Kind of
          vkNum: sh.Put(outRow, outp.C1 + k, NumToRaw(v.Num));
          vkStr: sh.Put(outRow, outp.C1 + k, sh.GlobalLabelPrefix + v.Str);
          vkNA: sh.Put(outRow, outp.C1 + k, '@NA');
        else
          sh.Put(outRow, outp.C1 + k, '@ERR');
        end;
      end;
    end;
  finally
    seen.Free;
    rows.Free;
  end;
end;

function QueryDelete(sh: TSheet; const input, crit: TRange; out deleted: Integer): string;
var
  rows: TList;
  keep: array of Integer;
  del: array of Boolean;
  n, i, r, p: Integer;
  data: TRange;
begin
  deleted := 0;
  rows := TList.Create;
  try
    Result := QueryMatches(sh, input, crit, rows);
    if Result <> '' then exit;
    n := input.R2 - input.R1;                 { number of records }
    SetLength(del, n);
    for i := 0 to rows.Count - 1 do del[PtrInt(rows[i]) - input.R1 - 1] := True;
    SetLength(keep, n);
    p := 0;
    for i := 0 to n - 1 do
      if del[i] then Inc(deleted)
      else begin keep[p] := i; Inc(p); end;
    for i := p to n - 1 do keep[i] := -1;
    data := NormRange(input.R1 + 1, input.C1, input.R2, input.C2);
    if deleted > 0 then Result := ReorderRows(sh, data, keep);
  finally
    rows.Free;
  end;
end;

{ ------------------------------------------------------------------ parse }

function MakeFormatLine(const sample: string): string;
var
  i: Integer;
  startOfToken: Boolean;
  token: string;
  j: Integer;
  d: Double;
begin
  Result := '';
  i := 1;
  while i <= Length(sample) do
  begin
    if sample[i] = ' ' then
    begin
      Result := Result + '*';
      Inc(i);
      continue;
    end;
    j := i;
    while (j <= Length(sample)) and (sample[j] <> ' ') do Inc(j);
    token := Copy(sample, i, j - i);
    if IsNumberLiteral(StringReplace(token, ',', '', [rfReplaceAll]), d) then Result := Result + 'V'
    else Result := Result + 'L';
    Result := Result + StringOfChar('>', Length(token) - 1);
    i := j;
  end;
  startOfToken := True;
  if startOfToken then ;
end;

function ParseLabels(sh: TSheet; const input: TRange; toR, toC: Integer): string;
var
  r, outRow, i, e, col, s: Integer;
  cell: TCell;
  p: Char;
  t, fmt, fld: string;
  d: Double;
  ser: Integer;
  fr: Double;
  haveFmt: Boolean;
begin
  Result := '';
  haveFmt := False;
  fmt := '';
  outRow := toR;
  for r := input.R1 to input.R2 do
  begin
    cell := sh.Find(r, input.C1);
    if (cell = nil) or not TextOf(cell, p, t) then
    begin
      if not haveFmt and (r = input.R1) then exit('Parse input range must start with format line');
      continue;
    end;
    if p = '|' then
    begin
      fmt := t;
      haveFmt := True;
      continue;
    end;
    if not haveFmt then exit('Parse input range must start with format line');
    if outRow > MaxRow then exit('The output does not fit on the worksheet');
    col := toC;
    i := 1;
    while i <= Length(fmt) do
    begin
      if not (UpCase(fmt[i]) in ['L', 'V', 'D', 'T', 'S']) then begin Inc(i); continue; end;
      s := i;
      e := i;
      while (e < Length(fmt)) and (fmt[e + 1] = '>') do Inc(e);
      fld := Trim(Copy(t, s, e - s + 1));
      i := e + 1;
      if UpCase(fmt[s]) = 'S' then continue;
      if col > MaxCol then exit('Too many fields for the columns available');
      if fld <> '' then
        case UpCase(fmt[s]) of
          'V':
            if IsNumberLiteral(StringReplace(fld, ',', '', [rfReplaceAll]), d) then
              sh.Put(outRow, col, NumToRaw(d))
            else
              sh.Put(outRow, col, sh.GlobalLabelPrefix + fld);
          'D':
            if ParseDate(fld, ser) then sh.Put(outRow, col, IntToStr(ser))
            else sh.Put(outRow, col, sh.GlobalLabelPrefix + fld);
          'T':
            if ParseTime(fld, fr) then sh.Put(outRow, col, NumToRaw(fr))
            else sh.Put(outRow, col, sh.GlobalLabelPrefix + fld);
        else
          sh.Put(outRow, col, sh.GlobalLabelPrefix + fld);
        end;
      Inc(col);
    end;
    Inc(outRow);
  end;
end;

end.
