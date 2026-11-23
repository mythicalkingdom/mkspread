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

{ /Data commands: Fill, Table, Sort, Query, Distribution, Matrix, Regression,
  Parse.  The arithmetic is in dataops; this unit holds the prompts and the
  remembered settings. }
unit cmddata;
{$mode objfpc}{$H+}

interface

uses commands, session;

procedure RegisterDataCommands(C: TCommands);

{ re-runs the last data table (the TABLE key, F8) }
procedure RunLastTable(S: TSession);

implementation

uses SysUtils, Classes, sheet, formula, cellfmt, dataops, editops;

procedure Report(S: TSession; const msg: string);
begin
  if msg <> '' then S.Msg := msg;
end;

function Need(S: TSession; ok: Boolean; const what: string): Boolean;
begin
  Result := ok;
  if not ok then S.Msg := what;
end;

{ ---------------------------------------------------------------- Fill }

procedure FillStop(S: TSession; const path: string);
var
  v: TValue;
  n: Integer;
begin
  if not (S.Calc.EvalText(S.PromptStr, v) and (v.Kind = vkNum)) then
  begin
    S.Msg := 'The stop value must be a number';
    exit;
  end;
  S.Data.FillStart := S.PendNum[0];
  S.Data.FillStep := S.PendNum[1];
  S.Data.FillStop := v.Num;
  S.SaveUndo;
  n := FillRange(S.Sheet, S.PendRange, S.PendNum[0], S.PendNum[1], v.Num);
  if n = 0 then S.Msg := 'Nothing was filled';
end;

procedure FillStep(S: TSession; const path: string);
var
  v: TValue;
begin
  if not (S.Calc.EvalText(S.PromptStr, v) and (v.Kind = vkNum)) then
  begin
    S.Msg := 'The step value must be a number';
    exit;
  end;
  S.PendNum[1] := v.Num;
  S.AskText('Stop:', NumToRaw(S.Data.FillStop), @FillStop, path);
end;

procedure FillStart(S: TSession; const path: string);
var
  v: TValue;
begin
  if not (S.Calc.EvalText(S.PromptStr, v) and (v.Kind = vkNum)) then
  begin
    S.Msg := 'The start value must be a number';
    exit;
  end;
  S.PendNum[0] := v.Num;
  S.AskText('Step:', NumToRaw(S.Data.FillStep), @FillStep, path);
end;

procedure FillRangeDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  S.AskText('Start:', NumToRaw(S.Data.FillStart), @FillStart, path);
end;

procedure CmdFill(S: TSession; const path: string);
begin
  S.AskRange('Enter fill range:', @FillRangeDone, path);
end;

{ ---------------------------------------------------------------- Table }

procedure RunLastTable(S: TSession);
var
  t: TRange;
  r, c, i, j: Integer;
  cell1, cell2: TCell;
  orig1, orig2: string;
  had1, had2: Boolean;
  fmt1, fmt2: TCellFormat;
  results: array of array of TValue;
  v: TValue;

  function Setv(r0, c0: Integer; const val: TValue): Boolean;
  begin
    Result := True;
    case val.Kind of
      vkNum: S.Sheet.Put(r0, c0, NumToRaw(val.Num));
      vkStr: S.Sheet.Put(r0, c0, S.Sheet.GlobalLabelPrefix + val.Str);
    else
      Result := False;
    end;
  end;

begin
  if S.Data.TableKind = 0 then
  begin
    S.Msg := 'No data table has been defined';
    exit;
  end;
  t := S.Data.TableRange;
  if (t.R2 - t.R1 < 1) or (t.C2 - t.C1 < 1) then
  begin
    S.Msg := 'The table range needs at least two rows and two columns';
    exit;
  end;
  S.SaveUndo;
  { remember the input cells }
  cell1 := S.Sheet.Find(S.Data.TableIn1.R1, S.Data.TableIn1.C1);
  had1 := cell1 <> nil;
  if had1 then begin orig1 := cell1.Raw; fmt1 := cell1.Fmt; end;
  cell2 := nil;
  had2 := False;
  if S.Data.TableKind = 2 then
  begin
    cell2 := S.Sheet.Find(S.Data.TableIn2.R1, S.Data.TableIn2.C1);
    had2 := cell2 <> nil;
    if had2 then begin orig2 := cell2.Raw; fmt2 := cell2.Fmt; end;
  end;
  SetLength(results, t.R2 - t.R1, t.C2 - t.C1);
  if S.Data.TableKind = 1 then
  begin
    { values down the first column, formulas along the first row }
    for r := t.R1 + 1 to t.R2 do
    begin
      if not Setv(S.Data.TableIn1.R1, S.Data.TableIn1.C1, CellValueOf(S.Sheet.Find(r, t.C1))) then continue;
      S.Calc.Recalc;
      for c := t.C1 + 1 to t.C2 do
        results[r - t.R1 - 1][c - t.C1 - 1] := CellValueOf(S.Sheet.Find(t.R1, c));
    end;
  end
  else
  begin
    { the formula is in the corner; the left column's values go in input cell 1, the top row's in input cell 2 }
    for r := t.R1 + 1 to t.R2 do
      for c := t.C1 + 1 to t.C2 do
      begin
        if not Setv(S.Data.TableIn1.R1, S.Data.TableIn1.C1, CellValueOf(S.Sheet.Find(r, t.C1))) then continue;
        if not Setv(S.Data.TableIn2.R1, S.Data.TableIn2.C1, CellValueOf(S.Sheet.Find(t.R1, c))) then continue;
        S.Calc.Recalc;
        results[r - t.R1 - 1][c - t.C1 - 1] := CellValueOf(S.Sheet.Find(t.R1, t.C1));
      end;
  end;
  { put the input cells back }
  if had1 then S.Sheet.Put(S.Data.TableIn1.R1, S.Data.TableIn1.C1, orig1).Fmt := fmt1
  else S.Sheet.Remove(S.Data.TableIn1.R1, S.Data.TableIn1.C1);
  if S.Data.TableKind = 2 then
  begin
    if had2 then S.Sheet.Put(S.Data.TableIn2.R1, S.Data.TableIn2.C1, orig2).Fmt := fmt2
    else S.Sheet.Remove(S.Data.TableIn2.R1, S.Data.TableIn2.C1);
  end;
  { the answers go in as plain values }
  for i := 0 to High(results) do
    for j := 0 to High(results[i]) do
    begin
      v := results[i][j];
      case v.Kind of
        vkNum: S.Sheet.Put(t.R1 + 1 + i, t.C1 + 1 + j, NumToRaw(v.Num));
        vkStr: S.Sheet.Put(t.R1 + 1 + i, t.C1 + 1 + j, S.Sheet.GlobalLabelPrefix + v.Str);
        vkNA: S.Sheet.Put(t.R1 + 1 + i, t.C1 + 1 + j, '@NA');
      else
        S.Sheet.Put(t.R1 + 1 + i, t.C1 + 1 + j, '@ERR');
      end;
    end;
end;

procedure TableInput2(S: TSession; const path: string);
begin
  S.Data.TableIn2 := S.Range;
  RunLastTable(S);
end;

procedure TableInput1(S: TSession; const path: string);
begin
  S.Data.TableIn1 := S.Range;
  if S.Data.TableKind = 2 then
    S.AskRange('Enter column input cell:', @TableInput2, path)
  else
    RunLastTable(S);
end;

procedure TableRangeDone(S: TSession; const path: string);
begin
  S.Data.TableRange := S.Range;
  if S.Data.TableKind = 2 then
    S.AskRange('Enter row input cell:', @TableInput1, path)
  else
    S.AskRange('Enter input cell:', @TableInput1, path);
end;

procedure CmdTable(S: TSession; const path: string);
begin
  if path.EndsWith('Reset') then
  begin
    S.Data.TableKind := 0;
    exit;
  end;
  if path.EndsWith(' 2') then S.Data.TableKind := 2 else S.Data.TableKind := 1;
  S.AskRange('Enter table range:', @TableRangeDone, path);
end;

{ ---------------------------------------------------------------- Sort }

procedure SortOrderDone(S: TSession; const path: string);
var
  asc: Boolean;
begin
  asc := not ((S.PromptStr <> '') and (UpCase(S.PromptStr[1]) = 'D'));
  if path.EndsWith('Secondary-Key') then
  begin
    S.Data.Key2 := S.PendRange.C1;
    S.Data.Asc2 := asc;
  end
  else
  begin
    S.Data.Key1 := S.PendRange.C1;
    S.Data.Asc1 := asc;
  end;
end;

procedure SortKeyDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  S.AskText('Sort order (A or D):', 'A', @SortOrderDone, path);
end;

procedure SortRangeDone(S: TSession; const path: string);
begin
  S.Data.SortRange := S.Range;
  S.Data.SortSet := True;
end;

procedure CmdSort(S: TSession; const path: string);
begin
  if path.EndsWith('Data-Range') then
    S.AskRange('Enter data range to sort:', @SortRangeDone, path)
  else if path.EndsWith('Primary-Key') then
    S.AskRange('Enter primary sort key (any cell in its column):', @SortKeyDone, path)
  else if path.EndsWith('Secondary-Key') then
    S.AskRange('Enter secondary sort key (any cell in its column):', @SortKeyDone, path)
  else if path.EndsWith('Reset') then
  begin
    S.Data.SortSet := False;
    S.Data.Key1 := 0;
    S.Data.Key2 := 0;
  end
  else if path.EndsWith('Go') then
  begin
    if not Need(S, S.Data.SortSet, 'Set the data range first') then exit;
    if not Need(S, S.Data.Key1 > 0, 'Set the primary key first') then exit;
    S.SaveUndo;
    Report(S, SortRows(S.Sheet, S.Data.SortRange, S.Data.Key1, S.Data.Asc1, S.Data.Key2, S.Data.Asc2));
  end;
end;

{ ---------------------------------------------------------------- Query }

procedure QueryDeleteConfirmed(S: TSession; const path: string);
var
  n: Integer;
  msg: string;
begin
  if S.ChoiceIndex <> 1 then exit;
  S.SaveUndo;
  msg := QueryDelete(S.Sheet, S.Data.QIn, S.Data.QCrit, n);
  if msg <> '' then S.Msg := msg else S.Msg := Format('%d record(s) deleted', [n]);
end;

procedure QueryRangeDone(S: TSession; const path: string);
begin
  if path.EndsWith('Input') then begin S.Data.QIn := S.Range; S.Data.QInSet := True; end
  else if path.EndsWith('Criteria') then begin S.Data.QCrit := S.Range; S.Data.QCritSet := True; end
  else begin S.Data.QOut := S.Range; S.Data.QOutSet := True; end;
end;

procedure CmdQuery(S: TSession; const path: string);
var
  msg: string;
begin
  if path.EndsWith('Input') then
    S.AskRange('Enter input range (with field names):', @QueryRangeDone, path)
  else if path.EndsWith('Criteria') then
    S.AskRange('Enter criteria range:', @QueryRangeDone, path)
  else if path.EndsWith('Output') then
    S.AskRange('Enter output range (with field names):', @QueryRangeDone, path)
  else if path.EndsWith('Reset') then
  begin
    S.Data.QInSet := False;
    S.Data.QCritSet := False;
    S.Data.QOutSet := False;
  end
  else if path.EndsWith('Find') then
  begin
    if not Need(S, S.Data.QInSet and S.Data.QCritSet, 'Set the input and criteria ranges first') then exit;
    msg := QueryMatches(S.Sheet, S.Data.QIn, S.Data.QCrit, S.FindRows);
    if msg <> '' then begin S.Msg := msg; exit; end;
    if S.FindRows.Count = 0 then begin S.Msg := 'No record matches the criteria'; exit; end;
    S.OrigRow := S.CurRow; S.OrigCol := S.CurCol; S.OrigTop := S.TopRow; S.OrigLeft := S.LeftCol;
    S.FindIdx := 0;
    S.CurRow := PtrInt(S.FindRows[0]);
    S.CurCol := S.Data.QIn.C1;
    S.Mode := mFind;
    S.Normalize;
  end
  else if path.EndsWith('Extract') or path.EndsWith('Unique') then
  begin
    if not Need(S, S.Data.QInSet and S.Data.QCritSet and S.Data.QOutSet,
                'Set the input, criteria and output ranges first') then exit;
    S.SaveUndo;
    Report(S, QueryExtract(S.Sheet, S.Data.QIn, S.Data.QCrit, S.Data.QOut, path.EndsWith('Unique')));
  end
  else if path.EndsWith('Delete') then
  begin
    if not Need(S, S.Data.QInSet and S.Data.QCritSet, 'Set the input and criteria ranges first') then exit;
    S.AskChoice(['Cancel', 'Delete'], @QueryDeleteConfirmed, path);
  end;
end;

{ ---------------------------------------------------------------- Distribution, Matrix }

procedure DistBinsDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  Report(S, Distribution(S.Sheet, S.PendRange, S.Range));
end;

procedure DistValuesDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  S.AskRange('Enter bin range:', @DistBinsDone, path);
end;

procedure CmdDistribution(S: TSession; const path: string);
begin
  S.AskRange('Enter values range:', @DistValuesDone, path);
end;

var
  MatrixFirst: TRange;

procedure InvertOutDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  Report(S, MatrixInvert(S.Sheet, S.PendRange, S.Range.R1, S.Range.C1));
end;

procedure InvertDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  S.AskRange('Enter output range:', @InvertOutDone, path);
end;

procedure MultOutDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  Report(S, MatrixMultiply(S.Sheet, MatrixFirst, S.PendRange, S.Range.R1, S.Range.C1));
end;

procedure MultSecondDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  S.AskRange('Enter output range:', @MultOutDone, path);
end;

procedure MultFirstDone(S: TSession; const path: string);
begin
  MatrixFirst := S.Range;
  S.AskRange('Enter second range to multiply:', @MultSecondDone, path);
end;

procedure CmdMatrix(S: TSession; const path: string);
begin
  if path.EndsWith('Invert') then
    S.AskRange('Enter range to invert:', @InvertDone, path)
  else
    S.AskRange('Enter first range to multiply:', @MultFirstDone, path);
end;

{ ---------------------------------------------------------------- Regression }

procedure RegRangeDone(S: TSession; const path: string);
begin
  if path.EndsWith('X-Range') then begin S.Data.RegX := S.Range; S.Data.RegXSet := True; end
  else if path.EndsWith('Y-Range') then begin S.Data.RegY := S.Range; S.Data.RegYSet := True; end
  else begin S.Data.RegOut := S.Range; S.Data.RegOutSet := True; end;
end;

procedure CmdRegression(S: TSession; const path: string);
begin
  if path.EndsWith('X-Range') then S.AskRange('Enter independent variable (X) range:', @RegRangeDone, path)
  else if path.EndsWith('Y-Range') then S.AskRange('Enter dependent variable (Y) range:', @RegRangeDone, path)
  else if path.EndsWith('Output-Range') then S.AskRange('Enter output range:', @RegRangeDone, path)
  else if path.EndsWith('Compute') then S.Data.RegZero := False
  else if path.EndsWith('Zero') then S.Data.RegZero := True
  else if path.EndsWith('Reset') then
  begin
    S.Data.RegXSet := False;
    S.Data.RegYSet := False;
    S.Data.RegOutSet := False;
    S.Data.RegZero := False;
  end
  else if path.EndsWith('Go') then
  begin
    if not Need(S, S.Data.RegXSet and S.Data.RegYSet and S.Data.RegOutSet,
                'Set the X, Y and output ranges first') then exit;
    S.SaveUndo;
    Report(S, Regression(S.Sheet, S.Data.RegX, S.Data.RegY, S.Data.RegOut.R1, S.Data.RegOut.C1, S.Data.RegZero));
  end;
end;

{ ---------------------------------------------------------------- Parse }

procedure ParseRangeDone(S: TSession; const path: string);
begin
  if path.EndsWith('Input-Column') then begin S.Data.ParseIn := S.Range; S.Data.ParseInSet := True; end
  else begin S.Data.ParseOut := S.Range; S.Data.ParseOutSet := True; end;
end;

procedure CmdParse(S: TSession; const path: string);
var
  cell, below: TCell;
  p: Char;
  t: string;
begin
  if path.EndsWith('Input-Column') then
    S.AskRange('Enter input column (the labels and format lines):', @ParseRangeDone, path)
  else if path.EndsWith('Output-Range') then
    S.AskRange('Enter output range:', @ParseRangeDone, path)
  else if path.EndsWith('Reset') then
  begin
    S.Data.ParseInSet := False;
    S.Data.ParseOutSet := False;
  end
  else if path.EndsWith('Format-Line Create') then
  begin
    below := S.Sheet.Find(S.CurRow + 1, S.CurCol);
    if (below = nil) or not TextOf(below, p, t) then
    begin
      S.Msg := 'The cell below the pointer must hold a label';
      exit;
    end;
    S.SaveUndo;
    S.Sheet.Put(S.CurRow, S.CurCol, '|' + MakeFormatLine(t));
  end
  else if path.EndsWith('Format-Line Edit') then
  begin
    cell := S.Sheet.Find(S.CurRow, S.CurCol);
    if (cell = nil) or not TextOf(cell, p, t) or (p <> '|') then
    begin
      S.Msg := 'The pointer must be on a format line';
      exit;
    end;
    S.Entry := cell.Raw;
    S.EditPos := Length(S.Entry);
    S.Mode := mEdit;
  end
  else if path.EndsWith('Go') then
  begin
    if not Need(S, S.Data.ParseInSet and S.Data.ParseOutSet, 'Set the input column and output range first') then exit;
    S.SaveUndo;
    Report(S, ParseLabels(S.Sheet, S.Data.ParseIn, S.Data.ParseOut.R1, S.Data.ParseOut.C1));
  end;
end;

procedure CmdQuit(S: TSession; const path: string);
begin
end;

procedure RegisterDataCommands(C: TCommands);
const
  Quits: array[0..3] of string = ('Sort', 'Query', 'Regression', 'Parse');
  SortItems: array[0..4] of string = ('Data-Range', 'Primary-Key', 'Secondary-Key', 'Reset', 'Go');
  QueryItems: array[0..7] of string = ('Input', 'Criteria', 'Output', 'Find', 'Extract', 'Unique', 'Delete', 'Reset');
  RegItems: array[0..4] of string = ('X-Range', 'Y-Range', 'Output-Range', 'Reset', 'Go');
  ParseItems: array[0..3] of string = ('Input-Column', 'Output-Range', 'Reset', 'Go');
var
  k: Integer;
begin
  C.Register('Data Fill', @CmdFill);
  C.Register('Data Table 1', @CmdTable);
  C.Register('Data Table 2', @CmdTable);
  C.Register('Data Table Reset', @CmdTable);
  for k := 0 to High(SortItems) do C.Register('Data Sort ' + SortItems[k], @CmdSort);
  for k := 0 to High(QueryItems) do C.Register('Data Query ' + QueryItems[k], @CmdQuery);
  C.Register('Data Distribution', @CmdDistribution);
  C.Register('Data Matrix Invert', @CmdMatrix);
  C.Register('Data Matrix Multiply', @CmdMatrix);
  for k := 0 to High(RegItems) do C.Register('Data Regression ' + RegItems[k], @CmdRegression);
  C.Register('Data Regression Intercept Compute', @CmdRegression);
  C.Register('Data Regression Intercept Zero', @CmdRegression);
  for k := 0 to High(ParseItems) do C.Register('Data Parse ' + ParseItems[k], @CmdParse);
  C.Register('Data Parse Format-Line Create', @CmdParse);
  C.Register('Data Parse Format-Line Edit', @CmdParse);
  for k := 0 to High(Quits) do C.Register('Data ' + Quits[k] + ' Quit', @CmdQuit);
end;

end.
