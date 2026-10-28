{ G7.3: physical backtrace mechanism, NOT SENS semantic dispatch.
  Frame coordinates originate upstream; neither width nor bits alone grant
  a language law. No function spelling, host boolean or SID8 identity. }
unit wsm.debugtrace;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain;

const
  MaxTraceDepth = 128;

type
  EDebugTraceError = class(Exception);
  TDebugToken = record
    Owner: TGUID;
    Serial: QWord;
  end;
  TDebugFrame = record
    Key: TDomainKey;
    ByteOffset, Line, ByteColumn: SizeInt;
    Token: TDebugToken;
  end;
  TDebugFrames = array of TDebugFrame;

  TDebugTrace = class
  private
    FOwner: TGUID;
    FNextSerial: QWord;
    FFrames: TDebugFrames;
  public
    constructor Create;
    function Push(const Key: TDomainKey;
      ByteOffset, Line, ByteColumn: SizeInt): TDebugToken;
    procedure Pop(const Token: TDebugToken);
    function Snapshot: TDebugFrames;
    function Backtrace: RawByteString;
    function Depth: SizeInt;
  end;

implementation

constructor TDebugTrace.Create;
begin
  inherited Create;
  if CreateGUID(FOwner) <> 0 then
    raise EDebugTraceError.Create('cannot establish trace owner identity');
  FNextSerial := 0;
  SetLength(FFrames, 0);
end;

function TDebugTrace.Push(const Key: TDomainKey;
  ByteOffset, Line, ByteColumn: SizeInt): TDebugToken;
var
  Bits: RawByteString;
  N: SizeInt;
begin
  try
    Bits := KeyBits(Key);
  except
    on E: EDomainError do
      raise EDebugTraceError.Create('invalid exact domain coordinate');
  end;
  if Bits = '' then
    raise EDebugTraceError.Create('empty exact domain coordinate');
  if (ByteOffset < 1) or (Line < 1) or (ByteColumn < 1) then
    raise EDebugTraceError.Create('source positions must be 1-based positive bytes');
  if Length(FFrames) >= MaxTraceDepth then
    raise EDebugTraceError.Create('physical debug frame depth limit exceeded');
  if FNextSerial = High(QWord) then
    raise EDebugTraceError.Create('debug frame serial exhausted');
  Inc(FNextSerial);
  Result.Owner := FOwner;
  Result.Serial := FNextSerial;
  N := Length(FFrames);
  SetLength(FFrames, N+1);
  FFrames[N].Key := Key;
  FFrames[N].ByteOffset := ByteOffset;
  FFrames[N].Line := Line;
  FFrames[N].ByteColumn := ByteColumn;
  FFrames[N].Token := Result;
end;

procedure TDebugTrace.Pop(const Token: TDebugToken);
var
  N: SizeInt;
begin
  N := Length(FFrames);
  if N = 0 then
    raise EDebugTraceError.Create('debug trace stack underflow');
  if (not CompareMem(@Token.Owner, @FOwner, SizeOf(TGUID))) or
     (Token.Serial = 0) or
     (Token.Serial <> FFrames[N-1].Token.Serial) then
    raise EDebugTraceError.Create('non-LIFO or foreign/stale debug frame token');
  SetLength(FFrames, N-1);
end;

function TDebugTrace.Snapshot: TDebugFrames;
begin
  { Copy creates a separate dynamic-array index buffer: readers cannot mutate
    the stack by editing a snapshot. Record keys/positions remain physical. }
  Result := Copy(FFrames, 0, Length(FFrames));
end;

function TDebugTrace.Depth: SizeInt;
begin
  Result := Length(FFrames);
end;

function TDebugTrace.Backtrace: RawByteString;
var
  I: SizeInt;
  Frame: TDebugFrame;
begin
  Result := '';
  for I := High(FFrames) downto 0 do
  begin
    Frame := FFrames[I];
    Result := Result + '#' + IntToStr(High(FFrames)-I) +
      ' D' + IntToStr(Frame.Key.Width) + ':' + KeyBits(Frame.Key) +
      ' byte=' + IntToStr(Frame.ByteOffset) +
      ' line=' + IntToStr(Frame.Line) +
      ' column=' + IntToStr(Frame.ByteColumn) + #10;
  end;
end;
end.
