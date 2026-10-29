{ G6.141: фізична right-nested D5 .sens → справжній PIE ELF64.
  Лише pinned SENS і вже перевірені механізми; жодної .lisp семантики. }
program sensarithpravyelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irarithpravy,wsm.elfpublish,wsm.elfgeometry;
type EPravyCLI=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure Say(const B:RawByteString;Bad:Boolean);
var H:THandleStream;OutputData:RawByteString;
begin
  OutputData:=B+#10;
  if Bad then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(OutputData[1],Length(OutputData));finally H.Free end;
end;
{ Borrowed Path, owned canonical T5M Bytes; input FPC TFileStream
  звільняється тільки після повного ReadBuffer.
  Питання: чому .lisp відхиляється? Де pinned D5 admission?
  Чому довжина байтів не визначає numeric domain? }
function Physical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EPravyCLI.Create(UA('потрібно фізичний .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>8192) then
      raise EPravyCLI.Create(UA('фізична форма поза допустимою host-квотою'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Physical input and owned ELF. Публікація чинним PublishNewELF64
  no-clobber. Якщо файл зайнятий — жодних часткових виводів.
  Питання: чому ELF ABI не закон Dn? Де stdout T5M?
  Чому no-clobber захищає й dangling symlink?
  Чому всі міжкрокові D12 мають бути допущені до публікації? }
procedure Run;
var Input,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--правий-ланцюг-D5')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EPravyCLI.Create(UA(
      'виклик: sensarithpravyelf --правий-ланцюг-D5 програма.sens новий.elf'));
  {$IFNDEF LINUX}
  raise EPravyCLI.Create(UA('потрібен Linux'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EPravyCLI.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Input:=Physical(ParamStr(2));
  Image:=BuildIRArithPravyELF(Input,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('Д5-ПРАВИЙ-ЛАНЦЮГ-ГОТОВО: ELF64=')+
    IntToStr(G.FileBytes)+' stdout=canonical-T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('Д5-ПРАВИЙ-ЛАНЦЮГ-ВІДМОВА: ')+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
