program test_debugtrace;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.debugtrace;

procedure Expect(Condition: Boolean; const Why: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'DEBUGTRACE-FAIL ', Why);
    Halt(1);
  end;
end;

var
  A, B: TDebugTrace;
  First, Second, Foreign: TDebugToken;
  StackTokens: array[1..MaxTraceDepth] of TDebugToken;
  Frames: TDebugFrames;
  Text: RawByteString;
  Raised: Boolean;
  I: Integer;
  Bad: TDomainKey;
begin
  A := TDebugTrace.Create;
  B := TDebugTrace.Create;
  try
    First := A.Push(ExactKey('1'), 1, 1, 1);
    Second := A.Push(ExactKey('001'), 21, 2, 4);
    Expect(A.Depth=2, 'stack depth');
    Frames := A.Snapshot;
    Expect(Length(Frames)=2, 'snapshot count');
    Expect(SameKey(Frames[0].Key, ExactKey('1')), 'first width/key');
    Expect(SameKey(Frames[1].Key, ExactKey('001')), 'second width/key');
    Expect(Frames[1].ByteOffset=21, 'source offset');
    Frames[1].ByteOffset := 999;
    Expect(A.Snapshot[1].ByteOffset=21, 'snapshot must not modify active frame');

    Text := A.Backtrace;
    Expect(Pos('#0 D3:001 byte=21 line=2 column=4'+#10,Text)=1,
      'top frame ordered first, exact bytes/position');
    Expect(Pos('#1 D1:1 byte=1 line=1 column=1'+#10,Text)>0,
      'parent frame exact width');

    Raised := False;
    try A.Pop(First); except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'non-LIFO pop rejected');
    Expect(A.Depth=2, 'invalid pop cannot mutate stack');

    Foreign := B.Push(ExactKey('01'), 5, 1, 5);
    Raised := False;
    try A.Pop(Foreign); except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'cross-trace token rejected');

    A.Pop(Second);
    Raised := False;
    try A.Pop(Second); except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'replayed/stale token rejected');

    A.Pop(First);
    Expect(A.Depth=0, 'stack drained');
    Expect(A.Backtrace='', 'empty backtrace');
    Raised := False;
    try A.Pop(First); except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'empty stack underflow rejected');

    Bad.Width := 0;
    Bad.Bits := 0;
    Raised := False;
    try First := A.Push(Bad,1,1,1);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'zero-width coordinate rejected');

    Bad.Width := 2;
    Bad.Bits := 4;
    Raised := False;
    try First := A.Push(Bad,1,1,1);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'out-of-range physical bits rejected');

    Raised := False;
    try First := A.Push(ExactKey('10'), 0,1,1);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'zero byte offset rejected');
    Raised := False;
    try First := A.Push(ExactKey('10'), 1,0,1);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'zero line rejected');
    Raised := False;
    try First := A.Push(ExactKey('10'), 1,1,0);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'zero byte column rejected');

    for I := 1 to MaxTraceDepth do
      StackTokens[I] := A.Push(ExactKey('10'), I,1,I);
    Expect(A.Depth=MaxTraceDepth, 'maximum allowed depth');
    Raised := False;
    try First := A.Push(ExactKey('10'),129,1,129);
    except on E: EDebugTraceError do Raised:=True; end;
    Expect(Raised, 'stack capacity limit rejected');
    Expect(A.Depth=MaxTraceDepth, 'over-capacity leaves stack unchanged');
    for I := MaxTraceDepth downto 1 do
      A.Pop(StackTokens[I]);
    Expect(A.Depth=0, 'bounded nested frames unwind');

    B.Pop(Foreign);
    Expect(B.Depth=0, 'foreign owner not mutated');
    WriteLn('DEBUGTRACE-OK frames=128 snapshot=independent ',
      'positions=exact owner=GUID nonlifo=reject stale=reject ',
      'crossstack=reject overflow=reject semantics=NOT_ASSERTED');
  finally
    A.Free;
    B.Free;
  end;
end.
