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

{ Worksheet-level commands: formats, label alignment, column widths, erase. }
unit cmdsheet;
{$mode objfpc}{$H+}

interface

uses commands;

procedure RegisterSheetCommands(C: TCommands);

implementation

uses SysUtils, Classes, session, sheet;

const
  MaxRangeCells = 300000;

procedure SplitPath(const path: string; out toks: TStringArray);
begin
  toks := path.Split([' ']);
end;

{ ---------------------------------------------------------------- formats }

{ Works out which format a menu path stands for.  needDec: it asks for
  decimal places.  The result has UseGlobal set for "Range Format Reset". }
function FormatOfPath(const path: string; out fmt: TCellFormat; out needDec: Boolean): Boolean;
var
  t: TStringArray;
  last, prev: string;
begin
  SplitPath(path, t);
  last := t[High(t)];
  if Length(t) > 1 then prev := t[High(t) - 1] else prev := '';
  needDec := False;
  Result := True;
  fmt := MakeFormat(fkGeneral, 0);
  if prev = 'Time' then
    fmt := MakeFormat(fkDate, 5 + StrToIntDef(last, 1))
  else if prev = 'Date' then
    fmt := MakeFormat(fkDate, StrToIntDef(last, 1))
  else if last = 'Fixed' then begin fmt := MakeFormat(fkFixed, 2); needDec := True; end
  else if last = 'Sci' then begin fmt := MakeFormat(fkSci, 2); needDec := True; end
  else if last = 'Currency' then begin fmt := MakeFormat(fkCurrency, 2); needDec := True; end
  else if last = ',' then begin fmt := MakeFormat(fkComma, 2); needDec := True; end
  else if last = 'Percent' then begin fmt := MakeFormat(fkPercent, 2); needDec := True; end
  else if last = 'General' then fmt := MakeFormat(fkGeneral, 0)
  else if last = '+/-' then fmt := MakeFormat(fkPlusMinus, 0)
  else if last = 'Text' then fmt := MakeFormat(fkText, 0)
  else if last = 'Hidden' then fmt := MakeFormat(fkHidden, 0)
  else if last = 'Reset' then fmt.UseGlobal := True
  else
    Result := False;
end;

function CheckSize(S: TSession): Boolean;
begin
  Result := (S.Range.R2 - S.Range.R1 + 1) * (S.Range.C2 - S.Range.C1 + 1) <= MaxRangeCells;
  if not Result then S.Msg := 'Range too large for this version';
end;

procedure FormatRangeDone(S: TSession; const path: string);
var
  r, c: Integer;
begin
  if not CheckSize(S) then exit;
  S.SaveUndo;
  for r := S.Range.R1 to S.Range.R2 do
    for c := S.Range.C1 to S.Range.C2 do
      S.Sheet.SetCellFormat(r, c, S.PendFmt, not S.PendFmt.UseGlobal);
end;

procedure FormatApply(S: TSession; const path: string; const fmt: TCellFormat);
begin
  if path.StartsWith('Worksheet') then
  begin
    S.SaveUndo;
    S.Sheet.GlobalFmt := fmt;
  end
  else
  begin
    S.PendFmt := fmt;
    S.AskRange('Enter range to format:', @FormatRangeDone, path);
  end;
end;

procedure FormatDecDone(S: TSession; const path: string);
var
  fmt: TCellFormat;
  nd: Boolean;
begin
  FormatOfPath(path, fmt, nd);
  fmt.Dec := S.PromptNum;
  FormatApply(S, path, fmt);
end;

procedure CmdFormat(S: TSession; const path: string);
var
  fmt: TCellFormat;
  nd: Boolean;
begin
  if not FormatOfPath(path, fmt, nd) then exit;
  if nd then
    S.AskNumber('Enter number of decimal places (0..15):', 2, 0, 15, @FormatDecDone, path)
  else
    FormatApply(S, path, fmt);
end;

{ ---------------------------------------------------------------- labels }

function PrefixOfPath(const path: string): Char;
begin
  if path.EndsWith('Left') then Result := ''''
  else if path.EndsWith('Right') then Result := '"'
  else Result := '^';
end;

procedure LabelRangeDone(S: TSession; const path: string);
begin
  if not CheckSize(S) then exit;
  S.SaveUndo;
  S.Sheet.SetLabelAlignment(PrefixOfPath(path), False, S.Range.R1, S.Range.C1, S.Range.R2, S.Range.C2);
end;

procedure CmdRangeLabel(S: TSession; const path: string);
begin
  S.AskRange('Enter label range:', @LabelRangeDone, path);
end;

procedure CmdGlobalLabel(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.GlobalLabelPrefix := PrefixOfPath(path);
  S.Sheet.SetLabelAlignment(PrefixOfPath(path), True, 0, 0, 0, 0);
end;

{ ---------------------------------------------------------------- widths }

procedure SetWidthDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.SetColWidth(S.CurCol, S.PromptNum);
end;

procedure SetGlobalWidthDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.GlobalWidth := S.PromptNum;
end;

procedure CmdSetWidth(S: TSession; const path: string);
begin
  S.AskNumber('Enter column width (1..240):', S.Sheet.ColWidth(S.CurCol), 1, 240,
              @SetWidthDone, path, plColumn);
end;

procedure CmdGlobalWidth(S: TSession; const path: string);
begin
  S.AskNumber('Enter global column width (1..240):', S.Sheet.GlobalWidth, 1, 240,
              @SetGlobalWidthDone, path, plGlobalWidth);
end;

procedure CmdResetWidth(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.SetColWidth(S.CurCol, 0);
end;

{ ---------------------------------------------------------------- zero, erase }

procedure CmdZero(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.ZeroDisplay := path.EndsWith('No');
end;

procedure EraseRangeDone(S: TSession; const path: string);
var
  r, c: Integer;
begin
  S.SaveUndo;
  for r := S.Range.R1 to S.Range.R2 do
    for c := S.Range.C1 to S.Range.C2 do
      S.Sheet.Remove(r, c);
end;

procedure CmdRangeErase(S: TSession; const path: string);
begin
  S.AskRange('Enter range to erase:', @EraseRangeDone, path);
end;

procedure CmdNothing(S: TSession; const path: string);
begin
end;

procedure CmdEraseSheet(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.Clear;
  S.CurCol := 1; S.CurRow := 1; S.LeftCol := 1; S.TopRow := 1;
end;

procedure RegisterSheetCommands(C: TCommands);
const
  Kinds: array[0..8] of string =
    ('Fixed', 'Sci', 'Currency', ',', 'General', '+/-', 'Percent', 'Text', 'Hidden');
  Prefixes: array[0..1] of string = ('Worksheet Global Format ', 'Range Format ');
  Aligns: array[0..2] of string = ('Left', 'Right', 'Center');
var
  p, k, n: Integer;
begin
  for p := 0 to 1 do
  begin
    for k := Low(Kinds) to High(Kinds) do
      C.Register(Prefixes[p] + Kinds[k], @CmdFormat);
    for n := 1 to 5 do
      C.Register(Prefixes[p] + 'Date ' + IntToStr(n), @CmdFormat);
    for n := 1 to 4 do
      C.Register(Prefixes[p] + 'Date Time ' + IntToStr(n), @CmdFormat);
  end;
  C.Register('Range Format Reset', @CmdFormat);
  for k := 0 to 2 do
  begin
    C.Register('Range Label ' + Aligns[k], @CmdRangeLabel);
    C.Register('Worksheet Global Label-Prefix ' + Aligns[k], @CmdGlobalLabel);
  end;
  C.Register('Worksheet Global Column-Width', @CmdGlobalWidth);
  C.Register('Worksheet Column Set-Width', @CmdSetWidth);
  C.Register('Worksheet Column Reset-Width', @CmdResetWidth);
  C.Register('Worksheet Global Zero No', @CmdZero);
  C.Register('Worksheet Global Zero Yes', @CmdZero);
  C.Register('Range Erase', @CmdRangeErase);
  C.Register('Worksheet Erase No', @CmdNothing);
  C.Register('Worksheet Erase Yes', @CmdEraseSheet);
end;

end.
