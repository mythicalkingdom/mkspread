{ Checks the file layer against real worksheet files, if a private-samples
  folder exists next to the tests (it is not part of the repository).

  For every .WK1/.WKS file:
    * it loads without error
    * every formula, decoded and encoded again, gives the original bytes
    * after recalculation every numeric formula result matches the value that
      was stored in the file (formulas using unimplemented @functions excepted)
    * saving and loading again reproduces the same sheet
  Only cell addresses and counts are printed, never cell contents. }
program test_samples;
{$mode objfpc}{$H+}

uses SysUtils, Classes, sheet, formula, wk1, session, cellfmt;

type
  TCached = record
    R, C: Integer;
    V: Double;
    Special: Integer;        { 0 number, 1 NA, 2 ERR, 3 string }
    Code: TBytes;
  end;

var
  Fails, Total: Integer;
  Files, FormulaCells, Lost, ByteMismatch, Equivalent, ValueChecked, ValueMismatch, Skipped: Integer;

function W16(const b: TBytes; p: Integer): Integer;
begin
  Result := b[p] or (b[p + 1] shl 8);
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

function Hex(const b: TBytes): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(b) do Result := Result + IntToHex(b[i], 2) + ' ';
end;

function UsesUnimplemented(const code: TBytes): Boolean;
var
  i, t, fi: Integer;
begin
  Result := False;
  i := 0;
  while i < Length(code) do
  begin
    t := code[i];
    case t of
      0, 2: Inc(i, 9);
      1: Inc(i, 5);
      5: Inc(i, 3);
      6: begin while (i < Length(code)) and (code[i] <> 0) do Inc(i); Inc(i); end;
      3, 4, 8..24: Inc(i);
    else
      begin
        fi := FuncIndexByOpcode(t);
        if (fi >= 0) and not FuncImplemented(fi) then exit(True);
        if (fi >= 0) and FuncIsList(fi) then Inc(i, 2) else Inc(i);
      end;
    end;
  end;
end;

procedure Fail(const msg: string);
begin
  Inc(Fails);
  WriteLn('  FAIL: ', msg);
end;

procedure ReadFormulas(const fn: string; var cached: array of TCached; out n: Integer);
var
  fs: TFileStream;
  buf: TBytes;
  p, op, ln, sz: Integer;
begin
  fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  SetLength(buf, fs.Size);
  fs.ReadBuffer(buf[0], Length(buf));
  fs.Free;
  n := 0;
  p := 0;
  while p + 4 <= Length(buf) do
  begin
    op := W16(buf, p);
    ln := W16(buf, p + 2);
    if op = $10 then
    begin
      sz := W16(buf, p + 4 + 13);
      if n <= High(cached) then
      begin
        cached[n].C := W16(buf, p + 5) + 1;
        cached[n].R := W16(buf, p + 7) + 1;
        cached[n].V := F64(buf, p + 4 + 5);
        cached[n].Special := 0;
        if (W16(buf, p + 4 + 11) and $7FF0) = $7FF0 then cached[n].Special := 2;
        SetLength(cached[n].Code, sz);
        if sz > 0 then Move(buf[p + 4 + 15], cached[n].Code[0], sz);
        Inc(n);
      end;
    end;
    Inc(p, 4 + ln);
  end;
end;

procedure CheckFile(const fn: string);
var
  S, S2: TSession;
  info: TFileInfo;
  warn: TStringList;
  msg, tmp: string;
  cached: array of TCached;
  n, i, k: Integer;
  cell, c2: TCell;
  enc: TBytes;
  ok: Boolean;
  maxR, maxC, cnt, cnt2: Integer;
  shown, ep: Integer;
  tf: string;
  fo: TFormula;
begin
  Inc(Files);
  S := TSession.Create;
  warn := TStringList.Create;
  SetLength(cached, 20000);
  try
    msg := LoadWorksheet(fn, S.Sheet, warn, info);
    if msg <> '' then
    begin
      Fail(ExtractFileName(fn) + ': ' + msg);
      exit;
    end;
    ReadFormulas(fn, cached, n);
    Inc(FormulaCells, n);
    Inc(Lost, info.FormulasLost);
    if info.FormulasLost > 0 then
      WriteLn('  ', ExtractFileName(fn), ': ', info.FormulasLost, ' formula(s) not imported: ', warn.CommaText);

    { formulas re-encode to the original bytes }
    shown := 0;
    for i := 0 to n - 1 do
    begin
      cell := S.Sheet.Find(cached[i].R, cached[i].C);
      if (cell = nil) or (cell.Formula = nil) then continue;
      enc := EncodeFormula(cell.Formula, S.Sheet, cached[i].R, cached[i].C);
      ok := Length(enc) = Length(cached[i].Code);
      if ok then
        for k := 0 to High(enc) do
          if enc[k] <> cached[i].Code[k] then ok := False;
      if not ok then
      begin
        { the same formula with range corners stored in another order is fine }
        if DecodeFormula(cached[i].Code, cached[i].R, cached[i].C, tf) and
           CompileFormula(tf, fo, ep) then
        begin
          ok := fo.Text = cell.Formula.Text;
          fo.Free;
          if ok then Inc(Equivalent);
        end;
      end;
      if not ok then
      begin
        Inc(ByteMismatch);
        if shown < 3 then
        begin
          WriteLn('  re-encode differs at ', ColLetter(cached[i].C), cached[i].R, ' (', cell.Raw, ')');
          WriteLn('    file: ', Hex(cached[i].Code));
          WriteLn('    ours: ', Hex(enc));
          Inc(shown);
        end;
      end;
    end;

    { recalculated values match the stored ones }
    S.Calc.Recalc;
    shown := 0;
    for i := 0 to n - 1 do
    begin
      cell := S.Sheet.Find(cached[i].R, cached[i].C);
      if (cell = nil) or (cell.Formula = nil) then continue;
      if UsesUnimplemented(cached[i].Code) then begin Inc(Skipped); continue; end;
      Inc(ValueChecked);
      ok := False;
      if cached[i].Special = 2 then
        ok := cell.Val.Kind in [vkErr, vkNA]
      else if cell.Val.Kind = vkNum then
        ok := Abs(cell.Val.Num - cached[i].V) <= 1e-9 * (1 + Abs(cached[i].V));
      if not ok then
      begin
        Inc(ValueMismatch);
        if shown < 3 then
        begin
          WriteLn('  value differs at ', ColLetter(cached[i].C), cached[i].R, ': formula ', cell.Raw);
          Inc(shown);
        end;
      end;
    end;

    { save and load again }
    tmp := GetTempDir + 'mkspread_rt.wk1';
    SaveWorksheet(tmp, S.Sheet, False, info, nil);
    S2 := TSession.Create;
    try
      msg := LoadWorksheet(tmp, S2.Sheet, nil, info);
      if msg <> '' then
        Fail(ExtractFileName(fn) + ' round trip: ' + msg)
      else
      begin
        S.Sheet.UsedExtent(maxR, maxC);
        cnt := 0;
        cnt2 := 0;
        for k := 1 to maxR do
          for i := 1 to maxC do
          begin
            cell := S.Sheet.Find(k, i);
            c2 := S2.Sheet.Find(k, i);
            if (cell <> nil) and (cell.Raw <> '') then
            begin
              Inc(cnt);
              if (c2 = nil) or (c2.Raw <> cell.Raw) then Fail(Format('%s round trip: cell %s%d differs', [ExtractFileName(fn), ColLetter(i), k]))
              else if FormatTag(c2.Fmt) <> FormatTag(cell.Fmt) then Fail(Format('%s round trip: format of %s%d differs', [ExtractFileName(fn), ColLetter(i), k]))
              else Inc(cnt2);
            end;
          end;
        if cnt <> cnt2 then Fail(ExtractFileName(fn) + ' round trip: cell count differs');
        for i := 1 to 255 do
          if S.Sheet.ColWidth(i) <> S2.Sheet.ColWidth(i) then
          begin
            Fail(Format('%s round trip: width of column %d differs', [ExtractFileName(fn), i]));
            break;
          end;
      end;
    finally
      S2.Free;
      DeleteFile(tmp);
    end;
  finally
    warn.Free;
    S.Free;
  end;
end;

var
  sr: TSearchRec;
  dir: string;
begin
  dir := 'private-samples';
  if not DirectoryExists(dir) then
  begin
    WriteLn('private-samples not found: corpus tests skipped');
    Halt(0);
  end;
  if FindFirst(dir + '/*', faAnyFile, sr) = 0 then
  begin
    repeat
      { MKT*.WK1 are generated by make_testsheet, not real samples }
      if (Copy(UpperCase(sr.Name), 1, 3) <> 'MKT') and
         ((UpperCase(ExtractFileExt(sr.Name)) = '.WK1') or (UpperCase(ExtractFileExt(sr.Name)) = '.WKS')) then
        CheckFile(dir + '/' + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  WriteLn(Files, ' files, ', FormulaCells, ' formulas: ', Lost, ' not imported, ',
          ByteMismatch, ' re-encode mismatches (', Equivalent, ' differ only in range corner order), ', ValueChecked, ' values checked (',
          Skipped, ' skipped for unimplemented functions), ', ValueMismatch, ' value mismatches, ',
          Fails, ' other failures');
  if (Fails > 0) or (ByteMismatch > 0) or (ValueMismatch > 0) or (Lost > 0) then Halt(1);
end.
