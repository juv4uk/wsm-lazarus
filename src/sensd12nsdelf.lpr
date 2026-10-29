{ G6.101 — вузький фізичний D6:010101 НСД, CLI для двох .sens D12.
  Не приймає .lisp, не диспетчеризує за назвою, не оцінює НСД у FPC.
  Нативний ELF рахує результат сам; файл публікується атомарно без overwrite. }
program sensd12nsdelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12nsd,wsm.elfpublish,wsm.elfgeometry;
const
  ModeNsd:RawByteString='--'+#$D0#$BD+#$D1#$81+#$D0#$B4+'-D12';

function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12NsdELFError.Create('потрібен фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12NsdELFError.Create('неприпустима довжина D12 файлу');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Path: позичена host адреса, Result: owned physical T5M з exact W12.
  1) Чому відсікаємо .lisp? 2) Чому довжина байтів не визначає домен?
  3) Хто звільняє TFileStream? }
procedure WriteStatus(const Geometry:TELFGeometry);
var Bytes:RawByteString;Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(UnicodeString('ELF-D12-НСД-ГОТОВО байтів=')))+
    IntToStr(Geometry.FileBytes)+
    RawByteString(UTF8Encode(UnicodeString(' тип=')))+IntToStr(Geometry.Kind)+
    ' machine-euclid-div=1 stdout=T5M'+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Run;
var Image,LeftPhysical,RightPhysical:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>ModeNsd) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ED12NsdELFError.Create(
      'виклик: sensd12nsdelf --нсд-D12 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12NsdELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12NsdELFError.Create('потрібен x86-64');
  {$ENDIF}
  LeftPhysical:=ReadAtom(ParamStr(2));
  RightPhysical:=ReadAtom(ParamStr(3));
  Image:=BuildD12NsdELF(LeftPhysical,RightPhysical);
  { Верифікатор і атомарний no-clobber publisher уже існують. }
  PublishNewELF64(ParamStr(4),Image,3,Geometry);
  { Увесь успішний статус також видаємо точними UTF-8 байтами;
    числові поля — host метадані ELF, не D12 проєкція. }
  WriteStatus(Geometry);
end;

{ Помилки: пряма UTF-8 публікація в позичений stderr handle,
  без системного AnsiString conversion у WriteLn. }
procedure WriteError(const Why:String);
var Bytes:RawByteString; Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(UnicodeString('ELF-D12-НСД-ВІДМОВА: ')))+
    RawByteString(UTF8Encode(UnicodeString(Why)))+#10;
  Stream:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;
begin
  try Run
  except on E:Exception do begin
    WriteError(E.Message);
    ExitCode:=2;
  end end;
end.

{ InputPhysical — borrowed physical bytes, Image — owned managed ELF64.
  PublishNewELF64 володіє приватним inode та не переписує наявного файла.
  1) Де перевірка D12? 2) Чому текст не може підмінити фізичний .sens?
  3) Де Linux виконує DIV? 4) Хто відповідає за no-clobber?
  5) Чому успішний stdout — метадані, а результат обчислення — T5M з ELF? }
