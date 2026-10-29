{ G6.146 — CLI лише для справжнього фізичного D5 бінарного дерева.
  Ні текстові D7 назви, ні .lisp не є канонічним джерелом. }
program sensarithderevoelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irarithderevo,wsm.elfpublish,wsm.elfgeometry;
type ETreeCLIError=class(Exception);
function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure PutBytes(const Bytes:RawByteString;IsError:Boolean);
var Stream:THandleStream;Handle:THandle;
begin
  if IsError then Handle:=TextRec(StdErr).Handle
  else Handle:=TextRec(Output).Handle;
  Stream:=THandleStream.Create(Handle);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ETreeCLIError.Create(Uk('потрібен канонічний фізичний .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>8192) then
      raise ETreeCLIError.Create(Uk('фізичний файл поза межею 8192'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Фізичний вхід — власний T5M; єдиний compiler authority — pinned SENS
  у BuildIRMixedTreeELF; PublishNewELF64 атомарно відмовляє від
  перезапису. У stdout — лише статус host CLI, не виконання SENS. }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>Uk('--змішане-дерево-D5')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ETreeCLIError.Create(Uk(
      'Виклик: sensarithderevoelf --змішане-дерево-D5 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise ETreeCLIError.Create(Uk('потрібен Linux'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ETreeCLIError.Create(Uk('потрібен x86-64'));
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRMixedTreeELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  PutBytes('ЗМІШАНЕ-D5-ELF64 bytes='+
    RawByteString(IntToStr(G.FileBytes))+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    PutBytes(Uk('ДЕРЕВО-D5-ВІДМОВА: ')+RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
