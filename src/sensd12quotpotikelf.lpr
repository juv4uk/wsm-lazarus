{ G6.161 — pinned D5 «частка» із двома D12 runtime параметрами.
  Канонічний якір — фізичний packed .sens; українська проєкція
  тільки для незалежного oracle, не для машинного dispatch. }
program sensd12quotpotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12quotpotik,wsm.elfpublish,wsm.elfgeometry;
type EQuotStreamCLI=class(Exception);
const ModeBuild:RawByteString='--зібрати-D5-частку-потік';

procedure Say(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;

{ Path — borrowed host path, Result — owned exact physical T5M.
  Перевірка доменної викличності відкладена виключно pinned WideIR.
  1) Чому не дозволяємо .lisp як канонічну програму?
  2) Як контролюємо квоту перед allocate?
  3) Коли звільняється F:TFileStream? }
function ReadAnchor(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise EQuotStreamCLI.Create('потрібен фізичний canonical .sens якір');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EQuotStreamCLI.Create('фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Бінарний ELF — caller-owned managed bytes, PublishNewELF64 забезпечує
  no-clobber. Runtime stdin: ДВА окремі canonical W12 (6 байтів).
  Успіх: один Linux executable ELF64 ET_DYN. Помилка: exit2 без ELF.
  1) Чому 6 байтів не є повною мовною формою SENS?
  2) Хто визначає ратифікований D5:10111 закон?
  3) Чому D24/дробова частка мають явну відмову?
  4) Чому Linux syscall не замінює SENS numeric gate? }
procedure Run;
var Anchor,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>ModeBuild) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EQuotStreamCLI.Create(
      'виклик: sensd12quotpotikelf --зібрати-D5-частку-потік якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise EQuotStreamCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EQuotStreamCLI.Create('потрібен x86-64');
  {$ENDIF}
  Anchor:=ReadAnchor(ParamStr(2));
  Image:=BuildVerifiedD12QuotStreamELF(Anchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д5-ЧАСТКА-ПОТІК-ГОТОВО байтів='+IntToStr(G.FileBytes)+
    ' machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('Д5-ЧАСТКА-ПОТІК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
