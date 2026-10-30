{ G6.134 — canonical фізичний D5:10110 anchor -> повторний native IMUL ELF.
  Input: borrowed шлях .sens і pinned authority root, не текст SENS.
  Image/Anchor: owned managed RawByteString; потоки мають finally.
  Result: один новий executable ET_DYN, no-clobber через PublishNewELF64.
  1) Чому двійковий D2 якір перевіряємо до машинного коду?
  2) Чому змінні stdin D12 не є частиною .sens програми?
  3) Чому межа D12→D24 відхиляється, а не обрізається?
  4) Хто володіє файловими descriptor/ELF byte buffers?
  5) Чому код 2 відрізняється від успішного ELF? }
program sensd12mulpotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12mulpotik,wsm.elfpublish,wsm.elfgeometry;
type EMulStreamCLI=class(Exception);
const ModeBuild:RawByteString='--зібрати-D5-множення-потік';

procedure Say(const Message:UnicodeString;ToError:Boolean);
var Data:RawByteString;S:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Data[1],Length(Data))
  finally S.Free end;
end;

function ReadAnchor(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise EMulStreamCLI.Create('потрібен canonical фізичний .sens якір');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EMulStreamCLI.Create('фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Run;
var PhysicalAnchor,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EMulStreamCLI.Create(
      'виклик: sensd12mulpotikelf --зібрати-D5-множення-потік якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise EMulStreamCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EMulStreamCLI.Create('потрібен x86-64');
  {$ENDIF}
  PhysicalAnchor:=ReadAnchor(ParamStr(2));
  Image:=BuildVerifiedD12MulStreamELF(PhysicalAnchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д5-МНОЖЕННЯ-ПОТІК-ГОТОВО байтів='+IntToStr(G.FileBytes)+
    ' machine=IMUL_EAX_R9D stdin=2xT5M-D12 stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('Д5-МНОЖЕННЯ-ПОТІК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
