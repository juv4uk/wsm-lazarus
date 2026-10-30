{ G6.141 — три фізичні D12 атоми .sens → дві pinned Core1
  функції, source-backed inline → один справжній native ELF64 PIE.
  Український CLI — людський transport; не є мовною семантикою.
  1) Чому .lisp не приймається за фізичний T5M?
  2) Чому кожен аргумент — окреме W12?
  3) Хто публікує ELF no-clobber і гарантує geometry?
  4) Чому stderr не можна зливати з фізичним stdout native програми? }
program senscore1twocalls;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.lowercore1twocalls,wsm.elfpublish,wsm.elfgeometry;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ELowerCore1TwoCallsError.Create('аргумент має бути фізичним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ELowerCore1TwoCallsError.Create('D12 фізичні байти поза квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Say(const Line:RawByteString;Failure:Boolean);
var S:THandleStream;B:RawByteString;
begin
  B:=Line+#10;
  if Failure then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(B[1],Length(B));finally S.Free end;
end;
procedure Run;
var A,B,C,Image:RawByteString;G:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise ELowerCore1TwoCallsError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ELowerCore1TwoCallsError.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>5) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-два-виклики-ядра1')) or
     (ExtractFileExt(ParamStr(5))<>'.elf') then
    raise ELowerCore1TwoCallsError.Create(
      'виклик: senscore1twocalls --скомпілювати-два-виклики-ядра1 a.sens b.sens c.sens вихід.elf');
  A:=ReadPhysical(ParamStr(2));
  B:=ReadPhysical(ParamStr(3));
  C:=ReadPhysical(ParamStr(4));
  Image:=BuildPinnedCore1TwoCallsELF('.',A,B,C);
  PublishNewELF64(ParamStr(5),Image,3,G);
  Say(UA('ЯДРО1-ДВА-ВИКЛИКИ-ГОТОВО байтів=')+
    IntToStr(G.FileBytes)+' stdout=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('ЯДРО1-ДВА-ВИКЛИКИ-ВІДМОВА: ')+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
