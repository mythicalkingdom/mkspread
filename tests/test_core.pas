{ Unit tests for the terminal-independent core: storage, formatting, menus,
  key queue and the controller driven purely by logical keys. }
program test_core;
{$mode objfpc}{$H+}

uses SysUtils, keys, sheet, cellfmt, dates, menutree, menudata, session, commands, controller;

var
  Fails, Total: Integer;

procedure Check(cond: Boolean; const what: string);
begin
  Inc(Total);
  if not cond then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what);
  end;
end;

procedure CheckStr(const got, want, what: string);
begin
  Inc(Total);
  if got <> want then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what, ': got "', got, '" want "', want, '"');
  end;
end;

procedure CheckInt(got, want: Integer; const what: string);
begin
  Inc(Total);
  if got <> want then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', what, ': got ', got, ' want ', want);
  end;
end;

{ ---- sheet ---- }
procedure TestSheet;
var
  sh: TSheet;
  c: TCell;
  r, col: Integer;
begin
  sh := TSheet.Create;
  Check(sh.Find(1, 1) = nil, 'empty sheet has no cells');
  sh.Put(1, 1, '''a');
  sh.Put(MaxRow, MaxCol, '5');
  CheckInt(sh.Count, 2, 'sparse count');
  CheckStr(sh.Find(MaxRow, MaxCol).Raw, '5', 'far corner stored');
  sh.UsedExtent(r, col);
  CheckInt(r, MaxRow, 'extent row');
  CheckInt(col, MaxCol, 'extent col');
  sh.Put(1, 1, '''b');
  CheckInt(sh.Count, 2, 'overwrite does not add');
  c := sh.Find(1, 1);
  CheckStr(c.Raw, '''b', 'overwrite value');
  sh.Remove(1, 1);
  Check(sh.Find(1, 1) = nil, 'remove');
  CheckInt(sh.ColWidth(3), 9, 'default width');
  sh.SetColWidth(3, 23);
  CheckInt(sh.ColWidth(3), 23, 'set width');
  Check(sh.ColWidthIsSet(3), 'width flagged');
  sh.Free;

  CheckStr(ColLetter(1), 'A', 'col A');
  CheckStr(ColLetter(26), 'Z', 'col Z');
  CheckStr(ColLetter(27), 'AA', 'col AA');
  CheckStr(ColLetter(256), 'IV', 'col IV');
  Check(ParseAddr('iv8192', col, r) and (col = 256) and (r = 8192), 'parse IV8192');
  Check(not ParseAddr('IW1', col, r), 'IW1 out of range');
  Check(not ParseAddr('A8193', col, r), 'row out of range');
  Check(not ParseAddr('12', col, r), 'digits only');
end;

{ ---- display formatting ---- }
procedure TestFormat;
var
  c: TCell;
  sh: TSheet;
  f: TCellFormat;
begin
  sh := TSheet.Create;
  c := TCell.Create;
  c.Raw := '3.50';
  CheckStr(ValueText(c, sh, 9), '3.5', 'general trims zeros');
  c.Raw := '0.1234567891234';
  CheckStr(ValueText(c, sh, 9), '0.1234568', 'general fits the column width');
  c.Raw := '1234567890123';
  CheckStr(ValueText(c, sh, 9), '1.235E+12', 'general falls back to scientific');
  c.Raw := '-12345';
  CheckStr(ValueText(c, sh, 9), '-12345', 'negative general');

  c.Fmt := MakeFormat(fkCurrency, 2);
  c.Raw := '1234567.891';
  CheckStr(ValueText(c, sh, 20), '$1,234,567.89', 'currency commas');
  c.Raw := '-5';
  CheckStr(ValueText(c, sh, 20), '($5.00)', 'currency negative');
  c.Raw := '@SUM(A1:A3)';
  c.Cache := '10.99';
  CheckStr(ValueText(c, sh, 20), '$10.99', 'cached formula value');
  c.Cache := '';

  c.Raw := '1234.5';
  c.Fmt := MakeFormat(fkFixed, 0);
  CheckStr(ValueText(c, sh, 20), '1235', 'fixed 0');
  c.Fmt := MakeFormat(fkFixed, 3);
  CheckStr(ValueText(c, sh, 20), '1234.500', 'fixed 3');
  c.Fmt := MakeFormat(fkComma, 1);
  CheckStr(ValueText(c, sh, 20), '1,234.5', 'comma 1');
  c.Fmt := MakeFormat(fkSci, 2);
  CheckStr(ValueText(c, sh, 20), '1.23E+03', 'sci 2');
  c.Raw := '0.00012';
  CheckStr(ValueText(c, sh, 20), '1.20E-04', 'sci small');
  c.Raw := '0.256';
  c.Fmt := MakeFormat(fkPercent, 1);
  CheckStr(ValueText(c, sh, 20), '25.6%', 'percent');
  c.Raw := '3';
  c.Fmt := MakeFormat(fkPlusMinus, 0);
  CheckStr(ValueText(c, sh, 20), '+++', 'plus-minus');
  c.Raw := '-2';
  CheckStr(ValueText(c, sh, 20), '--', 'plus-minus negative');
  c.Raw := '0';
  CheckStr(ValueText(c, sh, 20), '.', 'plus-minus zero');
  c.Raw := '12.5';
  c.Fmt := MakeFormat(fkText, 0);
  CheckStr(ValueText(c, sh, 20), '12.5', 'text format shows contents');
  c.Fmt := MakeFormat(fkHidden, 0);
  CheckStr(ValueText(c, sh, 20), '', 'hidden');
  c.Fmt := MakeFormat(fkDate, 1);
  c.Raw := '36526';
  CheckStr(ValueText(c, sh, 20), '01-Jan-00', 'date D1');
  c.Fmt := MakeFormat(fkDate, 4);
  CheckStr(ValueText(c, sh, 20), '01/01/00', 'date D4');
  c.Fmt := MakeFormat(fkDate, 6);
  c.Raw := '0.5625';
  CheckStr(ValueText(c, sh, 20), '01:30:00 PM', 'time D6');
  c.Fmt := MakeFormat(fkDate, 9);
  CheckStr(ValueText(c, sh, 20), '13:30', 'time D9');

  { global format and zero suppression }
  c.Fmt.UseGlobal := True;
  c.Raw := '0';
  sh.GlobalFmt := MakeFormat(fkFixed, 2);
  CheckStr(ValueText(c, sh, 9), '0.00', 'cell follows global format');
  sh.ZeroDisplay := False;
  CheckStr(ValueText(c, sh, 9), '', 'zero suppressed');
  f := EffectiveFormat(c, sh);
  CheckStr(FormatTag(f), 'F2', 'tag');
  CheckStr(FormatTag(MakeFormat(fkComma, 0)), ',0', 'comma tag');
  CheckStr(FormatTag(MakeFormat(fkDate, 7)), 'D7', 'time tag');

  c.Raw := '$12';
  sh.ZeroDisplay := True;
  CheckStr(ValueText(c, sh, 9), '$12', 'hex-looking text is not a number');
  CheckStr(NumToRaw(3.26), '3.26', 'number stored shortest');
  c.Free;
  sh.Free;
end;

{ ---- dates (serial numbers, including the 1900 leap-year quirk) ---- }
procedure TestDates;
var
  y, m, d: Integer;
begin
  Check(SerialToDate(1, y, m, d) and (y = 1900) and (m = 1) and (d = 1), 'serial 1');
  Check(SerialToDate(59, y, m, d) and (m = 2) and (d = 28), 'serial 59 is 28-Feb-1900');
  Check(SerialToDate(60, y, m, d) and (m = 2) and (d = 29), 'serial 60 is the phantom 29-Feb-1900');
  Check(SerialToDate(61, y, m, d) and (m = 3) and (d = 1), 'serial 61 is 1-Mar-1900');
  Check(SerialToDate(36526, y, m, d) and (y = 2000) and (m = 1) and (d = 1), 'serial 36526 is 1-Jan-2000');
  Check(not SerialToDate(0, y, m, d), 'serial 0 invalid');
  Check(SerialToDate(MaxSerial, y, m, d) and (y = 2099) and (m = 12) and (d = 31), 'last serial');
  CheckInt(DateToSerial(2000, 1, 1), 36526, 'date to serial');
  CheckInt(DateToSerial(1900, 2, 29), 60, 'phantom day to serial');
  CheckInt(DateToSerial(1900, 3, 1), 61, '1-Mar-1900 to serial');
  CheckInt(DateToSerial(1900, 1, 1), 1, '1-Jan-1900 to serial');
  CheckStr(FormatSerial(60, 1), '29-Feb-00', 'phantom day formatted');
  CheckStr(FormatSerial(0, 1), 'ERR', 'invalid date');
end;

{ ---- menus ---- }
procedure TestMenus;
var
  t: TMenuTree;
begin
  t := BuildMenuTree;
  CheckInt(t.Root.Count, 10, 'ten main menu items');
  CheckStr(t.Root.KidsText,
    'Worksheet, Range, Copy, Move, File, Print, Graph, Data, System, Quit', 'main menu order');
  CheckStr(t.Root[0].PanelText,
    'Global, Insert, Delete, Column, Erase, Titles, Window, Status, Page', 'worksheet panel text');
  CheckStr(t.Root[9][1].PanelText,
    'End the session (Answer Yes only if you have saved your work)', 'quit yes help');
  CheckInt(t.Root.FindByInitial('r'), 1, 'initial R finds Range');
  CheckInt(t.Root.FindByInitial('z'), -1, 'no initial Z');
  t.Free;
end;

{ ---- keys ---- }
procedure TestKeys;
var
  q: TKeyQueue;
  i: Integer;
begin
  q := TKeyQueue.Create;
  Check(q.Empty, 'new queue empty');
  for i := 1 to 100 do q.Push(i);
  CheckInt(q.Pop, 1, 'fifo first');
  for i := 2 to 100 do q.Pop;
  Check(q.Empty, 'drained');
  q.PushString('a' + UTF8Encode(WideChar($E9)));
  CheckInt(q.Pop, Ord('a'), 'string key a');
  CheckInt(q.Pop, $E9, 'utf-8 decoded');
  q.Free;
  CheckStr(KeyName(kF1 + 4), 'F5', 'F5 name');
  CheckStr(KeyName(kAltF1 + 3), 'Alt-F4', 'Alt-F4 name');
  CheckStr(KeyName(MakeAlt('x')), 'Alt-X', 'Alt-X name');
  CheckStr(KeyName(kCtrlRight), 'Ctrl-Right', 'Ctrl-Right name');
  CheckInt(Canonical(21), kAltF1 + 3, 'Ctrl-U is Undo');
  Check(MapCount > 20, 'mapping table populated');
end;

{ ---- controller ---- }
var
  S: TSession;
  Cmds: TCommands;
  Ctl: TController;

procedure NewSession;
begin
  S.Free;
  S := TSession.Create;
end;

procedure Feed(const keystr: string);
var
  q: TKeyQueue;
begin
  q := TKeyQueue.Create;
  q.PushString(keystr);
  while not q.Empty do Ctl.HandleKey(q.Pop);
  q.Free;
end;

procedure TestController;
begin
  S := nil;
  NewSession;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S, Cmds);

  { menus and stubs }
  Feed('/');
  Check(S.Mode = mMenu, 'slash opens menu');
  Feed('wgrn');
  Check(S.Mode = mReady, 'leaf returns to ready');
  CheckStr(S.Msg, '[stub] /Worksheet Global Recalculation Natural', 'stub message');

  Feed('/');
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kRight);
  CheckInt(S.MenuIdx[0], 2, 'right arrow moves highlight');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'esc at top level leaves menu');
  Feed('/wg');
  CheckInt(S.MenuDepth, 2, 'two levels down');
  Ctl.HandleKey(kEsc);
  CheckInt(S.MenuDepth, 1, 'esc goes up one level');
  Ctl.HandleKey(kBreak);
  Check(S.Mode = mReady, 'break leaves menu from any level');

  Feed('/qn');
  Check(not S.Quitting, 'quit no');
  Feed('/qy');
  Check(S.Quitting, 'quit yes');
  S.Quitting := False;

  { entry }
  Feed('hello'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''hello', 'label gets default prefix');
  Check(S.Mode = mReady, 'enter returns to ready');
  Ctl.HandleKey(kDown);
  Feed('12.5'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '12.5', 'number stored');
  Feed('"abc'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '"abc', 'explicit prefix kept');
  Feed('x');
  Check(S.Mode = mLabel, 'letter starts label mode');
  Ctl.HandleKey(kEsc);
  Check(S.Sheet.Find(2, 1).Raw = '"abc', 'esc cancels entry');
  Feed('7');
  Check(S.Mode = mValue, 'digit starts value mode');
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 3, 'arrow commits entry and moves');
  CheckStr(S.Sheet.Find(2, 1).Raw, '7', 'arrow committed value');
  Feed(UTF8Encode(WideChar($E9)) + 'te' + #13);
  CheckStr(S.Sheet.Find(3, 1).Raw, '''' + UTF8Encode(WideChar($E9)) + 'te', 'utf-8 label');
  Feed('ab');
  Ctl.HandleKey(kBackspace);
  CheckStr(S.Entry, 'a', 'backspace');
  Ctl.HandleKey(kEsc);

  { goto }
  Ctl.HandleKey(kF1 + 4);
  Check(S.Mode = mGoto, 'F5 starts goto');
  Feed('c10'#13);
  CheckInt(S.CurCol, 3, 'goto column');
  CheckInt(S.CurRow, 10, 'goto row');
  Ctl.HandleKey(kHome);
  CheckInt(S.CurRow * 100 + S.CurCol, 101, 'home goes to A1');

  { end-jump over a contiguous block }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  S.Sheet.Put(1, 1, '1');
  S.Sheet.Put(2, 1, '1');
  S.Sheet.Put(3, 1, '1');
  S.Sheet.Put(8, 1, '1');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 3, 'end-down stops at end of block');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, 8, 'end-down jumps to next block');
  Ctl.HandleKey(kEnd);
  Ctl.HandleKey(kDown);
  CheckInt(S.CurRow, MaxRow, 'end-down runs to the edge');

  { scrolling }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  Ctl.HandleKey(kPgDn);
  CheckInt(S.CurRow, 21, 'pgdn moves a screen');
  CheckInt(S.TopRow, 21, 'pgdn scrolls a screen');
  Ctl.HandleKey(kTab);
  CheckInt(S.LeftCol, 9, 'tab moves right a screen');


  { ---- phase 3 ---- }
  NewSession;
  Ctl := TController.Create(S, Cmds);

  { EDIT mode (F2) }
  S.Sheet.Put(1, 1, '''abcd');
  Ctl.HandleKey(kF1 + 1);
  Check(S.Mode = mEdit, 'F2 enters edit');
  CheckStr(S.Entry, '''abcd', 'edit shows contents with prefix');
  Ctl.HandleKey(kLeft);
  Ctl.HandleKey(kLeft);
  Feed('XY');
  CheckStr(S.Entry, '''abXYcd', 'insert at cursor');
  Ctl.HandleKey(kBackspace);
  CheckStr(S.Entry, '''abXcd', 'backspace in edit');
  Ctl.HandleKey(kDel);
  CheckStr(S.Entry, '''abXd', 'delete in edit');
  Ctl.HandleKey(kHome);
  Ctl.HandleKey(kRight);
  Feed('Z');
  CheckStr(S.Entry, '''ZabXd', 'home then right');
  Ctl.HandleKey(kEnter);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''ZabXd', 'edit committed');
  Ctl.HandleKey(kF1 + 1);
  Ctl.HandleKey(kEsc);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''ZabXd', 'esc cancels edit');
  Ctl.HandleKey(kDown);
  Feed('ab');
  Ctl.HandleKey(kF1 + 1);
  Check(S.Mode = mEdit, 'F2 during entry');
  CheckStr(S.Entry, '''ab', 'entry carried into edit with prefix');
  Ctl.HandleKey(kEsc);

  { numbers are normalised }
  Feed('007.50'#13);
  CheckStr(S.Sheet.Find(2, 1).Raw, '7.5', 'number normalised');

  { /Range Format Currency 2 over A2..A3 via POINT mode }
  S.Sheet.Put(3, 1, '1234.5');
  S.CurRow := 2;
  Feed('/rfc');
  Check(S.Mode = mPrompt, 'decimal places prompt');
  Feed(#13);
  Check(S.Mode = mPoint, 'range prompt follows');
  Ctl.HandleKey(Ord('.'));
  Ctl.HandleKey(kDown);
  Ctl.HandleKey(kEnter);
  Check(S.Mode = mReady, 'range accepted');
  CheckInt(S.CurRow, 2, 'pointer returns to where it was');
  CheckStr(FormatTag(S.Sheet.Find(3, 1).Fmt), 'C2', 'second cell formatted');
  CheckStr(FormatTag(S.Sheet.Find(2, 1).Fmt), 'C2', 'first cell formatted');
  Check(S.Sheet.Find(1, 1).Fmt.UseGlobal, 'unselected cell unchanged');

  { typing a range }
  Feed('/rfr');
  Check(S.Mode = mPoint, 'reset asks for a range');
  Feed('a1.a3'#13);
  Check(S.Sheet.Find(2, 1).Fmt.UseGlobal, 'reset returns cell to global format');

  { Undo }
  Check(S.HasUndo, 'undo available after commands');
  Ctl.HandleKey(kAltF1 + 3);
  CheckStr(FormatTag(S.Sheet.Find(2, 1).Fmt), 'C2', 'undo restores formats');
  Ctl.HandleKey(kAltF1 + 3);
  Check(S.Sheet.Find(2, 1).Fmt.UseGlobal, 'undo again redoes');

  { column widths with live preview }
  S.CurCol := 2;
  Feed('/wcs');
  Check(S.Mode = mPrompt, 'width prompt');
  CheckStr(S.Entry, '9', 'default is current width');
  Ctl.HandleKey(kRight);
  Ctl.HandleKey(kRight);
  CheckInt(S.Sheet.ColWidth(2), 11, 'arrows preview the width');
  Ctl.HandleKey(kEsc);
  CheckInt(S.Sheet.ColWidth(2), 9, 'esc restores the width');
  Feed('/wcs');
  Feed(#8'20'#13);
  CheckInt(S.Sheet.ColWidth(2), 20, 'width set');
  Check(S.Sheet.ColWidthIsSet(2), 'width flagged as set');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.ColWidth(2), 9, 'undo restores width');
  Feed('/wcs');
  Feed(#8'999'#13);
  Check(S.Mode = mPrompt, 'out-of-range width is refused');
  Ctl.HandleKey(kEsc);
  S.Sheet.SetColWidth(2, 15);
  Feed('/wcr');
  CheckInt(S.Sheet.ColWidth(2), 9, 'reset-width');
  Feed('/wgc');
  Feed(#8#8'12'#13);
  CheckInt(S.Sheet.GlobalWidth, 12, 'global width');

  { label prefixes }
  NewSession;
  Ctl := TController.Create(S, Cmds);
  Feed('/wglr');
  Feed('hi'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '"hi', 'global right alignment applies to new labels');
  S.Sheet.Put(2, 1, '''left');
  S.Sheet.Put(3, 1, '\-');
  Feed('/wglc');
  CheckStr(S.Sheet.Find(1, 1).Raw, '^hi', 'global label-prefix changes existing labels');
  CheckStr(S.Sheet.Find(2, 1).Raw, '^left', 'existing label changed');
  CheckStr(S.Sheet.Find(3, 1).Raw, '\-', 'repeating label untouched');
  Feed('/rll');
  Feed('a1.a1'#13);
  CheckStr(S.Sheet.Find(1, 1).Raw, '''hi', 'range label left');
  CheckStr(S.Sheet.Find(2, 1).Raw, '^left', 'outside range unchanged');

  { erase }
  Feed('/re');
  Check(S.Mode = mPoint, 'range erase prompts');
  Feed('a1.a2'#13);
  Check(S.Sheet.Find(1, 1) = nil, 'range erased');
  Check(S.Sheet.Find(3, 1) <> nil, 'rest kept');
  Feed('/wen');
  Check(S.Sheet.Find(3, 1) <> nil, 'worksheet erase No keeps data');
  Feed('/wey');
  CheckInt(S.Sheet.Count, 0, 'worksheet erase Yes');
  Ctl.HandleKey(kAltF1 + 3);
  CheckInt(S.Sheet.Count, 1, 'undo of worksheet erase');

  { zero display }
  Feed('/wgzy');
  Check(not S.Sheet.ZeroDisplay, 'zero hidden');
  Feed('/wgzn');
  Check(S.Sheet.ZeroDisplay, 'zero shown');

  { global formats }
  Feed('/wgfp');
  Feed(#8'1'#13);
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'P1', 'global percent 1');
  Feed('/wgfg');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'G', 'global general');
  Feed('/wgfd1');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'D1', 'global date 1');
  Feed('/wgfdt3');
  CheckStr(FormatTag(S.Sheet.GlobalFmt), 'D8', 'global time 3 is D8');

  Feed('/rfg');
  Check(S.Mode = mPoint, 'range format general prompts');
  Ctl.HandleKey(kEsc);
  Check(S.Mode = mReady, 'esc cancels range prompt');

  S.Free;
  Cmds.Free;
end;

begin
  TestSheet;
  TestFormat;
  TestDates;
  TestMenus;
  TestKeys;
  TestController;
  WriteLn(Total - Fails, '/', Total, ' checks passed');
  if Fails > 0 then Halt(1);
end.
