{ G6.94 — вузький host CLI для пакета 32 D12 порівнянь.
  Не має текстового dispatch SENS чи локального мовного закону.
  Випускає один ELF64 PIE для runtime-пар signed W12. }
program sensd12bilshpaket32elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12bilshpaket32,
     wsm.elfpublish,wsm.elfgeometry;
const BuildMode:RawByteString='--зібрати-D12-більше-пакет';

procedure SendText(const Msg:UnicodeString;OnError:Boolean);
var Bytes:RawByteString;Sink:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Msg))+#10;
  if OnError then Sink:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Bytes[1],Length(Bytes))
  finally Sink.Free end;
end;

procedure Compile;
var PhysicalELF:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>BuildMode) or
     (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ED12GreaterBatchError.Create(
      'виклик: sensd12bilshpaket32elf --зібрати-D12-більше-пакет новий.elf');
  {$IFNDEF LINUX}
  raise ED12GreaterBatchError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12GreaterBatchError.Create('потрібен процесор x86-64');
  {$ENDIF}
  PhysicalELF:=BuildD12GreaterBatch32ELF;
  PublishNewELF64(ParamStr(2),PhysicalELF,3,G);
  SendText('Д12-БІЛЬШЕ-ПАКЕТ-ГОТОВО пар=32 machine=CMP/SETG '+
    'D1=T5M ELF64=PIE байтів='+IntToStr(G.FileBytes),False);
end;

begin
  try Compile
  except on E:Exception do begin
    SendText(UnicodeString('Д12-БІЛЬШЕ-ПАКЕТ-КОМПІЛЯЦІЯ-ВІДМОВА: ')+
      UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
{ Питання: 1) Чому CLI не приймає .lisp як executable source?
  2) Чому режим — host параметр, а не функція SENS?
  3) Коли звільняється PhysicalELF?
  4) Як PublishNewELF64 захищає існуючий файл?
  5) Чому один compiled profile не є універсальним compiler? }
