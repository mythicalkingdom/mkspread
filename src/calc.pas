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

{ Recalculation of a worksheet's formulas.

  Natural order evaluates each formula after the cells it refers to (found on
  demand, so no separate dependency graph is kept; a cell revisited while it is
  still being evaluated is a circular reference).  Columnwise and rowwise
  order simply sweep the formula cells in that order, using whatever values
  the cells have at that moment, as many times as the iteration count says.
  Every recalculation covers all formulas; incremental recalculation can be
  added later behind the same interface. }
unit calc;
{$mode objfpc}{$H+}

interface

uses Classes, sheet, formula;

type
  TCalc = class
  private
    FSheet: TSheet;
    FSource: TCellSource;
    FPass: Integer;
    FCircular: Boolean;
    FNaturalPass: Boolean;
    procedure Evaluate(cell: TCell);
  public
    NeedsCalc: Boolean;               { manual mode and something changed }
    constructor Create(ASheet: TSheet);
    destructor Destroy; override;
    procedure Recalc;                 { everything, now }
    { the value of a formula in the context of this worksheet (for macros) }
    function EvalFormula(f: TFormula): TValue;
    { Called after a command: recalculates (automatic) or flags (manual). }
    procedure SheetChanged;
    property Circular: Boolean read FCircular;
  end;

implementation

uses SysUtils, funclib, cellfmt;

type
  TCalcSource = class(TCellSource)
  private
    FCalc: TCalc;
    FSheet: TSheet;
  public
    constructor Create(ACalc: TCalc; ASheet: TSheet);
    function CellValue(r, c: Integer): TValue; override;
    function LookupName(const name: string; out r1, c1, r2, c2: Integer): Boolean; override;
    function CellInfo(const attr: string; r, c: Integer): TValue; override;
    procedure PointerCell(out r, c: Integer); override;
    procedure Accumulate(r1, c1, r2, c2: Integer; acc: TAccumulator); override;
  end;

  TCollect = record
    List: TList;
  end;
  PCollect = ^TCollect;

constructor TCalcSource.Create(ACalc: TCalc; ASheet: TSheet);
begin
  inherited Create;
  FCalc := ACalc;
  FSheet := ASheet;
end;

function ValueOfCell(cell: TCell; calc: TCalc): TValue; forward;

function TCalcSource.CellInfo(const attr: string; r, c: Integer): TValue;
var
  cell: TCell;
  p: Char;
  t, a: string;
  d: Double;
begin
  cell := FSheet.Find(r, c);
  if attr = 'address' then
    exit(StrValue('$' + ColLetter(c) + '$' + IntToStr(r)));
  if attr = 'col' then exit(NumValue(c));
  if attr = 'row' then exit(NumValue(r));
  if attr = 'width' then exit(NumValue(FSheet.ColWidth(c)));
  if attr = 'protect' then exit(NumValue(1));          { cells are protected by default }
  if attr = 'filename' then exit(StrValue(FSheet.FileName));
  if attr = 'type' then
  begin
    if (cell = nil) or (cell.Raw = '') then exit(StrValue('b'));
    if TextOf(cell, p, t) then exit(StrValue('l'));
    exit(StrValue('v'));
  end;
  if attr = 'prefix' then
  begin
    if (cell <> nil) and TextOf(cell, p, t) and (cell.Formula = nil) then exit(StrValue(p));
    exit(StrValue(''));
  end;
  if attr = 'contents' then
  begin
    if (cell = nil) or (cell.Raw = '') then exit(EmptyValue);
    exit(ValueOfCell(cell, FCalc));
  end;
  if attr = 'format' then
  begin
    if cell = nil then a := FormatTag(FSheet.GlobalFmt)
    else a := FormatTag(EffectiveFormat(cell, FSheet));
    exit(StrValue(a));
  end;
  Result := ErrValue;
end;

procedure TCalcSource.PointerCell(out r, c: Integer);
begin
  r := FSheet.PointerRow;
  c := FSheet.PointerCol;
end;

function TCalcSource.LookupName(const name: string; out r1, c1, r2, c2: Integer): Boolean;
var
  r: TRange;
begin
  Result := FSheet.FindName(name, r);
  if Result then
  begin
    r1 := r.R1; c1 := r.C1; r2 := r.R2; c2 := r.C2;
  end;
end;

function TCalcSource.CellValue(r, c: Integer): TValue;
var
  cell: TCell;
begin
  cell := FSheet.Find(r, c);
  if (cell = nil) or (cell.Raw = '') then exit(EmptyValue);
  Result := ValueOfCell(cell, FCalc);
end;

type
  TRangeCtx = record
    R1, C1, R2, C2: Integer;
    Acc: TAccumulator;
    Src: TCalcSource;
  end;
  PRangeCtx = ^TRangeCtx;

procedure VisitInRange(cell: TCell; data: Pointer);
var
  ctx: PRangeCtx;
begin
  ctx := PRangeCtx(data);
  if (cell.Row < ctx^.R1) or (cell.Row > ctx^.R2) or (cell.Col < ctx^.C1) or (cell.Col > ctx^.C2) then exit;
  if cell.Raw = '' then exit;
  ctx^.Acc.Add(ValueOfCell(cell, ctx^.Src.FCalc));
end;

procedure TCalcSource.Accumulate(r1, c1, r2, c2: Integer; acc: TAccumulator);
var
  r, c: Integer;
  cell: TCell;
  ctx: TRangeCtx;
  area: Int64;
begin
  area := Int64(r2 - r1 + 1) * (c2 - c1 + 1);
  if area <= 4 * Int64(FSheet.Count) + 64 then
  begin
    for c := c1 to c2 do
      for r := r1 to r2 do
      begin
        cell := FSheet.Find(r, c);
        if (cell <> nil) and (cell.Raw <> '') then acc.Add(ValueOfCell(cell, FCalc));
      end;
  end
  else
  begin
    { a huge, mostly empty rectangle: walk the stored cells instead }
    ctx.R1 := r1; ctx.C1 := c1; ctx.R2 := r2; ctx.C2 := c2;
    ctx.Acc := acc;
    ctx.Src := Self;
    FSheet.EachCell(@VisitInRange, @ctx);
  end;
end;

function ValueOfCell(cell: TCell; calc: TCalc): TValue;
var
  d: Double;
begin
  if cell.Formula <> nil then
  begin
    calc.Evaluate(cell);
    exit(cell.Val);
  end;
  if (cell.Raw <> '') and (cell.Raw[1] in LabelPrefixes) then
  begin
    Result := StrValue(Copy(cell.Raw, 2, MaxInt));
    Result.IsLabel := True;
    exit;
  end;
  if IsNumberLiteral(cell.Raw, d) then
    Result := NumValue(d)
  else
    Result := ErrValue;                { text that is not a valid formula }
end;

{ ------------------------------------------------------------------ TCalc }

constructor TCalc.Create(ASheet: TSheet);
begin
  inherited Create;
  FSheet := ASheet;
  FSource := TCalcSource.Create(Self, ASheet);
end;

destructor TCalc.Destroy;
begin
  FSource.Free;
  inherited Destroy;
end;

function TCalc.EvalFormula(f: TFormula): TValue;
begin
  FNaturalPass := True;
  Inc(FPass);
  Result := f.Eval(FSource);
end;

procedure TCalc.Evaluate(cell: TCell);
begin
  if not FNaturalPass then exit;        { ordered sweeps use current values }
  if cell.Pass = FPass then exit;
  if cell.Visiting then
  begin
    FCircular := True;                  { keep the value it had before }
    exit;
  end;
  cell.Visiting := True;
  cell.Val := cell.Formula.Eval(FSource);
  cell.Visiting := False;
  cell.Pass := FPass;
end;

procedure Collect(cell: TCell; data: Pointer);
begin
  if cell.Formula <> nil then PCollect(data)^.List.Add(cell);
end;

function ByColumn(a, b: Pointer): Integer;
begin
  Result := TCell(a).Col - TCell(b).Col;
  if Result = 0 then Result := TCell(a).Row - TCell(b).Row;
end;

function ByRow(a, b: Pointer): Integer;
begin
  Result := TCell(a).Row - TCell(b).Row;
  if Result = 0 then Result := TCell(a).Col - TCell(b).Col;
end;

procedure TCalc.Recalc;
var
  cells: TList;
  col: TCollect;
  it, i: Integer;
  cell: TCell;
begin
  FCircular := False;
  NeedsCalc := False;
  cells := TList.Create;
  try
    col.List := cells;
    FSheet.EachCell(@Collect, @col);
    case FSheet.RecalcOrder of
      roColumnwise: cells.Sort(@ByColumn);
      roRowwise: cells.Sort(@ByRow);
    end;
    FNaturalPass := FSheet.RecalcOrder = roNatural;
    for it := 1 to FSheet.Iterations do
    begin
      Inc(FPass);
      for i := 0 to cells.Count - 1 do
      begin
        cell := TCell(cells[i]);
        if FNaturalPass then
          Evaluate(cell)
        else
          cell.Val := cell.Formula.Eval(FSource);
      end;
    end;
  finally
    cells.Free;
  end;
end;

procedure TCalc.SheetChanged;
begin
  if not FSheet.Changed then exit;
  FSheet.Changed := False;
  if FSheet.RecalcManual then NeedsCalc := True else Recalc;
end;

end.
