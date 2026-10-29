{ G6.144 — CLI для одного canonical packed binary D2/T5M джерела.
  Не відкриває .lisp як binary; не виконує предикат у Pascal.
  Зберігає no-clobber та розділяє вихідний ELF і діагностику. }
program senswidemezhyelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidemezhy,wsm.elfpublish,wsm.elfgeometry;
type EMezhyCLI=class(Exception);

{ Path borrowed, owned physical .sens RawByteString Result.
  TFileStream звільняємо у finally; не беремо семантику з extension.
  1) Чому .lisp не canonical машинний input?
  2) Хто перевіряє D6 head і signed D12 atoms?
  3) Чому квота розміру не є law authority?
  4) Що робити, коли файл зникає посеред читання? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise EMezhyCLI.Create('потрібна канонічна двійкова .sens програма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EMezhyCLI.Create('фізичний D2 input порожній або поза квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Human status UTF-8 bytes are NOT D7 language data or T5M.
  Borrowed stdout/stderr handle, own THandleStream released in finally.
  1) Чому partial ELF ніколи не йде на stdout?
  2) Чому показуємо діагностику тільки у stderr?
  3) Як EncodeUTF8 відрізняється від фізичного D7? }
procedure PrintUTF8(const Text:UnicodeString;Fail:Boolean);
var Bytes:RawByteString;S:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Text))+#10;
  if Fail then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes)) finally S.Free end;
end;

procedure Run;
var Input,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>
       RawByteString(UTF8Encode(UnicodeString('--скомпілювати-D6-межі')))) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EMezhyCLI.Create(
      'виклик: senswidemezhyelf --скомпілювати-D6-межі програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EMezhyCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EMezhyCLI.Create('потрібен x86-64');
  {$ENDIF}
  Input:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideMezhyELF(Input,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  PrintUTF8('Д6-МЕЖІ-WIDEIR-ГОТОВО: байтів='+IntToStr(G.FileBytes)+
    ' machine=CMP/SETLE/SETGE stdout=T5M-D1',False);
end;

begin
  try Run
  except on E:Exception do begin
    PrintUTF8('Д6-МЕЖІ-WIDEIR-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
