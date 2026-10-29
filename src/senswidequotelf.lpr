{ G6.139 — CLI тільки для ОДНІЄЇ canonical packed D2 .sens
  форми (D5:10111 D12 D12). Вхід — borrowed шлях до .sens;
  вихід — новий owned ELF64 PIE через уже перевірений publisher.
  Українська людська проєкція не є фізичним compiler input.
  1) Хто перевіряє закон D5? 2) Чому збережено розширення .sens?
  3) Хто володіє файлами та Image? 4) Чому нема часткового ELF? }
program senswidequotelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidequot,wsm.elfpublish,wsm.elfgeometry;
type EIRWideQuotCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function LoadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise EIRWideQuotCLI.Create('потрібна тільки packed .sens форма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideQuotCLI.Create('фізична програма завелика або порожня');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Message — owned UTF-8 host діагностика, НЕ дані SENS D7.
  Handle — borrowed OS fd, wrapper звільняється після запису.
  1) Чому статус не є stdout програми ELF?
  2) Чому на відмові статус надходить до stderr?
  3) Чи може запис зіпсувати канонічний .sens? Ні. }
procedure Send(const Message:RawByteString;Failure:Boolean);
var Stream:THandleStream;Bytes:RawByteString;
begin
  Bytes:=Message+#10;
  if Failure then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--скомпілювати-D5-частку-D12')) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideQuotCLI.Create(
      'виклик: senswidequotelf --скомпілювати-D5-частку-D12 програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EIRWideQuotCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideQuotCLI.Create('потрібен x86-64');
  {$ENDIF}
  Physical:=LoadPhysical(ParamStr(2));
  Image:=BuildIRWideQuotELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Send(UA('ЕЛФ-Д5-ЧАСТКА-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
    ' machine=CQO_IDIV stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    Send(UA('ЕЛФ-Д5-ЧАСТКА-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.