{ G6.83 — адміністративний FPC host CLI, не нове SENS ім'я функції.
  3 canonical packed D12 .sens -> 1 новий Linux ELF64.
  .lisp — тільки людська проєкція й не дозволений як фізичний operand.
  Питання: чому три окремі .sens файли? Хто володіє фізичними буферами?
  Де перевіряється атомарна відмова перезапису? }
program sensd12subadd_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12subadd,wsm.elfpublish,wsm.elfgeometry;
type EHostError=class(Exception);
const MaxAtomBytes=64;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — запозичений шлях ОС; Result — owned raw physical T5M bytes.
  Дескриптор і TFileStream закриваються завжди. }
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

{ UTF-8 host-діагностика — не канонічний SENS результат ELF. }
procedure WriteHost(const Handle:THandle;const S:RawByteString);
var Stream:THandleStream;
begin
  Stream:=THandleStream.Create(Handle);
  try if S<>'' then Stream.WriteBuffer(S[1],Length(S));
  finally Stream.Free end;
end;

procedure Run;
var A,B,C,Image:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>5) or
     (RawByteString(ParamStr(1))<>UA('--відняти-потім-додати-D12')) then
    raise EHostError.Create(UA(
      'виклик: sensd12subadd-elf --відняти-потім-додати-D12 a.sens b.sens c.sens новий.elf'));
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
  Image:=BuildD12SubAddELF(A,B,C);
  PublishNewELF64(ParamStr(5),Image,3,Geometry);
  WriteHost(TextRec(Output).Handle,
    UA('D12-SUBADD-ОДИН-ELF-ГОТОВО дії=SUB,ADD байтів=')+
    IntToStr(Geometry.FileBytes)+' stdout=T5M'+#10);
end;

begin
  try Run
  except on E:Exception do begin
    WriteHost(TextRec(ErrOutput).Handle,
      UA('D12-SUBADD-ОДИН-ELF-ВІДМОВА: ')+
      UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.
