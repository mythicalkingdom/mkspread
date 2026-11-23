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

{ /Print commands and /Worksheet Page.  The text of a page is made in printing.pas;
  this unit keeps the settings, collects the output and sends it to a file or to
  the printer (through the print command: lp, or what MKSPREAD_PRINT_COMMAND says). }
unit cmdprint;
{$mode objfpc}{$H+}

interface

uses commands, session;

var
  PrintCommandOverride: string = '';     { used instead of the environment and lp (tests) }

procedure RegisterPrintCommands(C: TCommands);

{ sends the collected output (called when the print menu has been left) }
procedure FlushPrint(S: TSession);

{ the menu to come back to after a /Print command, or '' when the menu is done }
function PrintReturnPath(const path: string): string;

implementation

uses SysUtils, Classes, Process, sheet, editops, printing;

{ ---------------------------------------------------------------- output }

procedure Emit(S: TSession; const text: string);
begin
  if (S.Print.Pending = '') and not S.Print.SetupSent then
  begin
    S.Print.Pending := SetupBytes(S.Print.Setup);
    S.Print.SetupSent := True;
  end;
  S.Print.Pending := S.Print.Pending + text;
end;

function PrinterCommand: string;
begin
  Result := PrintCommandOverride;
  if Result = '' then Result := GetEnvironmentVariable('MKSPREAD_PRINT_COMMAND');
  if Result = '' then Result := 'lp';
end;

procedure FlushPrint(S: TSession);
var
  f: TFileStream;
  p: TProcess;
  data, reply: string;
  buf: array[0..1023] of Byte;
  n: Integer;
begin
  data := S.Print.Pending;
  if data = '' then exit;
  S.Print.Pending := '';
  S.Print.SetupSent := False;
  if S.Print.ToFile then
  begin
    try
      if FileExists(S.Print.FileName) then
        f := TFileStream.Create(S.Print.FileName, fmOpenReadWrite or fmShareDenyNone)
      else
        f := TFileStream.Create(S.Print.FileName, fmCreate);
      try
        f.Seek(0, soEnd);
        f.WriteBuffer(data[1], Length(data));
      finally
        f.Free;
      end;
      S.Msg := 'Printed to ' + S.Print.FileName;
    except
      on E: Exception do S.Msg := 'Cannot write ' + S.Print.FileName;
    end;
    exit;
  end;
  p := TProcess.Create(nil);
  try
    try
      p.Executable := '/bin/sh';
      p.Parameters.Add('-c');
      p.Parameters.Add(PrinterCommand);
      p.Options := [poUsePipes, poStderrToOutPut];
      p.Execute;
      p.Input.WriteBuffer(data[1], Length(data));
      p.CloseInput;
      reply := '';
      repeat
        n := p.Output.Read(buf, SizeOf(buf));
        if n > 0 then SetString(reply, PChar(@buf[0]), n);
      until n <= 0;
      p.WaitOnExit;
      if p.ExitStatus <> 0 then
        S.Msg := 'Printer command failed: ' + Trim(Copy(reply, 1, 60))
      else
        S.Msg := 'Sent to the printer';
    except
      on E: Exception do S.Msg := 'Cannot run the print command';
    end;
  finally
    p.Free;
  end;
end;

{ ---------------------------------------------------------------- menu flow }

function PrintReturnPath(const path: string): string;
var
  words: TStringList;
  base: string;
begin
  Result := '';
  if (Pos('Print Printer', path) <> 1) and (Pos('Print File', path) <> 1) then exit;
  words := TStringList.Create;
  try
    words.Delimiter := ' ';
    words.StrictDelimiter := True;
    words.DelimitedText := path;
    base := words[0] + ' ' + words[1];
    if words.Count <= 2 then exit(base);            { choosing Printer or File: open its menu }
    if words[2] = 'Options' then
    begin
      if (words.Count = 4) and (words[3] = 'Quit') then exit(base);
      exit(base + ' Options');
    end;
    if words[2] = 'Quit' then exit('');
    Result := base;
  finally
    words.Free;
  end;
end;

{ ---------------------------------------------------------------- settings }

procedure PrinterChosen(S: TSession; const path: string);
begin
  S.Print.ToFile := False;
end;

procedure FileConfirmed(S: TSession; const path: string);
var
  f: TFileStream;
begin
  if S.ChoiceIndex <> 1 then exit;
  try
    f := TFileStream.Create(S.PendStr, fmCreate);
    f.Free;
    S.Print.ToFile := True;
    S.Print.FileName := S.PendStr;
  except
    S.Msg := 'Cannot create ' + S.PendStr;
  end;
end;

procedure FileNameDone(S: TSession; const path: string);
var
  p: string;
  f: TFileStream;
begin
  if S.PromptStr = '' then exit;
  p := S.PromptStr;
  if ExtractFileExt(p) = '' then p := p + '.PRN';
  if FileExists(p) then
  begin
    S.PendStr := p;
    S.AskChoice(['Cancel', 'Replace'], @FileConfirmed, path);
    exit;
  end;
  try
    f := TFileStream.Create(p, fmCreate);
    f.Free;
    S.Print.ToFile := True;
    S.Print.FileName := p;
  except
    S.Msg := 'Cannot create ' + p;
  end;
end;

procedure CmdFile(S: TSession; const path: string);
begin
  S.AskText('Enter print file name:', '', @FileNameDone, path);
  S.PromptFilter := '*.PRN';
end;

procedure RangeDone(S: TSession; const path: string);
begin
  S.Print.Range := S.Range;
  S.Print.RangeSet := True;
end;

procedure BorderDone(S: TSession; const path: string);
begin
  if path.EndsWith('Columns') then
  begin
    S.Print.BorderCols := S.Range;
    S.Print.BorderColsSet := True;
  end
  else
  begin
    S.Print.BorderRows := S.Range;
    S.Print.BorderRowsSet := True;
  end;
end;

procedure TextDone(S: TSession; const path: string);
begin
  if path.EndsWith('Header') then S.Print.Header := S.PromptStr
  else if path.EndsWith('Footer') then S.Print.Footer := S.PromptStr
  else S.Print.Setup := S.PromptStr;
end;

procedure NumberDone(S: TSession; const path: string);
begin
  if path.EndsWith('Left') then S.Print.Left := S.PromptNum
  else if path.EndsWith('Right') then S.Print.Right := S.PromptNum
  else if path.EndsWith('Top') then S.Print.Top := S.PromptNum
  else if path.EndsWith('Bottom') then S.Print.Bottom := S.PromptNum
  else S.Print.PgLength := S.PromptNum;
end;

procedure CmdPrint(S: TSession; const path: string);
var
  text, err: string;
begin
  if path.EndsWith('Options Header') then S.AskText('Enter header:', S.Print.Header, @TextDone, path)
  else if path.EndsWith('Options Footer') then S.AskText('Enter footer:', S.Print.Footer, @TextDone, path)
  else if path.EndsWith('Options Setup') then S.AskText('Enter setup string:', S.Print.Setup, @TextDone, path)
  else if path.EndsWith('Margins Left') then S.AskNumber('Enter left margin (0..240):', S.Print.Left, 0, 240, @NumberDone, path)
  else if path.EndsWith('Margins Right') then S.AskNumber('Enter right margin (0..240):', S.Print.Right, 0, 240, @NumberDone, path)
  else if path.EndsWith('Margins Top') then S.AskNumber('Enter top margin (0..32):', S.Print.Top, 0, 32, @NumberDone, path)
  else if path.EndsWith('Margins Bottom') then S.AskNumber('Enter bottom margin (0..32):', S.Print.Bottom, 0, 32, @NumberDone, path)
  else if path.EndsWith('Pg-Length') then S.AskNumber('Enter page length (1..100):', S.Print.PgLength, 1, 100, @NumberDone, path)
  else if path.EndsWith('Borders Columns') then S.AskRange('Enter border column range:', @BorderDone, path)
  else if path.EndsWith('Borders Rows') then S.AskRange('Enter border row range:', @BorderDone, path)
  else if path.EndsWith('Other As-Displayed') then S.Print.CellFormulas := False
  else if path.EndsWith('Other Cell-Formulas') then S.Print.CellFormulas := True
  else if path.EndsWith('Other Formatted') then S.Print.Unformatted := False
  else if path.EndsWith('Other Unformatted') then S.Print.Unformatted := True
  else if path.EndsWith('Clear All') then ResetPrint(S.Print)
  else if path.EndsWith('Clear Range') then S.Print.RangeSet := False
  else if path.EndsWith('Clear Borders') then
  begin
    S.Print.BorderColsSet := False;
    S.Print.BorderRowsSet := False;
  end
  else if path.EndsWith('Clear Format') then ResetPrintFormat(S.Print)
  else if path.EndsWith(' Range') then S.AskRange('Enter print range:', @RangeDone, path)
  else if path.EndsWith(' Line') then
  begin
    Emit(S, #10);
    Inc(S.Print.LinePos);
    if S.Print.LinePos >= S.Print.PgLength then S.Print.LinePos := 0;
  end
  else if path.EndsWith(' Page') then
  begin
    Emit(S, #12);
    S.Print.LinePos := 0;
  end
  else if path.EndsWith(' Align') then S.Print.LinePos := 0
  else if path.EndsWith(' Go') then
  begin
    text := PrintRangeText(S.Sheet, S.Print, err);
    if err <> '' then
    begin
      S.Msg := err;
      exit;
    end;
    Emit(S, text);
    S.Print.LinePos := 0;
  end;
end;

{ /Worksheet Page: a row holding a page break (:: after the | prefix) above the pointer }
procedure CmdWorksheetPage(S: TSession; const path: string);
var
  msg: string;
begin
  S.SaveUndo;
  msg := InsertRows(S.Sheet, S.CurRow, 1);
  if msg <> '' then
  begin
    S.Msg := msg;
    exit;
  end;
  S.Sheet.Put(S.CurRow, S.CurCol, '|::');
end;

const
  Subs: array[0..21] of string = (
    'Range', 'Line', 'Page', 'Align', 'Go', 'Quit',
    'Options Header', 'Options Footer', 'Options Setup', 'Options Pg-Length', 'Options Quit',
    'Options Margins Left', 'Options Margins Right', 'Options Margins Top', 'Options Margins Bottom',
    'Options Borders Columns', 'Options Borders Rows',
    'Options Other As-Displayed', 'Options Other Cell-Formulas', 'Options Other Formatted',
    'Options Other Unformatted', 'Clear All');
  MoreSubs: array[0..2] of string = ('Clear Range', 'Clear Borders', 'Clear Format');

procedure RegisterPrintCommands(C: TCommands);
var
  k, d: Integer;
  pre: string;
begin
  for d := 0 to 1 do
  begin
    if d = 0 then pre := 'Print Printer ' else pre := 'Print File ';
    for k := 0 to High(Subs) do C.Register(pre + Subs[k], @CmdPrint);
    for k := 0 to High(MoreSubs) do C.Register(pre + MoreSubs[k], @CmdPrint);
  end;
  C.Register('Print Printer', @PrinterChosen);
  C.Register('Print File', @CmdFile);
  C.Register('Worksheet Page', @CmdWorksheetPage);
end;

end.
