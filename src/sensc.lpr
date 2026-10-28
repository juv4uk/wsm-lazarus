program sensc;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.compiler;
var InFile,OutFile:TFileStream; Buffer:TMemoryStream; S:RawByteString;
    Stats:TSIR1Stats;
begin
  if (ParamCount=2) and (ParamStr(1)='--verify-ir') then begin
    try
      InFile:=TFileStream.Create(ParamStr(2),fmOpenRead);
      try VerifySIR1(InFile);
      finally InFile.Free; end;
      WriteLn('SENSC-SIR1-VERIFY-OK structural-only=1');
      Halt(0);
    except
      on E:Exception do begin WriteLn(StdErr,'SENSC-FAIL ',E.Message); Halt(1); end;
    end;
  end;
  if (ParamCount=2) and (ParamStr(1)='--inspect-ir') then begin
    try
      InFile:=TFileStream.Create(ParamStr(2),fmOpenRead);
      try InspectSIR1(InFile,Stats);
      finally InFile.Free; end;
      WriteLn('SENSC-SIR1-INSPECT-OK structural-only=1',
        ' tokens=',Stats.Tokens,
        ' opens=',Stats.ListOpens,
        ' closes=',Stats.ListCloses,
        ' atoms=',Stats.Atoms,
        ' strings=',Stats.Strings,
        ' payload_bytes=',Stats.PayloadBytes,
        ' max_depth=',Stats.MaxDepth);
      Halt(0);
    except
      on E:Exception do begin WriteLn(StdErr,'SENSC-FAIL ',E.Message); Halt(1); end;
    end;
  end;
  if (ParamCount<>3) or (ParamStr(1)<>'--compile-ir') then begin
    WriteLn(StdErr,'usage: sensc --compile-ir source.lisp output.sir');
    WriteLn(StdErr,'       sensc --verify-ir input.sir');
    WriteLn(StdErr,'       sensc --inspect-ir input.sir');
    Halt(64);
  end;
  try
    InFile:=TFileStream.Create(ParamStr(2),fmOpenRead);
    try
      if InFile.Size>High(LongInt) then raise ECompileError.Create('source too large');
      SetLength(S,InFile.Size);
      if Length(S)>0 then InFile.ReadBuffer(S[1],Length(S));
    finally InFile.Free; end;
    Buffer:=TMemoryStream.Create;
    try
      CompileSource(S,Buffer);
      Buffer.Position:=0;
      VerifySIR1(Buffer);
      OutFile:=TFileStream.Create(ParamStr(3),fmCreate);
      try Buffer.Position:=0; OutFile.CopyFrom(Buffer,Buffer.Size);
      finally OutFile.Free; end;
    finally Buffer.Free; end;
    WriteLn('SENSC-IR-OK');
  except
    on E:Exception do begin WriteLn(StdErr,'SENSC-FAIL ',E.Message); Halt(1); end;
  end;
end.
