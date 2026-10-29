{ G6.142 — CLI спеціалізації справжнього фізичного тіла Core1 D5:10110
  без копіювання визначень у Pascal. Вхід — два .sens D12 атоми;
  вихід — executable ELF64 PIE із точним D12/D24 T5M stdout.
  Питання: чому не дозволено .lisp як фізичне джерело?
  Чому тільки дві позиції? Хто гарантує не-перезапис ELF?
  Де відокремлено host-діагностику від машинних байтів? }
program senscore1mulelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.lowerpinnedcore1mul,
     wsm.elfpublish,wsm.elfgeometry;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ELowerPinnedCore1MulError.Create(
      'вхідний атом повинен мати розширення .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ELowerPinnedCore1MulError.Create('фізична квота D12 перевищена');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Say(const Text:RawByteString;ToError:Boolean);
var B:RawByteString;F:THandleStream;
begin
  B:=Text+#10;
  if ToError then F:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else F:=THandleStream.Create(TextRec(Output).Handle);
  try F.WriteBuffer(B[1],Length(B));finally F.Free end;
end;

procedure Run;
var Left,Right,Image:RawByteString;G:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise ELowerPinnedCore1MulError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ELowerPinnedCore1MulError.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-ядро1-множення')) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ELowerPinnedCore1MulError.Create(
      'виклик: senscore1mulelf --скомпілювати-ядро1-множення ліва.sens права.sens вихід.elf');
  Left:=ReadPhysical(ParamStr(2));
  Right:=ReadPhysical(ParamStr(3));
  Image:=BuildPinnedCore1MulELF('.',Left,Right);
  PublishNewELF64(ParamStr(4),Image,3,G);
  Say(UA('ЯДРО1-МНОЖЕННЯ-ELF-ГОТОВО байтів=')+
       IntToStr(G.FileBytes)+' stdout=T5M',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say(UA('ЯДРО1-МНОЖЕННЯ-ELF-ВІДМОВА: ')+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
