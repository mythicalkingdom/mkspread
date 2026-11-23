{ Generates DATA.WK1: a worksheet that runs the /Data commands (Fill, Table,
  Sort, Query, Distribution, Matrix, Regression, Parse) on small data blocks, for
  checking mkspread against the original program.

  Open it in the original program, press Alt-R (macro \R runs every test), then
  F9 if recalculation is manual, and read the total of differences in A3.  A row
  with a 1 in column A is a test whose result differs from mkspread's.  Alt-D
  lists the differing rows (from Y7 down).  A test's data and result are in a
  block of rows starting at row 100 + 30 * (test number - 1), columns H..Q; the
  result cells that mkspread produced are repeated 30 columns to the right, the
  per-cell differences 60 columns to the right.

  A macro that hits an error message in the original program stops; the tests
  after it then do not run, and their rows show differences.  Run a stopped
  test alone with Alt-F3 and TSTnn.

  Usage: make_datasheet <output.wk1> }
program make_datasheet;
{$mode objfpc}{$H+}

uses SysUtils, Classes, sheet, formula, cellfmt, session, commands, controller, macro, wk1;

type
  TTest = record
    Desc: string;
    Result: string;                 { the result range, e.g. H<b>..J<b+5> }
    Setup: array of string;         { 'H<b>=3' (number or formula), 'H<b>=''text', 'H<b>..J<b+2>=99' }
    Macro: string;
  end;

var
  Tests: array of TTest;
  FirstRow: Integer = 7;

procedure Add(const desc, result, macro: string; const setup: array of string);
var
  n, i: Integer;
begin
  n := Length(Tests);
  SetLength(Tests, n + 1);
  Tests[n].Desc := desc;
  { every test ends by typing q7 in a cell: 7 if a menu was still open (q left it), q7 if not }
  Tests[n].Result := result + ';H<b+20>..H<b+20>';
  Tests[n].Macro := macro + 'q7~';
  SetLength(Tests[n].Setup, Length(setup));
  for i := 0 to High(setup) do Tests[n].Setup[i] := setup[i];
end;

{ the keystrokes of a command in a standard block: goto the block's corner first }
procedure DefineTests;
const
  SortA: array[0..17] of string = (
    'H<b>=''a', 'I<b>=3', 'J<b>=9',
    'H<b+1>=''b', 'I<b+1>=1', 'J<b+1>=8',
    'H<b+2>=''c', 'I<b+2>=3', 'J<b+2>=7',
    'H<b+3>=''d', 'I<b+3>=2', 'J<b+3>=6',
    'H<b+4>=''e', 'I<b+4>=1', 'J<b+4>=5',
    'H<b+5>=''f', 'I<b+5>=3', 'J<b+5>=4');
  SortD: array[0..17] of string = (
    'H<b>=''a', 'I<b>=3', 'J<b>=9',
    'H<b+1>=''b', 'I<b+1>=1', 'J<b+1>=8',
    'H<b+2>=''c', 'I<b+2>=5', 'J<b+2>=7',
    'H<b+3>=''d', 'I<b+3>=2', 'J<b+3>=6',
    'H<b+4>=''e', 'I<b+4>=4', 'J<b+4>=5',
    'H<b+5>=''f', 'I<b+5>=6', 'J<b+5>=4');
  SortB: array[0..14] of string = (
    'H<b>=''pear', 'H<b+1>=''apple', 'H<b+2>=''Banana', 'H<b+3>=''10', 'H<b+4>=5',
    'H<b+6>=''apple', 'H<b+7>=''cherry', 'H<b+8>=-2.5',
    'I<b>=1', 'I<b+1>=2', 'I<b+2>=3', 'I<b+3>=4', 'I<b+4>=5', 'I<b+5>=6', 'I<b+6>=7');
  SortC: array[0..9] of string = (
    'H<b>=3', 'H<b+1>=1', 'H<b+2>=2',
    'I<b>=+H<b>*10', 'I<b+1>=+H<b+1>*10', 'I<b+2>=+H<b+2>*10',
    'J<b+1>=+H<b>', 'J<b+2>=+H<b+1>', 'K<b>=+H<b>+H<b+2>', 'K<b+1>=+$H$<b>');
  Db: array[0..27] of string = (
    'H<b>=''Name', 'I<b>=''Dept', 'J<b>=''Age', 'K<b>=''Pay',
    'H<b+1>=''Ann', 'I<b+1>=''Sales', 'J<b+1>=30', 'K<b+1>=100',
    'H<b+2>=''Bob', 'I<b+2>=''Dev', 'J<b+2>=45', 'K<b+2>=200',
    'H<b+3>=''Cy', 'I<b+3>=''Sales', 'J<b+3>=22', 'K<b+3>=150',
    'H<b+4>=''Dee', 'I<b+4>=''Ops', 'J<b+4>=45', 'K<b+4>=120',
    'H<b+5>=''Eve', 'I<b+5>=''Dev', 'J<b+5>=38', 'K<b+5>=300',
    'H<b+6>=''Al', 'I<b+6>=''Sales', 'J<b+6>=30', 'K<b+6>=90');
var
  i: Integer;

  { a database test: the criteria are given as extra setup cells }
  procedure Q(const desc, result, macro: string; const extra: array of string);
  var
    all: array of string;
    j, n: Integer;
  begin
    n := Length(Db);
    SetLength(all, n + Length(extra));
    for j := 0 to n - 1 do all[j] := Db[j];
    for j := 0 to High(extra) do all[n + j] := extra[j];
    Add(desc, result, macro, all);
  end;

  procedure Sorted(const desc, result, macro: string; const data: array of string);
  begin
    Add(desc, result, macro, data);
  end;
begin
  SetLength(Tests, 0);
  { ---- Sort ---- }
  Sorted('Sort ascending by a number column', 'H<b>..J<b+5>',
    '{GOTO}H<b+20>~/dsrdH<b>..J<b+5>~pI<b>~a~g', SortD);
  Sorted('Sort descending by a number column', 'H<b>..J<b+5>',
    '{GOTO}H<b+20>~/dsrdH<b>..J<b+5>~pI<b>~d~g', SortD);
  Sorted('Sort with a secondary key (descending)', 'H<b>..J<b+5>',
    '{GOTO}H<b+20>~/dsrdH<b>..J<b+5>~pI<b>~a~sJ<b>~d~g', SortA);
  Sorted('Sort a column mixing text, numbers and a blank, ascending', 'H<b>..I<b+7>',
    '{GOTO}H<b+20>~/dsrdH<b>..I<b+7>~pH<b>~a~g', SortB);
  Sorted('Same, descending', 'H<b>..I<b+7>',
    '{GOTO}H<b+20>~/dsrdH<b>..I<b+7>~pH<b>~d~g', SortB);
  Sorted('Sort rows that hold formulas', 'H<b>..K<b+2>',
    '{GOTO}H<b+20>~/dsrdH<b>..K<b+2>~pH<b>~a~g', SortC);
  { ---- Query ---- }
  Q('Extract: Dept = Sales', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Dept', 'M<b+1>=''Sales', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: Age = 45 (a number)', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Age', 'M<b+1>=45', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: two criteria rows (OR)', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..N<b+2>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Dept', 'N<b>=''Age', 'M<b+1>=''Dev', 'N<b+2>=22', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: two criteria in one row (AND)', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..N<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Dept', 'N<b>=''Age', 'M<b+1>=''Sales', 'N<b+1>=30', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: wildcard A*', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Name', 'M<b+1>=''A*', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: not (~Sales), lower-case criterion', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Dept', 'M<b+1>=''~sales', 'H<b+10>=''Name', 'I<b+10>=''Pay']);
  Q('Extract: output fields in another order', 'H<b+10>..I<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..I<b+17>~eq',
    ['M<b>=''Dept', 'M<b+1>=''Dev', 'H<b+10>=''Pay', 'I<b+10>=''Name']);
  Q('Unique: departments', 'H<b+10>..H<b+17>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~oH<b+10>..H<b+17>~uq',
    ['M<b>=''Dept', 'H<b+10>=''Dept']);
  Q('Delete: Dept = Sales', 'H<b>..K<b+6>',
    '{GOTO}H<b+20>~/dqriH<b>..K<b+6>~cM<b>..M<b+1>~ddq',
    ['M<b>=''Dept', 'M<b+1>=''Sales']);
  { ---- Fill ---- }
  Add('Fill 1, 1 down a 3 by 4 range', 'H<b>..J<b+3>',
    '{GOTO}H<b+20>~/dfH<b>..J<b+3>~1~1~8191~', []);
  Add('Fill 5 step 3 stop 20 (stops early)', 'H<b>..J<b+3>',
    '{GOTO}H<b+20>~/dfH<b>..J<b+3>~5~3~20~', ['H<b>..J<b+3>=99']);
  Add('Fill 10 step -2.5', 'H<b>..I<b+3>',
    '{GOTO}H<b+20>~/dfH<b>..I<b+3>~10~-2.5~-100~', []);
  Add('Fill with the default values', 'H<b>..I<b+2>',
    '{GOTO}H<b+20>~/dfH<b>..I<b+2>~~~~', []);
  Add('Fill a single row', 'H<b>..L<b>',
    '{GOTO}H<b+20>~/dfH<b>..L<b>~100~100~8191~', []);
  { ---- Table ---- }
  Add('Table 1: two formulas, three values', 'K<b+1>..L<b+3>',
    '{GOTO}H<b+20>~/dt1J<b>..L<b+3>~H<b>~',
    ['H<b>=0', 'J<b+1>=1', 'J<b+2>=2', 'J<b+3>=3', 'K<b>=+H<b>*H<b>', 'L<b>=+H<b>+10']);
  Add('Table 2: two input cells', 'K<b+1>..L<b+2>',
    '{GOTO}H<b+20>~/dt2J<b>..L<b+2>~H<b>~I<b>~',
    ['H<b>=0', 'I<b>=0', 'J<b>=+H<b>*10+I<b>', 'K<b>=1', 'L<b>=2', 'J<b+1>=5', 'J<b+2>=6']);
  { ---- Distribution ---- }
  Add('Distribution', 'K<b>..K<b+4>',
    '{GOTO}H<b+20>~/ddH<b>..H<b+7>~J<b>..J<b+3>~',
    ['H<b>=5', 'H<b+1>=12', 'H<b+2>=18', 'H<b+3>=25', 'H<b+4>=31', 'H<b+5>=31', 'H<b+6>=40', 'H<b+7>=2',
     'J<b>=10', 'J<b+1>=20', 'J<b+2>=30', 'J<b+3>=35']);
  Add('Distribution: values on a bin edge, a label and a blank', 'K<b>..K<b+3>',
    '{GOTO}H<b+20>~/ddH<b>..H<b+5>~J<b>..J<b+2>~',
    ['H<b>=10', 'H<b+1>=20', 'H<b+2>=''x', 'H<b+4>=10.5', 'H<b+5>=-4',
     'J<b>=10', 'J<b+1>=15', 'J<b+2>=20']);
  { ---- Matrix ---- }
  Add('Matrix invert 2 by 2', 'K<b>..L<b+1>',
    '{GOTO}H<b+20>~/dmiH<b>..I<b+1>~K<b>~',
    ['H<b>=2', 'I<b>=1', 'H<b+1>=1', 'I<b+1>=3']);
  Add('Matrix invert 3 by 3', 'K<b>..M<b+2>',
    '{GOTO}H<b+20>~/dmiH<b>..J<b+2>~K<b>~',
    ['H<b>=2', 'I<b>=0', 'J<b>=1', 'H<b+1>=1', 'I<b+1>=3', 'J<b+1>=2', 'H<b+2>=1', 'I<b+2>=1', 'J<b+2>=4']);
  Add('Matrix multiply 2 by 2', 'H<b+5>..I<b+6>',
    '{GOTO}H<b+20>~/dmmH<b>..I<b+1>~K<b>..L<b+1>~H<b+5>~',
    ['H<b>=1', 'I<b>=2', 'H<b+1>=3', 'I<b+1>=4', 'K<b>=5', 'L<b>=6', 'K<b+1>=7', 'L<b+1>=8']);
  Add('Matrix multiply 2 by 3 and 3 by 1', 'N<b>..N<b+1>',
    '{GOTO}H<b+20>~/dmmH<b>..J<b+1>~K<b>..K<b+2>~N<b>~',
    ['H<b>=1', 'I<b>=2', 'J<b>=3', 'H<b+1>=4', 'I<b+1>=5', 'J<b+1>=6', 'K<b>=1', 'K<b+1>=0', 'K<b+2>=-1']);
  { ---- Regression ---- }
  for i := 0 to 2 do
    case i of
      0: Add('Regression: one X column', 'K<b>..P<b+12>',
           '{GOTO}H<b+20>~/drrxH<b>..H<b+5>~yI<b>..I<b+5>~oK<b>~g',
           ['H<b>=1', 'H<b+1>=2', 'H<b+2>=3', 'H<b+3>=4', 'H<b+4>=5', 'H<b+5>=6',
            'I<b>=2.1', 'I<b+1>=3.9', 'I<b+2>=6.2', 'I<b+3>=7.8', 'I<b+4>=10.1', 'I<b+5>=12.2']);
      1: Add('Regression: two X columns', 'L<b>..R<b+12>',
           '{GOTO}H<b+20>~/drrxH<b>..I<b+5>~yJ<b>..J<b+5>~oL<b>~g',
           ['H<b>=1', 'H<b+1>=2', 'H<b+2>=3', 'H<b+3>=4', 'H<b+4>=5', 'H<b+5>=6',
            'I<b>=2', 'I<b+1>=1', 'I<b+2>=4', 'I<b+3>=3', 'I<b+4>=7', 'I<b+5>=5',
            'J<b>=5', 'J<b+1>=5', 'J<b+2>=11', 'J<b+3>=10', 'J<b+4>=17', 'J<b+5>=17.5']);
      2: Add('Regression: intercept forced to zero', 'K<b>..P<b+12>',
           '{GOTO}H<b+20>~/drrxH<b>..H<b+5>~yI<b>..I<b+5>~oK<b>~izg',
           ['H<b>=1', 'H<b+1>=2', 'H<b+2>=3', 'H<b+3>=4', 'H<b+4>=5', 'H<b+5>=6',
            'I<b>=2.1', 'I<b+1>=3.9', 'I<b+2>=6.2', 'I<b+3>=7.8', 'I<b+4>=10.1', 'I<b+5>=12.2']);
    end;
  { ---- Parse ---- }
  Add('Parse: label and number fields', 'J<b>..M<b+3>',
    '{GOTO}H<b+20>~/dpriH<b>..H<b+3>~oJ<b>~g',
    ['H<b>=|L>>>>>V>>>', 'H<b+1>=''Jones 4567', 'H<b+2>=''Lee   89', 'H<b+3>=''Kim   1234']);
  Add('Parse: skipped characters and a decimal value', 'J<b>..M<b+1>',
    '{GOTO}H<b+20>~/dpriH<b>..H<b+1>~oJ<b>~g',
    ['H<b>=|L>>>S>V>>>>>', 'H<b+1>=''Abc  x 12.50']);
end;

function Sub(const s: string; b: Integer): string;
var
  p, q, n: Integer;
  inner: string;
begin
  Result := s;
  p := Pos('<b', Result);
  while p > 0 do
  begin
    q := p;
    while Result[q] <> '>' do Inc(q);
    inner := Copy(Result, p + 2, q - p - 2);
    if inner = '' then n := b else n := b + StrToInt(Copy(inner, 2, MaxInt));
    Result := Copy(Result, 1, p - 1) + IntToStr(n) + Copy(Result, q + 1, MaxInt);
    p := Pos('<b', Result);
  end;
end;

function RangeOf(const s: string; out r1, c1, r2, c2: Integer): Boolean;
var
  p: Integer;
begin
  p := Pos('..', s);
  Result := (p > 0) and ParseAddr(Copy(s, 1, p - 1), c1, r1) and ParseAddr(Copy(s, p + 2, MaxInt), c2, r2);
end;

function BlockRow(t: Integer): Integer;
begin
  Result := 100 + 30 * t;
end;

procedure PutSetup(S: TSession; const item: string; b: Integer);
var
  line, addr, val: string;
  p, r, c, r1, c1, r2, c2: Integer;
begin
  line := Sub(item, b);
  p := Pos('=', line);
  addr := Copy(line, 1, p - 1);
  val := Copy(line, p + 1, MaxInt);
  if Pos('..', addr) > 0 then
  begin
    RangeOf(addr, r1, c1, r2, c2);
    for r := r1 to r2 do
      for c := c1 to c2 do S.Sheet.Put(r, c, val);
  end
  else if ParseAddr(addr, c, r) then
    S.Sheet.Put(r, c, val)
  else
  begin
    WriteLn('bad setup address: ', line);
    Halt(1);
  end;
end;

{ data, macros and names; withChecks adds the comparison cells }
procedure Build(S: TSession; withChecks: Boolean; expected: TSession);
var
  t, i, b, mr, r, c, r1, c1, r2, c2, p: Integer;
  nm, line, master, act, exp, rs, one, sumf: string;
  ev: TCell;
  dv: Double;
  pc: Char;
  tx: string;
begin
  mr := FirstRow;
  master := '';
  for t := 0 to High(Tests) do
  begin
    b := BlockRow(t);
    S.Sheet.Put(FirstRow + t, 5, '''' + ' ' + Tests[t].Desc);
    for i := 0 to High(Tests[t].Setup) do PutSetup(S, Tests[t].Setup[i], b);
    nm := Format('TST%.2d', [t + 1]);
    S.Sheet.SetName(nm, NormRange(mr, 19, mr, 19));
    master := master + '{' + nm + '}';
    line := Sub(Tests[t].Macro, b);
    { a macro cell holds at most about 240 characters; split at a tilde }
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
    if withChecks then
    begin
      rs := Sub(Tests[t].Result, b);
      sumf := '';
      while rs <> '' do
      begin
        p := Pos(';', rs);
        if p = 0 then begin one := rs; rs := ''; end
        else begin one := Copy(rs, 1, p - 1); rs := Copy(rs, p + 1, MaxInt); end;
        if not RangeOf(one, r1, c1, r2, c2) then
        begin
          WriteLn('bad result range in test ', t + 1);
          Halt(1);
        end;
        for r := r1 to r2 do
          for c := c1 to c2 do
          begin
            ev := expected.Sheet.Find(r, c);
            if (ev <> nil) and (ev.Raw <> '') then
            begin
              if CellNumber(ev, dv) then S.Sheet.Put(r, c + 30, NumToRaw(dv))
              else
              begin
                if TextOf(ev, pc, tx) then S.Sheet.Put(r, c + 30, '''' + tx)
                else S.Sheet.Put(r, c + 30, '@ERR');
              end;
            end;
            act := ColLetter(c) + IntToStr(r);
            exp := ColLetter(c + 30) + IntToStr(r);
            S.Sheet.Put(r, c + 60,
              Format('@IF(@ISERR(%s),@IF(@ISERR(%s),0,1),@IF(@ISSTRING(%s),@IF(@ISSTRING(%s),@IF(@EXACT(%s&"",%s&""),0,1),1),@IF(@ISSTRING(%s),1,@IF(@ISERR(%s),1,@IF(@ABS(%s-%s)<0.000001,0,1)))))',
                [act, exp, act, exp, act, exp, exp, exp, act, exp]));
          end;
        if sumf <> '' then sumf := sumf + '+';
        sumf := sumf + Format('@SUM(%s%d..%s%d)', [ColLetter(c1 + 60), r1, ColLetter(c2 + 60), r2]);
      end;
      S.Sheet.Put(FirstRow + t, 1, sumf);
    end;
  end;
  S.Sheet.SetName('\R', NormRange(1, 19, 1, 19));
  i := 1;
  r := 1;
  while i <= Length(master) do
  begin
    p := i + 60;
    if p > Length(master) then p := Length(master) + 1
    else while (p > i) and (master[p - 1] <> '}') do Dec(p);
    S.Sheet.Put(r, 19, '''' + Copy(master, i, p - i));
    Inc(r);
    i := p;
  end;
end;

procedure Report(S: TSession);
var
  t, b, r, c, r1, c1, r2, c2: Integer;
  line, tx: string;
  pc: Char;
  ev: TCell;
  dv: Double;
begin
  for t := 0 to High(Tests) do
  begin
    b := BlockRow(t);
    WriteLn('Test ', t + 1, ': ', Tests[t].Desc);
    RangeOf(Copy(Sub(Tests[t].Result, b), 1, Pos(';', Sub(Tests[t].Result, b)) - 1), r1, c1, r2, c2);
    for r := r1 to r2 do
    begin
      line := '';
      for c := c1 to c2 do
      begin
        ev := S.Sheet.Find(r, c);
        if (ev = nil) or (ev.Raw = '') then tx := '.'
        else if CellNumber(ev, dv) then tx := FloatToStrF(dv, ffGeneral, 8, 0)
        else if not TextOf(ev, pc, tx) then tx := 'ERR';
        line := line + Copy(Trim(tx) + '            ', 1, 12);
      end;
      WriteLn('   ', line);
    end;
  end;
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
    WriteLn('usage: make_datasheet output.wk1 [-v]');
    Halt(2);
  end;
  DefineTests;
  if GetEnvironmentVariable('LIMIT') <> '' then SetLength(Tests, StrToInt(GetEnvironmentVariable('LIMIT')));
  if GetEnvironmentVariable('ONLY') <> '' then
  begin
    with TStringList.Create do
    begin
      CommaText := GetEnvironmentVariable('ONLY');
      for i := 0 to Count - 1 do Tests[i] := Tests[StrToInt(Strings[i]) - 1];
      SetLength(Tests, Count);
    end;
  end;
  last := FirstRow + High(Tests);

  S1 := TSession.Create;
  Cmds := TCommands.Create;
  RegisterCoreCommands(Cmds);
  Ctl := TController.Create(S1, Cmds);
  M := TMacro.Create(S1);
  Build(S1, False, nil);
  if (ParamCount >= 2) and (ParamStr(2) = '-d') then ;
  S1.Calc.Recalc;
  if GetEnvironmentVariable('TRACE') <> '' then
  begin
    for i := 1 to Length(Tests) do
    begin
      S1.MacroRequest := Format('TST%.2d', [i]);
      M.RunSync(Ctl);
      WriteLn('after test ', i, ': H', 100 + 30 * (Length(Tests) - 1), '=[', S1.Sheet.Find(100 + 30 * (Length(Tests) - 1), 8) <> nil, ']  mode=', Ord(S1.Mode), ' ', S1.Msg, ' prompt=', S1.PromptText, ' entry=', S1.Entry, ' depth=', S1.MenuDepth);
    end;
    Halt(0);
  end;
  S1.MacroRequest := '\R';
  M.RunSync(Ctl);
  if M.Active then
  begin
    WriteLn('the master macro did not finish');
    Halt(1);
  end;
  S1.Calc.Recalc;
  if (ParamCount >= 2) and (ParamStr(2) = '-d') then
    for i := 128 to 160 do
    begin
      msg := '';
      for last := 8 to 14 do
        if S1.Sheet.Find(i, last) <> nil then msg := msg + ' [' + S1.Sheet.Find(i, last).Raw + ']' else msg := msg + ' .';
      WriteLn(i, msg);
    end;
  if (ParamCount >= 2) and (ParamStr(2) = '-v') then Report(S1);

  S2 := TSession.Create;
  S2.Sheet.SetColWidth(1, 4);
  S2.Sheet.SetColWidth(2, 1);
  S2.Sheet.SetColWidth(3, 15);
  S2.Sheet.SetColWidth(4, 15);
  S2.Sheet.SetColWidth(5, 41);
  S2.Sheet.SetColWidth(19, 40);
  S2.Sheet.Put(1, 1, '''mkspread /Data test: press Alt-R, then F9; total of differences in A3');
  S2.Sheet.Put(2, 1, '''A: 0=agree 1=differ. Test data and results: rows 100 + 30 * (test - 1), columns H..R');
  S2.Sheet.Put(3, 3, '''<- differences (0 = all agree)');
  S2.Sheet.Put(5, 1, '''Dif'); S2.Sheet.Put(5, 5, '');
  Build(S2, True, S1);
  S2.Sheet.Put(3, 1, Format('@SUM(A%d..A%d)', [FirstRow, last]));
  S2.Sheet.Put(4, 1, '''Alt-D lists the rows that differ (row, test) from Y7 down');
  S2.Sheet.Put(1, 23, '''{LET X1,0}{FOR X2,7,' + IntToStr(last) + ',1,DCHK}{GOTO}Y7~');
  S2.Sheet.Put(3, 23, Format('''{IF @INDEX(A7..A%d,0,X2-7)=1}{LET X1,X1+1}{PUT Y7..Z300,0,X1-1,X2}{PUT Y7..Z300,1,X1-1,@INDEX(E7..E%d,0,X2-7)}', [last, last]));
  S2.Sheet.SetName('\D', NormRange(1, 23, 1, 23));
  S2.Sheet.SetName('DCHK', NormRange(3, 23, 3, 23));
  for i := 1 to 2 do
    if not S2.Sheet.FindName('\' + Copy('RD', i, 1), g) then
    begin
      WriteLn('macro name missing');
      Halt(1);
    end;
  S2.Calc.Recalc;
  w := TStringList.Create;
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1; info.CursorRow := 3; info.LeftCol := 1; info.TopRow := 1;
  msg := SaveWorksheet(ParamStr(1), S2.Sheet, False, info, w);
  if msg <> '' then begin WriteLn(msg); Halt(1); end;
  if w.Count > 0 then WriteLn(w.Text);
  WriteLn('wrote ', ParamStr(1), ': ', Length(Tests), ' /Data tests');
end.
