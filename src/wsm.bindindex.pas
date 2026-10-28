{ Deterministic byte-exact index for SENS Ukrainian domain surfaces.
  This is a mechanical optimization of wsm.bind, not semantic admission. }
unit wsm.bindindex;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain, wsm.bind;
type
  TBindSlot = record
    Name: RawByteString;
    Key: TDomainKey;
  end;
  TBindIndex = record
    Slots: array of TBindSlot;
    Count: SizeInt;
  end;
procedure BuildBindIndex(const Tables: TDomainSet; out Index: TBindIndex);
function IndexedUkrainian(const Index: TBindIndex;
  const Name: RawByteString): TDomainKey;
function IndexedUkrainianInDomain(const Index: TBindIndex;
  const Name: RawByteString; Domain: Byte): TDomainKey;
implementation
function HashBytes(const Name: RawByteString): LongWord;
var H: QWord; I: SizeInt;
begin
  { FNV-1a in a fixed 32-bit ring; UTF-8 bytes are not normalized. }
  H := 2166136261;
  for I := 1 to Length(Name) do
    H := ((H xor Ord(Name[I])) * QWord(16777619)) and QWord($FFFFFFFF);
  Result := LongWord(H);
end;
procedure BuildBindIndex(const Tables: TDomainSet; out Index: TBindIndex);
var D, I, Position, Capacity, Total: SizeInt;
    Name: RawByteString;
    Candidate: TBindIndex;
begin
  { "out" очищає попередній record, але сам по собі не захищає
    від часткового заповнення на ПІЗНІЙ помилці. Публікувати тільки
    після перевірки всіх D1–D10 та відхилення кожного дубля ук. }
  SetLength(Index.Slots, 0);
  Index.Count := 0;
  Candidate.Count := 0;
  Total := 0;
  for D := FirstDomain to LastDomain do begin
    if Length(Tables[D]) <> (SizeInt(1) shl D) then
      raise EBindError.Create('invalid pinned domain table size');
    for I := 0 to High(Tables[D]) do begin
      if (Tables[D][I].Key.Width <> D) or
         (Tables[D][I].Key.Bits <> I) then
        raise EBindError.Create('invalid pinned domain coordinate order');
      if Tables[D][I].Ukrainian <> '' then Inc(Total);
    end;
  end;
  if Total = 0 then raise EBindError.Create('no Ukrainian surfaces');
  Capacity := 8;
  while Capacity < Total * 2 do Capacity := Capacity shl 1;
  SetLength(Candidate.Slots, Capacity);
  for D := FirstDomain to LastDomain do
    for I := 0 to High(Tables[D]) do begin
      Name := Tables[D][I].Ukrainian;
      if Name = '' then Continue;
      Position := SizeInt(HashBytes(Name) and LongWord(Capacity - 1));
      while Candidate.Slots[Position].Name <> '' do begin
        if Candidate.Slots[Position].Name = Name then
          raise EBindError.Create('ambiguous Ukrainian surface across domains');
        Position := (Position + 1) and (Capacity - 1);
      end;
      Candidate.Slots[Position].Name := Name;
      Candidate.Slots[Position].Key := Tables[D][I].Key;
      Inc(Candidate.Count);
    end;
  { Керований dynamic array зберігає lifetime після виходу локальної
    змінної Candidate; далі Candidate не змінюємо. Ця єдина операція
    відкриває довірений exact-key snapshot викликачеві. }
  Index := Candidate;
end;
function FindIndex(const Index: TBindIndex;
  const Name: RawByteString): SizeInt;
var Position, Capacity, Seen: SizeInt;
begin
  Capacity := Length(Index.Slots);
  if Capacity = 0 then raise EBindError.Create('uninitialized binding index');
  if Name = '' then raise EBindError.Create('empty Ukrainian surface');
  Position := SizeInt(HashBytes(Name) and LongWord(Capacity - 1));
  for Seen := 0 to Capacity - 1 do begin
    if Index.Slots[Position].Name = Name then Exit(Position);
    if Index.Slots[Position].Name = '' then Break;
    Position := (Position + 1) and (Capacity - 1);
  end;
  raise EBindError.Create('unknown Ukrainian surface');
end;
function IndexedUkrainian(const Index: TBindIndex;
  const Name: RawByteString): TDomainKey;
begin
  Result := Index.Slots[FindIndex(Index, Name)].Key;
end;
function IndexedUkrainianInDomain(const Index: TBindIndex;
  const Name: RawByteString; Domain: Byte): TDomainKey;
begin
  if (Domain < FirstDomain) or (Domain > LastDomain) then
    raise EBindError.Create('unsupported domain width');
  Result := IndexedUkrainian(Index, Name);
  if Result.Width <> Domain then
    raise EBindError.Create('surface not defined in requested domain');
end;
end.
