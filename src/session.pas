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

{ All mutable UI-visible state of a running spreadsheet session. No drawing,
  no key handling: those live in view.pas and controller.pas. }
unit session;
{$mode objfpc}{$H+}

interface

uses sheet, menutree, calc;

type
  TMode = (mReady, mLabel, mValue, mEdit, mMenu, mGoto, mPrompt, mPoint);

  TSession = class;
  { A command, or the continuation of a command that asked a question.
    path is the menu path that started it, e.g. 'Range Format Fixed'. }
  TCommandProc = procedure(S: TSession; const path: string);

  TRange = record
    R1, C1, R2, C2: Integer;
  end;

  { while a numeric prompt is open, Left/Right arrows can nudge a column width }
  TPromptLive = (plNone, plColumn, plGlobalWidth);

  TSession = class
  public
    Sheet: TSheet;
    Calc: TCalc;
    Menus: TMenuTree;
    CurCol, CurRow: Integer;
    LeftCol, TopRow: Integer;
    GridRows, GridW: Integer;           { size of the cell area, set by the view }
    Mode: TMode;
    Entry: string;                      { text being typed or edited (UTF-8) }
    EditPos: Integer;                   { insertion point in Entry, in characters }
    Msg: string;                        { one-shot message for the bottom line }
    EndMode: Boolean;
    Quitting: Boolean;

    { menu navigation: level d shows MenuNodes[d].Kids, highlight MenuIdx[d] }
    MenuDepth: Integer;
    MenuNodes: array[0..15] of TMenuNode;
    MenuIdx: array[0..15] of Integer;

    { numeric prompt }
    PromptText: string;
    PromptMin, PromptMax, PromptNum: Integer;
    PromptCont: TCommandProc;
    PromptPath: string;
    PromptLive: TPromptLive;
    PromptOrigWidth: Integer;

    { range selection (POINT mode) }
    PointText: string;
    PointCont: TCommandProc;
    PointPath: string;
    Anchored, Typing: Boolean;
    AnchorR, AnchorC: Integer;
    OrigRow, OrigCol, OrigTop, OrigLeft: Integer;
    Range: TRange;                      { result of the last range prompt }

    PendFmt: TCellFormat;               { scratch for multi-step commands }

    { single-level undo: a journal of what the last command changed }
    UndoSet: TChangeSet;
    HasUndo: Boolean;

    constructor Create;
    destructor Destroy; override;
    function RightColOf(left: Integer): Integer;
    procedure Normalize;
    procedure OpenMenu;
    function MenuPath(upTo: Integer): string;   { "Worksheet Global Format" }

    procedure AskNumber(const text: string; def, lo, hi: Integer;
                        cont: TCommandProc; const path: string; live: TPromptLive = plNone);
    procedure AskRange(const text: string; cont: TCommandProc; const path: string);
    function Selection: TRange;                 { cells to highlight }
    procedure SaveUndo;                         { call before changing the worksheet }
    procedure EndChange;                        { the command is done; stop recording }
    procedure DoUndo;
  end;

function NormRange(r1, c1, r2, c2: Integer): TRange;

implementation

uses menudata, SysUtils;

function NormRange(r1, c1, r2, c2: Integer): TRange;
begin
  if r1 <= r2 then begin Result.R1 := r1; Result.R2 := r2; end
  else begin Result.R1 := r2; Result.R2 := r1; end;
  if c1 <= c2 then begin Result.C1 := c1; Result.C2 := c2; end
  else begin Result.C1 := c2; Result.C2 := c1; end;
end;

constructor TSession.Create;
begin
  inherited Create;
  Sheet := TSheet.Create;
  Calc := TCalc.Create(Sheet);
  Menus := BuildMenuTree;
  CurCol := 1; CurRow := 1; LeftCol := 1; TopRow := 1;
  GridRows := 20;
  GridW := 76;
  Mode := mReady;
end;

destructor TSession.Destroy;
begin
  Menus.Free;
  UndoSet.Free;
  Calc.Free;
  Sheet.Free;
  inherited Destroy;
end;

function TSession.RightColOf(left: Integer): Integer;
var
  w, c: Integer;
begin
  c := left;
  w := Sheet.ColWidth(c);
  while (c < MaxCol) and (w + Sheet.ColWidth(c + 1) <= GridW) do
  begin
    Inc(c);
    Inc(w, Sheet.ColWidth(c));
  end;
  Result := c;
end;

procedure TSession.Normalize;
begin
  if CurCol < 1 then CurCol := 1;
  if CurCol > MaxCol then CurCol := MaxCol;
  if CurRow < 1 then CurRow := 1;
  if CurRow > MaxRow then CurRow := MaxRow;
  if CurCol < LeftCol then LeftCol := CurCol;
  while (LeftCol < CurCol) and (RightColOf(LeftCol) < CurCol) do Inc(LeftCol);
  if CurRow < TopRow then TopRow := CurRow;
  if CurRow > TopRow + GridRows - 1 then TopRow := CurRow - GridRows + 1;
  if TopRow < 1 then TopRow := 1;
  if TopRow > MaxRow - GridRows + 1 then TopRow := MaxRow - GridRows + 1;
end;

procedure TSession.OpenMenu;
begin
  Mode := mMenu;
  MenuDepth := 0;
  MenuNodes[0] := Menus.Root;
  MenuIdx[0] := 0;
end;

function TSession.MenuPath(upTo: Integer): string;
var
  j: Integer;
begin
  Result := '';
  for j := 0 to upTo do
  begin
    if j > 0 then Result := Result + ' ';
    Result := Result + MenuNodes[j][MenuIdx[j]].Name;
  end;
end;

procedure TSession.AskNumber(const text: string; def, lo, hi: Integer;
  cont: TCommandProc; const path: string; live: TPromptLive);
begin
  Mode := mPrompt;
  PromptText := text;
  PromptMin := lo;
  PromptMax := hi;
  PromptNum := def;
  PromptCont := cont;
  PromptPath := path;
  PromptLive := live;
  case live of
    plColumn: PromptOrigWidth := Sheet.ColWidthSetting(CurCol);
    plGlobalWidth: PromptOrigWidth := Sheet.GlobalWidth;
  end;
  Entry := IntToStr(def);
  EditPos := Length(Entry);
end;

procedure TSession.AskRange(const text: string; cont: TCommandProc; const path: string);
begin
  Mode := mPoint;
  PointText := text;
  PointCont := cont;
  PointPath := path;
  Anchored := False;
  Typing := False;
  Entry := '';
  OrigRow := CurRow; OrigCol := CurCol; OrigTop := TopRow; OrigLeft := LeftCol;
end;

function TSession.Selection: TRange;
begin
  if (Mode = mPoint) and Anchored then
    Result := NormRange(AnchorR, AnchorC, CurRow, CurCol)
  else
    Result := NormRange(CurRow, CurCol, CurRow, CurCol);
end;

procedure TSession.SaveUndo;
begin
  UndoSet.Free;                  { single level: the previous change is forgotten }
  UndoSet := Sheet.BeginChange;
  HasUndo := True;
end;

procedure TSession.EndChange;
begin
  Sheet.Journal := nil;
  Calc.SheetChanged;
end;

procedure TSession.DoUndo;
var
  inverse: TChangeSet;
begin
  if not HasUndo then
  begin
    Msg := 'Nothing to undo';
    exit;
  end;
  inverse := Sheet.Revert(UndoSet);
  UndoSet.Free;
  UndoSet := inverse;            { Undo is itself undoable }
end;

end.
