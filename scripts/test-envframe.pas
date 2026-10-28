program test_envframe;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.envframe;

procedure Expect(Condition: Boolean; const MessageText: String);
begin
  if not Condition then
  begin
    WriteLn(StdErr, 'ENVFRAME-FAIL ', MessageText);
    Halt(1);
  end;
end;

var
  Root, Child, CapturedFrame: IEnvFrame;
  Code: ICapturedCode;
  Key, Invalid: TDomainKey;
  ValueHandle: QWord;
  Raised: Boolean;
begin
  Root := NewEnvFrame(nil);
  Root.InstallLocal(ExactKey('1'), 17);
  Root.InstallLocal(ExactKey('001'), 56);
  Expect(Root.Resolve(ExactKey('1')) = 17, 'root lookup');
  Expect(Root.Resolve(ExactKey('001')) = 56, 'three-bit coordinate');

  Child := NewEnvFrame(Root);
  Child.InstallLocal(ExactKey('1'), 99);
  Child.InstallLocal(ExactKey('01'), 0);
  Expect(Child.Resolve(ExactKey('1')) = 99, 'lexical shadowing');
  Expect(Root.Resolve(ExactKey('1')) = 17, 'parent unchanged');
  Expect(Child.Resolve(ExactKey('001')) = 56, 'parent chain');
  Expect(Child.Resolve(ExactKey('01')) = 0, 'zero is a real handle');
  Expect(Child.Resolve(ExactKey('001')) <> Child.Resolve(ExactKey('01')),
    'same numeric bits different domain');
  Expect(Child.TryResolve(ExactKey('01'), ValueHandle) and
    (ValueHandle = 0), 'zero must not be unbound');

  Raised := False;
  try
    Child.InstallLocal(ExactKey('1'), 100);
  except on E: EFrameError do Raised := True; end;
  Expect(Raised, 'duplicate same-frame coordinate must fail');

  Raised := False;
  try
    ValueHandle := Child.Resolve(ExactKey('000'));
  except on E: EFrameError do Raised := True; end;
  Expect(Raised, 'unknown coordinate must fail');

  Invalid.Width := 0;
  Invalid.Bits := 0;
  Raised := False;
  try
    Child.InstallLocal(Invalid, 5);
  except on E: EFrameError do Raised := True; end;
  Expect(Raised, 'zero-width physical coordinate must fail');

  Invalid.Width := 2;
  Invalid.Bits := 4;
  Raised := False;
  try
    ValueHandle := Child.Resolve(Invalid);
  except on E: EFrameError do Raised := True; end;
  Expect(Raised, 'out-of-range bits must fail');

  Raised := False;
  try
    Code := CaptureCode(nil, 22);
  except on E: EFrameError do Raised := True; end;
  Expect(Raised, 'capture without environment must fail');

  Code := CaptureCode(Child, 31415);
  Expect(Code.EntryHandle = 31415, 'code handle remains opaque');
  CapturedFrame := Code.LexicalFrame;
  Child := nil;
  Root := nil;
  Expect(CapturedFrame.Resolve(ExactKey('1')) = 99,
    'captured child survives caller');
  Expect(CapturedFrame.Resolve(ExactKey('001')) = 56,
    'captured lexical parent survives caller');
  CapturedFrame := nil;
  Expect(Code.LexicalFrame.Resolve(ExactKey('01')) = 0,
    'closure owns frame independent of local reference');

  Key := ExactKey('1111111111');
  Code.LexicalFrame.InstallLocal(Key, 9);
  Expect(Code.LexicalFrame.Resolve(Key) = 9,
    'exact-width mechanical storage, not semantic ratification');

  WriteLn('ENVFRAME-OK physical-keys=exact shadow=pass ',
    'closure-capture=pass missing=reject duplicate=reject ',
    'SENS-execution=NOT_IMPLEMENTED Core4=NOT_EXECUTED');
end.
