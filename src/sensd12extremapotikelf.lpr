{ G6.114 — компілює лише host kernel з двома W12 stdin.
  Це host mode, ратифіковані D6 W6 голови — pinned SENS Contract 12.
  Один ELF багаторазово приймає два фізичні signed D12 W12. }
program sensd12extremapotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12extremapotik,wsm.elfpublish,wsm.elfgeometry;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure Emit(const S:UnicodeString;ToErr:Boolean);
var B:RawByteString;H:THandleStream;
begin
  B:=UA(S)+#10;
  if ToErr then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)) finally H.Free end;
end;
{ Host output filename borrowed; bytes managed and atomically published
  only after existing VerifySENSELF64. No input .lisp or numeric coercion.
  1) Чому mode не є D7 dispatch?
  2) Чому фізичні операнди надходять ПІСЛЯ компіляції?
  3) Чому PublishNewELF64 не повинен перезаписувати файл? }
procedure Run;
var M:RawByteString;K:TExtremaMachine;E:RawByteString;G:TELFGeometry;
begin
  if ParamCount<>2 then
    raise ED12ExtremaStream.Create('виклик: --D6-110101 або --D6-110111 новий.elf');
  M:=RawByteString(ParamStr(1));
  if M='--D6-110101' then K:=emMin
  else if M='--D6-110111' then K:=emMax
  else raise ED12ExtremaStream.Create('невідомий точний машинний профіль D6');
  if ExtractFileExt(ParamStr(2))<>'.elf' then
    raise ED12ExtremaStream.Create('вихід має бути новим .elf');
  {$IFNDEF LINUX}
  raise ED12ExtremaStream.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12ExtremaStream.Create('потрібен x86-64');
  {$ENDIF}
  E:=BuildD12ExtremaStreamELF(K);
  PublishNewELF64(ParamStr(2),E,3,G);
  Emit('Д6-ПОТІК-ELF64-ГОТОВО signed-CMOV=T5M bytes='+
    UnicodeString(IntToStr(G.FileBytes)),False);
end;
begin
  try Run except on X:Exception do begin
    Emit('Д6-ПОТІК-ВІДМОВА: '+UTF8Decode(X.Message),True);ExitCode:=2
  end end
end.
