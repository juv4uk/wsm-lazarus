program test_faulttrace;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.debugtrace, wsm.faulttrace;

procedure Expect(Condition: Boolean; const Why: String);
begin
  if not Condition then
  begin
    WriteLn(StdErr, 'FAULTTRACE-FAIL ', Why);
    Halt(1);
  end;
end;

procedure InnerFault(Trace: TDebugTrace);
var Token: TDebugToken;
begin
  Token := Trace.Push(ExactKey('000'), 29, 3, 8);
  try
    raise EDebugFault.Capture(Trace, 0, 'physical fault');
  finally
    Trace.Pop(Token);
  end;
end;

procedure OuterFault(Trace: TDebugTrace);
var Token: TDebugToken;
begin
  Token := Trace.Push(ExactKey('0'), 10, 2, 3);
  try
    InnerFault(Trace);
  finally
    Trace.Pop(Token);
  end;
end;

var
  Trace, Other: TDebugTrace;
  Token, OtherToken: TDebugToken;
  F: TDebugFrame;
  Raised: Boolean;
  Detail: String;
begin
  Trace := TDebugTrace.Create;
  try
    { The error is raised inside a nested call stack. Every try/finally
      POP runs BEFORE the outer handler, but the captured frames survive. }
    Raised := False;
    try
      OuterFault(Trace);
    except
      on E: EDebugFault do
      begin
        Raised := True;
        Expect(Trace.Depth = 0, 'actual stack must unwind before handler');
        Expect(E.PhysicalFaultCode = 0, 'zero is legal opaque code');
        Expect(E.Message = 'physical fault', 'detail preserved');
        Expect(E.FrameCount = 2, 'fault captured two physical frames');
        Expect(SameKey(E.FrameAt(0).Key, ExactKey('0')),
          'D1 coordinate preserved in snapshot');
        Expect(SameKey(E.FrameAt(1).Key, ExactKey('000')),
          'D3 000 distinct from D1 0 in snapshot');
        Expect(E.FrameAt(1).ByteOffset = 29, 'byte offset preserved');
        Expect(Pos('#0 D3:000 byte=29 line=3 column=8'+#10,
          E.Backtrace) = 1, 'top-first rendered snapshot after unwind');
        Token := Trace.Push(ExactKey('1'), 90, 9, 9);
        F := E.FrameAt(1);
        F.ByteOffset := 1;
        Expect(E.FrameAt(1).ByteOffset = 29,
          'returned frame cannot mutate saved stack snapshot');
        Expect(E.FrameCount = 2, 'live stack growth must not affect snapshot');
        Trace.Pop(Token);
        Trace.Free;
        Trace := nil;
        Expect(E.FrameCount = 2, 'snapshot survives trace owner destruction');
        Expect(E.FrameAt(0).Line = 2,
          'frame position survives destruction');
        Expect(Pos('D1:0', E.Backtrace) > 0,
          'backtrace is independent of source trace lifetime');
        Raised := True;
      end;
    end;
    Expect(Raised, 'fault must propagate through nested finally');
  finally
    Trace.Free;
  end;

  Trace := TDebugTrace.Create;
  Other := TDebugTrace.Create;
  try
    Raised := False;
    try
      EDebugFault.Capture(nil, 12, 'missing');
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'missing trace must fail closed');

    Raised := False;
    try
      EDebugFault.Capture(Trace, 12, 'missing frame');
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'empty trace must fail closed');

    Token := Trace.Push(ExactKey('01'), 1, 1, 1);
    OtherToken := Other.Push(ExactKey('10'), 2, 1, 2);

    Raised := False;
    try
      EDebugFault.Capture(Trace, 12, '');
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'empty error detail must fail closed');

    Detail := StringOfChar('a', MaxFaultDetailBytes+1);
    Raised := False;
    try
      EDebugFault.Capture(Trace, 12, Detail);
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'oversized error detail must fail closed');

    Raised := False;
    try
      EDebugFault.Capture(Trace, 12, 'bad'+#10+'line');
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'newline injection must fail closed');

    Raised := False;
    try
      EDebugFault.Capture(Trace, 12, 'bad'+#0+'zero');
    except on E: EDebugFaultError do Raised := True; end;
    Expect(Raised, 'NUL injection must fail closed');

    try
      raise EDebugFault.Capture(Trace, High(QWord), 'saved');
    except
      on E: EDebugFault do
      begin
        Expect(E.PhysicalFaultCode = High(QWord),
          'opaque mechanism fault code must preserve full width');
        Raised := False;
        try F := E.FrameAt(-1);
        except on X: EDebugFaultError do Raised := True; end;
        Expect(Raised, 'negative snapshot index rejected');
        Raised := False;
        try F := E.FrameAt(1);
        except on X: EDebugFaultError do Raised := True; end;
        Expect(Raised, 'out of range snapshot index rejected');
        Expect(E.FrameCount = 1, 'separate physical trace snapshot count');
        Expect(Pos('D2:01', E.Backtrace) > 0, 'exact width formatting');
        Expect(Pos('D2:10', E.Backtrace) = 0,
          'other physical trace never leaks into snapshot');
      end;
    end;

    Trace.Pop(Token);
    Other.Pop(OtherToken);
    Expect(Trace.Depth = 0, 'source trace unaffected by bad captures');
    Expect(Other.Depth = 0, 'foreign trace unaffected');
    WriteLn('FAULTTRACE-OK nested-unwind=2 snapshot=independent ',
      'owner-destruction=survived domain-width=exact ',
      'missing=reject empty=reject oversized=reject ',
      'newline=reject null=reject index=reject ',
      'SENS-semantics=NOT_ASSERTED');
  finally
    Trace.Free;
    Other.Free;
  end;
end.
