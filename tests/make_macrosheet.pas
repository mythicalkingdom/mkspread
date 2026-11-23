{ Generates MACROS.WK1: a worksheet of small macros for checking mkspread's macro
  interpreter against the original program.

  Open it in 1-2-3, press Alt-R (macro \R, which runs every test), then F9 if
  recalculation is manual, and read the total of differences in A3.  A row with
  a 1 in column A shows a test where the original program did something
  different from mkspread.  Alt-D lists the differing rows (from Y7 down).  Each test can also be
  run alone with Alt-F3 and TSTnn, if your keyboard passes Alt-F3 through.  The test macros are in column S, the by-hand macros in column U, the scratch cells they write to are
  H..Q on the test's own row.

  The "expected" column is what mkspread's interpreter produced when this
  program ran the same macros.

  Usage: make_macrosheet <output.wk1> }
program make_macrosheet;
{$mode objfpc}{$H+}

uses SysUtils, Classes, sheet, formula, cellfmt, session, commands, controller, macro, wk1;

type
  TTest = record
    Desc: string;
    Result: string;                 { the cell holding the outcome, <r> = the test's row }
    Lines: array of string;
    Setup: array of string;         { 'P<r>=5' or 'P<r>=1234.5;C2' }
  end;

var
  Tests: array of TTest;
  FirstRow: Integer = 7;

procedure Add(const desc, result: string; const lines: array of string; const setup: array of string);
var
  n, i: Integer;
begin
  n := Length(Tests);
  SetLength(Tests, n + 1);
  Tests[n].Desc := desc;
  Tests[n].Result := result;
  SetLength(Tests[n].Lines, Length(lines));
  for i := 0 to High(lines) do Tests[n].Lines[i] := lines[i];
  SetLength(Tests[n].Setup, Length(setup));
  for i := 0 to High(setup) do Tests[n].Setup[i] := setup[i];
end;

procedure DefineTests;
const
  None: array[0..0] of string = ('');
begin
  SetLength(Tests, 0);
  Add('type a number', 'H<r>', ['{GOTO}H<r>~5~'], []);
  Add('type a label', 'H<r>', ['{GOTO}H<r>~hello~'], []);
  Add('{RIGHT 3} repeat count', 'K<r>', ['{GOTO}H<r>~{RIGHT 3}x~'], []);
  Add('{LEFT 2}', 'H<r>', ['{GOTO}J<r>~{LEFT 2}7~'], []);
  Add('{EDIT} appends to a label', 'H<r>', ['{GOTO}H<r>~abc~{EDIT}d~'], []);
  Add('a formula typed by a macro', 'H<r>', ['{GOTO}H<r>~+1+2*3~'], []);
  Add('{ESC} cancels an entry', 'H<r>', ['{GOTO}H<r>~ab{ESC}c~'], []);
  Add('{BS} deletes a character', 'H<r>', ['{GOTO}H<r>~abc{BS}~'], []);
  Add('{IF} true', 'H<r>', ['{GOTO}H<r>~{IF 1}5~'], []);
  Add('{IF} false skips the rest of its cell', 'J<r>',
      ['{GOTO}H<r>~{IF 0}5~{RIGHT}9~', '{RIGHT 2}7~'], []);
  Add('{IF} with a cell comparison', 'H<r>', ['{GOTO}H<r>~{IF P<r>>3}a~'], ['P<r>=5']);
  Add('{BRANCH}', 'H<r>', ['{GOTO}H<r>~{BRANCH TST12B}1~', '2~', '[[TST12B]]3~'], []);
  Add('a routine called twice', 'I<r>',
      ['{GOTO}H<r>~{TST13S}{TST13S}{RETURN}', '[[TST13S]]x~{RIGHT}'], []);
  Add('{RETURN} leaves a routine early', 'H<r>',
      ['{GOTO}H<r>~{TST14S}{RETURN}', '[[TST14S]]x~{RETURN}y~'], []);
  Add('a routine ends at its last cell', 'I<r>',
      ['{GOTO}H<r>~{TST15S}{RIGHT}z~{RETURN}', '[[TST15S]]x~'], []);
  Add('{FOR} counter after the loop', 'P<r>',
      ['{GOTO}H<r>~{FOR P<r>,1,3,1,TST16S}{RETURN}', '[[TST16S]]n~{RIGHT}'], []);
  Add('{FOR} runs the routine each pass', 'J<r>',
      ['{GOTO}H<r>~{FOR P<r>,1,3,1,TST17S}{RETURN}', '[[TST17S]]n~{RIGHT}'], []);
  Add('{FORBREAK} leaves the counter alone', 'P<r>',
      ['{GOTO}H<r>~{FOR P<r>,1,5,1,TST18S}{RETURN}', '[[TST18S]]x~{RIGHT}{IF P<r>=2}{FORBREAK}'], []);
  Add('{LET} a number', 'H<r>', ['{LET H<r>,3*4}'], []);
  Add('{LET} a quoted string', 'H<r>', ['{LET H<r>,"hi"}'], []);
  Add('{LET} with :string', 'H<r>', ['{LET H<r>,1+2:string}'], []);
  Add('{LET} using a cell', 'H<r>', ['{LET H<r>,P<r>+1}'], ['P<r>=5']);
  Add('{LET} with a bare word', 'H<r>', ['{LET H<r>,hello}'], []);
  Add('{PUT} at an offset in a range', 'J<r>', ['{PUT H<r>..J<r>,2,0,7}'], []);
  Add('{BLANK}', 'H<r>', ['{BLANK H<r>}'], ['H<r>=99']);
  Add('{CONTENTS} of a formatted number', 'H<r>', ['{CONTENTS H<r>,P<r>}'], ['P<r>=1234.5;C2']);
  Add('braces typed with {{} and {}}', 'H<r>', ['{GOTO}H<r>~{{}x{}}~'], []);
  Add('a tilde typed with {~}', 'H<r>', ['{GOTO}H<r>~a{~}b~'], []);
  Add('a number cell ends the macro', 'I<r>', ['{GOTO}H<r>~1~', '[[NUM]]5', '{RIGHT}2~'], []);
  Add('a text formula as a macro line', 'H<r>', ['{GOTO}H<r>~', '[[FORMULA]]+"4"&"~"'], []);
  Add('{DEFINE} receives arguments', 'H<r>',
      ['{GOTO}H<r>~{TST32S 3,"ab"}{RETURN}', '[[TST32S]]{DEFINE P<r>:value,Q<r>:string}{LET H<r>,P<r>*2}'], []);
  Add('menu keystrokes then {CONTENTS}', 'I<r>', ['{GOTO}H<r>~5~/rfc~~{CONTENTS I<r>,H<r>}'], []);
  Add('{BEEP} is accepted', 'H<r>', ['{GOTO}H<r>~{BEEP}1~'], []);
  Add('{LET} then recalculation', 'H<r>', ['{LET P<r>,2}{LET H<r>,P<r>*P<r>}'], []);
  { {QUIT} ends the whole macro, including \R, so it must be the last test }
  Add('{QUIT}', 'H<r>', ['{GOTO}H<r>~1~{QUIT}2~'], []);
end;

function Sub(const s: string; r: Integer): string;
begin
  Result := StringReplace(s, '<r>', IntToStr(r), [rfReplaceAll]);
end;

{ puts macros, names and setup cells into S; returns the master macro's lines }
procedure Build(S: TSession; withChecks: Boolean; expected: TSession);
var
  t, i, r, mr, p: Integer;
  line, nm, res, setup, addr, val, fmtc: string;
  g: TRange;
  c, d: Integer;
  cell: TCell;
  master: string;
  mrow: Integer;
  cc, rr: Integer;
  kindNum: Boolean;
  ev: TCell;
  dv: Double;
  pc: Char;
  tx: string;
begin
  mr := FirstRow;                                         { next free macro row (column S) }
  master := '';
  for t := 0 to High(Tests) do
  begin
    r := FirstRow + t;
    S.Sheet.Put(r, 5, '''' + ' ' + Tests[t].Desc);
    { setup cells }
    for i := 0 to High(Tests[t].Setup) do
    begin
      setup := Sub(Tests[t].Setup[i], r);
      p := Pos('=', setup);
      addr := Copy(setup, 1, p - 1);
      val := Copy(setup, p + 1, MaxInt);
      fmtc := '';
      if Pos(';', val) > 0 then
      begin
        fmtc := Copy(val, Pos(';', val) + 1, MaxInt);
        val := Copy(val, 1, Pos(';', val) - 1);
      end;
      if ParseAddr(addr, cc, rr) then
      begin
        cell := S.Sheet.Put(rr, cc, val);
        if fmtc = 'C2' then cell.Fmt := MakeFormat(fkCurrency, 2);
      end;
    end;
    { macro lines in column S }
    nm := Format('TST%.2d', [t + 1]);
    S.Sheet.SetName(nm, NormRange(mr, 19, mr, 19));
    master := master + '{' + nm + '}';
    for i := 0 to High(Tests[t].Lines) do
    begin
      line := Sub(Tests[t].Lines[i], r);
      if Copy(line, 1, 2) = '[[' then
      begin
        p := Pos(']]', line);
        nm := Copy(line, 3, p - 3);
        line := Copy(line, p + 2, MaxInt);
        if nm = 'NUM' then
        begin
          S.Sheet.Put(mr, 19, line);
          Inc(mr);
          continue;
        end
        else if nm = 'FORMULA' then
        begin
          S.Sheet.Put(mr, 19, line);
          Inc(mr);
          continue;
        end
        else
          S.Sheet.SetName(nm, NormRange(mr, 19, mr, 19));
      end;
      S.Sheet.Put(mr, 19, '''' + line);
      Inc(mr);
    end;
    Inc(mr);                                              { a blank cell ends each test's macro }

    if withChecks then
    begin
      { actual value: the cell the macro wrote, whatever its type }
      res := Sub(Tests[t].Result, r);
      S.Sheet.Put(r, 3, Format('@IF(@ISSTRING(%s),%s&"",%s+0)', [res, res, res]));
      ParseAddr(res, cc, rr);
      ev := expected.Sheet.Find(rr, cc);
      kindNum := True;
      if (ev <> nil) and (ev.Raw <> '') then
        kindNum := CellNumber(ev, dv);
      if kindNum then
      begin
        if (ev = nil) or (ev.Raw = '') then S.Sheet.Put(r, 4, '0') else S.Sheet.Put(r, 4, NumToRaw(dv));
        S.Sheet.Put(r, 1, Format('@IF(@ISNUMBER(C%d),@IF(@ABS(C%d-D%d)<0.000001,0,1),1)', [r, r, r]));
      end
      else
      begin
        TextOf(ev, pc, tx);
        S.Sheet.Put(r, 4, '"' + tx);
        S.Sheet.Put(r, 1, Format('@IF(@ISSTRING(C%d),@IF(@EXACT(C%d,D%d),0,1),1)', [r, r, r]));
      end;
    end;
  end;
  { the master macro, split into lines of at most 60 characters }
  S.Sheet.SetName('\R', NormRange(1, 19, 1, 19));
  i := 1;
  mrow := 1;
  while i <= Length(master) do
  begin
    p := i + 60;
    if p > Length(master) then p := Length(master) + 1
    else while (p > i) and (master[p - 1] <> '}') do Dec(p);
    S.Sheet.Put(mrow, 19, '''' + Copy(master, i, p - i));
    Inc(mrow);
    i := p;
  end;
end;

procedure Manual(S: TSession; r: Integer);
  procedure L(const txt: string);
  begin
    S.Sheet.Put(r, 5, '''' + txt);
    Inc(r);
  end;
begin
  Inc(r);
  L('--- Try by hand (not checked automatically) ---');
  L('{?}: press Alt-Q. It stops; type abc, Enter (the Enter is not stored): done');
  L('   is added after abc in H400 (abcdone).');
  L('{GETLABEL}: Alt-W; answer Ann: label Ann in H401.');
  L('{GETNUMBER}: Alt-E; answer 2+3: 5 in H402.');
  L('{MENUBRANCH}: Alt-T; choose One or Two (letter or');
  L('   arrows+Enter): it types 1 or 2 in H403; Esc ends the macro.');
  L('{GET}: Alt-Y; press a key: that key is stored in H404');
  L('   as a label and is not typed into the sheet.');
  L('STEP: press Alt-F2, then Alt-U: it should wait for a key');
  L('   before each keystroke. Alt-F2 again lets it run on.');
  L('LEARN: /Worksheet Learn Range U500..U510, Alt-F5, type some keys,');
  L('   Alt-F5: the keystrokes appear as macro text in U500.');
  S.Sheet.Put(r + 2, 21, '''{GOTO}H400~{?}done~');
  S.Sheet.SetName('MAN1', NormRange(r + 2, 21, r + 2, 21));
  S.Sheet.SetName('\Q', NormRange(r + 2, 21, r + 2, 21));
  S.Sheet.Put(r + 4, 21, '''{GETLABEL "Name: ",H401}');
  S.Sheet.SetName('MAN2', NormRange(r + 4, 21, r + 4, 21));
  S.Sheet.SetName('\W', NormRange(r + 4, 21, r + 4, 21));
  S.Sheet.Put(r + 6, 21, '''{GETNUMBER "Qty: ",H402}');
  S.Sheet.SetName('MAN3', NormRange(r + 6, 21, r + 6, 21));
  S.Sheet.SetName('\E', NormRange(r + 6, 21, r + 6, 21));
  S.Sheet.Put(r + 8, 21, '''{MENUBRANCH U' + IntToStr(r + 20) + '}');
  S.Sheet.SetName('MAN4', NormRange(r + 8, 21, r + 8, 21));
  S.Sheet.SetName('\T', NormRange(r + 8, 21, r + 8, 21));
  S.Sheet.Put(r + 10, 21, '''{GET H404}');
  S.Sheet.SetName('MAN5', NormRange(r + 10, 21, r + 10, 21));
  S.Sheet.SetName('\Y', NormRange(r + 10, 21, r + 10, 21));
  S.Sheet.Put(r + 12, 21, '''{GOTO}H405~{DOWN}a~{DOWN}b~{DOWN}c~');
  S.Sheet.SetName('MAN6', NormRange(r + 12, 21, r + 12, 21));
  S.Sheet.SetName('\U', NormRange(r + 12, 21, r + 12, 21));
  { the menu for MAN4 }
  S.Sheet.Put(r + 20, 21, '''One'); S.Sheet.Put(r + 20, 22, '''Two');
  S.Sheet.Put(r + 21, 21, '''first choice'); S.Sheet.Put(r + 21, 22, '''second choice');
  S.Sheet.Put(r + 22, 21, '''{GOTO}H403~1~'); S.Sheet.Put(r + 22, 22, '''{GOTO}H403~2~');
end;

var
  S1, S2: TSession;
  Ctl: TController;
  Cmds: TCommands;
  M: TMacro;
  info: TFileInfo;
  w: TStringList;
  msg: string;
  last, i: Integer;
  g: TRange;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: make_macrosheet output.wk1');
    Halt(2);
  end;
  DefineTests;
  last := FirstRow + High(Tests);

  { run the macros in mkspread to learn what they do }
  S1 := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S1, Cmds);
  M := TMacro.Create(S1);
  Build(S1, False, nil);
  S1.Calc.Recalc;
  S1.MacroRequest := '\R';
  M.RunSync(Ctl);
  if M.Active then
  begin
    WriteLn('the master macro did not finish');
    Halt(1);
  end;
  S1.Calc.Recalc;

  { the worksheet to give to the original program: macros and setup only }
  S2 := TSession.Create;
  S2.Sheet.SetColWidth(1, 4);
  S2.Sheet.SetColWidth(2, 1);
  S2.Sheet.SetColWidth(3, 15);
  S2.Sheet.SetColWidth(4, 15);
  S2.Sheet.SetColWidth(5, 41);
  S2.Sheet.SetColWidth(19, 40);
  S2.Sheet.SetColWidth(21, 30);
  S2.Sheet.Put(1, 1, '''mkspread macro test: press Alt-R, then F9; total of differences in A3');
  S2.Sheet.Put(2, 1, '''A: 0=agree 1=differ  C: result in 1-2-3  D: mkspread expected');
  S2.Sheet.Put(3, 3, '''<- differences (0 = all agree)');
  S2.Sheet.Put(5, 1, '''Dif'); S2.Sheet.Put(5, 3, '''1-2-3'); S2.Sheet.Put(5, 4, '''mkspread'); S2.Sheet.Put(5, 5, '''Test');
  Build(S2, True, S1);
  S2.Sheet.Put(3, 1, Format('@SUM(A%d..A%d)', [FirstRow, last]));
  Manual(S2, last + 2);
  S2.Sheet.Put(4, 1, '''Alt-D lists the rows that differ (row, test) from Y7 down');
  S2.Sheet.Put(1, 23, '''{LET X1,0}{FOR X2,7,' + IntToStr(last) + ',1,DCHK}{GOTO}Y7~');
  S2.Sheet.Put(3, 23, Format('''{IF @INDEX(A7..A%d,0,X2-7)=1}{LET X1,X1+1}{PUT Y7..Z300,0,X1-1,X2}{PUT Y7..Z300,1,X1-1,@INDEX(E7..E%d,0,X2-7)}', [last, last]));
  S2.Sheet.SetName('\D', NormRange(1, 23, 1, 23));
  S2.Sheet.SetName('DCHK', NormRange(3, 23, 3, 23));
  { every macro the instructions mention must exist and start where it should }
  for i := 1 to Length('RDQWETYU') do
    if not S2.Sheet.FindName('\' + Copy('RDQWETYU', i, 1), g) then
    begin
      WriteLn('macro name \', Copy('RDQWETYU', i, 1), ' is missing');
      Halt(1);
    end
    else if not S2.Sheet.NonEmpty(g.R1, g.C1) then
    begin
      WriteLn('macro \', Copy('RDQWETYU', i, 1), ' points at an empty cell');
      Halt(1);
    end;
  S2.Calc.Recalc;
  w := TStringList.Create;
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1; info.CursorRow := 3; info.LeftCol := 1; info.TopRow := 1;
  msg := SaveWorksheet(ParamStr(1), S2.Sheet, False, info, w);
  if msg <> '' then begin WriteLn(msg); Halt(1); end;
  if w.Count > 0 then WriteLn(w.Text);
  WriteLn('wrote ', ParamStr(1), ': ', Length(Tests), ' macro tests');
  for i := 0 to High(Tests) do
    if S1.Sheet.Find(FirstRow + i, 3) <> nil then ;
end.
