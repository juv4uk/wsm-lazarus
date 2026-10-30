{ G6.168 — фізичний pinned Core1 ADD -> повторно використовуваний
  нативний ELF64 з динамічним signed D12/D24 T5M результатом.
  Жодного source .lisp у машинному вході: укр — лише людська проєкція. }
program senscore1potikadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.core1potikadaptive,
     wsm.elfpublish,wsm.elfgeometry;
type EAdaptiveCore1CLI=class(Exception);
const ModeBuild:RawByteString='--ядро1-адаптивне-додавання';

procedure Report(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;Sink:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then Sink:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Bytes[1],Length(Bytes)) finally Sink.Free end;
end;

{ CLI приймає тільки host-режим і новий ELF-файл, а не текстове ім'я
  мовної функції. Image — власний managed RawByteString до виходу
  процедури, Geometry — host ELF метадані. PublishNewELF64 гарантує
  0700/no-clobber і відсутність частково опублікованого машинного файла.
  1) Чому виконуваний файл не може перезаписати наявний?
  2) Де читається реальний pinned Core1, а де просто назва режиму?
  3) Чому машинний stdout належить викликаному ELF, а не цьому CLI?
  4) Чому D24 фізичний вивід має п'ять канонічних T5M байтів? }
procedure Run;
var Image:RawByteString;Geometry:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise EAdaptiveCore1CLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EAdaptiveCore1CLI.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>ModeBuild) or
     (Length(ParamStr(2))>4096) or
     (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise EAdaptiveCore1CLI.Create(
      'виклик: senscore1potikadaptive --ядро1-адаптивне-додавання новий.elf');
  Image:=BuildPinnedCore1AdaptiveAddELF('.');
  PublishNewELF64(ParamStr(2),Image,3,Geometry);
  Report('ЯДРО1-АДАПТИВНЕ-ELF-ГОТОВО bytes='+IntToStr(Geometry.FileBytes)+
    ' stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    Report('ЯДРО1-АДАПТИВНЕ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
