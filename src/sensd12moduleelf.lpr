{ G6.88 — нативний ELF64 NEG для одного канонічного D12 атома.
  Фізичний D12 вхід, машинний CDQ/XOR/SUB, канонічний T5M D12/D24 stdout;
  математична зміна знака — похідна від pinned MUL(-1, x), не новий закон. }
program sensd12moduleelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12abs,wsm.elfpublish,wsm.elfgeometry;
const
  ModeAbs:RawByteString='--'+#$D0#$BC+#$D0#$BE+#$D0#$B4+#$D1#$83+#$D0#$BB+#$D1#$8C+'-D12';

function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12AbsELFError.Create('потрібен фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12AbsELFError.Create('неприпустима довжина D12 файлу');
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
  Bytes:=RawByteString(UTF8Encode(UnicodeString('ELF-D12-МОДУЛЬ-ГОТОВО байтів=')))+
    IntToStr(Geometry.FileBytes)+
    RawByteString(UTF8Encode(UnicodeString(' тип=')))+IntToStr(Geometry.Kind)+
    ' machine-abs=1 stdout=T5M'+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Run;
var Image,InputPhysical:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>ModeAbs) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ED12AbsELFError.Create(
      'виклик: sensd12moduleelf --модуль-D12 вхід.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12AbsELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12AbsELFError.Create('потрібен x86-64');
  {$ENDIF}
  InputPhysical:=ReadAtom(ParamStr(2));
  Image:=BuildD12AbsELF(InputPhysical);
  { Верифікатор і атомарний no-clobber publisher уже існують. }
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  { Увесь успішний статус також видаємо точними UTF-8 байтами;
    числові поля — host метадані ELF, не D12 проєкція. }
  WriteStatus(Geometry);
end;

{ Помилки: пряма UTF-8 публікація в позичений stderr handle,
  без системного AnsiString conversion у WriteLn. }
procedure WriteError(const Why:String);
var Bytes:RawByteString; Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(UnicodeString('ELF-D12-ВІДМОВА: ')))+
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

{ Image — власні managed ELF байти; PublishNewELF64 володіє
  приватним тимчасовим inode й не переписує наявний ELF.
  Зовнішній формат відповіді після справжнього запуску — тільки T5M,
  а не текст. 1) Хто перевіряє ET_DYN? 2) Чому немає D5 alias?
  3) Чому -2048 повертає D24? 4) Чим codegen відрізняється від evaluator? }
