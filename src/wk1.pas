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

{ Reading and writing worksheet files (.WK1, and .WKS for the original format).

  A file is a sequence of records: a 16-bit type, a 16-bit length, then the
  body, all little-endian.  Coordinates are zero based.  The layouts used here
  come from the published worksheet file format documentation and from
  inspection of sample files; see docs/SOURCES.md.  Records this program does
  not model (print setup, graphs, query ranges...) are skipped when reading and
  not written. }
unit wk1;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, sheet, formula;

type
  TFileInfo = record
    Version: Integer;              { $0404 original, $0406 release 2 }
    CursorCol, CursorRow: Integer; { 1-based; where the file left the pointer }
    LeftCol, TopRow: Integer;      { screen position (writing) }
    Formulas: Integer;             { formulas read }
    FormulasLost: Integer;         { formulas kept only as their last value }
  end;

{ Replace the contents of sh with the file's.  Returns '' or an error message;
  problems that do not stop the load are added to warnings. }
function LoadWorksheet(const fn: string; sh: TSheet; warnings: TStrings; out info: TFileInfo): string;

{ Write sh.  The format follows wks: True = original .WKS records, False = .WK1. }
function SaveWorksheet(const fn: string; sh: TSheet; wks: Boolean; const info: TFileInfo;
                       warnings: TStrings): string;

{ exposed for tests }
function DecodeFormula(const code: TBytes; originR, originC: Integer; out text: string): Boolean;
function EncodeFormula(f: TFormula; sh: TSheet; originR, originC: Integer): TBytes;
function FormatToByte(const f: TCellFormat): Byte;
function ByteToFormat(b: Byte): TCellFormat;

implementation

uses charsets, cellfmt, Math, funclib;

{ ------------------------------------------------------------------ bytes }

function W16(const b: TBytes; p: Integer): Integer;
begin
  Result := b[p] or (b[p + 1] shl 8);
end;

function S16(const b: TBytes; p: Integer): Integer;
begin
  Result := W16(b, p);
  if Result >= $8000 then Dec(Result, $10000);
end;

function F64(const b: TBytes; p: Integer): Double;
var
  i: Integer;
  q: Int64;
begin
  q := 0;
  for i := 7 downto 0 do q := (q shl 8) or b[p + i];
  Result := Double(Pointer(@q)^);
end;

procedure PutW(var b: TBytes; v: Integer);
var
  n: Integer;
begin
  n := Length(b);
  SetLength(b, n + 2);
  b[n] := v and $FF;
  b[n + 1] := (v shr 8) and $FF;
end;

procedure PutB(var b: TBytes; v: Integer);
begin
  SetLength(b, Length(b) + 1);
  b[High(b)] := v and $FF;
end;

procedure PutF(var b: TBytes; d: Double);
var
  q: Int64;
  i: Integer;
begin
  q := Int64(Pointer(@d)^);
  for i := 0 to 7 do
  begin
    PutB(b, q and $FF);
    q := q shr 8;
  end;
end;

procedure PutStr0(var b: TBytes; const s: string);
var
  i: Integer;
begin
  for i := 1 to Length(s) do PutB(b, Ord(s[i]));
  PutB(b, 0);
end;

{ ------------------------------------------------------------------ cell formats }

{ special format codes: 0 +/-, 1 general, 2 D1, 3 D2, 4 D3, 5 text, 6 hidden,
  7 D6, 8 D7, 9 D4, 10 D5, 11 D8, 12 D9, 15 default }
function ByteToFormat(b: Byte): TCellFormat;
var
  typ, low: Integer;
begin
  typ := (b shr 4) and 7;
  low := b and 15;
  Result := MakeFormat(fkGeneral, 0);
  case typ of
    0: Result := MakeFormat(fkFixed, low);
    1: Result := MakeFormat(fkSci, low);
    2: Result := MakeFormat(fkCurrency, low);
    3: Result := MakeFormat(fkPercent, low);
    4: Result := MakeFormat(fkComma, low);
    7:
      case low of
        0: Result := MakeFormat(fkPlusMinus, 0);
        1: Result := MakeFormat(fkGeneral, 0);
        2: Result := MakeFormat(fkDate, 1);
        3: Result := MakeFormat(fkDate, 2);
        4: Result := MakeFormat(fkDate, 3);
        5: Result := MakeFormat(fkText, 0);
        6: Result := MakeFormat(fkHidden, 0);
        7: Result := MakeFormat(fkDate, 6);
        8: Result := MakeFormat(fkDate, 7);
        9: Result := MakeFormat(fkDate, 4);
        10: Result := MakeFormat(fkDate, 5);
        11: Result := MakeFormat(fkDate, 8);
        12: Result := MakeFormat(fkDate, 9);
      else
        Result.UseGlobal := True;                  { 15 and anything unknown }
        exit;
      end;
  else
    Result.UseGlobal := True;
    exit;
  end;
end;

{ The protection bit is always written set: cells are protected by default,
  and this program does not track protection yet. }
function FormatToByte(const f: TCellFormat): Byte;
var
  sp: Integer;
begin
  if f.UseGlobal then exit($FF);
  case f.Kind of
    fkFixed:    Result := $00 or f.Dec;
    fkSci:      Result := $10 or f.Dec;
    fkCurrency: Result := $20 or f.Dec;
    fkPercent:  Result := $30 or f.Dec;
    fkComma:    Result := $40 or f.Dec;
  else
    begin
      case f.Kind of
        fkPlusMinus: sp := 0;
        fkGeneral: sp := 1;
        fkText: sp := 5;
        fkHidden: sp := 6;
        fkDate:
          case f.Dec of
            1: sp := 2; 2: sp := 3; 3: sp := 4; 4: sp := 9; 5: sp := 10;
            6: sp := 7; 7: sp := 8; 8: sp := 11; 9: sp := 12;
          else sp := 15;
          end;
      else
        sp := 15;
      end;
      Result := $70 or sp;
    end;
  end;
  Result := Result or $80;
end;

{ ------------------------------------------------------------------ formulas: decode }

function ColLetterText(c: Integer): string;
begin
  if c < 26 then Result := Chr(65 + c)
  else Result := Chr(64 + c div 26) + Chr(65 + c mod 26);
end;

{ turns a stored column word and row word into reference text for the cell at
  (originR, originC), both 1-based }
function RefFromWords(cw, rw, originR, originC: Integer): string;
var
  c, r, off: Integer;
  ac, ar: Boolean;
begin
  ac := (cw and $8000) = 0;
  ar := (rw and $8000) = 0;
  if ac then c := cw and $FF
  else
  begin
    off := cw and $FF;
    if off >= $80 then Dec(off, $100);
    c := (originC - 1 + off) and $FF;
  end;
  if ar then r := rw and $1FFF
  else
  begin
    off := rw and $1FFF;
    if off >= $1000 then Dec(off, $2000);
    r := (originR - 1 + off) and $1FFF;
  end;
  Result := '';
  if ac then Result := '$';
  Result := Result + ColLetterText(c);
  if ar then Result := Result + '$';
  Result := Result + IntToStr(r + 1);
end;

function OperatorText(op: Integer): string;
begin
  case op of
    9: Result := '+';
    10: Result := '-';
    11: Result := '*';
    12: Result := '/';
    13: Result := '^';
    14: Result := '=';
    15: Result := '<>';
    16: Result := '<=';
    17: Result := '>=';
    18: Result := '<';
    19: Result := '>';
    20: Result := '#AND#';
    21: Result := '#OR#';
    24: Result := '&';
  else
    Result := '';
  end;
end;

function DecodeFormula(const code: TBytes; originR, originC: Integer; out text: string): Boolean;
var
  stack: TStringList;
  i, t, n, fi, k, j: Integer;
  a, b, s: string;
begin
  Result := False;
  text := '';
  stack := TStringList.Create;
  try
    i := 0;
    while i < Length(code) do
    begin
      t := code[i];
      case t of
        0:
          begin
            if i + 9 > Length(code) then exit;
            a := NumToRaw(F64(code, i + 1));
            stack.Add(a);
            Inc(i, 9);
          end;
        1:
          begin
            if i + 5 > Length(code) then exit;
            stack.Add(RefFromWords(W16(code, i + 1), W16(code, i + 3), originR, originC));
            Inc(i, 5);
          end;
        2:
          begin
            if i + 9 > Length(code) then exit;
            a := RefFromWords(W16(code, i + 1), W16(code, i + 3), originR, originC);
            b := RefFromWords(W16(code, i + 5), W16(code, i + 7), originR, originC);
            if a = b then stack.Add(a) else stack.Add(a + '..' + b);   { a range of one cell is a cell }
            Inc(i, 9);
          end;
        3:
          begin
            if stack.Count <> 1 then exit;
            text := stack[0];
            { the leading + that marks a formula is not stored }
            if (text <> '') and not (text[1] in ['0'..'9', '.', '(', '@', '-', '#']) then text := '+' + text;
            exit(True);
          end;
        4:
          begin
            if stack.Count < 1 then exit;
            stack[stack.Count - 1] := '(' + stack[stack.Count - 1] + ')';
            Inc(i);
          end;
        5:
          begin
            if i + 3 > Length(code) then exit;
            stack.Add(IntToStr(S16(code, i + 1)));
            Inc(i, 3);
          end;
        6:
          begin
            j := i + 1;
            while (j < Length(code)) and (code[j] <> 0) do Inc(j);
            if j >= Length(code) then exit;
            SetString(s, PChar(@code[i + 1]), j - i - 1);
            stack.Add('"' + LicsToUtf8(s) + '"');
            i := j + 1;
          end;
        8, 22, 23:
          begin
            if stack.Count < 1 then exit;
            if t = 8 then a := '-' else if t = 23 then a := '+' else a := '#NOT#';
            stack[stack.Count - 1] := a + stack[stack.Count - 1];
            Inc(i);
          end;
        9..21, 24:
          begin
            if stack.Count < 2 then exit;
            b := stack[stack.Count - 1];
            stack.Delete(stack.Count - 1);
            stack[stack.Count - 1] := stack[stack.Count - 1] + OperatorText(t) + b;
            Inc(i);
          end;
      else
        begin
          fi := FuncIndexByOpcode(t);
          if fi < 0 then exit;
          if FuncIsList(fi) then
          begin
            if i + 1 >= Length(code) then exit;
            n := code[i + 1];
            Inc(i, 2);
          end
          else
          begin
            if FuncMinArgs(fi) <> FuncMaxArgs(fi) then exit;
            n := FuncMinArgs(fi);
            Inc(i);
          end;
          if (n < FuncMinArgs(fi)) or (n > FuncMaxArgs(fi)) or (stack.Count < n) then exit;
          a := '';
          for k := 0 to n - 1 do
          begin
            if k > 0 then a := a + ',';
            a := a + stack[stack.Count - n + k];
          end;
          for k := 1 to n do stack.Delete(stack.Count - 1);
          if n = 0 then stack.Add('@' + FuncName(fi))
          else stack.Add('@' + FuncName(fi) + '(' + a + ')');
        end;
      end;
    end;
  finally
    stack.Free;
  end;
end;

{ ------------------------------------------------------------------ formulas: encode }

type
  TEmitter = class(TRpnWriter)
  public
    Buf: TBytes;
    OriginR, OriginC: Integer;
    Sh: TSheet;
    Failed: Boolean;
    function ResolveName(const name: string; out r1, c1, r2, c2: Integer): Boolean; override;
    procedure PutNumber(d: Double); override;
    procedure PutString(const s: string); override;
    procedure PutRef(r, c: Integer; absR, absC: Boolean); override;
    procedure PutRange(r1, c1, r2, c2: Integer; aR1, aC1, aR2, aC2: Boolean); override;
    procedure PutOp(opcode: Integer); override;
    procedure PutFunc(opcode, argc: Integer; isList: Boolean); override;
    procedure PutParen; override;
    procedure Words(r, c: Integer; absR, absC: Boolean);
  end;

function TEmitter.ResolveName(const name: string; out r1, c1, r2, c2: Integer): Boolean;
var
  g: TRange;
begin
  Result := (Sh <> nil) and Sh.FindName(name, g);
  if Result then
  begin
    r1 := g.R1; c1 := g.C1; r2 := g.R2; c2 := g.C2;
  end;
end;

procedure TEmitter.PutNumber(d: Double);
begin
  if (d = Int(d)) and (Abs(d) <= 32767) and not ((d = 0) and (1 / d < 0)) then
  begin
    PutB(Buf, 5);
    PutW(Buf, Trunc(d) and $FFFF);
  end
  else
  begin
    PutB(Buf, 0);
    PutF(Buf, d);
  end;
end;

procedure TEmitter.PutString(const s: string);
begin
  PutB(Buf, 6);
  PutStr0(Buf, Utf8ToLics(s));
end;

procedure TEmitter.Words(r, c: Integer; absR, absC: Boolean);
begin
  if absC then PutW(Buf, (c - 1) and $FF)
  else PutW(Buf, $8000 or ((c - OriginC) and $FF));
  if absR then PutW(Buf, (r - 1) and $1FFF)
  else PutW(Buf, $8000 or ((r - OriginR) and $1FFF));
end;

procedure TEmitter.PutRef(r, c: Integer; absR, absC: Boolean);
begin
  PutB(Buf, 1);
  Words(r, c, absR, absC);
end;

procedure TEmitter.PutRange(r1, c1, r2, c2: Integer; aR1, aC1, aR2, aC2: Boolean);
begin
  PutB(Buf, 2);
  Words(r1, c1, aR1, aC1);
  Words(r2, c2, aR2, aC2);
end;

procedure TEmitter.PutOp(opcode: Integer);
begin
  PutB(Buf, opcode);
end;

procedure TEmitter.PutFunc(opcode, argc: Integer; isList: Boolean);
begin
  if opcode < 0 then
  begin
    Failed := True;                       { no file code is known for this function }
    exit;
  end;
  PutB(Buf, opcode);
  if isList then PutB(Buf, argc);
end;

procedure TEmitter.PutParen;
begin
  PutB(Buf, 4);
end;

function EncodeFormula(f: TFormula; sh: TSheet; originR, originC: Integer): TBytes;
var
  e: TEmitter;
begin
  e := TEmitter.Create;
  try
    e.Sh := sh;
    e.OriginR := originR;
    e.OriginC := originC;
    f.Emit(e);
    PutB(e.Buf, 3);
    if e.Failed then Result := nil else Result := e.Buf;
  finally
    e.Free;
  end;
end;

{ ------------------------------------------------------------------ loading }

function CellNaN(const b: TBytes; p: Integer; out isNA, isErr, isStr: Boolean): Boolean;
var
  hi: Integer;
  fracZero: Boolean;
  k: Integer;
begin
  hi := W16(b, p + 6);
  Result := (hi and $7FF0) = $7FF0;
  isNA := False; isErr := False; isStr := False;
  if not Result then exit;
  fracZero := ((hi and $F) = 0);
  for k := 0 to 5 do
    if b[p + k] <> 0 then fracZero := False;
  if fracZero then
  begin
    if (hi and $8000) <> 0 then isNA := True else isErr := True;
  end
  else
    isStr := True;
end;

function LoadWorksheet(const fn: string; sh: TSheet; warnings: TStrings; out info: TFileInfo): string;
var
  fs: TFileStream;
  buf, body: TBytes;
  p, op, ln, r, c, i, v, n: Integer;
  fmt: Byte;
  cell: TCell;
  txt, nm: string;
  d: Double;
  isNA, isErr, isStr: Boolean;
  codeLen: Integer;
  code: TBytes;
  lastFormula: TCell;
  g: TRange;
  sawBof: Boolean;

  function Where(rr, cc: Integer): string;
  begin
    Result := ColLetter(cc + 1) + IntToStr(rr + 1);
  end;

  procedure Warn(const s: string);
  begin
    if warnings <> nil then warnings.Add(s);
  end;

begin
  Result := '';
  FillChar(info, SizeOf(info), 0);
  info.CursorCol := 1;
  info.CursorRow := 1;
  try
    fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do exit('Cannot open ' + ExtractFileName(fn));
  end;
  try
    SetLength(buf, fs.Size);
    if Length(buf) > 0 then fs.ReadBuffer(buf[0], Length(buf));
  finally
    fs.Free;
  end;

  if (Length(buf) < 6) or (W16(buf, 0) <> 0) then exit('Not a worksheet file');
  if W16(buf, 4) = $0405 then exit('Symphony files are not supported');
  sh.Reset;
  lastFormula := nil;
  sawBof := False;
  p := 0;
  while p + 4 <= Length(buf) do
  begin
    op := W16(buf, p);
    ln := W16(buf, p + 2);
    if p + 4 + ln > Length(buf) then
    begin
      Warn('The file is truncated; what could be read was loaded');
      break;
    end;
    SetLength(body, ln);
    if ln > 0 then Move(buf[p + 4], body[0], ln);
    Inc(p, 4 + ln);

    if (not sawBof) and (op <> 0) then exit('Not a worksheet file');
    case op of
      0:
        begin
          if ln < 2 then exit('Not a worksheet file');
          info.Version := W16(body, 0);
          sawBof := True;
          if info.Version = $0405 then exit('Symphony files are not supported');
          if (info.Version <> $0404) and (info.Version <> $0406) then
            Warn(Format('Unknown file version %.4x; reading it as a 1-2-3 worksheet', [info.Version]));
        end;
      1: break;
      2: if ln >= 1 then sh.RecalcManual := body[0] = 0;
      3:
        if ln >= 1 then
          case body[0] of
            1: sh.RecalcOrder := roColumnwise;
            $FF: sh.RecalcOrder := roRowwise;
          else
            sh.RecalcOrder := roNatural;
          end;
      $2F:
        if (ln >= 1) and (body[0] >= 1) and (body[0] <= 50) then sh.Iterations := body[0];
      7:
        if ln >= 8 then
        begin
          info.CursorCol := W16(body, 0) + 1;
          info.CursorRow := W16(body, 2) + 1;
          if (info.CursorCol > MaxCol) or (info.CursorRow > MaxRow) then
          begin
            info.CursorCol := 1;
            info.CursorRow := 1;
          end;
          sh.GlobalFmt := ByteToFormat(body[4]);
          if sh.GlobalFmt.UseGlobal then sh.GlobalFmt := MakeFormat(fkGeneral, 0);
          sh.GlobalFmt.UseGlobal := False;
          v := W16(body, 6);
          if (v >= 1) and (v <= 240) then sh.GlobalWidth := v;
          { frozen titles live here: counts and where they start }
          if ln >= 24 then
          begin
            if (W16(body, 16) > 0) and (W16(body, 20) + W16(body, 16) <= MaxCol) then
            begin
              sh.TitleC1 := W16(body, 20) + 1;
              sh.TitleC2 := W16(body, 20) + W16(body, 16);
            end;
            if (W16(body, 18) > 0) and (W16(body, 22) + W16(body, 18) <= MaxRow) then
            begin
              sh.TitleR1 := W16(body, 22) + 1;
              sh.TitleR2 := W16(body, 22) + W16(body, 18);
            end;
          end;
        end;
      8:
        if ln >= 3 then
        begin
          c := W16(body, 0) + 1;
          if (c >= 1) and (c <= MaxCol) and (body[2] >= 1) then sh.SetColWidth(c, body[2]);
        end;
      $29:
        if ln >= 1 then
          case body[0] of
            $22: sh.GlobalLabelPrefix := '"';
            $5E: sh.GlobalLabelPrefix := '^';
          else
            sh.GlobalLabelPrefix := '''';
          end;
      $0B:
        if ln >= 24 then
        begin
          i := 0;
          nm := '';
          while (i < 16) and (body[i] <> 0) do
          begin
            nm := nm + Chr(body[i]);
            Inc(i);
          end;
          nm := UpperCase(nm);
          g := NormRange(W16(body, 18) + 1, W16(body, 16) + 1, W16(body, 22) + 1, W16(body, 20) + 1);
          if IsValidName(nm) and InBounds(g.R1, g.C1) and InBounds(g.R2, g.C2) then
            sh.SetName(nm, g)
          else
            Warn('Range name ' + nm + ' was not imported');
        end;
      $0C, $0D, $0E, $0F, $10:
        begin
          if ln < 5 then continue;
          fmt := body[0];
          c := W16(body, 1);
          r := W16(body, 3);
          if (c >= MaxCol) or (r >= MaxRow) then
          begin
            Warn('Cell outside the worksheet ignored');
            continue;
          end;
          cell := nil;
          case op of
            $0C:
              cell := sh.Put(r + 1, c + 1, '');
            $0D:
              if ln >= 7 then cell := sh.Put(r + 1, c + 1, IntToStr(S16(body, 5)));
            $0E:
              if ln >= 13 then
              begin
                if CellNaN(body, 5, isNA, isErr, isStr) then
                begin
                  if isNA then cell := sh.Put(r + 1, c + 1, '@NA') else cell := sh.Put(r + 1, c + 1, '@ERR');
                end
                else
                  cell := sh.Put(r + 1, c + 1, NumToRaw(F64(body, 5)));
              end;
            $0F:
              if ln >= 7 then
              begin
                SetString(txt, PChar(@body[6]), ln - 6);
                i := Pos(#0, txt);
                if i > 0 then SetLength(txt, i - 1);
                txt := LicsToUtf8(txt);
                if not (Chr(body[5]) in LabelPrefixes) then
                  txt := '''' + Chr(body[5]) + txt          { odd prefix byte: keep the byte as text }
                else
                  txt := Chr(body[5]) + txt;
                cell := sh.Put(r + 1, c + 1, txt);
              end;
            $10:
              if ln >= 15 then
              begin
                Inc(info.Formulas);
                codeLen := W16(body, 13);
                if 15 + codeLen > ln then codeLen := ln - 15;
                SetLength(code, codeLen);
                if codeLen > 0 then Move(body[15], code[0], codeLen);
                isNA := False; isErr := False; isStr := False;
                d := 0;
                if CellNaN(body, 5, isNA, isErr, isStr) then
                  d := 0
                else
                  d := F64(body, 5);
                cell := nil;
                if DecodeFormula(code, r + 1, c + 1, txt) then
                begin
                  cell := sh.Put(r + 1, c + 1, txt);
                  if cell.Formula = nil then
                  begin
                    sh.Remove(r + 1, c + 1);
                    cell := nil;
                  end;
                end;
                if cell = nil then
                begin
                  { keep the value the file had; say so }
                  Inc(info.FormulasLost);
                  Warn(Where(r, c) + ': formula could not be imported; kept its value');
                  if isNA then cell := sh.Put(r + 1, c + 1, '@NA')
                  else if isErr then cell := sh.Put(r + 1, c + 1, '@ERR')
                  else if isStr then cell := sh.Put(r + 1, c + 1, '''')
                  else cell := sh.Put(r + 1, c + 1, NumToRaw(d));
                end
                else if isNA then cell.Val := NAValue
                else if isErr then cell.Val := ErrValue
                else if not isStr then cell.Val := NumValue(d);
                lastFormula := cell;
              end;
          end;
          if cell <> nil then
          begin
            cell.Fmt := ByteToFormat(fmt);
            { the format byte of a cell holds the cell's own format; 15 = follow global }
          end;
        end;
      $33:
        if (ln >= 6) and (lastFormula <> nil) and (lastFormula.Row = W16(body, 3) + 1) and
           (lastFormula.Col = W16(body, 1) + 1) then
        begin
          SetString(txt, PChar(@body[5]), ln - 5);
          i := Pos(#0, txt);
          if i > 0 then SetLength(txt, i - 1);
          lastFormula.Val := StrValue(LicsToUtf8(txt));
        end;
    else
      { records not modelled here are skipped }
    end;
  end;
  if not sawBof then exit('Not a worksheet file');
  sh.Changed := True;
end;

{ ------------------------------------------------------------------ saving }

type
  TWriter = class
  public
    Out: TBytes;
    procedure Rec(op: Integer; const body: TBytes);
    procedure Rec0(op: Integer);
    procedure Rec1(op, v: Integer);
  end;

procedure TWriter.Rec(op: Integer; const body: TBytes);
var
  i: Integer;
begin
  PutW(Out, op);
  PutW(Out, Length(body));
  for i := 0 to High(body) do PutB(Out, body[i]);
end;

procedure TWriter.Rec0(op: Integer);
var
  e: TBytes;
begin
  SetLength(e, 0);
  Rec(op, e);
end;

procedure TWriter.Rec1(op, v: Integer);
var
  b: TBytes;
begin
  SetLength(b, 0);
  PutB(b, v);
  Rec(op, b);
end;

function FFBytes(n: Integer): TBytes;
var
  i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := $FF;
end;

function Filled(n, v: Integer): TBytes;
var
  i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := v;
end;

type
  TCellRef = record
    R, C: Integer;
    Cell: TCell;
  end;
  TCellRefs = array of TCellRef;

  TCollectCtx = record
    Items: ^TCellRefs;
    N: Integer;
  end;
  PCollectCtx = ^TCollectCtx;

procedure CollectAll(cell: TCell; data: Pointer);
var
  ctx: PCollectCtx;
begin
  ctx := PCollectCtx(data);
  if (cell.Raw = '') and cell.Fmt.UseGlobal then exit;     { nothing worth saving }
  if ctx^.N = Length(ctx^.Items^) then SetLength(ctx^.Items^, ctx^.N * 2 + 64);
  ctx^.Items^[ctx^.N].R := cell.Row;
  ctx^.Items^[ctx^.N].C := cell.Col;
  ctx^.Items^[ctx^.N].Cell := cell;
  Inc(ctx^.N);
end;

procedure SortRefs(var a: TCellRefs; n: Integer);
  function Less(const x, y: TCellRef): Boolean;
  begin
    Result := (x.R < y.R) or ((x.R = y.R) and (x.C < y.C));
  end;
  procedure QS(lo, hi: Integer);
  var
    i, j: Integer;
    pivot, t: TCellRef;
  begin
    while lo < hi do
    begin
      i := lo;
      j := hi;
      pivot := a[(lo + hi) div 2];
      repeat
        while Less(a[i], pivot) do Inc(i);
        while Less(pivot, a[j]) do Dec(j);
        if i <= j then
        begin
          t := a[i]; a[i] := a[j]; a[j] := t;
          Inc(i);
          Dec(j);
        end;
      until i > j;
      if j - lo < hi - i then
      begin
        QS(lo, j);
        lo := i;
      end
      else
      begin
        QS(i, hi);
        hi := j;
      end;
    end;
  end;
begin
  QS(0, n - 1);
end;

function SaveWorksheet(const fn: string; sh: TSheet; wks: Boolean; const info: TFileInfo;
                       warnings: TStrings): string;
var
  w: TWriter;
  items: TCellRefs;
  ctx: TCollectCtx;
  i, c, r, minC, minR, maxC, maxR: Integer;
  b: TBytes;
  cell: TCell;
  d: Double;
  fmt: Byte;
  p: Char;
  t, label_: string;
  names: TStringList;
  g: TRange;
  fm: TFormula;
  code: TBytes;
  fs: TFileStream;
  pos: Integer;
  nan: Int64;
  lost: Integer;
  stringCells: Boolean;
  HasC, HasR: Boolean;

  procedure Warn(const s: string);
  begin
    if warnings <> nil then warnings.Add(s);
  end;

  function Head(r, c: Integer; fmtByte: Byte): TBytes;
  begin
    SetLength(Result, 0);
    PutB(Result, fmtByte);
    PutW(Result, c - 1);
    PutW(Result, r - 1);
  end;

  function Where(rr, cc: Integer): string;
  begin
    Result := ColLetter(cc) + IntToStr(rr);
  end;

begin
  Result := '';
  w := TWriter.Create;
  names := TStringList.Create;
  try
    ctx.Items := @items;
    ctx.N := 0;
    SetLength(items, 0);
    sh.EachCell(@CollectAll, @ctx);
    SortRefs(items, ctx.N);

    minC := MaxCol + 1; minR := MaxRow + 1; maxC := 0; maxR := 0;
    for i := 0 to ctx.N - 1 do
    begin
      if items[i].C < minC then minC := items[i].C;
      if items[i].R < minR then minR := items[i].R;
      if items[i].C > maxC then maxC := items[i].C;
      if items[i].R > maxR then maxR := items[i].R;
    end;

    { BOF }
    SetLength(b, 0);
    if wks then PutW(b, $0404) else PutW(b, $0406);
    w.Rec(0, b);
    { RANGE: the used area }
    SetLength(b, 0);
    if ctx.N = 0 then
    begin
      PutW(b, $FFFF); PutW(b, $FFFF); PutW(b, $FFFF); PutW(b, $FFFF);
    end
    else
    begin
      PutW(b, minC - 1); PutW(b, minR - 1); PutW(b, maxC - 1); PutW(b, maxR - 1);
    end;
    w.Rec(6, b);
    if not wks then w.Rec1($2F, sh.Iterations);
    if sh.RecalcManual then w.Rec1(2, 0) else w.Rec1(2, $FF);
    case sh.RecalcOrder of
      roColumnwise: w.Rec1(3, 1);
      roRowwise: w.Rec1(3, $FF);
    else
      w.Rec1(3, 0);
    end;
    w.Rec1(4, 0);          { not split }
    w.Rec1(5, $FF);        { windows synchronised }
    { WINDOW1 }
    SetLength(b, 0);
    PutW(b, Max(info.CursorCol, 1) - 1);
    PutW(b, Max(info.CursorRow, 1) - 1);
    fmt := FormatToByte(sh.GlobalFmt) and $7F;
    PutB(b, fmt);
    PutB(b, 0);
    PutW(b, sh.GlobalWidth);
    PutW(b, 7);                       { columns shown }
    PutW(b, 20);                      { rows shown }
    HasC := (sh.TitleC1 > 0) and (sh.TitleC2 >= sh.TitleC1);
    HasR := (sh.TitleR1 > 0) and (sh.TitleR2 >= sh.TitleR1);
    PutW(b, Max(info.LeftCol, 1) - 1);                 { 12: leftmost column shown }
    PutW(b, Max(info.TopRow, 1) - 1);                  { 14: top row shown }
    if HasC then PutW(b, sh.TitleC2 - sh.TitleC1 + 1) else PutW(b, 0);   { 16: title columns }
    if HasR then PutW(b, sh.TitleR2 - sh.TitleR1 + 1) else PutW(b, 0);   { 18: title rows }
    if HasC then PutW(b, sh.TitleC1 - 1) else PutW(b, 0);                { 20: left title column }
    if HasR then PutW(b, sh.TitleR1 - 1) else PutW(b, 0);                { 22: top title row }
    PutW(b, 4);                                        { 24: width of the row-number border (0 hides it) }
    PutW(b, 4);                                        { 26: height of the column-letter border }
    PutW(b, 72);                                       { 28: window width }
    PutB(b, 0);                                        { 30 }
    if not wks then PutB(b, 0);                        { 31 (release 2 files only) }
    w.Rec(7, b);
    { column widths }
    for c := 1 to MaxCol do
      if sh.ColWidthIsSet(c) then
      begin
        SetLength(b, 0);
        PutW(b, c - 1);
        PutB(b, sh.ColWidthSetting(c));
        w.Rec(8, b);
      end;
    { range names }
    sh.NameList(names);
    for i := 0 to names.Count - 1 do
    begin
      sh.FindName(names[i], g);
      SetLength(b, 0);
      for c := 1 to 16 do
        if c <= Length(names[i]) then PutB(b, Ord(names[i][c])) else PutB(b, 0);
      PutW(b, g.C1 - 1); PutW(b, g.R1 - 1); PutW(b, g.C2 - 1); PutW(b, g.R2 - 1);
      w.Rec($0B, b);
    end;
    { settings records whose contents are constant "unset" defaults }
    if not wks then
    begin
      w.Rec($64, Filled(32, 0));
      SetLength(b, 0); PutB(b, 0); for c := 1 to 24 do PutB(b, $FF);
      w.Rec($18, b);                                          { data table }
      SetLength(b, 0); for c := 1 to 24 do PutB(b, $FF); PutB(b, 0);
      w.Rec($19, b);                                          { query }
      w.Rec($1A, FFBytes(8));                                 { print range }
      w.Rec1($30, 0);
      w.Rec($1C, FFBytes(8));
      w.Rec($1B, FFBytes(8));
      SetLength(b, 0); for c := 1 to 8 do PutB(b, $FF); PutB(b, 2);
      w.Rec($1D, b);                                          { sort keys }
      SetLength(b, 0); for c := 1 to 8 do PutB(b, $FF); PutB(b, 0);
      w.Rec($1D, b);
      w.Rec($23, b);
      w.Rec($20, FFBytes(16));
    end;
    w.Rec1($24, 0);                                           { global protection off }
    case sh.GlobalLabelPrefix of
      '"': w.Rec1($29, $22);
      '^': w.Rec1($29, $5E);
    else
      w.Rec1($29, $27);
    end;
    { print borders (/Print Options Borders): not tracked, written as unset.  Frozen
      worksheet titles are in WINDOW1. }
    w.Rec($2A, FFBytes(16));

    if not wks then
    begin
      w.Rec($66, FFBytes(16));
      SetLength(b, 0); for c := 1 to 24 do PutB(b, $FF); PutB(b, 0);
      w.Rec($67, b);
      w.Rec($69, FFBytes(40));
    end;

    { cells, row by row }
    lost := 0;
    for i := 0 to ctx.N - 1 do
    begin
      cell := items[i].Cell;
      r := items[i].R;
      c := items[i].C;
      fmt := FormatToByte(cell.Fmt);
      if cell.Raw = '' then
      begin
        w.Rec($0C, Head(r, c, fmt));
        continue;
      end;
      if cell.Formula <> nil then
      begin
        code := EncodeFormula(cell.Formula, sh, r, c);
        if code = nil then
          Warn(Where(r, c) + ': formula uses a function the file format has no code for; stored as its value');
        if Length(code) > 2048 then
        begin
          Warn(Where(r, c) + ': formula too long for the file format; stored as its value');
          code := nil;
        end;
        if code <> nil then
        begin
          b := Head(r, c, fmt);
          case cell.Val.Kind of
            vkNum: PutF(b, cell.Val.Num);
            vkNA:  begin nan := Int64($FFF0000000000000); PutF(b, Double(Pointer(@nan)^)); end;
            vkErr: begin nan := Int64($7FF0000000000000); PutF(b, Double(Pointer(@nan)^)); end;
            vkStr: begin nan := Int64($7FF0000000000001); PutF(b, Double(Pointer(@nan)^)); end;   { a string follows }
          else
            PutF(b, 0);
          end;
          PutW(b, Length(code));
          for pos := 0 to High(code) do PutB(b, code[pos]);
          w.Rec($10, b);
          if cell.Val.Kind = vkStr then
          begin
            b := Head(r, c, fmt);
            PutStr0(b, Utf8ToLics(cell.Val.Str));
            { head is fmt, col, row: STRING has the same three leading fields }
            w.Rec($33, b);
          end;
          continue;
        end;
        { fall through: store the value }
        Inc(lost);
        if CellNumber(cell, d) then
        begin
          b := Head(r, c, fmt);
          PutF(b, d);
          w.Rec($0E, b);
        end;
        continue;
      end;
      if (cell.Raw[1] in LabelPrefixes) then
      begin
        label_ := Utf8ToLics(Copy(cell.Raw, 2, MaxInt));
        if Length(label_) > 240 then
        begin
          Warn(Where(r, c) + ': label longer than 240 characters was cut');
          SetLength(label_, 240);
        end;
        b := Head(r, c, fmt);
        PutB(b, Ord(cell.Raw[1]));
        PutStr0(b, label_);
        w.Rec($0F, b);
      end
      else if CellNumber(cell, d) then
      begin
        b := Head(r, c, fmt);
        if (d = Int(d)) and (Abs(d) <= 32767) and not ((d = 0) and (1 / d < 0)) then
        begin
          PutW(b, Trunc(d) and $FFFF);
          w.Rec($0D, b);
        end
        else
        begin
          PutF(b, d);
          w.Rec($0E, b);
        end;
      end
      else
        Warn(Where(r, c) + ': contents are not a valid number or formula; not saved');
    end;
    if lost > 0 then Warn(IntToStr(lost) + ' formula(s) could not be written and were saved as values');
    w.Rec0(1);

    try
      fs := TFileStream.Create(fn, fmCreate);
    except
      on E: Exception do exit('Cannot write ' + ExtractFileName(fn));
    end;
    try
      if Length(w.Out) > 0 then fs.WriteBuffer(w.Out[0], Length(w.Out));
    finally
      fs.Free;
    end;
  finally
    names.Free;
    w.Free;
  end;
end;

end.
