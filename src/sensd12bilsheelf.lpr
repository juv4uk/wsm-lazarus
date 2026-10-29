{ G6.78 — фізичний SENS D12 signed більше? native CLI, український host режим. }
program sensd12bilsheelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12greater,wsm.elfpublish,wsm.elfgeometry;
const ModeGreater:RawByteString='--більше-D12';
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12GreaterELFError.Create('потрібен канонічний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12GreaterELFError.Create('неправильна довжина фізичного атома');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Paths borrowed host strings; physical words owned RawByteString copies.
  Binary emitter returns owned ELF bytes, publisher makes exclusive inode.
  Questions: Who admits numeric D12? Why .lisp rejected? Why no-clobber?
  Where does machine compute D1? }
procedure Run;
var A,B,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>ModeGreater) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ED12GreaterELFError.Create(
      'виклик: sensd12bilsheelf --більше-D12 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12GreaterELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12GreaterELFError.Create('потрібен x86-64');
  {$ENDIF}
  A:=ReadPhysical(ParamStr(2));
  B:=ReadPhysical(ParamStr(3));
  Image:=BuildD12GreaterELF(A,B);
  PublishNewELF64(ParamStr(4),Image,3,G);
  WriteLn('ELF-D12-БІЛЬШЕ-ГОТОВО machine=CMP/SETG/MOVZX stdout=D1-T5M байтів=',G.FileBytes);
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(ErrOutput,'ELF-D12-БІЛЬШЕ-ВІДМОВА: ',E.Message);
    ExitCode:=2;
  end end;
end.