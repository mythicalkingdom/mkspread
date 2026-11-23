{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }

{ /Worksheet Global Default: printer defaults, directory, international formats,
  clock, undo, beep.  Status shows them, Update saves them to the configuration
  file. }
unit cmddefault;
{$mode objfpc}{$H+}

interface

uses commands, session;

procedure RegisterDefaultCommands(C: TCommands);

{ the menu to come back to after a command in this part of the menu tree }
function DefaultReturnPath(const path: string): string;

implementation

uses SysUtils, Classes, config, defaults, helpdata;

const
  Base = 'Worksheet Global Default';

function Last(const path: string): string;
var
  k: Integer;
begin
  k := Length(path);
  while (k > 0) and (path[k] <> ' ') do Dec(k);
  Result := Copy(path, k + 1, MaxInt);
end;

function DefaultReturnPath(const path: string): string;
var
  w: TStringList;
  n: Integer;
begin
  Result := '';
  if Pos(Base, path) <> 1 then exit;
  w := TStringList.Create;
  try
    w.Delimiter := ' ';
    w.StrictDelimiter := True;
    w.DelimitedText := Copy(path, Length(Base) + 2, MaxInt);
    n := w.Count;
    if n = 0 then exit(Base);
    if w[0] = 'Quit' then exit('');
    if w[0] = 'Printer' then
    begin
      if (n = 2) and (w[1] = 'Quit') then exit(Base);
      exit(Base + ' Printer');
    end;
    if w[0] = 'Other' then
    begin
      if (n = 2) and (w[1] = 'Quit') then exit(Base);
      if (n >= 2) and (w[1] = 'International') then
      begin
        if (n = 3) and (w[2] = 'Quit') then exit(Base + ' Other');
        if (n >= 4) and (w[2] = 'Currency') and (n = 4) then exit(Base + ' Other International');
        if (n = 3) and (w[2] = 'Currency') then exit(Base + ' Other International Currency');
        exit(Base + ' Other International');
      end;
      exit(Base + ' Other');
    end;
    Result := Base;
  finally
    w.Free;
  end;
end;

procedure Changed(S: TSession);
begin
  ApplyConfig(S.Cfg);
end;

procedure NumberDone(S: TSession; const path: string);
var
  k: string;
begin
  k := Last(path);
  if k = 'Interface' then S.Cfg.PrintInterface := S.PromptNum
  else if k = 'Left' then S.Cfg.PrintLeft := S.PromptNum
  else if k = 'Right' then S.Cfg.PrintRight := S.PromptNum
  else if k = 'Top' then S.Cfg.PrintTop := S.PromptNum
  else if k = 'Bottom' then S.Cfg.PrintBottom := S.PromptNum
  else if k = 'Pg-Length' then S.Cfg.PrintLength := S.PromptNum;
  Changed(S);
end;

procedure TextDone(S: TSession; const path: string);
var
  k: string;
begin
  k := Last(path);
  if k = 'Setup' then S.Cfg.PrintSetup := S.PromptStr
  else if k = 'Name' then S.Cfg.PrintName := S.PromptStr
  else if k = 'Currency' then
  begin
    if S.PromptStr <> '' then S.Cfg.CurrencySym := Copy(S.PromptStr, 1, 4);
  end
  else if k = 'Directory' then
  begin
    if S.PromptStr = '' then exit;
    if DirectoryExists(S.PromptStr) and SetCurrentDir(S.PromptStr) then S.Cfg.Directory := GetCurrentDir
    else S.Msg := 'No such directory';
  end;
  Changed(S);
end;

procedure CmdDefault(S: TSession; const path: string);
var
  k, p: string;
begin
  k := Last(path);
  p := Copy(path, Length(Base) + 2, MaxInt);
  if p = 'Printer Interface' then S.AskNumber('Enter printer interface number (1..8):', S.Cfg.PrintInterface, 1, 8, @NumberDone, path)
  else if p = 'Printer Left' then S.AskNumber('Enter left margin (0..240):', S.Cfg.PrintLeft, 0, 240, @NumberDone, path)
  else if p = 'Printer Right' then S.AskNumber('Enter right margin (0..240):', S.Cfg.PrintRight, 0, 240, @NumberDone, path)
  else if p = 'Printer Top' then S.AskNumber('Enter top margin (0..32):', S.Cfg.PrintTop, 0, 32, @NumberDone, path)
  else if p = 'Printer Bottom' then S.AskNumber('Enter bottom margin (0..32):', S.Cfg.PrintBottom, 0, 32, @NumberDone, path)
  else if p = 'Printer Pg-Length' then S.AskNumber('Enter page length (1..100):', S.Cfg.PrintLength, 1, 100, @NumberDone, path)
  else if p = 'Printer Setup' then S.AskText('Enter setup string:', S.Cfg.PrintSetup, @TextDone, path)
  else if p = 'Printer Name' then S.AskText('Enter the print queue name (empty = default):', S.Cfg.PrintName, @TextDone, path)
  else if p = 'Printer Auto-LF No' then S.Cfg.AutoLF := False
  else if p = 'Printer Auto-LF Yes' then S.Cfg.AutoLF := True
  else if p = 'Printer Wait No' then S.Cfg.PrintWait := False
  else if p = 'Printer Wait Yes' then S.Cfg.PrintWait := True
  else if p = 'Directory' then S.AskText('Enter default directory:', GetCurrentDir, @TextDone, path)
  else if p = 'Status' then
  begin
    HelpSetTopic('status', 'Default settings', DefaultsStatus(S.Cfg));
    S.HelpReturn := mReady;
    S.HelpBack.Clear;
    S.HelpId := 'status';
    S.HelpScroll := 0;
    S.HelpSel := 0;
    S.Mode := mHelp;
  end
  else if p = 'Update' then
  begin
    p := SaveConfig(S.Cfg);
    if p = '' then S.Msg := 'Settings saved to ' + ConfigPath else S.Msg := p;
  end
  else if Pos('Other International Punctuation ', p) = 1 then
    S.Cfg.Punctuation := Ord(k[1]) - 65
  else if p = 'Other International Currency' then
    S.AskText('Enter currency symbol:', S.Cfg.CurrencySym, @TextDone, path)
  else if p = 'Other International Currency Prefix' then S.Cfg.CurrencyAfter := False
  else if p = 'Other International Currency Suffix' then S.Cfg.CurrencyAfter := True
  else if Pos('Other International Date ', p) = 1 then S.Cfg.DateStyle := Ord(k[1]) - 65
  else if Pos('Other International Time ', p) = 1 then S.Cfg.TimeStyle := Ord(k[1]) - 65
  else if p = 'Other International Negative Parentheses' then S.Cfg.NegParen := True
  else if p = 'Other International Negative Sign' then S.Cfg.NegParen := False
  else if p = 'Other Help Instant' then S.Cfg.HelpRemovable := False
  else if p = 'Other Help Removable' then S.Cfg.HelpRemovable := True
  else if p = 'Other Clock Standard' then S.Cfg.Clock := 0
  else if p = 'Other Clock International' then S.Cfg.Clock := 1
  else if p = 'Other Clock None' then S.Cfg.Clock := 2
  else if p = 'Other Undo Enable' then S.Cfg.UndoOn := True
  else if p = 'Other Undo Disable' then S.Cfg.UndoOn := False
  else if p = 'Other Beep No' then S.Cfg.Beep := False
  else if p = 'Other Beep Yes' then S.Cfg.Beep := True;
  Changed(S);
end;

procedure RegisterDefaultCommands(C: TCommands);
const
  Items: array[0..53] of string = (
    'Printer Interface', 'Printer Left', 'Printer Right', 'Printer Top', 'Printer Bottom',
    'Printer Pg-Length', 'Printer Setup', 'Printer Name', 'Printer Auto-LF No', 'Printer Auto-LF Yes',
    'Printer Wait No', 'Printer Wait Yes', 'Printer Quit', 'Directory', 'Status', 'Update', 'Quit',
    'Other International Punctuation A', 'Other International Punctuation B',
    'Other International Punctuation C', 'Other International Punctuation D',
    'Other International Punctuation E', 'Other International Punctuation F',
    'Other International Punctuation G', 'Other International Punctuation H',
    'Other International Currency', 'Other International Currency Prefix', 'Other International Currency Suffix',
    'Other International Date A', 'Other International Date B', 'Other International Date C',
    'Other International Date D', 'Other International Time A', 'Other International Time B',
    'Other International Time C', 'Other International Time D',
    'Other International Negative Parentheses', 'Other International Negative Sign',
    'Other International Quit', 'Other Help Instant', 'Other Help Removable',
    'Other Clock Standard', 'Other Clock International', 'Other Clock None',
    'Other Undo Enable', 'Other Undo Disable', 'Other Beep No', 'Other Beep Yes', 'Other Quit',
    '', '', '', '', '');
var
  k: Integer;
begin
  for k := 0 to High(Items) do
    if Items[k] <> '' then C.Register(Base + ' ' + Items[k], @CmdDefault);
end;

end.
