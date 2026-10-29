{ G6.120 — компілятор pinned D6 «остача» у перевикористовуваний ELF64.
  Borrowed physical .sens anchor і шлях; owned Image; PublishNewELF64
  зберігає лише атомарно. Runtime stdin: 2× canonical packed D12.
  Це host framing, не 2-атомний SENS source і не D7 dispatch.
  1) Чому весь якір перевіряється до runtime generator?
  2) Чому kernel не створює один .sens із кадру stdin?
  3) Чому дільник має бути позитивний?
  4) Чому видання ELF тільки через no-clobber publisher? }
program sensd12restpotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12restpotik,wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-D6-остача-потік';
type ERestStreamCLI=class(Exception);

procedure Report(const Message:UnicodeString;Failure:Boolean);
var Bytes:RawByteString;Handle:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if Failure then Handle:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Handle:=THandleStream.Create(TextRec(Output).Handle);
  try Handle.WriteBuffer(Bytes[1],Length(Bytes))
  finally Handle.Free end;
end;

function ReadAnchor(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise ERestStreamCLI.Create('потрібен цілий canonical .sens якір');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>65536) then
      raise ERestStreamCLI.Create('фізичний якір поза квотою');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

procedure Run;
var Anchor,Image:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ERestStreamCLI.Create(
      'виклик: sensd12restpotikelf --зібрати-D6-остача-потік якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise ERestStreamCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ERestStreamCLI.Create('потрібен x86-64');
  {$ENDIF}
  Anchor:=ReadAnchor(ParamStr(2));
  Image:=BuildVerifiedD12RestStreamELF(Anchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  Report('Д6-ОСТАЧА-ПОТІК-ELF-ГОТОВО байтів='+
    IntToStr(Geometry.FileBytes)+' machine=CDQ_IDIV_ECX'+
    ' stdin=2xT5M-D12 stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    Report('Д6-ОСТАЧА-ПОТІК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
