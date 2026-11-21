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

{ Draws a session on the terminal.  Reads session state, never changes it
  (apart from telling it how big the cell area is). }
unit view;
{$mode objfpc}{$H+}

interface

uses session;

type
  TView = class
  public
    Expand: Boolean;       { use the whole terminal instead of 80x25 }
    procedure Draw(S: TSession);
  end;

implementation

uses terminal, sheet, cellfmt, menutree, SysUtils;

const
  MinW = 80;
  MinH = 25;
  BorderW = 4;             { width of the row-number border }

function PadR(const s: string; n: Integer): string;
var
  u: UnicodeString;
begin
  u := UTF8Decode(s);
  if Length(u) >= n then
    Result := UTF8Encode(Copy(u, 1, n))
  else
    Result := s + StringOfChar(' ', n - Length(u));
end;

procedure DrawRow(S: TSession; r, y, rc, gridW: Integer);
var
  buf, t: UnicodeString;
  c, c2, x, w, k, av, hx, hw: Integer;
  cell: TCell;
  sel: TRange;
  pre: Char;
  txt: string;

  procedure PutBuf(pos: Integer; const txt: UnicodeString);
  var
    j: Integer;
  begin
    for j := 1 to Length(txt) do
      if (pos + j - 1 >= 1) and (pos + j - 1 <= gridW) then
        buf[pos + j - 1] := txt[j];
  end;

begin
  SetLength(buf, gridW);
  for k := 1 to gridW do buf[k] := ' ';
  hx := 0;
  hw := 0;
  x := 1;
  sel := S.Selection;
  for c := S.LeftCol to rc do
  begin
    w := S.Sheet.ColWidth(c);
    if (r >= sel.R1) and (r <= sel.R2) and (c >= sel.C1) and (c <= sel.C2) then
    begin
      if hx = 0 then hx := x;
      hw := x + w - hx;
    end;
    cell := S.Sheet.Find(r, c);
    if (cell <> nil) and (cell.Raw <> '') then
    begin
      if TextOf(cell, pre, txt) then
      begin
        t := UTF8Decode(txt);
        case pre of
          '''':
            begin
              av := w;
              c2 := c + 1;
              while (c2 <= rc) and (S.Sheet.Find(r, c2) = nil) do
              begin
                Inc(av, S.Sheet.ColWidth(c2));
                Inc(c2);
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
        t := UTF8Decode(ValueText(cell, S.Sheet, w));
        if Length(t) > w then
        begin
          SetLength(t, w);
          for k := 1 to w do t[k] := '*';
        end;
        PutBuf(x + w - Length(t), t);
      end;
    end;
    Inc(x, w);
  end;
  TermPut(BorderW + 1, y, taNormal, UTF8Encode(buf));
  if hw > 0 then
    TermPut(BorderW + hx, y, taHi, UTF8Encode(Copy(buf, hx, hw)));
end;

procedure DrawMenu(S: TSession);
var
  d, i, x: Integer;
  nd, kid: TMenuNode;
  a: TAttr;
begin
  d := S.MenuDepth;
  nd := S.MenuNodes[d];
  x := 1;
  for i := 0 to nd.Count - 1 do
  begin
    if x + Length(nd[i].Name) > MinW + 1 then break;
    if i = S.MenuIdx[d] then a := taHi else a := taNormal;
    TermPut(x, 2, a, nd[i].Name);
    Inc(x, Length(nd[i].Name) + 2);
  end;
  kid := nd[S.MenuIdx[d]];
  TermPut(1, 3, taNormal, PadR(kid.PanelText, MinW));
end;

procedure TView.Draw(S: TSession);
var
  w, h, gridW, gridRows, rc, r, c, x, cx, i: Integer;
  st, mname, es: string;
  cell: TCell;
  sel: TRange;
begin
  w := TermWidth;
  h := TermHeight;
  TermClear;
  TermHideCursor;
  if (w < MinW) or (h < MinH) then
  begin
    TermPut(1, 1, taNormal, Format('Terminal too small (%dx%d): mkspread needs at least 80x25.', [w, h]));
    TermRefresh;
    exit;
  end;
  if not Expand then
  begin
    w := MinW;
    h := MinH;
  end;
  gridW := w - BorderW;
  gridRows := h - 5;
  S.GridW := gridW;
  S.GridRows := gridRows;
  S.Normalize;
  rc := S.RightColOf(S.LeftCol);

  { line 1: cell status and mode indicator }
  st := ColLetter(S.CurCol) + IntToStr(S.CurRow) + ':';
  cell := S.Sheet.Find(S.CurRow, S.CurCol);
  if (cell <> nil) and not cell.Fmt.UseGlobal then st := st + ' (' + FormatTag(cell.Fmt) + ')';
  if S.Sheet.ColWidthIsSet(S.CurCol) then st := st + ' [W' + IntToStr(S.Sheet.ColWidth(S.CurCol)) + ']';
  if cell <> nil then st := st + ' ' + cell.Raw;
  case S.Mode of
    mReady: mname := 'READY';
    mLabel: mname := 'LABEL';
    mValue: mname := 'VALUE';
    mEdit:  mname := 'EDIT';
    mMenu:  mname := 'MENU';
    mGoto:  mname := 'POINT';
    mPrompt: mname := 'EDIT';
    mPoint: mname := 'POINT';
  end;
  TermPut(1, 1, taNormal, PadR(st, w - Length(mname) - 1));
  TermPut(w - Length(mname) + 1, 1, taHi, mname);

  { lines 2-3: control panel }
  cx := 0;
  case S.Mode of
    mMenu: DrawMenu(S);
    mLabel, mValue:
      begin
        es := S.Entry;
        if (S.Mode = mLabel) and ((es = '') or not (es[1] in LabelPrefixes)) then
          es := '''' + es;
        if Length(UTF8Decode(es)) > w - 1 then
          es := UTF8Encode(Copy(UTF8Decode(es), Length(UTF8Decode(es)) - w + 2, w));
        TermPut(1, 2, taNormal, es);
        cx := Length(UTF8Decode(es)) + 1;
      end;
    mEdit:
      begin
        TermPut(1, 2, taNormal, PadR(S.Entry, w - 1));
        cx := S.EditPos + 1;
      end;
    mGoto:
      begin
        es := 'Enter address to go to: ' + S.Entry;
        TermPut(1, 2, taNormal, es);
        cx := Length(es) + 1;
      end;
    mPrompt:
      begin
        es := S.PromptText + ' ' + S.Entry;
        TermPut(1, 2, taNormal, es);
        cx := Length(es) + 1;
      end;
    mPoint:
      begin
        if S.Typing then
          es := S.PointText + ' ' + S.Entry
        else
        begin
          sel := S.Selection;
          es := S.PointText + ' ' + ColLetter(sel.C1) + IntToStr(sel.R1);
          if (sel.R1 <> sel.R2) or (sel.C1 <> sel.C2) then
            es := es + '..' + ColLetter(sel.C2) + IntToStr(sel.R2);
        end;
        TermPut(1, 2, taNormal, es);
        if S.Typing then cx := Length(es) + 1;
      end;
  end;

  { line 4: column letters }
  TermPut(1, 4, taHi, StringOfChar(' ', w));
  x := BorderW + 1;
  for c := S.LeftCol to rc do
  begin
    i := S.Sheet.ColWidth(c);
    TermPut(x + (i - Length(ColLetter(c))) div 2, 4, taHi, ColLetter(c));
    Inc(x, i);
  end;

  { rows }
  for r := S.TopRow to S.TopRow + gridRows - 1 do
  begin
    TermPut(1, 5 + r - S.TopRow, taHi, PadR(IntToStr(r), BorderW));
    DrawRow(S, r, 5 + r - S.TopRow, rc, gridW);
  end;

  { bottom line: clock, message, indicators }
  TermPut(1, h, taNormal, UpperCase(FormatDateTime('dd-mmm-yy hh:nn AM/PM', Now)));
  if S.Msg <> '' then TermPut(23, h, taMsg, PadR(S.Msg, 55));
  if S.Calc.NeedsCalc then TermPut(w - 20, h, taNormal, 'CALC');
  if S.Calc.Circular then TermPut(w - 26, h, taNormal, 'CIRC');
  if S.HasUndo then TermPut(w - 14, h, taNormal, 'UNDO');
  if S.EndMode then TermPut(w - 5, h, taNormal, 'END');

  if cx > 0 then
  begin
    if cx > w then cx := w;
    TermCursor(cx, 2);
  end;
  TermRefresh;
end;

end.
