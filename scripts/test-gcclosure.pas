{ Core1.2: реальний GC + IEnvFrame + ICapturedCode, НЕ Core1 evaluator.
  Test inputs є фізичними T5M-атомами; роль задає pinned SENS,
  тут перевіряємо лише життя та побайтове збереження носія. }
program test_gcclosure;
{$mode objfpc}{$H+}
uses SysUtils, wsm.gc, wsm.domain, wsm.t5m,
  wsm.envframe, wsm.gcclosure;
var Checks:SizeInt;
procedure Check(Ok:Boolean;const Why:String);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,'GC-ЗАМИКАННЯ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;
function Physical(const Bits:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);Words[0]:=Bits;
  Result:=EncodeT5M(Words);
end;
function TwoAtoms(const L,R:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,2);
  Words[0]:=L;Words[1]:=R;
  Result:=EncodeT5M(Words);
end;
procedure TestGraphAndCapture;
var Bridge,Other:TGCClosureBridge;
    Parent,Child,OtherFrame:TGCActivation;
    Code:TGCClosure; K7,K1:TDomainKey;
    ParentValue,ChildValue:RawByteString;
    Failed:Boolean;
begin
  Bridge:=TGCClosureBridge.Create;
  Other:=TGCClosureBridge.Create;
  Parent:=nil;Child:=nil;Code:=nil;OtherFrame:=nil;
  try
    K7:=ExactKey('1100001'); K1:=ExactKey('1');
    ParentValue:=Physical('1');
    ChildValue:=Physical('011111111111111111111111');
    Parent:=Bridge.BeginActivation;
    Bridge.BindPhysical(Parent,K7,ParentValue,1);
    Bridge.BindPhysical(Parent,K1,Physical('0'),1);
    Child:=Bridge.BeginActivation(Parent);
    Bridge.BindPhysical(Child,K7,ChildValue,24);
    Check(Bridge.ResolveActivation(Child,K7)=ChildValue,
      'лексичне затінення фізичного значення не працює');
    Check(Bridge.ResolveActivation(Child,K1)=Physical('0'),
      'батьківський кадр недоступний');
    Check(Bridge.ResolveActivation(Parent,K7)=ParentValue,
      'дочірній запис зіпсував батьківське значення');
    Check(Bridge.LiveCount=5,'не 2 кадри + 3 фізичних значення');
    { Навмисний цикл якорів: після звільнення останнього кореня
      цикл має збиратися, а під час захоплення залишатися живим. }
    Bridge.Heap.Link(Parent.Anchor,Child.Anchor);
    Code:=Bridge.Capture(Child,77);
    Check(Code.EntryHandle=77,'opaque entry handle не збережено');
    Failed:=False;
    try Other.ResolveClosure(Code,K7);
    except on E:EGCClosureError do Failed:=True end;
    Check(Failed,'інша купа прийняла захоплене замикання');
    OtherFrame:=Other.BeginActivation;
    Failed:=False;
    try Other.BeginActivation(Child);
    except on E:EGCClosureError do Failed:=True end;
    Check(Failed,'сторонній батьківський кадр прийнято');
    OtherFrame.Free;OtherFrame:=nil;
    Child.Free;Child:=nil;
    Parent.Free;Parent:=nil;
    Check(Bridge.Heap.ScopeDepth=0,'після виклику лишилася область коренів');
    Check(Bridge.RootCount=1,'замикання не тримає єдиний GC корінь');
    Check(Bridge.Collect=0,'замикання втратило значення після виходу зі стеку');
    Check(Bridge.ResolveClosure(Code,K7)=ChildValue,
      'після звільнення activation загублено захоплене значення');
    Check(Bridge.ResolveClosure(Code,K1)=Physical('0'),
      'захоплене батьківське лексичне значення загублено');
    Code.Free;Code:=nil;
    Check(Bridge.RootCount=0,'забули зняти permanent root');
    Check(Bridge.Collect=5,'недосяжний цикл та фізичні значення не зібрано');
    Check(Bridge.LiveCount=0,'GC комірки залишилися живими');
    Check(Bridge.Collect=0,'повторна збірка неідемпотентна');
    Check(Other.Collect=1,'сторонній незахоплений кадр не зібрано');
  finally
    Code.Free;
    Child.Free;
    Parent.Free;
    OtherFrame.Free;
    Other.Free;
    Bridge.Free;
  end;
end;
procedure TestInvalidAndRecovery;
var Bridge:TGCClosureBridge; A:TGCActivation;
    K:TDomainKey; Failed:Boolean;
    I:SizeInt; P:RawByteString;
begin
  Bridge:=TGCClosureBridge.Create;A:=nil;
  try
    K:=ExactKey('1010101');
    A:=Bridge.BeginActivation;
    Failed:=False;
    try Bridge.BindPhysical(A,K,#243,7);
    except on E:Exception do Failed:=True end;
    Check(Failed,'зіпсований T5M прийнято');
    Failed:=False;
    try Bridge.BindPhysical(A,K,TwoAtoms('1','0'),1);
    except on E:Exception do Failed:=True end;
    Check(Failed,'два фізичні слова стали одним значенням');
    Failed:=False;
    try Bridge.BindPhysical(A,K,Physical('1'),7);
    except on E:Exception do Failed:=True end;
    Check(Failed,'невірний фізичний домен прийнято');
    P:=Physical('1111111');
    Bridge.BindPhysical(A,K,P,7);
    Check(Bridge.ResolveActivation(A,K)=P,'відновлення після відмов');
    Failed:=False;
    try Bridge.BindPhysical(A,K,Physical('0000000'),7);
    except on E:EFrameError do Failed:=True end;
    Check(Failed and (Bridge.ResolveActivation(A,K)=P),
      'дубль змінив вже встановлений host handle');
    Check(Bridge.Collect=1,'невдалий дубль залишив живу зайву комірку');
    A.Free;A:=nil;
    Check(Bridge.Collect=2,'скоуп+значення не звільнені');
    Check(Bridge.LiveCount=0,'фізичний буфер не звільнено');
    { Тривалий сеанс: комірки перевикористовуються поколіннями,
      ніяке старе значення не стає видимим новому activation. }
    for I:=1 to 256 do begin
      A:=Bridge.BeginActivation;
      Bridge.BindPhysical(A,K,P,7);
      Check(Bridge.ResolveActivation(A,K)=P,'порушено цикл життя');
      A.Free;A:=nil;
      Check(Bridge.Collect=2,'довгий цикл залишив reachable об’єкти');
    end;
    Check((Bridge.LiveCount=0) and (Bridge.RootCount=0),
      'довга сесія залишила GC roots');
    Check(Bridge.Heap.SlotCount<=3,'reuse комірок не працює');
    WriteLn('GC-CORE1-МІСТ-ГАРАЗД циклів=256 тестів=',Checks,
      ' фізичний=T5M кадри=лексичні замикання=збережені',
      ' GC=спільний stale=відхилено');
  finally A.Free;Bridge.Free end;
end;
begin
  Checks:=0;
  TestGraphAndCapture;
  TestInvalidAndRecovery;
  WriteLn('GC-CORE1-МЕЖА реальний-core1-виклик=НЕ_РЕАЛІЗОВАНО ',
    'oracle=НЕ_ВИКОНУВАВСЯ  збирач=wsm.gc');
end.
