{ G5.1 host-side session dispatch. This is NOT a SENS evaluator or REPL.
  Parsing is delegated to pinned-compatible wsm.source; law and callability
  remain exclusively in juv4uk/sens. Reply.Ok is an I/O result, NOT D1. }
unit wsm.session;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.source, wsm.envframe;

type
  ESessionError = class(Exception);

  TSessionReply = record
    Ok: Boolean;              { transport/executor status; never a SENS bit }
    Output: RawByteString;
    Diagnostic: RawByteString;
    FormNumber: QWord;
    ByteOffset, Line, ByteColumn: SizeInt;
  end;
  TSessionReplies = array of TSessionReply;

  { Dependency injection: only a future SENS-verified executor can interpret
    forms. The transport has no built-in operator/surface dispatch. }
  IFormExecutor = interface
    ['{2263A0F4-BE89-4BE1-9EC5-2CD18180DF11}']
    function Execute(const Node: TSourceNode; const Frame: IEnvFrame): RawByteString;
  end;

  TNativeSession = class
  private
    FExecutor: IFormExecutor;
    FFrame: IEnvFrame;
    FFormsSeen: QWord;
    FBusy: Boolean;
    function Failure(const MessageText: RawByteString;
      AOffset, ALine, AColumn: SizeInt): TSessionReplies;
  public
    constructor Create(const Executor: IFormExecutor);
    function Submit(const Source: RawByteString): TSessionReplies;
    function LoadFile(const Filename: String): TSessionReplies;
    function FormsSeen: QWord;
  end;

implementation

const
  MaxSessionSourceBytes = 16 * 1024 * 1024;
  MaxReplyBytes = 1024 * 1024;

constructor TNativeSession.Create(const Executor: IFormExecutor);
begin
  inherited Create;
  if Executor = nil then
    raise ESessionError.Create('missing form executor');
  FExecutor := Executor;
  FFrame := NewEnvFrame(nil);
  FFormsSeen := 0;
  FBusy := False;
end;

function TNativeSession.FormsSeen: QWord;
begin
  Result := FFormsSeen;
end;

function TNativeSession.Failure(const MessageText: RawByteString;
  AOffset, ALine, AColumn: SizeInt): TSessionReplies;
begin
  SetLength(Result, 1);
  Result[0].Ok := False;
  Result[0].Output := '';
  Result[0].Diagnostic := MessageText;
  Result[0].FormNumber := FFormsSeen;
  Result[0].ByteOffset := AOffset;
  Result[0].Line := ALine;
  Result[0].ByteColumn := AColumn;
end;

function TNativeSession.Submit(const Source: RawByteString): TSessionReplies;
var
  Doc: TSourceDocument;
  I: SizeInt;
  Value: RawByteString;
begin
  if FBusy then raise ESessionError.Create('reentrant session submission');
  FBusy := True;
  Doc := nil;
  try
    if Length(Source) > MaxSessionSourceBytes then begin
      Result := Failure('session input exceeds 16 MiB', 1, 1, 1);
      Exit;
    end;
    try
      Doc := ReadUkrainianSource(Source);
    except
      on E: ESourceError do begin
        Result := Failure(RawByteString(E.Message),
          E.ByteOffset, E.Line, E.ByteColumn);
        Exit;
      end;
    end;
    SetLength(Result, Length(Doc.Forms));
    for I := 0 to High(Doc.Forms) do begin
      if FFormsSeen = High(QWord) then
        raise ESessionError.Create('session form sequence overflow');
      Inc(FFormsSeen);
      Result[I].FormNumber := FFormsSeen;
      Result[I].ByteOffset := Doc.Forms[I].ByteOffset;
      Result[I].Line := Doc.Forms[I].Line;
      Result[I].ByteColumn := Doc.Forms[I].ByteColumn;
      Result[I].Output := '';
      Result[I].Diagnostic := '';
      Result[I].Ok := False;
      try
        Value := FExecutor.Execute(Doc.Forms[I], FFrame);
        if Length(Value) > MaxReplyBytes then
          raise ESessionError.Create('executor response exceeds 1 MiB');
        Result[I].Output := Value;
        Result[I].Ok := True;
      except
        on E: ESourceError do begin
          { Зберігаємо позицію справжньої помилки нижче в дереві AST,
            а не лише позицію початку верхньої форми. }
          Result[I].Diagnostic := RawByteString(E.Message);
          Result[I].ByteOffset := E.ByteOffset;
          Result[I].Line := E.Line;
          Result[I].ByteColumn := E.ByteColumn;
        end;
        on E: Exception do begin
          Result[I].Diagnostic := RawByteString(E.Message);
        end;
      end;
    end;
  finally
    Doc.Free;
    FBusy := False;
  end;
end;

function TNativeSession.LoadFile(const Filename: String): TSessionReplies;
var
  Input: TFileStream;
  Source: RawByteString;
begin
  if FBusy then raise ESessionError.Create('reentrant session file load');
  try
    Input := TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
    try
      if (Input.Size < 0) or (Input.Size > MaxSessionSourceBytes) then begin
        Result := Failure('session file exceeds 16 MiB', 1, 1, 1);
        Exit;
      end;
      SetLength(Source, SizeInt(Input.Size));
      if Length(Source) > 0 then Input.ReadBuffer(Source[1], Length(Source));
    finally
      Input.Free;
    end;
  except
    on E: Exception do begin
      Result := Failure(RawByteString('session file: ' + E.Message), 1, 1, 1);
      Exit;
    end;
  end;
  Result := Submit(Source);
end;

end.
