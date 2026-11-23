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
    Pos: Integer;                     { lines already on the current page (0 = at the top) }
    PageNo: Integer;                  { the page number in the footer of the page in progress }
    Today: string;                    { replaces the date in headers (for tests) }
  end;

procedure ResetPrint(var ps: TPrintSettings);          { Clear All }
procedure ResetPrintFormat(var ps: TPrintSettings);    { Clear Format }

{ the text for the print range as set (Go): pages of PgLength lines }
function PrintRangeText(sh: TSheet; var ps: TPrintSettings; out err: string): string;

{ Line and Page: advance the paper one line / to the top of the next page }
function PrintLineText(var ps: TPrintSettings): string;
function PrintPageText(var ps: TPrintSettings): string;

{ the bytes of a setup string such as '\015' or '\027E' }
function SetupBytes(const s: string): string;

{ one row of a range as it shows on the screen, for the given columns }
function RenderRow(sh: TSheet; r: Integer; const cols: array of Integer;
                   spillCol: Integer = 0; spillMin: Integer = 1): string;

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

function RenderRow(sh: TSheet; r: Integer; const cols: array of Integer;
                   spillCol: Integer; spillMin: Integer): string;
var
  total, ci, cj, c, w, x, k, av, kk, used, si: Integer;
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
  { a left-aligned label that began in an earlier group of columns carries on here }
  if spillCol > 0 then
  begin
    si := -1;
    for ci := 0 to High(cols) do
      if cols[ci] = spillCol then si := ci;
    if (si >= 0) and (sh.Find(r, spillCol) = nil) then
    begin
      kk := spillCol - 1;
      used := 0;
      while (kk >= spillMin) and (sh.Find(r, kk) = nil) do
      begin
        Inc(used, sh.ColWidth(kk));
        Dec(kk);
      end;
      if kk >= spillMin then
      begin
        cell := sh.Find(r, kk);
        if (cell <> nil) and TextOf(cell, pre, txt) and (pre = '''') then
        begin
          Inc(used, sh.ColWidth(kk));
          t := UTF8Decode(txt);
          if Length(t) > used then
          begin
            x := 1;
            for ci := 0 to si - 1 do Inc(x, sh.ColWidth(cols[ci]));
            av := sh.ColWidth(spillCol);
            cj := si + 1;
            while (cj <= High(cols)) and (sh.Find(r, cols[cj]) = nil) do
            begin
              Inc(av, sh.ColWidth(cols[cj]));
              Inc(cj);
            end;
            PutBuf(x, Copy(t, used + 1, av));
          end;
        end;
      end;
    end;
  end;
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
              if Length(t) < w then PutBuf(x + w - Length(t) - 1, t) else PutBuf(x, t);
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
        t := UTF8Decode(ValueDisplay(cell, sh, w));
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
  d: Double;
begin
  cell := sh.Find(r, c);
  Result := ColLetter(c) + IntToStr(r) + ':';
  if not cell.Fmt.UseGlobal then Result := Result + ' (' + FormatTag(cell.Fmt) + ')';
  if sh.ColWidthIsSet(c) then Result := Result + ' [W' + IntToStr(sh.ColWidth(c)) + ']';
  if CellNumber(cell, d) and (cell.Formula = nil) then Result := Result + ' ' + NumToRaw(d)
  else Result := Result + ' ' + cell.Raw;
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

function Indented0(const ps: TPrintSettings; const s: string): string;
begin
  if s = '' then Result := '' else Result := StringOfChar(' ', ps.Left) + s;
end;

type
  { writes lines onto pages the way the original program does: the position in the
    page carries over from one print job to the next, the top of a page is printed
    when the first line of it is, and a job ends without finishing its last page }
  TPager = class
    Ps: ^TPrintSettings;
    Outp: TStringList;
    Borders: TStringList;
    Width, Indent: Integer;
    Today: string;
    constructor Create(var aps: TPrintSettings; aout: TStringList);
    function BodyEnd: Integer;
    function Indented(const s: string): string;
    procedure Body(const line: string);
    procedure FinishPage;               { fill the page and print its end }
    procedure PageEnd;
  end;

constructor TPager.Create(var aps: TPrintSettings; aout: TStringList);
begin
  Ps := @aps;
  Outp := aout;
  Borders := nil;
  Width := aps.Right - aps.Left;
  if Width < 1 then Width := 1;
  Indent := aps.Left;
  if aps.Today <> '' then Today := aps.Today else Today := FormatDateTime('dd-mmm-yy', Now);
end;

function TPager.BodyEnd: Integer;
begin
  Result := Ps^.PgLength - Ps^.Bottom - 3;
  if Result < Ps^.Top + 4 then Result := Ps^.Top + 4;
end;

function TPager.Indented(const s: string): string;
begin
  if s = '' then Result := '' else Result := StringOfChar(' ', Indent) + s;
end;

procedure TPager.PageEnd;
var
  i: Integer;
begin
  Outp.Add('');
  Outp.Add('');
  Outp.Add(Indented(Decorate(Ps^.Footer, IntToStr(Ps^.PageNo), Today, Width)));
  for i := 1 to Ps^.Bottom do Outp.Add('');
  Ps^.Pos := 0;
  Inc(Ps^.PageNo);
end;

procedure TPager.Body(const line: string);
var
  i: Integer;
begin
  if Ps^.Pos = 0 then
  begin
    for i := 1 to Ps^.Top do Outp.Add('');
    Outp.Add(Indented(Decorate(Ps^.Header, IntToStr(Ps^.PageNo), Today, Width)));
    Outp.Add('');
    Outp.Add('');
    Ps^.Pos := Ps^.Top + 3;
    if Borders <> nil then
      for i := 0 to Borders.Count - 1 do
      begin
        Outp.Add(Indented(Borders[i]));
        Inc(Ps^.Pos);
      end;
  end;
  Outp.Add(Indented(line));
  Inc(Ps^.Pos);
  if Ps^.Pos >= BodyEnd then PageEnd;
end;

procedure TPager.FinishPage;
begin
  if Ps^.Pos = 0 then exit;
  while Ps^.Pos < BodyEnd do
  begin
    Outp.Add('');
    Inc(Ps^.Pos);
  end;
  PageEnd;
end;

function PrintLineText(var ps: TPrintSettings): string;
var
  o: TStringList;
  pg: TPager;
begin
  o := TStringList.Create;
  pg := TPager.Create(ps, o);
  try
    pg.Body('');
    Result := o.Text;
  finally
    pg.Free;
    o.Free;
  end;
end;

function PrintPageText(var ps: TPrintSettings): string;
var
  o: TStringList;
  pg: TPager;
begin
  o := TStringList.Create;
  pg := TPager.Create(ps, o);
  try
    pg.FinishPage;
    Result := o.Text;
  finally
    pg.Free;
    o.Free;
  end;
end;

function PrintRangeText(sh: TSheet; var ps: TPrintSettings; out err: string): string;
var
  outp: TStringList;
  pg: TPager;
  rows: array of Integer;         { printable rows in order; page breaks are -1 }
  nrows: Integer;

  procedure AddRow(r: Integer);
  begin
    if nrows >= Length(rows) then SetLength(rows, nrows * 2 + 16);
    rows[nrows] := r;
    Inc(nrows);
  end;

var
  r, c, i, j: Integer;
  cols: array of Integer;
  group: array of Integer;
  gw, w, width: Integer;
  borderLines: TStringList;
  cell: TCell;
  pre: Char;
  txt: string;
  skip, firstGroup: Boolean;
  firstCol: Integer;
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
  ps.PageNo := 1;
  outp := TStringList.Create;
  borderLines := TStringList.Create;
  pg := TPager.Create(ps, outp);
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
          if not ps.Unformatted then pg.FinishPage;
          continue;
        end;
        for c := rg.C1 to rg.C2 do
        begin
          cell := sh.Find(rows[i], c);
          if (cell <> nil) and (cell.Raw <> '') then
            if ps.Unformatted then
            begin
              outp.Add(Indented0(ps, FormulaLine(sh, rows[i], c)));
              Inc(ps.Pos);
            end
            else pg.Body(FormulaLine(sh, rows[i], c));
        end;
      end;
      Result := outp.Text;
      exit;
    end;

    if ps.Unformatted then
    begin
      SetLength(cols, rg.C2 - rg.C1 + 1);
      for c := rg.C1 to rg.C2 do cols[c - rg.C1] := c;
      for i := 0 to nrows - 1 do
        if rows[i] >= 0 then
        begin
          outp.Add(Indented0(ps, RenderRow(sh, rows[i], cols)));
          Inc(ps.Pos);               { unformatted lines still move the paper }
        end;
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
    firstGroup := True;
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
      firstCol := group[j];                         { the first column that is not a border column }
      if not firstGroup then pg.FinishPage;       { the next group of columns starts a new page }
      firstGroup := False;
      borderLines.Clear;
      if ps.BorderRowsSet then
        for r := ps.BorderRows.R1 to ps.BorderRows.R2 do borderLines.Add(RenderRow(sh, r, group));
      if borderLines.Count > 0 then pg.Borders := borderLines else pg.Borders := nil;
      { a job that starts in the middle of a page prints the border rows first }
      if (ps.Pos > 0) and (borderLines.Count > 0) then
        for i := 0 to borderLines.Count - 1 do
        begin
          outp.Add(Indented0(ps, borderLines[i]));
          Inc(ps.Pos);
        end;
      for i := 0 to nrows - 1 do
      begin
        if rows[i] < 0 then pg.FinishPage
        else pg.Body(RenderRow(sh, rows[i], group, firstCol, rg.C1));
      end;
    end;
    Result := outp.Text;
  finally
    pg.Free;
    outp.Free;
    borderLines.Free;
  end;
end;

end.
