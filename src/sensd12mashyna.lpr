{ G6.69 — одна host-точка входу до ДВОХ уже перевірених D12 AOT backend.
  Це НЕ закон мови, не довільний SENS compiler і не REPL.
  Жодна текстова проєкція/назва функції не визначає машинну семантику:
  режим є явним host-параметром, після якого лише pinned numeric-механізми
  існуючих emitter-ів допускають точні фізичні D12 операнди. }
program sensd12mashyna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfd12add, wsm.elfd12mul,
  wsm.elfpublish, wsm.elfgeometry;

const
  MaxAtomBytes = 64;
  ModeAdd:RawByteString='--'+#$D0#$B4#$D0#$BE#$D0#$B4#$D0#$B0#$D1#$82#$D0#$B8+'-D12';
  ModeMul:RawByteString='--'+#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$BD#$D0#$BE#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8+'-D12';
type
  EDriver=class(Exception);

function UA(const Value:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(Value));
end;

{ Вхід Path — позичена host-адреса файла, а НЕ D7 слово.
  Вихід — owned RawByteString exact T5M, із керованим життям FPC.
  Розпізнання D12/D24 та закону належить винятково чинним emitter-ам,
  а НЕ довжині байтів; верхня межа тільки захищає host-ресурс.
  1) Чому .lisp не є двійковим атомом?
  2) Чому FSize не визначає домен?
  3) Чому інші читачі можуть безпечно відкривати той самий файл? }
function ReadPhysical(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise EDriver.Create(UA('Очікується канонічний двійковий .sens'));
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxAtomBytes) then
      raise EDriver.Create(UA('Фізичний атом порожній або завеликий'));
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally
    Stream.Free;
  end;
end;

{ Скарги і підтвердження публікуються точними UTF-8 host-байтами.
  Source/Result тут НЕ SENS-значення; лише повідомлення для людини.
  1) Чому stderr не є семантичним виходом?
  2) Кому належить THandleStream?
  3) Чому статус дозволено писати тільки після PublishNewELF64? }
procedure EmitText(const Handle:THandle;const Bytes:RawByteString);
var Stream:THandleStream;
begin
  Stream:=THandleStream.Create(Handle);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally
    Stream.Free;
  end;
end;

procedure Run;
var Mode,LeftAtom,RightAtom,Image,LabelText:RawByteString;
    Geometry:TELFGeometry; OutputPath:String;
begin
  if ParamCount<>4 then
    raise EDriver.Create(UA('Виклик: sensd12mashyna --додати-D12|--помножити-D12 ліве.sens праве.sens новий.elf'));
  Mode:=RawByteString(ParamStr(1));
  if (Mode<>ModeAdd) and (Mode<>ModeMul) then
    raise EDriver.Create(UA('Невідомий явний host-режим D12'));
  OutputPath:=ParamStr(4);
  if ExtractFileExt(OutputPath)<>'.elf' then
    raise EDriver.Create(UA('Для машинного результату потрібен новий .elf'));
  {$IFNDEF LINUX}
  raise EDriver.Create(UA('Підтримується лише Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EDriver.Create(UA('Підтримується лише x86-64'));
  {$ENDIF}
  LeftAtom:=ReadPhysical(ParamStr(2));
  RightAtom:=ReadPhysical(ParamStr(3));
  { Обидва backend самі повторно перевіряють T5M, точний D12, межі
    ратифікованого числового результату і фізичний T5M output.
    Host mode визначає лише вибір уже наявного codegen, а не lookup
    за укр/en іменем мовної функції. }
  if Mode=ModeAdd then begin
    Image:=BuildD12AddELF(LeftAtom,RightAtom);
    LabelText:=UA('додавання');
  end else begin
    Image:=BuildD12MulELF(LeftAtom,RightAtom);
    LabelText:=UA('множення');
  end;
  { Єдиний наявний структурний ELF guard і атомарний no-clobber
    publisher; успішна операція створює новий ET_DYN із режимом 0700. }
  PublishNewELF64(OutputPath,Image,3,Geometry);
  EmitText(TextRec(Output).Handle,
    UA('НАТИВНИЙ-D12-ELF-ГОТОВО дія=')+LabelText+
    UA(' тип=')+IntToStr(Geometry.Kind)+
    UA(' байтів=')+IntToStr(Geometry.FileBytes)+
    ' stdout=T5M'+#10);
end;

begin
  try Run
  except on E:Exception do begin
    EmitText(TextRec(ErrOutput).Handle,UA('НАТИВНИЙ-D12-ELF-ВІДМОВА: ')+
      UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.

{ Межі і lifetime: LeftAtom/RightAtom/Image — FPC managed owned bytes;
  зміст фізичних бітів ніколи не інтерпретується в CLI. Geometry — лише
  метадані Linux ELF64 (host), а не домен SENS. Жодного GC, Core1 чи
  числового D24 input цей вузький frontend не запроваджує.
  1) Хто визначає D12 overflow?
  2) Хто визначає D12→D24 ширину після IMUL?
  3) Чому ModeAdd/ModeMul — тільки host API, не SENS dispatch?
  4) Де гарантується відмова перезаписати існуючий ELF?
  5) Чому це справжній машинний AOT-виклик, але не загальний compiler? }
