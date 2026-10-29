{ G6.97 — явні машинні координати D6:110100/110110 як host режими.
  Людська проєкція УКР не є програмним входом; лише фізичні W12 .sens.
  Це вузький AOT backend, не загальний мовний dispatch чи REPL. }
program sensd6mezhyelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd6mezhy,wsm.elfpublish,wsm.elfgeometry;
type ECLI=class(Exception);

{ Позичений Path — host ім'я файлу, результат — власний packed T5M.
  Межі bytes лише захищають ресурси; exact D12 перевіряє backend.
  1) Чому .lisp відхилено? 2) Хто вирішує канонічність T5M?
  3) Коли звільняється TFileStream? }
function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ECLI.Create('потрібен фізичний двійковий .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ECLI.Create('неприпустима довжина фізичного D12');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Фізичний stdout створює ELF, не CLI. CLI пише тільки UTF-8 статус,
  і лише після no-clobber PublishNewELF64. Handle чужий, stream наш.
  1) Чому тут немає Pascal значення D1?
  2) Чому статус записується після публікації?
  3) Що буде з наявним output.elf? }
procedure PrintUTF8(const Message:UnicodeString;ErrorOutput:Boolean);
var Bytes:RawByteString; S:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ErrorOutput then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes))
  finally S.Free end;
end;

procedure Run;
var Mode,LeftPhysical,RightPhysical,Image:RawByteString; G:TELFGeometry;
begin
  if ParamCount<>4 then
    raise ECLI.Create('виклик: sensd6mezhyelf --D6-110100|--D6-110110 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ECLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  Mode:=RawByteString(ParamStr(1));
  if (Mode<>'--D6-110100') and (Mode<>'--D6-110110') then
    raise ECLI.Create('відхилено невідому точну D6 координату');
  if ExtractFileExt(ParamStr(4))<>'.elf' then
    raise ECLI.Create('вихід повинен мати .elf');
  LeftPhysical:=ReadAtom(ParamStr(2));
  RightPhysical:=ReadAtom(ParamStr(3));
  if Mode='--D6-110100' then
    Image:=BuildD6NotGreaterELF(LeftPhysical,RightPhysical)
  else
    Image:=BuildD6NotLessELF(LeftPhysical,RightPhysical);
  PublishNewELF64(ParamStr(4),Image,3,G);
  PrintUTF8('ЕЛФ-Д6-МЕЖІ-ГОТОВО machine=CMP/SETcc stdout=T5M-D1 байтів='+
    UnicodeString(IntToStr(G.FileBytes)),False);
end;

begin
  try Run
  except on E:Exception do begin
    PrintUTF8('ЕЛФ-Д6-МЕЖІ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
