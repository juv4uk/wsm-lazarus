{ G3.41: чинні wsm.gc + wsm.envframe, без SENS-evaluator.
  Усі payload — непрозорі host Int64; exact key не означає викличність. }
program test_gclexical;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.gc, wsm.domain, wsm.envframe, wsm.gclexical;
{ FPC може утримувати тимчасовий interface result до виходу із
  процедури; окремий стековий кадр обмежує lifetime перевірки.
  Питання: чи означає refcount фрейму право звільнити GC-комірку?
  Коли збирач може відпустити root після CaptureCode? }
function CapturedValue(const C:IRootedCode;
  const Key:TDomainKey):TGCHandle;
var F:IRootedFrame;
begin
  F:=C.CapturedFrame;
  Result:=F.Resolve(Key);
end;

function CapturedTicket(const C:IRootedCode):QWord;
var Code:ICapturedCode;
begin
  Code:=C.Captured;
  Result:=Code.EntryHandle;
end;

var Checks:SizeInt;
procedure Need(Condition:Boolean; const Description:String);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,'GC-LEXICAL-ПРОВАЛ: ',Description);
    Halt(1);
  end;
end;

{ Лексичні тимчасові інтерфейси гарантуються локальними саме для
  цього кадру, щоб GC-корені не вважалися вільними завчасно. }
procedure ExerciseCapture(H,Foreign:TGCHeap;
  out A,B,CodeCell,ForeignCell:TGCHandle);
var Root,Child,WrongParent:IRootedFrame;
    Closure:IRootedCode;
    Orphan:TGCHandle;
    Raised:Boolean;
begin
    Root:=NewRootedFrame(H,nil);
    A:=H.Allocate(11);
    Root.Bind(ExactKey('1'),A);
    Need(SameHandle(Root.Resolve(ExactKey('1')),A),
         'кореневий exact D1:1 не зв’язався');
    Need(H.RootCount=1,'кореневе значення не прикріплене');
    Child:=NewRootedFrame(H,Root);
    B:=H.Allocate(22);
    Child.Bind(ExactKey('1'),B);
    Need(SameHandle(Child.Resolve(ExactKey('1')),B),
         'лексичне тінювання не працює');
    Need(SameHandle(Root.Resolve(ExactKey('1')),A),
         'тінювання змінило предка');
    Child.Bind(ExactKey('000'),H.Allocate(33));
    Need(H.RootCount=3,'втрата кореня D3:000');
    Need(not SameHandle(Child.Resolve(ExactKey('1')),
                        Child.Resolve(ExactKey('000'))),
         'D1:1 злився з D3:000');
    Need(SameHandle(Child.Resolve(ExactKey('000')),
                    Child.Resolve(ExactKey('000'))),
         'точне D3:000 змінило значення');

    CodeCell:=H.Allocate(44);
    Closure:=CaptureRooted(Child,CodeCell);
    Need(SameHandle(Closure.Entry,CodeCell),
         'замикання втратило GUID/slot/generation');
    Need(CapturedTicket(Closure)<>0,
         'чинний CaptureCode не створив opaque host ticket');
    Need(SameHandle(CapturedValue(Closure,ExactKey('1')),B),
         'замикання не утримало lexical child');
    Need(SameHandle(CapturedValue(Closure,ExactKey('000')),
                    Child.Resolve(ExactKey('000'))),
         'замикання не утримало D3-значення');

    { Пізня відмова Duplicate НЕ залишає додаткового GC-root. }
    Raised:=False;
    try Child.Bind(ExactKey('1'),A);
    except on E:EFrameError do Raised:=True; end;
    Need(Raised and (H.RootCount=4),
         'дублікат пошкодив кількість коренів');
    Raised:=False;
    try Child.Resolve(ExactKey('0'));
    except on E:ERootedFrameError do Raised:=True; end;
    Need(Raised,'відсутній exact D1:0 не відхилений');
    ForeignCell:=Foreign.Allocate(77);
    Raised:=False;
    try Child.Bind(ExactKey('01'),ForeignCell);
    except on E:EGCError do Raised:=True; end;
    Need(Raised and (H.RootCount=4),'чужа купа прив’язалася');
    WrongParent:=NewRootedFrame(Foreign,nil);
    Raised:=False;
    try NewRootedFrame(H,WrongParent);
    except on E:ERootedFrameError do Raised:=True; end;
    Need(Raised,'чужого лексичного батька допущено');
    WrongParent:=nil;

    { Взаємні ребра живуть лише з root, не з reference-counted Pascal. }
    H.Link(A,B);
    H.Link(B,A);
    Orphan:=H.Allocate(55);
    Root:=nil;
    Child:=nil;
    Need(H.Collect=1,'недосяжну комірку не зібрано');
    Need((not H.IsAlive(Orphan)) and H.IsAlive(A) and H.IsAlive(B)
         and H.IsAlive(CodeCell),
         'захоплені GC-корені загубилися');
    Need(SameHandle(CapturedValue(Closure,ExactKey('1')),B),
         'захоплене лексичне значення зникло після Collect');
    Need(SameHandle(CapturedValue(Closure,ExactKey('000')),
                    CapturedValue(Closure,ExactKey('000'))),
         'захоплене порожнє значення втрачено');
    Need(H.Collect=0,'живі корені були звільнені повторним Collect');
    Closure:=nil;
end;

procedure ExerciseStale(H:TGCHeap; const B:TGCHandle);
var Root:IRootedFrame; Fresh,Old:TGCHandle; Raised:Boolean;
begin
  Old:=B;
    Fresh:=H.Allocate(66);
    Need(not H.IsAlive(Old) and H.IsAlive(Fresh),
         'застарілий handle воскрес після повторного використання');
    Raised:=False;
    try Root:=NewRootedFrame(H,nil); Root.Bind(ExactKey('1'),Old);
    except on E:EGCError do Raised:=True; end;
    Need(Raised and (H.RootCount=0),'застарілий handle потрапив у фрейм');
    Root:=nil;
    Need(H.Collect=1,'комірка після відмови лишилася');
end;

procedure ExerciseStack(H:TGCHeap);
var Token:TGCFrameToken; Transient:TGCHandle;
begin
    { Активні стекові області GC — через чинний Begin/Root/End,
      включно із винятком, без другого збирача сміття. }
    Token:=H.BeginRootScope;
    Transient:=H.Allocate(888);
    try
      H.RootInScope(Token,Transient);
      try
        Need(H.Collect=0,'стековий корінь був помилково зібраний');
        Need(H.IsAlive(Transient),'активний корінь стека втрачений');
        raise Exception.Create('gc-scope-exception-untouched');
      except on E:Exception do
        Need(E.Message='gc-scope-exception-untouched',
             'помилка поглинута або змінена');
      end;
    finally
      H.EndRootScope(Token);
    end;
    Need((H.ScopeDepth=0) and (H.ScopedRootCount=0),
         'GC-root стека не звільнено після винятку');
    Need(H.Collect=1,'стекове значення не зібрано після помилки');
    Need(not H.IsAlive(Transient),'витік стекового значення після помилки');
end;

procedure ExerciseCycle(H:TGCHeap; I:SizeInt);
var Root:IRootedFrame; Closure:IRootedCode;
    A,CodeCell:TGCHandle;
begin
      Root:=NewRootedFrame(H,nil);
      A:=H.Allocate(I);
      Root.Bind(ExactKey('0000001'),A);
      CodeCell:=H.Allocate(1000+I);
      Closure:=CaptureRooted(Root,CodeCell);
      Root:=nil;
      Need(H.Collect=0,'досяжні лексичні корені зібрано');
      Need(H.LiveCount=2,'пошкоджена кількість живих GC-значень');
      Need(H.ValueOf(CapturedValue(Closure,ExactKey('0000001')))=I,
           'перезаписаний payload на наступному циклі');
      Closure:=nil;
end;


{ Перевірка: повернуте сире інтерфейсне подання НЕ втрачає GC-root.
  Lifetime позиченого TGCHeap належить зовнішньому runtime.
  Питання: навіщо зберігати GUID? Чому opaque ticket не GC-handle?
  Хто утримує roots після виходу з творця інтерфейсу?
  Чому пряме InstallLocal через зовнішній IEnvFrame відмовляє? }
procedure HandOutFrame(H:TGCHeap; out Exposed:IEnvFrame;
  out Value:TGCHandle);
var F:IRootedFrame;
begin
  F:=NewRootedFrame(H,nil);
  Value:=H.Allocate(777);
  F.Bind(ExactKey('0000001'),Value);
  Exposed:=F.NativeFrame;
end;

procedure HandOutCode(H:TGCHeap; out Exposed:ICapturedCode;
  out Value,Entry:TGCHandle);
var F:IRootedFrame; Code:IRootedCode;
begin
  F:=NewRootedFrame(H,nil);
  Value:=H.Allocate(888);
  F.Bind(ExactKey('0000001'),Value);
  Entry:=H.Allocate(889);
  Code:=CaptureRooted(F,Entry);
  Exposed:=Code.Captured;
end;

procedure ExerciseExports(H:TGCHeap);
var Native:IEnvFrame; Code:ICapturedCode;
    A,Entry:TGCHandle; Ticket:QWord; Raised:Boolean;
begin
  HandOutFrame(H,Native,A);
  Need(H.RootCount=1,'зовнішній IEnvFrame не втримав GC-root');
  Need(H.Collect=0,'живий зовнішній IEnvFrame був зібраний');
  Need(Native.TryResolve(ExactKey('0000001'),Ticket) and (Ticket=1),
       'охоронюваний IEnvFrame втратив exact ticket');
  Raised:=False;
  try Native.InstallLocal(ExactKey('0'),123);
  except on E:ERootedFrameError do Raised:=True; end;
  Need(Raised and (H.RootCount=1),
       'зовнішній інтерфейс дозволив unsafe ticket без GC-root');
  Native:=nil;
  Need(H.RootCount=0,'відпущений зовнішній фрейм залишив GC-root');
  Need((H.Collect=1) and (not H.IsAlive(A)),
       'зовнішній фрейм не віддав heap після звільнення');

  HandOutCode(H,Code,A,Entry);
  Need(H.RootCount=2,'зовнішній ICapturedCode втратив два GC-root');
  Need(H.Collect=0,'живий зовнішній ICapturedCode був зібраний');
  Need(Code.EntryHandle<>0,'захоплений host ticket недоступний');
  Need(H.IsAlive(A) and H.IsAlive(Entry),
       'захоплені значення зникли перед звільненням інтерфейсу');
  Code:=nil;
  Need(H.RootCount=0,'зовнішній ICapturedCode залишив GC-root');
  Need(H.Collect=2,'зовнішній ICapturedCode не звільнив захоплені комірки');
  Need(H.LiveCount=0,'heap зріс після звільнення зовнішніх інтерфейсів');
end;

var H,Foreign:TGCHeap;
    A,B,CodeCell,ForeignCell:TGCHandle;
    I:SizeInt;
begin
  Checks:=0;
  H:=TGCHeap.Create;
  Foreign:=TGCHeap.Create;
  try
    ExerciseCapture(H,Foreign,A,B,CodeCell,ForeignCell);
    { На виході з процедури гарантовано звільнено і FPC temporary
      interfaces, і їхні GC roots, не лише основну Closure-змінну. }
    Need(H.RootCount=0,'знищене замикання залишило GC-корені');
    Need(H.Collect=4,'не всі лексичні значення звільнені');
    Need(H.LiveCount=0,'GC не очистив купу після замикання');
    ExerciseStale(H,B);
    ExerciseStack(H);
    ExerciseExports(H);
    for I:=1 to 32 do begin
      ExerciseCycle(H,I);
      Need(H.RootCount=0,'замикання залишило живий root');
      Need(H.Collect=2,'після замикання не зібрано два значення');
      Need(H.LiveCount=0,'довгий сеанс накопичив невивільнені GC комірки');
    end;
    Need(H.SlotCount<=6,'повторне використання GC-комірок не обмежило heap');
    Need(Foreign.IsAlive(ForeignCell),
         'відмова не повинна зачіпати іншу купу');
    Need(Foreign.Collect=1,
         'foreign heap не можна звільнити через наш root');
    WriteLn('GC-ЛЕКСИКА-ГАРАЗД перевірок=',Checks,
      ' замикань=33 циклів=32 exact=так shadow=так',
      ' stale=відхилено foreign=відхилено scope=звільнено');
    WriteLn('МЕЖА: Core1=ще-не-виконується evaluator=немає',
      ' D7=дані D12+=не-перетлумачено GC=механізм');
  finally
    Foreign.Free;
    H.Free;
  end;
end.
