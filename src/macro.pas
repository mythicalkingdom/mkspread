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

{ The macro interpreter.

  A macro is text in worksheet cells: it is read from its first cell down until
  a cell that is empty or not text.  Characters are typed as keystrokes, ~ is
  Enter, and {...} holds special keys and commands.  The interpreter produces
  one key at a time (NextKey); the caller passes each key to the controller,
  so a macro does exactly what typing would do.

  Commands implemented: the special keys ({UP 3}, {HOME}, {EDIT}, ...), {?},
  {BRANCH}, {IF}, {QUIT}, {RETURN}, {RESTART}, subroutine calls {name args}
  with {DEFINE}, {FOR}/{FORBREAK}, {MENUBRANCH}, {MENUCALL}, {LET}, {PUT},
  {BLANK}, {CONTENTS}, {GETLABEL}, {GETNUMBER}, {GET}, {LOOK}, {RECALC},
  {RECALCCOL}, {INDICATE}, and accepted-but-ignored {BEEP}, {WAIT},
  {PANELOFF}, {PANELON}, {WINDOWSOFF}, {WINDOWSON}, {BREAKOFF}, {BREAKON},
  {ONERROR}.  File and system commands are not implemented. }
unit macro;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, sheet, formula, session, controller;

type
  TWait = (wNone, wQuestion, wPrompt, wMenu, wGet);

  TFrame = record
    IsFor: Boolean;
    Row, Col, Pos: Integer;        { where to resume }
    Counter: TRange;               { FOR: the counter cell }
    Stop, Step: Double;
    Routine: TRange;
    Args: array of string;         { arguments of a subroutine call, for {DEFINE} }
  end;

  TMacro = class
  private
    FS: TSession;
    FActive: Boolean;
    FWait: TWait;
    FRow, FCol, FPos: Integer;     { current cell and byte position in its text }
    FLine: string;
    FHaveLine: Boolean;
    FJumpPos: Integer;             { position to use when the next line loads }
    FFrames: array of TFrame;
    FRepeatKey, FRepeatLeft: Integer;
    FLoc: TRange;                  { where a pending prompt or key goes }
    FPromptNumber: Boolean;
    FMenuRow, FMenuCol, FMenuCount: Integer;
    FMenuCall: Boolean;
    FMenuDone, FMenuChosen: Boolean;
    FPromptDone: Boolean;
    FStepWait, FStepOK: Boolean;
    function LoadLine: Boolean;
    procedure Jump(r, c, pos: Integer);
    procedure PushFrame(isFor: Boolean; const args: array of string);
    function PopFrame: Boolean;
    function ExecCommand(const cmd: string; out key: Integer): Boolean;
    function Eval(const expr: string; out v: TValue): Boolean;
    function EvalNum(const expr: string; out d: Double): Boolean;
    function Loc(const s: string; out r, c: Integer): Boolean;
    procedure StoreValue(r, c: Integer; const v: TValue);
    procedure StoreLabel(r, c: Integer; const text: string);
    procedure Changed;
    function StillWaiting: Boolean;
    function StepGate: Boolean;
  public
    constructor Create(S: TSession);
    destructor Destroy; override;
    { Start the macro whose range name is in S.MacroRequest.  False if none. }
    function TakeRequest: Boolean;
    procedure Start(r, c: Integer);
    procedure Stop;
    function Active: Boolean;
    { Running: active and not waiting for the user }
    function Running: Boolean;
    function NextKey(out k: Integer): Boolean;
    { A key came from the user.  True if the macro used it up ({GET}). }
    function UserKey(k: Integer): Boolean;
    { for tests and batch use: run until the macro ends or has to wait }
    procedure RunSync(Ctl: TController; maxKeys: Integer = 200000);
    { callbacks of prompts started by the macro }
    procedure PromptFinished;
    procedure MenuFinished;
  end;

implementation

uses keys, cellfmt, calc, u8edit;

var
  Current: TMacro;          { the macro whose prompt callbacks are pending }

procedure PromptCallback(S: TSession; const path: string);
begin
  if Current <> nil then Current.PromptFinished;
end;

procedure MenuCallback(S: TSession; const path: string);
begin
  if Current <> nil then Current.MenuFinished;
end;

constructor TMacro.Create(S: TSession);
begin
  inherited Create;
  FS := S;
  Current := Self;
end;

destructor TMacro.Destroy;
begin
  if Current = Self then Current := nil;
  inherited Destroy;
end;

{ ------------------------------------------------------------------ state }

function TMacro.Active: Boolean;
begin
  Result := FActive;
end;

{ In STEP mode each key and command waits for a key press from the user. }
function TMacro.StepGate: Boolean;
begin
  if (not FS.StepOn) or FStepOK then
  begin
    FStepOK := False;
    FS.StepInfo := '';
    exit(True);
  end;
  FStepWait := True;
  FS.StepInfo := ColLetter(FCol) + IntToStr(FRow) + ': ' + Copy(FLine, 1, FPos - 1) + '>' + Copy(FLine, FPos, MaxInt);
  Result := False;
end;

function TMacro.StillWaiting: Boolean;
begin
  if FStepWait then exit(True);
  case FWait of
    wNone: Result := False;
    wQuestion, wGet: Result := True;
    wPrompt: Result := (FS.Mode = mPrompt) and not FPromptDone;
    wMenu: Result := (FS.Mode = mNames) and not FMenuDone;
  else
    Result := False;
  end;
end;

function TMacro.Running: Boolean;
begin
  Result := FActive and not StillWaiting;
end;

procedure TMacro.Stop;
begin
  FActive := False;
  FWait := wNone;
  SetLength(FFrames, 0);
  FRepeatLeft := 0;
  FS.MacroActive := False;
  FS.IndicatorText := '';
  FS.StepInfo := '';
  FStepWait := False;
  FStepOK := False;
end;

procedure TMacro.Start(r, c: Integer);
begin
  SetLength(FFrames, 0);
  FWait := wNone;
  FRepeatLeft := 0;
  FHaveLine := False;
  FJumpPos := 1;
  FRow := r;
  FCol := c;
  FActive := True;
  FS.MacroActive := True;
end;

function TMacro.TakeRequest: Boolean;
var
  g: TRange;
  nm: string;
begin
  Result := False;
  nm := FS.MacroRequest;
  FS.MacroRequest := '';
  if nm = '' then exit;
  if FS.Sheet.FindName(nm, g) then
  begin
    Start(g.R1, g.C1);
    Result := True;
  end
  else
    FS.Msg := 'Macro ' + nm + ' is not defined';
end;

procedure TMacro.Changed;
begin
  FS.EndChange;               { recalculates when in automatic mode }
end;

{ ------------------------------------------------------------------ reading macro text }

function TMacro.LoadLine: Boolean;
var
  cell: TCell;
  p: Char;
  t: string;
begin
  Result := False;
  if (FRow > MaxRow) or (FCol > MaxCol) then exit;
  cell := FS.Sheet.Find(FRow, FCol);
  if (cell = nil) or (cell.Raw = '') then exit;
  if not TextOf(cell, p, t) then exit;
  FLine := t;
  FPos := FJumpPos;
  FJumpPos := 1;
  FHaveLine := True;
  Result := True;
end;

procedure TMacro.Jump(r, c, pos: Integer);
begin
  FRow := r;
  FCol := c;
  FJumpPos := pos;
  FHaveLine := False;
end;

procedure TMacro.PushFrame(isFor: Boolean; const args: array of string);
var
  n, i: Integer;
begin
  n := Length(FFrames);
  SetLength(FFrames, n + 1);
  FFrames[n].IsFor := isFor;
  FFrames[n].Row := FRow;
  FFrames[n].Col := FCol;
  FFrames[n].Pos := FPos;
  SetLength(FFrames[n].Args, Length(args));
  for i := 0 to High(args) do FFrames[n].Args[i] := args[i];
end;

{ End of a routine: go back to the caller, or run a FOR loop's next pass.
  False when there is nothing to go back to. }
function TMacro.PopFrame: Boolean;
var
  n: Integer;
  fr: TFrame;
  cell: TCell;
  d: Double;
begin
  Result := False;
  n := High(FFrames);
  if n < 0 then exit;
  fr := FFrames[n];
  if fr.IsFor then
  begin
    cell := FS.Sheet.Find(fr.Counter.R1, fr.Counter.C1);
    d := 0;
    if cell <> nil then CellNumber(cell, d);
    d := d + fr.Step;
    StoreValue(fr.Counter.R1, fr.Counter.C1, NumValue(d));
    if ((fr.Step > 0) and (d <= fr.Stop)) or ((fr.Step < 0) and (d >= fr.Stop)) then
    begin
      Jump(fr.Routine.R1, fr.Routine.C1, 1);          { another pass }
      exit(True);
    end;
  end;
  SetLength(FFrames, n);
  Jump(fr.Row, fr.Col, fr.Pos);
  Result := True;
end;

{ ------------------------------------------------------------------ expressions }

function TMacro.Eval(const expr: string; out v: TValue): Boolean;
var
  t: string;
  f: TFormula;
  pos: Integer;
  d: Double;
  g: TRange;
begin
  Result := False;
  t := Trim(expr);
  v := EmptyValue;
  if t = '' then exit(True);
  if IsNumberLiteral(t, d) then
  begin
    v := NumValue(d);
    exit(True);
  end;
  { a bare word that is not a range name is plain text, e.g. {LET A1,hello} }
  if IsValidName(t) and not FS.Sheet.FindName(t, g) then
  begin
    v := StrValue(t);
    exit(True);
  end;
  if not (t[1] in ValueStarts) then t := '+' + t;
  if CompileFormula(t, f, pos) then
  begin
    try
      v := FS.Calc.EvalFormula(f);
      Result := True;
    finally
      f.Free;
    end;
  end;
end;

function TMacro.EvalNum(const expr: string; out d: Double): Boolean;
var
  v: TValue;
begin
  d := 0;
  Result := Eval(expr, v) and (v.Kind = vkNum);
  if Result then d := v.Num;
end;

function TMacro.Loc(const s: string; out r, c: Integer): Boolean;
var
  g: TRange;
begin
  Result := ParseRangeText(FS.Sheet, Trim(s), g);
  if Result then
  begin
    r := g.R1;
    c := g.C1;
  end;
end;

procedure TMacro.StoreValue(r, c: Integer; const v: TValue);
begin
  case v.Kind of
    vkNum: FS.Sheet.Put(r, c, NumToRaw(v.Num));
    vkStr: FS.Sheet.Put(r, c, FS.Sheet.GlobalLabelPrefix + v.Str);
    vkNA: FS.Sheet.Put(r, c, '@NA');
  else
    FS.Sheet.Put(r, c, '@ERR');
  end;
  Changed;
end;

procedure TMacro.StoreLabel(r, c: Integer; const text: string);
begin
  FS.Sheet.Put(r, c, FS.Sheet.GlobalLabelPrefix + text);
  Changed;
end;

{ arguments separated by commas, except inside quotes and parentheses }
procedure SplitArgs(const s: string; args: TStrings);
var
  i, depth: Integer;
  cur: string;
  inQ: Boolean;
begin
  args.Clear;
  cur := '';
  depth := 0;
  inQ := False;
  for i := 1 to Length(s) do
  begin
    if s[i] = '"' then inQ := not inQ;
    if not inQ then
    begin
      if s[i] = '(' then Inc(depth)
      else if s[i] = ')' then Dec(depth);
      if (s[i] in [',', ';']) and (depth = 0) then
      begin
        args.Add(Trim(cur));
        cur := '';
        continue;
      end;
    end;
    cur := cur + s[i];
  end;
  if (cur <> '') or (args.Count > 0) then args.Add(Trim(cur));
end;

function Unquote(const s: string): string;
begin
  Result := Trim(s);
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

{ ------------------------------------------------------------------ commands }

function KeyForName(const nm: string): Integer;
begin
  if nm = 'UP' then Result := kUp
  else if nm = 'DOWN' then Result := kDown
  else if nm = 'LEFT' then Result := kLeft
  else if nm = 'RIGHT' then Result := kRight
  else if nm = 'HOME' then Result := kHome
  else if nm = 'END' then Result := kEnd
  else if nm = 'PGUP' then Result := kPgUp
  else if nm = 'PGDN' then Result := kPgDn
  else if nm = 'BIGLEFT' then Result := kCtrlLeft
  else if nm = 'BIGRIGHT' then Result := kCtrlRight
  else if (nm = 'DELETE') or (nm = 'DEL') then Result := kDel
  else if (nm = 'BACKSPACE') or (nm = 'BS') then Result := kBackspace
  else if (nm = 'ESCAPE') or (nm = 'ESC') then Result := kEsc
  else if nm = 'EDIT' then Result := kF1 + 1
  else if nm = 'NAME' then Result := kF1 + 2
  else if nm = 'ABS' then Result := kF1 + 3
  else if nm = 'GOTO' then Result := kF1 + 4
  else if nm = 'WINDOW' then Result := kF1 + 5
  else if nm = 'QUERY' then Result := kF1 + 6
  else if nm = 'TABLE' then Result := kF1 + 7
  else if nm = 'CALC' then Result := kF1 + 8
  else if nm = 'GRAPH' then Result := kF1 + 9
  else if nm = 'HELP' then Result := kF1
  else if nm = 'ENTER' then Result := kEnter
  else Result := kNone;
end;

{ Executes one {command}.  Returns True when it produced a key (the repeat
  state is then set up and key is the first of them). }
function TMacro.ExecCommand(const cmd: string; out key: Integer): Boolean;
var
  nm, rest: string;
  p, n, i, r, c, r1, c1, rows, cols, idx: Integer;
  args: TStringList;
  v: TValue;
  d, d2, d3: Double;
  g: TRange;
  k: Integer;
  cell: TCell;
  t: string;
  items: TStringList;
  ch: Char;
begin
  Result := False;
  key := kNone;
  p := 1;
  while (p <= Length(cmd)) and not (cmd[p] in [' ', ',']) do Inc(p);
  nm := UpperCase(Copy(cmd, 1, p - 1));
  rest := Trim(Copy(cmd, p, MaxInt));
  args := TStringList.Create;
  try
    SplitArgs(rest, args);

    { ---- keys ---- }
    k := KeyForName(nm);
    if k <> kNone then
    begin
      n := 1;
      if (rest <> '') and EvalNum(rest, d) then n := Trunc(d);
      if n < 1 then exit(False);
      key := k;
      FRepeatKey := k;
      FRepeatLeft := n - 1;
      exit(True);
    end;

    if nm = '?' then
    begin
      FWait := wQuestion;
      exit(False);
    end;

    { ---- flow ---- }
    if nm = 'BRANCH' then
    begin
      if (args.Count > 0) and Loc(args[0], r, c) then Jump(r, c, 1) else Stop;
      exit(False);
    end;
    if nm = 'QUIT' then begin Stop; exit(False); end;
    if nm = 'RETURN' then
    begin
      if not PopFrame then Stop;
      exit(False);
    end;
    if nm = 'RESTART' then begin SetLength(FFrames, 0); exit(False); end;
    if nm = 'IF' then
    begin
      if not (Eval(rest, v) and (v.Kind = vkNum) and (v.Num <> 0)) then
      begin
        FPos := Length(FLine) + 1;              { condition false: skip the rest of this cell }
      end;
      exit(False);
    end;
    if (nm = 'FOR') then
    begin
      if (args.Count < 5) or not Loc(args[0], r, c) or not EvalNum(args[1], d) or
         not EvalNum(args[2], d2) or not EvalNum(args[3], d3) or not Loc(args[4], r1, c1) then
      begin
        Stop;
        exit(False);
      end;
      StoreValue(r, c, NumValue(d));
      if ((d3 >= 0) and (d > d2)) or ((d3 < 0) and (d < d2)) then exit(False);
      PushFrame(True, []);
      with FFrames[High(FFrames)] do
      begin
        Counter := NormRange(r, c, r, c);
        Stop := d2;
        Step := d3;
        Routine := NormRange(r1, c1, r1, c1);
      end;
      Jump(r1, c1, 1);
      exit(False);
    end;
    if nm = 'FORBREAK' then
    begin
      while (Length(FFrames) > 0) and not FFrames[High(FFrames)].IsFor do
        SetLength(FFrames, Length(FFrames) - 1);
      if Length(FFrames) > 0 then
      begin
        with FFrames[High(FFrames)] do Jump(Row, Col, Pos);
        SetLength(FFrames, Length(FFrames) - 1);
      end
      else
        Stop;
      exit(False);
    end;
    if nm = 'DEFINE' then
    begin
      if Length(FFrames) > 0 then
        for i := 0 to args.Count - 1 do
        begin
          t := args[i];
          idx := Pos(':', t);
          if idx > 0 then
          begin
            ch := UpCase(t[idx + 1]);
            t := Copy(t, 1, idx - 1);
          end
          else
            ch := 'V';
          if (i <= High(FFrames[High(FFrames)].Args)) and Loc(t, r, c) then
          begin
            if ch = 'S' then
              StoreLabel(r, c, Unquote(FFrames[High(FFrames)].Args[i]))
            else if Eval(FFrames[High(FFrames)].Args[i], v) then
              StoreValue(r, c, v)
            else
              StoreLabel(r, c, Unquote(FFrames[High(FFrames)].Args[i]));
          end;
        end;
      exit(False);
    end;
    if (nm = 'MENUBRANCH') or (nm = 'MENUCALL') then
    begin
      if (args.Count < 1) or not Loc(args[0], r, c) then begin Stop; exit(False); end;
      items := TStringList.Create;
      try
        FS.ChoiceHelp.Clear;
        cols := 0;
        while (c + cols <= MaxCol) and (FS.Sheet.Find(r, c + cols) <> nil) and
              (FS.Sheet.Find(r, c + cols).Raw <> '') do
        begin
          cell := FS.Sheet.Find(r, c + cols);
          if TextOf(cell, ch, t) then items.Add(t) else items.Add('?');
          Inc(cols);
        end;
        if items.Count = 0 then begin Stop; exit(False); end;
        FMenuRow := r;
        FMenuCol := c;
        FMenuCount := items.Count;
        FMenuCall := nm = 'MENUCALL';
        FMenuDone := False;
        FMenuChosen := False;
        FS.AskChoice(['x'], @MenuCallback, '');          { sets up the chooser; items follow }
        FS.NameChoices.Assign(items);
        for i := 0 to items.Count - 1 do
        begin
          cell := FS.Sheet.Find(r + 1, c + i);
          if (cell <> nil) and TextOf(cell, ch, t) then FS.ChoiceHelp.Add(t) else FS.ChoiceHelp.Add('');
        end;
        FWait := wMenu;
      finally
        items.Free;
      end;
      exit(False);
    end;

    { ---- data ---- }
    if nm = 'LET' then
    begin
      if (args.Count < 2) or not Loc(args[0], r, c) then exit(False);
      t := args[1];
      idx := LastDelimiter(':', t);
      ch := 'A';
      if (idx > 0) and (UpperCase(Copy(t, idx + 1, MaxInt)) = 'STRING') then
      begin
        ch := 'S';
        t := Copy(t, 1, idx - 1);
      end
      else if (idx > 0) and (UpperCase(Copy(t, idx + 1, MaxInt)) = 'VALUE') then
      begin
        ch := 'V';
        t := Copy(t, 1, idx - 1);
      end;
      if ch = 'S' then
        StoreLabel(r, c, Unquote(t))
      else if Eval(t, v) then
        StoreValue(r, c, v)
      else
        StoreLabel(r, c, Unquote(t));
      exit(False);
    end;
    if nm = 'PUT' then
    begin
      if (args.Count < 4) or not Loc(args[0], r, c) or not EvalNum(args[1], d) or not EvalNum(args[2], d2) then
        exit(False);
      r1 := r + Trunc(d2);
      c1 := c + Trunc(d);
      if InBounds(r1, c1) and Eval(args[3], v) then StoreValue(r1, c1, v);
      exit(False);
    end;
    if nm = 'BLANK' then
    begin
      if (args.Count > 0) and ParseRangeText(FS.Sheet, args[0], g) then
      begin
        for r := g.R1 to g.R2 do
          for c := g.C1 to g.C2 do
            if FS.Sheet.NonEmpty(r, c) then FS.Sheet.Put(r, c, '');
        Changed;
      end;
      exit(False);
    end;
    if nm = 'CONTENTS' then
    begin
      if (args.Count >= 2) and Loc(args[0], r, c) and Loc(args[1], r1, c1) then
      begin
        cell := FS.Sheet.Find(r1, c1);
        { the width the cell is shown in: the source column's, or the third argument }
        n := FS.Sheet.ColWidth(c1);
        if (args.Count >= 3) and EvalNum(args[2], d) and (d >= 1) and (d <= 240) then n := Trunc(d);
        if cell = nil then t := ''
        else if TextOf(cell, ch, t) then
          { the text itself }
        else
        begin
          { a number as displayed: right-aligned in the width, stars if it does not fit }
          t := ValueText(cell, FS.Sheet, n);
          if Length(t) > n then t := StringOfChar('*', n)
          else t := StringOfChar(' ', n - Length(t)) + t;
        end;
        StoreLabel(r, c, t);
      end;
      exit(False);
    end;
    if (nm = 'RECALC') or (nm = 'RECALCCOL') then
    begin
      FS.Calc.Recalc;
      exit(False);
    end;
    if nm = 'INDICATE' then
    begin
      FS.IndicatorText := UpperCase(Unquote(rest));
      exit(False);
    end;
    if (nm = 'GETLABEL') or (nm = 'GETNUMBER') then
    begin
      if (args.Count < 2) or not Loc(args[1], r, c) then begin Stop; exit(False); end;
      FLoc := NormRange(r, c, r, c);
      FPromptNumber := nm = 'GETNUMBER';
      FPromptDone := False;
      FS.AskText(Unquote(args[0]), '', @PromptCallback, '');
      FWait := wPrompt;
      exit(False);
    end;
    if nm = 'GET' then
    begin
      if (args.Count > 0) and Loc(args[0], r, c) then
      begin
        FLoc := NormRange(r, c, r, c);
        FWait := wGet;
      end;
      exit(False);
    end;
    if nm = 'LOOK' then
    begin
      if (args.Count > 0) and Loc(args[0], r, c) then StoreLabel(r, c, '');
      exit(False);
    end;
    if (nm = 'BEEP') or (nm = 'WAIT') or (nm = 'PANELOFF') or (nm = 'PANELON') or
       (nm = 'WINDOWSOFF') or (nm = 'WINDOWSON') or (nm = 'BREAKOFF') or (nm = 'BREAKON') or
       (nm = 'ONERROR') then
      exit(False);

    { ---- {~} {{} {}} : the character itself ---- }
    if (nm = '~') or (nm = '{') or (nm = '}') then
    begin
      if nm = '~' then key := Ord('~') else key := Ord(nm[1]);
      exit(True);
    end;

    { ---- a subroutine: {name arg, arg} ---- }
    if FS.Sheet.FindName(nm, g) then
    begin
      PushFrame(False, []);
      SetLength(FFrames[High(FFrames)].Args, args.Count);
      for i := 0 to args.Count - 1 do FFrames[High(FFrames)].Args[i] := args[i];
      Jump(g.R1, g.C1, 1);
      exit(False);
    end;
    { unknown command: ends the macro, as an error would }
    FS.Msg := 'Macro command {' + nm + '} is not available';
    Stop;
  finally
    args.Free;
  end;
end;

{ ------------------------------------------------------------------ running }

function TMacro.NextKey(out k: Integer): Boolean;
var
  e, guard, cp, len: Integer;
  cmd: string;
  b: Byte;
begin
  Result := False;
  k := kNone;
  guard := 0;
  while FActive do
  begin
    Inc(guard);
    if guard > 100000 then
    begin
      FS.Msg := 'Macro stopped: it loops without typing anything';
      Stop;
      exit;
    end;
    if FRepeatLeft > 0 then
    begin
      if not StepGate then exit(False);
      Dec(FRepeatLeft);
      k := FRepeatKey;
      exit(True);
    end;
    if FWait <> wNone then
    begin
      if StillWaiting then exit(False);
      case FWait of
        wPrompt: FWait := wNone;
        wMenu:
          begin
            FWait := wNone;
            if not FMenuChosen then begin Stop; exit(False); end;
          end;
      else
        FWait := wNone;
      end;
    end;
    if not FHaveLine then
    begin
      if not LoadLine then
      begin
        { end of this routine, or of the macro }
        if not PopFrame then Stop;
        continue;
      end;
    end;
    if FPos > Length(FLine) then
    begin
      FHaveLine := False;
      Inc(FRow);
      FJumpPos := 1;
      continue;
    end;
    if not StepGate then exit(False);          { one key or command at a time in STEP mode }
    b := Ord(FLine[FPos]);
    if FLine[FPos] = '~' then
    begin
      Inc(FPos);
      k := kEnter;
      exit(True);
    end;
    if FLine[FPos] = '{' then
    begin
      if Copy(FLine, FPos, 3) = '{{}' then begin Inc(FPos, 3); k := Ord('{'); exit(True); end;
      if Copy(FLine, FPos, 3) = '{}}' then begin Inc(FPos, 3); k := Ord('}'); exit(True); end;
      e := FPos + 1;
      while (e <= Length(FLine)) and (FLine[e] <> '}') do Inc(e);
      if e > Length(FLine) then
      begin
        FS.Msg := 'Macro has an unclosed {';
        Stop;
        exit;
      end;
      cmd := Copy(FLine, FPos + 1, e - FPos - 1);
      FPos := e + 1;
      if ExecCommand(cmd, k) then exit(True);
      continue;
    end;
    { an ordinary character: one UTF-8 sequence }
    len := 1;
    if (b and $E0) = $C0 then len := 2
    else if (b and $F0) = $E0 then len := 3
    else if (b and $F8) = $F0 then len := 4;
    if b < $80 then cp := b
    else
    begin
      cp := Ord(UTF8Decode(Copy(FLine, FPos, len))[1]);
    end;
    Inc(FPos, len);
    k := cp;
    exit(True);
  end;
end;

function TMacro.UserKey(k: Integer): Boolean;
var
  s: string;
begin
  Result := False;
  if not FActive then exit;
  if k = kBreak then
  begin
    Stop;
    exit;
  end;
  if FStepWait then
  begin
    FStepWait := False;
    FStepOK := True;
    if k = kAltF1 + 1 then FS.StepOn := False;       { Alt-F2 again: run freely }
    exit(True);                                       { the key only steps; it is not typed }
  end;
  case FWait of
    wQuestion:
      if k = kEnter then
      begin
        FWait := wNone;
        Result := True;                            { the Enter only resumes the macro }
      end;
    wGet:
      begin
        s := KeyMacroText(k);
        StoreLabel(FLoc.R1, FLoc.C1, s);
        FWait := wNone;
        Result := True;                            { used up: not typed into the worksheet }
      end;
  end;
end;

procedure TMacro.PromptFinished;
var
  v: TValue;
  s: string;
begin
  s := FS.PromptStr;
  FPromptDone := True;
  if FPromptNumber then
  begin
    if Eval(s, v) and (v.Kind = vkNum) then StoreValue(FLoc.R1, FLoc.C1, v)
    else StoreValue(FLoc.R1, FLoc.C1, ErrValue);
  end
  else
    StoreLabel(FLoc.R1, FLoc.C1, s);
end;

procedure TMacro.MenuFinished;
var
  i: Integer;
begin
  FMenuDone := True;
  i := FS.ChoiceIndex;
  if (i < 0) or (i >= FMenuCount) then exit;
  FMenuChosen := True;
  if FMenuCall then
  begin
    PushFrame(False, []);
  end;
  Jump(FMenuRow + 2, FMenuCol + i, 1);
end;

procedure TMacro.RunSync(Ctl: TController; maxKeys: Integer);
var
  k, n: Integer;
begin
  n := 0;
  while True do
  begin
    if FS.MacroRequest <> '' then TakeRequest;
    if not Running then exit;
    if not NextKey(k) then exit;
    Ctl.HandleKey(k);
    Inc(n);
    if n > maxKeys then
    begin
      Stop;
      exit;
    end;
  end;
end;

end.
