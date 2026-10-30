{ G6.162 — одне фізичне D5:01010 джерело → динамічний native ELF64.
  Вхідні два окремі canonical W12 у host stdin, НЕ текст .lisp.
  Домен і закон визначають тільки pinned SENS через WideIR донора.
  Result: owned packed ELF bytes, атомарний no-clobber host-файл.
  TFileStream закривається у finally; FPC звільняє RawByteString.
  1) Чому D24 output має 5 фізичних T5M байтів?
  2) Чому .sens якір передує машинній компіляції?
  3) Чому існуючий ELF шлях не можна переписувати?
  4) Де перевірка цілого D2 виразу?
  5) Чому .lisp не є binary program? }
program sensd12addpotikadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12addpotikadaptive,
  wsm.elfpublish,wsm.elfgeometry;
type EAdaptiveAddCLI=class(Exception);
const ModeBuild:RawByteString='--зібрати-адаптивне-D5-додавання';
      ModeBuildSub:RawByteString='--зібрати-адаптивне-D5-віднімання';

procedure ReportUTF8(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;S:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes)) finally S.Free end;
end;

function ReadPhysical(const Path:String):RawByteString;
var S:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EAdaptiveAddCLI.Create('потрібен канонічний двійковий .sens');
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<1) or (S.Size>65536) then
      raise EAdaptiveAddCLI.Create('фізичний файл поза квотою');
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

procedure Run;
var Physical,ELF,ChosenMode:RawByteString;G:TELFGeometry;
begin
  ChosenMode:=RawByteString(ParamStr(1));
  if (ParamCount<>3) or
    ((ChosenMode<>ModeBuild) and (ChosenMode<>ModeBuildSub)) or
    (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EAdaptiveAddCLI.Create(
      'виклик: sensd12addpotikadaptive --зібрати-адаптивне-D5-додавання|--зібрати-адаптивне-D5-віднімання програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EAdaptiveAddCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EAdaptiveAddCLI.Create('потрібен x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  if ChosenMode=ModeBuild then
    ELF:=BuildAdaptiveD12AddFramedELF(Physical,'external/sens')
  else
    ELF:=BuildAdaptiveD12SubFramedELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),ELF,3,G);
  if ChosenMode=ModeBuild then
    ReportUTF8('АДАПТИВНЕ-D5-ADD-ГОТОВО elf-bytes='+IntToStr(G.FileBytes)+
      ' stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False)
  else
    ReportUTF8('АДАПТИВНЕ-D5-SUB-ГОТОВО elf-bytes='+IntToStr(G.FileBytes)+
      ' stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    if RawByteString(ParamStr(1))=ModeBuildSub then
      ReportUTF8('АДАПТИВНЕ-D5-SUB-ВІДМОВА: '+UnicodeString(E.Message),True)
    else
      ReportUTF8('АДАПТИВНЕ-D5-ADD-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
