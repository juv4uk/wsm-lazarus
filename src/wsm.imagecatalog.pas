{ G7.8. Огляд відновленого приватного лексичного образу WSMIMG1.
  Не є програмою .sens, законом мови, знімком замикань або GC.
  Формат читає і перевіряє вже чинний wsm.image.LoadFrameImage.
  Тут лише перелічуємо фізичні координати вже допущеного образу,
  порівнюючи їх із реально відновленими значеннями й канонічним записом. }
unit wsm.imagecatalog;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, wsm.domain, wsm.image;

type
  EImageCatalogError = class(Exception);
  TImageCatalogEntry = record
    Key: TDomainKey;         { exact width + bits, НЕ семантичний код }
    OpaqueHandle: QWord;    { фізичне host-значення, НЕ SENS truth bit }
  end;
  TImageCatalog = array of TImageCatalogEntry;

procedure ReadImageCatalog(Input: TStream; out Entries: TImageCatalog);

implementation
uses wsm.envframe;

function ReadU16(const Data: array of Byte; At: SizeInt): Word;
begin
  Result := Word(Data[At]) or (Word(Data[At+1]) shl 8);
end;

function ReadU32(const Data: array of Byte; At: SizeInt): LongWord;
begin
  Result := LongWord(Data[At]) or (LongWord(Data[At+1]) shl 8) or
    (LongWord(Data[At+2]) shl 16) or (LongWord(Data[At+3]) shl 24);
end;

function ReadU64(const Data: array of Byte; At: SizeInt): QWord;
var I: Integer;
begin
  Result := 0;
  for I := 7 downto 0 do
    Result := (Result shl 8) or QWord(Data[At+I]);
end;

procedure ReadImageCatalog(Input: TStream; out Entries: TImageCatalog);
const
  HeaderBytes = 12;
  RecordBytes = 11;
  FooterBytes = 4;
var
  Data: array of Byte;
  Keys: array of TDomainKey;
  Temporary: TImageCatalog;
  Frame: IEnvFrame;
  Reencoded: TMemoryStream;
  Count, I, At, Size: SizeInt;
  Encoded: QWord;
begin
  SetLength(Entries, 0);
  if Input = nil then
    raise EImageCatalogError.Create('відсутній фізичний образ');
  { Єдиний авторитет приватного WSMIMG1 — already-merged loader:
    magic, count, checksum, порядок, точні координати, межі розміру. }
  Frame := LoadFrameImage(Input);
  Size := Input.Size;
  Input.Position := 0;
  SetLength(Data, Size);
  Input.ReadBuffer(Data[0], Size);
  Count := ReadU32(Data, 8);
  if (Count < 1) or (Count > MaxImageBindings) or
     (Size <> HeaderBytes + Count * RecordBytes + FooterBytes) then
    raise EImageCatalogError.Create('порушено довжину допущеного образу');
  SetLength(Temporary, Count);
  SetLength(Keys, Count);
  for I := 0 to Count-1 do begin
    At := HeaderBytes + I * RecordBytes;
    Keys[I].Width := Data[At];
    Keys[I].Bits := ReadU16(Data, At+1);
    { KeyBits не вирішує викличності. Це перевірка фізичної ширини. }
    if Length(KeyBits(Keys[I])) <> Keys[I].Width then
      raise EImageCatalogError.Create('втрачено точну двійкову координату');
    Encoded := ReadU64(Data, At+3);
    Temporary[I].Key := Keys[I];
    Temporary[I].OpaqueHandle := Frame.Resolve(Keys[I]);
    if Temporary[I].OpaqueHandle <> Encoded then
      raise EImageCatalogError.Create('розбіжність реально відновленого host-значення');
  end;
  { Не дублюємо writer: використаємо чинне SaveFrameImage, щоб
    підтвердити точну фізичну оборотність уже відновленого образу. }
  Reencoded := TMemoryStream.Create;
  try
    SaveFrameImage(Frame, Keys, Reencoded);
    if (Reencoded.Size <> Size) or
       (not CompareMem(Reencoded.Memory, @Data[0], Size)) then
      raise EImageCatalogError.Create('образ не має канонічного повторного запису');
  finally
    Reencoded.Free;
  end;
  Entries := Temporary; { результат лише після повного допуску }
end;

end.
