program sensc;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.compiler{$IFDEF UNIX}, BaseUnix{$ENDIF};
{$IFDEF UNIX}
function CreatePrivateSIRTemp(Template: PChar): cint; cdecl;
  external 'c' name 'mkstemp';
{$ENDIF}

{ SIR1 — приватна структурна послідовність, а не канонічна .sens і не
  виконуваний код. Path — запозичене ім'я цілі ОС, Buffer — перевірений
  TMemoryStream; його байти лишаються власністю викликача.
  Тимчасовий inode/fd живе лише тут. mkstemp створює новий 0600,
  цикл записує навіть за коротких fpWrite, fpLink публікує повний
  контейнер під новим ім'ям без перезапису файлів чи symlink.
  Питання: 1) Чому перевірка FileExists не захищає від гонки?
  2) Чому потік не можна повторно відкривати через fmCreate?
  3) Чому fpLink має бути після fpClose?
  4) Чому SIR1 не можна виконувати як .sens?
  5) Чи очищається inode, коли target уже зайнятий? }
procedure PublishNewSIR1(const Path:String; const Buffer:TMemoryStream);
{$IFDEF UNIX}
var Temp:RawByteString; FD:cint; Offset,Written:SizeInt;
    Created:Boolean;
{$ENDIF}
begin
  if Path='' then raise ECompileError.Create('не задано вихідний SIR1');
  if (Buffer.Size<9) or (Buffer.Size>High(LongInt)) then
    raise ECompileError.Create('неприпустимий обсяг SIR1');
  {$IFDEF UNIX}
  Temp:=''; FD:=-1; Created:=False;
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path)))+'sirXXXXXX');
    UniqueString(Temp);
    FD:=CreatePrivateSIRTemp(PChar(Temp));
    if FD<0 then raise ECompileError.Create('не створено приватний SIR1');
    Created:=True;
    Offset:=0;
    while Offset<Buffer.Size do begin
      Written:=fpWrite(FD,PByte(Buffer.Memory)[Offset],Buffer.Size-Offset);
      if Written<=0 then
        raise ECompileError.Create('не записано повний SIR1');
      Inc(Offset,Written);
    end;
    if fpClose(FD)<>0 then begin
      FD:=-1;
      raise ECompileError.Create('не закрито повний SIR1');
    end;
    FD:=-1;
    if fpLink(Temp,RawByteString(Path))<>0 then
      raise ECompileError.Create('ціль SIR1 зайнята або недоступна');
  finally
    if FD>=0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise ECompileError.Create('безпечна публікація SIR1 на цій ОС недоступна');
  {$ENDIF}
end;

var InFile:TFileStream; Buffer:TMemoryStream; S:RawByteString;
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
      PublishNewSIR1(ParamStr(3),Buffer);
    finally Buffer.Free; end;
    WriteLn('SENSC-IR-OK');
  except
    on E:Exception do begin WriteLn(StdErr,'SENSC-FAIL ',E.Message); Halt(1); end;
  end;
end.
