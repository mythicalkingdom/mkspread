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

program mkspread;
{$mode objfpc}{$H+}

uses SysUtils, keys, terminal, session, commands, controller, view, demo, keytest, cmdfile;

const
  Version = '0.7 (phase 7: @functions)';

procedure Usage;
begin
  WriteLn('Usage: mkspread [options] [file.wk1]');
  WriteLn('  --demo       start with the sample worksheet');
  WriteLn('  --expand     use the whole terminal instead of 80x25');
  WriteLn('  --keytest    show how the terminal''s keys are received');
  WriteLn('  --version    print version');
  WriteLn('  --help       this text');
end;

var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;
  V: TView;
  Queue: TKeyQueue;
  i: Integer;
  opt: string;
  doDemo, doKeyTest: Boolean;
  startFile, loadMsg: string;
  k: Integer;

begin
  doDemo := False;
  doKeyTest := False;
  V := TView.Create;
  for i := 1 to ParamCount do
  begin
    opt := LowerCase(ParamStr(i));
    if (opt = '--demo') or (opt = 'demo') then doDemo := True
    else if opt = '--expand' then V.Expand := True
    else if opt = '--keytest' then doKeyTest := True
    else if opt = '--version' then begin WriteLn('mkspread ', Version); Halt(0); end
    else if (opt = '--help') or (opt = '-h') then begin Usage; Halt(0); end
    else if (Length(opt) > 0) and (opt[1] = '-') then
    begin
      WriteLn('mkspread: unknown option ', ParamStr(i));
      Usage;
      Halt(2);
    end
    else startFile := ParamStr(i);
  end;

  S := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  Queue := TKeyQueue.Create;
  if doDemo then LoadDemo(S);
  if startFile <> '' then
  begin
    loadMsg := RetrieveFile(S, startFile);
    if loadMsg <> '' then
    begin
      WriteLn('mkspread: ', loadMsg);
      Halt(1);
    end;
  end;

  TermInit;
  try
    if doKeyTest then
      RunKeyTest
    else
      repeat
        if Queue.Empty then V.Draw(S);
        if Queue.Empty then
          Queue.Push(TermReadKey(-1));
        k := Queue.Pop;
        Ctl.HandleKey(k);
      until S.Quitting;
  finally
    TermDone;
  end;
end.
