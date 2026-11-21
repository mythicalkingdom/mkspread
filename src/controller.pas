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

uses session, commands;

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
    procedure PromptKey(k: Integer);
    procedure PointKey(k: Integer);
    procedure MenuKey(k: Integer);
    procedure CommitText(const text: string);
    procedure StartEdit;
    procedure SelectItem(i: Integer);
    procedure StubKey(const name: string);
    procedure RestorePromptPreview;
    procedure PointFinish(accept: Boolean);
  public
    constructor Create(S: TSession; Cmds: TCommands);
    procedure HandleKey(k: Integer);
  end;

{ "A1", "A1..C5", "a1.c5" -> normalized range }
function ParseRangeText(const s: string; out r: TRange): Boolean;

implementation

uses keys, sheet, cellfmt, menutree, u8edit, SysUtils;

function ParseRangeText(const s: string; out r: TRange): Boolean;
var
  p, q, c1, r1, c2, r2: Integer;
  t: string;
begin
  t := Trim(s);
  p := Pos('.', t);
  if p = 0 then
  begin
    Result := ParseAddr(t, c1, r1);
    c2 := c1;
    r2 := r1;
  end
  else
  begin
    q := p;
    while (q <= Length(t)) and (t[q] = '.') do Inc(q);
    Result := ParseAddr(Copy(t, 1, p - 1), c1, r1) and ParseAddr(Copy(t, q, MaxInt), c2, r2);
  end;
  if Result then r := NormRange(r1, c1, r2, c2);
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
  while (nl > 1) and (w + FS.Sheet.ColWidth(nl - 1) <= FS.GridW) do
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
        Dec(FS.CurRow, FS.GridRows);
        Dec(FS.TopRow, FS.GridRows);
        if FS.CurRow < 1 then FS.CurRow := 1;
        if FS.TopRow < 1 then FS.TopRow := 1;
        FS.Normalize;
      end;
    kPgDn:
      begin
        Inc(FS.CurRow, FS.GridRows);
        Inc(FS.TopRow, FS.GridRows);
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
    kF1 + 8: StubKey('F9 (CALC)');
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
  prefix keeps it a label, a number-ish start makes it a value, anything else
  is a label with the worksheet's default prefix. }
procedure TController.CommitText(const text: string);
var
  raw: string;
  d: Double;
  code: Integer;
begin
  FS.Mode := mReady;
  if text = '' then exit;
  raw := text;
  if raw[1] in LabelPrefixes then
    { label as typed }
  else if raw[1] in ValueStarts then
  begin
    Val(raw, d, code);
    if (code = 0) and not (raw[1] in ['$', '#']) then raw := NumToRaw(d);
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
    kUp:    begin CommitText(FS.Entry); MoveCur(-1, 0); end;
    kDown:  begin CommitText(FS.Entry); MoveCur(1, 0); end;
    kLeft:  begin CommitText(FS.Entry); MoveCur(0, -1); end;
    kRight: begin CommitText(FS.Entry); MoveCur(0, 1); end;
    kPgUp, kPgDn, kHome, kTab, kShiftTab, kCtrlLeft, kCtrlRight:
      begin
        CommitText(FS.Entry);
        NavKey(k);
      end;
    32..126, 128..kSpecialBase - 1:
      if Length(FS.Entry) < 240 then FS.Entry := FS.Entry + UTF8Encode(WideChar(k));
  end;
end;

procedure TController.EditKey(k: Integer);
begin
  case k of
    kEnter: CommitText(FS.Entry);
    kEsc, kBreak:
      begin
        FS.Mode := mReady;
        FS.Entry := '';
      end;
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
    kUp:   begin CommitText(FS.Entry); MoveCur(-1, 0); end;
    kDown: begin CommitText(FS.Entry); MoveCur(1, 0); end;
    32..126, 128..kSpecialBase - 1:
      if Length(FS.Entry) < 240 then
      begin
        U8Insert(FS.Entry, FS.EditPos, UTF8Encode(WideChar(k)));
        Inc(FS.EditPos);
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
    ok := ParseRangeText(FS.Entry, r)
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
  end;
end;

end.
