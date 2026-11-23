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
    { /Worksheet Global Default }
    PrintInterface: Integer;       { 1..8, kept for compatibility }
    AutoLF, PrintWait: Boolean;
    PrintLeft, PrintRight, PrintTop, PrintBottom, PrintLength: Integer;
    PrintSetup, PrintName: string;
    Directory: string;
    Punctuation: Integer;          { 0..7 = A..H }
    CurrencySym: string;
    CurrencyAfter: Boolean;
    NegParen: Boolean;
    DateStyle, TimeStyle: Integer; { 0..3 = A..D }
    Clock: Integer;                { 0 standard, 1 international, 2 none }
    UndoOn: Boolean;
    Beep: Boolean;
    HelpRemovable: Boolean;
  end;

function ConfigDir: string;
function ConfigPath: string;
procedure DefaultConfig(out cfg: TConfig);

{ applies the lines of a configuration text to cfg; returns the problems found, one per line }
function ParseConfig(const text: string; var cfg: TConfig): string;

{ reads the file when there is one }
procedure LoadConfig(var cfg: TConfig; out problems: string);

{ the text of a configuration file for cfg; SaveConfig writes it (Update) }
function FormatConfig(const cfg: TConfig): string;
function SaveConfig(const cfg: TConfig): string;      { '' or an error message }

{ the separators of punctuation letter A..H (index 0..7) }
procedure PunctuationChars(idx: Integer; out decimal, thousands, argsep: Char);

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
  cfg.PrintInterface := 1;
  cfg.AutoLF := False;
  cfg.PrintWait := False;
  cfg.PrintLeft := 4;
  cfg.PrintRight := 76;
  cfg.PrintTop := 2;
  cfg.PrintBottom := 2;
  cfg.PrintLength := 66;
  cfg.PrintSetup := '';
  cfg.PrintName := '';
  cfg.Directory := '';
  cfg.Punctuation := 0;
  cfg.CurrencySym := '$';
  cfg.CurrencyAfter := False;
  cfg.NegParen := True;
  cfg.DateStyle := 0;
  cfg.TimeStyle := 0;
  cfg.Clock := 0;
  cfg.UndoOn := True;
  cfg.Beep := True;
  cfg.HelpRemovable := False;
end;

procedure PunctuationChars(idx: Integer; out decimal, thousands, argsep: Char);
begin
  case idx of
    1: begin decimal := ','; thousands := '.'; argsep := '.'; end;
    2: begin decimal := '.'; thousands := ' '; argsep := ','; end;
    3: begin decimal := ','; thousands := ' '; argsep := '.'; end;
    4: begin decimal := '.'; thousands := ','; argsep := ';'; end;
    5: begin decimal := ','; thousands := '.'; argsep := ';'; end;
    6: begin decimal := '.'; thousands := ' '; argsep := ';'; end;
    7: begin decimal := ','; thousands := ' '; argsep := ';'; end;
  else
    begin decimal := '.'; thousands := ','; argsep := ','; end;
  end;
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

function LetterIndex(const v: string; maxIdx: Integer): Integer;
begin
  Result := -1;
  if (Length(v) = 1) and (UpCase(v[1]) >= 'A') and (Ord(UpCase(v[1])) - 65 <= maxIdx) then
    Result := Ord(UpCase(v[1])) - 65;
end;

{ the /Worksheet Global Default settings; False when the key or value is wrong }
function ParseDefaultsKey(const key, val: string; var cfg: TConfig): Boolean;
var
  n: Integer;
  b: Boolean;
  s: string;
begin
  Result := True;
  s := LowerCase(val);
  if key = 'print-interface' then Result := TryStrToInt(val, n) and (n >= 1) and (n <= 8)
  else if key = 'print-left' then Result := TryStrToInt(val, n) and (n >= 0) and (n <= 240)
  else if key = 'print-right' then Result := TryStrToInt(val, n) and (n >= 0) and (n <= 240)
  else if key = 'print-top' then Result := TryStrToInt(val, n) and (n >= 0) and (n <= 32)
  else if key = 'print-bottom' then Result := TryStrToInt(val, n) and (n >= 0) and (n <= 32)
  else if key = 'print-length' then Result := TryStrToInt(val, n) and (n >= 1) and (n <= 100)
  else if (key = 'print-autolf') or (key = 'print-wait') or (key = 'undo') or (key = 'beep') then
    Result := YesNo(val, b)
  else if key = 'punctuation' then Result := LetterIndex(val, 7) >= 0
  else if (key = 'date-format') or (key = 'time-format') then Result := LetterIndex(val, 3) >= 0
  else if key = 'currency-position' then Result := (s = 'prefix') or (s = 'suffix')
  else if key = 'negative' then Result := (s = 'parentheses') or (s = 'sign')
  else if key = 'clock' then Result := (s = 'standard') or (s = 'international') or (s = 'none')
  else if key = 'help' then Result := (s = 'instant') or (s = 'removable')
  else if (key = 'print-setup') or (key = 'print-name') or (key = 'directory') or (key = 'currency') then
    Result := True
  else
    exit(False);
  if not Result then exit;
  if key = 'print-interface' then cfg.PrintInterface := StrToInt(val)
  else if key = 'print-left' then cfg.PrintLeft := StrToInt(val)
  else if key = 'print-right' then cfg.PrintRight := StrToInt(val)
  else if key = 'print-top' then cfg.PrintTop := StrToInt(val)
  else if key = 'print-bottom' then cfg.PrintBottom := StrToInt(val)
  else if key = 'print-length' then cfg.PrintLength := StrToInt(val)
  else if key = 'print-autolf' then begin YesNo(val, b); cfg.AutoLF := b; end
  else if key = 'print-wait' then begin YesNo(val, b); cfg.PrintWait := b; end
  else if key = 'undo' then begin YesNo(val, b); cfg.UndoOn := b; end
  else if key = 'beep' then begin YesNo(val, b); cfg.Beep := b; end
  else if key = 'print-setup' then cfg.PrintSetup := val
  else if key = 'print-name' then cfg.PrintName := val
  else if key = 'directory' then cfg.Directory := val
  else if key = 'currency' then cfg.CurrencySym := val
  else if key = 'punctuation' then cfg.Punctuation := LetterIndex(val, 7)
  else if key = 'date-format' then cfg.DateStyle := LetterIndex(val, 3)
  else if key = 'time-format' then cfg.TimeStyle := LetterIndex(val, 3)
  else if key = 'currency-position' then cfg.CurrencyAfter := s = 'suffix'
  else if key = 'negative' then cfg.NegParen := s = 'parentheses'
  else if key = 'clock' then
  begin
    if s = 'standard' then cfg.Clock := 0 else if s = 'international' then cfg.Clock := 1 else cfg.Clock := 2;
  end
  else if key = 'help' then cfg.HelpRemovable := s = 'removable';
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
      else if not ParseDefaultsKey(key, val, cfg) then
        Result := Result + Format('line %d: bad or unknown setting %s', [i + 1, key]) + LineEnding;
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

function YN(b: Boolean): string;
begin
  if b then Result := 'yes' else Result := 'no';
end;

function FormatConfig(const cfg: TConfig): string;
const
  Clocks: array[0..2] of string = ('standard', 'international', 'none');
var
  pos: string;
begin
  if cfg.CurrencyAfter then pos := 'suffix' else pos := 'prefix';
  Result :=
    '# mkspread settings.  /Worksheet Global Default Update writes this file;' + LineEnding +
    '# you can edit it by hand.  See docs/config.md.' + LineEnding +
    'autosave = ' + IntToStr(cfg.AutosaveMinutes) + LineEnding +
    'recovery = ' + IntToStr(cfg.RecoverySeconds) + LineEnding +
    'expand = ' + YN(cfg.Expand) + LineEnding +
    'directory = ' + cfg.Directory + LineEnding +
    'print-interface = ' + IntToStr(cfg.PrintInterface) + LineEnding +
    'print-autolf = ' + YN(cfg.AutoLF) + LineEnding +
    'print-left = ' + IntToStr(cfg.PrintLeft) + LineEnding +
    'print-right = ' + IntToStr(cfg.PrintRight) + LineEnding +
    'print-top = ' + IntToStr(cfg.PrintTop) + LineEnding +
    'print-bottom = ' + IntToStr(cfg.PrintBottom) + LineEnding +
    'print-length = ' + IntToStr(cfg.PrintLength) + LineEnding +
    'print-wait = ' + YN(cfg.PrintWait) + LineEnding +
    'print-setup = ' + cfg.PrintSetup + LineEnding +
    'print-name = ' + cfg.PrintName + LineEnding +
    'punctuation = ' + Chr(65 + cfg.Punctuation) + LineEnding +
    'currency = ' + cfg.CurrencySym + LineEnding +
    'currency-position = ' + pos + LineEnding;
  if cfg.NegParen then Result := Result + 'negative = parentheses' + LineEnding
  else Result := Result + 'negative = sign' + LineEnding;
  Result := Result +
    'date-format = ' + Chr(65 + cfg.DateStyle) + LineEnding +
    'time-format = ' + Chr(65 + cfg.TimeStyle) + LineEnding +
    'clock = ' + Clocks[cfg.Clock] + LineEnding +
    'undo = ' + YN(cfg.UndoOn) + LineEnding +
    'beep = ' + YN(cfg.Beep) + LineEnding;
  if cfg.HelpRemovable then Result := Result + 'help = removable' + LineEnding
  else Result := Result + 'help = instant' + LineEnding;
end;

function SaveConfig(const cfg: TConfig): string;
var
  sl: TStringList;
begin
  Result := '';
  sl := TStringList.Create;
  try
    try
      if not ForceDirectories(ConfigDir) then exit('Cannot make ' + ConfigDir);
      sl.Text := FormatConfig(cfg);
      sl.SaveToFile(ConfigPath);
    except
      Result := 'Cannot write ' + ConfigPath;
    end;
  finally
    sl.Free;
  end;
end;

end.
