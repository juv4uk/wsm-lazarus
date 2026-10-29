{ G6.130 — CLI native ELF із БІБЛІОТЕЧНОГО pinned Core4, а не
  Pascal-копія Core4 LAMBDA. Лише Linux host I/O, atomic publish. }
program senscore4natyv;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.lowerpinnedcore4,wsm.elfpublish,wsm.elfgeometry;
type ECore4NativeCLIError=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Owned host stdout/stderr stream wrapper, immediate Free.
  Never writes physical D24 or ELF bytes to stdout. Status is UTF-8 only.
  Питання: чому stdout не SENS AST? Де закривається wrapper?
  Чому українська тут не мовний dispatch? }
procedure Status(const MessageText:UnicodeString;IsError:Boolean);
var St:THandleStream;B:RawByteString;
begin
  B:=UA(MessageText)+#10;
  if IsError then St:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else St:=THandleStream.Create(TextRec(Output).Handle);
  try St.WriteBuffer(B[1],Length(B))
  finally St.Free end;
end;

{ Borrowed physical path, returns owned canonical packed binary .sens.
  Only exact one-word D24 is admitted by the source-body compiler.
  Питання: чому не читаємо .lisp? Чому розмір — ресурсна межа?
  Чому не допускаємо частковий файл? }
function ReadArg(const Filename:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Filename)<>'.sens' then
    raise ECore4NativeCLIError.Create('потрібний фізичний двійковий .sens');
  F:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ECore4NativeCLIError.Create('порожній або завеликий D24');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Image owned ET_EXEC ELF64 bytes from actual pinned Core4 body.
  Publisher creates only a new .elf and never overwrites an inode/symlink.
  Exit code machine low8 is NOT the whole 24-bit SENS numeric result.
  Питання: де оригінальне фізичне тіло? Чому atomic no-clobber?
  Чому це тільки один D24 machine profile? }
procedure Run;
var Arg,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-core4-тіло')) then
    raise ECore4NativeCLIError.Create(
      'виклик: senscore4natyv --скомпілювати-core4-тіло аргумент.sens новий.elf');
  {$IFNDEF LINUX}
  raise ECore4NativeCLIError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore4NativeCLIError.Create('потрібен x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise ECore4NativeCLIError.Create('потрібна ціль .elf');
  Arg:=ReadArg(ParamStr(2));
  Image:=BuildPinnedCore4ELF('.',Arg);
  PublishNewELF64(ParamStr(3),Image,2,G);
  Status('CORE4-ТІЛО-ELF-ГОТОВО: pinned DEFINE/LAMBDA, D24, x86-64 ET_EXEC bytes='+
    IntToStr(G.FileBytes),False);
end;

begin
  try Run
  except on E:Exception do begin
    Status('CORE4-ТІЛО-ELF-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
