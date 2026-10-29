{ G6.35 — атомарна публікація ТІЛЬКИ перевіреного native ELF64.
  Формат/геометрію незалежно підтверджує злитий wsm.elfgeometry;
  мовний pinned admission лишається у наявних D3 emitters. }
unit wsm.elfpublish;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.elfgeometry;
type EELFPublishError=class(Exception);
procedure PublishNewELF64(const Path:String;const Image:RawByteString;
  ExpectedKind:Word;out Geometry:TELFGeometry);
implementation
uses BaseUnix,Classes;

procedure PublishNewELF64(const Path:String;const Image:RawByteString;
  ExpectedKind:Word;out Geometry:TELFGeometry);
var
  Admitted:TELFGeometry;
  Temp,Directory:String;
  F:TFileStream;
begin
  { Усі фізичні байти й метадані — до будь-якого файла в цілі.
    Image borrowed: не переписуємо жодного байта. }
  FillChar(Geometry,SizeOf(Geometry),0);
  Temp:='';
  try
    if (ExpectedKind<>2) and (ExpectedKind<>3) then
      raise EELFPublishError.Create('Непідтриманий host тип ELF64');
    if Path='' then
      raise EELFPublishError.Create('Відсутнє ім’я вихідного ELF');
    VerifySENSELF64(Image,Admitted);
    if Admitted.Kind<>ExpectedKind then
      raise EELFPublishError.Create('Тип ELF не збігся з явним профілем CLI');
    if (Admitted.FileBytes<>Length(Image)) or
       (Admitted.MachineBytes<1) then
      raise EELFPublishError.Create('Неповний фізичний машинний образ');

    { O_EXCL у первинному CI НЕ захистив існуючий шлях; звідси
      перевірений шаблон уже злитого senself: тимчасовий файл
      створює GetTempFileName в ТІЙ САМІЙ теці; посилання
      fpLink(temp,target) є атомарним no-clobber і для симлінка. }
    Directory:=ExtractFilePath(ExpandFileName(Path));
    Temp:=GetTempFileName(Directory,'sen');
    F:=TFileStream.Create(Temp,fmCreate);
    try
      F.WriteBuffer(Image[1],Length(Image));
    finally F.Free end;
    if fpChmod(PChar(Temp),&700)<>0 then
      raise EELFPublishError.Create('Не встановлено права виконання ELF');
    if fpLink(PChar(Temp),PChar(Path))<>0 then
      raise EELFPublishError.Create('Не можна атомарно створити ELF без перезапису');
    { Власний tempfile вже не потрібен: після успіху fpLink
      фізичний inode має незалежне цільове ім'я. }
    if not DeleteFile(Temp) then begin
      { Файл цілі уже опубліковано. Не вдаємо, що операція
        не відбулася, якщо OS відхилила прибирання власного temp. }
      Temp:='';
      Geometry:=Admitted;
      Exit;
    end;
    Temp:='';
    Geometry:=Admitted;
  except
    on E:Exception do begin
      if Temp<>'' then DeleteFile(Temp);
      FillChar(Geometry,SizeOf(Geometry),0);
      if E is EELFPublishError then raise;
      raise EELFPublishError.Create('Відхилено створення ELF64: '+E.Message);
    end;
  end;
end;

{ Контракт: Path — host шлях, Image — borrowed immutable RawByteString;
  ExpectedKind=host ELF ET_EXEC(2)/ET_DYN(3), НЕ домен SENS;
  Geometry — out record, zero до успішного закриття. File descriptor
  TFileStream живе лише до повного запису у власний тимчасовий inode;
  після fpLink ціль не може замінити чужий файл чи dangling symlink.
  На успіх файл належить файловій системі, не malloc-heap.
  1) Чому VerifySENSELF64 виконується ДО файлової мутації?
  2) Чому fpLink є атомарним no-clobber для dangling symlink?
  3) Чому ET_EXEC/ET_DYN — host ABI, а не D1/D3 координати?
  4) Хто доводить SENS закон, а хто — фізичну геометрію ELF?
  5) Чому зміна проєкції укр не змінює байтів canonical .sens? }
end.
