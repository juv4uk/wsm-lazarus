{ G6.77: host CLI запускає лише вже допущений D12→D1 машинний backend.
  Назва "--нуль-D12" — людиночитаний ключ HOST, а НЕ SENS opcode.
  Відсутні власні таблиці мовних законів/семантичний ASCII dispatch. }
program sensd12zeroelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12zero,wsm.elfpublish,wsm.elfgeometry;
const ModeZero:RawByteString='--'+#$D0#$BD#$D1#$83#$D0#$BB#$D1#$8C+'-D12';

function ReadPhysical(const Path:String):RawByteString;
var S:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise ED12ZeroELFError.Create('Очікується фізичний вхід D12 .sens');
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<1) or (S.Size>64) then
      raise ED12ZeroELFError.Create('Фізичне джерело не в допущеній межі');
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

{ MessageText — owned UTF-8 bytes, handle позичений від OS stdout/stderr.
  Потік не має переводити кирилицю; publish тільки після повного допуску.
  1) Навіщо тут не WriteLn для кирилиці?
  2) Чому немає ASCII-канону для .sens?
  3) Коли stdout має бути порожній при негативі? }
procedure WriteBytes(const MessageText:RawByteString;IsError:Boolean);
var S:THandleStream;LF:AnsiChar;
begin
  LF:=#10;
  if IsError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(MessageText)>0 then S.WriteBuffer(MessageText[1],Length(MessageText));
    S.WriteBuffer(LF,1);
  finally S.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>ModeZero) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ED12ZeroELFError.Create(
      'Виклик: sensd12zeroelf --нуль-D12 вхід.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12ZeroELFError.Create('Потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12ZeroELFError.Create('Потрібен x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildD12ZeroELF(Physical);
  { Чинний захищений publisher, без перезапису існуючого ELF. }
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  WriteBytes(RawByteString(UTF8Encode(UnicodeString(
    'ЕЛЬФ-Д12-НУЛЬ-ГОТОВО тип=')))+RawByteString(IntToStr(Geometry.Kind))+
    ' machine=TEST_SETE_MOVZX output=D1',False);
end;

begin
  try Run
  except on E:Exception do begin
    WriteBytes(RawByteString(UTF8Encode(UnicodeString(
      'ЕЛЬФ-Д12-НУЛЬ-ВІДМОВА: ')))+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
