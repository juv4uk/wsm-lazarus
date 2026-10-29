{ G6.86 — окремий host CLI лише для вже ратифікованої D5:01000.
  .sens — canonical packed D2 program, .lisp — тільки людська УКР.
  Немає локального реєстру семантики, читання за текстовими назвами,
  або перетворення D12 у host число як джерело закону. }
program senswidezeroelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidezero,wsm.elfpublish,wsm.elfgeometry;
const ModeCompile:RawByteString=#$2D+#$2D+#$D1+#$81+#$D0+#$BA+#$D0+#$BE+#$D0+#$BC+#$D0+#$BF+#$D1+#$96+#$D0+#$BB+#$D1+#$8E+#$D0+#$B2+#$D0+#$B0+#$D1+#$82+#$D0+#$B8+#$2D+#$44+#$35+#$2D+#$D0+#$BD+#$D1+#$83+#$D0+#$BB+#$D1+#$8C;
      PinnedRoot:RawByteString='external/sens';

function ReadProgram(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise EIRWideZeroError.Create('потрібна фізична канонічна програма .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideZeroError.Create('фізична програма перевищує межу');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ UnicodeString людського повідомлення -> UTF-8 managed byte stream.
  Handle лише позичаємо від процесу; THandleStream вивільняється.
  1) Чому stderr використовується для помилок?
  2) Коли ELF може публікуватися?
  3) Як no-clobber не допускає часткового виконуваного файла? }
procedure WriteUTF8(const Message:RawByteString;Failure:Boolean);
var H:THandleStream; LF:AnsiChar;
begin
  LF:=#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(Message)>0 then H.WriteBuffer(Message[1],Length(Message));
    H.WriteBuffer(LF,1);
  finally H.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>ModeCompile) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideZeroError.Create(
      'виклик: senswidezeroelf --скомпілювати-D5-нуль програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EIRWideZeroError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideZeroError.Create('потрібен x86-64');
  {$ENDIF}
  Physical:=ReadProgram(ParamStr(2));
  Image:=BuildIRWideZeroELF(Physical,PinnedRoot);
  PublishNewELF64(ParamStr(3),Image,3,G);
  WriteUTF8(RawByteString(UTF8Encode(UnicodeString(
    'ЕЛЬФ-Д5-НУЛЬ-ГОТОВО тип=')))+RawByteString(IntToStr(G.Kind))+
    ' machine=TEST_SETE_MOVZX output=D1',False);
end;
begin
  try Run
  except on E:Exception do begin
    WriteUTF8(RawByteString(UTF8Encode(UnicodeString(
      'ЕЛЬФ-Д5-НУЛЬ-ВІДМОВА: ')))+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
