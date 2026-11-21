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

{ The sample worksheet used for screenshots and tests. }
unit demo;
{$mode objfpc}{$H+}

interface

uses session;

procedure LoadDemo(S: TSession);

implementation

uses sheet;

procedure LoadDemo(S: TSession);
  procedure L(r, c: Integer; const txt: string);
  begin
    S.Sheet.Put(r, c, txt);
  end;
  procedure V(r, c: Integer; const txt, cache: string);
  var
    cell: TCell;
  begin
    cell := S.Sheet.Put(r, c, txt);
    cell.Fmt := 2;
    cell.Cache := cache;
  end;
begin
  S.Sheet.SetColWidth(10, 1);
  S.Sheet.SetColWidth(11, 23);
  S.Sheet.SetColWidth(14, 24);
  L(1, 11, '''     Variable Costs/Unit');
  L(1, 14, '''          Fixed Costs');
  L(2, 11, '''Description');
  L(2, 12, '"Cost/Unit');
  L(2, 14, '''Description');
  L(3, 11, '\=');
  L(3, 12, '\=');
  L(3, 14, '\=');
  L(4, 11, '''Materials');         V(4, 12, '3.26', '');
  L(5, 11, '''Contract Labor');    V(5, 12, '3.75', '');
  L(6, 11, '''Energy');            V(6, 12, '1.45', '');
  L(7, 11, '''Sales Commissions'); V(7, 12, '2.21', '');
  L(8, 11, '''Freight');           V(8, 12, '0.32', '');
  L(9, 12, '\-');
  L(10, 11, '''Total');            V(10, 12, '@SUM(L4:L8)', '10.99');
  L(4, 14, '''Plant Operation');
  L(5, 14, '''Salaries');
  L(6, 14, '''Administration');
  L(7, 14, '''Sales & Marketing');
  L(8, 14, '''Research & Development');
  S.CurCol := 11;
  S.CurRow := 4;
  S.LeftCol := 10;
  S.TopRow := 1;
end;

end.
