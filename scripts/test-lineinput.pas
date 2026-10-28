{ G5.2 line buffering tests. An injected SYNTHETIC executor verifies session
  mechanics only; none of its spellings or outputs define SENS semantics. }
program test_lineinput;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.lineinput, wsm.session, wsm.source,
     wsm.envframe, wsm.domain;

function Bytes(const S: UnicodeString): RawByteString;
begin Result := RawByteString(UTF8Encode(S)); end;

type
  TProbe = class(TInterfacedObject, IFormExecutor)
  public
    Calls: SizeInt;
    function Execute(const Node: TSourceNode;
      const Frame: IEnvFrame): RawByteString;
  end;

function TProbe.Execute(const Node: TSourceNode;
  const Frame: IEnvFrame): RawByteString;
var K: TDomainKey;
begin
  Inc(Calls);
  K := ExactKey('0101'); { opaque test coordinate, NOT SENS domain law }
  if Node.Kind = skList then
    Exit('synthetic-list-' + IntToStr(Length(Node.Children)));
  if Node.Kind = skString then Exit('synthetic-string');
  if Node.Kind <> skAtom then raise Exception.Create('unexpected probe node');
  if Node.Text = Bytes('записати') then begin
    Frame.InstallLocal(K, 73);
    Exit('stored');
  end;
  if Node.Text = Bytes('читати') then begin
    if Frame.Resolve(K) <> 73 then
      raise Exception.Create('synthetic frame mismatch');
    Exit('73');
  end;
  if Node.Text = Bytes('помилка') then
    raise Exception.Create('synthetic executor rejection');
  raise Exception.Create('unsupported test-only atom');
end;

procedure Check(V: Boolean; const Why: String);
begin
  if not V then begin
    WriteLn(StdErr, 'LINEINPUT-FAIL ', Why);
    Halt(1);
  end;
end;

procedure CheckFailure(const R: TSessionReplies; const Needle: String);
begin
  Check(Length(R) = 1, 'missing failed reply');
  Check(not R[0].Ok, 'negative input accepted');
  Check(R[0].Output = '', 'failed form returned a value');
  Check(Pos(Needle, String(R[0].Diagnostic)) <> 0,
    'unexpected negative diagnostic: ' + String(R[0].Diagnostic));
end;

var
  Session: TNativeSession;
  Executor: IFormExecutor;
  Probe: TProbe;
  Input, Small: TLineInput;
  R: TSessionReplies;
  Invalid, CommentLine: RawByteString;
  I: SizeInt;
  Failed: Boolean;
begin
  Failed := False;
  try
    Small := TLineInput.Create(nil);
  except on E: ELineInputError do Failed := True; end;
  Check(Failed, 'missing session accepted');

  Probe := TProbe.Create;
  Executor := Probe;
  Session := TNativeSession.Create(Executor);
  Input := TLineInput.Create(Session);
  try
    R := Input.FeedLine(Bytes('; коментар: ) ( "'));
    Check((Length(R)=0) and (Input.PendingBytes=0),
      'comment-only line did not close without execution');

    R := Input.FeedLine(Bytes('записати'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='stored'),
      'initial injected executor invocation');
    Check(Session.FormsSeen=1, 'first form sequence');

    R := Input.FeedLine(Bytes('(тест ; коментар із ) і "'));
    Check((Length(R)=0) and (Input.PendingBytes>0),
      'premature dispatch of incomplete list');
    R := Input.FeedLine(Bytes(' "рядок із ) та ; і \"лапками\""'));
    Check((Length(R)=0) and (Input.PendingBytes>0),
      'string punctuation incorrectly ended list');
    R := Input.FeedLine(')');
    Check((Length(R)=1) and R[0].Ok and
      (R[0].Output='synthetic-list-2'),
      'multiline bounded list not forwarded as a single form');
    Check((Session.FormsSeen=2) and (Input.PendingBytes=0),
      'multiline form count/buffer');

    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='73'),
      'persistent lexical frame across multiline submission');
    R := Input.FeedLine(Bytes('помилка'));
    CheckFailure(R, 'synthetic executor rejection');
    R := Input.FeedLine(Bytes('читати читати'));
    Check((Length(R)=2) and R[0].Ok and R[1].Ok and
      (R[0].Output='73') and (R[1].Output='73'),
      'ordered multiple forms on one physical line');
    Check(Session.FormsSeen=6, 'failed executor should still count a form');

    R := Input.FeedLine(Bytes('"багато'));
    Check((Length(R)=0) and (Input.PendingBytes>0),
      'multiline string submitted before closing quote');
    R := Input.FeedLine(Bytes('рядків"'));
    Check((Length(R)=1) and R[0].Ok and
      (R[0].Output='synthetic-string'),
      'continued quoted string was not submitted');

    R := Input.FeedLine(Bytes('(читати'));
    Check(Length(R)=0, 'incomplete EOF fixture executed prematurely');
    R := Input.Finish;
    CheckFailure(R, 'unclosed list');
    Check(Input.PendingBytes=0, 'EOF did not release pending bytes');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='73'),
      'EOF parse error poisoned next line');

    R := Input.FeedLine(Bytes('(читати'));
    Check(Length(R)=0, 'cancel fixture executed');
    Input.Cancel;
    Check(Input.PendingBytes=0, 'cancel left pending input');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok, 'cancel affected subsequent session');

    R := Input.FeedLine(')');
    CheckFailure(R, 'unexpected closing parenthesis');
    R := Input.FeedLine(')(');
    CheckFailure(R, 'unexpected closing parenthesis');
    R := Input.FeedLine(Bytes('"незакритий'));
    Check(Length(R)=0, 'unterminated string executed prematurely');
    R := Input.Finish;
    CheckFailure(R, 'unterminated string');

    Invalid := AnsiChar($C0);
    R := Input.FeedLine(Invalid);
    CheckFailure(R, 'UTF-8 leading byte');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok, 'UTF-8 negative poisoned session');

    Failed := False;
    try
      R := Input.FeedLine(Bytes('неправильно') + #10 + Bytes('читати'));
    except on E: ELineInputError do Failed := True; end;
    Check(Failed and (Input.PendingBytes=0), 'embedded newline was admitted');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok, 'invalid line poisoned session');

    Small := TLineInput.Create(Session, 32);
    try
      Failed := False;
      try
        R := Small.FeedLine(Bytes('(') + StringOfChar('a', 32));
      except on E: ELineInputError do Failed := True; end;
      Check(Failed and (Small.PendingBytes=0),
        'buffer limit not enforced or not reset');
      R := Small.FeedLine(Bytes('читати'));
      Check((Length(R)=1) and R[0].Ok,
        'bounded buffer error poisoned session');

      { Місткість не дорівнює логічній довжині; 31 з 32 байтів — допустимо. }
      R := Small.FeedLine('(');
      Check((Length(R)=0) and (Small.PendingBytes=2),
        'reserved capacity appeared as pending source');
      for I := 1 to 13 do begin
        R := Small.FeedLine(';');
        Check(Length(R)=0, 'comment prematurely submitted buffered list');
      end;
      Check(Small.PendingBytes=28, 'logical length after 13 lines');
      R := Small.FeedLine('1)');
      Check((Length(R)=1) and R[0].Ok and
        (R[0].Output='synthetic-list-1') and (Small.PendingBytes=0),
        'source of 31 bytes was not submitted exactly');

      { Рівно 32 байти — за попереднім строгим правилом відмова. }
      R := Small.FeedLine('(');
      for I := 1 to 14 do R := Small.FeedLine(';');
      Check(Small.PendingBytes=30, 'pending bytes before exact boundary');
      Failed := False;
      try R := Small.FeedLine(')');
      except on E: ELineInputError do Failed := True; end;
      Check(Failed and (Small.PendingBytes=0),
        'equal-to-limit input was admitted or left pending bytes');
      R := Small.FeedLine(Bytes('читати'));
      Check((Length(R)=1) and R[0].Ok and (R[0].Output='73'),
        'exact-limit failure poisoned stored frame');
    finally Small.Free; end;

    R := Input.FeedLine(StringOfChar('(', 256));
    Check(Length(R)=0, '256 levels prematurely executed');
    Failed := False;
    try R := Input.FeedLine('(');
    except on E: ELineInputError do Failed := True; end;
    Check(Failed and (Input.PendingBytes=0), 'nesting bound not enforced');

    { Регресія: '\' на фізичному кінці рядка екранує вставлений LF,
      а не наступну лапку. Попередній фреймер НЕ відправляв закриту форму. }
    R := Input.FeedLine(Bytes('("рядок\'));
    Check((Length(R)=0) and (Input.PendingBytes>0),
      'physical escaped newline submitted too early');
    R := Input.FeedLine('")');
    Check((Length(R)=1) and R[0].Ok and
      (R[0].Output='synthetic-list-1'),
      'escaped newline consumed quote of next physical line');
    Check(Input.PendingBytes=0,'completed escaped-newline buffer not cleared');

    { EOF після escaped LF без завершальної лапки лишається відмовою;
      наступна команда та той самий лексичний frame мають зберегтися. }
    R := Input.FeedLine(Bytes('"незакритий\'));
    Check(Length(R)=0,'unterminated escape submitted before EOF');
    R := Input.Finish;
    CheckFailure(R,'unterminated string');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='73'),
      'escaped newline EOF poisoned persistent session');

    { Тисячі фізичних рядків не мають змушувати виконувати незавершену
      форму; перевіряємо точні байтові межі після багатьох розширень. }
    CommentLine := Bytes('; накопичення без зміни форми');
    R := Input.FeedLine('(');
    Check((Length(R)=0) and (Input.PendingBytes=2),
      'long multiline initial framing');
    for I := 1 to 8192 do begin
      R := Input.FeedLine(CommentLine);
      Check(Length(R)=0, 'long multiline prematurely executed');
      if I mod 2048 = 0 then
        Check(Input.PendingBytes=2 + I*(Length(CommentLine)+1),
          'long multiline exposed padding/capacity bytes');
    end;
    R := Input.FeedLine('1)');
    Check((Length(R)=1) and R[0].Ok and
      (R[0].Output='synthetic-list-1') and (Input.PendingBytes=0),
      'long multiline source did not submit exactly once');
    R := Input.FeedLine(Bytes('читати'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='73'),
      'long multiline submit lost persistent lexical environment');

    R := Input.Finish;
    Check(Length(R)=0, 'empty EOF produced invented output');
    Check(Probe.Calls = Session.FormsSeen, 'synthetic callback count differs');
    WriteLn('LINEINPUT-OK multiline=buffered utf8=strict ',
      'quoted=preserved comments=ignored recovery=1 ',
      'session-frame=persistent synthetic-executor=YES ',
      'sens-repl=NOT_IMPLEMENTED core4-execution=NOT_PROVEN');
  finally
    Input.Free;
    Session.Free;
    Executor := nil;
  end;
end.
