{ G5.9 — атомарний командний запуск кількох фізичних SENS форм.
  Вихід лише після повного успіху. Це НЕ постійний REPL. }
program senspaket;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.binaryexec, wsm.binarybatch;
procedure Zapustyty;
var
  Stream: TFileStream;       { файловий потік — належить виклику }
  Payload: RawByteString;   { тільки фізичні T5M байти }
  Answers: TBinaryBatchAnswers; { вихід host evaluator, не файл .sens }
  Executor: TBinaryExecutor; { власник native evaluator / pinned таблиць }
  I: SizeInt;
begin
  if (ParamCount <> 2) or (ParamStr(1) <> #$2D#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82) or
     (LowerCase(ExtractFileExt(ParamStr(2))) <> '.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$70#$61#$6B#$65#$74#$20#$2D#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$20#$D0#$BF#$D1#$80#$D0#$BE#$D0#$B3#$D1#$80#$D0#$B0#$D0#$BC#$D0#$B0#$2E#$73#$65#$6E#$73);
    ExitCode := 64;
    Exit;
  end;
  Executor := nil;
  try
    try
      Stream := TFileStream.Create(ParamStr(2),fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size <= 0) or (Stream.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$BD#$D0#$B0#$D0#$B4#$D1#$82#$D0#$BE#$20#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$2E#$73#$65#$6E#$73);
      SetLength(Payload,SizeInt(Stream.Size));
      Stream.ReadBuffer(Payload[1],Length(Payload));
    finally
      Stream.Free;
    end;
    Executor := TBinaryExecutor.Create('external/sens');
    ExecuteBinaryBatch(Payload,Executor,Answers);
    { Жодного виводу, поки не прийнято ОСТАННЮ фізичну форму. }
    for I := 0 to High(Answers) do WriteLn(String(Answers[I]));
  except
    on E: EBinaryBatchError do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$53#$45#$4E#$53#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0#$3D,E.RootIndex+1,
        #$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D,E.WordIndex,' ',E.Message);
      ExitCode := 2;
    end;
    on E: Exception do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$53#$45#$4E#$53#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$20,E.Message);
      ExitCode := 2;
    end;
    end;
  finally
    { Навіть після помилки другої форми і невдалого конструктора. }
    Executor.Free;
  end;
end;

begin
  Zapustyty;
end.
