{ Generates a worksheet for checking mkspread's behaviour against the original
  program: open it in 1-2-3, let it recalculate, and look at the total in B3.

  Every test row has: the test name (A), the live formula (B, recalculated by
  whatever opens the file), the value mkspread computes (C, stored as a
  constant) and a check (D: 0 = the two agree, 1 = they differ).  Rows that
  need a look rather than a number are in the display sections below.

  Usage: make_testsheet <output.wk1> }
program make_testsheet;
{$mode objfpc}{$H+}

uses SysUtils, Classes, sheet, formula, cellfmt, session, wk1, fn_time;

var
  S: TSession;
  Row: Integer;
  Kinds: array[0..2000] of Char;     { n = number, s = string, e = ERR, a = NA }

function FixedClock: Double;
begin
  Result := 36526.5;
end;

procedure Section(const title: string);
begin
  Inc(Row);
  S.Sheet.Put(Row, 1, '''--- ' + title + ' ---');
  Inc(Row);
end;

procedure T(const desc, f: string);
begin
  S.Sheet.Put(Row, 1, '''' + desc);
  S.Sheet.Put(Row, 2, f);
  Kinds[Row] := '?';
  Inc(Row);
end;

procedure Data;
const
  Stat: array[0..7] of Integer = (2, 4, 4, 4, 5, 5, 7, 9);
var
  i: Integer;
begin
  { test data, columns F..T }
  S.Sheet.Put(4, 6, '''abc');
  for i := 0 to 7 do S.Sheet.Put(6 + i, 6, IntToStr(Stat[i]));
  S.Sheet.Put(6, 7, '4'); S.Sheet.Put(7, 7, '6'); S.Sheet.Put(8, 7, '''text');
  S.Sheet.Put(6, 8, '-100'); S.Sheet.Put(7, 8, '60'); S.Sheet.Put(8, 8, '60');
  S.Sheet.Put(6, 9, '10'); S.Sheet.Put(6, 10, '1');
  S.Sheet.Put(7, 9, '20'); S.Sheet.Put(7, 10, '2');
  S.Sheet.Put(8, 9, '30'); S.Sheet.Put(8, 10, '3');
  S.Sheet.Put(10, 9, '''a'); S.Sheet.Put(10, 10, '''b');
  S.Sheet.Put(11, 9, '5'); S.Sheet.Put(11, 10, '6');
  S.Sheet.Put(6, 11, '10'); S.Sheet.Put(6, 12, '20'); S.Sheet.Put(6, 13, '30');
  S.Sheet.Put(7, 11, '1'); S.Sheet.Put(7, 12, '2'); S.Sheet.Put(7, 13, '3');
  S.Sheet.Put(6, 14, '7').Fmt := MakeFormat(fkCurrency, 2);
  S.Sheet.Put(7, 14, '''lbl');
  S.Sheet.SetColWidth(14, 14);
  { database: Name / Amt }
  S.Sheet.Put(6, 16, '''Name'); S.Sheet.Put(6, 17, '''Amt');
  S.Sheet.Put(7, 16, '''Smith'); S.Sheet.Put(7, 17, '10');
  S.Sheet.Put(8, 16, '''Smyth'); S.Sheet.Put(8, 17, '20');
  S.Sheet.Put(9, 16, '''Jones'); S.Sheet.Put(9, 17, '30');
  S.Sheet.Put(10, 16, '''Smith'); S.Sheet.Put(10, 17, '40');
  S.Sheet.Put(6, 18, '''Name'); S.Sheet.Put(7, 18, '''Smith');
  S.Sheet.Put(6, 19, '''Name'); S.Sheet.Put(7, 19, '''Sm?th'); S.Sheet.Put(8, 19, '''Jones');
  S.Sheet.Put(6, 20, '''Amt'); S.Sheet.Put(7, 20, '''>15');
  S.Sheet.Put(3, 6, '''Test data used by the formulas (F4:T11)');
end;

procedure Tests;
begin
  Section('Operators and precedence');
  T('1+2*3', '1+2*3');
  T('(1+2)*3', '(1+2)*3');
  T('2^3^2  (left to right: 64)', '2^3^2');
  T('-2^2  (exponent first: -4)', '-2^2');
  T('2^-1', '2^-1');
  T('10-4-3', '10-4-3');
  T('1/0', '1/0');
  T('3>2', '+3>2');
  T('1<2 #AND# 2<3', '1<2#AND#2<3');
  T('#NOT# 0', '#NOT#0');
  T('1+2>2  (arithmetic before comparison)', '1+2>2');
  T('string join', '+"ab"&"cd"');
  T('text compare ignores case?', '+"abc"="ABC"');
  T('string in arithmetic', '+"a"+1');
  T('label counts as zero: F4+1', '+F4+1');
  T('label in a string formula', '+F4&"x"');
  T('blank cell counts as zero', '+Z99+1');
  T('blank cell in a string formula', '+Z99&"x"');
  T('number in a string formula', '+F6&"x"');

  Section('Math');
  T('@ABS(-3)', '@ABS(-3)');
  T('@INT(-3.7)  (truncates)', '@INT(-3.7)');
  T('@SQRT(16)', '@SQRT(16)');
  T('@SQRT(-1)', '@SQRT(-1)');
  T('@LOG(100)', '@LOG(100)');
  T('@LN(1)', '@LN(1)');
  T('@EXP(0)', '@EXP(0)');
  T('@PI', '@PI');
  T('@ATAN(1)*4', '@ATAN(1)*4');
  T('@ATAN2(1,1)', '@ATAN2(1,1)');
  T('@ATAN2(-1,0)', '@ATAN2(-1,0)');
  T('@ASIN(2)', '@ASIN(2)');
  T('@MOD(7,3)', '@MOD(7,3)');
  T('@MOD(-7,3)  (sign of x)', '@MOD(-7,3)');
  T('@MOD(5,0)', '@MOD(5,0)');
  T('@ROUND(2.5,0)', '@ROUND(2.5,0)');
  T('@ROUND(-2.5,0)', '@ROUND(-2.5,0)');
  T('@ROUND(1234.5678,2)', '@ROUND(1234.5678,2)');
  T('@ROUND(1234,-2)', '@ROUND(1234,-2)');

  Section('Logic');
  T('@IF(1,5,6)', '@IF(1,5,6)');
  T('@IF(0,5,6)', '@IF(0,5,6)');
  T('@IF(1,5,1/0)  (only the chosen branch)', '@IF(1,5,1/0)');
  T('@CHOOSE(1,10,20,30)  (counts from 0)', '@CHOOSE(1,10,20,30)');
  T('@CHOOSE(5,1,2)', '@CHOOSE(5,1,2)');
  T('@ISNA(@NA)', '@ISNA(@NA)');
  T('@ISNA(@ERR)', '@ISNA(@ERR)');
  T('@ISERR(@ERR)', '@ISERR(@ERR)');
  T('@ISERR(@NA)  (is NA an error?)', '@ISERR(@NA)');
  T('@ISNUMBER(5)', '@ISNUMBER(5)');
  T('@ISNUMBER("a")', '@ISNUMBER("a")');
  T('@ISSTRING("a")', '@ISSTRING("a")');
  T('@ISNUMBER(blank cell)', '@ISNUMBER(Z99)');
  T('@ISSTRING(blank cell)', '@ISSTRING(Z99)');
  T('@ISSTRING(label cell F4)', '@ISSTRING(F4)');
  T('@NA+1', '@NA+1');
  T('@ERR+@NA', '@ERR+@NA');

  Section('Text');
  T('@LENGTH("hello")', '@LENGTH("hello")');
  T('@LEFT("hello",2)', '@LEFT("hello",2)');
  T('@RIGHT("hello",2)', '@RIGHT("hello",2)');
  T('@MID("hello",1,3)  (start counts from 0)', '@MID("hello",1,3)');
  T('@REPEAT("ab",3)', '@REPEAT("ab",3)');
  T('@UPPER("abc")', '@UPPER("abc")');
  T('@LOWER("ABC")', '@LOWER("ABC")');
  T('@PROPER("hello wORLD 3x")', '@PROPER("hello wORLD 3x")');
  T('@TRIM("  a   b  ")', '@TRIM("  a   b  ")');
  T('@EXACT("a","A")', '@EXACT("a","A")');
  T('@REPLACE("abcdef",1,2,"XY")', '@REPLACE("abcdef",1,2,"XY")');
  T('@FIND("c","abcabc",0)', '@FIND("c","abcabc",0)');
  T('@FIND("c","abcabc",3)', '@FIND("c","abcabc",3)');
  T('@FIND("z","abc",0)', '@FIND("z","abc",0)');
  T('@STRING(3.14159,2)', '@STRING(3.14159,2)');
  T('@VALUE("12.5")', '@VALUE("12.5")');
  T('@VALUE("abc")', '@VALUE("abc")');
  T('@CHAR(65)', '@CHAR(65)');
  T('@CODE("A")', '@CODE("A")');

  Section('Dates and times');
  T('@DATE(100,1,1)  (1-Jan-2000)', '@DATE(100,1,1)');
  T('@DATE(96,2,29)', '@DATE(96,2,29)');
  T('@DATE(96,2,30)', '@DATE(96,2,30)');
  T('@DATE(1996,1,1)  (year must be 0..199?)', '@DATE(1996,1,1)');
  T('@DATE(0,2,29)  (the 1900 leap-year quirk)', '@DATE(0,2,29)');
  T('@DAY(35124)', '@DAY(35124)');
  T('@MONTH(35124)', '@MONTH(35124)');
  T('@YEAR(35124)', '@YEAR(35124)');
  T('@TIME(12,0,0)', '@TIME(12,0,0)');
  T('@TIME(24,0,0)', '@TIME(24,0,0)');
  T('@HOUR(0.75)', '@HOUR(0.75)');
  T('@MINUTE(@TIME(1,23,45))', '@MINUTE(@TIME(1,23,45))');
  T('@SECOND(@TIME(1,23,45))', '@SECOND(@TIME(1,23,45))');
  T('@DATEVALUE("29-Feb-96")', '@DATEVALUE("29-Feb-96")');
  T('@DATEVALUE("Mar-96")', '@DATEVALUE("Mar-96")');
  T('@TIMEVALUE("1:30 PM")', '@TIMEVALUE("1:30 PM")');

  Section('Financial');
  T('@PMT(1000,0.01,12)', '@PMT(1000,0.01,12)');
  T('@PV(100,0.01,12)', '@PV(100,0.01,12)');
  T('@FV(100,0.01,12)', '@FV(100,0.01,12)');
  T('@NPV(0.1,G6:G7)', '@NPV(0.1,G6..G7)');
  T('@IRR(0.1,H6:H8)', '@IRR(0.1,H6..H8)');
  T('@TERM(100,0.01,1200)', '@TERM(100,0.01,1200)');
  T('@CTERM(0.1,2000,1000)', '@CTERM(0.1,2000,1000)');
  T('@RATE(2000,1000,10)', '@RATE(2000,1000,10)');
  T('@SLN(1000,100,9)', '@SLN(1000,100,9)');
  T('@SYD(1000,100,3,1)', '@SYD(1000,100,3,1)');
  T('@DDB(1000,100,5,1)', '@DDB(1000,100,5,1)');
  T('@DDB(1000,100,5,5)', '@DDB(1000,100,5,5)');

  Section('Statistics (data in F6:H8)');
  T('@SUM(F6:F13)', '@SUM(F6..F13)');
  T('@AVG(F6:F13)', '@AVG(F6..F13)');
  T('@STD(F6:F13)  (population?)', '@STD(F6..F13)');
  T('@VAR(F6:F13)  (population?)', '@VAR(F6..F13)');
  T('@AVG(G6:G8)  (a label in the range)', '@AVG(G6..G8)');
  T('@COUNT(G6:G8)  (counts labels?)', '@COUNT(G6..G8)');
  T('@MIN(G6:G8)  (label counts as zero?)', '@MIN(G6..G8)');
  T('@MAX(G6:G8)', '@MAX(G6..G8)');
  T('@SUM(G6:G8,10)', '@SUM(G6..G8,10)');

  Section('Lookup and information');
  T('@VLOOKUP(25,I6:J8,1)', '@VLOOKUP(25,I6..J8,1)');
  T('@VLOOKUP(5,I6:J8,1)  (below the table)', '@VLOOKUP(5,I6..J8,1)');
  T('@VLOOKUP("a",I10:J11,1)', '@VLOOKUP("a",I10..J11,1)');
  T('@HLOOKUP(25,K6:M7,1)', '@HLOOKUP(25,K6..M7,1)');
  T('@INDEX(I6:J8,1,2)  (column, row from 0)', '@INDEX(I6..J8,1,2)');
  T('@COLS(I6:J8)', '@COLS(I6..J8)');
  T('@ROWS(I6:J8)', '@ROWS(I6..J8)');
  T('@N(G7)', '@N(G7)');
  T('@S(G8)', '@S(G8)');
  T('@CELL("address",C7)', '@CELL("address",C7)');
  T('@CELL("col",C7)', '@CELL("col",C7)');
  T('@CELL("row",C7)', '@CELL("row",C7)');
  T('@CELL("type",G6)', '@CELL("type",G6)');
  T('@CELL("type",G8)', '@CELL("type",G8)');
  T('@CELL("type",Z99)', '@CELL("type",Z99)');
  T('@CELL("format",N6)  (currency 2)', '@CELL("format",N6)');
  T('@CELL("width",N6)  (column set to 14)', '@CELL("width",N6)');
  T('@CELL("prefix",N7)', '@CELL("prefix",N7)');
  T('@@("G6")*2', '@@("G6")*2');

  Section('Database (P6:Q10; criteria R6:R7, S6:S8, T6:T7)');
  T('@DSUM(P6:Q10,1,R6:R7)  Name = Smith', '@DSUM(P6..Q10,1,R6..R7)');
  T('@DCOUNT(P6:Q10,1,R6:R7)', '@DCOUNT(P6..Q10,1,R6..R7)');
  T('@DSUM with wildcard Sm?th or Jones', '@DSUM(P6..Q10,1,S6..S8)');
  T('@DAVG Amt > 15', '@DAVG(P6..Q10,1,T6..T7)');
  T('@DMAX Name = Smith', '@DMAX(P6..Q10,1,R6..R7)');
  T('@DMIN Name = Smith', '@DMIN(P6..Q10,1,R6..R7)');
  T('@DSTD Name = Smith', '@DSTD(P6..Q10,1,R6..R7)');
  T('@DVAR Name = Smith', '@DVAR(P6..Q10,1,R6..R7)');
end;

procedure FinishTests(firstRow, lastRow: Integer);
var
  r: Integer;
  cell: TCell;
  f: string;
begin
  S.Calc.Recalc;
  for r := firstRow to lastRow do
  begin
    if Kinds[r] <> '?' then continue;
    cell := S.Sheet.Find(r, 2);
    case cell.Val.Kind of
      vkNum:
        begin
          S.Sheet.Put(r, 3, NumToRaw(cell.Val.Num));
          f := Format('@IF(@ISNUMBER(B%d),@IF(@ABS(B%d-C%d)<0.000001,0,1),1)', [r, r, r]);
        end;
      vkStr:
        begin
          S.Sheet.Put(r, 3, '''' + cell.Val.Str);
          f := Format('@IF(@ISSTRING(B%d),@IF(@EXACT(B%d,C%d),0,1),1)', [r, r, r]);
        end;
      vkNA:
        begin
          S.Sheet.Put(r, 3, '''NA');
          f := Format('@IF(@ISNA(B%d),0,1)', [r]);
        end;
    else
      S.Sheet.Put(r, 3, '''ERR');
      f := Format('@IF(@ISERR(B%d),0,1)', [r]);
    end;
    S.Sheet.Put(r, 4, f);
  end;
end;

procedure Display(firstRow: Integer);
var
  r: Integer;
  c: TCell;

  procedure D(const desc: string; const raw: string; fmt: TCellFormat);
  begin
    S.Sheet.Put(r, 1, '''' + desc);
    c := S.Sheet.Put(r, 2, raw);
    c.Fmt := fmt;
    c.Fmt.UseGlobal := False;
    S.Sheet.Put(r, 3, '''' + ValueText(c, S.Sheet, 12));
    Inc(r);
  end;

begin
  r := firstRow;
  S.Sheet.Put(r, 1, '''--- Display: compare column B with the text in column C (mkspread''s rendering) ---');
  Inc(r, 2);
  D('Fixed 2: 1234.5678', '1234.5678', MakeFormat(fkFixed, 2));
  D('Fixed 0: 2.5', '2.5', MakeFormat(fkFixed, 0));
  D('Scientific 2: 12345.678', '12345.678', MakeFormat(fkSci, 2));
  D('Currency 2: 1234.5', '1234.5', MakeFormat(fkCurrency, 2));
  D('Currency 2: -5', '-5', MakeFormat(fkCurrency, 2));
  D('Comma 2: 1234567.891', '1234567.891', MakeFormat(fkComma, 2));
  D('Comma 0: -1234', '-1234', MakeFormat(fkComma, 0));
  D('Percent 1: 0.256', '0.256', MakeFormat(fkPercent, 1));
  D('+/-: 3', '3', MakeFormat(fkPlusMinus, 0));
  D('+/-: -2', '-2', MakeFormat(fkPlusMinus, 0));
  D('General: 3.50', '3.5', MakeFormat(fkGeneral, 0));
  D('General: 0.1234567891234', '0.1234567891234', MakeFormat(fkGeneral, 0));
  D('General: 1234567890123 (wide number)', '1234567890123', MakeFormat(fkGeneral, 0));
  D('Date D1: 36526', '36526', MakeFormat(fkDate, 1));
  D('Date D2: 36526', '36526', MakeFormat(fkDate, 2));
  D('Date D3: 36526', '36526', MakeFormat(fkDate, 3));
  D('Date D4: 36526', '36526', MakeFormat(fkDate, 4));
  D('Date D5: 36526', '36526', MakeFormat(fkDate, 5));
  D('Time D6: 0.5625', '0.5625', MakeFormat(fkDate, 6));
  D('Time D7: 0.5625', '0.5625', MakeFormat(fkDate, 7));
  D('Time D8: 0.5625', '0.5625', MakeFormat(fkDate, 8));
  D('Time D9: 0.5625', '0.5625', MakeFormat(fkDate, 9));
  D('Date D1: serial 60 (1900 leap day)', '60', MakeFormat(fkDate, 1));
  D('Text format of a formula', '1+2', MakeFormat(fkText, 0));
  D('Hidden: 42', '42', MakeFormat(fkHidden, 0));
  Inc(r);
  S.Sheet.Put(r, 1, '''--- Labels: prefixes ---');
  Inc(r);
  S.Sheet.Put(r, 1, '''left (apostrophe)'); S.Sheet.Put(r, 2, '''left'); Inc(r);
  S.Sheet.Put(r, 1, '''right (quote)'); S.Sheet.Put(r, 2, '"right'); Inc(r);
  S.Sheet.Put(r, 1, '''center (caret)'); S.Sheet.Put(r, 2, '^center'); Inc(r);
  S.Sheet.Put(r, 1, '''repeat (backslash)'); S.Sheet.Put(r, 2, '\-='); Inc(r);
  S.Sheet.Put(r, 1, '''accents (LICS)'); S.Sheet.Put(r, 2, '''caf' + UTF8Encode(WideChar($E9)) + ' ' + UTF8Encode(WideChar($A3)) + UTF8Encode(WideChar($B0)) + UTF8Encode(WideChar($D1)));
end;

var
  last: Integer;
  info: TFileInfo;
  w: TStringList;
  msg: string;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: make_testsheet output.wk1');
    Halt(2);
  end;
  fn_time.ClockNow := @FixedClock;
  S := TSession.Create;
  S.Sheet.SetColWidth(1, 44);
  S.Sheet.SetColWidth(2, 16);
  S.Sheet.SetColWidth(3, 16);
  S.Sheet.SetColWidth(4, 6);
  S.Sheet.Put(1, 1, '''mkspread test worksheet: open in 1-2-3, recalculate (F9), read the total in B3');
  S.Sheet.Put(2, 1, '''Column B is live; C is what mkspread computed; D is 0 when they agree, 1 when they differ');
  S.Sheet.Put(3, 1, '''Total differences (0 = everything agrees):');
  S.Sheet.Put(5, 1, '''Test'); S.Sheet.Put(5, 2, '''1-2-3 value'); S.Sheet.Put(5, 3, '''mkspread value'); S.Sheet.Put(5, 4, '''Diff');
  Data;
  Row := 5;
  Tests;
  last := Row - 1;
  FinishTests(6, last);
  S.Sheet.Put(3, 2, Format('@SUM(D6..D%d)', [last]));
  Display(last + 3);
  S.Calc.Recalc;
  w := TStringList.Create;
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 2; info.CursorRow := 3; info.LeftCol := 1; info.TopRow := 1;
  msg := SaveWorksheet(ParamStr(1), S.Sheet, False, info, w);
  if msg <> '' then begin WriteLn(msg); Halt(1); end;
  WriteLn(w.Text);
  WriteLn('wrote ', ParamStr(1), ': ', last - 5, ' test rows, total in B3 = ', S.Sheet.Find(3, 2).Val.Num:0:0);
end.
