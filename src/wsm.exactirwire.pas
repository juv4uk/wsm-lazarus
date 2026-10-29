{ G6.5: приватний контейнер EIR1 для вже підтвердженого структурного
  ExactIR. Повторний допуск звіряє КОЖНЕ поле з фізичним .sens і pinned
  доменами через чинний BuildExactIR; байти EIR1 не є канонічною мовою.
  Немає callable verdict, семантики виконання, оптимізацій чи codegen. }
unit wsm.exactirwire;
{$mode objfpc}{$H+}
interface

uses SysUtils, wsm.bind, wsm.exactir;

type EExactIRWireError = class(Exception);

function EncodePinnedExactIR(const Physical: RawByteString;
  const Tables: TDomainSet): RawByteString;
procedure DecodePinnedExactIR(const Physical: RawByteString;
  const Tables: TDomainSet; const Encoded: RawByteString;
  out ProgramIR: TExactIR);

implementation

const
  HeaderBytes = 16;   { EIR1 + node count + root count + leaf count }
  NodeBytes = 46;     { фіксовані поля без нативного FPC record padding }
  WireMagic: RawByteString = 'EIR1';

procedure Reject(const Details: String);
begin
  raise EExactIRWireError.Create(Details);
end;

procedure PutByte(var Data: RawByteString; var At: SizeInt; Value: Byte);
begin
  if (At < 1) or (At > Length(Data)) then Reject('переповнено контейнер EIR1');
  Data[At] := AnsiChar(Value);
  Inc(At);
end;

procedure PutU32(var Data: RawByteString; var At: SizeInt; Value: LongWord);
var I: Integer;
begin
  for I := 0 to 3 do begin
    PutByte(Data, At, Byte(Value and $FF));
    Value := Value shr 8;
  end;
end;

procedure PutIndex(var Data: RawByteString; var At: SizeInt;
  Value: SizeInt; AllowParent: Boolean);
begin
  if AllowParent and (Value = -1) then begin
    PutU32(Data, At, High(LongWord));
    Exit;
  end;
  if (Value < 0) or (QWord(Value) >= QWord(High(LongWord))) then
    Reject('індекс EIR1 поза допустимим діапазоном');
  PutU32(Data, At, LongWord(Value));
end;

function TakeByte(const Data: RawByteString; var At: SizeInt): Byte;
begin
  if (At < 1) or (At > Length(Data)) then
    Reject('обрізано поле контейнера EIR1');
  Result := Ord(Data[At]);
  Inc(At);
end;

function TakeU32(const Data: RawByteString; var At: SizeInt): LongWord;
var I: Integer;
begin
  Result := 0;
  for I := 0 to 3 do
    Result := Result or (LongWord(TakeByte(Data, At)) shl (I*8));
end;

function TakeIndex(const Data: RawByteString; var At: SizeInt;
  AllowParent: Boolean): SizeInt;
var RawValue: LongWord;
begin
  RawValue := TakeU32(Data, At);
  if AllowParent and (RawValue = High(LongWord)) then Exit(-1);
  if RawValue >= High(LongWord) then
    Reject('неприпустимий sentinel індексу EIR1');
  Result := SizeInt(RawValue);
end;

function TakeFlag(const Data: RawByteString; var At: SizeInt): Boolean;
var Value: Byte;
begin
  Value := TakeByte(Data, At);
  if Value > 1 then Reject('небулевий фізичний прапорець EIR1');
  Result := Value = 1;
end;

function EncodePinnedExactIR(const Physical: RawByteString;
  const Tables: TDomainSet): RawByteString;
var
  IR: TExactIR;
  At, I, Total: SizeInt;
  N: TExactIRNode;
begin
  { У цьому API сторонній/підроблений TExactIR не можна записати: усі
    координати та зв'язки вперше будуються з фізичного канону. }
  BuildExactIR(Physical, Tables, IR);
  if (Length(IR.Nodes) < 1) or (Length(IR.Roots) < 1) or
     (Length(IR.Nodes) > MaxExactIRNodes) or
     (Length(IR.Roots) > MaxExactIRNodes) then
    Reject('неприпустима кількість вузлів або коренів EIR1');
  Total := HeaderBytes + Length(IR.Roots)*4 + Length(IR.Nodes)*NodeBytes;
  SetLength(Result, Total);
  At := 1;
  for I := 1 to Length(WireMagic) do PutByte(Result, At, Ord(WireMagic[I]));
  PutU32(Result, At, LongWord(Length(IR.Nodes)));
  PutU32(Result, At, LongWord(Length(IR.Roots)));
  PutU32(Result, At, LongWord(IR.BoundLeaves));
  for I := 0 to High(IR.Roots) do PutIndex(Result, At, IR.Roots[I], False);
  for I := 0 to High(IR.Nodes) do begin
    N := IR.Nodes[I];
    PutByte(Result, At, Ord(N.Kind));
    PutIndex(Result, At, N.RootIndex, False);
    PutIndex(Result, At, N.ParentIndex, True);
    PutIndex(Result, At, N.ChildIndex, False);
    PutIndex(Result, At, N.Depth, False);
    PutIndex(Result, At, N.WordIndex, False);
    PutIndex(Result, At, N.Physical.WordIndex, False);
    PutIndex(Result, At, N.Physical.TritStart, False);
    PutIndex(Result, At, N.Physical.TritEnd, False);
    PutIndex(Result, At, N.Physical.ByteStart, False);
    PutIndex(Result, At, N.Physical.ByteEnd, False);
    if N.Physical.IsEOF then PutByte(Result, At, 1)
    else PutByte(Result, At, 0);
    if N.HasKey then PutByte(Result, At, 1)
    else PutByte(Result, At, 0);
    PutByte(Result, At, N.Key.Width);
    PutByte(Result, At, Byte(N.Key.Bits and $FF));
    PutByte(Result, At, Byte(N.Key.Bits shr 8));
  end;
  if At <> Length(Result)+1 then Reject('неузгоджена довжина EIR1');
end;

procedure DecodePinnedExactIR(const Physical: RawByteString;
  const Tables: TDomainSet; const Encoded: RawByteString;
  out ProgramIR: TExactIR);
var
  Candidate, Expected: TExactIR;
  Count, RootCount, LeafCount, At, I: SizeInt;
  ExpectedBytes: Int64;
  N, Ref: TExactIRNode;
  KindByte: Byte;

  procedure EqualField(Condition: Boolean; Index: SizeInt);
  begin
    if not Condition then
      Reject('EIR1 не відповідає фізичному .sens: вузол №'+IntToStr(Index));
  end;

begin
  { fail-closed: до повної перевірки зовнішній результат порожній }
  SetLength(ProgramIR.Nodes, 0);
  SetLength(ProgramIR.Roots, 0);
  ProgramIR.BoundLeaves := 0;

  if (Length(Encoded) < HeaderBytes) or
     (Copy(Encoded, 1, 4) <> WireMagic) then
    Reject('невідомий або обрізаний заголовок EIR1');
  At := 5;
  Count := SizeInt(TakeU32(Encoded, At));
  RootCount := SizeInt(TakeU32(Encoded, At));
  LeafCount := SizeInt(TakeU32(Encoded, At));
  if (Count < 1) or (Count > MaxExactIRNodes) or
     (RootCount < 1) or (RootCount > Count) or
     (LeafCount < 0) or (LeafCount > Count) then
    Reject('неприпустимі кількості в заголовку EIR1');
  ExpectedBytes := Int64(HeaderBytes) + Int64(RootCount)*4 +
                   Int64(Count)*NodeBytes;
  if ExpectedBytes <> Length(Encoded) then
    Reject('довжина EIR1 не відповідає кількостям у заголовку');

  SetLength(Candidate.Nodes, Count);
  SetLength(Candidate.Roots, RootCount);
  Candidate.BoundLeaves := LeafCount;
  for I := 0 to RootCount-1 do begin
    Candidate.Roots[I] := TakeIndex(Encoded, At, False);
    if Candidate.Roots[I] >= Count then
      Reject('індекс кореня EIR1 поза масивом вузлів');
  end;
  for I := 0 to Count-1 do begin
    KindByte := TakeByte(Encoded, At);
    if KindByte > Ord(High(TExactIRKind)) then
      Reject('невідомий вид вузла EIR1');
    N := Default(TExactIRNode);
    N.Kind := TExactIRKind(KindByte);
    N.RootIndex := TakeIndex(Encoded, At, False);
    N.ParentIndex := TakeIndex(Encoded, At, True);
    N.ChildIndex := TakeIndex(Encoded, At, False);
    N.Depth := TakeIndex(Encoded, At, False);
    N.WordIndex := TakeIndex(Encoded, At, False);
    N.Physical.WordIndex := TakeIndex(Encoded, At, False);
    N.Physical.TritStart := TakeIndex(Encoded, At, False);
    N.Physical.TritEnd := TakeIndex(Encoded, At, False);
    N.Physical.ByteStart := TakeIndex(Encoded, At, False);
    N.Physical.ByteEnd := TakeIndex(Encoded, At, False);
    N.Physical.IsEOF := TakeFlag(Encoded, At);
    N.HasKey := TakeFlag(Encoded, At);
    N.Key.Width := TakeByte(Encoded, At);
    N.Key.Bits := Word(TakeByte(Encoded, At));
    N.Key.Bits := N.Key.Bits or (Word(TakeByte(Encoded, At)) shl 8);
    Candidate.Nodes[I] := N;
  end;
  if At <> Length(Encoded)+1 then Reject('надлишкові байти EIR1');

  { Звірка проти ТОГО САМОГО фізичного джерела та pinned binder.
    Кожне поле має збігтися, інакше backend ніколи не побачить IR. }
  BuildExactIR(Physical, Tables, Expected);
  if (Length(Expected.Nodes) <> Count) or
     (Length(Expected.Roots) <> RootCount) or
     (Expected.BoundLeaves <> LeafCount) then
    Reject('EIR1 не відповідає числу фізичних вузлів/коренів/слів');
  for I := 0 to RootCount-1 do
    if Candidate.Roots[I] <> Expected.Roots[I] then
      Reject('EIR1 підмінено індекс фізичного кореня');
  for I := 0 to Count-1 do begin
    N := Candidate.Nodes[I];
    Ref := Expected.Nodes[I];
    EqualField(N.Kind = Ref.Kind, I);
    EqualField(N.RootIndex = Ref.RootIndex, I);
    EqualField(N.ParentIndex = Ref.ParentIndex, I);
    EqualField(N.ChildIndex = Ref.ChildIndex, I);
    EqualField(N.Depth = Ref.Depth, I);
    EqualField(N.WordIndex = Ref.WordIndex, I);
    EqualField(N.Physical.WordIndex = Ref.Physical.WordIndex, I);
    EqualField(N.Physical.TritStart = Ref.Physical.TritStart, I);
    EqualField(N.Physical.TritEnd = Ref.Physical.TritEnd, I);
    EqualField(N.Physical.ByteStart = Ref.Physical.ByteStart, I);
    EqualField(N.Physical.ByteEnd = Ref.Physical.ByteEnd, I);
    EqualField(N.Physical.IsEOF = Ref.Physical.IsEOF, I);
    EqualField(N.HasKey = Ref.HasKey, I);
    EqualField((N.Key.Width = Ref.Key.Width) and
               (N.Key.Bits = Ref.Key.Bits), I);
    { G6.49: приватний EIR1 v1 має рівно 46 байтів на вузол —
      SubtreeEndExclusive там ІСТОРИЧНО не серіалізовано.
      Відновлюємо похідну 0-based піввідкриту межу ЛИШЕ з
      незалежного BuildExactIR того самого pinned T5M, ПІСЛЯ
      звірки всіх реально переданих полів. Нульове значення
      Default(TExactIRNode) не можна віддавати далі guard/lowering.
      Фізичний EIR1 не є мовним .sens і не створює законів SENS. }
    Candidate.Nodes[I].SubtreeEndExclusive := Ref.SubtreeEndExclusive;
  end;
  ProgramIR := Candidate;
end;

end.
