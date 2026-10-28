{ Командний вхід для вузького фізичного двійкового виконання.
  Вивід — поточний результат вже злитого native evaluator, НЕ .sens. }
program sensvykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec, wsm.t5m;
var F:TFileStream; Payload,Answer:RawByteString; Engine:TBinaryExecutor;
begin
  if (ParamCount <> 2) or (ParamStr(1) <> #$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8) or
     (LowerCase(ExtractFileExt(ParamStr(2))) <> '.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$76#$79#$6B#$6F#$6E#$20#$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$20#$D0#$BF#$D1#$80#$D0#$BE#$D0#$B3#$D1#$80#$D0#$B0#$D0#$BC#$D0#$B0#$2E#$73#$65#$6E#$73);
    Halt(64);
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
    Answer := Engine.ExecutePhysical(Payload);
    { Нічого не виводити до повної фізичної/структурної перевірки. }
    WriteLn(Answer);
  except
    on E: EBinaryExecutionError do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D,
        E.WordIndex,' ',E.Message);
      Halt(2);
    end;
    on E: Exception do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$20,E.Message);
      Halt(2);
    end;
  end;
  Engine.Free;
end.
