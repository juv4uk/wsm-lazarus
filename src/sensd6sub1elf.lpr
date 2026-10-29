{ G6.82 — фізичний D6:001111(D12) -> машинний ELF64 PIE.
  .lisp не є допустимим джерелом для цього вузького компілятора. }
program sensd6sub1elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird6sub1,wsm.elfpublish,wsm.elfgeometry;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise EIRD6Sub1Error.Create('очікується фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>128) then
      raise EIRD6Sub1Error.Create('фізична D6 форма поза межею 128 байтів');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Physical — owned bytes, Image — owned ELF bytes, PublishNewELF64
  володіє приватним no-clobber тимчасовим файлом.
  1) Чому суфікс .sens обов'язковий? 2) Чому .elf не перезаписуємо?
  3) Де перевірено CPU opcode? 4) Чим кодогенерація відрізняється від eval? }
procedure Run;
var Image,Physical:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or (ParamStr(1)<>'--скомпілювати-D6') or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRD6Sub1Error.Create(
      'виклик: sensd6sub1elf --скомпілювати-D6 вхід.sens новий.elf');
  {$IFNDEF LINUX}
  raise EIRD6Sub1Error.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRD6Sub1Error.Create('потрібен x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildD6Sub1ELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,Geometry);
  WriteLn('D6-ВІДНЯТИ-1-ГОТОВО ELF64=',Geometry.FileBytes,
          ' machine-SUB=так output=T5M');
end;
begin
  SetTextCodePage(Output,CP_UTF8);
  SetTextCodePage(StdErr,CP_UTF8);
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'D6-ВІДНЯТИ-1-ВІДМОВА: ',E.Message);
    ExitCode:=2
  end end;
end.
