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

uses cmdsheet, cmdedit, cmdfile, cmddata, cmdprint, cmddefault;

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
    proc(S, path)
  else
    S.Msg := '[stub] /' + path;
end;

procedure CmdSystem(S: TSession; const path: string);
begin
  S.SystemCmd := '';
  S.SystemPending := True;
end;

procedure CmdQuitNo(S: TSession; const path: string);
begin
  { nothing: just return to READY }
end;

procedure CmdQuitSure(S: TSession; const path: string);
begin
  if S.ChoiceIndex = 1 then S.Quitting := True;
end;

procedure CmdQuitYes(S: TSession; const path: string);
begin
  S.CheckModified;
  if S.Modified then
  begin
    { unsaved changes: ask again }
    S.AskChoice(['No', 'Yes'], @CmdQuitSure, path);
    S.ChoiceHelp.Add('Go back to the worksheet');
    S.ChoiceHelp.Add('Quit now: the changes since the last save are lost');
    S.Msg := 'The worksheet has unsaved changes';
  end
  else
    S.Quitting := True;
end;

procedure RegisterCoreCommands(C: TCommands);
begin
  C.Register('System', @CmdSystem);
  C.Register('Quit No', @CmdQuitNo);
  C.Register('Quit Yes', @CmdQuitYes);
  RegisterSheetCommands(C);
  RegisterEditCommands(C);
  RegisterFileCommands(C);
  RegisterDataCommands(C);
  RegisterPrintCommands(C);
  RegisterDefaultCommands(C);
end;

end.
