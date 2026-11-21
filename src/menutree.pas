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

{ Data-driven menu tree: no knowledge of screens or keys. }
unit menutree;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils;

type
  TMenuNode = class
  private
    FKids: TList;
    function GetKid(i: Integer): TMenuNode;
    function GetCount: Integer;
  public
    Name, Help: string;
    Parent: TMenuNode;
    constructor Create(const AName, AHelp: string; AParent: TMenuNode);
    destructor Destroy; override;
    function IsLeaf: Boolean;
    function KidsText: string;            { "Global, Insert, ..." }
    function PanelText: string;           { text for the 3rd screen line }
    function FindByInitial(ch: Char): Integer;
    property Count: Integer read GetCount;
    property Kids[i: Integer]: TMenuNode read GetKid; default;
  end;

  TMenuTree = class
  private
    FStack: array[0..15] of TMenuNode;
  public
    Root: TMenuNode;
    constructor Create;
    destructor Destroy; override;
    { Add an item at depth d (1 = main menu) as a child of the last item added
      at depth d-1.  Spec is 'Name|help text'. }
    function Add(d: Integer; const spec: string): TMenuNode;
  end;

implementation

constructor TMenuNode.Create(const AName, AHelp: string; AParent: TMenuNode);
begin
  inherited Create;
  Name := AName;
  Help := AHelp;
  Parent := AParent;
  FKids := TList.Create;
end;

destructor TMenuNode.Destroy;
var
  i: Integer;
begin
  for i := 0 to FKids.Count - 1 do TMenuNode(FKids[i]).Free;
  FKids.Free;
  inherited Destroy;
end;

function TMenuNode.GetKid(i: Integer): TMenuNode;
begin
  Result := TMenuNode(FKids[i]);
end;

function TMenuNode.GetCount: Integer;
begin
  Result := FKids.Count;
end;

function TMenuNode.IsLeaf: Boolean;
begin
  Result := FKids.Count = 0;
end;

function TMenuNode.KidsText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to Count - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + Kids[i].Name;
  end;
end;

function TMenuNode.PanelText: string;
begin
  if IsLeaf then Result := Help else Result := KidsText;
end;

function TMenuNode.FindByInitial(ch: Char): Integer;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if UpCase(Kids[i].Name[1]) = UpCase(ch) then exit(i);
  Result := -1;
end;

constructor TMenuTree.Create;
begin
  inherited Create;
  Root := TMenuNode.Create('', '', nil);
  FStack[0] := Root;
end;

destructor TMenuTree.Destroy;
begin
  Root.Free;
  inherited Destroy;
end;

function TMenuTree.Add(d: Integer; const spec: string): TMenuNode;
var
  p: Integer;
  nm, hp: string;
begin
  p := Pos('|', spec);
  if p > 0 then
  begin
    nm := Copy(spec, 1, p - 1);
    hp := Copy(spec, p + 1, MaxInt);
  end
  else
  begin
    nm := spec;
    hp := '';
  end;
  Result := TMenuNode.Create(nm, hp, FStack[d - 1]);
  FStack[d - 1].FKids.Add(Result);
  FStack[d] := Result;
end;

end.
