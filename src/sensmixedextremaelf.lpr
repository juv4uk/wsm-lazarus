{ G6.105 — фізична D2/T5M програма з 1..4 вкладеними D6
  «найменше»/«найбільше» → компілятор → ELF64 PIE.
  Імена host CLI не визначають мовних законів, жодного D7 dispatch. }
program sensmixedextremaelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irmixedextrema,wsm.elfpublish,wsm.elfgeometry;
type ECLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — borrowed host filename, Result — owned canonical packed bytes.
  Чи може текст .lisp бути фізичним входом? Хто перевіряє T5M?
  Де звільняється файловий дескриптор? }
function ReadProgram(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ECLI.Create('вхід має бути фізичним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>512) then
      raise ECLI.Create('фізична програма порожня або завелика');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Bytes owned transient UTF8 status; host handles borrowed, managed
  stream wrapper released. Physical ELF stdout created only at run time.
  Чому статус не є фізичним T5M? Чому спершу no-clobber публікація?
  Хто володіє результатом Image? }
procedure Report(const S:UnicodeString;Err:Boolean);
var B:RawByteString;H:THandleStream;
begin
  B:=UA(S)+#10;
  if Err then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B))
  finally H.Free end;
end;

procedure Run;
var Input,Image:RawByteString; G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--скомпілювати-вкладені-D6')) then
    raise ECLI.Create('виклик: sensmixedextremaelf --скомпілювати-вкладені-D6 програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise ECLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECLI.Create('потрібен x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise ECLI.Create('потрібна нова ELF64 ціль');
  Input:=ReadProgram(ParamStr(2));
  Image:=BuildIRMixedExtremaELF(Input,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Report('Д6-ВКЛАДЕННЯ-ГОТОВО: machine=CMP/CMOV stdout=T5M-D12 bytes='+
    UnicodeString(IntToStr(G.FileBytes)),False);
end;
begin
  try Run
  except on E:Exception do begin
    Report('Д6-ВКЛАДЕННЯ-ВІДМОВА: '+UTF8Decode(E.Message),True);
    ExitCode:=2;
  end end;
end.
