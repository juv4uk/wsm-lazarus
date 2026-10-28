{ Командний вхід для вузького фізичного двійкового виконання.
  Вивід — поточний результат вже злитого native evaluator, НЕ .sens. }
program sensvykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec, wsm.t5m;
var F:TFileStream; Payload,Answer:RawByteString; Engine:TBinaryExecutor;
begin
  if (ParamCount <> 2) or (ParamStr(1) <> '--виконати') or
     (LowerCase(ExtractFileExt(ParamStr(2))) <> '.sens') then begin
    WriteLn(StdErr,'Використання: sensvykon --виконати програма.sens');
    Halt(64);
  end;
  Engine := nil;
  try
    F := TFileStream.Create(ParamStr(2),fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або завеликий двійковий файл');
      SetLength(Payload, SizeInt(F.Size));
      F.ReadBuffer(Payload[1], Length(Payload));
    finally F.Free; end;
    Engine := TBinaryExecutor.Create('external/sens');
    Answer := Engine.ExecutePhysical(Payload);
    { Нічого не виводити до повної фізичної/структурної перевірки. }
    WriteLn(Answer);
  except
    on E: EBinaryExecutionError do begin
      WriteLn(StdErr,'ПОМИЛКА-ДВІЙКОВОГО-ВИКОНАННЯ слово=',
        E.WordIndex,' ',E.Message);
      Halt(2);
    end;
    on E: Exception do begin
      WriteLn(StdErr,'ПОМИЛКА-ДВІЙКОВОГО-ВИКОНАННЯ ',E.Message);
      Halt(2);
    end;
  end;
  Engine.Free;
end.
