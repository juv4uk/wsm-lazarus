{ G6.88 — host AOT для ОДНОГО повторно використовуваного ELF64 PIE.
  Мовний закон D5 ADD — pinned SENS; CLI не має семантичного dispatch.
  Скомпільований kernel отримує дві фізичні D12 константи через stdin
  ПІСЛЯ компіляції, без перестворення ELF чи перекладу через D7. }
program sensd12potikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12potik,wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-D12-потік';

procedure EmitUTF8(const Message:UnicodeString;ToError:Boolean);
var Data:RawByteString; S:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Data[1],Length(Data))
  finally S.Free end;
end;

{ File destination — borrowed host path; Image — owned binary ELF64
  RawByteString. No-clobber atomicity and permissions use EXISTING
  PublishNewELF64; no new SENS opcode or Pascal numeric evaluator. }
procedure Run;
var Image:RawByteString; G:TELFGeometry;
begin
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ED12StreamELFError.Create(
      'виклик: sensd12potikelf --зібрати-D12-потік новий.elf');
  {$IFNDEF LINUX}
  raise ED12StreamELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12StreamELFError.Create('потрібен x86-64');
  {$ENDIF}
  Image:=BuildD12StreamAddELF;
  PublishNewELF64(ParamStr(2),Image,3,G);
  EmitUTF8('Д12-ПОТІК-ELF-ГОТОВО ELF64 PIE байтів='+IntToStr(G.FileBytes)+
    ' machine=ADD D12=T5M-stdin2 stdout=T5M',False);
end;

begin
  try Run
  except on E:Exception do begin
    EmitUTF8(UnicodeString('Д12-ПОТІК-КОМПІЛЯЦІЯ-ВІДМОВА: ')+
      UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
{ Питання: 1) Чому CLI компілює один ELF до отримання operands?
  2) Чому host frame stdin не є одним .sens документом?
  3) Чому не можна друкувати ASCII суму на stdout?
  4) Який захист існуючої .elf цілі? }