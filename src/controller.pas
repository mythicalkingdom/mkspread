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
    procedure MoveCur(dr, dc: Integer);
    procedure EndJump(dr, dc: Integer);
    procedure BigRight;
    procedure BigLeft;
    procedure Ready(k: Integer);
    procedure EntryKey(k: Integer);
    procedure GotoKey(k: Integer);
    procedure MenuKey(k: Integer);
    procedure CommitEntry;
    procedure SelectItem(i: Integer);
    procedure StubKey(const name: string);
  public
    constructor Create(S: TSession; Cmds: TCommands);
    procedure HandleKey(k: Integer);
  end;

implementation

uses keys, sheet, cellfmt, menutree, SysUtils;

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
  if InBounds(r + dr, c + dc) and (sh.Find(r, c) <> nil) and (sh.Find(r + dr, c + dc) <> nil) then
  begin
    while InBounds(r + dr, c + dc) and (sh.Find(r + dr, c + dc) <> nil) do
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
      if sh.Find(r, c) <> nil then break;
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

procedure TController.Ready(k: Integer);
var
  em: Boolean;
  mr, mc: Integer;
begin
  if k = kEnd then
  begin
    FS.EndMode := not FS.EndMode;
    exit;
  end;
  em := FS.EndMode;
  FS.EndMode := False;
  if (k = Ord('/')) or (k = Ord('<')) then
  begin
    FS.OpenMenu;
    exit;
  end;
  case k of
    kUp:    if em then EndJump(-1, 0) else MoveCur(-1, 0);
    kDown:  if em then EndJump(1, 0) else MoveCur(1, 0);
    kLeft:  if em then EndJump(0, -1) else MoveCur(0, -1);
    kRight: if em then EndJump(0, 1) else MoveCur(0, 1);
    kHome:
      if em then
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
    kF1: StubKey('F1 (HELP)');
    kF1 + 1: StubKey('F2 (EDIT)');
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
    kAltF1 + 3: StubKey('Alt-F4 (UNDO)');
    kBreak, kEsc, kBackspace: ;
    32..126, 128..kSpecialBase - 1:
      begin
        if (k < 127) and (Chr(k) in ['0'..'9', '+', '-', '.', '@', '(', '#', '$']) then
          FS.Mode := mValue
        else
          FS.Mode := mLabel;
        FS.Entry := '';
        FS.Entry := UTF8Encode(WideChar(k));
      end;
  else
    if IsAltLetter(k) then StubKey('Alt-' + AltLetter(k) + ' (macro)');
  end;
end;

procedure TController.CommitEntry;
var
  raw: string;
begin
  if FS.Entry <> '' then
  begin
    raw := FS.Entry;
    if (FS.Mode = mLabel) and not (raw[1] in LabelPrefixes) then
      raw := '''' + raw;
    FS.Sheet.Put(FS.CurRow, FS.CurCol, raw);
  end;
  FS.Mode := mReady;
end;

procedure DeleteLastChar(var s: string);
var
  n: Integer;
begin
  n := Length(s);
  if n = 0 then exit;
  while (n > 1) and ((Ord(s[n]) and $C0) = $80) do Dec(n);   { skip UTF-8 continuation bytes }
  Delete(s, n, MaxInt);
end;

procedure TController.EntryKey(k: Integer);
begin
  case k of
    kEnter: CommitEntry;
    kEsc, kBreak:
      begin
        FS.Mode := mReady;
        FS.Entry := '';
      end;
    kBackspace: DeleteLastChar(FS.Entry);
    kUp:    begin CommitEntry; MoveCur(-1, 0); end;
    kDown:  begin CommitEntry; MoveCur(1, 0); end;
    kLeft:  begin CommitEntry; MoveCur(0, -1); end;
    kRight: begin CommitEntry; MoveCur(0, 1); end;
    kPgUp, kPgDn, kHome, kTab, kShiftTab, kCtrlLeft, kCtrlRight:
      begin
        CommitEntry;
        Ready(k);
      end;
    32..126, 128..kSpecialBase - 1:
      if Length(FS.Entry) < 240 then FS.Entry := FS.Entry + UTF8Encode(WideChar(k));
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
    kBackspace: DeleteLastChar(FS.Entry);
    32..126: if Length(FS.Entry) < 12 then FS.Entry := FS.Entry + Chr(k);
  end;
end;

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
  case FS.Mode of
    mReady: Ready(k);
    mLabel, mValue: EntryKey(k);
    mMenu: MenuKey(k);
    mGoto: GotoKey(k);
  end;
end;

end.
