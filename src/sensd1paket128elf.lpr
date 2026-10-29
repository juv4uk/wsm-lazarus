{ G6.90 — host CLI створення одного пакетного ELF64 для рівно
  128 фізичних D3:101 рівностей D1. НЕ текстовий SENS диспетчер.
  Рантайм ELF читає 256 окремих canonical T5M W1 байтів зі stdin;
  повертає 128 окремих W1 байтів, лише після повного admission. }
program sensd1paket128elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd1paket128,wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-пакет-D1';

procedure Send(const Message:UnicodeString;IsError:Boolean);
var Bytes:RawByteString;Handle:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if IsError then Handle:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Handle:=THandleStream.Create(TextRec(Output).Handle);
  try Handle.WriteBuffer(Bytes[1],Length(Bytes))
  finally Handle.Free end;
end;

procedure Build;
var Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise EBatchD1ELFError.Create(
      'виклик: sensd1paket128elf --зібрати-пакет-D1 новий.elf');
  {$IFNDEF LINUX}
  raise EBatchD1ELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EBatchD1ELFError.Create('потрібен процесор x86-64');
  {$ENDIF}
  Image:=BuildD1Batch128ELF;
  PublishNewELF64(ParamStr(2),Image,3,G);
  Send('Д1-ПАКЕТ-ГОТОВО машинні-пари=128 фізичні-W1=так '+
    'ELF64=PIE байтів='+IntToStr(G.FileBytes),False);
end;

begin
  try Build
  except on E:Exception do begin
    Send(UnicodeString('Д1-ПАКЕТ-КОМПІЛЯЦІЯ-ВІДМОВА: ')+
      UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
{ Питання: 1) Чому .sens програми не передаються як host аргументи
  builder-а? 2) Чому no-clobber потрібен і для виведеного ELF?
  3) Яка фізична форма stdout під час runtime?
  4) Хто звільняє Image і THandleStream?
  5) Чому цей CLI не свідчить про повний SENS compiler? }
