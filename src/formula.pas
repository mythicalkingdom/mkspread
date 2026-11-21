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
    { calls acc.Add for every non-empty cell in the rectangle }
    procedure Accumulate(r1, c1, r2, c2: Integer; acc: TAccumulator); virtual; abstract;
  end;

  TNode = class
  public
    function Eval(src: TCellSource): TValue; virtual; abstract;
    function ToText: string; virtual; abstract;
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
    property Text: string read FText;    { canonical text, e.g. +A1+B2 }
    property Root: TNode read FRoot;
  end;

function NumValue(d: Double): TValue;
function StrValue(const s: string): TValue;
function ErrValue: TValue;
function NAValue: TValue;
function EmptyValue: TValue;

{ True for text that is just a number: 12, -3.5, .5, 1E3 }
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
  end;

  TStrNode = class(TNode)
  public
    Value: string;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TRefNode = class(TNode)
  public
    Row, Col: Integer;
    AbsRow, AbsCol: Boolean;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TRangeNode = class(TNode)
  public
    A, B: TRefNode;            { normalised: A is top-left, B bottom-right }
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TParenNode = class(TNode)
  public
    Inner: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TUnaryNode = class(TNode)
  public
    Op: string;                { '+', '-', '#NOT#' }
    Operand: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TBinaryNode = class(TNode)
  public
    Op: string;
    Left, Right: TNode;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
  end;

  TFuncProc = function(const args: TNodeArray; src: TCellSource): TValue;

  TFuncDef = record
    Name: string;
    MinArgs, MaxArgs: Integer;
    Proc: TFuncProc;
  end;

  TFuncNode = class(TNode)
  public
    Def: Integer;              { index into the function table }
    Args: TNodeArray;
    function Eval(src: TCellSource): TValue; override;
    function ToText: string; override;
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
  code: Integer;
begin
  d := 0;
  Result := False;
  if (s = '') or not (s[1] in ['0'..'9', '.', '+', '-']) then exit;
  Val(s, d, code);
  Result := code = 0;
end;

function NumToRaw(d: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(d, ffGeneral, 15, 0, fs);
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

function ColText(c: Integer): string;
begin
  if c <= 26 then Result := Chr(64 + c)
  else Result := Chr(64 + (c - 1) div 26) + Chr(65 + (c - 1) mod 26);
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

function FnSum(const args: TNodeArray; src: TCellSource): TValue;
var
  acc: TSumAcc;
  i: Integer;
  v: TValue;
  d: Double;
  rg: TRangeNode;
begin
  acc := TSumAcc.Create;
  try
    for i := 0 to High(args) do
      if args[i] is TRangeNode then
      begin
        rg := TRangeNode(args[i]);
        src.Accumulate(rg.A.Row, rg.A.Col, rg.B.Row, rg.B.Col, acc);
      end
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

const
  { The full @function library arrives in a later phase; this is the registry
    it will extend. }
  Funcs: array[0..5] of TFuncDef = (
    (Name: 'SUM';   MinArgs: 1; MaxArgs: 255; Proc: @FnSum),
    (Name: 'NA';    MinArgs: 0; MaxArgs: 0;   Proc: @FnNA),
    (Name: 'ERR';   MinArgs: 0; MaxArgs: 0;   Proc: @FnErr),
    (Name: 'TRUE';  MinArgs: 0; MaxArgs: 0;   Proc: @FnTrue),
    (Name: 'FALSE'; MinArgs: 0; MaxArgs: 0;   Proc: @FnFalse),
    (Name: 'PI';    MinArgs: 0; MaxArgs: 0;   Proc: @FnPi)
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
    '$', 'A'..'Z', 'a'..'z':
      begin
        if not TryRef(ref) then Fail(P);
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
