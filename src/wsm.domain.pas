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
function DomainRowByKey(const Rows: TDomainTable; const Key: TDomainKey;
  out Row: TDomainRow): Boolean;
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
{ Атомарне зчитування однієї закріпленої таблиці.
  Candidate не спостережуваний caller-ом до перевірки всіх рядків.
  Кількість комірок = 2^Width, обмеження місткості — host механізм,
  не нова доменна семантика SENS. }
{ Byte-exact hash короткої проєкції «ук» лише для одного читання.
  Обмежений modulo 2*2^Width, без overflow під FPC -Co.
  Hash — тільки прискорювач: тотожність назв завжди за рівними байтами,
  не за хешем, Unicode normalization чи мовною викличністю. }
function SurfaceBucket(const Name: RawByteString; Mask: SizeInt): SizeInt;
var I: SizeInt;
begin
  Result:=0;
  for I:=1 to Length(Name) do
    Result:=((Result*131)+Ord(Name[I])) and Mask;
end;

procedure LoadDomainTable(const Source: RawByteString; Width: Byte; out Rows: TDomainTable);
var
  P, E, KStart, KEnd, UStart, UEnd, Used, Limit, I, Slot, Mask: SizeInt;
  Line, WordBits, Surface: RawByteString;
  K: TDomainKey;
  Candidate: TDomainTable;
  SeenBits: array of Boolean;
  NameSlots: array of SizeInt; { 0=порожній, решта = candidate index+1 }
begin
  SetLength(Rows,0);
  if (Width < 1) or (Width > 10) then
    raise EDomainError.Create('invalid domain width');
  Limit:=SizeInt(1) shl Width;
  SetLength(Candidate,Limit);
  { Exact-key позиції можливі лише 0..2^Width-1.
    Таблиця проєкцій має половинне заповнення навіть для D10=1024. }
  SetLength(SeenBits,Limit);
  SetLength(NameSlots,Limit*2);
  Mask:=Length(NameSlots)-1;
  Used:=0;
  P:=1;
  while P<=Length(Source) do begin
    E:=P;
    while (E<=Length(Source)) and (Source[E]<>#10) do Inc(E);
    Line:=Trim(Copy(Source,P,E-P));
    P:=E+1;
    if (Length(Line)<3) or (Copy(Line,1,1)<>'(') then Continue;
    KStart:=2; KEnd:=KStart;
    while (KEnd<=Length(Line)) and
      (Line[KEnd] in ['0','1']) do Inc(KEnd);
    if KEnd=KStart then Continue;
    if (KEnd>Length(Line)) or (Line[KEnd]<>' ') then
      raise EDomainError.Create('malformed domain row coordinate');
    WordBits:=Copy(Line,KStart,KEnd-KStart);
    K:=ExactKey(WordBits);
    if K.Width<>Width then raise EDomainError.Create('wrong domain width');
    if Used>=Limit then
      raise EDomainError.Create('domain table contains too many rows');
    if SeenBits[K.Bits] then
      raise EDomainError.Create('duplicate domain key');
    UStart:=Pos('(ук ',Line);
    if UStart=0 then raise EDomainError.Create('missing Ukrainian surface');
    UStart:=UStart+Length('(ук ');
    if UStart>Length(Line) then
      raise EDomainError.Create('empty Ukrainian surface');
    { Зберегти точний pinned текст, включно з лапками. Дужка в
      quoted D7 даних (наприклад ")") не закриває колонку ук.
      Escape — лише лапка або зворотна коса риска, як у чинному
      wsm.proektsii. Це читання host-даних, НЕ SENS evaluator. }
    if Line[UStart]='"' then begin
      UEnd:=UStart+1;
      while UEnd<=Length(Line) do begin
        if Line[UEnd]='\' then begin
          Inc(UEnd);
          if (UEnd>Length(Line)) or
             not (Line[UEnd] in ['\','"']) then
            raise EDomainError.Create('invalid quoted Ukrainian escape');
        end else if Line[UEnd]='"' then Break;
        Inc(UEnd);
      end;
      if UEnd>Length(Line) then
        raise EDomainError.Create('unclosed quoted Ukrainian surface');
      Inc(UEnd); { після закривальної лапки — обов'язково ) колонки }
      if (UEnd>Length(Line)) or (Line[UEnd]<>')') then
        raise EDomainError.Create('unclosed quoted Ukrainian column');
    end else begin
      UEnd:=UStart;
      while (UEnd<=Length(Line)) and (Line[UEnd]<>')') do Inc(UEnd);
      if UEnd>Length(Line) then
        raise EDomainError.Create('unclosed Ukrainian surface');
    end;
    Surface:=Copy(Line,UStart,UEnd-UStart);
    if Surface='(' then Surface:=''; { explicit () = no surface }
    if Surface<>'' then begin
      Slot:=SurfaceBucket(Surface,Mask);
      { Лінійне пробування тільки при хеш-колізії; не переплутати
        два різні UTF-8 байтові рядки з однаковим bucket. }
      while NameSlots[Slot]<>0 do begin
        if Candidate[NameSlots[Slot]-1].Ukrainian=Surface then
          raise EDomainError.Create('ambiguous Ukrainian domain surface');
        Slot:=(Slot+1) and Mask;
      end;
    end;
    Candidate[Used].Key:=K;
    Candidate[Used].Ukrainian:=Surface;
    SeenBits[K.Bits]:=True;
    if Surface<>'' then NameSlots[Slot]:=Used+1;
    Inc(Used);
  end;
  if Used<>Limit then raise EDomainError.Create('incomplete domain table');
  for I:=0 to Used-1 do
    if Candidate[I].Key.Bits<>I then
      raise EDomainError.Create('missing or out-of-order domain coordinate');
  { Публікація лише після ВСЬОГО pinned вводу. Ephemeral індекси
    звільняє FPC; caller отримує лише схвалений TDomainTable. }
  Rows:=Candidate;
end;
function DomainRowByKey(const Rows: TDomainTable; const Key: TDomainKey;
  out Row: TDomainRow): Boolean;
var I, Address: SizeInt;
begin
  Result := False;
  { LoadDomainTable приймає тільки повні впорядковані D1–D10:
    позиція = біти, ширина — частина точного ключа. Для цієї
    перевіреної форми прямий доступ займає O(1), а не 1024
    порівняння для останнього слова D10. Це індекс HOST,
    НЕ числовий D12+ і НЕ семантичний dispatch за назвами. }
  if (Key.Width >= 1) and (Key.Width <= 10) then begin
    Address := Key.Bits;
    if Address < Length(Rows) then
      if SameKey(Rows[Address].Key, Key) then begin
        Row := Rows[Address];
        Exit(True);
      end;
  end;
  { Сумісність із зовнішнім переставленим або неповним масивом:
    не повертати чужу адресу з випадкового індексу. }
  for I := 0 to High(Rows) do
    if SameKey(Rows[I].Key,Key) then begin
      Row := Rows[I]; Result := True; Exit;
    end;
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
