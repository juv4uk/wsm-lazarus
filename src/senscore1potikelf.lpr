{ G6.161 — physical pinned Core1 → повторно використовуваний ELF64.
  Збірка БЕЗ runtime аргументів: новий ELF читає два D12 T5M
  зі stdin під час кожного окремого запуску. .lisp — людська «укр»
  проєкція, не джерело машинного компілювання цього CLI. }
program senscore1potikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.core1potik,wsm.elfpublish,wsm.elfgeometry;
type ECore1PotikCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Say(const S:UnicodeString;ErrorChannel:Boolean);
var B:RawByteString;Stream:THandleStream;
begin
  B:=UA(S)+#10;
  if ErrorChannel then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(B[1],Length(B))
  finally Stream.Free end;
end;

{ Єдиний host mode, без D7 або текстового semantic dispatch.
  Вихідний .elf — новий файл із 0700, який публікує наявний
  PublishNewELF64 без перезапису. Image — managed ELF bytes, G
  локальний host-запис, не мовний Dn. Потоковий ввід відбувається
  вже під час виконання ELF, а НЕ під час компіляції.

  1) Чому .elf не має права бути наявним файлом?
  2) Чи може D7 текстова назва змінити pinned Core1 закон?
  3) Хто перевіряє повний оригінальний фізичний DEFINE?
  4) Чому stderr не змішується із T5M stdout ELF? }
procedure Run;
var Mode:RawByteString;Kind:TCore1PotikMachine;
    Image:RawByteString;G:TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise ECore1PotikCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore1PotikCLI.Create('потрібен x86-64');
  {$ENDIF}
  if ParamCount<>2 then
    raise ECore1PotikCLI.Create('виклик: senscore1potikelf --ядро1-додати-потік|--ядро1-відняти-потік новий.elf');
  Mode:=RawByteString(ParamStr(1));
  if Mode=UA('--ядро1-додати-потік') then Kind:=cpAdd
  else if Mode=UA('--ядро1-відняти-потік') then Kind:=cpSub
  else raise ECore1PotikCLI.Create('невідомий host режим Core1');
  if (Length(ParamStr(2))>4096) or
     (ExtractFileExt(ParamStr(2))<>'.elf') then
    raise ECore1PotikCLI.Create('потрібна нова ціль .elf');
  Image:=BuildPinnedCore1StreamELF('.',Kind);
  PublishNewELF64(ParamStr(2),Image,3,G);
  Say('ЯДРО1-ПОТІК-ELF-ГОТОВО bytes='+IntToStr(G.FileBytes)+
      ' runtime=2xD12 T5M; overflow=D24-НЕ-ПІДТРИМАНО',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('ЯДРО1-ПОТІК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
