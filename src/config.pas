{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }

{ The configuration file: ~/.config/mkspread/mkspread.conf (or under
  $XDG_CONFIG_HOME).  Lines of  key = value ; # starts a comment. }
unit config;
{$mode objfpc}{$H+}

interface

type
  TConfig = record
    AutosaveMinutes: Integer;      { 0 = off: save the worksheet to its file this often }
    RecoverySeconds: Integer;      { 0 = off: write the recovery file this often when there are changes }
    Expand: Boolean;               { use the whole terminal }
  end;

function ConfigDir: string;
function ConfigPath: string;
procedure DefaultConfig(out cfg: TConfig);

{ applies the lines of a configuration text to cfg; returns the problems found, one per line }
function ParseConfig(const text: string; var cfg: TConfig): string;

{ reads the file when there is one }
procedure LoadConfig(var cfg: TConfig; out problems: string);

implementation

uses SysUtils, Classes;

function ConfigDir: string;
var
  d: string;
begin
  d := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if d = '' then d := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.config';
  Result := IncludeTrailingPathDelimiter(d) + 'mkspread';
end;

function ConfigPath: string;
begin
  Result := IncludeTrailingPathDelimiter(ConfigDir) + 'mkspread.conf';
end;

procedure DefaultConfig(out cfg: TConfig);
begin
  cfg.AutosaveMinutes := 0;
  cfg.RecoverySeconds := 30;
  cfg.Expand := False;
end;

function YesNo(const v: string; out b: Boolean): Boolean;
var
  s: string;
begin
  s := LowerCase(v);
  Result := True;
  if (s = 'yes') or (s = 'true') or (s = 'on') or (s = '1') then b := True
  else if (s = 'no') or (s = 'false') or (s = 'off') or (s = '0') then b := False
  else Result := False;
end;

function ParseConfig(const text: string; var cfg: TConfig): string;
var
  lines: TStringList;
  i, p, n: Integer;
  line, key, val: string;
  b: Boolean;
begin
  Result := '';
  lines := TStringList.Create;
  try
    lines.Text := text;
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      p := Pos('#', line);
      if p > 0 then line := Trim(Copy(line, 1, p - 1));
      if line = '' then continue;
      p := Pos('=', line);
      if p = 0 then
      begin
        Result := Result + Format('line %d: expected key = value', [i + 1]) + LineEnding;
        continue;
      end;
      key := LowerCase(Trim(Copy(line, 1, p - 1)));
      val := Trim(Copy(line, p + 1, MaxInt));
      if key = 'autosave' then
      begin
        if TryStrToInt(val, n) and (n >= 0) and (n <= 1440) then cfg.AutosaveMinutes := n
        else Result := Result + Format('line %d: autosave is a number of minutes, 0 to 1440', [i + 1]) + LineEnding;
      end
      else if key = 'recovery' then
      begin
        if TryStrToInt(val, n) and (n >= 0) and (n <= 86400) then cfg.RecoverySeconds := n
        else Result := Result + Format('line %d: recovery is a number of seconds, 0 to 86400', [i + 1]) + LineEnding;
      end
      else if key = 'expand' then
      begin
        if YesNo(val, b) then cfg.Expand := b
        else Result := Result + Format('line %d: expand is yes or no', [i + 1]) + LineEnding;
      end
      else
        Result := Result + Format('line %d: unknown setting %s', [i + 1, key]) + LineEnding;
    end;
  finally
    lines.Free;
  end;
end;

procedure LoadConfig(var cfg: TConfig; out problems: string);
var
  sl: TStringList;
begin
  problems := '';
  if not FileExists(ConfigPath) then exit;
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(ConfigPath);
      problems := ParseConfig(sl.Text, cfg);
    except
      problems := 'cannot read ' + ConfigPath;
    end;
  finally
    sl.Free;
  end;
end;

end.
