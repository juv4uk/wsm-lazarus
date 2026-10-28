{ G5.1 mechanical session tests. Synthetic executor is NOT SENS language logic. }
program test_session;
{$mode objfpc}{$H+}
{$codepage utf8}
uses SysUtils, Classes, wsm.session, wsm.source, wsm.envframe, wsm.domain;

type
  TProbeExecutor = class(TInterfacedObject, IFormExecutor)
  public
    function Execute(const Form: TSourceNode; const Frame: IEnvFrame): RawByteString;
  end;

function TProbeExecutor.Execute(const Form: TSourceNode;
  const Frame: IEnvFrame): RawByteString;
var Key: TDomainKey;
begin
  if Form.Kind <> skAtom then
    raise ESessionError.Create('test-only executor requires atom');
  Key := ExactKey('0101'); { opaque physical test coordinate, no SENS law }
  if Form.Text = 'записати' then begin
    Frame.InstallLocal(Key, 42);
    Result := 'stored';
  end else if Form.Text = 'читати' then begin
    if Frame.Resolve(Key) <> 42 then
      raise ESessionError.Create('stored host handle mismatch');
    Result := '42';
  end else if Form.Text = 'помилка' then
    raise ESessionError.Create('test-only rejected form')
  else if Form.Text = 'велике' then
    Result := RawByteString(StringOfChar('X', 1024*1024+1))
  else
    raise ESessionError.Create('test-only unknown form');
end;

procedure Check(const Condition: Boolean; const LabelText: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'SESSION-FAIL ', LabelText);
    Halt(1);
  end;
end;

var
  Session: TNativeSession;
  Executor: IFormExecutor;
  Replies: TSessionReplies;
  F: TFileStream;
  Filename: String;
  FailNil: Boolean;
begin
  FailNil := False;
  try
    Session := TNativeSession.Create(nil);
  except
    on E: ESessionError do FailNil := True;
  end;
  Check(FailNil, 'missing executor accepted');

  Executor := TProbeExecutor.Create;
  Session := TNativeSession.Create(Executor);
  try
    Replies := Session.Submit('записати читати');
    Check(Length(Replies)=2, 'two forms in a single batch');
    Check(Replies[0].Ok and (Replies[0].Output='stored'),
      'synthetic write callback not invoked');
    Check(Replies[1].Ok and (Replies[1].Output='42'),
      'persistent frame not shared between forms');
    Check((Replies[0].FormNumber=1) and (Replies[1].FormNumber=2),
      'per-form ordinals');

    Replies := Session.Submit('помилка читати');
    Check((Length(Replies)=2) and not Replies[0].Ok and Replies[1].Ok,
      'failed executor poisoned following form');
    Check((Replies[0].Diagnostic='test-only rejected form') and
      (Replies[1].Output='42'), 'diagnostic/recovery mismatch');

    Replies := Session.Submit('записати читати');
    Check((Length(Replies)=2) and not Replies[0].Ok and Replies[1].Ok,
      'duplicate binding did not fail closed');
    Check(Replies[1].Output='42', 'failed redefinition corrupted binding');

    Replies := Session.Submit('(читати');
    Check((Length(Replies)=1) and not Replies[0].Ok,
      'incomplete source unexpectedly admitted');
    Check((Replies[0].Line>0) and (Replies[0].ByteColumn>0),
      'source position missing');
    Replies := Session.Submit('читати');
    Check((Length(Replies)=1) and Replies[0].Ok and
      (Replies[0].Output='42'), 'session did not recover after parse failure');

    Replies := Session.Submit(RawByteString(AnsiChar($C0)));
    Check((Length(Replies)=1) and not Replies[0].Ok and
      (Replies[0].Diagnostic<>''), 'invalid UTF-8 admitted');
    Replies := Session.Submit('читати'+#0);
    Check((Length(Replies)=1) and not Replies[0].Ok,
      'embedded NUL admitted');
    Replies := Session.Submit('велике читати');
    Check((Length(Replies)=2) and not Replies[0].Ok and Replies[1].Ok,
      'oversized executor result did not fail closed');

    Replies := Session.Submit('; тільки коментар'+#10);
    Check(Length(Replies)=0, 'comment unexpectedly executed');
    Check(Session.FormsSeen=9, 'unexpected form count after parse failures');

    Filename := GetTempFileName(GetTempDir(False), 'sens-session-');
    try
      F := TFileStream.Create(Filename, fmCreate);
      try
        F.WriteBuffer('читати'[1], Length('читати'));
      finally
        F.Free;
      end;
      Replies := Session.LoadFile(Filename);
      Check((Length(Replies)=1) and Replies[0].Ok and
        (Replies[0].Output='42'), 'file+session environment lost');
    finally
      if FileExists(Filename) then DeleteFile(Filename);
    end;

    Replies := Session.LoadFile(Filename);
    Check((Length(Replies)=1) and not Replies[0].Ok and
      (Replies[0].Diagnostic<>''), 'missing input file admitted');
    Check(Session.FormsSeen=10, 'file failures incremented form count');
    Check((Replies[0].Output=''), 'error produced a fake value');
    WriteLn('SESSION-TEST-OK forms=10 error-recovery=1 lexical-frame=1 ',
      'utf8=reject core4-execution=NOT_IMPLEMENTED sens-repl=NOT_IMPLEMENTED');
  finally
    Session.Free;
  end;
end.
