{ G6.97 — CLI компілює єдину nested фізичну D5 арифметичну програму.
  Текстовий режим українською є лише host CLI, не semantic dispatch. }
program sensarithchainelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irarithchain,wsm.elfpublish,wsm.elfgeometry;
type EChainCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure OutputBytes(const B:RawByteString;IsErr:Boolean);
var S:THandleStream;H:THandle;
begin
  if IsErr then H:=TextRec(StdErr).Handle else H:=TextRec(Output).Handle;
  S:=THandleStream.Create(H);
  try if Length(B)>0 then S.WriteBuffer(B[1],Length(B));
  finally S.Free end;
end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise EChainCLIError.Create(UA('потрібен фізичний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>8192) then
      raise EChainCLIError.Create(UA('фізична програма поза межею'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Owned RawByteString — canonical physical та ELF; влада над ISA тільки
  через чинні перевірені emitters; no-clobber — PublishNewELF64.
  Чому не використовуємо .lisp як canonical? Чому stdout лише host метадані?
  Який момент публікації ELF є атомарним? }
procedure Run;
var Physical,Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--ланцюг-D5')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EChainCLIError.Create(UA(
      'виклик: sensarithchainelf --ланцюг-D5 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EChainCLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EChainCLIError.Create(UA('потрібен процесор x86-64'));
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRArithChainELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  OutputBytes('D5-ARITH-CHAIN-ELF64 bytes='+
    RawByteString(IntToStr(Geometry.FileBytes))+' stdout=T5M'+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    OutputBytes(UA('КОМПІЛЯТОР-Д5-ЛАНЦЮГ-ВІДМОВА: ')+
      RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
