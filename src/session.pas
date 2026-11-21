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

{ All mutable UI-visible state of a running spreadsheet session. No drawing,
  no key handling: those live in view.pas and controller.pas. }
unit session;
{$mode objfpc}{$H+}

interface

uses sheet, menutree;

type
  TMode = (mReady, mLabel, mValue, mMenu, mGoto);

  TSession = class
  public
    Sheet: TSheet;
    Menus: TMenuTree;
    CurCol, CurRow: Integer;
    LeftCol, TopRow: Integer;
    GridRows, GridW: Integer;           { size of the cell area, set by the view }
    Mode: TMode;
    Entry: string;                      { text being typed (UTF-8) }
    Msg: string;                        { one-shot message for the bottom line }
    EndMode: Boolean;
    Quitting: Boolean;
    { menu navigation: level d shows MenuNodes[d].Kids, highlight MenuIdx[d] }
    MenuDepth: Integer;
    MenuNodes: array[0..15] of TMenuNode;
    MenuIdx: array[0..15] of Integer;
    constructor Create;
    destructor Destroy; override;
    function RightColOf(left: Integer): Integer;
    procedure Normalize;
    procedure OpenMenu;
    function MenuPath(upTo: Integer): string;   { "Worksheet Global Format" }
  end;

implementation

uses menudata;

constructor TSession.Create;
begin
  inherited Create;
  Sheet := TSheet.Create;
  Menus := BuildMenuTree;
  CurCol := 1; CurRow := 1; LeftCol := 1; TopRow := 1;
  GridRows := 20;
  GridW := 76;
  Mode := mReady;
end;

destructor TSession.Destroy;
begin
  Menus.Free;
  Sheet.Free;
  inherited Destroy;
end;

function TSession.RightColOf(left: Integer): Integer;
var
  w, c: Integer;
begin
  c := left;
  w := Sheet.ColWidth(c);
  while (c < MaxCol) and (w + Sheet.ColWidth(c + 1) <= GridW) do
  begin
    Inc(c);
    Inc(w, Sheet.ColWidth(c));
  end;
  Result := c;
end;

procedure TSession.Normalize;
begin
  if CurCol < 1 then CurCol := 1;
  if CurCol > MaxCol then CurCol := MaxCol;
  if CurRow < 1 then CurRow := 1;
  if CurRow > MaxRow then CurRow := MaxRow;
  if CurCol < LeftCol then LeftCol := CurCol;
  while (LeftCol < CurCol) and (RightColOf(LeftCol) < CurCol) do Inc(LeftCol);
  if CurRow < TopRow then TopRow := CurRow;
  if CurRow > TopRow + GridRows - 1 then TopRow := CurRow - GridRows + 1;
  if TopRow < 1 then TopRow := 1;
  if TopRow > MaxRow - GridRows + 1 then TopRow := MaxRow - GridRows + 1;
end;

procedure TSession.OpenMenu;
begin
  Mode := mMenu;
  MenuDepth := 0;
  MenuNodes[0] := Menus.Root;
  MenuIdx[0] := 0;
end;

function TSession.MenuPath(upTo: Integer): string;
var
  j: Integer;
begin
  Result := '';
  for j := 0 to upTo do
  begin
    if j > 0 then Result := Result + ' ';
    Result := Result + MenuNodes[j][MenuIdx[j]].Name;
  end;
end;

end.
