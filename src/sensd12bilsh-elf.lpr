{ G6.78 — український host CLI до перевіреного D12 «більше?» ELF.
  Два окремі канонічні .sens атоми, не текстовий D5 dispatch.
  Runtime виконує машинні signed CMP/SETG, результат — D1 T5M.
  Чинний PublishNewELF64 гарантує no-clobber атомарний output. }
program sensd12bilsh_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12greater,wsm.elfpublish,wsm.elfgeometry;
const ModeGreater:RawByteString='--більше-D12';

function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12GreaterELFError.Create('вхід тільки у фізичному .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12GreaterELFError.Create('неприпустимий розмір фізичного атома');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure SendUTF8(const Value:UnicodeString;ErrorOutput:Boolean);
var Bytes:RawByteString;Sink:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Value))+#10;
  if ErrorOutput then Sink:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Bytes[1],Length(Bytes))
  finally Sink.Free end;
end;

procedure Run;
var Image,LeftPhysical,RightPhysical:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>ModeGreater) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ED12GreaterELFError.Create(
      'виклик: sensd12bilsh-elf --більше-D12 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12GreaterELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12GreaterELFError.Create('потрібен процесор x86-64');
  {$ENDIF}
  LeftPhysical:=ReadAtom(ParamStr(2));
  RightPhysical:=ReadAtom(ParamStr(3));
  Image:=BuildD12GreaterELF(LeftPhysical,RightPhysical);
  PublishNewELF64(ParamStr(4),Image,3,Geometry);
  SendUTF8(UnicodeString('ЕЛФ-Д12-БІЛЬШЕ-ГОТОВО machine=CMP/SETG ')+
    'T5M=D1 байтів='+IntToStr(Geometry.FileBytes),False);
end;

begin
  try Run
  except on E:Exception do begin
    SendUTF8(UnicodeString('ЕЛФ-Д12-БІЛЬШЕ-ВІДМОВА: ')+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
{ Питання: 1) Чому .lisp ніколи не передається в machine emitter?
  2) Який модуль володіє точним D12 admission?
  3) Чому статус stdout пишеться лише ПІСЛЯ атомарної публікації?
  4) Хто звільняє два власні managed RawByteString?
  5) Чому цей host-профіль не дорівнює повному D5 компілятору? }
