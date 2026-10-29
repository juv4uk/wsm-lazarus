{ Командний вхід для вузького фізичного двійкового виконання.
  --виконати: людська проєкція; --виконати-сенс: packed canonical T5M.
  Обидва режими лише через той самий pinned exact-domain evaluator. }
program sensvykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec, wsm.t5m, wsm.physloc;
var F:TFileStream; Payload,Answer:RawByteString; Engine:TBinaryExecutor;
{ G3.35. Лише host-діагностика: WordIndex — 1-based фізичне слово
  з EBinaryExecutionError; Bytes — позичений канонічний T5M payload.
  TExactWords/TPhysicalWordSpans керовані FPC-масиви й існують лише
  протягом виклику; повертаємо звичайний український String у stderr.
  У межах WordIndex=N+1 показуємо справжню позицію EOF, а не слово.
  Помилкові T5M байти ніколи не отримують вигаданої координати.
  Нові закони, UTF8 bind або додатковий фізичний decoder НЕ створюємо.
  Питання: чому EOF не є словом? Як два слова можуть ділити байт?
  Коли фізичний номер відомий, але trit/byte позиція — ні?
  Чому host-рядок діагностики не є результатом SENS? }
function PhysicalFaultLocation(const Bytes:RawByteString;
  AtWord:SizeInt):RawByteString;
var
  Words:TExactWords;
  Spans:TPhysicalWordSpans;
  AtSpan:TPhysicalWordSpan;
begin
  Result:='';
  if (AtWord<1) or (Length(Bytes)=0) or
     (Length(Bytes)>MAX_T5M_FILE_BYTES) then Exit;
  try
    DecodeT5MWithLocations(Bytes,Words,Spans);
    { Exact mapping only; no guessing from decoded lengths if out of range. }
    if (AtWord>Length(Spans)+1) then Exit;
    AtSpan:=LocatePhysicalWord(Bytes,Spans,AtWord);
    if AtSpan.WordIndex<>AtWord then Exit;
    if AtSpan.IsEOF then Result:=#$20#$D0#$BA#$D1#$96#$D0#$BD#$D0#$B5#$D1#$86#$D1#$8C#$2D#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$D1#$83;
    { UTF-8 bytes explicit: FPC host ANSI runtime must not convert
      UnicodeString literals into ????? on minimal Ubuntu locale. }
    Result:=Result+#$20#$D1#$82#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8#$3D#$5B+
      IntToStr(AtSpan.TritStart)+','+IntToStr(AtSpan.TritEnd)+')'+
      #$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D0#$B8#$3D#$5B+
      IntToStr(AtSpan.ByteStart)+','+IntToStr(AtSpan.ByteEnd)+')';
  except
    { Первинна помилка виконання має лишитися основною; не видавати
      вигадану позицію, якщо фізичні байти недопустимі. }
    on X:Exception do Result:='';
  end;
end;

{ G3.37. Bytes: позичений повністю виконаний T5M результат, не
  українська проєкція. Єдиний власник — RawByteString виконавця;
  Offset/Chunk: host SizeInt кількість уже записаних/нових байтів.
  FileWrite працює без ANSI/UTF8-конверсії і без кінцевого newline;
  пишемо після повної перевірки, з урахуванням short writes.
  Запис stdout при фізичній помилці потоку не можна відкрутити назад,
  але мовна/структурна відмова відбувається ДО першого FileWrite.
  Питання: чому WriteLn зіпсує T5M? Що таке short write?
  Яка різниця між D7 символами та фізичними D7 словами?
  Хто гарантує exact-domain admission до першого байта stdout? }
procedure WritePhysicalStdout(const Bytes:RawByteString);
var Offset,Chunk:SizeInt;
begin
  if Length(Bytes)=0 then
    raise Exception.Create('порожня фізична відповідь SENS');
  Offset:=0;
  while Offset<Length(Bytes) do begin
    Chunk:=FileWrite(TTextRec(Output).Handle,Bytes[Offset+1],
      Length(Bytes)-Offset);
    if Chunk<=0 then
      raise Exception.Create('помилка запису двійкового stdout');
    Inc(Offset,Chunk);
  end;
end;

procedure Zapustyty;
var PhysicalOutput:Boolean;
begin
  PhysicalOutput:=(ParamCount=2) and (ParamStr(1) = #$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$2D#$D1#$81#$D0#$B5#$D0#$BD#$D1#$81);
  if (ParamCount <> 2) or
     (not PhysicalOutput and (ParamStr(1) <> #$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8)) or
     (LowerCase(ExtractFileExt(ParamStr(2))) <> '.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$76#$79#$6B#$6F#$6E#$20#$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$20#$D0#$BF#$D1#$80#$D0#$BE#$D0#$B3#$D1#$80#$D0#$B0#$D0#$BC#$D0#$B0#$2E#$73#$65#$6E#$73);
    ExitCode := 64;
    Exit;
  end;
  Engine := nil;
  try
    F := TFileStream.Create(ParamStr(2),fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB);
      SetLength(Payload, SizeInt(F.Size));
      F.ReadBuffer(Payload[1], Length(Payload));
    finally F.Free; end;
    Engine := TBinaryExecutor.Create('external/sens');
    { Рівно один вже злитий native evaluator; PhysicalOutput тільки
      обирає host-представлення відповіді ПІСЛЯ виконання. }
    if PhysicalOutput then Answer:=Engine.ExecutePhysicalT5M(Payload)
    else Answer:=Engine.ExecutePhysical(Payload);
    { Ніякого stdout до повного T5M/D2/binder/evaluator допуску. }
    if PhysicalOutput then WritePhysicalStdout(Answer)
    else WriteLn(Answer);
  except
    on E: EBinaryExecutionError do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D,
        E.WordIndex,PhysicalFaultLocation(Payload,E.WordIndex),' ',E.Message);
      ExitCode := 2;
    end;
    on E: Exception do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$20,E.Message);
      ExitCode := 2;
    end;
  end;
  { Виняток уже оброблено; потрібен нормальний вихід з процедурою
    очищення, а не Halt із витоком клітин і pinned-таблиць. }
  Engine.Free;
end;

begin
  Zapustyty;
end.
