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

{ Key-test mode: shows what the program receives for each key press, so a
  user can check how their terminal maps onto the logical keys. }
unit keytest;
{$mode objfpc}{$H+}

interface

procedure RunKeyTest;

implementation

uses terminal, keys, SysUtils;

procedure RunKeyTest;
const
  Max = 18;
var
  hist: array[0..Max - 1] of string;
  n, i, k: Integer;
  done: Boolean;
begin
  n := 0;
  done := False;
  repeat
    TermClear;
    TermHideCursor;
    TermPut(1, 1, taHi, ' mkspread key test: press keys to see how they arrive. Ctrl-Q quits. ');
    TermPut(1, 3, taNormal, 'Logical key name        code');
    for i := 0 to n - 1 do
      TermPut(1, 4 + i, taNormal, hist[i]);
    TermRefresh;
    k := TermReadKey(-1);
    if k = 17 then
      done := True
    else if k <> kNone then
    begin
      if n = Max then
      begin
        for i := 0 to Max - 2 do hist[i] := hist[i + 1];
        Dec(n);
      end;
      hist[n] := Format('%-22s %d', [KeyName(k), k]);
      Inc(n);
    end;
  until done;
end;

end.
