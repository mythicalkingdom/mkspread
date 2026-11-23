{ F4 (ABS): cycle the cell reference at the cursor through absolute and relative
  forms:  A1 -> $A$1 -> A$1 -> $A1 -> A1.  A range (A1..B2) changes both corners
  together, by the state of its first corner. }
unit refedit;

{$mode objfpc}{$H+}

interface

{ s is the text, pos the cursor (0-based character index).  Returns False when
  there is no reference next to the cursor; otherwise s and pos are updated
  (pos moves to the end of the changed reference). }
function CycleAbsolute(var s: string; var pos: Integer): Boolean;

implementation

type
  TRef = record
    Start, Stop: Integer;            { 1-based, Stop is one past the end }
    ColAbs, RowAbs: Boolean;
    Col, Row: UnicodeString;         { the letters and the digits }
  end;

function IsLetter(c: WideChar): Boolean;
begin
  Result := ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z'));
end;

function IsDigit(c: WideChar): Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

{ finds all references outside of quoted strings }
procedure FindRefs(const w: UnicodeString; var refs: array of TRef; out n: Integer);
var
  i, j, nl, nd: Integer;
  quote: WideChar;
  r: TRef;
begin
  n := 0;
  i := 1;
  quote := #0;
  while i <= Length(w) do
  begin
    if quote <> #0 then
    begin
      if w[i] = quote then quote := #0;
      Inc(i);
      continue;
    end;
    if (w[i] = '"') or (w[i] = '''') then
    begin
      quote := w[i];
      Inc(i);
      continue;
    end;
    if (w[i] = '$') or IsLetter(w[i]) then
    begin
      if (i > 1) and (IsLetter(w[i - 1]) or IsDigit(w[i - 1]) or (w[i - 1] = '_') or (w[i - 1] = '@') or
          ((w[i - 1] = '.') and not ((i > 2) and (w[i - 2] = '.') and (i > 3) and (IsLetter(w[i - 3]) or IsDigit(w[i - 3]))))) then
      begin
        { part of a name, a number or a function: skip the whole word }
        while (i <= Length(w)) and (IsLetter(w[i]) or IsDigit(w[i]) or (w[i] = '_') or (w[i] = '$')) do Inc(i);
        continue;
      end;
      j := i;
      r.ColAbs := False;
      r.RowAbs := False;
      if w[j] = '$' then begin r.ColAbs := True; Inc(j); end;
      nl := 0;
      r.Col := '';
      while (j <= Length(w)) and IsLetter(w[j]) do begin r.Col := r.Col + UpCase(w[j]); Inc(j); Inc(nl); end;
      if (nl >= 1) and (nl <= 2) and (j <= Length(w)) and (w[j] = '$') then begin r.RowAbs := True; Inc(j); end;
      nd := 0;
      r.Row := '';
      while (nl >= 1) and (nl <= 2) and (j <= Length(w)) and IsDigit(w[j]) do begin r.Row := r.Row + w[j]; Inc(j); Inc(nd); end;
      if (nl >= 1) and (nl <= 2) and (nd >= 1) and
         not ((j <= Length(w)) and (IsLetter(w[j]) or (w[j] = '_') or (w[j] = '('))) and
         (n <= High(refs)) then
      begin
        r.Start := i;
        r.Stop := j;
        refs[n] := r;
        Inc(n);
        i := j;
        continue;
      end;
      while (i <= Length(w)) and (IsLetter(w[i]) or IsDigit(w[i]) or (w[i] = '_') or (w[i] = '$')) do Inc(i);
      continue;
    end;
    Inc(i);
  end;
end;

function RefText(const r: TRef; colAbs, rowAbs: Boolean): UnicodeString;
begin
  Result := '';
  if colAbs then Result := '$';
  Result := Result + r.Col;
  if rowAbs then Result := Result + '$';
  Result := Result + r.Row;
end;

function CycleAbsolute(var s: string; var pos: Integer): Boolean;
var
  w: UnicodeString;
  refs: array[0..199] of TRef;
  n, i, pick, partner, cp: Integer;
  ca, ra: Boolean;
  a, b: Integer;
  newA, newB: UnicodeString;

  function Joined(x, y: Integer): Boolean;     { x and y are the two ends of a range }
  begin
    Result := (refs[x].Stop + 1 <= refs[y].Start) and
              (Copy(w, refs[x].Stop, refs[y].Start - refs[x].Stop) = '..');
  end;

begin
  Result := False;
  w := UTF8Decode(s);
  FindRefs(w, refs, n);
  if n = 0 then exit;
  cp := pos + 1;                       { the cursor as a 1-based position before which text lies }
  pick := -1;
  for i := 0 to n - 1 do
    if (refs[i].Start < cp) and (cp <= refs[i].Stop) then begin pick := i; break; end;
  if pick < 0 then
    for i := 0 to n - 1 do
      if refs[i].Stop <= cp then pick := i;
  if pick < 0 then pick := 0;
  { the pair of a range }
  partner := -1;
  if (pick + 1 < n) and Joined(pick, pick + 1) then partner := pick + 1;
  if partner < 0 then
    if (pick > 0) and Joined(pick - 1, pick) then
    begin
      partner := pick;
      pick := pick - 1;
    end;
  { next form: A1 -> $A$1 -> A$1 -> $A1 -> A1 }
  ca := refs[pick].ColAbs;
  ra := refs[pick].RowAbs;
  if not ca and not ra then begin ca := True; ra := True; end
  else if ca and ra then begin ca := False; ra := True; end
  else if ra then begin ca := True; ra := False; end
  else begin ca := False; ra := False; end;
  newA := RefText(refs[pick], ca, ra);
  if partner >= 0 then
  begin
    newB := RefText(refs[partner], ca, ra);
    a := pick;
    b := partner;
    { replace the later reference first so the earlier positions stay valid }
    w := Copy(w, 1, refs[b].Start - 1) + newB + Copy(w, refs[b].Stop, MaxInt);
    w := Copy(w, 1, refs[a].Start - 1) + newA + Copy(w, refs[a].Stop, MaxInt);
    pos := refs[b].Start - 1 + Length(newB) - (refs[a].Stop - refs[a].Start - Length(newA));
  end
  else
  begin
    w := Copy(w, 1, refs[pick].Start - 1) + newA + Copy(w, refs[pick].Stop, MaxInt);
    pos := refs[pick].Start - 1 + Length(newA);
  end;
  s := UTF8Encode(w);
  Result := True;
end;

end.
