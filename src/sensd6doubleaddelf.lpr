{ G6.90 — CLI тільки для однієї двійкової вкладеної D6 форми.
  Усі українські літерали — host CLI поверхня, НЕ SENS dispatch. }
program sensd6doubleaddelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird6doubleadd,wsm.elfpublish,wsm.elfgeometry;
const MaxSourceBytes=256;
type EDoubleAddCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure OutputBytes(const Bytes:RawByteString;IsError:Boolean);
var Stream:THandleStream;Handle:THandle;
begin
  if IsError then Handle:=TextRec(StdErr).Handle
  else Handle:=TextRec(Output).Handle;
  Stream:=THandleStream.Create(Handle);
  try if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;
function ReadPhysical(const Path:String):RawByteString;
var FileStream:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EDoubleAddCLIError.Create(UA('потрібен фізичний .sens'));
  FileStream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (FileStream.Size<1) or (FileStream.Size>MaxSourceBytes) then
      raise EDoubleAddCLIError.Create(UA('неприпустима довжина програми'));
    SetLength(Result,SizeInt(FileStream.Size));
    FileStream.ReadBuffer(Result[1],Length(Result));
  finally FileStream.Free end;
end;
{ Borrowed host Path; RawByteString Physical та Image — managed owned;
  PublishNewELF64 перевіряє ELF, приватний no-clobber, не випускає
  частковий файл. D7 тут не призначає числової функції.
  Питання: чому .lisp не допущений як машинне джерело?
  Чому один ELF може містити два окремі машинні ADD?
  Хто володіє FD під час PublishNewELF64?
  Чому stdout повідомляє лише metadata, не machine-result? }
procedure Run;
var Physical,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--двічі-додати-1')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EDoubleAddCLIError.Create(UA(
      'виклик: sensd6doubleaddelf --двічі-додати-1 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EDoubleAddCLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EDoubleAddCLIError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRDoubleAddELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  OutputBytes('D6-001110x2-ELF64 bytes='+
    RawByteString(IntToStr(Geometry.FileBytes))+
    ' machine-ADD=2 stdout=T5M'+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    OutputBytes(UA('КОМПІЛЯТОР-Д6-ДВІЧІ-ВІДМОВА: ')+
      RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
