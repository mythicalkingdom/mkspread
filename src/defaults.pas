{ mkspread - a terminal spreadsheet for users of classic DOS spreadsheets.
  Copyright (C) 2026 The mkspread authors  (GPL-3.0-or-later; see COPYING) }

{ /Worksheet Global Default: puts the settings of a TConfig to work (number
  punctuation, currency, date and time styles, printer defaults) and describes them
  for the Status screen. }
unit defaults;
{$mode objfpc}{$H+}

interface

uses config;

procedure ApplyConfig(const cfg: TConfig);

{ the Status screen, lines separated by #10 }
function DefaultsStatus(const cfg: TConfig): string;

implementation

uses SysUtils, dates, printing;

procedure ApplyConfig(const cfg: TConfig);
var
  a: Char;
begin
  PunctuationChars(cfg.Punctuation, Intl.Decimal, Intl.Thousands, Intl.ArgSep);
  Intl.CurrencySym := cfg.CurrencySym;
  Intl.CurrencyAfter := cfg.CurrencyAfter;
  Intl.NegParen := cfg.NegParen;
  Intl.DateStyle := cfg.DateStyle;
  Intl.TimeStyle := cfg.TimeStyle;
  PrintDefaults.Left := cfg.PrintLeft;
  PrintDefaults.Right := cfg.PrintRight;
  PrintDefaults.Top := cfg.PrintTop;
  PrintDefaults.Bottom := cfg.PrintBottom;
  PrintDefaults.PgLength := cfg.PrintLength;
  PrintDefaults.Setup := cfg.PrintSetup;
  PrintDefaults.Name := cfg.PrintName;
end;

function IfThenStr(b: Boolean; const a, c: string): string;
begin
  if b then Result := a else Result := c;
end;

function YN(b: Boolean): string;
begin
  if b then Result := 'Yes' else Result := 'No';
end;

function DefaultsStatus(const cfg: TConfig): string;
const
  Dates: array[0..3] of string = ('A (MM/DD/YY)', 'B (DD/MM/YY)', 'C (DD.MM.YY)', 'D (YY-MM-DD)');
  Times: array[0..3] of string = ('A (HH:MM:SS)', 'B (HH.MM.SS)', 'C (HH,MM,SS)', 'D (HHhMMmSSs)');
  Clocks: array[0..2] of string = ('Standard', 'International', 'None');
var
  d, t, a: Char;
  neg, cur, nm, dir: string;
begin
  PunctuationChars(cfg.Punctuation, d, t, a);
  if cfg.NegParen then neg := 'Parentheses' else neg := 'Sign';
  if cfg.CurrencyAfter then cur := cfg.CurrencySym + ' (suffix)' else cur := cfg.CurrencySym + ' (prefix)';
  nm := cfg.PrintName;
  if nm = '' then nm := '(system default)';
  dir := cfg.Directory;
  if dir = '' then dir := '(where the program was started)';
  Result :=
    'Printer' + #10 +
    '  Interface ' + IntToStr(cfg.PrintInterface) + '    Auto linefeed ' + YN(cfg.AutoLF) + '    Wait ' + YN(cfg.PrintWait) + #10 +
    '  Margins  Left ' + IntToStr(cfg.PrintLeft) + '  Right ' + IntToStr(cfg.PrintRight) +
      '  Top ' + IntToStr(cfg.PrintTop) + '  Bottom ' + IntToStr(cfg.PrintBottom) + #10 +
    '  Page length ' + IntToStr(cfg.PrintLength) + #10 +
    '  Setup string ' + cfg.PrintSetup + #10 +
    '  Printer name ' + nm + #10 +
    #10 +
    'Directory ' + dir + #10 +
    #10 +
    'International' + #10 +
    '  Punctuation ' + Chr(65 + cfg.Punctuation) + '  (decimal ' + d + '  thousands ' + t + '  arguments ' + a + ')' + #10 +
    '  Currency ' + cur + #10 +
    '  Negative numbers ' + neg + #10 +
    '  Date ' + Dates[cfg.DateStyle] + '    Time ' + Times[cfg.TimeStyle] + #10 +
    #10 +
    'Other' + #10 +
    '  Clock ' + Clocks[cfg.Clock] + '    Undo ' + IfThenStr(cfg.UndoOn, 'Enabled', 'Disabled') + '    Beep ' + YN(cfg.Beep) + #10 +
    '  Help ' + IfThenStr(cfg.HelpRemovable, 'Removable', 'Instant') + #10 +
    #10 +
    'Update saves these settings; Esc leaves.';
end;

end.
