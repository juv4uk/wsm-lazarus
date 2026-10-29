{ G6.128 — фізичний .sens → перевірений native ELF64 у stdout.
  Немає нового SENS закону, числового dispatch чи нового emitter.
  Весь binary stdout відкладаємо до закінчення pinned admission,
  компіляції та остаточної ELF64 геометричної перевірки.
  Типи: Path — borrowed host String, Source і Image — owned managed
  RawByteString; файловий та stdout THandleStream мають локальний lifetime.
  1) Чому .lisp не є фізичним джерелом?
  2) Чому неможливо визначати D12 тільки з ширини W12?
  3) Хто вирішує допустимість виклику за pinned D5/D6?
  4) Чому діагностика має йти лише у stderr?
  5) Що гарантує відсутність часткового stdout при помилці admission? }
program senswidefrontstdout;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.elfgeometry;
type EWideStdoutError=class(Exception);
const ModeCompile:RawByteString='--скомпілювати-фізичну-форму-в-потік';

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EWideStdoutError.Create(
      'потрібна канонічна фізична програма з розширенням .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWideStdoutError.Create('фізичний вхід поза дозволеною квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Image — повністю перевірений ELF64 PIE, ще не записаний.
  Запис однією операцією THandleStream не є файловою транзакцією:
  якщо споживач розірвав pipe посеред запису, можливий усічений ELF.
  Жодна відмова читача/домена/компілятора/геометрії не пише stdout.
  1) Чому stdout — двійковий і не містить українського статусу?
  2) Коли виділена пам'ять Image звільняється?
  3) Чому перевіряємо Kind=3 і Entry=120 перед emit?
  4) Чому EPIPE відрізняється від помилки pinned admission? }
procedure EmitVerifiedELF(const Image:RawByteString);
var G:TELFGeometry;OutStream:THandleStream;
begin
  VerifySENSELF64(Image,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Image)) or (G.MachineBytes<1) then
    raise EWideStdoutError.Create('невірна геометрія ELF64 PIE');
  OutStream:=THandleStream.Create(TextRec(Output).Handle);
  try
    OutStream.WriteBuffer(Image[1],Length(Image));
  finally OutStream.Free end;
end;

{ Службова помилка — UTF-8 тільки в stderr, не у фізичному каналі ELF.
  Result не потрібен: stdout містить єдиний виконуваний артефакт.
  1) Чому error path не виводить зіпсований ELF?
  2) Чому текстова мова людини не задає машинний opcode?
  3) Чому код 2 не можна приховати зеленим shell pipeline? }
procedure ReportFailure(const Message:UnicodeString);
var Data:RawByteString;ErrStream:THandleStream;
begin
  Data:=RawByteString(UTF8Encode('ЕЛЬФ-ПОТІК-ВІДМОВА: '+Message))+#10;
  ErrStream:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try ErrStream.WriteBuffer(Data[1],Length(Data))
  finally ErrStream.Free end;
end;

procedure Run;
var Source,Image:RawByteString;
begin
  if (ParamCount<>2) or
    (RawByteString(ParamStr(1))<>ModeCompile) then
    raise EWideStdoutError.Create(
      'виклик: senswidefrontstdout --скомпілювати-фізичну-форму-в-потік програма.sens');
  {$IFNDEF LINUX}
  raise EWideStdoutError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideStdoutError.Create('потрібен x86-64');
  {$ENDIF}
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildVerifiedWideELF(Source,'external/sens');
  EmitVerifiedELF(Image);
end;

begin
  try Run
  except
    on E:Exception do begin
      ReportFailure(UnicodeString(E.Message));
      ExitCode:=2;
    end;
  end;
end.
