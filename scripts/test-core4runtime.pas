program TestCore4Runtime;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4runtime, wsm.t5m;
var Runtime:TCore4Runtime; NameBits:RawByteString;

procedure Check(const Condition:Boolean; const LabelText:String);
begin if not Condition then raise Exception.Create('провал: '+LabelText) end;

function MakeCall(const Id:RawByteString; const Arg:RawByteString;
  IncludeArg:Boolean=True):RawByteString;
var W:TExactWords; I,N:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('тест має некоректну D7-послідовність');
  SetLength(W,0);
  SetLength(W,Length(Id) div 7+5);
  N:=0; W[N]:='10'; Inc(N); W[N]:='10'; Inc(N);
  for I:=0 to (Length(Id) div 7)-1 do begin
    W[N]:=Copy(Id,I*7+1,7); Inc(N);
  end;
  W[N]:='01'; Inc(N);
  if IncludeArg then begin W[N]:=Arg; Inc(N) end;
  W[N]:='01'; Inc(N);
  SetLength(W,N);
  Result:=EncodeT5M(W);
end;

function MakeIdentifier(const Id:RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('тест має некоректну D7-послідовність');
  SetLength(W,Length(Id) div 7+2);
  W[0]:='10';
  for I:=0 to (Length(Id) div 7)-1 do W[I+1]:=Copy(Id,I*7+1,7);
  W[High(W)]:='01';
  Result:=EncodeT5M(W);
end;

procedure ExpectReject(const Payload:RawByteString; const LabelText:String);
begin
  try Runtime.ExecutePhysicalCall(Payload);
  except on E:ECore4RuntimeError do Exit end;
  raise Exception.Create('негативний випадок пройшов: '+LabelText);
end;

procedure CheckResult(const Payload,Expected:RawByteString; const LabelText:String);
var Output:RawByteString; W:TExactWords;
begin
  Output:=Runtime.ExecutePhysicalCall(Payload);
  DecodeT5M(Output,W);
  Check((Length(W)=1) and (W[0]=Expected),LabelText);
end;

var Changed:RawByteString;
begin
  if ParamCount<>1 then begin WriteLn(StdErr,'usage: test-core4runtime REPO'); Halt(64) end;
  Runtime:=TCore4Runtime.Create(ParamStr(1));
  try
    NameBits:=Runtime.FirstDefinitionIdentifier;
    Check((Length(NameBits)>0) and ((Length(NameBits) mod 7)=0),
      'завантаження точного D7-імені першого визначення');
    Check(Runtime.BindingCount=3,'послідовне завантаження трьох початкових Core4 DEFINE');
    CheckResult(MakeCall(NameBits,'1'),'1','виклик Core4 із D1:1');
    CheckResult(MakeCall(NameBits,'0'),'0','повторний виклик Core4 із D1:0');
    CheckResult(MakeCall(NameBits,'000000000000000000000000'),
      '000000000000000000000000','передача точного D24:0 через Core4-функцію');
    CheckResult(MakeIdentifier(Runtime.BindingIdentifier(1)),
      '000000000000000000000000','читання Core4-глобала exact D24:0');
    CheckResult(MakeIdentifier(Runtime.BindingIdentifier(2)),
      '000000000000000000000001','читання Core4-глобала exact D24:1');
    ExpectReject(MakeCall(NameBits,'',False),'неправильна арність');
    Changed:=Copy(NameBits,1,Length(NameBits));
    if Changed[7]='0' then Changed[7]:='1' else Changed[7]:='0';
    ExpectReject(MakeCall(Changed,'1'),'невідоме exact D7-ім’я');
    ExpectReject(MakeCall(NameBits,'000'),'непідтримане значення, без підміни на D1');
    WriteLn('CORE4-RUNTIME-ГАРАЗД джерело=core4.sens форми=3 D4=DEFINE/LAMBDA ',
      'D7=точне-зв’язування D24=opaque-значення виклики=5 негативні=3');
  finally Runtime.Free end;
end.
