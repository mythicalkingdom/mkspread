{ Generates PRINT.WK1: a worksheet whose macro \R prints a series of jobs to files
  P01.PRN, P02.PRN ... with /Print File, for checking mkspread's /Print against the
  original program.  It also writes the files mkspread itself produces for the same
  macros into a directory, so the two sets can be compared (tests/cmp_print.py).

  Usage: make_printsheet <PRINT.WK1> <directory for mkspread's .PRN files>

  In the original program: delete old P*.PRN files, retrieve PRINT.WK1, press Alt-R.
  Each job is a macro (TST01 .. ) and can also be run alone with Alt-F3. }
program make_printsheet;
{$mode objfpc}{$H+}

uses SysUtils, Classes, sheet, formula, cellfmt, session, commands, controller, macro, wk1;

type
  TJob = record
    Desc, Keys: string;
  end;

var
  Jobs: array of TJob;

procedure Job(const desc, keys: string);
var
  n: Integer;
begin
  n := Length(Jobs);
  SetLength(Jobs, n + 1);
  Jobs[n].Desc := desc;
  Jobs[n].Keys := keys;
end;

procedure DefineJobs;
begin
  SetLength(Jobs, 0);
  Job('Default layout', 'rA101..D108~g');
  Job('Header and footer', 'rA101..D108~ohReport|Sales|Page #~fSeen at #~qg');
  Job('Margins and page length', 'rA101..J108~omr50~ml2~mt1~mb1~p30~qg');
  Job('Wide range in groups of columns', 'rA101..J108~g');
  Job('Border column and border row', 'rC102..J108~obcA101..A108~brA101..J101~qg');
  Job('Page-break row and an unprinted row', 'rA120..A131~g');
  Job('Several pages with a header', 'rA150..A215~ohTop #~fEnd #~qg');
  Job('Cell-Formulas', 'rA101..D108~oocqg');
  Job('Unformatted', 'rA101..D108~oouqg');
  Job('Setup string, Line and Page', 'rA101..B103~osXY\015Z~qlgp');
  Job('Label prefixes and number formats', 'rA110..J113~g');
  Job('Short pages', 'rA150..A175~op20~qg');
  Job('No top or bottom margin', 'rA101..D104~omt0~mb0~ml0~mr30~qg');
end;

procedure BuildData(S: TSession);
var
  r, c: Integer;
  cell: TCell;
  hdr: array[0..9] of string = ('Item', 'Price', 'Qty', 'Rate', 'Date', 'Ratio', 'Value', 'Delta', 'Note', 'Flag');
begin
  for c := 1 to 10 do S.Sheet.SetColWidth(c, 12);
  for c := 1 to 10 do S.Sheet.Put(101, c, '''' + hdr[c - 1]);
  for r := 102 to 108 do
  begin
    S.Sheet.Put(r, 1, '''Widget ' + IntToStr(r - 101));
    cell := S.Sheet.Put(r, 2, IntToStr((r - 100) * 10) + '.5');
    cell.Fmt := MakeFormat(fkCurrency, 2);
    cell := S.Sheet.Put(r, 3, IntToStr((r - 100) * 1234));
    cell.Fmt := MakeFormat(fkComma, 0);
    cell := S.Sheet.Put(r, 4, '0.' + IntToStr(r - 95));
    cell.Fmt := MakeFormat(fkPercent, 0);
    cell := S.Sheet.Put(r, 5, IntToStr(33000 + r * 7));
    cell.Fmt := MakeFormat(fkDate, 1);
    cell := S.Sheet.Put(r, 6, '+' + IntToStr(r - 100) + '/3');
    cell.Fmt := MakeFormat(fkFixed, 3);
    S.Sheet.Put(r, 7, '12.3456');
    S.Sheet.Put(r, 8, '-5.5');
    S.Sheet.Put(r, 9, '''note ' + IntToStr(r - 101));
    S.Sheet.Put(r, 10, '+B' + IntToStr(r) + '*C' + IntToStr(r));
  end;
  { rows with page breaks and a row that is not printed }
  for r := 120 to 131 do S.Sheet.Put(r, 1, '''line ' + IntToStr(r - 119));
  S.Sheet.Put(124, 1, '|::');
  S.Sheet.Put(127, 1, '|this note is not printed');
  { labels and formats }
  S.Sheet.Put(110, 1, '''left');
  S.Sheet.Put(110, 2, '"right');
  S.Sheet.Put(110, 3, '^mid');
  S.Sheet.Put(110, 4, '\=');
  S.Sheet.Put(110, 5, '''a long label that runs over the empty cells to its right');
  S.Sheet.Put(111, 1, '1234.5678');
  S.Sheet.Put(111, 2, '1234.5678').Fmt := MakeFormat(fkFixed, 0);
  S.Sheet.Put(111, 3, '1234.5678').Fmt := MakeFormat(fkSci, 2);
  S.Sheet.Put(111, 4, '-1234.5678').Fmt := MakeFormat(fkCurrency, 2);
  S.Sheet.Put(111, 5, '-1234.5678').Fmt := MakeFormat(fkComma, 1);
  S.Sheet.Put(111, 6, '3').Fmt := MakeFormat(fkPlusMinus, 0);
  S.Sheet.Put(111, 7, '0.256').Fmt := MakeFormat(fkPercent, 1);
  S.Sheet.Put(111, 8, '+A111*2').Fmt := MakeFormat(fkText, 0);
  S.Sheet.Put(111, 9, '12').Fmt := MakeFormat(fkHidden, 0);
  S.Sheet.Put(111, 10, '123456789012');
  S.Sheet.Put(112, 1, '0');
  S.Sheet.Put(112, 2, '1/0');
  S.Sheet.Put(112, 3, '@NA');
  S.Sheet.Put(112, 4, '"quoted');
  S.Sheet.Put(113, 1, '''last row');
  { many rows for several pages }
  for r := 150 to 215 do S.Sheet.Put(r, 1, IntToStr(r - 149) + '.25');
end;

procedure BuildMacros(S: TSession);
var
  t, mr, p, i: Integer;
  line, master: string;
begin
  mr := 7;
  master := '';
  for t := 0 to High(Jobs) do
  begin
    S.Sheet.Put(7 + t, 5, '''' + Format('P%.2d  ', [t + 1]) + Jobs[t].Desc);
    S.Sheet.SetName(Format('TST%.2d', [t + 1]), NormRange(mr, 19, mr, 19));
    master := master + Format('{TST%.2d}', [t + 1]);
    line := '{ESC}{ESC}{ESC}{ESC}{ESC}/pfP' + Format('%.2d', [t + 1]) + '~ca' + Jobs[t].Keys + 'q';
    while Length(line) > 0 do
    begin
      p := Length(line);
      if p > 70 then
      begin
        p := 70;
        while (p > 1) and (line[p] <> '~') do Dec(p);
        if p <= 1 then p := 70;
      end;
      S.Sheet.Put(mr, 19, '''' + Copy(line, 1, p));
      Inc(mr);
      line := Copy(line, p + 1, MaxInt);
    end;
    Inc(mr);
  end;
  S.Sheet.SetName('\R', NormRange(1, 19, 1, 19));
  i := 1;
  mr := 1;
  while i <= Length(master) do
  begin
    p := i + 60;
    if p > Length(master) then p := Length(master) + 1
    else while (p > i) and (master[p - 1] <> '}') do Dec(p);
    S.Sheet.Put(mr, 19, '''' + Copy(master, i, p - i));
    Inc(mr);
    i := p;
  end;
end;

var
  S: TSession;
  Ctl: TController;
  Cmds: TCommands;
  M: TMacro;
  info: TFileInfo;
  w: TStringList;
  msg, outDir, here: string;
  i: Integer;
begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: make_printsheet PRINT.WK1 expected-directory');
    Halt(2);
  end;
  DefineJobs;
  outDir := ParamStr(2);
  ForceDirectories(outDir);
  here := GetCurrentDir;

  S := TSession.Create;
  S.Sheet.SetColWidth(5, 41);
  S.Sheet.SetColWidth(19, 40);
  S.Sheet.Put(1, 1, '''mkspread /Print test: delete P*.PRN, then press Alt-R; compare the P*.PRN files');
  S.Sheet.Put(2, 1, '''with the ones from mkspread (tests/cmp_print.py).  Data is at rows 101 and below.');
  S.Sheet.Put(5, 5, '''File and test');
  BuildData(S);
  BuildMacros(S);
  S.Sheet.SetColWidth(1, 12);

  { run the macros here to make mkspread's files, in the output directory }
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);
  M := TMacro.Create(S);
  S.Calc.Recalc;
  for i := 1 to Length(Jobs) do
    if FileExists(outDir + Format('/P%.2d.PRN', [i])) then DeleteFile(outDir + Format('/P%.2d.PRN', [i]));
  SetCurrentDir(outDir);
  S.MacroRequest := '\R';
  M.RunSync(Ctl);
  SetCurrentDir(here);
  if M.Active then
  begin
    WriteLn('the master macro did not finish');
    Halt(1);
  end;
  for i := 1 to Length(Jobs) do
    if not FileExists(outDir + Format('/P%.2d.PRN', [i])) then
      WriteLn('warning: mkspread did not produce P', Format('%.2d', [i]), '.PRN');

  w := TStringList.Create;
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1; info.CursorRow := 1; info.LeftCol := 1; info.TopRow := 1;
  msg := SaveWorksheet(ParamStr(1), S.Sheet, False, info, w);
  if msg <> '' then begin WriteLn(msg); Halt(1); end;
  WriteLn('wrote ', ParamStr(1), ': ', Length(Jobs), ' print jobs; mkspread output in ', outDir);
end.
