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

{ Command registry.  A command is identified by its menu path, for example
  'Worksheet Global Format Fixed'.  Anything not registered is a stub. }
unit commands;
{$mode objfpc}{$H+}

interface

uses session, Generics.Collections;

type
  TCommandProc = procedure(S: TSession);
  TCommandMap = specialize TDictionary<string, TCommandProc>;

  TCommands = class
  private
    FMap: TCommandMap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Register(const path: string; proc: TCommandProc);
    { Runs the command; for unimplemented commands sets a stub message. }
    procedure Run(const path: string; S: TSession);
    function IsImplemented(const path: string): Boolean;
  end;

procedure RegisterCoreCommands(C: TCommands);

implementation

constructor TCommands.Create;
begin
  inherited Create;
  FMap := TCommandMap.Create;
end;

destructor TCommands.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

procedure TCommands.Register(const path: string; proc: TCommandProc);
begin
  FMap.AddOrSetValue(path, proc);
end;

function TCommands.IsImplemented(const path: string): Boolean;
begin
  Result := FMap.ContainsKey(path);
end;

procedure TCommands.Run(const path: string; S: TSession);
var
  proc: TCommandProc;
begin
  if FMap.TryGetValue(path, proc) then
    proc(S)
  else
    S.Msg := '[stub] /' + path;
end;

procedure CmdQuitNo(S: TSession);
begin
  { nothing: just return to READY }
end;

procedure CmdQuitYes(S: TSession);
begin
  S.Quitting := True;
end;

procedure RegisterCoreCommands(C: TCommands);
begin
  C.Register('Quit No', @CmdQuitNo);
  C.Register('Quit Yes', @CmdQuitYes);
end;

end.
