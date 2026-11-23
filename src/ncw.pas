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

{ Minimal binding to the wide-character ncurses library (libncursesw). }
unit ncw;
{$mode objfpc}{$H+}
{$linklib ncursesw}

interface

uses ctypes;

const
  ERR = -1;
  KEY_CODE_YES = 256;
  A_NORMAL  = 0;
  A_REVERSE = $40000;
  A_BOLD    = $200000;
  COLOR_BLACK = 0; COLOR_RED = 1; COLOR_GREEN = 2; COLOR_YELLOW = 3;
  COLOR_BLUE = 4; COLOR_MAGENTA = 5; COLOR_CYAN = 6; COLOR_WHITE = 7;
  LC_ALL = 6;

  KEY_DOWN = 258; KEY_UP = 259; KEY_LEFT = 260; KEY_RIGHT = 261;
  KEY_HOME = 262; KEY_BACKSPACE = 263; KEY_F0 = 264;
  KEY_DC = 330; KEY_IC = 331; KEY_NPAGE = 338; KEY_PPAGE = 339;
  KEY_ENTER = 343; KEY_BTAB = 353; KEY_END = 360; KEY_RESIZE = 410;

var
  stdscr: Pointer; external name 'stdscr';

function setlocale(category: cint; locale: PChar): PChar; cdecl; external 'c';
function initscr: Pointer; cdecl; external 'ncursesw';
function endwin: cint; cdecl; external 'ncursesw';
function def_prog_mode: cint; cdecl; external 'ncursesw';
function reset_prog_mode: cint; cdecl; external 'ncursesw';
function clearok(w: Pointer; f: ByteBool): cint; cdecl; external 'ncursesw';
function raw: cint; cdecl; external 'ncursesw';
function noecho: cint; cdecl; external 'ncursesw';
function nonl: cint; cdecl; external 'ncursesw';
function keypad(w: Pointer; f: ByteBool): cint; cdecl; external 'ncursesw';
function curs_set(v: cint): cint; cdecl; external 'ncursesw';
function has_colors: ByteBool; cdecl; external 'ncursesw';
function start_color: cint; cdecl; external 'ncursesw';
function init_pair(pair, fg, bg: cshort): cint; cdecl; external 'ncursesw';
function wattrset(w: Pointer; a: cint): cint; cdecl; external 'ncursesw';
function wmove(w: Pointer; y, x: cint): cint; cdecl; external 'ncursesw';
function waddstr(w: Pointer; s: PChar): cint; cdecl; external 'ncursesw';
function werase(w: Pointer): cint; cdecl; external 'ncursesw';
function wrefresh(w: Pointer): cint; cdecl; external 'ncursesw';
function wnoutrefresh(w: Pointer): cint; cdecl; external 'ncursesw';
function doupdate: cint; cdecl; external 'ncursesw';
function wtimeout(w: Pointer; delay: cint): cint; cdecl; external 'ncursesw' name 'wtimeout';
function wget_wch(w: Pointer; var c: cuint): cint; cdecl; external 'ncursesw';
function unget_wch(c: cuint): cint; cdecl; external 'ncursesw';
function set_escdelay(d: cint): cint; cdecl; external 'ncursesw';
function define_key(def: PChar; code: cint): cint; cdecl; external 'ncursesw';
function getmaxy(w: Pointer): cint; cdecl; external 'ncursesw';
function getmaxx(w: Pointer): cint; cdecl; external 'ncursesw';

implementation

end.
