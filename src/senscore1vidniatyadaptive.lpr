{ G6.177 — pinned Core1 DEFINE → атомарна публікація одного x86-64 ELF64,
  що віднімає два canonical runtime W12 зі signed D12/D24 відповіддю.
  Host CLI режим — не текстовий мовний dispatch і не .lisp source. }
program senscore1vidniatyadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.core1vidniatyadaptive,
     wsm.elfpublish,wsm.elfgeometry;
type ECore1SubCLI=class(Exception);
const ModeBuild:RawByteString='--ядро1-адаптивне-віднімання';

procedure Report(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;Handle:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then Handle:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Handle:=THandleStream.Create(TextRec(Output).Handle);
  try Handle.WriteBuffer(Bytes[1],Length(Bytes)) finally Handle.Free end;
end;

{ Обидва параметри CLI — host-дані. ELF — owned RawByteString, який
  опублікує чинний verified ELF publisher лише у новий inode, правами
  0700, без перезапису цілі/посилання, no partial image. Параметри
  чисел не передаються сюди: їх прочитає вже створена машина зі stdin.
  1) Чому mode не визначає SENS закон?
  2) Навіщо Require ELF extension і no-clobber для native output?
  3) Чим фізичний stdin відрізняється від українського .lisp?
  4) Чому ExitCode=2 не має створити недописаний ELF? }
procedure Run;
var Machine:RawByteString;Geometry:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise ECore1SubCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore1SubCLI.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>ModeBuild) or
     (ParamStr(2)='') or (Length(ParamStr(2))>4096) or
     (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ECore1SubCLI.Create(
      'виклик: senscore1vidniatyadaptive --ядро1-адаптивне-віднімання новий.elf');
  Machine:=BuildPinnedCore1AdaptiveSubELF('.');
  PublishNewELF64(ParamStr(2),Machine,3,Geometry);
  Report('ЯДРО1-ВІДНЯТИ-ELF-ГОТОВО bytes='+IntToStr(Geometry.FileBytes)+
    ' stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    Report('ЯДРО1-ВІДНЯТИ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
