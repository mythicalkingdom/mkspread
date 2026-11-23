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

{ /File commands: Retrieve, Save, Combine, Xtract, Erase, List, Import,
  Directory. }
unit cmdfile;
{$mode objfpc}{$H+}

interface

uses Classes, commands, session;

procedure RegisterFileCommands(C: TCommands);

{ Loads a worksheet file into the session (used by File Retrieve and by the
  command line).  Returns '' or an error message; warnings go to the
  session's message line. }
function RetrieveFile(S: TSession; const fileName: string): string;

{ names of the files in the current directory matching patterns such as
  '*.WK1;*.WKS' (case-insensitive), sorted }
procedure ListFiles(const patterns: string; items: TStrings; withDirs: Boolean = False);

{ puts such a list in the choice line so one can be picked (F3 in a file prompt) }
procedure OpenFileChoices(S: TSession; const patterns: string; quiet: Boolean = False);

implementation

uses SysUtils, sheet, wk1, formula, calc, editops, textimport, cellfmt, printing;

const
  WorksheetPatterns = '*.WK1;*.WKS';

{ ---------------------------------------------------------------- files }

function MatchesPattern(const name, pattern: string): Boolean;
var
  n, p: string;
  star: Integer;
begin
  n := UpperCase(name);
  p := UpperCase(pattern);
  if p = '*' then exit(True);
  star := Pos('*', p);
  if star = 0 then exit(n = p);
  Result := (Copy(n, 1, star - 1) = Copy(p, 1, star - 1)) and
            (Length(n) >= star - 1 + Length(p) - star) and
            (Copy(n, Length(n) - (Length(p) - star) + 1, MaxInt) = Copy(p, star + 1, MaxInt));
  if (star < Length(p)) and (Copy(p, star + 1, 1) = '.') and (Pos('.', n) = 0) then Result := False;
end;

procedure ListFiles(const patterns: string; items: TStrings; withDirs: Boolean);
var
  sr: TSearchRec;
  pats: TStringArray;
  i: Integer;
  sl, dl: TStringList;
  ok: Boolean;
begin
  sl := TStringList.Create;
  dl := TStringList.Create;
  try
    pats := patterns.Split([';']);
    if FindFirst('*', faAnyFile and not faDirectory, sr) = 0 then
    begin
      repeat
        ok := False;
        for i := 0 to High(pats) do
          if MatchesPattern(sr.Name, pats[i]) then ok := True;
        if ok then sl.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    sl.Sort;
    if withDirs then
    begin
      if FindFirst('*', faDirectory, sr) = 0 then
      begin
        repeat
          if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..') then
            dl.Add(UpperCase(sr.Name) + '/');
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;
      dl.Sort;
      sl.AddStrings(dl);
      if GetCurrentDir <> '/' then sl.Add('../');
    end;
    items.Assign(sl);
  finally
    sl.Free;
    dl.Free;
  end;
end;

procedure OpenFileChoices(S: TSession; const patterns: string; quiet: Boolean);
var
  items: TStringList;
begin
  items := TStringList.Create;
  try
    ListFiles(patterns, items, True);
    if items.Count = 0 then
    begin
      if not quiet then S.Msg := 'No files found';
      exit;
    end;
    S.ShowChoices(items, mPrompt);
  finally
    items.Free;
  end;
end;

{ The real name of a file given as typed: tries the default extensions and
  ignores case.  When nothing matches, the first candidate is returned. }
function ResolveFile(const typed, exts: string): string;
var
  name, dir, base: string;
  cands: TStringList;
  i: Integer;
  sr: TSearchRec;
begin
  name := Trim(typed);
  cands := TStringList.Create;
  try
    if (ExtractFileExt(name) <> '') or (exts = '') then cands.Add(name)
    else
      for i := 0 to High(exts.Split([';'])) do cands.Add(name + exts.Split([';'])[i]);
    if cands.Count = 0 then cands.Add(name);
    for i := 0 to cands.Count - 1 do
    begin
      if FileExists(cands[i]) then exit(cands[i]);
      dir := ExtractFilePath(cands[i]);
      base := UpperCase(ExtractFileName(cands[i]));
      if dir = '' then dir := '.';
      if FindFirst(IncludeTrailingPathDelimiter(dir) + '*', faAnyFile and not faDirectory, sr) = 0 then
      begin
        repeat
          if UpperCase(sr.Name) = base then
          begin
            Result := ExtractFilePath(cands[i]) + sr.Name;
            FindClose(sr);
            exit;
          end;
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;
    end;
    Result := cands[0];
  finally
    cands.Free;
  end;
end;

function IsWks(const fn: string): Boolean;
begin
  Result := UpperCase(ExtractFileExt(fn)) = '.WKS';
end;

{ ---------------------------------------------------------------- retrieve }

function RetrieveFile(S: TSession; const fileName: string): string;
var
  warn: TStringList;
  info: TFileInfo;
  g: TRange;
begin
  warn := TStringList.Create;
  try
    Result := LoadWorksheet(fileName, S.Sheet, warn, info);
    if Result <> '' then exit;
    S.ForgetUndo;
    CopyFilePrintSettings(S.Print, info.Print);       { the file's print settings (or the defaults) }
    S.FileName := fileName;
    S.CurCol := info.CursorCol;
    S.CurRow := info.CursorRow;
    S.LeftCol := 1;
    S.TopRow := 1;
    S.Calc.Recalc;
    S.Normalize;
    if S.Sheet.FindName('\0', g) then S.MacroRequest := '\0';       { autoexec macro }
    if warn.Count > 0 then
    begin
      S.Msg := warn[0];
      if warn.Count > 1 then S.Msg := S.Msg + Format(' (+%d more)', [warn.Count - 1]);
    end;
  finally
    warn.Free;
  end;
end;

procedure RetrieveDone(S: TSession; const path: string);
var
  p, msg: string;
begin
  p := ResolveFile(S.PromptStr, '.WK1;.WKS');
  if not FileExists(p) then
  begin
    S.Msg := 'File not found: ' + S.PromptStr;
    exit;
  end;
  msg := RetrieveFile(S, p);
  if msg <> '' then S.Msg := msg;
end;

procedure CmdRetrieve(S: TSession; const path: string);
begin
  S.AskText('Enter name of file to retrieve:', '', @RetrieveDone, path);
  S.PromptFilter := WorksheetPatterns;
  OpenFileChoices(S, S.PromptFilter, True);
end;

{ ---------------------------------------------------------------- save }

procedure DoSave(S: TSession; const p: string);
var
  info: TFileInfo;
  warn: TStringList;
  msg: string;
begin
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := S.CurCol;
  info.CursorRow := S.CurRow;
  info.LeftCol := S.LeftCol;
  info.TopRow := S.TopRow;
  info.Print := S.Print;
  warn := TStringList.Create;
  try
    msg := SaveWorksheet(p, S.Sheet, IsWks(p), info, warn);
    if msg <> '' then
      S.Msg := msg
    else
    begin
      S.FileName := p;
      if warn.Count > 0 then S.Msg := warn[0] else S.Msg := 'Saved ' + ExtractFileName(p);
    end;
  finally
    warn.Free;
  end;
end;

procedure SaveConfirmed(S: TSession; const path: string);
begin
  if S.ChoiceIndex = 1 then DoSave(S, S.PendStr);
end;

procedure SaveDone(S: TSession; const path: string);
var
  p: string;
begin
  if S.PromptStr = '' then exit;
  p := ResolveFile(S.PromptStr, '.WK1');
  if ExtractFileExt(p) = '' then p := p + '.WK1';
  if FileExists(p) then
  begin
    S.PendStr := p;
    S.AskChoice(['Cancel', 'Replace'], @SaveConfirmed, path);
  end
  else
    DoSave(S, p);
end;

procedure CmdSave(S: TSession; const path: string);
begin
  S.AskText('Enter name of file to save:', S.FileName, @SaveDone, path);
  S.PromptFilter := WorksheetPatterns;
  OpenFileChoices(S, S.PromptFilter, True);
end;

{ ---------------------------------------------------------------- xtract }

procedure XtractWrite(S: TSession; const p: string; xvalues: Boolean);
var
  tmp: TSheet;
  tc: TCalc;
  info: TFileInfo;
  msg: string;
begin
  tmp := TSheet.Create;
  try
    tmp.GlobalWidth := S.Sheet.GlobalWidth;
    tmp.GlobalFmt := S.Sheet.GlobalFmt;
    tmp.GlobalLabelPrefix := S.Sheet.GlobalLabelPrefix;
    tmp.ZeroDisplay := S.Sheet.ZeroDisplay;
    msg := CopyBetween(S.Sheet, S.Range, tmp, 1, 1, xvalues, True);
    if msg <> '' then
    begin
      S.Msg := msg;
      exit;
    end;
    tc := TCalc.Create(tmp);
    try
      tc.Recalc;
    finally
      tc.Free;
    end;
    FillChar(info, SizeOf(info), 0);
    info.CursorCol := 1; info.CursorRow := 1; info.LeftCol := 1; info.TopRow := 1;
    msg := SaveWorksheet(p, tmp, IsWks(p), info, nil);
    if msg <> '' then S.Msg := msg else S.Msg := 'Extracted to ' + ExtractFileName(p);
  finally
    tmp.Free;
  end;
end;

procedure XtractConfirmed(S: TSession; const path: string);
begin
  if S.ChoiceIndex = 1 then XtractWrite(S, S.PendStr, path.EndsWith('Values'));
end;

procedure XtractRange(S: TSession; const path: string);
begin
  if FileExists(S.PendStr) then
    S.AskChoice(['Cancel', 'Replace'], @XtractConfirmed, path)
  else
    XtractWrite(S, S.PendStr, path.EndsWith('Values'));
end;

procedure XtractName(S: TSession; const path: string);
var
  p: string;
begin
  if S.PromptStr = '' then exit;
  p := ResolveFile(S.PromptStr, '.WK1');
  if ExtractFileExt(p) = '' then p := p + '.WK1';
  S.PendStr := p;
  S.AskRange('Enter xtract range:', @XtractRange, path);
end;

procedure CmdXtract(S: TSession; const path: string);
begin
  S.AskText('Enter xtract file name:', '', @XtractName, path);
  S.PromptFilter := WorksheetPatterns;
  OpenFileChoices(S, S.PromptFilter, True);
end;

{ ---------------------------------------------------------------- combine }

procedure CombineApply(S: TSession; const fileName, rangeSpec, path: string);
var
  tmp: TSheet;
  tc: TCalc;
  info: TFileInfo;
  g: TRange;
  r, c, nr, nc, mr, mc: Integer;
  cell, mine: TCell;
  d, e: Double;
  msg: string;
begin
  tmp := TSheet.Create;
  try
    msg := LoadWorksheet(fileName, tmp, nil, info);
    if msg <> '' then begin S.Msg := msg; exit; end;
    tc := TCalc.Create(tmp);
    try
      tc.Recalc;
    finally
      tc.Free;
    end;
    if rangeSpec = '' then
    begin
      tmp.UsedExtent(mr, mc);
      g := NormRange(1, 1, mr, mc);
    end
    else if not ParseRangeText(tmp, rangeSpec, g) then
    begin
      S.Msg := 'That range is not in the file';
      exit;
    end;
    if (S.CurRow + (g.R2 - g.R1) > MaxRow) or (S.CurCol + (g.C2 - g.C1) > MaxCol) then
    begin
      S.Msg := 'It does not fit below and to the right of the pointer';
      exit;
    end;
    S.SaveUndo;
    for r := g.R1 to g.R2 do
      for c := g.C1 to g.C2 do
      begin
        cell := tmp.Find(r, c);
        if (cell = nil) or (cell.Raw = '') then continue;      { blanks change nothing }
        nr := S.CurRow + (r - g.R1);
        nc := S.CurCol + (c - g.C1);
        if path.Contains(' Copy ') then
          CopyBetween(tmp, NormRange(r, c, r, c), S.Sheet, nr, nc, False, False)
        else if CellNumber(cell, d) then
        begin
          mine := S.Sheet.Find(nr, nc);
          e := 0;
          if (mine <> nil) and (mine.Raw <> '') then
          begin
            if not CellNumber(mine, e) then continue;          { labels are left alone }
          end;
          if path.Contains(' Add ') then e := e + d else e := e - d;
          S.Sheet.Put(nr, nc, NumToRaw(e));
        end;
      end;
  finally
    tmp.Free;
  end;
end;

procedure CombineRangeDone(S: TSession; const path: string);
begin
  CombineApply(S, S.PendStr, S.PromptStr, path);
end;

procedure CombineFileDone(S: TSession; const path: string);
var
  p: string;
begin
  if S.PromptStr = '' then exit;
  p := ResolveFile(S.PromptStr, '.WK1;.WKS');
  if not FileExists(p) then
  begin
    S.Msg := 'File not found: ' + S.PromptStr;
    exit;
  end;
  S.PendStr := p;
  if path.EndsWith('Entire-File') then
    CombineApply(S, p, '', path)
  else
    S.AskText('Enter range name or address:', '', @CombineRangeDone, path);
end;

procedure CmdCombine(S: TSession; const path: string);
begin
  S.AskText('Enter name of file to combine:', '', @CombineFileDone, path);
  S.PromptFilter := WorksheetPatterns;
  OpenFileChoices(S, S.PromptFilter, True);
end;

{ ---------------------------------------------------------------- import }

procedure ImportDone(S: TSession; const path: string);
var
  p, msg: string;
begin
  if S.PromptStr = '' then exit;
  p := ResolveFile(S.PromptStr, '');
  if not FileExists(p) then
  begin
    S.Msg := 'File not found: ' + S.PromptStr;
    exit;
  end;
  S.SaveUndo;
  if path.EndsWith('Text') then msg := ImportLines(S.Sheet, p, S.CurRow, S.CurCol)
  else msg := ImportNumbers(S.Sheet, p, S.CurRow, S.CurCol);
  if msg <> '' then S.Msg := msg;
end;

procedure CmdImport(S: TSession; const path: string);
begin
  S.AskText('Enter name of file to import:', '', @ImportDone, path);
  S.PromptFilter := '*';
  OpenFileChoices(S, S.PromptFilter, True);
end;

{ ---------------------------------------------------------------- directory, list, erase }

procedure DirectoryDone(S: TSession; const path: string);
begin
  if S.PromptStr = '' then exit;
  if not SetCurrentDir(S.PromptStr) then S.Msg := 'Cannot change to that directory';
end;

procedure CmdDirectory(S: TSession; const path: string);
begin
  S.AskText('Enter current directory:', GetCurrentDir, @DirectoryDone, path);
end;

function PatternsFor(const path: string): string;
begin
  if path.EndsWith('Worksheet') then Result := WorksheetPatterns
  else if path.EndsWith('Print') then Result := '*.PRN'
  else if path.EndsWith('Graph') then Result := '*.PIC'
  else Result := '*';
end;

procedure CmdList(S: TSession; const path: string);
var
  items: TStringList;
begin
  items := TStringList.Create;
  try
    ListFiles(PatternsFor(path), items);
    if items.Count = 0 then
      S.Msg := 'No files found'
    else
      S.ShowChoices(items, mReady);
  finally
    items.Free;
  end;
end;

procedure EraseDone(S: TSession; const path: string);
var
  p: string;
begin
  if S.PromptStr = '' then exit;
  if path.EndsWith('Worksheet') then p := ResolveFile(S.PromptStr, '.WK1;.WKS')
  else if path.EndsWith('Print') then p := ResolveFile(S.PromptStr, '.PRN')
  else if path.EndsWith('Graph') then p := ResolveFile(S.PromptStr, '.PIC')
  else p := ResolveFile(S.PromptStr, '');
  if not FileExists(p) then
    S.Msg := 'File not found: ' + S.PromptStr
  else if DeleteFile(p) then
    S.Msg := 'Erased ' + ExtractFileName(p)
  else
    S.Msg := 'Cannot erase ' + ExtractFileName(p);
end;

procedure CmdErase(S: TSession; const path: string);
begin
  S.AskText('Enter name of file to erase:', '', @EraseDone, path);
  S.PromptFilter := PatternsFor(path);
  OpenFileChoices(S, S.PromptFilter, True);
end;

procedure RegisterFileCommands(C: TCommands);
const
  Kinds: array[0..3] of string = ('Worksheet', 'Print', 'Graph', 'Other');
  Modes: array[0..2] of string = ('Copy', 'Add', 'Subtract');
  Scopes: array[0..1] of string = ('Entire-File', 'Named/Specified-Range');
var
  k, m: Integer;
begin
  C.Register('File Retrieve', @CmdRetrieve);
  C.Register('File Save', @CmdSave);
  C.Register('File Xtract Formulas', @CmdXtract);
  C.Register('File Xtract Values', @CmdXtract);
  C.Register('File Import Text', @CmdImport);
  C.Register('File Import Numbers', @CmdImport);
  C.Register('File Directory', @CmdDirectory);
  for k := 0 to 3 do
  begin
    C.Register('File List ' + Kinds[k], @CmdList);
    C.Register('File Erase ' + Kinds[k], @CmdErase);
  end;
  for m := 0 to 2 do
    for k := 0 to 1 do
      C.Register('File Combine ' + Modes[m] + ' ' + Scopes[k], @CmdCombine);
end;

end.
