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

{ Logical keys, the terminal-sequence mapping table, and the key queue.
  Pure Pascal: no terminal access, so everything here is unit-testable.

  Printable characters are their Unicode code point.  Control letters are
  1..26 (Ctrl-A = 1).  Everything else gets a code at or above kSpecialBase. }
unit keys;
{$mode objfpc}{$H+}

interface

const
  kNone      = 0;
  kBreak     = 3;                 { Ctrl-C, also stands in for Ctrl-Break }
  kBackspace = 8;
  kTab       = 9;
  kEnter     = 13;
  kEsc       = 27;

  kSpecialBase = $110000;
  kUp = kSpecialBase + 1;   kDown = kSpecialBase + 2;
  kLeft = kSpecialBase + 3; kRight = kSpecialBase + 4;
  kHome = kSpecialBase + 5; kEnd = kSpecialBase + 6;
  kPgUp = kSpecialBase + 7; kPgDn = kSpecialBase + 8;
  kIns = kSpecialBase + 9;  kDel = kSpecialBase + 10;
  kShiftTab = kSpecialBase + 11;
  kCtrlLeft = kSpecialBase + 12;  kCtrlRight = kSpecialBase + 13;
  kCtrlUp = kSpecialBase + 14;    kCtrlDown = kSpecialBase + 15;
  kCtrlHome = kSpecialBase + 16;  kCtrlEnd = kSpecialBase + 17;
  kCtrlPgUp = kSpecialBase + 18;  kCtrlPgDn = kSpecialBase + 19;
  kResize = kSpecialBase + 20;
  kF1 = kSpecialBase + 32;        { kF1 .. kF10 are consecutive }
  kF10 = kF1 + 9;
  kAltF1 = kSpecialBase + 48;     { kAltF1 .. kAltF10 are consecutive }
  kAltF10 = kAltF1 + 9;
  kAltBase = kSpecialBase + 128;  { kAltBase + Ord('A'..'Z') = Alt-A .. Alt-Z }

type
  TKeySeq = record
    Seq: string;       { escape sequence as sent by the terminal }
    Key: Integer;      { logical key }
    Note: string;      { which terminals send it }
  end;

{ Terminal escape sequences that are not in terminfo but are common. Installed
  at startup by the terminal unit. }
function MapCount: Integer;
function MapEntry(i: Integer): TKeySeq;

function IsFKey(k: Integer): Boolean;
function IsAltLetter(k: Integer): Boolean;
function AltLetter(k: Integer): Char;
function MakeAlt(ch: Char): Integer;

{ Keys some terminals cannot send have a documented equivalent. }
function Canonical(k: Integer): Integer;

function KeyName(k: Integer): string;

{ The text that types key k when it is part of a macro: the character itself
  (braces and tilde escaped), ~ for Enter, {DOWN} and so on for special keys.
  '' for keys a macro cannot hold (Alt keys, Ctrl-Break, Insert). }
function KeyMacroText(k: Integer): string;

type
  { FIFO of logical keys.  The terminal feeds it; macros will too. }
  TKeyQueue = class
  private
    FKeys: array of Integer;
    FHead, FCount: Integer;
  public
    procedure Push(k: Integer);
    procedure PushString(const utf8: string);     { each character as a key }
    function Pop: Integer;
    function Empty: Boolean;
    procedure Clear;
  end;

implementation

uses SysUtils;

const
  Map: array[0..51] of TKeySeq = (
    (Seq: #27'[A';    Key: kUp;        Note: 'terminals in normal cursor mode'),
    (Seq: #27'[B';    Key: kDown;      Note: 'terminals in normal cursor mode'),
    (Seq: #27'[C';    Key: kRight;     Note: 'terminals in normal cursor mode'),
    (Seq: #27'[D';    Key: kLeft;      Note: 'terminals in normal cursor mode'),
    (Seq: #27'[5~';   Key: kPgUp;      Note: 'nearly all terminals'),
    (Seq: #27'[6~';   Key: kPgDn;      Note: 'nearly all terminals'),
    (Seq: #27'[2~';   Key: kIns;       Note: 'nearly all terminals'),
    (Seq: #27'[3~';   Key: kDel;       Note: 'nearly all terminals'),
    (Seq: #27'[1;5C'; Key: kCtrlRight; Note: 'xterm, VTE, tmux, PuTTY'),
    (Seq: #27'[1;5D'; Key: kCtrlLeft;  Note: 'xterm, VTE, tmux, PuTTY'),
    (Seq: #27'[1;5A'; Key: kCtrlUp;    Note: 'xterm, VTE, tmux, PuTTY'),
    (Seq: #27'[1;5B'; Key: kCtrlDown;  Note: 'xterm, VTE, tmux, PuTTY'),
    (Seq: #27'[1;5H'; Key: kCtrlHome;  Note: 'xterm, VTE'),
    (Seq: #27'[1;5F'; Key: kCtrlEnd;   Note: 'xterm, VTE'),
    (Seq: #27'[5;5~'; Key: kCtrlPgUp;  Note: 'xterm, VTE'),
    (Seq: #27'[6;5~'; Key: kCtrlPgDn;  Note: 'xterm, VTE'),
    (Seq: #27'[5C';   Key: kCtrlRight; Note: 'older xterm, rxvt'),
    (Seq: #27'[5D';   Key: kCtrlLeft;  Note: 'older xterm, rxvt'),
    (Seq: #27'Oc';    Key: kCtrlRight; Note: 'rxvt'),
    (Seq: #27'Od';    Key: kCtrlLeft;  Note: 'rxvt'),
    (Seq: #27'[c';    Key: kRight;     Note: 'rxvt shift-right'),
    (Seq: #27'[1;2C'; Key: kRight;     Note: 'xterm shift-right (treated as plain)'),
    (Seq: #27'[1;2D'; Key: kLeft;      Note: 'xterm shift-left (treated as plain)'),
    (Seq: #27'[Z';    Key: kShiftTab;  Note: 'most terminals'),
    (Seq: #27'[1;3P'; Key: kAltF1;     Note: 'xterm alt-F1'),
    (Seq: #27'[1;3Q'; Key: kAltF1 + 1; Note: 'xterm alt-F2'),
    (Seq: #27'[1;3R'; Key: kAltF1 + 2; Note: 'xterm alt-F3'),
    (Seq: #27'[1;3S'; Key: kAltF1 + 3; Note: 'xterm alt-F4'),
    (Seq: #27'[15;3~'; Key: kAltF1 + 4; Note: 'xterm alt-F5'),
    (Seq: #27'[17;3~'; Key: kAltF1 + 5; Note: 'xterm alt-F6'),
    (Seq: #27'[18;3~'; Key: kAltF1 + 6; Note: 'xterm alt-F7'),
    (Seq: #27'[19;3~'; Key: kAltF1 + 7; Note: 'xterm alt-F8'),
    (Seq: #27'[20;3~'; Key: kAltF1 + 8; Note: 'xterm alt-F9'),
    (Seq: #27'[21;3~'; Key: kAltF1 + 9; Note: 'xterm alt-F10'),
    (Seq: #27'[1;5P'; Key: kF1;        Note: 'xterm ctrl-F1 (treated as plain)'),
    (Seq: #27'[1~';   Key: kHome;      Note: 'linux console, screen'),
    (Seq: #27'[4~';   Key: kEnd;       Note: 'linux console, screen'),
    (Seq: #27'[7~';   Key: kHome;      Note: 'rxvt'),
    (Seq: #27'[8~';   Key: kEnd;       Note: 'rxvt'),
    (Seq: #27'OH';    Key: kHome;      Note: 'xterm application mode'),
    (Seq: #27'OF';    Key: kEnd;       Note: 'xterm application mode'),
    (Seq: #27'[H';    Key: kHome;      Note: 'xterm normal mode'),
    (Seq: #27'[F';    Key: kEnd;       Note: 'xterm normal mode'),
    (Seq: #27'[[A';   Key: kF1;        Note: 'linux console'),
    (Seq: #27'[[B';   Key: kF1 + 1;    Note: 'linux console'),
    (Seq: #27'[[C';   Key: kF1 + 2;    Note: 'linux console'),
    (Seq: #27'[[D';   Key: kF1 + 3;    Note: 'linux console'),
    (Seq: #27'[[E';   Key: kF1 + 4;    Note: 'linux console'),
    (Seq: #27'[11~';  Key: kF1;        Note: 'rxvt'),
    (Seq: #27'[12~';  Key: kF1 + 1;    Note: 'rxvt'),
    (Seq: #27'[13~';  Key: kF1 + 2;    Note: 'rxvt'),
    (Seq: #27'[14~';  Key: kF1 + 3;    Note: 'rxvt')
  );

function MapCount: Integer;
begin
  Result := Length(Map);
end;

function MapEntry(i: Integer): TKeySeq;
begin
  Result := Map[i];
end;

function IsFKey(k: Integer): Boolean;
begin
  Result := (k >= kF1) and (k <= kF10);
end;

function IsAltLetter(k: Integer): Boolean;
begin
  Result := (k >= kAltBase + Ord('A')) and (k <= kAltBase + Ord('Z'));
end;

function AltLetter(k: Integer): Char;
begin
  Result := Chr(k - kAltBase);
end;

function MakeAlt(ch: Char): Integer;
begin
  Result := kAltBase + Ord(UpCase(ch));
end;

function Canonical(k: Integer): Integer;
begin
  case k of
    21: Result := kAltF1 + 3;       { Ctrl-U = Undo (Alt-F4) }
    10: Result := kEnter;           { Ctrl-J / LF }
  else
    Result := k;
  end;
end;

function KeyName(k: Integer): string;
begin
  if k = kNone then exit('(none)');
  if (k >= 1) and (k <= 26) then
    case k of
      8: exit('Backspace');
      9: exit('Tab');
      13: exit('Enter');
      3: exit('Ctrl-C (Break)');
    else exit('Ctrl-' + Chr(64 + k));
    end;
  if k = 27 then exit('Esc');
  if (k >= 32) and (k < kSpecialBase) then
  begin
    if k < 127 then exit('''' + Chr(k) + '''');
    if k = 127 then exit('Del(127)');
    exit('U+' + IntToHex(k, 4));
  end;
  if IsAltLetter(k) then exit('Alt-' + AltLetter(k));
  if (k >= kF1) and (k <= kF10) then exit('F' + IntToStr(k - kF1 + 1));
  if (k >= kAltF1) and (k <= kAltF10) then exit('Alt-F' + IntToStr(k - kAltF1 + 1));
  case k of
    kUp: Result := 'Up';           kDown: Result := 'Down';
    kLeft: Result := 'Left';       kRight: Result := 'Right';
    kHome: Result := 'Home';       kEnd: Result := 'End';
    kPgUp: Result := 'PgUp';       kPgDn: Result := 'PgDn';
    kIns: Result := 'Ins';         kDel: Result := 'Del';
    kShiftTab: Result := 'Shift-Tab';
    kCtrlLeft: Result := 'Ctrl-Left';   kCtrlRight: Result := 'Ctrl-Right';
    kCtrlUp: Result := 'Ctrl-Up';       kCtrlDown: Result := 'Ctrl-Down';
    kCtrlHome: Result := 'Ctrl-Home';   kCtrlEnd: Result := 'Ctrl-End';
    kCtrlPgUp: Result := 'Ctrl-PgUp';   kCtrlPgDn: Result := 'Ctrl-PgDn';
    kResize: Result := '(resize)';
  else
    Result := '?' + IntToHex(k, 6);
  end;
end;

function KeyMacroText(k: Integer): string;
begin
  case k of
    kEnter: Result := '~';
    kEsc: Result := '{ESC}';
    kBackspace: Result := '{BS}';
    kTab: Result := '{BIGRIGHT}';
    kUp: Result := '{UP}';
    kDown: Result := '{DOWN}';
    kLeft: Result := '{LEFT}';
    kRight: Result := '{RIGHT}';
    kHome: Result := '{HOME}';
    kEnd: Result := '{END}';
    kPgUp: Result := '{PGUP}';
    kPgDn: Result := '{PGDN}';
    kDel: Result := '{DEL}';
    kCtrlRight, kCtrlPgDn: Result := '{BIGRIGHT}';
    kShiftTab, kCtrlLeft, kCtrlPgUp: Result := '{BIGLEFT}';
    kCtrlHome: Result := '{HOME}';
    kF1: Result := '{HELP}';
    kF1 + 1: Result := '{EDIT}';
    kF1 + 2: Result := '{NAME}';
    kF1 + 3: Result := '{ABS}';
    kF1 + 4: Result := '{GOTO}';
    kF1 + 5: Result := '{WINDOW}';
    kF1 + 6: Result := '{QUERY}';
    kF1 + 7: Result := '{TABLE}';
    kF1 + 8: Result := '{CALC}';
    kF1 + 9: Result := '{GRAPH}';
    Ord('{'): Result := '{{}';
    Ord('}'): Result := '{}}';
    Ord('~'): Result := '{~}';
  else
    if (k >= 32) and (k < kSpecialBase) then Result := UTF8Encode(WideChar(k)) else Result := '';
  end;
end;

{ ---- queue ---- }

procedure TKeyQueue.Push(k: Integer);
begin
  if FCount = Length(FKeys) then
    SetLength(FKeys, FCount * 2 + 16);
  FKeys[(FHead + FCount) mod Length(FKeys)] := k;
  Inc(FCount);
end;

procedure TKeyQueue.PushString(const utf8: string);
var
  i, len: Integer;
  u: UnicodeString;
begin
  u := UTF8Decode(utf8);
  len := Length(u);
  for i := 1 to len do
    Push(Ord(u[i]));
end;

function TKeyQueue.Pop: Integer;
begin
  if FCount = 0 then exit(kNone);
  Result := FKeys[FHead];
  FHead := (FHead + 1) mod Length(FKeys);
  Dec(FCount);
end;

function TKeyQueue.Empty: Boolean;
begin
  Result := FCount = 0;
end;

procedure TKeyQueue.Clear;
begin
  FHead := 0;
  FCount := 0;
end;

end.
