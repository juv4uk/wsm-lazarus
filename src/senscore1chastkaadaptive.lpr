{ G6.181 — запуск лише перевіреного фізичного pinned Core1 → ELF64.
  Українські слова тут тільки host UI; семантика походить із Core1 T5M. }
program senscore1chastkaadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.core1chastkaadaptive,
     wsm.elfpublish,wsm.elfgeometry;
const ModeBuild:RawByteString='--зібрати-фізичну-core1-частку';
type ECore1QuotCLI=class(Exception);

procedure Say(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;S:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes))
  finally S.Free end;
end;

{ RepoRoot is an immutable host path; Image is an owned checked ELF byte
  string. Existing PublishNewELF64 prevents clobber and symlink writes.
  Questions: why is a .lisp projection not an input? Who owns Image?
  Why check the ELF profile after source-backed admission? }
procedure Run;
var Image:RawByteString;Geometry:TELFGeometry;
begin
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>ModeBuild) or
     (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ECore1QuotCLI.Create(
      'виклик: senscore1chastkaadaptive --зібрати-фізичну-core1-частку новий.elf');
  {$IFNDEF LINUX}
  raise ECore1QuotCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore1QuotCLI.Create('потрібен x86-64');
  {$ENDIF}
  Image:=BuildPinnedCore1AdaptiveQuotELF('.');
  PublishNewELF64(ParamStr(2),Image,3,Geometry);
  Say('CORE1-ЧАСТКА-ГОТОВО байтів='+IntToStr(Geometry.FileBytes)+
      ' machine=IDIV stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say('CORE1-ЧАСТКА-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
