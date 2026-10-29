{ G6.63 — справжній компілятор вузької host D12 операції в Linux ELF64.
  Він ніколи не вважає .lisp/текст машинним SENS. Додати — НЕ D5 dispatch:
  дві точні D12 фізичні константи, результат рахує сам x86-64 код. }
program sensd12elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12add,wsm.elfpublish,wsm.elfgeometry;
const
  ModeAdd:RawByteString='--'+#$D0#$B4#$D0#$BE#$D0#$B4#$D0#$B0#$D1#$82#$D0#$B8+
    '-D12';

function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12ELFError.Create('потрібен фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12ELFError.Create('неприпустима довжина D12 файлу');
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
  Bytes:=RawByteString(UTF8Encode(UnicodeString('ELF-D12-ГОТОВО байтів=')))+
    IntToStr(Geometry.FileBytes)+
    RawByteString(UTF8Encode(UnicodeString(' тип=')))+IntToStr(Geometry.Kind)+
    ' machine-add=1 stdout=T5M'+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Run;
var Image,LeftPhysical,RightPhysical:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>ModeAdd) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ED12ELFError.Create(
      'виклик: sensd12elf --додати-D12 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12ELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12ELFError.Create('потрібен x86-64');
  {$ENDIF}
  LeftPhysical:=ReadAtom(ParamStr(2));
  RightPhysical:=ReadAtom(ParamStr(3));
  Image:=BuildD12AddELF(LeftPhysical,RightPhysical);
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
  3) Де відхиляється D12→D24? 4) Чим codegen відрізняється від evaluator? }
