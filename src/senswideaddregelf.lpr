{ G6.100 — компіляція ОДНІЄЇ повної packed фізичної D5 ADD програми.
  Текстова укр .lisp є лише проєкцією, не допускається як машинний
  source. Незмінні verified ELF публікуються atomically/no-clobber. }
program senswideaddregelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideaddreg,wsm.elfpublish,wsm.elfgeometry;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EIRWideAddRegError.Create('вхід має бути канонічним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideAddRegError.Create('погана фізична довжина .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Host TextRec handle borrowed, THandleStream created/freed locally.
  Output status — UTF-8 host diagnostics, never a SENS D7 source word.
  1) Чому ELF виходить лише через PublishNewELF64?
  2) Який exit статус відрізняє admitted від rejected?
  3) Чому stderr ніколи не є фізичним результатом ELF? }
procedure Say(const Message:RawByteString;IsError:Boolean);
var F:THandleStream;Line:RawByteString;
begin
  Line:=Message+#10;
  if IsError then F:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else F:=THandleStream.Create(TextRec(Output).Handle);
  try F.WriteBuffer(Line[1],Length(Line));
  finally F.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-додавання-Д5')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideAddRegError.Create(
      'виклик: senswideaddregelf --скомпілювати-додавання-Д5 програма.sens вихід.elf');
  {$IFNDEF LINUX}
  raise EIRWideAddRegError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideAddRegError.Create('потрібен процесор x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideAddRegisterELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  Say(UA('Д5-РЕЄСТРОВЕ-ДОДАВАННЯ-ELF-ГОТОВО: байтів=')+
       IntToStr(Geometry.FileBytes)+' machine=ADD-EAX-ECX stdout=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('Д5-РЕЄСТРОВЕ-ДОДАВАННЯ-ELF-ВІДМОВА: ')+
        RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
