program TestCore4Runtime;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4runtime, wsm.t5m, wsm.physloc;
var Runtime:TCore4Runtime; NameBits:RawByteString;
    ListValues,LargeValues,FirstValues,OuterTail:TExactWords; I:SizeInt;

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

{ Пряма фізична форма D4:1110; Values — слова атомів або D2-свідки
  для негативних вкладених форм, не поверхневі назви. }
function MakeListCall(const Values:TExactWords):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Values)+3);
  W[0]:='10'; W[1]:='1110';
  for I:=0 to High(Values) do W[I+2]:=Values[I];
  W[High(W)]:='01';
  Result:=EncodeT5M(W);
end;

function MakeOtherD4Call(const Head:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,4);
  W[0]:='10'; W[1]:=Head; W[2]:='1'; W[3]:='01';
  Result:=EncodeT5M(W);
end;

function MakeSecondOfListCall(const Values:TExactWords):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Values)+6);
  W[0]:='10'; W[1]:='1001'; { D4:1001 }
  W[2]:='10'; W[3]:='1110'; { D4:1110 }
  for I:=0 to High(Values) do W[I+4]:=Values[I];
  W[Length(Values)+4]:='01'; { close constructor }
  W[Length(Values)+5]:='01'; { close selector }
  Result:=EncodeT5M(W);
end;

function MakeSecondNestedListCall:RawByteString;
var W:TExactWords;
begin
  { D4:1001 selects a nested exact D2 value from an outer D4:1110 form.
    Neither inner nor selected form is evaluated by this selector. }
  SetLength(W,15);
  W[0]:='10'; W[1]:='1001'; W[2]:='00';
  W[3]:='10'; W[4]:='1110'; W[5]:='00'; W[6]:='1'; W[7]:='00';
  W[8]:='10'; W[9]:='1110'; W[10]:='00';
  W[11]:='000000000000000000000001';
  W[12]:='01'; W[13]:='01'; W[14]:='01';
  Result:=EncodeT5M(W);
end;

function MakeRestRestOfListCall(const Values:TExactWords):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Values)+6);
  W[0]:='10'; W[1]:='0111'; { D4:0111 }
  W[2]:='10'; W[3]:='1110'; { D4:1110 }
  for I:=0 to High(Values) do W[I+4]:=Values[I];
  W[Length(Values)+4]:='01'; { close constructor }
  W[Length(Values)+5]:='01'; { close selector }
  Result:=EncodeT5M(W);
end;

function MakeNestedListSelectorCall(const SelectorId:RawByteString;
  const FirstValues,OuterTail:TExactWords;
  const InnerHead:RawByteString):RawByteString;
var W:TExactWords; I,N,M,P:SizeInt;
begin
  N:=Length(FirstValues); M:=Length(OuterTail);
  SetLength(W,2*N+2*M+11); P:=0;
  W[P]:='10'; Inc(P); W[P]:=SelectorId; Inc(P);
  W[P]:='00'; Inc(P); { D2 separator }
  W[P]:='10'; Inc(P); W[P]:='1110'; Inc(P); { зовнішній D4:1110 }
  W[P]:='00'; Inc(P);
  W[P]:='10'; Inc(P); W[P]:=InnerHead; Inc(P); { перший елемент — внутрішній список }
  for I:=0 to N-1 do begin
    W[P]:='00'; Inc(P); W[P]:=FirstValues[I]; Inc(P);
  end;
  W[P]:='01'; Inc(P); { close внутрішнього списку }
  for I:=0 to M-1 do begin
    W[P]:='00'; Inc(P); W[P]:=OuterTail[I]; Inc(P);
  end;
  W[P]:='01'; Inc(P); { close зовнішнього списку }
  W[P]:='01'; Inc(P); { close D4:1000 }
  SetLength(W,P);
  Result:=EncodeT5M(W);
end;

function MakeFirstFirstOfListsCall(const FirstValues,OuterTail:TExactWords;
  const InnerHead:RawByteString):RawByteString;
begin
  Result:=MakeNestedListSelectorCall('1000',FirstValues,OuterTail,InnerHead);
end;

function MakeRestFirstOfListsCall(const FirstValues,OuterTail:TExactWords;
  const InnerHead:RawByteString):RawByteString;
begin
  Result:=MakeNestedListSelectorCall('0110',FirstValues,OuterTail,InnerHead);
end;

function MakeD4ListExpression(const Head:RawByteString;
  const Values:TExactWords):TExactWords;
var I:SizeInt;
begin
  Result:=nil;
  SetLength(Result,Length(Values)+3);
  Result[0]:='10'; Result[1]:=Head;
  for I:=0 to High(Values) do Result[I+2]:=Values[I];
  Result[High(Result)]:='01';
end;

function MakeAppendCall(const LeftExpression,RightExpression:TExactWords):RawByteString;
var W:TExactWords; I,P:SizeInt;
begin
  SetLength(W,Length(LeftExpression)+Length(RightExpression)+5);
  P:=0; W[P]:='10'; Inc(P); W[P]:='1111'; Inc(P); W[P]:='00'; Inc(P);
  for I:=0 to High(LeftExpression) do begin W[P]:=LeftExpression[I]; Inc(P) end;
  W[P]:='00'; Inc(P);
  for I:=0 to High(RightExpression) do begin W[P]:=RightExpression[I]; Inc(P) end;
  W[P]:='01'; Inc(P);
  SetLength(W,P);
  Result:=EncodeT5M(W);
end;

function MakeFirstFirstOfFlatListCall(const Values:TExactWords):RawByteString;
var W:TExactWords; I,P:SizeInt;
begin
  SetLength(W,Length(Values)*2+7); P:=0;
  W[P]:='10'; Inc(P); W[P]:='1000'; Inc(P); { D4:1000 }
  W[P]:='00'; Inc(P);
  W[P]:='10'; Inc(P); W[P]:='1110'; Inc(P); { D4:1110 }
  for I:=0 to High(Values) do begin
    W[P]:='00'; Inc(P); W[P]:=Values[I]; Inc(P);
  end;
  W[P]:='01'; Inc(P); { close list }
  W[P]:='01'; Inc(P); { close selector }
  SetLength(W,P);
  Result:=EncodeT5M(W);
end;

function MakeFirstFirstEmptyOuterCall:RawByteString;
begin
  Result:=MakeFirstFirstOfFlatListCall(nil);
end;

procedure CheckAtomicResult(const Payload,Expected:RawByteString;
  const LabelText:String);
var Got:TExactWords;
begin
  DecodeT5M(Runtime.ExecutePhysicalCall(Payload),Got);
  Check((Length(Got)=1) and (Got[0]=Expected),
    LabelText+' exact atomic result');
end;

procedure CheckListResult(const Payload:RawByteString;
  const Values:TExactWords; const LabelText:String);
var Got,Expected:TExactWords; I:SizeInt;
begin
  DecodeT5M(Runtime.ExecutePhysicalCall(Payload),Got);
  SetLength(Expected,Length(Values)+2);
  Expected[0]:='10';
  for I:=0 to High(Values) do Expected[I+1]:=Values[I];
  Expected[High(Expected)]:='01';
  Check(Length(Got)=Length(Expected),LabelText+' exact D2 word count');
  for I:=0 to High(Expected) do
    Check(Got[I]=Expected[I],LabelText+' exact child/framing word '+IntToStr(I+1));
end;

procedure CheckExactValueResult(const Payload:RawByteString;
  const Expected:TExactWords; const LabelText:String);
var Got:TExactWords; I:SizeInt;
begin
  DecodeT5M(Runtime.ExecutePhysicalCall(Payload),Got);
  Check(Length(Got)=Length(Expected),LabelText+' exact D2 word count');
  for I:=0 to High(Expected) do
    Check(Got[I]=Expected[I],LabelText+' exact D2 word '+IntToStr(I+1));
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
    Expected,Actual:String; Got:Boolean;
begin
  DecodeT5MWithLocations(Payload,W,Spans);
  At:=LocatePhysicalWord(Payload,Spans,AtWord);
  Expected:='слово='+IntToStr(At.WordIndex)+
    ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+')'+
    ' байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')';
  Got:=False; Actual:='виклик не відхилено';
  try
    Runtime.ExecutePhysicalCall(Payload);
  except
    on E:ECore4RuntimeError do
      begin
        Actual:=E.Message;
        Got:=(Pos(Expected,E.Message)>0) and
          ((Pos('EOF=так',E.Message)>0)=At.IsEOF);
      end;
  end;
  Check(Got,'точна фізична адреса: '+LabelText+'; '+Actual);
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

var Changed,Physical:RawByteString; W,AppendLeft,AppendRight:TExactWords;
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
    SetLength(FirstValues,2); FirstValues[0]:='1';
    FirstValues[1]:='000000000000000000000001';
    CheckListResult(MakeRestFirstOfListsCall(FirstValues,nil,'1110'),
      TExactWords(['000000000000000000000001']),
      'D4:0110 повертає точний суфікс першого вкладеного списку');
    SetLength(FirstValues,1); FirstValues[0]:='1';
    CheckExactValueResult(MakeRestFirstOfListsCall(FirstValues,nil,'1110'),
      TExactWords(['10','01']),
      'D4:0110 повертає порожній список після одноелементного списку');
    SetLength(FirstValues,5); FirstValues[0]:='1'; FirstValues[1]:='10';
    FirstValues[2]:='1110'; FirstValues[3]:='0'; FirstValues[4]:='01';
    CheckExactValueResult(MakeRestFirstOfListsCall(FirstValues,nil,'1110'),
      TExactWords(['10','10','1110','0','01','01']),
      'D4:0110 зберігає вкладене значення у суфіксі');
    ExpectRejectAt(MakeOtherD4Call('0110'),3,
      'D4:0110 відхиляє скалярний аргумент за його адресою');
    ExpectRejectAt(MakeRestFirstOfListsCall(nil,nil,'1110'),7,
      'D4:0110 відхиляє порожній перший внутрішній список');
    SetLength(FirstValues,1); FirstValues[0]:='1';
    ExpectRejectAt(MakeRestFirstOfListsCall(FirstValues,nil,'1001'),8,
      'D4:0110 відхиляє перший список з іншою exact D4-головою');
    AppendLeft:=MakeD4ListExpression('1110',
      TExactWords(['1','000000000000000000000001']));
    AppendRight:=MakeD4ListExpression('1110',TExactWords(['0']));
    CheckExactValueResult(MakeAppendCall(AppendLeft,AppendRight),
      TExactWords(['10','1','000000000000000000000001','0','01']),
      'D4:1111 приєднує атомні списки зі збереженням D24');
    ExpectRejectAt(MakeAppendCall(TExactWords(['1']),AppendRight),4,
      'D4:1111 відхиляє скалярний лівий аргумент за його адресою');
    ExpectRejectAt(MakeAppendCall(
      MakeD4ListExpression('1001',TExactWords(['1'])),AppendRight),5,
      'D4:1111 відхиляє ліву форму з іншою exact D4-головою');
    ExpectRejectAt(MakeAppendCall(
      MakeD4ListExpression('1110',nil),AppendRight),4,
      'D4:1111 відхиляє порожній список поза цією межею');
    ExpectRejectAt(MakeAppendCall(
      MakeD4ListExpression('1110',TExactWords(['1'])),
      MakeD4ListExpression('1110',TExactWords(['10','1110','1','01']))),11,
      'D4:1111 fail-closed для складеного елемента поза evaluator');
    ExpectRejectAt(MakeOtherD4Call('1111'),1,
      'D4:1111 відхиляє неправильну арність');
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
    CheckListResult(MakeListCall(nil),nil,'D4:1110 порожній список');
    SetLength(ListValues,1); ListValues[0]:='0';
    CheckListResult(MakeListCall(ListValues),ListValues,
      'D4:1110 один точний D1 атом');
    SetLength(ListValues,2); ListValues[0]:='1';
    ListValues[1]:='000000000000000000000001';
    CheckListResult(MakeListCall(ListValues),ListValues,
      'D4:1110 зберігає ширину та біти D1/D24');
    CheckAtomicResult(MakeSecondOfListCall(ListValues),ListValues[1],
      'D4:1001 бере другий атом зі списку D4:1110');
    CheckExactValueResult(MakeSecondNestedListCall,
      TExactWords(['10','1110','000000000000000000000001','01']),
      'D4:1001 повертає повне вкладене D2-значення з opaque D24');
    SetLength(ListValues,2); ListValues[0]:='1'; ListValues[1]:='0';
    CheckListResult(MakeRestRestOfListCall(ListValues),nil,
      'D4:0111 повертає порожній суфікс після двох атомів');
    SetLength(ListValues,4); ListValues[0]:='1'; ListValues[1]:='0';
    ListValues[2]:='000000000000000000000001';
    ListValues[3]:='000000000000000000000000';
    CheckListResult(MakeRestRestOfListCall(ListValues),
      TExactWords([ListValues[2],ListValues[3]]),
      'D4:0111 зберігає точні слова суфікса');
    ExpectRejectAt(MakeRestRestOfListCall(nil),3,
      'D4:0111 відхиляє список коротший за два атоми');
    SetLength(ListValues,1); ListValues[0]:='0';
    ExpectRejectAt(MakeRestRestOfListCall(ListValues),3,
      'D4:0111 відхиляє список з одним атомом');
    SetLength(ListValues,3); ListValues[0]:='1';
    ListValues[1]:='10'; ListValues[2]:='01';
    ExpectRejectAt(MakeRestRestOfListCall(ListValues),6,
      'D4:0111 відхиляє вкладений елемент суфікса');
    ExpectRejectAt(MakeOtherD4Call('0111'),3,
      'D4:0111 відхиляє скалярний аргумент');
    ExpectRejectAt(MakeOtherD4Call('1000'),3,
      'D4:1000 відхиляє скалярний аргумент');
    SetLength(FirstValues,2);
    FirstValues[0]:='000000000000000000000001'; FirstValues[1]:='0';
    SetLength(OuterTail,1); OuterTail[0]:='1';
    CheckAtomicResult(MakeFirstFirstOfListsCall(FirstValues,OuterTail,'1110'),
      FirstValues[0],
      'D4:1000 вибирає перший атом першого вкладеного D4:1110');
    SetLength(FirstValues,2); FirstValues[0]:='1'; FirstValues[1]:='0';
    SetLength(OuterTail,0);
    CheckAtomicResult(MakeFirstFirstOfListsCall(FirstValues,OuterTail,'1110'),
      FirstValues[0],'D4:1000 зберігає точне D1-слово');
    { Той самий селектор має повернути вкладене значення як повний D2-вузол,
      зберігши його власні точні слова та дужки. }
    SetLength(FirstValues,5);
    FirstValues[0]:='10'; FirstValues[1]:='1110';
    FirstValues[2]:='000000000000000000000001';
    FirstValues[3]:='01'; FirstValues[4]:='0';
    CheckListResult(MakeFirstFirstOfListsCall(FirstValues,nil,'1110'),
      TExactWords(['1110','000000000000000000000001']),
      'D4:1000 повертає повний вкладений D2-список з opaque D24');
    SetLength(FirstValues,5); FirstValues[0]:='10'; FirstValues[1]:='1110';
    FirstValues[2]:='11'; FirstValues[3]:='1'; FirstValues[4]:='01';
    CheckExactValueResult(MakeFirstFirstOfListsCall(FirstValues,nil,'1110'),
      TExactWords(['10','1110','11','1','01']),
      'D4:1000 зберігає вкладену D2-пару');
    ExpectRejectAt(MakeFirstFirstEmptyOuterCall,4,
      'D4:1000 відхиляє порожній зовнішній список');
    SetLength(ListValues,1); ListValues[0]:='1';
    ExpectRejectAt(MakeFirstFirstOfFlatListCall(ListValues),7,
      'D4:1000 відхиляє атом замість першого вкладеного списку');
    ExpectRejectAt(MakeFirstFirstOfListsCall(nil,nil,'1110'),7,
      'D4:1000 відхиляє порожній перший внутрішній список');
    SetLength(FirstValues,1); FirstValues[0]:='1';
    ExpectRejectAt(MakeFirstFirstOfListsCall(FirstValues,nil,'1001'),8,
      'D4:1000 відхиляє внутрішній список із іншою D4-головою');
    SetLength(FirstValues,1); FirstValues[0]:='1';
    SetLength(OuterTail,3); OuterTail[0]:='10';
    OuterTail[1]:='0'; OuterTail[2]:='01';
    ExpectRejectAt(MakeFirstFirstOfListsCall(FirstValues,OuterTail,'1110'),13,
      'D4:1000 відхиляє складений хвіст поза атомарним зрізом');
    ExpectRejectAt(MakeOtherD4Call('1001'),3,
      'D4:1001 відхиляє скалярний аргумент за його адресою');
    SetLength(ListValues,1); ListValues[0]:='0';
    ExpectRejectAt(MakeSecondOfListCall(ListValues),3,
      'D4:1001 не має другого елемента');
    SetLength(ListValues,1); ListValues[0]:='000';
    ExpectReject(MakeListCall(ListValues),'D3:000 є структурним пустим списком');
    SetLength(ListValues,3); ListValues[0]:='10'; ListValues[1]:='0';
    ListValues[2]:='01';
    ExpectReject(MakeListCall(ListValues),'вкладена форма поза атомарним зрізом');
    ExpectReject(MakeOtherD4Call('1111'),'інша raw D4-голова');
    SetLength(LargeValues,4094);
    for I:=0 to High(LargeValues) do LargeValues[I]:='0';
    ExpectReject(MakeListCall(LargeValues),'межа слів фізичного виклику');
    CheckResult(MakeCall(NameBits,'1'),'1',
      'Core4 відновлюється після негативних D4-форм');
    WriteLn('CORE4-RUNTIME-СПИСОК-ГАРАЗД D4:1110=точна-голова ',
      'D4:1001=друге точні-атомні-та-складені-D2-значення ',
      'D4:0111=решта-решти D4:1000=перше-першого ',
      'D4:0110=решта-першого D4:1111=приєднати негативи=24');
    WriteLn('CORE4-RUNTIME-АДРЕСА-ГАРАЗД вкладена=внутрішній-вузол ',
      'D2=закриття/EOF відновлення=так');
    WriteLn('CORE4-RUNTIME-ГАРАЗД джерело=core4.sens початкові-форми=3 ',
      'D4=DEFINE/LAMBDA D7=точне-зв’язування D24=opaque-значення');
  finally Runtime.Free end;
end.
