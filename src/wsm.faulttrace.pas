{ G7.6: physical debugger fault snapshots for native SENS substrate.
  No SENS condition laws, callable status, host-name dispatch or Core4 semantics.
  Caller-supplied numeric fault codes are opaque diagnostics only.
  The snapshot is captured at the throw site, BEFORE the frame stack unwinds. }
unit wsm.faulttrace;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.debugtrace;

const
  MaxFaultDetailBytes = 1024;

type
  EDebugFaultError = class(Exception);
  EDebugFault = class(Exception)
  private
    FCode: QWord;
    FFrames: TDebugFrames;
    FTraceText: RawByteString;
  public
    constructor Capture(const Trace: TDebugTrace; FaultCode: QWord;
      const Detail: String);
    function FrameCount: SizeInt;
    function FrameAt(Index: SizeInt): TDebugFrame;
    function Backtrace: RawByteString;
    function UkrainskyiStek: RawByteString;
    property PhysicalFaultCode: QWord read FCode;
  end;

implementation
uses wsm.uktrace;

constructor EDebugFault.Capture(const Trace: TDebugTrace; FaultCode: QWord;
  const Detail: String);
begin
  if Trace = nil then
    raise EDebugFaultError.Create('missing physical trace');
  if Trace.Depth = 0 then
    raise EDebugFaultError.Create('cannot capture fault without a physical frame');
  if (Length(Detail) = 0) or (Length(Detail) > MaxFaultDetailBytes) then
    raise EDebugFaultError.Create('invalid physical fault detail length');
  if (Pos(#0, Detail) <> 0) or (Pos(#10, Detail) <> 0) or
     (Pos(#13, Detail) <> 0) then
    raise EDebugFaultError.Create('physical fault detail contains control bytes');
  inherited Create(Detail);
  FCode := FaultCode;
  { Snapshot() creates a separate dynamic array; old FPC frame tokens
    and byte positions survive future Pop(), mutation and trace Free(). }
  FFrames := Trace.Snapshot;
  FTraceText := Trace.Backtrace;
end;

function EDebugFault.FrameCount: SizeInt;
begin
  Result := Length(FFrames);
end;

function EDebugFault.FrameAt(Index: SizeInt): TDebugFrame;
begin
  if (Index < 0) or (Index >= Length(FFrames)) then
    raise EDebugFaultError.Create('fault frame index outside snapshot');
  Result := FFrames[Index];
end;

function EDebugFault.Backtrace: RawByteString;
begin
  Result := FTraceText;
end;
function EDebugFault.UkrainskyiStek: RawByteString;
begin
  Result := PodanniaSteka(FFrames);
end;
end.
