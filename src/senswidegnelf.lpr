{ G6.91 — один повний фізичний SENS вираз D5:10110(D12:-1,D12:x)
  → checked WideIR → real Linux x86-64 ELF PIE / NEG / packed T5M.
  Лише host CLI; .lisp не замінює canonical .sens. }
program senswidegnelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidenegmul,wsm.elfpublish,wsm.elfgeometry;
type EWGNCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure Say(const B:RawByteString;Err:Boolean);
var S:THandleStream; H:THandle; LF:AnsiChar;
begin
  LF:=#10;
  if Err then H:=THandleStream.Create(TextRec(StdErr).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  S:=H;
  try
    if Length(B)>0 then S.WriteBuffer(B[1],Length(B));
    S.WriteBuffer(LF,1);
  finally S.Free end;
end;
{ InputPath — host borrowed pathname; Result — FPC-managed packed
  canonical binary source bytes. UTF8 текст ніколи не змінює біти.
  1) Чому .lisp не еквівалент фізичному джерелу?
  2) Чому bound 65536 — host захист, а не ширина домену?
  3) Хто закриває FileStream на винятку?
  4) Чому source не трактує Unicode? }
function ReadPhysical(const InputPath:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (InputPath='') or (Length(InputPath)>4096) or
     (ExtractFileExt(InputPath)<>'.sens') then
    raise EWGNCLIError.Create('потрібен точний файл .sens');
  F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWGNCLIError.Create('неприпустима довжина фізичної програми');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Публікація лише після WideIR gate, pinned numeric admission і
  VerifySENSELF64; PublishNewELF64 атомарно O_EXCL/no-clobber.
  1) Чому немає часткового .elf після semantic rejection?
  2) Чому в SENS ширина відповіді може зрости до D24?
  3) Чому runtime NEG відбувається у ELF, а не у CLI?
  4) Що тут owned на момент повернення Run? }
procedure Run;
var Mode,Physical,Image:RawByteString; G:TELFGeometry; Target:String;
begin
  if ParamCount<>3 then
    raise EWGNCLIError.Create('виклик: senswidegnelf --скомпілювати-D5-знак програма.sens новий.elf');
  Mode:=RawByteString(ParamStr(1));
  if Mode<>UA('--скомпілювати-D5-знак') then
    raise EWGNCLIError.Create('невідомий explicit host режим');
  {$IFNDEF LINUX}
  raise EWGNCLIError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWGNCLIError.Create('потрібен x86-64');
  {$ENDIF}
  Target:=ParamStr(3);
  if ExtractFileExt(Target)<>'.elf' then
    raise EWGNCLIError.Create('ціль мусить бути новим .elf');
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideNegMulELF(Physical,'external/sens');
  PublishNewELF64(Target,Image,3,G);
  Say(UA('Д5-ПОМНОЖИТИ-МІНУС-ОДИН-ELF-ГОТОВО байтів=')+
      RawByteString(IntToStr(G.FileBytes))+' machine=NEG output=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('Д5-ПОМНОЖИТИ-МІНУС-ОДИН-ВІДМОВА: ')+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
