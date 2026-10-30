{ G6.125 — повна фізична canonical .sens D5 програма →
  pinned WideIR → два machine IMUL + ADD у справжньому ELF64 PIE.
  Це host CLI; людське керування — не мовний D7 dispatch. }
program senstwomuladdelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irtwomuladd,wsm.elfpublish,wsm.elfgeometry;
type ETwoMulCLI=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — host path, не SENS слово. Owned packed raw bytes — Result.
  TFileStream звільняється обов'язково, на помилці вихідний ELF
  не створено. 1) Чому не читаємо .lisp як канонічний binary?
  2) Хто встановлює exact domain/width? 3) Де межа 65536? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ETwoMulCLI.Create('вхід має бути канонічною packed .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ETwoMulCLI.Create('фізичне джерело поза квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Позичений fd; THandleStream/RawByteString — owned на час виклику.
  Host stderr — не байти фізичного SENS stdout.
  1) Чому статус тільки після PublishNewELF64?
  2) Чому не використовуємо текстові SENS імена в compiler dispatch?
  3) Як захистити існуючий ELF від перезапису? }
procedure Say(const Message:RawByteString;Failure:Boolean);
var Stream:THandleStream;B:RawByteString;
begin
  B:=Message+#10;
  if Failure then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(B[1],Length(B));finally Stream.Free end;
end;

procedure Run;
var P,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--скомпілювати-два-множення')) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ETwoMulCLI.Create(
      'виклик: senstwomuladdelf --скомпілювати-два-множення форма.sens вихід.elf');
  {$IFNDEF LINUX}
  raise ETwoMulCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ETwoMulCLI.Create('потрібен x86-64');
  {$ENDIF}
  P:=ReadPhysical(ParamStr(2));
  Image:=BuildIRTwoMulAddELF(P,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('ДВА-ДОБУТКИ-ELF-ГОТОВО байтів=')+IntToStr(G.FileBytes)+
    ' machine=IMUL,IMUL,ADD stdout=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('ДВА-ДОБУТКИ-ELF-ВІДМОВА: ')+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
