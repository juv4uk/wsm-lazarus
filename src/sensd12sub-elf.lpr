program sensd12sub_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12sub,wsm.elfpublish,wsm.elfgeometry;
const ModeSub:RawByteString='--'+#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D1#$96#$D0#$BC#$D0#$B0#$D1#$82#$D0#$B8+'-D12';
function UA(const S:UnicodeString):RawByteString; begin Result:=RawByteString(UTF8Encode(S)) end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create(UA('очікується канонічний фізичний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>4096) then raise Exception.Create('неприпустимий розмір фізичного файла');
    SetLength(Result,F.Size); F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Run;
var Image,L,R:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>ModeSub) then
    raise Exception.Create(UA('Використання: sensd12sub-elf --віднімати-D12 ліве.sens праве.sens вихід.elf'));
  L:=ReadPhysical(ParamStr(2)); R:=ReadPhysical(ParamStr(3));
  Image:=BuildD12SubELF(L,R); PublishNewELF64(ParamStr(4),Image,3,Geometry);
  WriteLn(UA('ELF-D12-ВІДНІМАННЯ-ГОТОВО тип='),Geometry.Kind,
    UA(' байтів='),Geometry.FileBytes,UA(' машинне-SUB=так вихід=T5M'));
end;
begin
  SetTextCodePage(Output,CP_UTF8); SetTextCodePage(StdErr,CP_UTF8);
  try Run except on E:Exception do begin
    WriteLn(StdErr,UA('ELF-D12-ВІДНІМАННЯ-ПОМИЛКА: '),E.Message); ExitCode:=1;
  end end;
end.
