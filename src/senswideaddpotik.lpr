{ G6.144: physical D5 source -> reusable native ELF64.
  TFileStream owns file descriptor; RawByteString owns source and image;
  PublishNewELF64 atomically creates output without replacing existing.
  1) Why only source .sens, not human .lisp?
  2) Why only Linux x86-64?
  3) Who checks physical D5 and D12 laws?
  4) Who checks stdin frame and output physical T5M? }
program senswideaddpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidedynadd,wsm.elfpublish,wsm.elfgeometry;
type EWideDynamicCLI=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure Say(const S:UnicodeString;Bad:Boolean);
var B:RawByteString;H:THandleStream;
begin
  B:=RawByteString(UTF8Encode(S))+#10;
  if Bad then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)) finally H.Free end;
end;
function ReadAnchor(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise EWideDynamicCLI.Create('потрібне фізичне джерело .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWideDynamicCLI.Create('порожній або надмірний фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Run;
var Source,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--зібрати-D5-додавання-потік')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EWideDynamicCLI.Create(
      'виклик: senswideaddpotik --зібрати-D5-додавання-потік якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise EWideDynamicCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideDynamicCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=ReadAnchor(ParamStr(2));
  Image:=BuildVerifiedDynamicD12AddELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д5-ДИНАМІЧНЕ-ДОДАВАННЯ-ELF-ГОТОВО bytes='+
      IntToStr(G.FileBytes)+' machine=ADD stdin=2xT5M-D12',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say('Д5-ДИНАМІЧНЕ-ДОДАВАННЯ-ВІДМОВА: '+
       UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
