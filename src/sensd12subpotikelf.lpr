{ G6.127 — компілює один canonical packed фізичний D5:01011 якір
  у багаторазовий native ELF64 PIE (2×signed D12 stdin, exact T5M).
  Path — borrowed, RawByteString — owned managed у час виклику;
  PublishNewELF64 гарантує atomic no-clobber і executable permissions.
  Цей CLI не обчислює віднімання та не читає .lisp як SENS закон.
  1) Чому вхід .sens, не .lisp? 2) Хто перевіряє pinned D5?
  3) Чому kernel створюємо один раз? 4) Чому no-clobber важливий? }
program sensd12subpotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12subpotik,wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-D5-віднімання-потік';
type ESubStreamCLI=class(Exception);

procedure ReportUTF8(const Message:UnicodeString;Failure:Boolean);
var Data:RawByteString;Stream:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  if Failure then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Data[1],Length(Data))
  finally Stream.Free end;
end;

function ReadAnchor(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise ESubStreamCLI.Create('потрібен canonical фізичний .sens якір');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>65536) then
      raise ESubStreamCLI.Create('фізична програма поза host квотою');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

procedure Run;
var PhysicalAnchor,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ESubStreamCLI.Create(
      'виклик: sensd12subpotikelf --зібрати-D5-віднімання-потік якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise ESubStreamCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ESubStreamCLI.Create('потрібен x86-64');
  {$ENDIF}
  PhysicalAnchor:=ReadAnchor(ParamStr(2));
  Image:=BuildVerifiedD12SubStreamELF(PhysicalAnchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  ReportUTF8('Д5-ВІДНІМАННЯ-ПОТІК-ELF-ГОТОВО байтів='+
    IntToStr(Geometry.FileBytes)+
    ' machine=SUB_EAX_R9D stdin=2xT5M-D12 stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    ReportUTF8('Д5-ВІДНІМАННЯ-ПОТІК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
