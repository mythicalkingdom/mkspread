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

{ Formula parsing and evaluation.  Independent of the worksheet: cell values
  come in through a TCellSource.

  Operator precedence, highest first (ASSUMED from memory of the classic
  behaviour; verify against real files and macros when the test corpus exists):
    ^   (left to right: 2^3^2 = 64)
    unary + and -
    *  /
    +  -  &
    =  <>  <  >  <=  >=
    #NOT#
    #AND#  #OR#
  Other quirks kept on purpose: a label (text cell) counts as 0 in arithmetic,
  an empty cell is 0 (or "" for &), & refuses numbers, text compares with text
  only, a string literal in arithmetic is an error. }
unit formula;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils;

type
  TRpnWriter = class;

  TValKind = (vkNum, vkStr, vkErr, vkNA);

  TValue = record
    Kind: TValKind;
    Num: Double;
    Str: string;
    IsLabel: Boolean;       { came from a text cell: counts as 0 in arithmetic }
    IsEmpty: Boolean;       { came from an empty cell }
  end;

  TAccumulator = class
  public
    procedure Add(const v: TValue); virtual; abstract;
  end;

  { Supplies cell contents to a formula while it is evaluated. }
  TCellSource = class
  public
    function CellValue(r, c: Integer): TValue; virtual; abstract;
    { resolves a range name; False when the name is not defined }
    function LookupName(const name: string; out r1, c1, r2, c2: Integer): Boolean; virtual; abstract;
    { calls acc.Add for every non-empty cell in the rectangle }
    procedure Accumulate(r1, c1, r2, c2: Integer; acc: TAccumulator); virtual; abstract;
  end;

  { Rewrites cell references when cells are copied, moved, inserted or
    deleted.  Return False when the reference no longer points anywhere (it
    becomes @ERR in the formula text). }
  TRefMapper = class
  public
    function MapCell(var r, c: Integer; absR, absC: Boolean): Boolean; virtual; abstract;
    { default: map both corners with MapCell, then put them in order }
    function MapRange(var r1, c1, r2, c2: Integer; absR1, absC1, absR2, absC2: Boolean): Boolean; virtual;
  end;

  TNode = class
  public
    function Eval(src: TCellSource): TValue; virtual; abstract;
    function ToText: string; virtual; abstract;
    function Mapped(m: TRefMapper): string; virtual; abstract;
    procedure Emit(w: TRpnWriter); virtual; abstract;
  end;

  TNodeArray = array of TNode;

  TFormula = class
  private
    FPool: TList;          { owns every node }
    FRoot: TNode;
    FText: string;
  public
    constructor Create;
    destructor Destroy; override;
    function Eval(src: TCellSource): TValue;
    { canonical text with every reference run through the mapper }
    function MappedText(m: TRefMapper): string;
    procedure Emit(w: TRpnWriter);          { the formula as RPN, ending without a return }
    property Text: string read FText;    { canonical text, e.g. +A1+B2 }
    property Root: TNode read FRoot;
  end;

function NumValue(d: Double): TValue;
function StrValue(const s: string): TValue;
function ErrValue: TValue;
function NAValue: TValue;
function EmptyValue: TValue;

{ True for text that is just a number: 12, -3.5, .5, 1E3 }
{ ---- the @function table, for the file formats ---- }
function FuncCount: Integer;
function FuncIndexByOpcode(opcode: Integer): Integer;          { -1 if none }
function FuncName(i: Integer): string;
function FuncOpcode(i: Integer): Integer;
function FuncMinArgs(i: Integer): Integer;
function FuncMaxArgs(i: Integer): Integer;
function FuncIsList(i: Integer): Boolean;
function FuncImplemented(i: Integer): Boolean;

{ ---- converting a formula to the file format's reverse Polish code ---- }
type
  TRpnWriter = class
  public
    { name -> range; False if undefined (the formula then gets @ERR) }
    function ResolveName(const name: string; out r1, c1, r2, c2: Integer): Boolean; virtual; abstract;
    procedure PutNumber(d: Double); virtual; abstract;
    procedure PutString(const s: string); virtual; abstract;
    procedure PutRef(r, c: Integer; absR, absC: Boolean); virtual; abstract;
    procedure PutRange(r1, c1, r2, c2: Integer; aR1, aC1, aR2, aC2: Boolean); virtual; abstract;
    procedure PutOp(opcode: Integer); virtual; abstract;       { operators 8..24 }
    procedure PutFunc(opcode, argc: Integer; isList: Boolean); virtual; abstract;
    procedure PutParen; virtual; abstract;
  end;

{ Range names: up to 15 letters, digits and underscores, not starting with a
  digit, and not something that reads as a cell address. }
function IsValidName(const s: string): Boolean;
function IsCellAddress(const s: string): Boolean;

function IsNumberLiteral(const s: string; out d: Double): Boolean;
{ Shortest text that reads back as the same value (15 significant digits) }
function NumToRaw(d: Double): string;

{ Compile a formula.  errPos is the 1-based byte position of the problem. }
function CompileFormula(const text: string; out f: TFormula; out errPos: Integer): Boolean;

implementation

uses Math;

type
  EFormula = class(Exception)
  public
    Pos: Integer;
  end;

  TNumNode = class(TNode)
  public
    Value: Double;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TStrNode = class(TNode)
  public
    Value: string;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TRefNode = class(TNode)
  public
    Row, Col: Integer;
    AbsRow, AbsCol: Boolean;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TRangeNode = class(TNode)
  public
    A, B: TRefNode;            { normalised: A is top-left, B bottom-right }
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TNameNode = class(TNode)
  public
    Name: string;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TParenNode = class(TNode)
  public
    Inner: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TUnaryNode = class(TNode)
  public
    Op: string;                { '+', '-', '#NOT#' }
    Elide: Boolean;            { leading formula marker: not stored in files }
    Operand: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TBinaryNode = class(TNode)
  public
    Op: string;
    Left, Right: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

  TFuncProc = function(const args: TNodeArray; src: TCellSource): TValue;

  TFuncDef = record
    Name: string;
    MinArgs, MaxArgs: Integer;
    Proc: TFuncProc;
    Opcode: Integer;           { number in the worksheet file format }
    IsList: Boolean;           { file stores an argument-count byte }
  end;

  TFuncNode = class(TNode)
  public
    Def: Integer;              { index into the function table }
    Args: TNodeArray;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
    function Mapped(m: TRefMapper): string; override;
    procedure Emit(w: TRpnWriter); override;
  end;

{ ------------------------------------------------------------------ values }

function NumValue(d: Double): TValue;
begin
  Result.Kind := vkNum;
  Result.Num := d;
  Result.Str := '';
  Result.IsLabel := False;
  Result.IsEmpty := False;
  if IsNan(d) or IsInfinite(d) then Result.Kind := vkErr;
end;

function StrValue(const s: string): TValue;
begin
  Result := NumValue(0);
  Result.Kind := vkStr;
  Result.Str := s;
end;

function ErrValue: TValue;
begin
  Result := NumValue(0);
  Result.Kind := vkErr;
end;

function NAValue: TValue;
begin
  Result := NumValue(0);
  Result.Kind := vkNA;
end;

function EmptyValue: TValue;
begin
  Result := NumValue(0);
  Result.IsEmpty := True;
end;

function IsNumberLiteral(const s: string; out d: Double): Boolean;
var
  i, n: Integer;
  code: Integer;
begin
  d := 0;
  Result := False;
  i := 1;
  if (i <= Length(s)) and (s[i] in ['+', '-']) then Inc(i);
  n := 0;
  while (i <= Length(s)) and (s[i] in ['0'..'9']) do begin Inc(i); Inc(n); end;
  if (i <= Length(s)) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= Length(s)) and (s[i] in ['0'..'9']) do begin Inc(i); Inc(n); end;
  end;
  if n = 0 then exit;                              { needs at least one digit before any exponent }
  if (i <= Length(s)) and (s[i] in ['e', 'E']) then
  begin
    Inc(i);
    if (i <= Length(s)) and (s[i] in ['+', '-']) then Inc(i);
    n := 0;
    while (i <= Length(s)) and (s[i] in ['0'..'9']) do begin Inc(i); Inc(n); end;
    if n = 0 then exit;
  end;
  if i <= Length(s) then exit;
  Val(s, d, code);
  Result := code = 0;
end;

function NumToRaw(d: Double): string;
var
  fs: TFormatSettings;
  back: Double;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(d, ffGeneral, 15, 0, fs);
  { 15 digits are what people type; files can hold doubles that need 17 }
  if (TryStrToFloat(Result, back, fs)) and (back <> d) then
    Result := FloatToStrF(d, ffGeneral, 17, 0, fs);
end;

{ numeric view of a value: ok = False means it cannot be used as a number }
function Numeric(const v: TValue; out d: Double): Boolean;
begin
  Result := True;
  case v.Kind of
    vkNum: d := v.Num;
    vkStr:
      if v.IsLabel then d := 0 else Result := False;
  else
    Result := False;
  end;
end;

function ColText(c: Integer): string;
begin
  if c <= 26 then Result := Chr(64 + c)
  else Result := Chr(64 + (c - 1) div 26) + Chr(65 + (c - 1) mod 26);
end;

{ ------------------------------------------------------------------ evaluation }

function TNumNode.Eval(src: TCellSource): TValue;
begin
  Result := NumValue(Value);
end;

function TNumNode.ToText: string;
begin
  Result := NumToRaw(Value);
end;

function TStrNode.Eval(src: TCellSource): TValue;
begin
  Result := StrValue(Value);
end;

function TStrNode.ToText: string;
begin
  Result := '"' + Value + '"';
end;

function TRefNode.Eval(src: TCellSource): TValue;
begin
  Result := src.CellValue(Row, Col);
end;

function TRefNode.ToText: string;
begin
  Result := '';
  if AbsCol then Result := '$';
  Result := Result + ColText(Col);
  if AbsRow then Result := Result + '$';
  Result := Result + IntToStr(Row);
end;

function TRangeNode.Eval(src: TCellSource): TValue;
begin
  Result := ErrValue;            { a range is only meaningful inside a function }
end;

function TRangeNode.ToText: string;
begin
  Result := A.ToText + '..' + B.ToText;
end;

function TParenNode.Eval(src: TCellSource): TValue;
begin
  Result := Inner.Eval(src);
end;

function TParenNode.ToText: string;
begin
  Result := '(' + Inner.ToText + ')';
end;

function TUnaryNode.Eval(src: TCellSource): TValue;
var
  v: TValue;
  d: Double;
begin
  v := Operand.Eval(src);
  if v.Kind = vkErr then exit(ErrValue);
  if v.Kind = vkNA then exit(NAValue);
  if Op = '+' then exit(v);                { unary plus changes nothing (ASSUMED) }
  if not Numeric(v, d) then exit(ErrValue);
  if Op = '-' then Result := NumValue(-d)
  else if d = 0 then Result := NumValue(1)       { #NOT# }
  else Result := NumValue(0);
end;

function TUnaryNode.ToText: string;
begin
  Result := Op + Operand.ToText;
end;

function Compare(const a, b: TValue; out cmp: Integer): Boolean;
var
  x, y: Double;
  s, t: string;
begin
  Result := True;
  if (a.Kind = vkStr) or (b.Kind = vkStr) then
  begin
    { text compares with text; an empty cell counts as "" }
    if a.Kind = vkStr then s := a.Str
    else if a.IsEmpty then s := ''
    else exit(False);
    if b.Kind = vkStr then t := b.Str
    else if b.IsEmpty then t := ''
    else exit(False);
    cmp := CompareText(s, t);
  end
  else
  begin
    x := a.Num;
    y := b.Num;
    if x < y then cmp := -1 else if x > y then cmp := 1 else cmp := 0;
  end;
end;

function TBinaryNode.Eval(src: TCellSource): TValue;
var
  l, r: TValue;
  x, y, z: Double;
  cmp: Integer;
  s, t: string;
begin
  l := Left.Eval(src);
  r := Right.Eval(src);
  if (l.Kind = vkErr) or (r.Kind = vkErr) then exit(ErrValue);
  if (l.Kind = vkNA) or (r.Kind = vkNA) then exit(NAValue);

  if Op = '&' then
  begin
    if l.Kind = vkStr then s := l.Str else if l.IsEmpty then s := '' else exit(ErrValue);
    if r.Kind = vkStr then t := r.Str else if r.IsEmpty then t := '' else exit(ErrValue);
    exit(StrValue(s + t));
  end;

  if (Op = '=') or (Op = '<>') or (Op = '<') or (Op = '>') or (Op = '<=') or (Op = '>=') then
  begin
    if not Compare(l, r, cmp) then exit(ErrValue);
    if Op = '=' then z := Ord(cmp = 0)
    else if Op = '<>' then z := Ord(cmp <> 0)
    else if Op = '<' then z := Ord(cmp < 0)
    else if Op = '>' then z := Ord(cmp > 0)
    else if Op = '<=' then z := Ord(cmp <= 0)
    else z := Ord(cmp >= 0);
    exit(NumValue(z));
  end;

  if not (Numeric(l, x) and Numeric(r, y)) then exit(ErrValue);
  if Op = '+' then z := x + y
  else if Op = '-' then z := x - y
  else if Op = '*' then z := x * y
  else if Op = '/' then
  begin
    if y = 0 then exit(ErrValue);
    z := x / y;
  end
  else if Op = '^' then
  begin
    if (x = 0) and (y <= 0) then exit(ErrValue);
    if (x < 0) and (Frac(y) <> 0) then exit(ErrValue);
    z := Power(x, y);
  end
  else if Op = '#AND#' then z := Ord((x <> 0) and (y <> 0))
  else if Op = '#OR#' then z := Ord((x <> 0) or (y <> 0))
  else exit(ErrValue);
  Result := NumValue(z);
end;

function TBinaryNode.ToText: string;
begin
  Result := Left.ToText + Op + Right.ToText;
end;

{ ------------------------------------------------------------------ functions }

type
  TSumAcc = class(TAccumulator)
  public
    Total: Double;
    Err, NA: Boolean;
    procedure Add(const v: TValue); override;
  end;

procedure TSumAcc.Add(const v: TValue);
begin
  case v.Kind of
    vkNum: if not v.IsEmpty then Total := Total + v.Num;
    vkErr: Err := True;
    vkNA: NA := True;
  end;                                  { text is ignored }
end;

function RangeOf(node: TNode; src: TCellSource; out r1, c1, r2, c2: Integer): Boolean; forward;

function FnSum(const args: TNodeArray; src: TCellSource): TValue;
var
  acc: TSumAcc;
  i: Integer;
  v: TValue;
  d: Double;
  r1, c1, r2, c2: Integer;
begin
  acc := TSumAcc.Create;
  try
    for i := 0 to High(args) do
      if RangeOf(args[i], src, r1, c1, r2, c2) then
        src.Accumulate(r1, c1, r2, c2, acc)
      else
      begin
        v := args[i].Eval(src);
        if v.Kind = vkErr then acc.Err := True
        else if v.Kind = vkNA then acc.NA := True
        else if Numeric(v, d) then acc.Total := acc.Total + d
        else acc.Err := True;
      end;
    if acc.Err then Result := ErrValue
    else if acc.NA then Result := NAValue
    else Result := NumValue(acc.Total);
  finally
    acc.Free;
  end;
end;

function FnNA(const args: TNodeArray; src: TCellSource): TValue;
begin
  Result := NAValue;
end;

function FnErr(const args: TNodeArray; src: TCellSource): TValue;
begin
  Result := ErrValue;
end;

function FnTrue(const args: TNodeArray; src: TCellSource): TValue;
begin
  Result := NumValue(1);
end;

function FnFalse(const args: TNodeArray; src: TCellSource): TValue;
begin
  Result := NumValue(0);
end;

function FnPi(const args: TNodeArray; src: TCellSource): TValue;
begin
  Result := NumValue(Pi);
end;

{ numeric value of a scalar argument; False with err set when it cannot be one }
function NumArg(node: TNode; src: TCellSource; out d: Double; out bad: TValue): Boolean;
var
  v: TValue;
begin
  d := 0;
  v := node.Eval(src);
  if v.Kind = vkErr then begin bad := ErrValue; exit(False); end;
  if v.Kind = vkNA then begin bad := NAValue; exit(False); end;
  if not Numeric(v, d) then begin bad := ErrValue; exit(False); end;
  Result := True;
end;

function FnRound(const args: TNodeArray; src: TCellSource): TValue;
var
  x, n, scale: Double;
  bad: TValue;
begin
  if not NumArg(args[0], src, x, bad) then exit(bad);
  if not NumArg(args[1], src, n, bad) then exit(bad);
  n := Trunc(n);
  if Abs(n) > 300 then exit(ErrValue);
  scale := Power(10, n);
  if x >= 0 then Result := NumValue(Int(x * scale + 0.5) / scale)
  else Result := NumValue(-Int(-x * scale + 0.5) / scale);
end;

{ payment per period for a loan: principal, interest rate per period, periods }
function FnPmt(const args: TNodeArray; src: TCellSource): TValue;
var
  p, i, n: Double;
  bad: TValue;
begin
  if not NumArg(args[0], src, p, bad) then exit(bad);
  if not NumArg(args[1], src, i, bad) then exit(bad);
  if not NumArg(args[2], src, n, bad) then exit(bad);
  if n <= 0 then exit(ErrValue);
  if i = 0 then exit(NumValue(p / n));
  if i <= -1 then exit(ErrValue);
  Result := NumValue(p * i / (1 - Power(1 + i, -n)));
end;

const
  { Every 1-2-3 @function the file formats know, with its file opcode.  Proc is
    nil for the ones not implemented yet: they parse, round-trip through files,
    and evaluate to ERR until the function library phase fills them in. }
  Funcs: array[0..84] of TFuncDef = (
    (Name: 'SUM'; MinArgs: 1; MaxArgs: 255; Proc: @FnSum; Opcode: 80; IsList: True),
    (Name: 'NA'; MinArgs: 0; MaxArgs: 0; Proc: @FnNA; Opcode: 31; IsList: False),
    (Name: 'ERR'; MinArgs: 0; MaxArgs: 0; Proc: @FnErr; Opcode: 32; IsList: False),
    (Name: 'TRUE'; MinArgs: 0; MaxArgs: 0; Proc: @FnTrue; Opcode: 52; IsList: False),
    (Name: 'FALSE'; MinArgs: 0; MaxArgs: 0; Proc: @FnFalse; Opcode: 51; IsList: False),
    (Name: 'PI'; MinArgs: 0; MaxArgs: 0; Proc: @FnPi; Opcode: 38; IsList: False),
    (Name: 'ROUND'; MinArgs: 2; MaxArgs: 2; Proc: @FnRound; Opcode: 63; IsList: False),
    (Name: 'PMT'; MinArgs: 3; MaxArgs: 3; Proc: @FnPmt; Opcode: 56; IsList: False),
    (Name: 'ABS'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 33; IsList: False),
    (Name: 'INT'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 34; IsList: False),
    (Name: 'SQRT'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 35; IsList: False),
    (Name: 'LOG'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 36; IsList: False),
    (Name: 'LN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 37; IsList: False),
    (Name: 'SIN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 39; IsList: False),
    (Name: 'COS'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 40; IsList: False),
    (Name: 'TAN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 41; IsList: False),
    (Name: 'ATAN2'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 42; IsList: False),
    (Name: 'ATAN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 43; IsList: False),
    (Name: 'ASIN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 44; IsList: False),
    (Name: 'ACOS'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 45; IsList: False),
    (Name: 'EXP'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 46; IsList: False),
    (Name: 'MOD'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 47; IsList: False),
    (Name: 'CHOOSE'; MinArgs: 2; MaxArgs: 255; Proc: nil; Opcode: 48; IsList: True),
    (Name: 'ISNA'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 49; IsList: False),
    (Name: 'ISERR'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 50; IsList: False),
    (Name: 'RAND'; MinArgs: 0; MaxArgs: 0; Proc: nil; Opcode: 53; IsList: False),
    (Name: 'DATE'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 54; IsList: False),
    (Name: 'NOW'; MinArgs: 0; MaxArgs: 0; Proc: nil; Opcode: 55; IsList: False),
    (Name: 'PV'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 57; IsList: False),
    (Name: 'FV'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 58; IsList: False),
    (Name: 'IF'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 59; IsList: False),
    (Name: 'DAY'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 60; IsList: False),
    (Name: 'MONTH'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 61; IsList: False),
    (Name: 'YEAR'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 62; IsList: False),
    (Name: 'TIME'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 64; IsList: False),
    (Name: 'HOUR'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 65; IsList: False),
    (Name: 'MINUTE'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 66; IsList: False),
    (Name: 'SECOND'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 67; IsList: False),
    (Name: 'ISNUMBER'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 68; IsList: False),
    (Name: 'ISSTRING'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 69; IsList: False),
    (Name: 'LENGTH'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 70; IsList: False),
    (Name: 'VALUE'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 71; IsList: False),
    (Name: 'STRING'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 72; IsList: False),
    (Name: 'MID'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 73; IsList: False),
    (Name: 'CHAR'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 74; IsList: False),
    (Name: 'CODE'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 75; IsList: False),
    (Name: 'FIND'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 76; IsList: False),
    (Name: 'DATEVALUE'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 77; IsList: False),
    (Name: 'TIMEVALUE'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 78; IsList: False),
    (Name: 'CELLPOINTER'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 79; IsList: False),
    (Name: 'AVG'; MinArgs: 1; MaxArgs: 255; Proc: nil; Opcode: 81; IsList: True),
    (Name: 'COUNT'; MinArgs: 1; MaxArgs: 255; Proc: nil; Opcode: 82; IsList: True),
    (Name: 'MIN'; MinArgs: 1; MaxArgs: 255; Proc: nil; Opcode: 83; IsList: True),
    (Name: 'MAX'; MinArgs: 1; MaxArgs: 255; Proc: nil; Opcode: 84; IsList: True),
    (Name: 'VLOOKUP'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 85; IsList: False),
    (Name: 'NPV'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 86; IsList: False),
    (Name: 'VAR'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 87; IsList: False),
    (Name: 'STD'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 88; IsList: False),
    (Name: 'IRR'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 89; IsList: False),
    (Name: 'HLOOKUP'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 90; IsList: False),
    (Name: 'DSUM'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 91; IsList: False),
    (Name: 'DAVG'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 92; IsList: False),
    (Name: 'DCOUNT'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 93; IsList: False),
    (Name: 'DMIN'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 94; IsList: False),
    (Name: 'DMAX'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 95; IsList: False),
    (Name: 'DVAR'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 96; IsList: False),
    (Name: 'DSTD'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 97; IsList: False),
    (Name: 'INDEX'; MinArgs: 3; MaxArgs: 3; Proc: nil; Opcode: 98; IsList: False),
    (Name: 'COLS'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 99; IsList: False),
    (Name: 'ROWS'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 100; IsList: False),
    (Name: 'REPEAT'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 101; IsList: False),
    (Name: 'UPPER'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 102; IsList: False),
    (Name: 'LOWER'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 103; IsList: False),
    (Name: 'LEFT'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 104; IsList: False),
    (Name: 'RIGHT'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 105; IsList: False),
    (Name: 'REPLACE'; MinArgs: 4; MaxArgs: 4; Proc: nil; Opcode: 106; IsList: False),
    (Name: 'PROPER'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 107; IsList: False),
    (Name: 'CELL'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 108; IsList: False),
    (Name: 'TRIM'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 109; IsList: False),
    (Name: 'CLEAN'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 110; IsList: False),
    (Name: 'S'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 111; IsList: False),
    (Name: 'N'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 112; IsList: False),
    (Name: 'EXACT'; MinArgs: 2; MaxArgs: 2; Proc: nil; Opcode: 113; IsList: False),
    (Name: 'CALL'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 114; IsList: False),
    (Name: 'INDIRECT'; MinArgs: 1; MaxArgs: 1; Proc: nil; Opcode: 115; IsList: False)
  );

function FindFunc(const name: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Funcs) do
    if Funcs[i].Name = name then exit(i);
  Result := -1;
end;

function TFuncNode.Eval(src: TCellSource): TValue;
begin
  if not Assigned(Funcs[Def].Proc) then exit(ErrValue);     { not implemented yet }
  Result := Funcs[Def].Proc(Args, src);
end;

function TFuncNode.ToText: string;
var
  i: Integer;
begin
  Result := '@' + Funcs[Def].Name;
  if (Length(Args) = 0) and (Funcs[Def].MaxArgs = 0) then exit;
  Result := Result + '(';
  for i := 0 to High(Args) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Args[i].ToText;
  end;
  Result := Result + ')';
end;


function RefText(r, c: Integer; absR, absC: Boolean): string;
begin
  Result := '';
  if absC then Result := '$';
  Result := Result + ColText(c);
  if absR then Result := Result + '$';
  Result := Result + IntToStr(r);
end;

function TRefMapper.MapRange(var r1, c1, r2, c2: Integer; absR1, absC1, absR2, absC2: Boolean): Boolean;
var
  t: Integer;
begin
  Result := MapCell(r1, c1, absR1, absC1) and MapCell(r2, c2, absR2, absC2);
  if not Result then exit;
  if r1 > r2 then begin t := r1; r1 := r2; r2 := t; end;
  if c1 > c2 then begin t := c1; c1 := c2; c2 := t; end;
end;

function IsCellAddress(const s: string): Boolean;
var
  i, n, c, r: Integer;
begin
  Result := False;
  i := 1;
  c := 0;
  n := 0;
  while (i <= Length(s)) and (UpCase(s[i]) in ['A'..'Z']) do
  begin
    c := c * 26 + Ord(UpCase(s[i])) - 64;
    Inc(i);
    Inc(n);
  end;
  if (n < 1) or (n > 2) or (i > Length(s)) then exit;
  r := 0;
  while (i <= Length(s)) and (s[i] in ['0'..'9']) do
  begin
    r := r * 10 + Ord(s[i]) - 48;
    Inc(i);
    if r > 99999 then exit;
  end;
  Result := (i > Length(s)) and (c >= 1) and (c <= 256) and (r >= 1) and (r <= 8192);
end;

function IsValidName(const s: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (s = '') or (Length(s) > 15) then exit;
  if not (UpCase(s[1]) in ['A'..'Z', '_']) then exit;
  for i := 2 to Length(s) do
    if not (UpCase(s[i]) in ['A'..'Z', '0'..'9', '_']) then exit;
  Result := not IsCellAddress(s);
end;

{ the rectangle an argument stands for, if it is a range or a multi-cell name }
function RangeOf(node: TNode; src: TCellSource; out r1, c1, r2, c2: Integer): Boolean;
begin
  Result := False;
  if node is TRangeNode then
  begin
    r1 := TRangeNode(node).A.Row; c1 := TRangeNode(node).A.Col;
    r2 := TRangeNode(node).B.Row; c2 := TRangeNode(node).B.Col;
    Result := True;
  end
  else if node is TNameNode then
    Result := src.LookupName(TNameNode(node).Name, r1, c1, r2, c2);
end;

function TNameNode.Eval(src: TCellSource): TValue;
var
  r1, c1, r2, c2: Integer;
begin
  if not src.LookupName(Name, r1, c1, r2, c2) then exit(ErrValue);
  if (r1 = r2) and (c1 = c2) then
    Result := src.CellValue(r1, c1)
  else
    Result := ErrValue;
end;

function TNameNode.ToText: string;
begin
  Result := Name;
end;

function TNameNode.Mapped(m: TRefMapper): string;
begin
  Result := Name;
end;

function TNumNode.Mapped(m: TRefMapper): string;
begin
  Result := ToText;
end;

function TStrNode.Mapped(m: TRefMapper): string;
begin
  Result := ToText;
end;

function TRefNode.Mapped(m: TRefMapper): string;
var
  r, c: Integer;
begin
  r := Row;
  c := Col;
  if not m.MapCell(r, c, AbsRow, AbsCol) then exit('@ERR');
  Result := RefText(r, c, AbsRow, AbsCol);
end;

function TRangeNode.Mapped(m: TRefMapper): string;
var
  r1, c1, r2, c2: Integer;
begin
  r1 := A.Row; c1 := A.Col; r2 := B.Row; c2 := B.Col;
  if not m.MapRange(r1, c1, r2, c2, A.AbsRow, A.AbsCol, B.AbsRow, B.AbsCol) then exit('@ERR');
  Result := RefText(r1, c1, A.AbsRow, A.AbsCol) + '..' + RefText(r2, c2, B.AbsRow, B.AbsCol);
end;

function TParenNode.Mapped(m: TRefMapper): string;
begin
  Result := '(' + Inner.Mapped(m) + ')';
end;

function TUnaryNode.Mapped(m: TRefMapper): string;
begin
  Result := Op + Operand.Mapped(m);
end;

function TBinaryNode.Mapped(m: TRefMapper): string;
begin
  Result := Left.Mapped(m) + Op + Right.Mapped(m);
end;

function TFuncNode.Mapped(m: TRefMapper): string;
var
  i: Integer;
begin
  Result := '@' + Funcs[Def].Name;
  if (Length(Args) = 0) and (Funcs[Def].MaxArgs = 0) then exit;
  Result := Result + '(';
  for i := 0 to High(Args) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Args[i].Mapped(m);
  end;
  Result := Result + ')';
end;


{ ------------------------------------------------------------------ emit }

function BinaryOpcode(const op: string): Integer;
begin
  if op = '+' then Result := 9
  else if op = '-' then Result := 10
  else if op = '*' then Result := 11
  else if op = '/' then Result := 12
  else if op = '^' then Result := 13
  else if op = '=' then Result := 14
  else if op = '<>' then Result := 15
  else if op = '<=' then Result := 16
  else if op = '>=' then Result := 17
  else if op = '<' then Result := 18
  else if op = '>' then Result := 19
  else if op = '#AND#' then Result := 20
  else if op = '#OR#' then Result := 21
  else if op = '&' then Result := 24
  else Result := 0;
end;

procedure TNumNode.Emit(w: TRpnWriter);
begin
  w.PutNumber(Value);
end;

procedure TStrNode.Emit(w: TRpnWriter);
begin
  w.PutString(Value);
end;

procedure TRefNode.Emit(w: TRpnWriter);
begin
  w.PutRef(Row, Col, AbsRow, AbsCol);
end;

procedure TRangeNode.Emit(w: TRpnWriter);
begin
  w.PutRange(A.Row, A.Col, B.Row, B.Col, A.AbsRow, A.AbsCol, B.AbsRow, B.AbsCol);
end;

procedure TNameNode.Emit(w: TRpnWriter);
var
  r1, c1, r2, c2: Integer;
begin
  if not w.ResolveName(Name, r1, c1, r2, c2) then
    w.PutFunc(32, 0, False)                 { undefined name: @ERR }
  else if (r1 = r2) and (c1 = c2) then
    w.PutRef(r1, c1, True, True)
  else
    w.PutRange(r1, c1, r2, c2, True, True, True, True);
end;

procedure TParenNode.Emit(w: TRpnWriter);
begin
  Inner.Emit(w);
  w.PutParen;
end;

procedure TUnaryNode.Emit(w: TRpnWriter);
begin
  Operand.Emit(w);
  if Elide then exit;
  if Op = '-' then w.PutOp(8)
  else if Op = '+' then w.PutOp(23)
  else w.PutOp(22);
end;

procedure TBinaryNode.Emit(w: TRpnWriter);
begin
  Left.Emit(w);
  Right.Emit(w);
  w.PutOp(BinaryOpcode(Op));
end;

procedure TFuncNode.Emit(w: TRpnWriter);
var
  i: Integer;
begin
  for i := 0 to High(Args) do Args[i].Emit(w);
  w.PutFunc(Funcs[Def].Opcode, Length(Args), Funcs[Def].IsList);
end;

procedure TFormula.Emit(w: TRpnWriter);
var
  lead: TNode;
begin
  { a formula typed +A1*2 is stored without the leading +, which only marks
    "this is a formula" }
  lead := FRoot;
  while lead is TBinaryNode do lead := TBinaryNode(lead).Left;
  if (lead is TUnaryNode) and (TUnaryNode(lead).Op = '+') then TUnaryNode(lead).Elide := True;
  try
    FRoot.Emit(w);
  finally
    if (lead is TUnaryNode) then TUnaryNode(lead).Elide := False;
  end;
end;

function FuncCount: Integer;
begin
  Result := Length(Funcs);
end;

function FuncIndexByOpcode(opcode: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Funcs) do
    if Funcs[i].Opcode = opcode then exit(i);
  Result := -1;
end;

function FuncName(i: Integer): string;
begin
  Result := Funcs[i].Name;
end;

function FuncOpcode(i: Integer): Integer;
begin
  Result := Funcs[i].Opcode;
end;

function FuncMinArgs(i: Integer): Integer;
begin
  Result := Funcs[i].MinArgs;
end;

function FuncMaxArgs(i: Integer): Integer;
begin
  Result := Funcs[i].MaxArgs;
end;

function FuncIsList(i: Integer): Boolean;
begin
  Result := Funcs[i].IsList;
end;

function FuncImplemented(i: Integer): Boolean;
begin
  Result := Assigned(Funcs[i].Proc);
end;

{ ------------------------------------------------------------------ parser }

type
  TParser = class
  private
    S: string;
    P: Integer;
    Pool: TList;
    procedure Fail(pos: Integer);
    function New(n: TNode): TNode;
    procedure SkipWs;
    function Peek: Char;
    function LookingAt(const w: string): Boolean;      { case-insensitive, at P }
    function TryRef(out ref: TRefNode): Boolean;
    function ParseNumber: TNode;
    function ParseString: TNode;
    function ParseFunc: TNode;
    function ParseName: TNode;
    function ParseOperand: TNode;
    function ParseOr: TNode;
    function ParseNot: TNode;
    function ParseCmp: TNode;
    function ParseAdd: TNode;
    function ParseMul: TNode;
    function ParseUnary: TNode;
    function ParsePow: TNode;
    function ParsePowOperand: TNode;
    function Binary(const op: string; l, r: TNode): TNode;
  public
    constructor Create(const text: string; aPool: TList);
    function Parse: TNode;
  end;

constructor TParser.Create(const text: string; aPool: TList);
begin
  inherited Create;
  S := text;
  P := 1;
  Pool := aPool;
end;

procedure TParser.Fail(pos: Integer);
var
  e: EFormula;
begin
  e := EFormula.Create('invalid formula');
  e.Pos := pos;
  raise e;
end;

function TParser.New(n: TNode): TNode;
begin
  Pool.Add(n);
  Result := n;
end;

procedure TParser.SkipWs;
begin
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
end;

function TParser.Peek: Char;
begin
  SkipWs;
  if P <= Length(S) then Result := S[P] else Result := #0;
end;

function TParser.LookingAt(const w: string): Boolean;
begin
  SkipWs;
  Result := UpperCase(Copy(S, P, Length(w))) = w;
end;

function TParser.Binary(const op: string; l, r: TNode): TNode;
var
  b: TBinaryNode;
begin
  b := TBinaryNode.Create;
  New(b);
  b.Op := op;
  b.Left := l;
  b.Right := r;
  Result := b;
end;

{ [$]LL[$]ddd with no letters or digits following }
function TParser.TryRef(out ref: TRefNode): Boolean;
var
  q, c, r: Integer;
  ac, ar: Boolean;
  n: Integer;
begin
  Result := False;
  ref := nil;
  q := P;
  ac := (q <= Length(S)) and (S[q] = '$');
  if ac then Inc(q);
  c := 0;
  n := 0;
  while (q <= Length(S)) and (UpCase(S[q]) in ['A'..'Z']) do
  begin
    c := c * 26 + Ord(UpCase(S[q])) - 64;
    Inc(q);
    Inc(n);
  end;
  if (n < 1) or (n > 2) then exit;
  ar := (q <= Length(S)) and (S[q] = '$');
  if ar then Inc(q);
  r := 0;
  n := 0;
  while (q <= Length(S)) and (S[q] in ['0'..'9']) do
  begin
    r := r * 10 + Ord(S[q]) - 48;
    Inc(q);
    Inc(n);
    if n > 5 then exit;
  end;
  if (n < 1) or (c < 1) or (c > 256) or (r < 1) or (r > 8192) then exit;
  if (q <= Length(S)) and (UpCase(S[q]) in ['A'..'Z', '0'..'9', '_']) then exit;
  ref := TRefNode.Create;
  New(ref);
  ref.Row := r;
  ref.Col := c;
  ref.AbsRow := ar;
  ref.AbsCol := ac;
  P := q;
  Result := True;
end;

function TParser.ParseNumber: TNode;
var
  q: Integer;
  d: Double;
  n: TNumNode;
  code: Integer;
begin
  q := P;
  while (q <= Length(S)) and (S[q] in ['0'..'9']) do Inc(q);
  if (q <= Length(S)) and (S[q] = '.') and not ((q < Length(S)) and (S[q + 1] = '.')) then
  begin
    Inc(q);
    while (q <= Length(S)) and (S[q] in ['0'..'9']) do Inc(q);
  end;
  if (q <= Length(S)) and (UpCase(S[q]) = 'E') then
  begin
    Inc(q);
    if (q <= Length(S)) and (S[q] in ['+', '-']) then Inc(q);
    if not ((q <= Length(S)) and (S[q] in ['0'..'9'])) then Fail(q);
    while (q <= Length(S)) and (S[q] in ['0'..'9']) do Inc(q);
  end;
  Val(Copy(S, P, q - P), d, code);
  if code <> 0 then Fail(P);
  n := TNumNode.Create;
  New(n);
  n.Value := d;
  P := q;
  Result := n;
end;

function TParser.ParseString: TNode;
var
  q: Integer;
  n: TStrNode;
begin
  q := P + 1;
  while (q <= Length(S)) and (S[q] <> '"') do Inc(q);
  if q > Length(S) then Fail(P);
  n := TStrNode.Create;
  New(n);
  n.Value := Copy(S, P + 1, q - P - 1);
  P := q + 1;
  Result := n;
end;

function TParser.ParseFunc: TNode;
var
  q, idx, start: Integer;
  name: string;
  f: TFuncNode;
  arg: TNode;
begin
  start := P;
  Inc(P);                                  { the @ }
  q := P;
  while (q <= Length(S)) and (UpCase(S[q]) in ['A'..'Z', '0'..'9']) do Inc(q);
  name := UpperCase(Copy(S, P, q - P));
  idx := FindFunc(name);
  if idx < 0 then Fail(start);
  P := q;
  f := TFuncNode.Create;
  New(f);
  f.Def := idx;
  if Peek = '(' then
  begin
    Inc(P);
    if Peek = ')' then
      Inc(P)
    else
      repeat
        arg := ParseOr;
        SetLength(f.Args, Length(f.Args) + 1);
        f.Args[High(f.Args)] := arg;
        if (Peek = ',') or (Peek = ';') then
          Inc(P)
        else if Peek = ')' then
        begin
          Inc(P);
          break;
        end
        else
          Fail(P);
      until False;
  end;
  if (Length(f.Args) < Funcs[idx].MinArgs) or (Length(f.Args) > Funcs[idx].MaxArgs) then
    Fail(start);
  Result := f;
end;

function TParser.ParseName: TNode;
var
  q: Integer;
  n: TNameNode;
begin
  q := P;
  while (q <= Length(S)) and (UpCase(S[q]) in ['A'..'Z', '0'..'9', '_']) do Inc(q);
  if not IsValidName(Copy(S, P, q - P)) then Fail(P);
  n := TNameNode.Create;
  New(n);
  n.Name := UpperCase(Copy(S, P, q - P));
  P := q;
  Result := n;
end;

function TParser.ParseOperand: TNode;
var
  ref, ref2: TRefNode;
  rg: TRangeNode;
  paren: TParenNode;
  q, t: Integer;
  r, c: Integer;
begin
  SkipWs;
  if P > Length(S) then Fail(P);
  case S[P] of
    '0'..'9': Result := ParseNumber;
    '.':
      if (P < Length(S)) and (S[P + 1] in ['0'..'9']) then Result := ParseNumber
      else Fail(P);
    '"': Result := ParseString;
    '@': Result := ParseFunc;
    '(':
      begin
        Inc(P);
        paren := TParenNode.Create;
        New(paren);
        paren.Inner := ParseOr;
        if Peek <> ')' then Fail(P);
        Inc(P);
        Result := paren;
      end;
    '_':
      Result := ParseName;
    '$', 'A'..'Z', 'a'..'z':
      begin
        if not TryRef(ref) then
        begin
          if S[P] = '$' then Fail(P);
          Result := ParseName;
          exit;
        end;
        { range: ref..ref or ref.ref }
        q := P;
        if (q <= Length(S)) and (S[q] = '.') then
        begin
          Inc(q);
          if (q <= Length(S)) and (S[q] = '.') then Inc(q);
          t := P;
          P := q;
          if TryRef(ref2) then
          begin
            rg := TRangeNode.Create;
            New(rg);
            { normalise corners }
            r := ref.Row; c := ref.Col;
            if ref2.Row < r then begin ref.Row := ref2.Row; ref2.Row := r; end;
            if ref2.Col < c then begin ref.Col := ref2.Col; ref2.Col := c; end;
            rg.A := ref;
            rg.B := ref2;
            Result := rg;
            exit;
          end;
          P := t;
        end;
        Result := ref;
      end;
  else
    Fail(P);
  end;
end;

function TParser.ParsePowOperand: TNode;
var
  u: TUnaryNode;
begin
  if (Peek = '+') or (Peek = '-') then
  begin
    u := TUnaryNode.Create;
    New(u);
    u.Op := S[P];
    Inc(P);
    u.Operand := ParsePowOperand();
    Result := u;
  end
  else
    Result := ParseOperand;
end;

function TParser.ParsePow: TNode;
begin
  Result := ParseOperand;
  while Peek = '^' do
  begin
    Inc(P);
    Result := Binary('^', Result, ParsePowOperand);
  end;
end;

function TParser.ParseUnary: TNode;
var
  u: TUnaryNode;
begin
  if (Peek = '+') or (Peek = '-') then
  begin
    u := TUnaryNode.Create;
    New(u);
    u.Op := S[P];
    Inc(P);
    u.Operand := ParseUnary();
    Result := u;
  end
  else
    Result := ParsePow;
end;

function TParser.ParseMul: TNode;
var
  op: Char;
begin
  Result := ParseUnary;
  while (Peek = '*') or (Peek = '/') do
  begin
    op := S[P];
    Inc(P);
    Result := Binary(op, Result, ParseUnary);
  end;
end;

function TParser.ParseAdd: TNode;
var
  op: Char;
begin
  Result := ParseMul;
  while (Peek = '+') or (Peek = '-') or (Peek = '&') do
  begin
    op := S[P];
    Inc(P);
    Result := Binary(op, Result, ParseMul);
  end;
end;

function TParser.ParseCmp: TNode;
var
  op: string;
begin
  Result := ParseAdd;
  repeat
    SkipWs;
    op := '';
    if LookingAt('<=') or LookingAt('>=') or LookingAt('<>') then op := Copy(S, P, 2)
    else if (Peek = '<') or (Peek = '>') or (Peek = '=') then op := S[P];
    if op = '' then break;
    Inc(P, Length(op));
    Result := Binary(op, Result, ParseAdd);
  until False;
end;

function TParser.ParseNot: TNode;
var
  u: TUnaryNode;
begin
  if LookingAt('#NOT#') then
  begin
    Inc(P, 5);
    u := TUnaryNode.Create;
    New(u);
    u.Op := '#NOT#';
    u.Operand := ParseNot();
    Result := u;
  end
  else
    Result := ParseCmp;
end;

function TParser.ParseOr: TNode;
begin
  Result := ParseNot;
  repeat
    if LookingAt('#AND#') then
    begin
      Inc(P, 5);
      Result := Binary('#AND#', Result, ParseNot);
    end
    else if LookingAt('#OR#') then
    begin
      Inc(P, 4);
      Result := Binary('#OR#', Result, ParseNot);
    end
    else
      break;
  until False;
end;

function TParser.Parse: TNode;
begin
  Result := ParseOr;
  SkipWs;
  if P <= Length(S) then Fail(P);
end;

{ ------------------------------------------------------------------ TFormula }

constructor TFormula.Create;
begin
  inherited Create;
  FPool := TList.Create;
end;

destructor TFormula.Destroy;
var
  i: Integer;
begin
  for i := 0 to FPool.Count - 1 do TObject(FPool[i]).Free;
  FPool.Free;
  inherited Destroy;
end;

function TFormula.Eval(src: TCellSource): TValue;
begin
  Result := FRoot.Eval(src);
end;

function TFormula.MappedText(m: TRefMapper): string;
begin
  Result := FRoot.Mapped(m);
end;

function CompileFormula(const text: string; out f: TFormula; out errPos: Integer): Boolean;
var
  parser: TParser;
begin
  f := TFormula.Create;
  errPos := 0;
  parser := TParser.Create(text, f.FPool);
  try
    try
      if (text = '') or not (text[1] in ['0'..'9', '+', '-', '.', '@', '(', '#', '$']) then
        parser.Fail(1);
      f.FRoot := parser.Parse;
      f.FText := f.FRoot.ToText;
      Result := True;
    except
      on e: EFormula do
      begin
        errPos := e.Pos;
        FreeAndNil(f);
        Result := False;
      end;
    end;
  finally
    parser.Free;
  end;
end;

initialization
  { divide-by-zero, overflow etc. must give ERR, not raise }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
end.
