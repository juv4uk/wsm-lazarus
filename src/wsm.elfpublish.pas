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
uses BaseUnix;

procedure PublishNewELF64(const Path:String;const Image:RawByteString;
  ExpectedKind:Word;out Geometry:TELFGeometry);
var
  Admitted:TELFGeometry;
  FD:CInt;
  Position,Written:SizeInt;
  Closed:Boolean;
begin
  { На помилку НЕ довіряємо жодній частині статистики.
    Image — borrowed reference-counted байти, без їх перетворення. }
  FillChar(Geometry,SizeOf(Geometry),0);
  try
    if (ExpectedKind<>2) and (ExpectedKind<>3) then
      raise EELFPublishError.Create('Непідтриманий host тип ELF64');
    if Path='' then
      raise EELFPublishError.Create('Відсутнє ім’я вихідного ELF');
    { УСІ формальні перевірки до будь-якої файлової мутації.
      Сегмент RX, e_entry, ET_EXEC/ET_DYN, ELF64, x86-64, повний
      p_filesz/memsz перевіряє незалежний read-only guard G6.33. }
    VerifySENSELF64(Image,Admitted);
    if Admitted.Kind<>ExpectedKind then
      raise EELFPublishError.Create('Тип ELF не збігся з явним профілем CLI');
    if (Admitted.FileBytes<>Length(Image)) or
       (Admitted.MachineBytes<1) then
      raise EELFPublishError.Create('Неповний фізичний машинний образ');

    { O_EXCL — атомарний no-clobber навіть для dangling symlink.
      Створюємо 0700 з урахуванням umask. Ніяких RenameFile
      та FileExists->створити, які допускають TOCTOU-перезапис. }
    FD:=fpOpen(PChar(Path),O_WRONLY or O_CREAT or O_EXCL,&700);
    if FD<0 then
      raise EELFPublishError.Create('Не можна створити ELF без перезапису');
    Closed:=False;
    try
      Position:=1;
      while Position<=Length(Image) do begin
        Written:=fpWrite(FD,Image[Position],Length(Image)-Position+1);
        if Written<=0 then
          raise EELFPublishError.Create('Неповний запис машинного ELF');
        Inc(Position,Written);
      end;
      if fpClose(FD)<>0 then begin
        Closed:=True;
        raise EELFPublishError.Create('Не вдалося закрити машинний ELF');
      end;
      Closed:=True;
    except
      if not Closed then fpClose(FD);
      fpUnlink(PChar(Path));
      raise;
    end;
    { Тільки повністю записаний ELF отримує опубліковану статистику. }
    Geometry:=Admitted;
  except
    on E:EELFPublishError do raise;
    on E:Exception do
      raise EELFPublishError.Create('Відхилено створення ELF64: '+E.Message);
  end;
end;

{ Контракт: Path — host шлях, Image — borrowed immutable RawByteString;
  ExpectedKind=host ELF ET_EXEC(2)/ET_DYN(3), НЕ домен SENS;
  Geometry — out record, zero до успішного закриття. File descriptor
  живе лише в цій процедурі; за помилки новий файл видаляється,
  а вже існуючий ніколи не змінюється. На успіх новий ELF належить
  файловій системі, не malloc-heap.
  1) Чому VerifySENSELF64 виконується ДО O_EXCL?
  2) Чому O_EXCL захищає навіть dangling symlink?
  3) Чому ET_EXEC/ET_DYN — host ABI, а не D1/D3 координати?
  4) Хто доводить SENS закон, а хто — фізичну геометрію ELF?
  5) Чому зміна проєкції укр не змінює байтів canonical .sens? }
end.
