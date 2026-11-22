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

{ @functions: statistics over lists, financial, and database. }
unit fn_fin;
{$mode objfpc}{$H+}

interface

implementation

uses SysUtils, Math, formula;

{ ------------------------------------------------------------------ statistics }

type
  TStat = class(TAccumulator)
  public
    Vals: array of Double;       { numeric items; text counts as 0 }
    Cnt: Integer;                { every non-empty item (text included) }
    Err, NA: Boolean;
    procedure AddNum(x: Double);
    procedure Add(const v: TValue); override;
  end;

procedure TStat.AddNum(x: Double);
begin
  SetLength(Vals, Length(Vals) + 1);
  Vals[High(Vals)] := x;
  Inc(Cnt);
end;

procedure TStat.Add(const v: TValue);
begin
  case v.Kind of
    vkErr: Err := True;
    vkNA: NA := True;
    vkNum: if not v.IsEmpty then AddNum(v.Num);
    vkStr: AddNum(0);
  end;
end;

{ Gathers the arguments of a list function: ranges and names cell by cell,
  anything else as a single value.  False: the result is st.Err / st.NA. }
function Gather(const a: TNodeArray; src: TCellSource; st: TStat; textInScalars: Boolean): Boolean;
var
  i: Integer;
  r1, c1, r2, c2: Integer;
  v: TValue;
  d: Double;
begin
  for i := 0 to High(a) do
    if RectOf(a[i], src, r1, c1, r2, c2) then
      src.Accumulate(r1, c1, r2, c2, st)
    else
    begin
      v := a[i].Eval(src);
      if v.Kind = vkErr then st.Err := True
      else if v.Kind = vkNA then st.NA := True
      else if Numeric(v, d) then st.AddNum(d)
      else if textInScalars then st.AddNum(0)
      else st.Err := True;
    end;
  Result := not (st.Err or st.NA);
end;

function StatError(st: TStat): TValue;
begin
  if st.Err then Result := ErrValue else Result := NAValue;
end;

function FnSum(const a: TNodeArray; s: TCellSource): TValue;
var
  st: TStat;
  i: Integer;
  t: Double;
begin
  st := TStat.Create;
  try
    if not Gather(a, s, st, False) then exit(StatError(st));
    t := 0;
    for i := 0 to High(st.Vals) do t := t + st.Vals[i];
    Result := NumValue(t);
  finally
    st.Free;
  end;
end;

function FnAvg(const a: TNodeArray; s: TCellSource): TValue;
var
  st: TStat;
  i: Integer;
  t: Double;
begin
  st := TStat.Create;
  try
    if not Gather(a, s, st, True) then exit(StatError(st));
    if Length(st.Vals) = 0 then exit(ErrValue);
    t := 0;
    for i := 0 to High(st.Vals) do t := t + st.Vals[i];
    Result := NumValue(t / Length(st.Vals));
  finally
    st.Free;
  end;
end;

function FnCount(const a: TNodeArray; s: TCellSource): TValue;
var
  st: TStat;
begin
  st := TStat.Create;
  try
    if not Gather(a, s, st, True) then exit(StatError(st));
    Result := NumValue(st.Cnt);
  finally
    st.Free;
  end;
end;

function MinMax(const a: TNodeArray; s: TCellSource; wantMax: Boolean): TValue;
var
  st: TStat;
  i: Integer;
  m: Double;
begin
  st := TStat.Create;
  try
    if not Gather(a, s, st, True) then exit(StatError(st));
    if Length(st.Vals) = 0 then exit(NumValue(0));
    m := st.Vals[0];
    for i := 1 to High(st.Vals) do
      if (wantMax and (st.Vals[i] > m)) or (not wantMax and (st.Vals[i] < m)) then m := st.Vals[i];
    Result := NumValue(m);
  finally
    st.Free;
  end;
end;

function FnMin(const a: TNodeArray; s: TCellSource): TValue; begin Result := MinMax(a, s, False); end;
function FnMax(const a: TNodeArray; s: TCellSource): TValue; begin Result := MinMax(a, s, True); end;

{ population variance, the way the spreadsheet defines it }
function Variance(const v: array of Double; out ok: Boolean): Double;
var
  i: Integer;
  mean, t: Double;
begin
  ok := Length(v) > 0;
  Result := 0;
  if not ok then exit;
  mean := 0;
  for i := 0 to High(v) do mean := mean + v[i];
  mean := mean / Length(v);
  t := 0;
  for i := 0 to High(v) do t := t + Sqr(v[i] - mean);
  Result := t / Length(v);
end;

function VarStd(const a: TNodeArray; s: TCellSource; wantStd: Boolean): TValue;
var
  st: TStat;
  x: Double;
  ok: Boolean;
begin
  st := TStat.Create;
  try
    if not Gather(a, s, st, True) then exit(StatError(st));
    x := Variance(st.Vals, ok);
    if not ok then exit(ErrValue);
    if wantStd then x := Sqrt(x);
    Result := NumValue(x);
  finally
    st.Free;
  end;
end;

function FnVar(const a: TNodeArray; s: TCellSource): TValue; begin Result := VarStd(a, s, False); end;
function FnStd(const a: TNodeArray; s: TCellSource): TValue; begin Result := VarStd(a, s, True); end;

{ ------------------------------------------------------------------ financial }

function Num3(const a: TNodeArray; s: TCellSource; out x, y, z: Double; out bad: TValue): Boolean;
begin
  Result := ArgNumber(a[0], s, x, bad) and ArgNumber(a[1], s, y, bad) and ArgNumber(a[2], s, z, bad);
end;

function FnPmt(const a: TNodeArray; s: TCellSource): TValue;
var
  p, i, n: Double;
  bad: TValue;
begin
  if not Num3(a, s, p, i, n, bad) then exit(bad);
  if n <= 0 then exit(ErrValue);
  if i = 0 then exit(NumValue(p / n));
  if i <= -1 then exit(ErrValue);
  Result := NumValue(p * i / (1 - Power(1 + i, -n)));
end;

function FnPv(const a: TNodeArray; s: TCellSource): TValue;
var
  p, i, n: Double;
  bad: TValue;
begin
  if not Num3(a, s, p, i, n, bad) then exit(bad);
  if n <= 0 then exit(ErrValue);
  if i = 0 then exit(NumValue(p * n));
  if i <= -1 then exit(ErrValue);
  Result := NumValue(p * (1 - Power(1 + i, -n)) / i);
end;

function FnFv(const a: TNodeArray; s: TCellSource): TValue;
var
  p, i, n: Double;
  bad: TValue;
begin
  if not Num3(a, s, p, i, n, bad) then exit(bad);
  if n <= 0 then exit(ErrValue);
  if i = 0 then exit(NumValue(p * n));
  if i <= -1 then exit(ErrValue);
  Result := NumValue(p * (Power(1 + i, n) - 1) / i);
end;

{ the numbers of a range, in order (rows, then columns); text and blanks are skipped }
procedure RangeNumbers(src: TCellSource; r1, c1, r2, c2: Integer; out v: array of Double; out n: Integer);
var
  r, c: Integer;
  x: TValue;
begin
  n := 0;
  for r := r1 to r2 do
    for c := c1 to c2 do
    begin
      x := src.CellValue(r, c);
      if (x.Kind = vkNum) and not x.IsEmpty then
      begin
        if n <= High(v) then v[n] := x.Num;
        Inc(n);
      end;
    end;
end;

function FnNpv(const a: TNodeArray; s: TCellSource): TValue;
var
  i: Double;
  bad: TValue;
  r1, c1, r2, c2, n, k: Integer;
  v: array of Double;
  t: Double;
begin
  if not ArgNumber(a[0], s, i, bad) then exit(bad);
  if not RectOf(a[1], s, r1, c1, r2, c2) then exit(ErrValue);
  if i <= -1 then exit(ErrValue);
  SetLength(v, (r2 - r1 + 1) * (c2 - c1 + 1));
  RangeNumbers(s, r1, c1, r2, c2, v, n);
  t := 0;
  for k := 1 to n do t := t + v[k - 1] / Power(1 + i, k);
  Result := NumValue(t);
end;

{ @IRR(guess, range): Newton's method on the net present value }
function FnIrr(const a: TNodeArray; s: TCellSource): TValue;
var
  guess, r, f, df, nr: Double;
  bad: TValue;
  r1, c1, r2, c2, n, k, it: Integer;
  v: array of Double;
  hasPos, hasNeg: Boolean;
begin
  if not ArgNumber(a[0], s, guess, bad) then exit(bad);
  if not RectOf(a[1], s, r1, c1, r2, c2) then exit(ErrValue);
  SetLength(v, (r2 - r1 + 1) * (c2 - c1 + 1));
  RangeNumbers(s, r1, c1, r2, c2, v, n);
  hasPos := False;
  hasNeg := False;
  for k := 0 to n - 1 do
  begin
    if v[k] > 0 then hasPos := True;
    if v[k] < 0 then hasNeg := True;
  end;
  if not (hasPos and hasNeg) then exit(ErrValue);
  r := guess;
  for it := 1 to 50 do
  begin
    if r <= -1 then exit(ErrValue);
    f := 0;
    df := 0;
    for k := 1 to n do
    begin
      f := f + v[k - 1] / Power(1 + r, k);
      df := df - k * v[k - 1] / Power(1 + r, k + 1);
    end;
    if df = 0 then exit(ErrValue);
    nr := r - f / df;
    if Abs(nr - r) < 1e-10 then exit(NumValue(nr));
    r := nr;
  end;
  Result := ErrValue;
end;

{ @TERM(payment, interest, future value): periods to reach the future value }
function FnTerm(const a: TNodeArray; s: TCellSource): TValue;
var
  p, i, fv: Double;
  bad: TValue;
begin
  if not Num3(a, s, p, i, fv, bad) then exit(bad);
  if (p <= 0) or (i <= 0) or (fv <= 0) then exit(ErrValue);
  Result := NumValue(Ln(1 + fv * i / p) / Ln(1 + i));
end;

function FnCterm(const a: TNodeArray; s: TCellSource): TValue;
var
  i, fv, pv: Double;
  bad: TValue;
begin
  if not Num3(a, s, i, fv, pv, bad) then exit(bad);
  if (i <= 0) or (fv <= 0) or (pv <= 0) then exit(ErrValue);
  Result := NumValue(Ln(fv / pv) / Ln(1 + i));
end;

function FnRate(const a: TNodeArray; s: TCellSource): TValue;
var
  fv, pv, n: Double;
  bad: TValue;
begin
  if not Num3(a, s, fv, pv, n, bad) then exit(bad);
  if (fv <= 0) or (pv <= 0) or (n <= 0) then exit(ErrValue);
  Result := NumValue(Power(fv / pv, 1 / n) - 1);
end;

function FnSln(const a: TNodeArray; s: TCellSource): TValue;
var
  cost, salv, life: Double;
  bad: TValue;
begin
  if not Num3(a, s, cost, salv, life, bad) then exit(bad);
  if life <= 0 then exit(ErrValue);
  Result := NumValue((cost - salv) / life);
end;

function FnSyd(const a: TNodeArray; s: TCellSource): TValue;
var
  cost, salv, life, per: Double;
  bad: TValue;
begin
  if not Num3(a, s, cost, salv, life, bad) then exit(bad);
  if not ArgNumber(a[3], s, per, bad) then exit(bad);
  if (life <= 0) or (per < 1) or (per > life) then exit(ErrValue);
  Result := NumValue((cost - salv) * (life - per + 1) * 2 / (life * (life + 1)));
end;

function FnDdb(const a: TNodeArray; s: TCellSource): TValue;
var
  cost, salv, life, per, bv, dep: Double;
  bad: TValue;
  p: Integer;
begin
  if not Num3(a, s, cost, salv, life, bad) then exit(bad);
  if not ArgNumber(a[3], s, per, bad) then exit(bad);
  if (life <= 0) or (per < 1) or (per > life) or (cost < 0) or (salv < 0) then exit(ErrValue);
  bv := cost;
  dep := 0;
  for p := 1 to Trunc(per) do
  begin
    dep := bv * 2 / life;
    if bv - dep < salv then dep := bv - salv;
    if dep < 0 then dep := 0;
    bv := bv - dep;
  end;
  Result := NumValue(dep);
end;

{ ------------------------------------------------------------------ database }

{ * and ? wildcards, ignoring case }
function WildMatch(const pat, s: string; pi_, si: Integer): Boolean;
begin
  while pi_ <= Length(pat) do
  begin
    if pat[pi_] = '*' then
    begin
      Inc(pi_);
      while si <= Length(s) + 1 do
      begin
        if WildMatch(pat, s, pi_, si) then exit(True);
        Inc(si);
      end;
      exit(False);
    end;
    if si > Length(s) then exit(False);
    if (pat[pi_] <> '?') and (UpCase(pat[pi_]) <> UpCase(s[si])) then exit(False);
    Inc(pi_);
    Inc(si);
  end;
  Result := si > Length(s);
end;

{ Does the record's cell satisfy one criterion cell?  A number matches an equal
  number; a label matches text exactly (ignoring case) with ? and * wildcards,
  and a leading ~ negates it.  Comparison operators written in a label (">15")
  are NOT operators: the original program matched no record for them. }
function CriterionMet(const crit, cell: TValue): Boolean;
var
  t, hay: string;
  neg: Boolean;
begin
  if crit.IsEmpty then exit(True);
  if crit.Kind = vkNum then
    exit((cell.Kind = vkNum) and not cell.IsEmpty and (cell.Num = crit.Num));
  if crit.Kind <> vkStr then exit(False);
  t := crit.Str;
  neg := False;
  if (t <> '') and (t[1] = '~') then
  begin
    neg := True;
    Delete(t, 1, 1);
  end;
  if cell.Kind = vkStr then hay := cell.Str
  else if cell.IsEmpty then hay := ''
  else if cell.Kind = vkNum then hay := NumToRaw(cell.Num)
  else exit(neg);
  Result := WildMatch(t, hay, 1, 1);
  if neg then Result := not Result;
end;

{ Collects the values of one field over the records that match.  The input
  range's first row holds the field names; the criteria range's first row
  names fields too, each further row is an alternative, and all cells of a row
  must hold.  Only numbers count as values; text cells are counted (DCOUNT)
  but otherwise ignored.  Returns nil and sets bad when an argument is wrong. }
function DbCollect(const a: TNodeArray; s: TCellSource; out bad: TValue): TStat;
var
  ir1, ic1, ir2, ic2, cr1, cc1, cr2, cc2: Integer;
  field: Double;
  r, k, cr, f, col: Integer;
  critCols: array of Integer;
  rowOk, matched: Boolean;
  hdr, nm, x: TValue;
begin
  Result := nil;
  if not RectOf(a[0], s, ir1, ic1, ir2, ic2) then begin bad := ErrValue; exit; end;
  if not ArgNumber(a[1], s, field, bad) then exit;
  if not RectOf(a[2], s, cr1, cc1, cr2, cc2) then begin bad := ErrValue; exit; end;
  f := Trunc(field);
  if (f < 0) or (ic1 + f > ic2) then begin bad := ErrValue; exit; end;
  { which input column each criteria column refers to (-1: none) }
  SetLength(critCols, cc2 - cc1 + 1);
  for k := 0 to High(critCols) do
  begin
    critCols[k] := -1;
    hdr := s.CellValue(cr1, cc1 + k);
    if hdr.Kind <> vkStr then continue;
    for col := ic1 to ic2 do
    begin
      nm := s.CellValue(ir1, col);
      if (nm.Kind = vkStr) and (CompareText(nm.Str, hdr.Str) = 0) then
      begin
        critCols[k] := col;
        break;
      end;
    end;
  end;
  Result := TStat.Create;
  for r := ir1 + 1 to ir2 do
  begin
    matched := cr2 <= cr1;                         { no criteria rows: every record }
    for cr := cr1 + 1 to cr2 do
    begin
      rowOk := True;
      for k := 0 to High(critCols) do
      begin
        hdr := s.CellValue(cr, cc1 + k);
        if hdr.IsEmpty then continue;
        if (critCols[k] < 0) or not CriterionMet(hdr, s.CellValue(r, critCols[k])) then
        begin
          rowOk := False;
          break;
        end;
      end;
      if rowOk then
      begin
        matched := True;                            { an empty criteria row matches all }
        break;
      end;
    end;
    if not matched then continue;
    x := s.CellValue(r, ic1 + f);
    if x.Kind = vkErr then Result.Err := True
    else if x.Kind = vkNA then Result.NA := True
    else if (x.Kind = vkNum) and not x.IsEmpty then Result.AddNum(x.Num)
    else if x.Kind = vkStr then Inc(Result.Cnt);
  end;
end;

function DbRun(const a: TNodeArray; s: TCellSource; which: Integer): TValue;
var
  st: TStat;
  bad: TValue;
  i: Integer;
  t, m: Double;
  ok: Boolean;
begin
  st := DbCollect(a, s, bad);
  if st = nil then exit(bad);
  try
    if st.Err then exit(ErrValue);
    if st.NA then exit(NAValue);
    t := 0;
    for i := 0 to High(st.Vals) do t := t + st.Vals[i];
    case which of
      1: Result := NumValue(t);                             { DSUM }
      2:                                                    { DAVG }
        if Length(st.Vals) = 0 then Result := ErrValue
        else Result := NumValue(t / Length(st.Vals));
      3: Result := NumValue(st.Cnt);                        { DCOUNT }
      4, 5:                                                 { DMIN, DMAX }
        if Length(st.Vals) = 0 then Result := NumValue(0)
        else
        begin
          m := st.Vals[0];
          for i := 1 to High(st.Vals) do
            if ((which = 5) and (st.Vals[i] > m)) or ((which = 4) and (st.Vals[i] < m)) then m := st.Vals[i];
          Result := NumValue(m);
        end;
    else                                                    { DVAR, DSTD }
      begin
        m := Variance(st.Vals, ok);
        if not ok then exit(ErrValue);
        if which = 7 then m := Sqrt(m);
        Result := NumValue(m);
      end;
    end;
  finally
    st.Free;
  end;
end;

function FnDsum(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 1); end;
function FnDavg(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 2); end;
function FnDcount(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 3); end;
function FnDmin(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 4); end;
function FnDmax(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 5); end;
function FnDvar(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 6); end;
function FnDstd(const a: TNodeArray; s: TCellSource): TValue; begin Result := DbRun(a, s, 7); end;

initialization
  RegisterFunc('PMT', 3, 3, 56, False, @FnPmt);
  RegisterFunc('PV', 3, 3, 57, False, @FnPv);
  RegisterFunc('FV', 3, 3, 58, False, @FnFv);
  RegisterFunc('SUM', 1, 255, 80, True, @FnSum);
  RegisterFunc('AVG', 1, 255, 81, True, @FnAvg);
  RegisterFunc('COUNT', 1, 255, 82, True, @FnCount);
  RegisterFunc('MIN', 1, 255, 83, True, @FnMin);
  RegisterFunc('MAX', 1, 255, 84, True, @FnMax);
  RegisterFunc('NPV', 2, 2, 86, False, @FnNpv);
  RegisterFunc('VAR', 1, 255, 87, True, @FnVar);          { list functions, like @SUM }
  RegisterFunc('STD', 1, 255, 88, True, @FnStd);
  RegisterFunc('IRR', 2, 2, 89, False, @FnIrr);
  RegisterFunc('DSUM', 3, 3, 91, False, @FnDsum);
  RegisterFunc('DAVG', 3, 3, 92, False, @FnDavg);
  RegisterFunc('DCOUNT', 3, 3, 93, False, @FnDcount);
  RegisterFunc('DMIN', 3, 3, 94, False, @FnDmin);
  RegisterFunc('DMAX', 3, 3, 95, False, @FnDmax);
  RegisterFunc('DVAR', 3, 3, 96, False, @FnDvar);
  RegisterFunc('DSTD', 3, 3, 97, False, @FnDstd);
  SetFuncRangeArgs('NPV', 2);
  SetFuncRangeArgs('IRR', 2);
  SetFuncRangeArgs('DSUM', 5);
  SetFuncRangeArgs('DAVG', 5);
  SetFuncRangeArgs('DCOUNT', 5);
  SetFuncRangeArgs('DMIN', 5);
  SetFuncRangeArgs('DMAX', 5);
  SetFuncRangeArgs('DVAR', 5);
  SetFuncRangeArgs('DSTD', 5);
  { financial functions of release 2 that the old documents give no file code for }
  RegisterFunc('TERM', 3, 3, -1, False, @FnTerm);
  RegisterFunc('CTERM', 3, 3, -1, False, @FnCterm);
  RegisterFunc('RATE', 3, 3, -1, False, @FnRate);
  RegisterFunc('SLN', 3, 3, -1, False, @FnSln);
  RegisterFunc('SYD', 4, 4, -1, False, @FnSyd);
  RegisterFunc('DDB', 4, 4, -1, False, @FnDdb);
end.
