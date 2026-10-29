{ G6.106 — вузький FPC CLI: два домени, один canonical .sens → ELF64.
  Українська назва команди — host API, не SENS семантичний dispatch. }
program sensd5d6composeelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird5d6compose,wsm.elfpublish,wsm.elfgeometry;
type EComposeCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure WriteBytes(const B:RawByteString;IsError:Boolean);
var S:THandleStream;H:THandle;
begin
  if IsError then H:=TextRec(StdErr).Handle else H:=TextRec(Output).Handle;
  S:=THandleStream.Create(H);
  try if Length(B)>0 then S.WriteBuffer(B[1],Length(B));
  finally S.Free end;
end;
{ Source — borrowed host file path; result owned raw bytes.
  Не приймаємо текстовий .lisp як фізичний canonical .sens.
  Питання: як обмежено allocation? хто закриває потік?
  Де відхилено відсутнє джерело чи інше розширення? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EComposeCLIError.Create(UA('потрібен двійковий файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>256) then
      raise EComposeCLIError.Create(UA('неприпустима довжина фізичної програми'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Image — managed ELF64, PublishNewELF64 публікує лише після повного
  pinned numeric+machine admission, приватно й без перезапису.
  Питання: чому stdout CLI містить metadata, не відповідь SENS?
  Чим відрізняється успіх збірки від виконання згенерованого ELF?
  Як перевірено, що два CPU обчислення не підмінені константою? }
procedure Run;
var Source,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--поєднати-D5-D6')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EComposeCLIError.Create(UA(
      'виклик: sensd5d6composeelf --поєднати-D5-D6 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EComposeCLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EComposeCLIError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildIRComposedD5D6ELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  WriteBytes('D5-D6-COMPOSE-ELF64 bytes='+
    RawByteString(IntToStr(Geometry.FileBytes))+' output=T5M'+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    WriteBytes(UA('КОМПІЛЯТОР-D5-D6-ВІДМОВА: ')+
      RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
