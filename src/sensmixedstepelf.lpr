{ G6.101 — FPC CLI для одного фізичного nested D6 .sens.
  Українська назва режиму — host API, не мовний dispatch SENS. }
program sensmixedstepelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irmixedstep,wsm.elfpublish,wsm.elfgeometry;
type EMixedCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure OutputBytes(const B:RawByteString;IsError:Boolean);
var Stream:THandleStream;Handle:THandle;
begin
  if IsError then Handle:=TextRec(StdErr).Handle
  else Handle:=TextRec(Output).Handle;
  Stream:=THandleStream.Create(Handle);
  try if Length(B)>0 then Stream.WriteBuffer(B[1],Length(B));
  finally Stream.Free end;
end;
{ Вихід — FPC managed packed canonical T5M, до 512 host bytes.
  Файл тільки .sens. Питання: чому не приймати .lisp як machine
  source? Хто закриває FD? Чому перевірено розмір ДО allocation? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EMixedCLIError.Create(UA('джерело повинно бути двійковим .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>512) then
      raise EMixedCLIError.Create(UA('неприпустимий розмір фізичної програми'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ PublishNewELF64 проводить незалежну геометрію та атомарний no-clobber.
  Image — own managed ELF bytes, Geometry — host metadata.
  Питання: де відбувається виконання machine арифметики?
  Чому stdout CLI не є результатом SENS програми?
  Чому збереження ніколи не має перезаписувати ELF? }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--змішані-D6')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EMixedCLIError.Create(UA(
      'виклик: sensmixedstepelf --змішані-D6 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EMixedCLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EMixedCLIError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRMixedStepELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  OutputBytes('D6-MIXED-ELF64 bytes='+RawByteString(IntToStr(G.FileBytes))+
    ' output=T5M'+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    OutputBytes(UA('КОМПІЛЯТОР-Д6-ЗМІШАНІ-ВІДМОВА: ')+
      RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
