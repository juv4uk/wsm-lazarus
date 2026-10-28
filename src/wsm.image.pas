{ G7.4: bounded, deterministic private lexical-binding snapshot.
  This is NOT a SENS program .sens, system image, semantic law, or closure/GC
  serializer. QWord is an opaque host storage handle, never a SENS truth bit.
  Version 1 wire: 8-byte "WSMIMG1\0", u32 count LE, ascending exact keys
  (u8 width, u16 bits LE, u64 opaque handle LE), u32 FNV1a checksum LE.
  FNV detects accidental corruption; it is NOT cryptographic authenticity. }
unit wsm.image;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.domain, wsm.envframe;
const
  MaxImageBindings = 4096;
type
  EImageError = class(Exception);
procedure SaveFrameImage(const Frame: IEnvFrame;
  const Keys: array of TDomainKey; Output: TStream);
function LoadFrameImage(Input: TStream): IEnvFrame;

implementation
const
  ImageMagic = 'WSMIMG1'#0;
  RecordBytes = 11;
  MaxImageBytes = 8 + 4 + MaxImageBindings * RecordBytes + 4;
type
  TImageEntry = record
    Key: TDomainKey;
    ValueHandle: QWord;
  end;
  TImageEntries = array of TImageEntry;

function KeyLess(const A, B: TDomainKey): Boolean;
begin
  if A.Width <> B.Width then Result := A.Width < B.Width
  else Result := A.Bits < B.Bits;
end;

procedure CheckKey(const Key: TDomainKey);
begin
  try
    if Length(KeyBits(Key)) <> Key.Width then
      raise EImageError.Create('invalid exact-domain coordinate');
  except
    on E: EDomainError do
      raise EImageError.Create('invalid exact-domain coordinate');
  end;
end;

procedure AddByte(S: TStream; B: Byte; var H: LongWord);
begin
  S.WriteBuffer(B, 1);
  H := LongWord(((QWord(H) xor QWord(B)) * QWord(16777619)) and
                QWord($FFFFFFFF));
end;

procedure AddU16(S: TStream; N: Word; var H: LongWord);
var I: Integer;
begin
  for I := 0 to 1 do AddByte(S, Byte((N shr (I * 8)) and $FF), H);
end;

procedure AddU32(S: TStream; N: LongWord; var H: LongWord);
var I: Integer;
begin
  for I := 0 to 3 do AddByte(S, Byte((N shr (I * 8)) and $FF), H);
end;

procedure AddU64(S: TStream; N: QWord; var H: LongWord);
var I: Integer;
begin
  for I := 0 to 7 do AddByte(S, Byte((N shr (I * 8)) and $FF), H);
end;

procedure PutChecksum(S: TStream; H: LongWord);
var I: Integer; B: Byte;
begin
  for I := 0 to 3 do begin
    B := Byte((H shr (I * 8)) and $FF);
    S.WriteBuffer(B, 1);
  end;
end;

function GetU16(const Data: array of Byte; At: SizeInt): Word;
begin
  Result := Word(Data[At]) or (Word(Data[At+1]) shl 8);
end;

function GetU32(const Data: array of Byte; At: SizeInt): LongWord;
var I: Integer;
begin
  Result := 0;
  for I := 3 downto 0 do Result := (Result shl 8) or Data[At+I];
end;

function GetU64(const Data: array of Byte; At: SizeInt): QWord;
var I: Integer;
begin
  Result := 0;
  for I := 7 downto 0 do Result := (Result shl 8) or QWord(Data[At+I]);
end;

function Checksum(const Data: array of Byte; Count: SizeInt): LongWord;
var I: SizeInt;
begin
  Result := 2166136261;
  for I := 0 to Count - 1 do
    Result := LongWord(((QWord(Result) xor QWord(Data[I])) *
                        QWord(16777619)) and QWord($FFFFFFFF));
end;

{ Bottom-up stable merge sort: не залежить від FPC рекурсивного стека,
  не створює недовірених Dn координат, не публікує частковий образ.
  Два керовані масиви — локальні; перед поверненням видимий лише Source. }
procedure SortImageEntries(var Entries:TImageEntries);
var
  Source, Target, Swap:TImageEntries;
  N, Width, Left, Middle, Right, I, J, K:SizeInt;
begin
  N:=Length(Entries);
  if N<2 then Exit;
  Source:=Entries;
  SetLength(Target,N);
  Width:=1;
  while Width<N do begin
    Left:=0;
    while Left<N do begin
      Middle:=Left+Width;
      if Middle>N then Middle:=N;
      Right:=Middle+Width;
      if Right>N then Right:=N;
      I:=Left; J:=Middle;
      for K:=Left to Right-1 do begin
        if (J>=Right) or
           ((I<Middle) and not KeyLess(Source[J].Key,Source[I].Key)) then
        begin
          Target[K]:=Source[I];
          Inc(I);
        end else begin
          Target[K]:=Source[J];
          Inc(J);
        end;
      end;
      Left:=Right;
    end;
    Swap:=Source; Source:=Target; Target:=Swap;
    Width:=Width*2;
  end;
  Entries:=Source;
end;

procedure SaveFrameImage(const Frame: IEnvFrame;
  const Keys: array of TDomainKey; Output: TStream);
var
  Entries: TImageEntries;
  Temp: TMemoryStream;
  I: SizeInt;
  Hash: LongWord;
begin
  if Frame = nil then raise EImageError.Create('missing lexical frame');
  if Output = nil then raise EImageError.Create('missing output stream');
  if (Length(Keys) = 0) or (Length(Keys) > MaxImageBindings) then
    raise EImageError.Create('image binding count outside 1..4096');
  if (Output.Size <> 0) or (Output.Position <> 0) then
    raise EImageError.Create('image output must be empty');
  SetLength(Entries, Length(Keys));
  for I := 0 to High(Entries) do begin
    CheckKey(Keys[I]);
    Entries[I].Key := Keys[I];
    if not Frame.TryResolve(Keys[I], Entries[I].ValueHandle) then
      raise EImageError.Create('image key is not bound in captured frame');
  end;
  { Відтворюваний фізичний порядок незалежний від порядку вибірки.
    Ітеративний merge sort має O(n log n) порівнянь і O(n) приватної
    пам'яті при наявному host-ліміті MaxImageBindings=4096.
    Тільки порівняння точних (width,bits), не SENS семантика. }
  SortImageEntries(Entries);
  for I := 1 to High(Entries) do
    if SameKey(Entries[I-1].Key, Entries[I].Key) then
      raise EImageError.Create('duplicate exact-domain image key');

  Temp := TMemoryStream.Create;
  try
    Hash := 2166136261;
    for I := 1 to Length(ImageMagic) do
      AddByte(Temp, Ord(ImageMagic[I]), Hash);
    AddU32(Temp, LongWord(Length(Entries)), Hash);
    for I := 0 to High(Entries) do begin
      AddByte(Temp, Entries[I].Key.Width, Hash);
      AddU16(Temp, Entries[I].Key.Bits, Hash);
      AddU64(Temp, Entries[I].ValueHandle, Hash);
    end;
    PutChecksum(Temp, Hash);
    if Temp.Size > MaxImageBytes then
      raise EImageError.Create('image exceeds physical size limit');
    Output.WriteBuffer(Temp.Memory^, Temp.Size);
  finally
    Temp.Free;
  end;
end;

function LoadFrameImage(Input: TStream): IEnvFrame;
var
  Data: array of Byte;
  Frame: IEnvFrame;
  Count, I, At: SizeInt;
  K, Previous: TDomainKey;
  ValueHandle: QWord;
begin
  if Input = nil then raise EImageError.Create('missing input stream');
  if Input.Position <> 0 then
    raise EImageError.Create('image input must begin at byte zero');
  if (Input.Size < 8 + 4 + RecordBytes + 4) or
     (Input.Size > MaxImageBytes) then
    raise EImageError.Create('image physical size invalid');
  SetLength(Data, Input.Size);
  Input.ReadBuffer(Data[0], Length(Data));
  for I := 1 to Length(ImageMagic) do
    if Data[I-1] <> Ord(ImageMagic[I]) then
      raise EImageError.Create('image magic/version mismatch');
  Count := GetU32(Data, 8);
  if (Count < 1) or (Count > MaxImageBindings) then
    raise EImageError.Create('image entry count invalid');
  if Length(Data) <> 8 + 4 + Count * RecordBytes + 4 then
    raise EImageError.Create('image length/count mismatch');
  if GetU32(Data, Length(Data)-4) <> Checksum(Data, Length(Data)-4) then
    raise EImageError.Create('image checksum mismatch');
  Frame := NewEnvFrame(nil);
  Previous.Width := 0;
  Previous.Bits := 0;
  At := 12;
  for I := 0 to Count - 1 do begin
    K.Width := Data[At];
    K.Bits := GetU16(Data, At+1);
    CheckKey(K);
    if (I > 0) and (not KeyLess(Previous, K)) then
      raise EImageError.Create('duplicate or unsorted image coordinates');
    ValueHandle := GetU64(Data, At+3);
    Frame.InstallLocal(K, ValueHandle);
    Previous := K;
    Inc(At, RecordBytes);
  end;
  Result := Frame;
end;
end.
