{ G5.3 physical byte-transport tests, not SENS semantic witness. }
program test_sessionwire;
{$mode objfpc}{$H+}
{$codepage utf8}
uses SysUtils, wsm.session, wsm.sessionwire, wsm.source,
     wsm.envframe, wsm.domain;

function SourceBytes(const Text: UnicodeString): RawByteString;
begin Result := RawByteString(UTF8Encode(Text)); end;

type
  TProbe = class(TInterfacedObject, IFormExecutor)
    function Execute(const Node: TSourceNode; const Frame: IEnvFrame): RawByteString;
  end;

function TProbe.Execute(const Node: TSourceNode; const Frame: IEnvFrame): RawByteString;
var Key: TDomainKey;
begin
  if Node.Kind <> skAtom then
    raise Exception.Create('test-only expects atom');
  Key := ExactKey('0101');
  if Node.Text = SourceBytes('записати') then begin
    Frame.InstallLocal(Key, 77);
    Result := 'stored';
  end else if Node.Text = SourceBytes('читати') then begin
    if Frame.Resolve(Key) <> 77 then
      raise Exception.Create('lost lexical container');
    Result := '77';
  end else if Node.Text = SourceBytes('помилка') then
    raise Exception.Create('test-only failure')
  else
    raise Exception.Create('test-only unknown atom');
end;

procedure Check(const Yes: Boolean; const Detail: String);
begin
  if not Yes then begin
    WriteLn(StdErr,'SESSIONWIRE-FAIL ', Detail);
    Halt(1);
  end;
end;

function Pack(const Payload: RawByteString): RawByteString;
var N: LongWord;
begin
  N := Length(Payload);
  SetLength(Result, Length(Payload) + 4);
  Result[1] := AnsiChar(N and $FF);
  Result[2] := AnsiChar((N shr 8) and $FF);
  Result[3] := AnsiChar((N shr 16) and $FF);
  Result[4] := AnsiChar((N shr 24) and $FF);
  if N > 0 then Move(Payload[1], Result[5], N);
end;

function BadLengthHeader(const N: LongWord): RawByteString;
begin
  SetLength(Result, 4);
  Result[1] := AnsiChar(N and $FF);
  Result[2] := AnsiChar((N shr 8) and $FF);
  Result[3] := AnsiChar((N shr 16) and $FF);
  Result[4] := AnsiChar((N shr 24) and $FF);
end;

procedure ExpectFault(const Wire: TSessionWire; const Bytes: RawByteString;
                      const Why: String);
var Rejected: Boolean;
begin
  Rejected := False;
  try Wire.Feed(Bytes); except on E:EWireError do Rejected := True; end;
  Check(Rejected, Why);
end;

procedure ExpectEofFault(const Wire: TSessionWire; const Why: String);
var Rejected: Boolean;
begin
  Rejected := False;
  try Wire.Finish; except on E:EWireError do Rejected := True; end;
  Check(Rejected and Wire.IsBroken and Wire.IsClosed, Why);
end;

{ G5.4: обмеження черги — лише фізичні механізми, без законів мови.
  Переповнений пакет не має викликати Execute чи міняти лексичний frame. }
procedure TestBoundedQueue;
var
  Executor: IFormExecutor;
  Session: TNativeSession;
  Wire: TSessionWire;
  Replies: TWireBatches;
  Rejected: Boolean;
begin
  Executor:=TProbe.Create;
  Session:=TNativeSession.Create(Executor);
  try
    Rejected:=False;
    try Wire:=TSessionWire.Create(Session,0);
    except on E:EWireError do Rejected:=True; end;
    Check(Rejected,'нульова межа черги прийнята');
    Rejected:=False;
    try Wire:=TSessionWire.Create(Session,MaxConfiguredBatches+1);
    except on E:EWireError do Rejected:=True; end;
    Check(Rejected,'надмірна межа черги прийнята');

    Wire:=TSessionWire.Create(Session,2);
    try
      Wire.Feed(Pack(SourceBytes('записати'))+
                Pack(SourceBytes('читати')));
      Check((Wire.PendingBatches=2) and (Wire.PacketCount=2) and
        (Session.FormsSeen=2),'лічильник перед переповненням');

      Rejected:=False;
      try Wire.Feed(Pack(SourceBytes('помилка')));
      except on E:EWireError do Rejected:=True; end;
      Check(Rejected and Wire.IsBroken,'переповнення не заблокувало потік');
      Check((Wire.PendingBatches=2) and (Wire.PacketCount=2) and
        (Session.FormsSeen=2),
        'переповнений пакет був виконаний або знищив чергу');
      Rejected:=False;
      try Wire.Feed(Pack(SourceBytes('читати')));
      except on E:EWireError do Rejected:=True; end;
      Check(Rejected,'пошкоджений потік приймає наступні пакети');

      Replies:=Wire.Drain;
      Check((Length(Replies)=2) and (Length(Replies[0])=1) and
        (Length(Replies[1])=1) and Replies[0][0].Ok and
        Replies[1][0].Ok and (Replies[0][0].Output='stored') and
        (Replies[1][0].Output='77'),'FIFO втрачено після відмови');
      Check(Wire.PendingBatches=0,'Drain не звільнив чергу');

      Wire.Reset;
      Check(not Wire.IsBroken and not Wire.IsClosed,
        'скидання не відновило обмежений приймач');
      Wire.Feed(Pack(SourceBytes('читати')));
      Replies:=Wire.Drain;
      Check((Length(Replies)=1) and (Length(Replies[0])=1) and
        Replies[0][0].Ok and (Replies[0][0].Output='77') and
        (Session.FormsSeen=3),'скидання втратило постійне середовище');
      Check(Wire.PacketCount=3,'заблокований пакет увійшов до лічильника');

      { Порожній payload теж займає місце в черзі результатів. }
      Wire.Feed(Pack('')+Pack(''));
      Check(Wire.PendingBatches=2,'порожні пакети оминули квоту');
      Rejected:=False;
      try Wire.Feed(Pack(''));
      except on E:EWireError do Rejected:=True; end;
      Check(Rejected and (Wire.PacketCount=5) and
        (Session.FormsSeen=3),'порожній пакет обійшов обмеження');
      Replies:=Wire.Drain;
      Check((Length(Replies)=2) and (Length(Replies[0])=0) and
        (Length(Replies[1])=0),'порожні відповіді втрачено');
      WriteLn('SESSIONWIRE-QUEUE-OK межа=2 відмова=так ',
        'FIFO=збережено зайві-форми=0');
    finally Wire.Free; end;
  finally Session.Free; end;
end;

var
  Executor: IFormExecutor;
  Session: TNativeSession;
  Wire: TSessionWire;
  V, First, Second: RawByteString;
  Responses: TWireBatches;
  N: SizeInt;
  Rejected: Boolean;
begin
  Rejected := False;
  try Wire := TSessionWire.Create(nil);
  except on E:EWireError do Rejected := True; end;
  Check(Rejected,'nil session admitted');

  Executor := TProbe.Create;
  Session := TNativeSession.Create(Executor);
  try
    Wire := TSessionWire.Create(Session);
    try
      V := Pack(SourceBytes('записати'));
      Wire.Feed(Copy(V,1,2));
      Check(Length(Wire.Drain)=0, 'incomplete header delivered');
      Wire.Feed(Copy(V,3,3)); { header remainder + one UTF-8 byte }
      Check(Length(Wire.Drain)=0, 'fragmented UTF-8 delivered');
      Wire.Feed(Copy(V,6,Length(V)-5));
      Responses := Wire.Drain;
      Check((Length(Responses)=1) and (Length(Responses[0])=1) and
        Responses[0][0].Ok and (Responses[0][0].Output='stored'),
        'split header / payload did not dispatch correctly');

      First := Pack(SourceBytes('читати'));
      Second := Pack(SourceBytes('помилка читати'));
      Wire.Feed(First+Second);
      Responses := Wire.Drain;
      Check((Length(Responses)=2) and (Length(Responses[0])=1) and
        (Length(Responses[1])=2), 'multiple packets batch lost');
      Check(Responses[0][0].Ok and (Responses[0][0].Output='77'),
        'persistent lexical environment lost');
      Check((not Responses[1][0].Ok) and Responses[1][1].Ok and
        (Responses[1][1].Output='77'), 'executor failure poisoned next item');
      Check((Responses[0][0].FormNumber=2) and
        (Responses[1][0].FormNumber=3) and
        (Responses[1][1].FormNumber=4), 'session form ordinals diverged');
      Check(Wire.PacketCount=3,'packets not accounted');

      Wire.Feed(Pack('')); { valid empty transport packet, no source expressions }
      Responses := Wire.Drain;
      Check((Length(Responses)=1) and (Length(Responses[0])=0),
        'empty message invented expression');
      Wire.Feed(Pack(SourceBytes('(незакрите'))+Pack(SourceBytes('читати')));
      Responses := Wire.Drain;
      Check((Length(Responses)=2) and (Length(Responses[0])=1) and
        not Responses[0][0].Ok and Responses[1][0].Ok,
        'bad syntax did not recover at next framed packet');

      { Valid completed packet must survive a subsequent invalid header. }
      Wire.Feed(Pack(SourceBytes('читати')));
      ExpectFault(Wire, BadLengthHeader(MaxWirePayload+1),
        'oversized length was admitted');
      Check(Wire.IsBroken, 'invalid length did not poison decoder');
      Responses := Wire.Drain;
      Check((Length(Responses)=1) and Responses[0][0].Ok and
        (Responses[0][0].Output='77'), 'queued good reply lost on fault');
      ExpectFault(Wire, Pack(SourceBytes('читати')),
        'broken decoder accepted more data');
      Wire.Reset;
      Check(not Wire.IsBroken and not Wire.IsClosed,
        'reset did not restore transport state');
      Wire.Feed(Pack(SourceBytes('читати')));
      Responses := Wire.Drain;
      Check((Length(Responses)=1) and Responses[0][0].Ok,
        'reset destroyed session lexical frame');

      V := Pack(SourceBytes('читати'));
      Wire.Feed(Copy(V,1,1));
      ExpectEofFault(Wire, 'truncated one-byte header at EOF admitted');
      Wire.Reset;
      Wire.Feed(Copy(V,1,Length(V)-1));
      ExpectEofFault(Wire, 'truncated UTF-8 payload at EOF admitted');
      Wire.Reset;
      Wire.Feed(Pack(SourceBytes('читати')));
      Wire.Finish;
      Check(Wire.IsClosed and not Wire.IsBroken, 'complete EOF rejected');
      ExpectFault(Wire, Pack(SourceBytes('читати')),
        'post-EOF data was admitted');

      Check(Session.FormsSeen=8, 'transport EOF or errors invented expressions');
      WriteLn('SESSIONWIRE-OK split-header=1 split-utf8=1 forms=8 ',
        'ordered=1 eof=reject oversize=reject recovery=1 ',
        'semantic-eval=NOT_IMPLEMENTED');
    finally Wire.Free; end;
  finally Session.Free; end;
  TestBoundedQueue;
end.
