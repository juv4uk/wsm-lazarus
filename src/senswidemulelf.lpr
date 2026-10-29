{ G6.103 — одна канонічна packed програма .sens → verified WideIR
  → реально виконуваний D5 машинний IMUL ELF64 PIE.
  .lisp — лише людська укр проєкція, ніколи не заміна .sens. }
program senswidemulelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidemul,wsm.elfpublish,wsm.elfgeometry;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — borrowed filesystem шлях; Result — owned фізичні T5M байти.
  Межа host 65536 не є властивістю SENS. TFileStream завжди закрито.
  Питання: чому відхиляємо .lisp навіть якщо він містить дійсну форму?
  Чому байтова довжина не визначає домен? Хто володіє Result? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EIRWideMulError.Create('вхід має бути канонічним фізичним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideMulError.Create('неприпустима фізична довжина програми');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ UTF-8 повідомлення — host діагностика; stderr ізольований від
  фактичного фізичного T5M stdout, який видає створений ELF. }
procedure Say(const Message:RawByteString;Failure:Boolean);
var S:THandleStream;B:RawByteString;
begin
  B:=Message+#10;
  if Failure then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(B[1],Length(B));finally S.Free end;
end;

procedure Run;
var ProgramPhysical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-множення-Д5')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideMulError.Create(
      'виклик: senswidemulelf --скомпілювати-множення-Д5 програма.sens вихід.elf');
  {$IFNDEF LINUX}
  raise EIRWideMulError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideMulError.Create('потрібен x86-64');
  {$ENDIF}
  ProgramPhysical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideMulELF(ProgramPhysical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('Д5-МНОЖЕННЯ-ELF-ГОТОВО байтів=')+IntToStr(G.FileBytes)+
    ' machine=IMUL stdout=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('Д5-МНОЖЕННЯ-ELF-ВІДМОВА: ')+
      RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
