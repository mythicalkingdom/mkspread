{ Unit tests for the terminal-independent core: storage, formatting, menus,
  key queue and the controller driven purely by logical keys. }
program test_core;
{$mode objfpc}{$H+}

uses SysUtils, keys, sheet, cellfmt, menutree, menudata, session, commands, controller;

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
begin
  c := TCell.Create;
  c.Fmt := -1;
  c.Raw := '3.50';
  CheckStr(ValueText(c), '3.5', 'general trims zeros');
  c.Fmt := 2;
  c.Raw := '1234567.891';
  CheckStr(ValueText(c), '$1,234,567.89', 'currency commas');
  c.Raw := '-5';
  CheckStr(ValueText(c), '($5.00)', 'currency negative');
  c.Raw := '@SUM(A1:A3)';
  c.Cache := '10.99';
  CheckStr(ValueText(c), '$10.99', 'cached formula value');
  c.Cache := '';
  c.Fmt := -1;
  c.Raw := '$12';
  CheckStr(ValueText(c), '$12', 'hex-looking text is not a number');
  c.Free;
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
  Feed('wgff');
  Check(S.Mode = mReady, 'leaf returns to ready');
  CheckStr(S.Msg, '[stub] /Worksheet Global Format Fixed', 'stub message');

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

  S.Free;
  Cmds.Free;
end;

begin
  TestSheet;
  TestFormat;
  TestMenus;
  TestKeys;
  TestController;
  WriteLn(Total - Fails, '/', Total, ' checks passed');
  if Fails > 0 then Halt(1);
end.
