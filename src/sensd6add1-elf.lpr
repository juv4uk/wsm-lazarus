program sensd6add1_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd6add1,wsm.elfpublish,wsm.elfgeometry;
function UA(const S:UnicodeString):RawByteString; begin Result:=RawByteString(UTF8Encode(S)) end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then raise Exception.Create(UA('очікується канонічний фізичний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try if (F.Size<1) or (F.Size>4096) then raise Exception.Create('неприпустимий розмір .sens'); SetLength(Result,F.Size); F.ReadBuffer(Result[1],Length(Result)) finally F.Free end;
end;
procedure Run;
var Image,Physical:RawByteString; Geometry:TELFGeometry;
begin
  if ParamCount<>3 then
    raise Exception.Create(UA('Використання: sensd6add1-elf вхід.sens pinned-profile.lisp вихід.elf'));
  Physical:=ReadPhysical(ParamStr(1)); Image:=BuildD6Add1ELF(Physical,RawByteString(ParamStr(2)));
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  WriteLn(UA('ELF-D6-ДОДАТИ-1-ГОТОВО тип='),Geometry.Kind,UA(' байтів='),Geometry.FileBytes,UA(' машинний-ADD=так вихід=T5M'));
end;
begin
  SetTextCodePage(Output,CP_UTF8); SetTextCodePage(StdErr,CP_UTF8);
  try Run except on E:Exception do begin WriteLn(StdErr,UA('ELF-D6-ДОДАТИ-1-ПОМИЛКА: '),E.Message); ExitCode:=1 end end;
end.
