{ /Print: turns a worksheet range into text, split into pages.  Pure code: the
  commands (cmdprint.pas) keep the settings, send the text to a file or printer. }
unit printing;

{$mode objfpc}{$H+}

interface

uses sheet;

type
  TPrintSettings = record
    RangeSet: Boolean;
    Range: TRange;
    Left, Right, Top, Bottom, PgLength: Integer;
    Header, Footer: string;           { left|centre|right, # = page number, @ = date }
    Setup: string;                    { printer codes: \nnn is the byte with that decimal code }
    BorderCols, BorderRows: TRange;
    BorderColsSet, BorderRowsSet: Boolean;
    CellFormulas: Boolean;            { Other: Cell-Formulas instead of As-Displayed }
    Unformatted: Boolean;             { Other: Unformatted instead of Formatted }
    ToFile: Boolean;                  { destination: a file instead of the printer }
    FileName: string;
    Pending: string;                  { text produced but not yet sent }
    SetupSent: Boolean;
    LinePos: Integer;                 { lines already on the current page }
    Today: string;                    { replaces the date in headers (for tests) }
  end;

procedure ResetPrint(var ps: TPrintSettings);          { Clear All }
procedure ResetPrintFormat(var ps: TPrintSettings);    { Clear Format }

{ the text for the print range as set (Go): pages of PgLength lines }
function PrintRangeText(sh: TSheet; const ps: TPrintSettings; out err: string): string;

{ the bytes of a setup string such as '\015' or '\027E' }
function SetupBytes(const s: string): string;

{ one row of a range as it shows on the screen, for the given columns }
function RenderRow(sh: TSheet; r: Integer; const cols: array of Integer): string;

implementation

uses SysUtils, Classes, cellfmt, formula;

procedure ResetPrintFormat(var ps: TPrintSettings);
begin
  ps.Left := 4;
  ps.Right := 76;
  ps.Top := 2;
  ps.Bottom := 2;
  ps.PgLength := 66;
  ps.Setup := '';
  ps.SetupSent := False;
end;

procedure ResetPrint(var ps: TPrintSettings);
begin
  ps.RangeSet := False;
  ps.Header := '';
  ps.Footer := '';
  ps.BorderColsSet := False;
  ps.BorderRowsSet := False;
  ps.CellFormulas := False;
  ps.Unformatted := False;
  ResetPrintFormat(ps);
end;

function SetupBytes(const s: string): string;
var
  i, n: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(s) do
  begin
    if (s[i] = '\') and (i + 1 <= Length(s)) and (s[i + 1] in ['0'..'9']) then
    begin
      n := 0;
      Inc(i);
      while (i <= Length(s)) and (s[i] in ['0'..'9']) and (n < 100) do
      begin
        n := n * 10 + Ord(s[i]) - 48;
        Inc(i);
      end;
      Result := Result + Chr(n and 255);
    end
    else
    begin
      Result := Result + s[i];
      Inc(i);
    end;
  end;
end;

{ ---------------------------------------------------------------- rows }

function RenderRow(sh: TSheet; r: Integer; const cols: array of Integer): string;
var
  total, ci, cj, c, w, x, k, av: Integer;
  buf, t: UnicodeString;
  cell: TCell;
  pre: Char;
  txt: string;

  procedure PutBuf(pos: Integer; const s: UnicodeString);
  var
    j: Integer;
  begin
    for j := 1 to Length(s) do
      if (pos + j - 1 >= 1) and (pos + j - 1 <= total) then
        buf[pos + j - 1] := s[j];
  end;

begin
  total := 0;
  for ci := 0 to High(cols) do Inc(total, sh.ColWidth(cols[ci]));
  SetLength(buf, total);
  for k := 1 to total do buf[k] := ' ';
  x := 1;
  for ci := 0 to High(cols) do
  begin
    c := cols[ci];
    w := sh.ColWidth(c);
    cell := sh.Find(r, c);
    if (cell <> nil) and (cell.Raw <> '') then
    begin
      if TextOf(cell, pre, txt) then
      begin
        t := UTF8Decode(txt);
        case pre of
          '''', '|':
            begin
              av := w;
              cj := ci + 1;
              while (cj <= High(cols)) and (sh.Find(r, cols[cj]) = nil) do
              begin
                Inc(av, sh.ColWidth(cols[cj]));
                Inc(cj);
              end;
              PutBuf(x, Copy(t, 1, av));
            end;
          '"':
            begin
              t := Copy(t, 1, w);
              PutBuf(x + w - Length(t), t);
            end;
          '^':
            begin
              t := Copy(t, 1, w);
              PutBuf(x + (w - Length(t)) div 2, t);
            end;
          '\':
            if t <> '' then
              for k := 1 to w do
                buf[x + k - 1] := t[((k - 1) mod Length(t)) + 1];
        end;
      end
      else
      begin
        t := UTF8Decode(ValueText(cell, sh, w));
        if Length(t) > w then
        begin
          SetLength(t, w);
          for k := 1 to w do t[k] := '*';
        end;
        if EffectiveFormat(cell, sh).Kind in [fkPlusMinus, fkText] then
          PutBuf(x, t)
        else
          PutBuf(x + w - Length(t), t);
      end;
    end;
    Inc(x, w);
  end;
  { trailing blanks are not printed }
  k := Length(buf);
  while (k > 0) and (buf[k] = ' ') do Dec(k);
  SetLength(buf, k);
  Result := UTF8Encode(buf);
end;

{ the contents of a cell the way the status line shows it }
function FormulaLine(sh: TSheet; r, c: Integer): string;
var
  cell: TCell;
begin
  cell := sh.Find(r, c);
  Result := ColLetter(c) + IntToStr(r) + ':';
  if not cell.Fmt.UseGlobal then Result := Result + ' (' + FormatTag(cell.Fmt) + ')';
  if sh.ColWidthIsSet(c) then Result := Result + ' [W' + IntToStr(sh.ColWidth(c)) + ']';
  Result := Result + ' ' + cell.Raw;
end;

{ ---------------------------------------------------------------- header, footer }

function Decorate(const spec, page, today: string; width: Integer): string;
var
  parts: array[0..2] of string;
  n, i: Integer;
  ch: Char;
  s: string;
  l, m, rr: UnicodeString;
  buf: UnicodeString;
begin
  for i := 0 to 2 do parts[i] := '';
  n := 0;
  for i := 1 to Length(spec) do
  begin
    ch := spec[i];
    if ch = '|' then
    begin
      if n < 2 then Inc(n);
    end
    else if ch = '#' then parts[n] := parts[n] + page
    else if ch = '@' then parts[n] := parts[n] + today
    else parts[n] := parts[n] + ch;
  end;
  l := UTF8Decode(parts[0]);
  m := UTF8Decode(parts[1]);
  rr := UTF8Decode(parts[2]);
  SetLength(buf, width);
  for i := 1 to width do buf[i] := ' ';
  for i := 1 to Length(l) do
    if i <= width then buf[i] := l[i];
  for i := 1 to Length(m) do
    if (width - Length(m)) div 2 + i >= 1 then
      if (width - Length(m)) div 2 + i <= width then buf[(width - Length(m)) div 2 + i] := m[i];
  for i := 1 to Length(rr) do
    if width - Length(rr) + i >= 1 then buf[width - Length(rr) + i] := rr[i];
  s := UTF8Encode(buf);
  while (s <> '') and (s[Length(s)] = ' ') do Delete(s, Length(s), 1);
  Result := s;
end;

{ ---------------------------------------------------------------- pages }

function PrintRangeText(sh: TSheet; const ps: TPrintSettings; out err: string): string;
var
  outp: TStringList;
  width, indent, bodyLines, pageNo: Integer;
  today: string;
  rows: array of Integer;         { printable rows in order; page breaks are -1 }
  nrows: Integer;

  function Indented(const s: string): string;
  begin
    if s = '' then Result := '' else Result := StringOfChar(' ', indent) + s;
  end;

  procedure AddRow(r: Integer);
  begin
    if nrows >= Length(rows) then SetLength(rows, nrows * 2 + 16);
    rows[nrows] := r;
    Inc(nrows);
  end;

  procedure PageStart;
  var
    i: Integer;
  begin
    Inc(pageNo);
    for i := 1 to ps.Top do outp.Add('');
    outp.Add(Indented(Decorate(ps.Header, IntToStr(pageNo), today, width)));
    outp.Add('');                       { the header is followed by two blank lines }
    outp.Add('');
  end;

  procedure PageEnd(used: Integer);
  var
    i: Integer;
  begin
    for i := used + 1 to bodyLines do outp.Add('');
    outp.Add('');
    outp.Add('');
    outp.Add(Indented(Decorate(ps.Footer, IntToStr(pageNo), today, width)));
    for i := 1 to ps.Bottom do outp.Add('');
  end;

  { prints body lines as pages; a page break comes before the lines whose numbers are in breaks }
  procedure Paginate(lines: TStringList; breaks: TList; const borderLines: TStringList);
  var
    i, used, bl, k: Integer;
  begin
    bl := 0;
    if borderLines <> nil then bl := borderLines.Count;
    if bl >= bodyLines then bl := 0;
    i := 0;
    repeat
      PageStart;
      for k := 0 to bl - 1 do outp.Add(Indented(borderLines[k]));
      used := bl;
      while i < lines.Count do
      begin
        if (used > bl) and (breaks.IndexOf(Pointer(PtrInt(i))) >= 0) then break;
        outp.Add(Indented(lines[i]));
        Inc(i);
        Inc(used);
        if used >= bodyLines then break;
      end;
      PageEnd(used);
    until i >= lines.Count;
  end;

var
  r, c, i, j: Integer;
  cols: array of Integer;
  group: array of Integer;
  gw, w: Integer;
  lines, borderLines: TStringList;
  breaks: TList;
  cell: TCell;
  pre: Char;
  txt: string;
  skip: Boolean;
  rg: TRange;
  colList: array of Integer;
  ncols: Integer;
begin
  err := '';
  Result := '';
  if not ps.RangeSet then
  begin
    err := 'Specify a print range first';
    exit;
  end;
  rg := ps.Range;
  width := ps.Right - ps.Left;
  if width < 1 then width := 1;
  indent := ps.Left;
  bodyLines := ps.PgLength - ps.Top - ps.Bottom - 6;
  if bodyLines < 1 then bodyLines := 1;
  if ps.Today <> '' then today := ps.Today else today := FormatDateTime('dd-mmm-yy', Now);
  pageNo := 0;
  outp := TStringList.Create;
  lines := TStringList.Create;
  borderLines := TStringList.Create;
  breaks := TList.Create;
  try
    { the printable rows: a row whose first cell is a label starting | is not printed,
      and a label starting |:: is a page break }
    nrows := 0;
    for r := rg.R1 to rg.R2 do
    begin
      skip := False;
      cell := sh.Find(r, rg.C1);
      if (cell <> nil) and TextOf(cell, pre, txt) and (pre = '|') then
      begin
        skip := True;
        if Copy(txt, 1, 2) = '::' then AddRow(-1);
      end;
      if not skip then AddRow(r);
    end;

    if ps.CellFormulas then
    begin
      for i := 0 to nrows - 1 do
      begin
        if rows[i] < 0 then
        begin
          breaks.Add(Pointer(PtrInt(lines.Count)));
          continue;
        end;
        for c := rg.C1 to rg.C2 do
        begin
          cell := sh.Find(rows[i], c);
          if (cell <> nil) and (cell.Raw <> '') then lines.Add(FormulaLine(sh, rows[i], c));
        end;
      end;
      if ps.Unformatted then
        for i := 0 to lines.Count - 1 do outp.Add(lines[i])
      else
        Paginate(lines, breaks, nil);
      Result := outp.Text;
      exit;
    end;

    if ps.Unformatted then
    begin
      SetLength(cols, rg.C2 - rg.C1 + 1);
      for c := rg.C1 to rg.C2 do cols[c - rg.C1] := c;
      for i := 0 to nrows - 1 do
        if rows[i] >= 0 then outp.Add(RenderRow(sh, rows[i], cols));
      Result := outp.Text;
      exit;
    end;

    { formatted, as displayed: one group of columns after the other }
    ncols := 0;
    SetLength(colList, 0);
    if ps.BorderColsSet then
      for c := ps.BorderCols.C1 to ps.BorderCols.C2 do
      begin
        SetLength(colList, ncols + 1);
        colList[ncols] := c;
        Inc(ncols);
      end;
    j := ncols;                                  { the border columns come first in every group }
    c := rg.C1;
    while c <= rg.C2 do
    begin
      SetLength(group, 0);
      gw := 0;
      for i := 0 to j - 1 do
      begin
        SetLength(group, Length(group) + 1);
        group[High(group)] := colList[i];
        Inc(gw, sh.ColWidth(colList[i]));
      end;
      while c <= rg.C2 do
      begin
        w := sh.ColWidth(c);
        if (Length(group) > j) and (gw + w > width) then break;
        SetLength(group, Length(group) + 1);
        group[High(group)] := c;
        Inc(gw, w);
        Inc(c);
        if gw >= width then break;
      end;
      lines.Clear;
      breaks.Clear;
      borderLines.Clear;
      if ps.BorderRowsSet then
        for r := ps.BorderRows.R1 to ps.BorderRows.R2 do borderLines.Add(RenderRow(sh, r, group));
      for i := 0 to nrows - 1 do
      begin
        if rows[i] < 0 then
          breaks.Add(Pointer(PtrInt(lines.Count)))
        else
          lines.Add(RenderRow(sh, rows[i], group));
      end;
      Paginate(lines, breaks, borderLines);
    end;
    Result := outp.Text;
  finally
    outp.Free;
    lines.Free;
    borderLines.Free;
    breaks.Free;
  end;
end;

end.
