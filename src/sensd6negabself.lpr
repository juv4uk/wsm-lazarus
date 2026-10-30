{ G6.181 — explicit CLI for pinned T5M→D6 NEG→ABS ELF64 PIE.
  Ukrainian command is host mode only; exact D6 words verified in WideIR.
  No .lisp-to-code conversion, D7 dispatch or private SENS laws. }
program sensd6negabself;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird6negabs,wsm.elfpublish,wsm.elfgeometry;
type ENegAbsCLI=class(Exception);
const ModeBuild:RawByteString='--скомпілювати-D6-знак-модуль';
function UA(const Text:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Text)) end;

{ Text owned UTF8, stdout/err borrowed OS file handles.
  1) Чому український статус не має потрапляти в ELF?
  2) Чому mode не є SENS координатою?
  3) Хто звільняє тимчасовий THandleStream? }
procedure Say(const Text:UnicodeString;IsError:Boolean);
var Data:RawByteString;H:THandleStream;
begin
  Data:=UA(Text)+#10;
  if IsError then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(Data[1],Length(Data))
  finally H.Free end;
end;

{ Filename borrowed host path; result managed packed T5M bytes,
  не Unicode і не source .lisp. FileStream owned/released finally.
  1) Чому .sens повинен бути точним фізичним файлом?
  2) Чому квота перевіряється перед SetLength?
  3) Хто допустить D2 і exact D6 після читання? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ENegAbsCLI.Create('потрібна фізична канонічна форма .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ENegAbsCLI.Create('порожній або завеликий фізичний T5M');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Result — owned verified ET_DYN ELF, publisher creates a NEW inode.
  No-clobber on existing file or symlink; exit=2 leaves no partial ELF.
  1) Чому не можна записувати Result перед WideIR?
  2) Як перевірено не лише форму, а машинну геометрію?
  3) Де обчислення робить x86, а не Pascal? }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise ENegAbsCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ENegAbsCLI.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>ModeBuild) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ENegAbsCLI.Create(
      'виклик: sensd6negabself --скомпілювати-D6-знак-модуль програма.sens новий.elf');
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRNegAbsELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д6-ЗНАК-МОДУЛЬ-ГОТОВО байтів='+IntToStr(G.FileBytes)+
      ' machine=NEG_CDQ_XOR_SUB stdout=T5M-D12-D24',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say('Д6-ЗНАК-МОДУЛЬ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2
  end end;
end.
