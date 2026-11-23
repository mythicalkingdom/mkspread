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

{ Editing commands: /Copy, /Move, /Range Value|Trans|Name, /Worksheet
  Insert|Delete|Titles.  The heavy lifting is in editops. }
unit cmdedit;
{$mode objfpc}{$H+}

interface

uses commands;

procedure RegisterEditCommands(C: TCommands);

implementation

uses SysUtils, Classes, session, sheet, editops, formula, cellfmt;

{ ---------------------------------------------------------------- copy family }

procedure ToDone(S: TSession; const path: string);
var
  msg: string;
begin
  S.SaveUndo;
  if path = 'Copy' then
    msg := CopyRange(S.Sheet, S.PendRange, S.Range)
  else if path = 'Move' then
    msg := MoveRange(S.Sheet, S.PendRange, S.Range.R1, S.Range.C1)
  else if path = 'Range Value' then
    msg := ValuesRange(S.Sheet, S.PendRange, S.Range.R1, S.Range.C1)
  else
    msg := TransposeRange(S.Sheet, S.PendRange, S.Range.R1, S.Range.C1);
  if msg <> '' then S.Msg := msg;
end;

procedure FromDone(S: TSession; const path: string);
begin
  S.PendRange := S.Range;
  if path = 'Move' then
    S.AskRange('Enter range to move TO:', @ToDone, path)
  else
    S.AskRange('Enter range to copy TO:', @ToDone, path);
end;

procedure CmdTwoRanges(S: TSession; const path: string);
begin
  if path = 'Move' then
    S.AskRange('Enter range to move FROM:', @FromDone, path)
  else
    S.AskRange('Enter range to copy FROM:', @FromDone, path);
end;

{ ---------------------------------------------------------------- insert, delete }

procedure InsDelDone(S: TSession; const path: string);
var
  msg: string;
begin
  S.SaveUndo;
  if path = 'Worksheet Insert Column' then
    msg := InsertCols(S.Sheet, S.Range.C1, S.Range.C2 - S.Range.C1 + 1)
  else if path = 'Worksheet Insert Row' then
    msg := InsertRows(S.Sheet, S.Range.R1, S.Range.R2 - S.Range.R1 + 1)
  else if path = 'Worksheet Delete Column' then
    msg := DeleteCols(S.Sheet, S.Range.C1, S.Range.C2)
  else
    msg := DeleteRows(S.Sheet, S.Range.R1, S.Range.R2);
  if msg <> '' then S.Msg := msg;
end;

procedure CmdInsDel(S: TSession; const path: string);
begin
  if path = 'Worksheet Insert Column' then
    S.AskRange('Enter column insert range:', @InsDelDone, path)
  else if path = 'Worksheet Insert Row' then
    S.AskRange('Enter row insert range:', @InsDelDone, path)
  else if path = 'Worksheet Delete Column' then
    S.AskRange('Enter range of columns to delete:', @InsDelDone, path)
  else
    S.AskRange('Enter range of rows to delete:', @InsDelDone, path);
end;

{ ---------------------------------------------------------------- range names }

procedure NameRangeDone(S: TSession; const path: string);
begin
  S.SaveUndo;
  S.Sheet.SetName(S.PendStr, S.Range);
end;

procedure NameCreateText(S: TSession; const path: string);
begin
  if not IsValidName(S.PromptStr) then
  begin
    S.Msg := 'Invalid range name';
    exit;
  end;
  S.PendStr := UpperCase(S.PromptStr);
  S.AskRange('Enter range:', @NameRangeDone, path);
end;

procedure NameDeleteText(S: TSession; const path: string);
var
  r: TRange;
begin
  if not S.Sheet.FindName(S.PromptStr, r) then
  begin
    S.Msg := 'Range name not found';
    exit;
  end;
  S.SaveUndo;
  S.Sheet.DeleteName(S.PromptStr);
end;

procedure NameLabelsDone(S: TSession; const path: string);
var
  r, c, tr, tc: Integer;
  cell: TCell;
  p: Char;
  txt, nm: string;
  dr, dc: Integer;
begin
  dr := 0;
  dc := 0;
  if path.EndsWith('Right') then dc := 1
  else if path.EndsWith('Down') then dr := 1
  else if path.EndsWith('Left') then dc := -1
  else dr := -1;
  S.SaveUndo;
  for r := S.Range.R1 to S.Range.R2 do
    for c := S.Range.C1 to S.Range.C2 do
    begin
      cell := S.Sheet.Find(r, c);
      if (cell = nil) or not TextOf(cell, p, txt) then continue;
      nm := UpperCase(Copy(Trim(txt), 1, 15));
      tr := r + dr;
      tc := c + dc;
      if IsValidName(nm) and InBounds(tr, tc) then
        S.Sheet.SetName(nm, NormRange(tr, tc, tr, tc));
    end;
end;

procedure CmdNameLabels(S: TSession; const path: string);
begin
  S.AskRange('Enter label range:', @NameLabelsDone, path);
end;

function RangeText(const g: TRange): string;
begin
  Result := ColLetter(g.C1) + IntToStr(g.R1);
  if (g.R1 <> g.R2) or (g.C1 <> g.C2) then
    Result := Result + '..' + ColLetter(g.C2) + IntToStr(g.R2);
end;

procedure NameTableDone(S: TSession; const path: string);
var
  names: TStringList;
  i: Integer;
  g: TRange;
begin
  names := TStringList.Create;
  try
    S.Sheet.NameList(names);
    if S.Range.R1 + names.Count - 1 > MaxRow then
    begin
      S.Msg := 'Not enough room for the table';
      exit;
    end;
    S.SaveUndo;
    for i := 0 to names.Count - 1 do
    begin
      S.Sheet.FindName(names[i], g);
      S.Sheet.Put(S.Range.R1 + i, S.Range.C1, '''' + names[i]);
      if S.Range.C1 < MaxCol then
        S.Sheet.Put(S.Range.R1 + i, S.Range.C1 + 1, '''' + RangeText(g));
    end;
  finally
    names.Free;
  end;
end;

procedure CmdName(S: TSession; const path: string);
begin
  if path = 'Range Name Create' then
    S.AskText('Enter name:', '', @NameCreateText, path)
  else if path = 'Range Name Delete' then
    S.AskText('Enter name to delete:', '', @NameDeleteText, path)
  else if path = 'Range Name Reset' then
  begin
    S.SaveUndo;
    S.Sheet.ClearNames;
  end
  else if path = 'Range Name Table' then
    S.AskRange('Enter range for table of names:', @NameTableDone, path);
end;

{ ---------------------------------------------------------------- titles }

procedure CmdTitles(S: TSession; const path: string);
var
  both, horiz, vert, clear: Boolean;
  r1, c1: Integer;
begin
  clear := path.EndsWith('Clear');
  both := path.EndsWith('Both');
  horiz := both or path.EndsWith('Horizontal');
  vert := both or path.EndsWith('Vertical');
  S.SaveUndo;
  if clear then
  begin
    S.Sheet.TitleR1 := 0; S.Sheet.TitleR2 := 0;
    S.Sheet.TitleC1 := 0; S.Sheet.TitleC2 := 0;
    exit;
  end;
  if horiz then
  begin
    if S.HasTitleRows then r1 := S.Sheet.TitleR1 else r1 := S.TopRow;
    if S.CurRow - 1 >= r1 then
    begin
      S.Sheet.TitleR1 := r1;
      S.Sheet.TitleR2 := S.CurRow - 1;
      S.TopRow := S.CurRow;
    end
    else
    begin
      S.Sheet.TitleR1 := 0;
      S.Sheet.TitleR2 := 0;
    end;
  end;
  if vert then
  begin
    if S.HasTitleCols then c1 := S.Sheet.TitleC1 else c1 := S.LeftCol;
    if S.CurCol - 1 >= c1 then
    begin
      S.Sheet.TitleC1 := c1;
      S.Sheet.TitleC2 := S.CurCol - 1;
      S.LeftCol := S.CurCol;
    end
    else
    begin
      S.Sheet.TitleC1 := 0;
      S.Sheet.TitleC2 := 0;
    end;
  end;
end;

procedure LearnRangeDone(S: TSession; const path: string);
begin
  S.LearnRange := S.Range;
  S.LearnSet := True;
  S.LearnOn := False;
  S.LearnRow := S.Range.R1;
  S.LearnCol := S.Range.C1;
  S.LearnLine := '';
end;

procedure CmdLearn(S: TSession; const path: string);
begin
  if path.EndsWith('Range') then
    S.AskRange('Enter learn range:', @LearnRangeDone, path)
  else if path.EndsWith('Cancel') then
  begin
    S.LearnSet := False;
    S.LearnOn := False;
  end
  else if S.LearnSet then
  begin
    S.SaveUndo;
    S.EraseLearnRange;
  end;
end;

procedure RegisterEditCommands(C: TCommands);
const
  Dirs: array[0..3] of string = ('Right', 'Down', 'Left', 'Up');
  TitleKinds: array[0..3] of string = ('Both', 'Horizontal', 'Vertical', 'Clear');
var
  k: Integer;
begin
  C.Register('Copy', @CmdTwoRanges);
  C.Register('Move', @CmdTwoRanges);
  C.Register('Range Value', @CmdTwoRanges);
  C.Register('Range Trans', @CmdTwoRanges);
  C.Register('Worksheet Insert Column', @CmdInsDel);
  C.Register('Worksheet Insert Row', @CmdInsDel);
  C.Register('Worksheet Delete Column', @CmdInsDel);
  C.Register('Worksheet Delete Row', @CmdInsDel);
  C.Register('Worksheet Learn Range', @CmdLearn);
  C.Register('Worksheet Learn Cancel', @CmdLearn);
  C.Register('Worksheet Learn Erase', @CmdLearn);
  C.Register('Range Name Create', @CmdName);
  C.Register('Range Name Delete', @CmdName);
  C.Register('Range Name Reset', @CmdName);
  C.Register('Range Name Table', @CmdName);
  for k := 0 to 3 do
  begin
    C.Register('Range Name Labels ' + Dirs[k], @CmdNameLabels);
    C.Register('Worksheet Titles ' + TitleKinds[k], @CmdTitles);
  end;
end;

end.
