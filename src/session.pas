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

uses Classes, sheet, menutree, calc;

type
  TMode = (mReady, mLabel, mValue, mEdit, mMenu, mGoto, mPrompt, mPoint, mNames);

  TSession = class;
  { A command, or the continuation of a command that asked a question.
    path is the menu path that started it, e.g. 'Range Format Fixed'. }
  TCommandProc = procedure(S: TSession; const path: string);

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
    PromptIsText: Boolean;              { a text prompt rather than a number }
    PromptStr: string;                  { its answer }

    { choosing a range name from a list (F3) }
    NameChoices: TStringList;
    NameIdx: Integer;
    NameReturn: TMode;                  { mode to go back to }
    ChoiceIsName: Boolean;              { the choices are range names }
    ChoiceCont: TCommandProc;           { called when a choice is made (nil: just pick) }
    ChoicePath: string;
    ChoiceIndex: Integer;
    PromptFilter: string;               { text prompt for a file: patterns for F3 }
    FileName: string;                   { the file last retrieved or saved }

    { range selection (POINT mode) }
    PointText: string;
    PointCont: TCommandProc;
    PointPath: string;
    Anchored, Typing: Boolean;
    AnchorR, AnchorC: Integer;
    OrigRow, OrigCol, OrigTop, OrigLeft: Integer;
    Range: TRange;                      { result of the last range prompt }

    PendFmt: TCellFormat;               { scratch for multi-step commands }
    PendRange: TRange;
    PendStr: string;

    { single-level undo: a journal of what the last command changed }
    UndoSet: TChangeSet;
    HasUndo: Boolean;

    constructor Create;
    destructor Destroy; override;
    function HasTitleRows: Boolean;
    function HasTitleCols: Boolean;
    function TitleRowCount: Integer;
    function TitleWidth: Integer;
    function ScrollRows: Integer;       { rows available to scrolling }
    function ScrollW: Integer;          { columns' width available to scrolling }
    function RightColOf(left: Integer): Integer;
    procedure Normalize;
    procedure OpenMenu;
    function MenuPath(upTo: Integer): string;   { "Worksheet Global Format" }

    procedure AskNumber(const text: string; def, lo, hi: Integer;
                        cont: TCommandProc; const path: string; live: TPromptLive = plNone);
    procedure AskText(const text, def: string; cont: TCommandProc; const path: string);
    function OpenNameList: Boolean;     { False when there are no names }
    { A one-line list to choose from; cont runs with ChoiceIndex set. }
    procedure AskChoice(const items: array of string; cont: TCommandProc; const path: string);
    procedure ShowChoices(items: TStrings; returnTo: TMode);
    procedure ForgetUndo;
    procedure AskRange(const text: string; cont: TCommandProc; const path: string);
    function Selection: TRange;                 { cells to highlight }
    procedure SaveUndo;                         { call before changing the worksheet }
    procedure EndChange;                        { the command is done; stop recording }
    procedure DoUndo;
  end;

implementation

uses menudata, u8edit, SysUtils;

constructor TSession.Create;
begin
  inherited Create;
  Sheet := TSheet.Create;
  Calc := TCalc.Create(Sheet);
  Menus := BuildMenuTree;
  NameChoices := TStringList.Create;
  CurCol := 1; CurRow := 1; LeftCol := 1; TopRow := 1;
  GridRows := 20;
  GridW := 76;
  Mode := mReady;
end;

destructor TSession.Destroy;
begin
  NameChoices.Free;
  Menus.Free;
  UndoSet.Free;
  Calc.Free;
  Sheet.Free;
  inherited Destroy;
end;

function TSession.HasTitleRows: Boolean;
begin
  Result := (Sheet.TitleR1 > 0) and (Sheet.TitleR2 >= Sheet.TitleR1);
end;

function TSession.HasTitleCols: Boolean;
begin
  Result := (Sheet.TitleC1 > 0) and (Sheet.TitleC2 >= Sheet.TitleC1);
end;

function TSession.TitleRowCount: Integer;
begin
  if HasTitleRows then Result := Sheet.TitleR2 - Sheet.TitleR1 + 1 else Result := 0;
end;

function TSession.TitleWidth: Integer;
var
  c: Integer;
begin
  Result := 0;
  if HasTitleCols then
    for c := Sheet.TitleC1 to Sheet.TitleC2 do Inc(Result, Sheet.ColWidth(c));
end;

function TSession.ScrollRows: Integer;
begin
  Result := GridRows - TitleRowCount;
  if Result < 1 then Result := 1;
end;

function TSession.ScrollW: Integer;
begin
  Result := GridW - TitleWidth;
  if Result < 1 then Result := 1;
end;

function TSession.RightColOf(left: Integer): Integer;
var
  w, c: Integer;
begin
  c := left;
  w := Sheet.ColWidth(c);
  while (c < MaxCol) and (w + Sheet.ColWidth(c + 1) <= ScrollW) do
  begin
    Inc(c);
    Inc(w, Sheet.ColWidth(c));
  end;
  Result := c;
end;

procedure TSession.Normalize;
var
  minLeft, minTop: Integer;
begin
  if CurCol < 1 then CurCol := 1;
  if CurCol > MaxCol then CurCol := MaxCol;
  if CurRow < 1 then CurRow := 1;
  if CurRow > MaxRow then CurRow := MaxRow;

  minLeft := 1;
  if HasTitleCols then minLeft := Sheet.TitleC2 + 1;
  if LeftCol < minLeft then LeftCol := minLeft;
  if not (HasTitleCols and (CurCol >= Sheet.TitleC1) and (CurCol <= Sheet.TitleC2)) then
  begin
    if CurCol < LeftCol then LeftCol := CurCol;
    while (LeftCol < CurCol) and (RightColOf(LeftCol) < CurCol) do Inc(LeftCol);
  end;

  minTop := 1;
  if HasTitleRows then minTop := Sheet.TitleR2 + 1;
  if TopRow < minTop then TopRow := minTop;
  if not (HasTitleRows and (CurRow >= Sheet.TitleR1) and (CurRow <= Sheet.TitleR2)) then
  begin
    if CurRow < TopRow then TopRow := CurRow;
    if CurRow > TopRow + ScrollRows - 1 then TopRow := CurRow - ScrollRows + 1;
  end;
  if TopRow > MaxRow - ScrollRows + 1 then TopRow := MaxRow - ScrollRows + 1;
  if TopRow < minTop then TopRow := minTop;
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
  PromptIsText := False;
end;

procedure TSession.AskText(const text, def: string; cont: TCommandProc; const path: string);
begin
  Mode := mPrompt;
  PromptText := text;
  PromptCont := cont;
  PromptPath := path;
  PromptLive := plNone;
  PromptIsText := True;
  PromptFilter := '';
  Entry := def;
  EditPos := U8Len(def);
end;

function TSession.OpenNameList: Boolean;
begin
  Sheet.NameList(NameChoices);
  Result := NameChoices.Count > 0;
  if not Result then
  begin
    Msg := 'No range names are defined';
    exit;
  end;
  NameReturn := Mode;
  NameIdx := 0;
  ChoiceIsName := True;
  ChoiceCont := nil;
  Mode := mNames;
end;

procedure TSession.AskChoice(const items: array of string; cont: TCommandProc; const path: string);
var
  i: Integer;
begin
  NameChoices.Clear;
  for i := 0 to High(items) do NameChoices.Add(items[i]);
  NameReturn := mReady;
  NameIdx := 0;
  ChoiceIsName := False;
  ChoiceCont := cont;
  ChoicePath := path;
  Mode := mNames;
end;

procedure TSession.ShowChoices(items: TStrings; returnTo: TMode);
begin
  NameChoices.Assign(items);
  NameReturn := returnTo;
  NameIdx := 0;
  ChoiceIsName := False;
  ChoiceCont := nil;
  Mode := mNames;
end;

procedure TSession.ForgetUndo;
begin
  UndoSet.Free;
  UndoSet := nil;
  HasUndo := False;
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
