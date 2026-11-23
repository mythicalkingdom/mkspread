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

{ Key handling: turns logical keys into changes to the session. }
unit controller;
{$mode objfpc}{$H+}

interface

uses session, commands, sheet;

type
  TController = class
  private
    FS: TSession;
    FCmds: TCommands;
    FEnd: Boolean;                 { END was active when this key arrived }
    procedure MoveCur(dr, dc: Integer);
    procedure EndJump(dr, dc: Integer);
    procedure BigRight;
    procedure BigLeft;
    function NavKey(k: Integer): Boolean;
    procedure Ready(k: Integer);
    procedure EntryKey(k: Integer);
    procedure EditKey(k: Integer);
    procedure GotoKey(k: Integer);
    function EditText(k: Integer): Boolean;
    procedure TextPromptKey(k: Integer);
    procedure NamesKey(k: Integer);
    procedure FindKey(k: Integer);
    procedure HelpKey(k: Integer);
    procedure ToggleAbsolute;
    function CanPoint: Boolean;
    procedure StartFormPoint(k: Integer);
    procedure EndFormPoint(keepText: Boolean);
    procedure RefreshFormPoint;
    procedure FormPointKey(k: Integer);
    procedure OpenHelp;
    procedure ShowTopic(const id: string; remember: Boolean);
    procedure PromptKey(k: Integer);
    procedure PointKey(k: Integer);
    procedure MenuKey(k: Integer);
    procedure Reopen(const path: string);
    function CommitText(const text: string): Boolean;
    procedure StartEdit;
    procedure SelectItem(i: Integer);
    procedure StubKey(const name: string);
    procedure RestorePromptPreview;
    procedure PointFinish(accept: Boolean);
  public
    constructor Create(S: TSession; Cmds: TCommands);
    procedure HandleKey(k: Integer);
    { a key typed by the user: recorded in LEARN mode, then handled }
    procedure HandleUserKey(k: Integer);
  end;

implementation

uses keys, cellfmt, formula, menutree, u8edit, cmdfile, cmddata, cmdprint, cmddefault, helpdata, refedit, Classes, Math, SysUtils;

{ Alt-F3 picked a range name: start it as a macro }
procedure RunNameChosen(S: TSession; const path: string);
begin
  S.MacroRequest := S.NameChoices[S.ChoiceIndex];
end;

constructor TController.Create(S: TSession; Cmds: TCommands);
begin
  inherited Create;
  FS := S;
  FCmds := Cmds;
end;

procedure TController.StubKey(const name: string);
begin
  FS.Msg := '[stub] ' + name + ' not implemented';
end;

{ ---------------------------------------------------------------- movement }

procedure TController.MoveCur(dr, dc: Integer);
begin
  Inc(FS.CurRow, dr);
  Inc(FS.CurCol, dc);
  FS.Normalize;
end;

procedure TController.EndJump(dr, dc: Integer);
var
  r, c: Integer;
  sh: TSheet;
begin
  sh := FS.Sheet;
  r := FS.CurRow;
  c := FS.CurCol;
  if InBounds(r + dr, c + dc) and sh.NonEmpty(r, c) and sh.NonEmpty(r + dr, c + dc) then
  begin
    while InBounds(r + dr, c + dc) and sh.NonEmpty(r + dr, c + dc) do
    begin
      Inc(r, dr);
      Inc(c, dc);
    end;
  end
  else
  begin
    while InBounds(r + dr, c + dc) do
    begin
      Inc(r, dr);
      Inc(c, dc);
      if sh.NonEmpty(r, c) then break;
    end;
  end;
  FS.CurRow := r;
  FS.CurCol := c;
  FS.Normalize;
end;

procedure TController.BigRight;
var
  rc, off: Integer;
begin
  rc := FS.RightColOf(FS.LeftCol);
  if rc >= MaxCol then exit;
  off := FS.CurCol - FS.LeftCol;
  FS.LeftCol := rc + 1;
  FS.CurCol := FS.LeftCol + off;
  if FS.CurCol > FS.RightColOf(FS.LeftCol) then FS.CurCol := FS.RightColOf(FS.LeftCol);
  FS.Normalize;
end;

procedure TController.BigLeft;
var
  nl, w, off: Integer;
begin
  if FS.LeftCol <= 1 then
  begin
    FS.CurCol := 1;
    exit;
  end;
  nl := FS.LeftCol;
  w := 0;
  while (nl > 1) and (w + FS.Sheet.ColWidth(nl - 1) <= FS.ScrollW) do
  begin
    Dec(nl);
    Inc(w, FS.Sheet.ColWidth(nl));
  end;
  if nl = FS.LeftCol then Dec(nl);
  off := FS.CurCol - FS.LeftCol;
  FS.LeftCol := nl;
  FS.CurCol := nl + off;
  if FS.CurCol > FS.RightColOf(nl) then FS.CurCol := FS.RightColOf(nl);
  FS.Normalize;
end;

{ Cursor movement shared by READY and POINT modes.  True if k was one. }
function TController.NavKey(k: Integer): Boolean;
var
  mr, mc: Integer;
begin
  Result := True;
  case k of
    kEnd: FS.EndMode := not FS.EndMode;
    kUp:    if FEnd then EndJump(-1, 0) else MoveCur(-1, 0);
    kDown:  if FEnd then EndJump(1, 0) else MoveCur(1, 0);
    kLeft:  if FEnd then EndJump(0, -1) else MoveCur(0, -1);
    kRight: if FEnd then EndJump(0, 1) else MoveCur(0, 1);
    kHome:
      if FEnd then
      begin
        FS.Sheet.UsedExtent(mr, mc);
        FS.CurRow := mr;
        FS.CurCol := mc;
        FS.Normalize;
      end
      else
      begin
        FS.CurCol := 1; FS.CurRow := 1; FS.LeftCol := 1; FS.TopRow := 1;
      end;
    kCtrlHome:
      begin
        FS.CurCol := 1; FS.CurRow := 1; FS.LeftCol := 1; FS.TopRow := 1;
      end;
    kPgUp:
      begin
        Dec(FS.CurRow, FS.ScrollRows);
        Dec(FS.TopRow, FS.ScrollRows);
        if FS.CurRow < 1 then FS.CurRow := 1;
        if FS.TopRow < 1 then FS.TopRow := 1;
        FS.Normalize;
      end;
    kPgDn:
      begin
        Inc(FS.CurRow, FS.ScrollRows);
        Inc(FS.TopRow, FS.ScrollRows);
        FS.Normalize;
      end;
    kTab, kCtrlRight, kCtrlPgDn: BigRight;
    kShiftTab, kCtrlLeft, kCtrlPgUp: BigLeft;
  else
    Result := False;
  end;
end;

{ ---------------------------------------------------------------- READY }

procedure TController.StartEdit;
var
  cell: TCell;
begin
  cell := FS.Sheet.Find(FS.CurRow, FS.CurCol);
  if (cell <> nil) then FS.Entry := cell.Raw else FS.Entry := '';
  FS.EditPos := U8Len(FS.Entry);
  FS.Mode := mEdit;
end;

procedure TController.Ready(k: Integer);
var
  g: TRange;
begin
  if (k = Ord('/')) or (k = Ord('<')) then
  begin
    FS.OpenMenu;
    exit;
  end;
  if NavKey(k) then exit;
  case k of
    kF1 + 1: StartEdit;
    kF1 + 2: StubKey('F3 (NAME)');
    kF1 + 3: ;                                  { F4 only means something while typing }
    kF1 + 4:
      begin
        FS.Mode := mGoto;
        FS.Entry := '';
      end;
    kF1 + 5: FS.WindowSwitch;
    kF1 + 6: StubKey('F7 (QUERY)');
    kF1 + 7: RunLastTable(FS);
    kF1 + 8: FS.Calc.Recalc;
    kF1 + 9: StubKey('F10 (GRAPH)');
    kAltF1: StubKey('Alt-F1 (COMPOSE)');
    kAltF1 + 2:
      if FS.OpenNameList then FS.ChoiceCont := @RunNameChosen;     { Alt-F3: run a macro }
    kAltF1 + 3: FS.DoUndo;
    kBreak, kEsc, kBackspace: ;
    32..126, 128..kSpecialBase - 1:
      begin
        if (k < 127) and (Chr(k) in ValueStarts) then
          FS.Mode := mValue
        else
          FS.Mode := mLabel;
        FS.Entry := UTF8Encode(WideChar(k));
      end;
  else
    if IsAltLetter(k) then
    begin
      if FS.Sheet.FindName('\' + AltLetter(k), g) then FS.MacroRequest := '\' + UpCase(AltLetter(k))
      else FS.Msg := 'No macro \' + UpCase(AltLetter(k)) + ' is defined';
    end;
  end;
end;

{ ---------------------------------------------------------------- entry / edit }

{ Store text typed into the current cell.  First character decides: a label
  prefix keeps it a label, a number-ish start makes it a number or formula,
  anything else is a label with the worksheet's default prefix.  A formula
  that does not parse puts the text into EDIT mode with the cursor at the
  problem and returns False (nothing is stored). }
function TController.CommitText(const text: string): Boolean;
var
  raw: string;
  d: Double;
  f: TFormula;
  errPos: Integer;
begin
  Result := True;
  FS.Mode := mReady;
  if text = '' then exit;
  raw := text;
  if raw[1] in LabelPrefixes then
    { label as typed }
  else if raw[1] in ValueStarts then
  begin
    if IsNumberLiteral(raw, d) then
      raw := NumToRaw(d)
    else if CompileFormula(raw, f, errPos) then
    begin
      raw := f.Text;
      f.Free;
    end
    else
    begin
      FS.Entry := text;
      FS.EditPos := U8Len(Copy(text, 1, errPos - 1));
      FS.Mode := mEdit;
      FS.Msg := 'Invalid formula';
      exit(False);
    end;
  end
  else
    raw := FS.Sheet.GlobalLabelPrefix + raw;
  FS.SaveUndo;
  FS.Sheet.Put(FS.CurRow, FS.CurCol, raw);
end;

procedure TController.EntryKey(k: Integer);
var
  shown: string;
begin
  case k of
    kEnter: CommitText(FS.Entry);
    kEsc, kBreak:
      begin
        FS.Mode := mReady;
        FS.Entry := '';
      end;
    kBackspace: begin
      FS.EditPos := U8Len(FS.Entry);
      if FS.EditPos > 0 then U8DeleteAt(FS.Entry, FS.EditPos - 1);
    end;
    kF1 + 1:
      begin
        { F2: continue the entry in EDIT mode, with the label prefix visible }
        shown := FS.Entry;
        if (FS.Mode = mLabel) and not (shown[1] in LabelPrefixes) then
          shown := FS.Sheet.GlobalLabelPrefix + shown;
        FS.Entry := shown;
        FS.EditPos := U8Len(shown);
        FS.Mode := mEdit;
      end;
    kUp:    if CommitText(FS.Entry) then MoveCur(-1, 0);
    kDown:  if CommitText(FS.Entry) then MoveCur(1, 0);
    kLeft:  if CommitText(FS.Entry) then MoveCur(0, -1);
    kRight: if CommitText(FS.Entry) then MoveCur(0, 1);
    kPgUp, kPgDn, kHome, kTab, kShiftTab, kCtrlLeft, kCtrlRight:
      if CommitText(FS.Entry) then NavKey(k);
    32..126, 128..kSpecialBase - 1:
      if Length(FS.Entry) < 240 then FS.Entry := FS.Entry + UTF8Encode(WideChar(k));
  end;
end;

{ Cursor movement and typing inside FS.Entry (EDIT mode and text prompts). }
function TController.EditText(k: Integer): Boolean;
begin
  Result := True;
  case k of
    kLeft: if FS.EditPos > 0 then Dec(FS.EditPos);
    kRight: if FS.EditPos < U8Len(FS.Entry) then Inc(FS.EditPos);
    kHome: FS.EditPos := 0;
    kEnd: FS.EditPos := U8Len(FS.Entry);
    kBackspace:
      if FS.EditPos > 0 then
      begin
        U8DeleteAt(FS.Entry, FS.EditPos - 1);
        Dec(FS.EditPos);
      end;
    kDel: U8DeleteAt(FS.Entry, FS.EditPos);
    32..126, 128..kSpecialBase - 1:
      if Length(FS.Entry) < 240 then
      begin
        U8Insert(FS.Entry, FS.EditPos, UTF8Encode(WideChar(k)));
        Inc(FS.EditPos);
      end;
  else
    Result := False;
  end;
end;

procedure TController.EditKey(k: Integer);
begin
  if EditText(k) then exit;
  case k of
    kEnter: CommitText(FS.Entry);
    kEsc, kBreak:
      begin
        FS.Mode := mReady;
        FS.Entry := '';
      end;
    kUp:   if CommitText(FS.Entry) then MoveCur(-1, 0);
    kDown: if CommitText(FS.Entry) then MoveCur(1, 0);
  end;
end;

procedure TController.TextPromptKey(k: Integer);
begin
  if FS.PromptFresh then
  begin
    FS.PromptFresh := False;
    if (k >= 32) and (k < kSpecialBase) and (k <> 127) then
    begin
      FS.Entry := '';
      FS.EditPos := 0;
    end;
  end;
  if EditText(k) then exit;
  case k of
    kEnter:
      begin
        FS.PromptStr := Trim(FS.Entry);
        FS.Mode := mReady;
        FS.PromptCont(FS, FS.PromptPath);
      end;
    kEsc, kBreak: FS.Mode := mReady;
    kF1 + 2:
      if FS.PromptFilter <> '' then OpenFileChoices(FS, FS.PromptFilter)
      else FS.OpenNameList;
  end;
end;

{ F4 (ABS) while typing or editing a formula }
procedure TController.ToggleAbsolute;
var
  pos: Integer;
begin
  if (FS.Mode = mPoint) and not FS.Typing then exit;
  if FS.Mode = mEdit then pos := FS.EditPos else pos := U8Len(FS.Entry);
  if CycleAbsolute(FS.Entry, pos) then
  begin
    if FS.Mode = mEdit then FS.EditPos := pos;
    if FS.FPActive then FS.FPLen := U8Len(FS.Entry) - FS.FPStart;
  end;
end;

{ ---- pointing at cells while typing a formula ---- }

{ true when the text ends where a cell reference could start (after an operator,
  an opening parenthesis or a comma) }
function TController.CanPoint: Boolean;
var
  n: Integer;
begin
  Result := False;
  if FS.Mode <> mValue then exit;
  n := Length(FS.Entry);
  if n = 0 then exit;
  Result := FS.Entry[n] in ['+', '-', '*', '/', '^', '(', ',', '&', '<', '>', '=', '#'];
end;

procedure TController.RefreshFormPoint;
var
  r: TRange;
  t: string;
begin
  r := FS.Selection;
  t := ColLetter(r.C1) + IntToStr(r.R1);
  if (r.R1 <> r.R2) or (r.C1 <> r.C2) then t := t + '..' + ColLetter(r.C2) + IntToStr(r.R2);
  FS.Entry := U8Copy(FS.Entry, 1, FS.FPStart) + t;
  FS.FPLen := Length(t);
end;

procedure TController.StartFormPoint(k: Integer);
begin
  FS.FPActive := True;
  FS.FPStart := U8Len(FS.Entry);
  FS.OrigRow := FS.CurRow; FS.OrigCol := FS.CurCol;
  FS.OrigTop := FS.TopRow; FS.OrigLeft := FS.LeftCol;
  FS.Anchored := False;
  NavKey(k);
  RefreshFormPoint;
end;

procedure TController.EndFormPoint(keepText: Boolean);
begin
  if not keepText then FS.Entry := U8Copy(FS.Entry, 1, FS.FPStart);
  FS.CurRow := FS.OrigRow; FS.CurCol := FS.OrigCol;
  FS.TopRow := FS.OrigTop; FS.LeftCol := FS.OrigLeft;
  FS.Anchored := False;
  FS.FPActive := False;
  FS.Normalize;
end;

procedure TController.FormPointKey(k: Integer);
begin
  case k of
    kEsc, kBackspace:
      if FS.Anchored then
      begin
        FS.Anchored := False;
        RefreshFormPoint;
      end
      else
        EndFormPoint(False);
    kBreak:
      begin
        EndFormPoint(False);
        EntryKey(k);
      end;
    Ord('.'):
      begin
        if not FS.Anchored then
        begin
          FS.Anchored := True;
          FS.AnchorR := FS.CurRow;
          FS.AnchorC := FS.CurCol;
        end;
        RefreshFormPoint;
      end;
  else
    if NavKey(k) then RefreshFormPoint
    else
    begin
      { anything else ends the pointing and is typed as usual }
      EndFormPoint(True);
      EntryKey(k);
    end;
  end;
end;

{ ---------------------------------------------------------------- help }

procedure TController.ShowTopic(const id: string; remember: Boolean);
begin
  if HelpIndexOf(id) < 0 then exit;
  if remember and (FS.HelpId <> '') then FS.HelpBack.Add(FS.HelpId);
  FS.HelpId := id;
  FS.HelpScroll := 0;
  FS.HelpSel := 0;
end;

{ F1: the topic that fits what is on the screen }
procedure TController.OpenHelp;
var
  id: string;
begin
  case FS.Mode of
    mLabel, mValue: id := 'entry';
    mEdit, mPrompt: id := 'editing';
    mMenu: id := HelpForMenu(FS.MenuPath(FS.MenuDepth));
    mGoto, mPoint, mNames: id := 'ranges';
    mFind: id := 'm:data query';
  else
    id := 'basics';
  end;
  FS.HelpReturn := FS.Mode;
  FS.HelpBack.Clear;
  FS.HelpId := '';
  FS.Mode := mHelp;
  ShowTopic(id, False);
end;

procedure TController.HelpKey(k: Integer);
var
  rel: TStringList;
  n, i, page: Integer;
  isIndex: Boolean;
begin
  rel := TStringList.Create;
  try
    rel.Delimiter := ',';
    rel.StrictDelimiter := True;
    i := HelpIndexOf(FS.HelpId);
    rel.DelimitedText := HelpRelated(i);
    isIndex := FS.HelpId = 'index';
    n := 1;
    for i := 1 to Length(HelpBody(HelpIndexOf(FS.HelpId))) do
      if HelpBody(HelpIndexOf(FS.HelpId))[i] = #10 then Inc(n);
    page := FS.GridRows;
    if page < 5 then page := 5;
    case k of
      kEsc, kBreak: FS.Mode := FS.HelpReturn;
      kF1: if not isIndex then ShowTopic('index', True);
      kBackspace:
        if FS.HelpBack.Count = 0 then FS.Mode := FS.HelpReturn
        else
        begin
          FS.HelpId := FS.HelpBack[FS.HelpBack.Count - 1];
          FS.HelpBack.Delete(FS.HelpBack.Count - 1);
          FS.HelpScroll := 0;
          FS.HelpSel := 0;
        end;
      kEnter:
        if (FS.HelpSel >= 0) and (FS.HelpSel < rel.Count) then ShowTopic(rel[FS.HelpSel], True);
      kDown, kRight, kTab:
        if isIndex or (k <> kDown) then
        begin
          if FS.HelpSel < rel.Count - 1 then Inc(FS.HelpSel);
        end
        else if FS.HelpScroll < n - 1 then Inc(FS.HelpScroll);
      kUp, kLeft, kShiftTab:
        if isIndex or (k <> kUp) then
        begin
          if FS.HelpSel > 0 then Dec(FS.HelpSel);
        end
        else if FS.HelpScroll > 0 then Dec(FS.HelpScroll);
      kPgDn:
        if isIndex then FS.HelpSel := Min(FS.HelpSel + page, rel.Count - 1)
        else FS.HelpScroll := Min(FS.HelpScroll + page, n - 1);
      kPgUp:
        if isIndex then FS.HelpSel := Max(FS.HelpSel - page, 0)
        else FS.HelpScroll := Max(FS.HelpScroll - page, 0);
      kHome:
        begin
          FS.HelpScroll := 0;
          FS.HelpSel := 0;
        end;
    end;
  finally
    rel.Free;
  end;
end;

{ /Data Query Find: step through the matching records }
procedure TController.FindKey(k: Integer);
var
  n: Integer;
begin
  n := FS.FindRows.Count;
  case k of
    kDown, kRight, 32: if FS.FindIdx < n - 1 then Inc(FS.FindIdx);
    kUp, kLeft: if FS.FindIdx > 0 then Dec(FS.FindIdx);
    kHome: FS.FindIdx := 0;
    kEnd: FS.FindIdx := n - 1;
    kEnter, kEsc, kBreak:
      begin
        FS.CurRow := FS.OrigRow;
        FS.CurCol := FS.OrigCol;
        FS.TopRow := FS.OrigTop;
        FS.LeftCol := FS.OrigLeft;
        FS.Mode := mReady;
        exit;
      end;
  end;
  FS.CurRow := PtrInt(FS.FindRows[FS.FindIdx]);
  FS.CurCol := FS.Data.QIn.C1;
  FS.Normalize;
end;

procedure TController.NamesKey(k: Integer);
var
  n, name: string;
  i: Integer;
begin
  n := '';
  case k of
    kRight, 32: FS.NameIdx := (FS.NameIdx + 1) mod FS.NameChoices.Count;
    kLeft: FS.NameIdx := (FS.NameIdx + FS.NameChoices.Count - 1) mod FS.NameChoices.Count;
    kHome: FS.NameIdx := 0;
    kEnd: FS.NameIdx := FS.NameChoices.Count - 1;
    kEsc, kBreak: FS.Mode := FS.NameReturn;
    33..126:
      if (FS.NameReturn = mPrompt) and (FS.PromptFilter <> '') then
      begin
        { choosing a file and then typing a name: back to the prompt, the key is typed there }
        FS.Mode := mPrompt;
        TextPromptKey(k);
      end
      else
      { menu-style choices (not range names) are picked by their first letter }
      if not FS.ChoiceIsName then
        for i := 0 to FS.NameChoices.Count - 1 do
          if (FS.NameChoices[i] <> '') and (UpCase(FS.NameChoices[i][1]) = UpCase(Chr(k))) then
          begin
            FS.NameIdx := i;
            NamesKey(kEnter);
            break;
          end;
    kEnter:
      begin
        name := FS.NameChoices[FS.NameIdx];
        if Assigned(FS.ChoiceCont) then
        begin
          FS.Mode := mReady;
          FS.ChoiceIndex := FS.NameIdx;
          FS.ChoiceCont(FS, FS.ChoicePath);
          exit;
        end;
        FS.Mode := FS.NameReturn;
        if (FS.Mode = mPrompt) and (FS.PromptFilter <> '') and (name <> '') and (name[Length(name)] = '/') then
        begin
          { a directory: go into it and list its files }
          SetCurrentDir(Copy(name, 1, Length(name) - 1));
          OpenFileChoices(FS, FS.PromptFilter, True);
          exit;
        end;
        if (FS.Mode = mPrompt) and (FS.PromptFilter <> '') then
        begin
          { a file: the same as typing its name and pressing Enter }
          FS.Entry := name;
          TextPromptKey(kEnter);
          exit;
        end;
        if FS.Mode = mPoint then
        begin
          FS.Typing := True;
          FS.Entry := name;
          PointFinish(True);
        end
        else
        begin
          FS.Entry := name;
          FS.EditPos := U8Len(name);
        end;
      end;
  end;
end;

procedure TController.GotoKey(k: Integer);
var
  c, r: Integer;
begin
  case k of
    kEnter:
      begin
        if ParseAddr(FS.Entry, c, r) then
        begin
          FS.CurCol := c;
          FS.CurRow := r;
          FS.Normalize;
        end
        else
          FS.Msg := 'Invalid cell or range address';
        FS.Mode := mReady;
      end;
    kEsc, kBreak: FS.Mode := mReady;
    kBackspace: if FS.Entry <> '' then Delete(FS.Entry, Length(FS.Entry), 1);
    32..126: if Length(FS.Entry) < 12 then FS.Entry := FS.Entry + Chr(k);
  end;
end;

{ ---------------------------------------------------------------- prompts }

procedure TController.RestorePromptPreview;
begin
  case FS.PromptLive of
    plColumn: FS.Sheet.SetColWidth(FS.CurCol, FS.PromptOrigWidth);
    plGlobalWidth: FS.Sheet.GlobalWidth := FS.PromptOrigWidth;
  end;
end;

procedure TController.PromptKey(k: Integer);
var
  n: Integer;
begin
  if FS.PromptIsText then
  begin
    TextPromptKey(k);
    exit;
  end;
  if FS.PromptFresh then
  begin
    { the first digit replaces the number offered; Backspace clears it }
    FS.PromptFresh := False;
    if ((k >= Ord('0')) and (k <= Ord('9'))) or (k = kBackspace) then
    begin
      FS.Entry := '';
      if k = kBackspace then exit;
    end;
  end;
  case k of
    kEnter:
      begin
        n := StrToIntDef(FS.Entry, -1);
        if (n < FS.PromptMin) or (n > FS.PromptMax) then
        begin
          FS.Msg := Format('Value must be between %d and %d', [FS.PromptMin, FS.PromptMax]);
          exit;
        end;
        FS.PromptNum := n;
        RestorePromptPreview;
        FS.Mode := mReady;
        FS.PromptCont(FS, FS.PromptPath);
      end;
    kEsc, kBreak:
      begin
        RestorePromptPreview;
        FS.Mode := mReady;
      end;
    kBackspace: if FS.Entry <> '' then Delete(FS.Entry, Length(FS.Entry), 1);
    kLeft, kRight:
      if FS.PromptLive <> plNone then
      begin
        n := StrToIntDef(FS.Entry, FS.PromptMin);
        if k = kLeft then Dec(n) else Inc(n);
        if n < FS.PromptMin then n := FS.PromptMin;
        if n > FS.PromptMax then n := FS.PromptMax;
        FS.Entry := IntToStr(n);
        case FS.PromptLive of
          plColumn: FS.Sheet.SetColWidth(FS.CurCol, n);
          plGlobalWidth: FS.Sheet.GlobalWidth := n;
        end;
      end;
    Ord('0')..Ord('9'):
      if Length(FS.Entry) < 4 then FS.Entry := FS.Entry + Chr(k);
  end;
end;

procedure TController.PointFinish(accept: Boolean);
var
  r: TRange;
  ok: Boolean;
begin
  if FS.Typing then
    ok := ParseRangeText(FS.Sheet, FS.Entry, r)
  else
  begin
    r := FS.Selection;
    ok := True;
  end;
  if accept and not ok then
  begin
    FS.Msg := 'Invalid cell or range address';
    exit;
  end;
  FS.CurRow := FS.OrigRow;
  FS.CurCol := FS.OrigCol;
  FS.TopRow := FS.OrigTop;
  FS.LeftCol := FS.OrigLeft;
  FS.Mode := mReady;
  FS.Anchored := False;
  FS.Typing := False;
  if accept then
  begin
    FS.Range := r;
    FS.PointCont(FS, FS.PointPath);
  end;
end;

procedure TController.PointKey(k: Integer);
begin
  if k = kF1 + 2 then
  begin
    FS.OpenNameList;
    exit;
  end;
  if FS.Typing then
  begin
    case k of
      kEnter: PointFinish(True);
      kEsc, kBreak: begin FS.Typing := False; FS.Entry := ''; end;
      kBackspace:
        begin
          if FS.Entry <> '' then Delete(FS.Entry, Length(FS.Entry), 1);
          if FS.Entry = '' then FS.Typing := False;
        end;
      32..126: if Length(FS.Entry) < 24 then FS.Entry := FS.Entry + Chr(k);
    end;
    exit;
  end;
  if NavKey(k) then exit;
  case k of
    kEnter: PointFinish(True);
    Ord('.'):
      if not FS.Anchored then
      begin
        FS.Anchored := True;
        FS.AnchorR := FS.CurRow;
        FS.AnchorC := FS.CurCol;
      end
      else
      begin
        { period again: move the pointer to the opposite corner }
        FS.Normalize;
        k := FS.AnchorR; FS.AnchorR := FS.CurRow; FS.CurRow := k;
        FS.Normalize;
      end;
    kEsc:
      if FS.Anchored then FS.Anchored := False else PointFinish(False);
    kBackspace:
      if FS.Anchored then FS.Anchored := False else PointFinish(False);
    kBreak: PointFinish(False);
    Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'):
      begin
        FS.Typing := True;
        FS.Entry := Chr(k);
      end;
  end;
end;

{ ---------------------------------------------------------------- menus }

procedure TController.SelectItem(i: Integer);
var
  d, p: Integer;
  path: string;
  kid: TMenuNode;
begin
  d := FS.MenuDepth;
  FS.MenuIdx[d] := i;
  kid := FS.MenuNodes[d][i];
  path := FS.MenuPath(d);
  if (not kid.IsLeaf) and ((path = 'Print Printer') or (path = 'Print File') or
     (path = 'Worksheet Global Default Other International Currency')) then
  begin
    { choosing the destination runs a command (file name prompt), then the menu opens }
    FS.Mode := mReady;
    if Pos('Print', path) = 1 then FS.ReturnPath := PrintReturnPath(path)
    else FS.ReturnPath := DefaultReturnPath(path);
    FCmds.Run(path, FS);
    exit;
  end;
  if not kid.IsLeaf then
  begin
    Inc(FS.MenuDepth);
    FS.MenuNodes[FS.MenuDepth] := kid;
    FS.MenuIdx[FS.MenuDepth] := 0;
    exit;
  end;
  FS.Mode := mReady;
  FS.ReturnPath := '';
  if Pos('Print ', path) = 1 then FS.ReturnPath := PrintReturnPath(path)
  else if Pos('Worksheet Global Default ', path) = 1 then FS.ReturnPath := DefaultReturnPath(path);
  if (Pos('Data Sort ', path) = 1) or (Pos('Data Query ', path) = 1) or
     (Pos('Data Regression ', path) = 1) or (Pos('Data Parse ', path) = 1) then
    if not path.EndsWith(' Quit') and (path <> 'Data Sort Go') and (path <> 'Data Regression Go') and (path <> 'Data Parse Go') then
    begin
      p := Pos(' ', Copy(path, 6, MaxInt));
      FS.ReturnPath := Copy(path, 1, 5 + p - 1);
    end;
  FCmds.Run(path, FS);
end;

{ opens the menu again at a submenu such as "Data Sort" }
procedure TController.Reopen(const path: string);
var
  rest, nm: string;
  p, i, d: Integer;
begin
  FS.OpenMenu;
  rest := path;
  while rest <> '' do
  begin
    p := Pos(' ', rest);
    if p = 0 then begin nm := rest; rest := ''; end
    else begin nm := Copy(rest, 1, p - 1); rest := Copy(rest, p + 1, MaxInt); end;
    d := FS.MenuDepth;
    i := FS.MenuNodes[d].FindByInitial(nm[1]);
    if (i < 0) or (FS.MenuNodes[d][i].Name <> nm) then
    begin
      for i := 0 to FS.MenuNodes[d].Count - 1 do
        if FS.MenuNodes[d][i].Name = nm then break;
      if i >= FS.MenuNodes[d].Count then exit;
    end;
    FS.MenuIdx[d] := i;
    Inc(FS.MenuDepth);
    FS.MenuNodes[FS.MenuDepth] := FS.MenuNodes[d][i];
    FS.MenuIdx[FS.MenuDepth] := 0;
  end;
end;

procedure TController.MenuKey(k: Integer);
var
  d, n, i: Integer;
begin
  d := FS.MenuDepth;
  n := FS.MenuNodes[d].Count;
  case k of
    kRight, 32: FS.MenuIdx[d] := (FS.MenuIdx[d] + 1) mod n;
    kLeft: FS.MenuIdx[d] := (FS.MenuIdx[d] + n - 1) mod n;
    kHome: FS.MenuIdx[d] := 0;
    kEnd: FS.MenuIdx[d] := n - 1;
    kEnter: SelectItem(FS.MenuIdx[d]);
    kEsc, kBackspace:
      if d = 0 then FS.Mode := mReady else Dec(FS.MenuDepth);
    kBreak: FS.Mode := mReady;
    33..126:
      begin
        i := FS.MenuNodes[d].FindByInitial(Chr(k));
        if i >= 0 then SelectItem(i);
      end;
  end;
end;

procedure TController.HandleUserKey(k: Integer);
begin
  if k <> kNone then FS.LearnKey(k);
  HandleKey(k);
end;

procedure TController.HandleKey(k: Integer);
begin
  if k = kNone then exit;
  { STEP (Alt-F2) and LEARN (Alt-F5) switch on and off whatever the mode }
  if k = kAltF1 + 1 then begin FS.StepOn := not FS.StepOn; exit; end;
  if k = kAltF1 + 4 then begin FS.Msg := ''; FS.ToggleLearn; exit; end;
  if (k = kF1) and (FS.Mode <> mHelp) then begin FS.Msg := ''; OpenHelp; exit; end;
  if FS.FPActive and (FS.Mode = mValue) and (k <> kF1) and (k <> kF1 + 3) then
  begin
    FS.Msg := '';
    FEnd := FS.EndMode;
    if k <> kEnd then FS.EndMode := False;
    FormPointKey(k);
    FS.EndChange;
    exit;
  end;
  if (FS.Mode = mValue) and not FS.FPActive and CanPoint and
     ((k = kUp) or (k = kDown) or (k = kLeft) or (k = kRight) or (k = kPgUp) or (k = kPgDn) or
      (k = kCtrlLeft) or (k = kCtrlRight) or (k = kTab) or (k = kShiftTab)) then
  begin
    FS.Msg := '';
    FEnd := False;
    StartFormPoint(k);
    FS.EndChange;
    exit;
  end;
  if (k = kF1 + 3) and (FS.Mode in [mValue, mEdit, mPoint]) then
  begin
    FS.Msg := '';
    ToggleAbsolute;
    exit;
  end;
  FS.Msg := '';
  FEnd := FS.EndMode;
  if k <> kEnd then FS.EndMode := False;
  case FS.Mode of
    mReady: Ready(k);
    mLabel, mValue: EntryKey(k);
    mEdit: EditKey(k);
    mMenu: MenuKey(k);
    mGoto: GotoKey(k);
    mPrompt: PromptKey(k);
    mPoint: PointKey(k);
    mNames: NamesKey(k);
    mFind: FindKey(k);
    mHelp: HelpKey(k);
  end;
  if (FS.Mode = mReady) and (FS.ReturnPath <> '') then
  begin
    Reopen(FS.ReturnPath);
    FS.ReturnPath := '';
  end;
  if (FS.Mode = mReady) and (FS.Print.Pending <> '') then FlushPrint(FS);
  FS.SyncWindows;
  FS.EndChange;
end;

end.
