{ G6.130 — пакетний host CLI до ВЖЕ перевіреного WideIR → ELF64.
  Кожен .sens читається фізично, ідентичність/закони — тільки pinned SENS.
  Усі форми допускаються ДО першої публікації; I/O публікацій не є
  загальною транзакцією, тому вже опубліковані ELF не видаляються. }
program senswidepaketelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.irwidefront, wsm.elfpublish, wsm.elfgeometry;
type
  EWidePackageError = class(Exception);
  TPackageItem = record
    Target: String;
    Image: RawByteString;
  end;
  TPackageItems = array of TPackageItem;

function UA(const S: UnicodeString): RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Say(const Value: RawByteString; Failure: Boolean);
var H:THandleStream; B:RawByteString;
begin
  B:=Value+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

{ Path: запозичений host шлях лише до .sens. Результат: власні паковані
  байти T5M, не текстова проєкція і не W12→D12 перетворення. TFileStream
  існує лише під час читання, а Result — керований RawByteString.
  Питання: 1) Де перевіряються фізичні трити? 2) Чому .lisp заборонено?
  3) Хто звільняє потік? 4) Чи означає довжина файла домен? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EWidePackageError.Create('потрібен фізичний файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWidePackageError.Create('порожня або завелика фізична форма');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Result: масив власних ELF байтів та host-шляхів; усі виходи
  семантично й фізично перевірено, але нічого не записано. Повторно
  використовуємо pinned BuildVerifiedWideELF, не дублюючи закони.
  Питання: 1) Коли виділяється пам'ять Image? 2) Де перевіряється
  точна D5/D6 голова? 3) Чому два однакових basename — помилка?
  4) Чому preflight не гарантує транзакції при пізній I/O-відмові? }
function PreparePackage(const OutputDir:String):TPackageItems;
var I,J,N:Integer; Source,Name,Target:String; Physical:RawByteString;
begin
  if (not DirectoryExists(OutputDir)) or (Length(OutputDir)>4096) then
    raise EWidePackageError.Create('вихідний каталог має існувати');
  N:=ParamCount-2;
  SetLength(Result,N);
  for I:=0 to N-1 do begin
    Source:=ParamStr(I+3);
    Name:=ChangeFileExt(ExtractFileName(Source),'.elf');
    Target:=IncludeTrailingPathDelimiter(ExpandFileName(OutputDir))+Name;
    if (Name='.elf') or (Length(Target)>4096) then
      raise EWidePackageError.Create('недопустиме ім’я вихідного ELF');
    for J:=0 to I-1 do
      if Result[J].Target=Target then
        raise EWidePackageError.Create('дубльоване ім’я вихідного ELF');
    if FileExists(Target) or DirectoryExists(Target) then
      raise EWidePackageError.Create('вихідний ELF вже зайнято');
    Physical:=ReadPhysical(Source);
    Result[I].Target:=Target;
    Result[I].Image:=BuildVerifiedWideELF(Physical,'external/sens');
  end;
end;

{ Items — керовані власні ELF байти; публікатор запозичує байти та
  створює новий виконуваний файл 0700 через приватний temp+hard link.
  Ніяких записів до завершення PreparePackage; пізня I/O-відмова
  не видаляє вже опубліковані файли. Результат — число ELF у stdout.
  Питання: 1) Хто перевіряє геометрію ELF64? 2) Чому link не перезапише
  символьне посилання? 3) Як поводитися після відмови на другому файлі? }
procedure Run;
var Items:TPackageItems; I:Integer; G:TELFGeometry;
begin
  if (ParamCount<3) or (ParamCount>18) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-пакет')) then
    raise EWidePackageError.Create(
      'виклик: senswidepaketelf --скомпілювати-пакет каталог новий1.sens [новий2.sens ... до 16]');
  {$IFNDEF LINUX}
  raise EWidePackageError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWidePackageError.Create('потрібен x86-64');
  {$ENDIF}
  Items:=PreparePackage(ParamStr(2));
  for I:=0 to High(Items) do
    PublishNewELF64(Items[I].Target,Items[I].Image,3,G);
  Say(UA('ПАКЕТ-WIDEIR-ГОТОВО: машинних-ELF=')+IntToStr(Length(Items))+
      ' machine=pinned-exact-WideIR stdout=T5M energy=NOT-MEASURED',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say(UA('ПАКЕТ-WIDEIR-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
