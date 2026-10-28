program TestCore4Runtime;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4runtime, wsm.t5m, wsm.physloc;
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

{ Вкладений РЕАЛЬНИЙ Core4 виклик: жодного конкатенування
  T5M-байтів з padding, тільки точні слова й один спільний EncodeT5M. }
function MakeNestedCall(const OuterId,InnerId,Arg:RawByteString):RawByteString;
var Outer,Inner,Merged:TExactWords; I,N:SizeInt;
begin
  DecodeT5M(MakeCall(OuterId,'1'),Outer);
  DecodeT5M(MakeCall(InnerId,Arg),Inner);
  N:=Length(Outer)-2;
  SetLength(Merged,N+Length(Inner)+1);
  for I:=0 to N-1 do Merged[I]:=Outer[I];
  for I:=0 to High(Inner) do Merged[N+I]:=Inner[I];
  Merged[High(Merged)]:='01';
  Result:=EncodeT5M(Merged);
end;

{ Звіряємо адресу з оригінального канонічного байтового T5M,
  наявні префікси та EOF. Жодної доменної або D12+ семантики. }
procedure ExpectRejectAt(const Payload:RawByteString; AtWord:SizeInt;
  const LabelText:String);
var W:TExactWords; Spans:TPhysicalWordSpans; At:TPhysicalWordSpan;
    Expected:String; Got:Boolean;
begin
  DecodeT5MWithLocations(Payload,W,Spans);
  At:=LocatePhysicalWord(Payload,Spans,AtWord);
  Expected:='слово='+IntToStr(At.WordIndex)+
    ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+')'+
    ' байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')';
  Got:=False;
  try
    Runtime.ExecutePhysicalCall(Payload);
  except
    on E:ECore4RuntimeError do
      Got:=(Pos(Expected,E.Message)>0) and
        (Pos('EOF=так',E.Message)>0)=At.IsEOF;
  end;
  Check(Got,'точна фізична адреса: '+LabelText);
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

var Changed,Physical:RawByteString; W:TExactWords;
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
    { Позитив через ДВА живі nested pinned Core4 DEFINE, без Pascal копії. }
    CheckResult(MakeNestedCall(NameBits,NameBits,'1'),'1',
      'два справжні вкладені Core4 виклики');
    { Глибока невідома точна D7-голова: адресується INNER,
      а не нульовий root і не зовнішня D7-голова. }
    Physical:=MakeNestedCall(NameBits,Changed,'1');
    DecodeT5M(MakeCall(NameBits,'1'),W);
    ExpectRejectAt(Physical,Length(W)-1,'внутрішня невідома D7-голова');
    SetLength(W,1); W[0]:='01';
    ExpectRejectAt(EncodeT5M(W),1,'синтаксис зайвого CLOSE');
    W[0]:='10';
    ExpectRejectAt(EncodeT5M(W),2,'відсутній CLOSE у EOF');
    CheckResult(MakeCall(NameBits,'0'),'0',
      'відновлення після глибокої і двох синтаксичних помилок');
    WriteLn('CORE4-RUNTIME-АДРЕСА-ГАРАЗД вкладена=внутрішній-вузол ',
      'D2=закриття/EOF відновлення=так');
    WriteLn('CORE4-RUNTIME-ГАРАЗД джерело=core4.sens форми=3 D4=DEFINE/LAMBDA ',
      'D7=точне-зв’язування D24=opaque-значення виклики=5 негативні=3');
  finally Runtime.Free end;
end.
