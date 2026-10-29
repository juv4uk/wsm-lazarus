{ G6.80 — тільки host CLI одного AOT-композиційного профілю.
  Канонічні входи — ТРИ окремі фізичні .sens із явним D12 у backend.
  Український режим — адміністративний вибір, не SENS викличний код.
  Питання: чому filename не є D7 SENS словом?
  Чому вивід .elf не є пакованою .sens програмою?
  Де перевіряється no-clobber?
  Чому цей режим не породжує новий мовний закон? }
program sensd12addmul_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12addmul,wsm.elfpublish,wsm.elfgeometry;
type EHostError=class(Exception);
const MaxAtomBytes=64;

function UA(const Value:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Value)) end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise EHostError.Create(UA('потрібен точний двійковий .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxAtomBytes) then
      raise EHostError.Create(UA('розмір фізичного атома недопустимий'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Непустий RawByteString, owned by FPC; IO stream не володіє fd 1/2.
  1) Чому stdout не містить фізичного результату компілятора?
  2) Чому статус пишеться лише після успішної публікації?
  3) Хто звільняє вихідний буфер? }
procedure EmitText(const Handle:THandle;const Bytes:RawByteString);
var S:THandleStream;
begin
  S:=THandleStream.Create(Handle);
  try if Bytes<>'' then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;

procedure Run;
var A,B,C,Image:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>5) or
    (RawByteString(ParamStr(1))<>UA('--додати-потім-помножити-D12')) then
    raise EHostError.Create(UA(
      'виклик: sensd12addmul-elf --додати-потім-помножити-D12 a.sens b.sens c.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EHostError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EHostError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  if ExtractFileExt(ParamStr(5))<>'.elf' then
    raise EHostError.Create(UA('результат компіляції тільки новий .elf'));
  A:=ReadPhysical(ParamStr(2));
  B:=ReadPhysical(ParamStr(3));
  C:=ReadPhysical(ParamStr(4));
  Image:=BuildD12AddMulELF(A,B,C);
  PublishNewELF64(ParamStr(5),Image,3,Geometry);
  EmitText(TextRec(Output).Handle,
    UA('D12-ОДИН-ELF-ГОТОВО дії=ADD,IMUL байтів=')+
    IntToStr(Geometry.FileBytes)+' stdout=T5M'+#10);
end;
begin
  try Run except on E:Exception do begin
    EmitText(TextRec(ErrOutput).Handle,
      UA('D12-ОДИН-ELF-ВІДМОВА: ')+
      UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.
