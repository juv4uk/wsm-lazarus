{ Вузький CLI для фактичного D1/D3 виконання і точних фізичних помилок.
  Жодна українська проєкція не є виконуваним джерелом. }
program senspomylka;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.execfault, wsm.binaryexec, wsm.t5m;
var Stream: TFileStream; Data,Answer: RawByteString; Engine:TBinaryExecutor;
begin
  if (ParamCount<>2) or
     (ParamStr(1)<>'--'+#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$70#$6F#$6D#$79#$6C#$6B#$61#$20#$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73);
    Halt(64);
  end;
  Engine:=nil;
  try
    Stream:=TFileStream.Create(ParamStr(2),fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<=0) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB);
      SetLength(Data,SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[1],Length(Data));
    finally Stream.Free; end;
    Engine:=TBinaryExecutor.Create('external/sens');
    Answer:=ExecuteWithPhysicalLocation(Data,Engine);
    { Атомарність stdout: лише ПІСЛЯ повного виконання. }
    WriteLn(Answer);
  except
    on E:ELocatedExecutionFault do begin
      Write(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D,E.WordIndex);
      if E.HasPhysicalSpan then begin
        Write(StdErr,#$20#$D1#$82#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8#$3D#$5B,E.Span.TritStart,',',E.Span.TritEnd,') ',
          #$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D0#$B8#$3D#$5B,E.Span.ByteStart,',',E.Span.ByteEnd,')');
        if E.Span.IsEOF then Write(StdErr,' EOF');
      end else Write(StdErr,#$20#$D1#$96#$D0#$BD#$D1#$82#$D0#$B5#$D1#$80#$D0#$B2#$D0#$B0#$D0#$BB#$3D#$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$B9);
      WriteLn(StdErr,' ',E.Message);
      Halt(2);
    end;
    on E:Exception do begin
      WriteLn(StdErr,#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$2D#$D0#$A4#$D0#$86#$D0#$97#$D0#$98#$D0#$A7#$D0#$9D#$D0#$9E#$D0#$93#$D0#$9E#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$3A#$20,E.Message);
      Halt(2);
    end;
  end;
  Engine.Free;
end.
