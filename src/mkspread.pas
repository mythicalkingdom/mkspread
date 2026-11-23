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

uses SysUtils, DateUtils, StrUtils, keys, terminal, session, commands, controller, view, demo, keytest,
     cmdfile, macro, version, config, recovery, defaults;

procedure Usage;
begin
  WriteLn('Usage: mkspread [options] [file.wk1]');
  WriteLn('  --demo         start with the sample worksheet');
  WriteLn('  --expand       use the whole terminal instead of 80x25');
  WriteLn('  --autosave=N   save the worksheet to its file every N minutes (0 = off)');
  WriteLn('  --keytest      show how the terminal''s keys are received');
  WriteLn('  --version      print version');
  WriteLn('  --help         this text');
  WriteLn('Settings can also be kept in ', ConfigPath, ' (see docs/config.md).');
end;

var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;
  V: TView;
  Queue: TKeyQueue;
  M: TMacro;
  kb: Integer;
  i: Integer;
  opt: string;
  doDemo, doKeyTest: Boolean;
  startFile, loadMsg, problems: string;
  k: Integer;
  cfg: TConfig;
  Stale: TStale;
  lastRecovery, lastAutosave: TDateTime;
  recChanges: Cardinal;
  noRecovery, needDraw: Boolean;
  lastMinute: Integer;
  lastMsg: string;

{ the answer to "unsaved worksheet found" }
procedure RecoverChosen(S: TSession; const path: string);
var
  msg: string;
begin
  case S.ChoiceIndex of
    0:
      begin
        msg := RetrieveFile(S, Stale.Path);
        if msg <> '' then
          S.Msg := msg
        else
        begin
          S.FileName := Stale.Original;       { saving goes back to the original file }
          S.Modified := True;
          Inc(S.Changes);
          DeleteStale(Stale);
          S.Msg := 'Recovered; save it with /File Save';
        end;
      end;
    1: DeleteStale(Stale);
  end;
end;

{ recovery file and autosave, once in a while }
procedure Housekeeping;
var
  now_: TDateTime;
  err, warn: string;
begin
  S.CheckModified;
  now_ := Now;
  if (cfg.AutosaveMinutes > 0) and S.Modified and (S.FileName <> '') and (S.Mode = mReady) and
     (MinutesBetween(now_, lastAutosave) >= cfg.AutosaveMinutes) then
  begin
    err := SaveSessionFile(S, S.FileName, warn);
    lastAutosave := now_;
    if err = '' then
    begin
      S.MarkSaved;
      S.Msg := 'Autosaved ' + ExtractFileName(S.FileName);
    end
    else
      S.Msg := 'Autosave failed: ' + err;
  end;
  if (cfg.RecoverySeconds > 0) and not noRecovery and S.Modified and (S.Changes <> recChanges) and
     (SecondsBetween(now_, lastRecovery) >= cfg.RecoverySeconds) then
  begin
    WriteRecovery(S);
    recChanges := S.Changes;
    lastRecovery := now_;
  end;
end;

begin
  doDemo := False;
  doKeyTest := False;
  noRecovery := False;
  V := TView.Create;
  DefaultConfig(cfg);
  LoadConfig(cfg, problems);
  if problems <> '' then Write(StdErr, 'mkspread: ', ConfigPath, ': ', problems);
  V.Expand := cfg.Expand;
  for i := 1 to ParamCount do
  begin
    opt := LowerCase(ParamStr(i));
    if (opt = '--demo') or (opt = 'demo') then doDemo := True
    else if opt = '--expand' then V.Expand := True
    else if opt = '--keytest' then doKeyTest := True
    else if Copy(opt, 1, 11) = '--autosave=' then
    begin
      if not TryStrToInt(Copy(opt, 12, MaxInt), cfg.AutosaveMinutes) or (cfg.AutosaveMinutes < 0) then
      begin
        WriteLn('mkspread: --autosave needs a number of minutes');
        Halt(2);
      end;
    end
    else if opt = '--version' then begin WriteLn(VersionText); Halt(0); end
    else if (opt = '--help') or (opt = '-h') then begin Usage; Halt(0); end
    else if (Length(opt) > 0) and (opt[1] = '-') then
    begin
      WriteLn('mkspread: unknown option ', ParamStr(i));
      Usage;
      Halt(2);
    end
    else startFile := ParamStr(i);
  end;

  ApplyConfig(cfg);
  if (cfg.Directory <> '') and DirectoryExists(cfg.Directory) then SetCurrentDir(cfg.Directory);
  S := TSession.Create;
  S.Cfg := cfg;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  Queue := TKeyQueue.Create;
  M := TMacro.Create(S);
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

  if S.MacroRequest <> '' then M.TakeRequest;       { an autoexec macro in the file }
  S.MarkSaved;
  lastRecovery := Now;
  lastAutosave := Now;
  recChanges := S.Changes;
  InstallHangupHandlers;
  needDraw := True;
  lastMinute := MinuteOf(Now);

  TermInit;
  try
    if doKeyTest then
      RunKeyTest
    else
    begin
      { an unsaved worksheet left behind by a program that died? }
      Stale := FindStale;
      if Stale.Found and not doKeyTest then
      begin
        S.AskChoice(['Recover', 'Discard', 'Later'], @RecoverChosen, 'Recover');
        S.ChoiceHelp.Add('Load the unsaved worksheet' + IfThen(Stale.Original <> '', ' of ' + Stale.Original, '') +
                         IfThen(Stale.When <> '', ' (' + Stale.When + ')', ''));
        S.ChoiceHelp.Add('Delete the recovery file');
        S.ChoiceHelp.Add('Keep it and ask again next time');
      end;
      repeat
        if Hangup then
        begin
          S.CheckModified;
          if S.Modified and not noRecovery then WriteRecovery(S);
          Halt(1);                     { the recovery file stays for the next start }
        end;
        if M.Running then
        begin
          { a macro is typing: only Ctrl-Break gets through }
          kb := TermReadKey(0);
          if kb = kBreak then
            M.Stop
          else if M.NextKey(k) then
          begin
            Ctl.HandleKey(k);
            needDraw := True;
          end;
        end
        else
        begin
          if Queue.Empty and needDraw then
          begin
            V.Draw(S);
            needDraw := False;
          end;
          if Queue.Empty then
            Queue.Push(TermReadKey(1000));
          k := Queue.Pop;
          if k <> kNone then
          begin
            if not (M.Active and M.UserKey(k)) then Ctl.HandleUserKey(k);
            needDraw := True;
          end;
          lastMsg := S.Msg;
          Housekeeping;
          { the screen is redrawn when something changed, or for the clock once a minute }
          if (S.Msg <> lastMsg) or (MinuteOf(Now) <> lastMinute) then
          begin
            needDraw := True;
            lastMinute := MinuteOf(Now);
          end;
        end;
        if S.MacroRequest <> '' then M.TakeRequest;
      until S.Quitting;
    end;
  finally
    TermDone;
  end;
  RemoveRecovery;                       { a clean exit leaves nothing to recover }
end.
