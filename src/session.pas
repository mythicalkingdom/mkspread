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

uses Classes, sheet, menutree, calc, printing, config;

type
  TMode = (mReady, mLabel, mValue, mEdit, mMenu, mGoto, mPrompt, mPoint, mNames, mFind, mHelp);

  TWinState = record                    { the window that does not have the pointer }
    Row, Col, Left, Top: Integer;
  end;

  TSession = class;
  { A command, or the continuation of a command that asked a question.
    path is the menu path that started it, e.g. 'Range Format Fixed'. }
  TCommandProc = procedure(S: TSession; const path: string);

  { while a numeric prompt is open, Left/Right arrows can nudge a column width }
  TPromptLive = (plNone, plColumn, plGlobalWidth);

  { what /Data Sort, Query, Table, Regression and Parse have been told }
  TDataSettings = record
    FillStart, FillStep, FillStop: Double;   { the last Fill values are the next defaults }
    SortSet: Boolean;
    SortRange: TRange;
    Key1, Key2: Integer;                 { key columns, 0 = none }
    Asc1, Asc2: Boolean;
    QInSet, QCritSet, QOutSet: Boolean;
    QIn, QCrit, QOut: TRange;
    TableKind: Integer;                  { 0 none, 1 or 2 }
    TableRange, TableIn1, TableIn2: TRange;
    RegXSet, RegYSet, RegOutSet: Boolean;
    RegX, RegY, RegOut: TRange;
    RegZero: Boolean;
    ParseInSet, ParseOutSet: Boolean;
    ParseIn, ParseOut: TRange;
  end;

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
    HelpId: string;                      { the topic on show }
    HelpScroll: Integer;                 { first body line shown }
    HelpSel: Integer;                    { selected related topic (or index entry) }
    HelpBack: TStringList;               { topics visited before this one }
    HelpReturn: TMode;                   { the mode to go back to }
    ReturnPath: string;                  { a menu to open again when the command is finished }
    MenuNodes: array[0..15] of TMenuNode;
    MenuIdx: array[0..15] of Integer;

    { numeric prompt }
    PromptText: string;
    PromptMin, PromptMax, PromptNum: Integer;
    PromptCont: TCommandProc;
    PromptPath: string;
    PromptLive: TPromptLive;
    PromptOrigWidth: Integer;
    PromptFresh: Boolean;               { the default is still untouched: typing replaces it }
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
    MacroRequest: string;               { name of a macro to start (set by Alt-key, Alt-F3, autoexec) }
    MacroActive: Boolean;               { a macro is running or paused }
    IndicatorText: string;              { replaces the mode indicator (macro {INDICATE}) }
    StepOn: Boolean;                    { STEP mode: a macro runs one key at a time }
    StepInfo: string;                   { the macro line being stepped, shown at the bottom }
    LearnSet, LearnOn: Boolean;         { a learn range is defined / keystrokes are being recorded }
    LearnRange: TRange;
    LearnRow, LearnCol: Integer;        { the cell being filled }
    LearnLine: string;                  { its text so far }
    ChoiceHelp: TStringList;            { a help line per choice, shown on line 3 }

    { range selection (POINT mode) }
    PointText: string;
    PointCont: TCommandProc;
    PointPath: string;
    Anchored, Typing: Boolean;
    AnchorR, AnchorC: Integer;
    OrigRow, OrigCol, OrigTop, OrigLeft: Integer;
    WinKind: Integer;                   { 0 one window, 1 split horizontally (top/bottom), 2 vertically }
    WinSize: Integer;                   { rows of the top window / width of the left one }
    WinActive: Integer;                 { 0 = top or left window, 1 = bottom or right }
    WinSync: Boolean;                   { windows scroll together }
    WinOther: TWinState;
    ScreenW, ScreenH: Integer;
    Cfg: TConfig;                       { the settings (and /Worksheet Global Default) }
    Modified: Boolean;                  { the worksheet has changes that are not in a file }
    Changes: Cardinal;                  { counts changes (for the recovery file) }
    SeenVersion: Cardinal;
    Print: TPrintSettings;               { /Print settings and the output not yet sent }
    FPActive: Boolean;                  { pointing at cells while typing a formula }
    FPStart, FPLen: Integer;            { where the reference text is in the entry }
    Range: TRange;                      { result of the last range prompt }

    PendFmt: TCellFormat;               { scratch for multi-step commands }
    PendNum: array[0..3] of Double;
    Data: TDataSettings;
    FindRows: TList;                    { /Data Query Find: matching record rows }
    FindIdx: Integer;
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
    procedure WinRect(idx: Integer; out x0, y0, rows, wtot: Integer);
    procedure ApplyGeometry;            { GridW and GridRows of the window with the pointer }
    procedure WindowSplit(kind: Integer);
    procedure WindowClear;
    procedure WindowSwitch;             { F6 }
    procedure SyncWindows;
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
    { macro recording (Learn): Alt-F5 turns it on and off }
    procedure ToggleLearn;
    procedure LearnKey(k: Integer);
    procedure EraseLearnRange;
    procedure AskRange(const text: string; cont: TCommandProc; const path: string);
    function Selection: TRange;                 { cells to highlight }
    procedure CheckModified;                    { notices changes made without SaveUndo }
    procedure MarkSaved;                        { the worksheet and its file agree }
    procedure SaveUndo;                         { call before changing the worksheet }
    procedure EndChange;                        { the command is done; stop recording }
    procedure DoUndo;
  end;

implementation

uses menudata, u8edit, keys, SysUtils;

constructor TSession.Create;
begin
  inherited Create;
  Sheet := TSheet.Create;
  Calc := TCalc.Create(Sheet);
  Menus := BuildMenuTree;
  NameChoices := TStringList.Create;
  FindRows := TList.Create;
  HelpBack := TStringList.Create;
  ChoiceHelp := TStringList.Create;
  CurCol := 1; CurRow := 1; LeftCol := 1; TopRow := 1;
  ResetPrint(Print);
  DefaultConfig(Cfg);
  ScreenW := 80;
  ScreenH := 25;
  Print.Pos := 0;
  Print.PageNo := 1;
  Data.FillStart := 0; Data.FillStep := 1; Data.FillStop := 8191;
  GridRows := 20;
  GridW := 76;
  Mode := mReady;
end;

destructor TSession.Destroy;
begin
  FindRows.Free;
  ChoiceHelp.Free;
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

{ ---------------------------------------------------------------- windows }

{ where window idx is on the screen: x0 its first column, y0 the line of its column
  letters, rows its number of data rows, wtot its width (with the row numbers) }
procedure TSession.WinRect(idx: Integer; out x0, y0, rows, wtot: Integer);
begin
  x0 := 1;
  y0 := 4;
  rows := ScreenH - 5;
  wtot := ScreenW;
  case WinKind of
    1: if idx = 0 then rows := WinSize
       else begin y0 := 5 + WinSize; rows := ScreenH - 6 - WinSize; end;
    2: if idx = 0 then wtot := WinSize
       else begin x0 := WinSize + 2; wtot := ScreenW - WinSize - 1; end;
  end;
  if rows < 1 then rows := 1;
end;

procedure TSession.ApplyGeometry;
var
  x0, y0, rows, wtot: Integer;
begin
  WinRect(WinActive, x0, y0, rows, wtot);
  GridRows := rows;
  GridW := wtot - 4;
end;

procedure TSession.WindowClear;
begin
  WinKind := 0;
  WinActive := 0;
  ApplyGeometry;
  Normalize;
end;

procedure TSession.WindowSplit(kind: Integer);
var
  i, rows, w: Integer;
begin
  if WinKind <> 0 then WindowClear;
  if kind = 1 then
  begin
    rows := ScreenH - 5;
    WinSize := CurRow - TopRow;
    if WinSize < 1 then WinSize := 1;
    if WinSize > rows - 3 then WinSize := rows - 3;
    WinOther.Row := CurRow - 1;
    if WinOther.Row < TopRow then WinOther.Row := TopRow;
    WinOther.Col := CurCol;
    WinOther.Left := LeftCol;
    WinOther.Top := TopRow;
    TopRow := CurRow;                  { the lower window starts at the pointer's row }
  end
  else
  begin
    w := 4;
    for i := LeftCol to CurCol - 1 do Inc(w, Sheet.ColWidth(i));
    if CurCol = LeftCol then w := 4 + Sheet.ColWidth(LeftCol);
    if w > ScreenW - 12 then w := ScreenW - 12;
    if w < 8 then w := 8;
    WinSize := w;
    WinOther.Row := CurRow;
    WinOther.Col := CurCol - 1;
    if WinOther.Col < LeftCol then WinOther.Col := LeftCol;
    WinOther.Left := LeftCol;
    WinOther.Top := TopRow;
    LeftCol := CurCol;                 { the right window starts at the pointer's column }
  end;
  WinKind := kind;
  WinActive := 1;
  WinSync := True;
  ApplyGeometry;
  Normalize;
end;

procedure TSession.WindowSwitch;
var
  t: TWinState;
begin
  if WinKind = 0 then
  begin
    Msg := 'There is only one window';
    exit;
  end;
  t.Row := CurRow; t.Col := CurCol; t.Left := LeftCol; t.Top := TopRow;
  CurRow := WinOther.Row; CurCol := WinOther.Col; LeftCol := WinOther.Left; TopRow := WinOther.Top;
  WinOther := t;
  WinActive := 1 - WinActive;
  ApplyGeometry;
  Normalize;
end;

procedure TSession.SyncWindows;
begin
  if (WinKind = 0) or not WinSync then exit;
  if WinKind = 1 then WinOther.Left := LeftCol else WinOther.Top := TopRow;
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
  PromptFresh := True;
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
  PromptFresh := def <> '';
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
  ChoiceHelp.Clear;
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
  ChoiceHelp.Clear;
  Mode := mNames;
end;

procedure TSession.ShowChoices(items: TStrings; returnTo: TMode);
begin
  NameChoices.Assign(items);
  NameReturn := returnTo;
  NameIdx := 0;
  ChoiceIsName := False;
  ChoiceCont := nil;
  ChoiceHelp.Clear;
  Mode := mNames;
end;

procedure TSession.ToggleLearn;
var
  r, c: Integer;
begin
  if LearnOn then
  begin
    LearnOn := False;
    exit;
  end;
  if not LearnSet then
  begin
    Msg := 'Set a learn range first (/Worksheet Learn Range)';
    exit;
  end;
  { continue after what is already recorded: the first empty cell, down then across }
  for c := LearnRange.C1 to LearnRange.C2 do
    for r := LearnRange.R1 to LearnRange.R2 do
      if not Sheet.NonEmpty(r, c) then
      begin
        LearnRow := r;
        LearnCol := c;
        LearnLine := '';
        LearnOn := True;
        exit;
      end;
  Msg := 'The learn range is full';
end;

procedure TSession.LearnKey(k: Integer);
const
  MaxLine = 100;
var
  t: string;
begin
  if not LearnOn then exit;
  t := KeyMacroText(k);
  if t = '' then exit;
  if (LearnLine <> '') and (Length(LearnLine) + Length(t) > MaxLine) then
  begin
    { start the next cell }
    Inc(LearnRow);
    LearnLine := '';
    if LearnRow > LearnRange.R2 then
    begin
      LearnRow := LearnRange.R1;
      Inc(LearnCol);
    end;
    if LearnCol > LearnRange.C2 then
    begin
      LearnOn := False;
      Msg := 'The learn range is full';
      exit;
    end;
  end;
  LearnLine := LearnLine + t;
  Sheet.Put(LearnRow, LearnCol, '''' + LearnLine);
end;

procedure TSession.EraseLearnRange;
var
  r, c: Integer;
begin
  if not LearnSet then exit;
  for r := LearnRange.R1 to LearnRange.R2 do
    for c := LearnRange.C1 to LearnRange.C2 do
      Sheet.Remove(r, c);
  LearnRow := LearnRange.R1;
  LearnCol := LearnRange.C1;
  LearnLine := '';
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
  if (Mode = mFind) and Data.QInSet then
    Result := NormRange(CurRow, Data.QIn.C1, CurRow, Data.QIn.C2)
  else if ((Mode = mPoint) or FPActive) and Anchored then
    Result := NormRange(AnchorR, AnchorC, CurRow, CurCol)
  else
    Result := NormRange(CurRow, CurCol, CurRow, CurCol);
end;

procedure TSession.CheckModified;
begin
  if Sheet.Version <> SeenVersion then
  begin
    SeenVersion := Sheet.Version;
    Modified := True;
    Inc(Changes);
  end;
end;

procedure TSession.MarkSaved;
begin
  Modified := False;
  SeenVersion := Sheet.Version;
end;

procedure TSession.SaveUndo;
begin
  Modified := True;
  Inc(Changes);
  if not Cfg.UndoOn then
  begin
    UndoSet.Free;
    UndoSet := nil;
    HasUndo := False;
    exit;
  end;
  UndoSet.Free;                  { single level: the previous change is forgotten }
  UndoSet := Sheet.BeginChange;
  HasUndo := True;
end;

procedure TSession.EndChange;
begin
  Sheet.Journal := nil;
  Sheet.PointerRow := CurRow;
  Sheet.PointerCol := CurCol;
  Sheet.FileName := FileName;
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
