{ SENS domain-coordinate mechanism. Semantic meaning remains in pinned SENS. }
unit wsm.domain;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  EDomainError = class(Exception);
  TDomainKey = record
    Width: Byte;
    Bits: Word;
  end;
  TDomainRow = record
    Key: TDomainKey;
    Ukrainian: RawByteString;
  end;
  TDomainTable = array of TDomainRow;
function ExactKey(const S: RawByteString): TDomainKey;
function SameKey(const A, B: TDomainKey): Boolean;
function KeyBits(const K: TDomainKey): RawByteString;
procedure LoadDomainTable(const Source: RawByteString; Width: Byte; out Rows: TDomainTable);
function UkrainianKey(const Rows: TDomainTable; const Name: RawByteString;
  out K: TDomainKey): Boolean;
implementation
function ExactKey(const S: RawByteString): TDomainKey;
var I: Integer; V: Word;
begin
  if (Length(S) < 1) or (Length(S) > 10) then
    raise EDomainError.Create('domain width must be 1..10');
  V := 0;
  for I := 1 to Length(S) do begin
    V := V shl 1;
    if S[I] = '1' then V := V or 1
    else if S[I] <> '0' then
      raise EDomainError.Create('nonbinary domain coordinate');
  end;
  Result.Width := Length(S); Result.Bits := V;
end;
function SameKey(const A, B: TDomainKey): Boolean;
begin Result := (A.Width = B.Width) and (A.Bits = B.Bits); end;
function KeyBits(const K: TDomainKey): RawByteString;
var I: Integer;
begin
  if (K.Width < 1) or (K.Width > 10) or
     (K.Bits >= (Word(1) shl K.Width)) then
    raise EDomainError.Create('invalid domain coordinate');
  SetLength(Result,K.Width);
  for I := 1 to K.Width do
    if (K.Bits and (Word(1) shl (K.Width-I))) <> 0 then Result[I] := '1'
    else Result[I] := '0';
end;
procedure LoadDomainTable(const Source: RawByteString; Width: Byte; out Rows: TDomainTable);
var P, E, KStart, KEnd, UStart, UEnd, N, I: SizeInt;
    Line, WordBits, Surface: RawByteString; K: TDomainKey;
begin
  if (Width < 1) or (Width > 10) then
    raise EDomainError.Create('invalid domain width');
  SetLength(Rows,0); P := 1;
  while P <= Length(Source) do begin
    E := P;
    while (E <= Length(Source)) and (Source[E] <> #10) do Inc(E);
    Line := Trim(Copy(Source,P,E-P)); P := E+1;
    if (Length(Line) < 3) or (Copy(Line,1,1) <> '(') then Continue;
    KStart := 2; KEnd := KStart;
    while (KEnd <= Length(Line)) and
      (Line[KEnd] in ['0','1']) do Inc(KEnd);
    if KEnd = KStart then Continue;
    if (KEnd > Length(Line)) or (Line[KEnd] <> ' ') then
      raise EDomainError.Create('malformed domain row coordinate');
    WordBits := Copy(Line,KStart,KEnd-KStart);
    K := ExactKey(WordBits);
    if K.Width <> Width then raise EDomainError.Create('wrong domain width');
    for I := 0 to High(Rows) do
      if SameKey(Rows[I].Key,K) then raise EDomainError.Create('duplicate domain key');
    UStart := Pos('(ук ',Line);
    if UStart = 0 then raise EDomainError.Create('missing Ukrainian surface');
    UStart := UStart + Length('(ук ');
    UEnd := UStart;
    while (UEnd <= Length(Line)) and (Line[UEnd] <> ')') do Inc(UEnd);
    if UEnd > Length(Line) then raise EDomainError.Create('unclosed Ukrainian surface');
    Surface := Copy(Line,UStart,UEnd-UStart);
    if Surface = '(' then Surface := ''; { explicit () means no surface }
    N := Length(Rows); SetLength(Rows,N+1);
    Rows[N].Key := K; Rows[N].Ukrainian := Surface;
  end;
  if Length(Rows) = 0 then raise EDomainError.Create('no domain rows');
end;
function UkrainianKey(const Rows: TDomainTable; const Name: RawByteString;
  out K: TDomainKey): Boolean;
var I: SizeInt;
begin
  Result := False;
  if Name = '' then Exit;
  for I := 0 to High(Rows) do
    if Rows[I].Ukrainian = Name then begin
      K := Rows[I].Key; Result := True; Exit;
    end;
end;
end.
