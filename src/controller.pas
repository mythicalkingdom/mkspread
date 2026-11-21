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
    procedure PromptKey(k: Integer);
    procedure PointKey(k: Integer);
    procedure MenuKey(k: Integer);
    function CommitText(const text: string): Boolean;
    procedure StartEdit;
    procedure SelectItem(i: Integer);
    procedure StubKey(const name: string);
    procedure RestorePromptPreview;
    procedure PointFinish(accept: Boolean);
  public
    constructor Create(S: TSession; Cmds: TCommands);
    procedure HandleKey(k: Integer);
  end;

implementation

uses keys, cellfmt, formula, menutree, u8edit, cmdfile, SysUtils;

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
begin
  if (k = Ord('/')) or (k = Ord('<')) then
  begin
    FS.OpenMenu;
    exit;
  end;
  if NavKey(k) then exit;
  case k of
    kF1: StubKey('F1 (HELP)');
    kF1 + 1: StartEdit;
    kF1 + 2: StubKey('F3 (NAME)');
    kF1 + 3: StubKey('F4 (ABS)');
    kF1 + 4:
      begin
        FS.Mode := mGoto;
        FS.Entry := '';
      end;
    kF1 + 5: StubKey('F6 (WINDOW)');
    kF1 + 6: StubKey('F7 (QUERY)');
    kF1 + 7: StubKey('F8 (TABLE)');
    kF1 + 8: FS.Calc.Recalc;
    kF1 + 9: StubKey('F10 (GRAPH)');
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
    if IsAltLetter(k) then StubKey('Alt-' + AltLetter(k) + ' (macro)');
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

procedure TController.NamesKey(k: Integer);
var
  n, name: string;
begin
  n := '';
  case k of
    kRight, 32: FS.NameIdx := (FS.NameIdx + 1) mod FS.NameChoices.Count;
    kLeft: FS.NameIdx := (FS.NameIdx + FS.NameChoices.Count - 1) mod FS.NameChoices.Count;
    kHome: FS.NameIdx := 0;
    kEnd: FS.NameIdx := FS.NameChoices.Count - 1;
    kEsc, kBreak: FS.Mode := FS.NameReturn;
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
  d: Integer;
  kid: TMenuNode;
begin
  d := FS.MenuDepth;
  FS.MenuIdx[d] := i;
  kid := FS.MenuNodes[d][i];
  if not kid.IsLeaf then
  begin
    Inc(FS.MenuDepth);
    FS.MenuNodes[FS.MenuDepth] := kid;
    FS.MenuIdx[FS.MenuDepth] := 0;
    exit;
  end;
  FS.Mode := mReady;
  FCmds.Run(FS.MenuPath(d), FS);
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

procedure TController.HandleKey(k: Integer);
begin
  if k = kNone then exit;
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
  end;
  FS.EndChange;
end;

end.
