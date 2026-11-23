{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }

{ The recovery file.  While a worksheet has unsaved changes a copy is written to
  $XDG_STATE_HOME/mkspread/recover (default ~/.local/state/mkspread/recover) as
  <pid>.wk1 with a small <pid>.txt that says which file it was.  A clean exit
  removes them.  If the program dies (or the terminal hangs up) they stay, and the
  next start offers to recover them. }
unit recovery;
{$mode objfpc}{$H+}

interface

uses session;

type
  TStale = record
    Found: Boolean;
    Pid: Integer;
    Path: string;                { the .wk1 copy }
    Original: string;            { the file it came from ('' for a new worksheet) }
    When: string;
  end;

var
  RecoveryDirOverride: string = '';       { for tests }

function RecoveryDir: string;
procedure WriteRecovery(S: TSession);      { sets S.Msg when something goes wrong }
procedure RemoveRecovery;                  { this process's files }
function FindStale: TStale;                { a recovery file of a process that is gone }
procedure DeleteStale(const st: TStale);

{ stops the process cleanly when the terminal goes away: sets Hangup }
var
  Hangup: Boolean = False;
procedure InstallHangupHandlers;

implementation

uses SysUtils, Classes, BaseUnix, cmdfile;

function RecoveryDir: string;
var
  d: string;
begin
  if RecoveryDirOverride <> '' then exit(RecoveryDirOverride);
  d := GetEnvironmentVariable('XDG_STATE_HOME');
  if d = '' then d := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.local/state';
  Result := IncludeTrailingPathDelimiter(d) + 'mkspread/recover';
end;

function MyBase: string;
begin
  Result := IncludeTrailingPathDelimiter(RecoveryDir) + IntToStr(Integer(FpGetPid));
end;

procedure WriteRecovery(S: TSession);
var
  warn, err: string;
  info: TStringList;
begin
  if not ForceDirectories(RecoveryDir) then
  begin
    S.Msg := 'Cannot make the recovery folder';
    exit;
  end;
  err := SaveSessionFile(S, MyBase + '.wk1', warn);
  if err <> '' then
  begin
    S.Msg := 'Recovery file: ' + err;
    exit;
  end;
  info := TStringList.Create;
  try
    info.Add(S.FileName);
    info.Add(FormatDateTime('yyyy-mm-dd hh:nn', Now));
    try
      info.SaveToFile(MyBase + '.txt');
    except
    end;
  finally
    info.Free;
  end;
end;

procedure RemoveRecovery;
begin
  DeleteFile(MyBase + '.wk1');
  DeleteFile(MyBase + '.txt');
end;

function Alive(pid: Integer): Boolean;
begin
  Result := (FpKill(pid, 0) = 0) or (fpgeterrno = ESysEPERM);
end;

function FindStale: TStale;
var
  sr: TSearchRec;
  pid: Integer;
  base: string;
  info: TStringList;
  best: Int64;
  age: Int64;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Found := False;
  best := -1;
  if FindFirst(IncludeTrailingPathDelimiter(RecoveryDir) + '*.wk1', faAnyFile, sr) <> 0 then exit;
  try
    repeat
      pid := StrToIntDef(ChangeFileExt(sr.Name, ''), -1);
      if (pid <= 0) or Alive(pid) then continue;
      age := sr.Time;
      if age > best then
      begin
        best := age;
        base := IncludeTrailingPathDelimiter(RecoveryDir) + IntToStr(pid);
        Result.Found := True;
        Result.Pid := pid;
        Result.Path := base + '.wk1';
        Result.Original := '';
        Result.When := '';
        if FileExists(base + '.txt') then
        begin
          info := TStringList.Create;
          try
            try
              info.LoadFromFile(base + '.txt');
              if info.Count > 0 then Result.Original := info[0];
              if info.Count > 1 then Result.When := info[1];
            except
            end;
          finally
            info.Free;
          end;
        end;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

procedure DeleteStale(const st: TStale);
begin
  DeleteFile(st.Path);
  DeleteFile(ChangeFileExt(st.Path, '.txt'));
end;

procedure HangupHandler(sig: cint); cdecl;
begin
  Hangup := True;
end;

procedure InstallHangupHandlers;
begin
  FpSignal(SIGHUP, @HangupHandler);
  FpSignal(SIGTERM, @HangupHandler);
end;

end.
