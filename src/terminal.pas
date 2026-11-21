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

{ Thin terminal layer over ncurses: drawing primitives and logical-key input. }
unit terminal;
{$mode objfpc}{$H+}

interface

type
  TAttr = (taNormal, taHi, taMsg);

procedure TermInit;
procedure TermDone;
function TermWidth: Integer;
function TermHeight: Integer;
procedure TermClear;
{ x, y are 1-based.  s is UTF-8. }
procedure TermPut(x, y: Integer; a: TAttr; const s: string);
procedure TermCursor(x, y: Integer);
procedure TermHideCursor;
procedure TermRefresh;
{ Wait up to ms milliseconds (-1 = forever) for a key; kNone on timeout. }
function TermReadKey(ms: Integer): Integer;

implementation

uses ncw, keys, ctypes, SysUtils;

var
  Colour: Boolean = False;
  CurX: Integer = 0;
  CurY: Integer = 0;
  CurOn: Boolean = False;

procedure TermInit;
var
  i: Integer;
  e: TKeySeq;
begin
  setlocale(LC_ALL, '');
  initscr;
  raw;
  noecho;
  nonl;
  keypad(stdscr, True);
  set_escdelay(40);          { long enough for slow SSH links, short enough to feel snappy }
  curs_set(0);
  Colour := has_colors;
  if Colour then
  begin
    start_color;
    init_pair(1, COLOR_WHITE, COLOR_BLACK);
    init_pair(2, COLOR_BLACK, COLOR_CYAN);
    init_pair(3, COLOR_YELLOW, COLOR_BLACK);
  end;
  for i := 0 to MapCount - 1 do
  begin
    e := MapEntry(i);
    define_key(PChar(e.Seq), e.Key - kSpecialBase + 2000);
  end;
end;

procedure TermDone;
begin
  curs_set(1);
  endwin;
end;

function TermWidth: Integer;
begin
  Result := getmaxx(stdscr);
end;

function TermHeight: Integer;
begin
  Result := getmaxy(stdscr);
end;

procedure TermClear;
begin
  werase(stdscr);
end;

procedure SetAttr(a: TAttr);
begin
  if Colour then
    case a of
      taNormal: wattrset(stdscr, 1 shl 8);
      taHi:     wattrset(stdscr, 2 shl 8);
      taMsg:    wattrset(stdscr, (3 shl 8) or A_BOLD);
    end
  else
    case a of
      taNormal: wattrset(stdscr, A_NORMAL);
      taHi:     wattrset(stdscr, A_REVERSE);
      taMsg:    wattrset(stdscr, A_BOLD);
    end;
end;

procedure TermPut(x, y: Integer; a: TAttr; const s: string);
begin
  if s = '' then exit;
  SetAttr(a);
  wmove(stdscr, y - 1, x - 1);
  waddstr(stdscr, PChar(s));
end;

procedure TermCursor(x, y: Integer);
begin
  CurX := x;
  CurY := y;
  CurOn := True;
end;

procedure TermHideCursor;
begin
  CurOn := False;
end;

procedure TermRefresh;
begin
  if CurOn then
  begin
    wmove(stdscr, CurY - 1, CurX - 1);
    curs_set(1);
  end
  else
    curs_set(0);
  wrefresh(stdscr);
end;

{ Special codes handed to define_key are offset so they never collide with
  ncurses' own KEY_* values (all below 1000) or Unicode. }
function FromDefined(code: Integer): Integer;
begin
  Result := code - 2000 + kSpecialBase;
end;

function TranslateCode(c: Integer): Integer;
begin
  case c of
    KEY_UP: Result := kUp;
    KEY_DOWN: Result := kDown;
    KEY_LEFT: Result := kLeft;
    KEY_RIGHT: Result := kRight;
    KEY_HOME: Result := kHome;
    KEY_END: Result := kEnd;
    KEY_PPAGE: Result := kPgUp;
    KEY_NPAGE: Result := kPgDn;
    KEY_IC: Result := kIns;
    KEY_DC: Result := kDel;
    KEY_BTAB: Result := kShiftTab;
    KEY_ENTER: Result := kEnter;
    KEY_BACKSPACE: Result := kBackspace;
    KEY_RESIZE: Result := kResize;
    KEY_F0 + 1 .. KEY_F0 + 10: Result := kF1 + (c - KEY_F0 - 1);
  else
    if c >= 2000 then Result := FromDefined(c) else Result := kNone;
  end;
end;

function TermReadKey(ms: Integer): Integer;
var
  ch: cuint;
  r: cint;
  k: Integer;
begin
  wtimeout(stdscr, ms);
  ch := 0;
  r := wget_wch(stdscr, ch);
  if r = ERR then exit(kNone);
  if r = KEY_CODE_YES then exit(TranslateCode(ch));
  k := ch;
  if k = 127 then k := kBackspace;
  if k = kEsc then
  begin
    { ESC immediately followed by a character is Alt-<character>. }
    wtimeout(stdscr, 0);
    r := wget_wch(stdscr, ch);
    if (r <> ERR) and (r <> KEY_CODE_YES) and (ch < 127) and (Chr(ch) in ['a'..'z', 'A'..'Z']) then
      exit(MakeAlt(Chr(ch)));
    if (r <> ERR) and (r <> KEY_CODE_YES) then
      unget_wch(ch);       { Esc followed by something else: give the char back }
    exit(kEsc);
  end;
  Result := Canonical(k);
end;

end.
