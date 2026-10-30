{ G6.162 — реальний runtime-input ELF для фізичного Core1 multiply.
  Inputs are borrowed canonical D12 T5M files. Output image is an owned
  RawByteString and is published only after ELF geometry validation using
  the shared atomic no-clobber writer. No evaluator or library body lives
  in this CLI; Core1 admission and WideIR lowering remain shared.
  1) Which physical source establishes the Core1 definition?
  2) Why is each anchor a separate canonical D12 atom?
  3) Where are runtime operands consumed after compilation?
  4) Why is output publication atomic and no-clobber?
  5) What does this profile NOT prove about all Core1 definitions? }
program senscore1mulpotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.lowerpinnedcore1mul,wsm.elfpublish,wsm.elfgeometry;
type ECore1MulCLI=class(Exception);
const BuildMode:RawByteString='--зібрати-ядро1-множення-потік';

procedure ReportUTF8(const Message:RawByteString;ToError:Boolean);
var Bytes:RawByteString;S:THandleStream;
begin
  Bytes:=Message+#10;
  if ToError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes)) finally S.Free end;
end;

function ReadPhysical(const Path:String):RawByteString;
var S:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ECore1MulCLI.Create('потрібен двійковий D12 .sens аргумент');
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<1) or (S.Size>64) then
      raise ECore1MulCLI.Create('фізичний D12 аргумент поза квотою');
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

procedure Run;
var Left,Right,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>BuildMode) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ECore1MulCLI.Create(
      'виклик: senscore1mulpotikelf --зібрати-ядро1-множення-потік лівий.sens правий.sens новий.elf');
  {$IFNDEF LINUX}
  raise ECore1MulCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore1MulCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  Left:=ReadPhysical(ParamStr(2));
  Right:=ReadPhysical(ParamStr(3));
  Image:=BuildPinnedCore1MulStreamELF('.',Left,Right);
  PublishNewELF64(ParamStr(4),Image,3,G);
  ReportUTF8(RawByteString(UTF8Encode(UnicodeString(
    'CORE1-D12-МНОЖЕННЯ-ПОТІК-ГОТОВО: ELF64 bytes=')))+
    RawByteString(IntToStr(G.FileBytes))+
    ' stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    ReportUTF8(RawByteString(UTF8Encode(UnicodeString(
      'CORE1-D12-МНОЖЕННЯ-ПОТІК-ВІДМОВА: ')))+
      RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
