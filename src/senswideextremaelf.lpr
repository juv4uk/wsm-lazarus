{ G6.101 — фізична D2/T5M SENS програма -> native ELF64.
  Human CLI mode selects compiler service, not a language function.
  Only pinned D6:110101/110111 physical heads can compile. }
program senswideextremaelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideextrema,wsm.elfpublish,wsm.elfgeometry;
type EPhysicalCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path borrowed host path; result owned FPC managed packed bytes.
  1) Чому суфікс .sens обов'язковий? 2) Хто перевіряє T5M?
  3) Чому FileStream закривається у finally? }
function ReadProgram(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EPhysicalCLI.Create('вхід повинен бути фізичним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EPhysicalCLI.Create('розмір канонічної програми поза межею');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Borrowed OS output handles, locally owned THandleStream and
  UTF8 buffer. This human diagnostic is never a SENS physical value.
  Питання: 1) Чому програма ELF окремо друкує T5M?
  2) Де гарантується атомарна публікація? 3) Хто власник Handle? }
procedure Emit(const S:UnicodeString;Failure:Boolean);
var H:THandleStream;Bytes:RawByteString;
begin
  Bytes:=RawByteString(UTF8Encode(S))+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(Bytes[1],Length(Bytes))
  finally H.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--D6-фізичний-екстремум')) then
    raise EPhysicalCLI.Create(
      'виклик: senswideextremaelf --D6-фізичний-екстремум програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EPhysicalCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EPhysicalCLI.Create('потрібен x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise EPhysicalCLI.Create('вихід повинен бути новим .elf');
  Physical:=ReadProgram(ParamStr(2));
  Image:=BuildIRWideExtremaELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Emit('Д6-ЕКСТРЕМУМ-ГОТОВО machine=CMP/CMOV stdout=T5M-D12 розмір='+
    UnicodeString(IntToStr(G.FileBytes)),False);
end;

begin
  try Run
  except on E:Exception do begin
    Emit('Д6-ЕКСТРЕМУМ-ВІДМОВА: '+UTF8Decode(E.Message),True);
    ExitCode:=2;
  end end;
end.
