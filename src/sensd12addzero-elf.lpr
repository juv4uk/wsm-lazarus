{ G6.85 — український host CLI фізичних D12 ADD→D1 «нуль?».
  Не читати .lisp і не використовувати назви як SENS dispatch.
  Питання: хто володіє фізичним T5M буфером?
  Чому файл .sens приймаємо лише після перевірки backend?
  Де виникає один машинний ELF64 PIE?
  Чому status stdout не містить семантичного результату? }
program sensd12addzero_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12addzero,wsm.elfpublish,wsm.elfgeometry;
type EHostError=class(Exception);
const MaxAtomBytes=64;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EHostError.Create(UA('допускається лише фізичний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxAtomBytes) then
      raise EHostError.Create(UA('неприпустимий розмір фізичного слова'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Буфер owned UTF8, OS handle borrowed; немає власності над stdout. }
procedure Emit(const FD:THandle;const Bytes:RawByteString);
var S:THandleStream;
begin
  S:=THandleStream.Create(FD);
  try
    if Bytes<>'' then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;

procedure Run;
var A,B,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>UA('--додати-нуль-D12')) then
    raise EHostError.Create(UA(
      'виклик: sensd12addzero-elf --додати-нуль-D12 ліве.sens праве.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EHostError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EHostError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  if ExtractFileExt(ParamStr(4))<>'.elf' then
    raise EHostError.Create(UA('потрібен новий вихідний файл .elf'));
  A:=ReadPhysical(ParamStr(2));
  B:=ReadPhysical(ParamStr(3));
  Image:=BuildD12AddZeroELF(A,B);
  PublishNewELF64(ParamStr(4),Image,3,Geometry);
  Emit(TextRec(Output).Handle,
    UA('D12-ОДИН-ELF-НУЛЬ-ГОТОВО machine=ADD_TEST_SETE_MOVZX тип=')+
    IntToStr(Geometry.Kind)+' stdout=T5M-D1'+#10);
end;
begin
  try Run except on E:Exception do begin
    Emit(TextRec(ErrOutput).Handle,
      UA('D12-ОДИН-ELF-НУЛЬ-ВІДМОВА: ')+
      UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.
