{ G6.85 — host AOT публікація єдиного динамічного D1 kernel.
  CLI не приймає текстових імен SENS функцій, не обчислює D3,
  а тільки створює фізичний x86-64 ELF64 для pinned механізму.
  У runtime stdin — конкатенація ДВОХ окремих canonical W1 байтів. }
program sensd1potikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd1potik,wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-D1-потік';

procedure EmitUTF8(const Message:UnicodeString;ToError:Boolean);
var Data:RawByteString;OutputHandle:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then OutputHandle:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else OutputHandle:=THandleStream.Create(TextRec(Output).Handle);
  try OutputHandle.WriteBuffer(Data[1],Length(Data))
  finally OutputHandle.Free end;
end;

procedure Run;
var Data:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ED1StreamELFError.Create(
      'виклик: sensd1potikelf --зібрати-D1-потік новий.elf');
  {$IFNDEF LINUX}
  raise ED1StreamELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED1StreamELFError.Create('потрібен x86-64');
  {$ENDIF}
  Data:=BuildD1StreamKernelELF;
  PublishNewELF64(ParamStr(2),Data,3,G);
  EmitUTF8('Д1-ПОТІК-ГОТОВО ELF64 PIE байтів='+IntToStr(G.FileBytes)+
    ' machine=CMP/SETE/MOVZX stdout=T5M',False);
end;

begin
  try Run
  except on E:Exception do begin
    EmitUTF8(UnicodeString('Д1-ПОТІК-КОМПІЛЯЦІЯ-ВІДМОВА: ')+
      UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
{ Питання: 1) Яка різниця між CLI параметром і SENS функцією?
  2) Чому не можна додати до stdin .lisp замість двох W1 .sens?
  3) Що поверне ELF за помилки канонічності вхідного кадру?
  4) Хто володіє RawByteString ELF до атомарної публікації?
  5) Чому успішний image не є доказом загального reader? }
