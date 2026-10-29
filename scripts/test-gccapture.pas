program test_gccapture;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.gc, wsm.envframe, wsm.domain, wsm.gccapture;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then
    raise Exception.Create('GC-ЗАХОПЛЕННЯ-ПРОВАЛ: '+Why);
end;

procedure OneCapture;
var
  Heap:TGCHeap;
  Closure,Environment,Value,Orphan,Old,NewCell:TGCHandle;
  Lexical:IEnvFrame;
  Code:ICapturedCode;
  Guard:TGCProtectedCapture;
begin
  Heap:=TGCHeap.Create;
  Guard:=nil;
  try
    Closure:=Heap.Allocate(101);
    Environment:=Heap.Allocate(102);
    Value:=Heap.Allocate(103);
    Orphan:=Heap.Allocate(104);
    Lexical:=NewEnvFrame(nil);
    Lexical.InstallLocal(ExactKey('010'),73);
    Guard:=TGCProtectedCapture.Create(Heap,Lexical,73,
      Closure,Environment,Value);
    Code:=Guard.CapturedCode;
    Lexical:=nil; { reference counting в ICapturedCode зберігає IEnvFrame }
    Require(Code.EntryHandle=73,'захоплене opaque entry відрізняється');
    Require(Code.LexicalFrame.Resolve(ExactKey('010'))=73,
      'лексичне оточення не пережило вихід локального scope');
    Require(SameHandle(Guard.ClosureHandle,Closure),
      'фізичний GCHandle замикання втрачено');
    Heap.Link(Value,Closure); { цикл, який mark/sweep має зберегти }
    Require((Heap.ScopeDepth=1) and (Heap.ScopedRootCount=1) and
      (Heap.RootCount=0),'неправильна власність області GC');
    Require(Heap.Collect=1,'не звільнено сироту при живому захопленні');
    Require(Heap.IsAlive(Closure) and Heap.IsAlive(Environment) and
      Heap.IsAlive(Value) and not Heap.IsAlive(Orphan),
      'доступний цикл замикання не збережено');
    Require((Heap.ValueOf(Closure)=101) and (Heap.ValueOf(Value)=103),
      'пошкоджено opaque payload комірок');
    Old:=Closure;
    Guard.Free; Guard:=nil;
    Require((Heap.ScopeDepth=0) and (Heap.ScopedRootCount=0),
      'після release залишилася область коренів');
    Require(Heap.Collect=3,'недосяжний цикл не звільнено');
    Require(not Heap.IsAlive(Old),'доступ до звільненого замикання');
    NewCell:=Heap.Allocate(201);
    Require((NewCell.Slot=Old.Slot) and
      (NewCell.Generation>Old.Generation),'повторно не використано слот');
    Require(not Heap.IsAlive(Old),'старий GCHandle воскрес після reuse');
    Require(Code.LexicalFrame.Resolve(ExactKey('010'))=73,
      'FPC reference counting не є тим самим, що mark/sweep');
    Code:=nil;
    Require(Heap.Collect=1,'після повтору слот не звільнено');
  finally
    Guard.Free;
    Heap.Free;
  end;
end;

procedure ForeignAndStale;
var
  H,Other:TGCHeap;
  A,B,C,Foreign,Stale:TGCHandle;
  Lexical:IEnvFrame;
  Rejected:Boolean;
  Guard:TGCProtectedCapture;
begin
  H:=TGCHeap.Create;
  Other:=TGCHeap.Create;
  Guard:=nil;
  try
    A:=H.Allocate(1);
    B:=H.Allocate(2);
    C:=H.Allocate(3);
    Foreign:=Other.Allocate(4);
    Lexical:=NewEnvFrame(nil);
    Rejected:=False;
    try Guard:=TGCProtectedCapture.Create(H,Lexical,1,A,B,Foreign);
    except on E:EGCError do Rejected:=True; end;
    Require(Rejected and (Guard=nil),'чужа комірка стала замиканням');
    Require((H.ScopeDepth=0) and (H.ScopedRootCount=0),
      'помилка конструктора залишила GC-корінь');
    Rejected:=False;
    try Guard:=TGCProtectedCapture.Create(H,nil,1,A,B,C);
    except on E:EGCError do Rejected:=True; end;
    Require(Rejected and (Guard=nil),'відсутній лексичний frame прийнято');
    Require((H.ScopeDepth=0) and (H.ScopedRootCount=0),
      'відмова nil-frame пошкодила GC-області');
    Stale:=C;
    Require(H.Collect=3,'не звільнено незакріплені початкові комірки');
    A:=H.Allocate(11);
    B:=H.Allocate(12);
    C:=H.Allocate(13);
    Require(not H.IsAlive(Stale),'застарілий handle несправедливо живий');
    Rejected:=False;
    try Guard:=TGCProtectedCapture.Create(H,Lexical,1,A,B,Stale);
    except on E:EGCError do Rejected:=True; end;
    Require(Rejected and (Guard=nil) and
      (H.ScopeDepth=0) and (H.ScopedRootCount=0),
      'старе покоління прийнято або scope протік');
    Require(H.Collect=3,'після негативів залишилася пам’ять');
    Require(Other.Collect=1,'чужу купу пошкоджено');
  finally
    Guard.Free;
    Other.Free;
    H.Free;
  end;
end;

procedure NestedCaptures;
var
  H:TGCHeap;
  A,B,C,D,E,F:TGCHandle;
  Lexical:IEnvFrame;
  Outer,Inner:TGCProtectedCapture;
begin
  H:=TGCHeap.Create;Outer:=nil;Inner:=nil;
  try
    Lexical:=NewEnvFrame(nil);
    A:=H.Allocate(1); B:=H.Allocate(2); C:=H.Allocate(3);
    Outer:=TGCProtectedCapture.Create(H,Lexical,1,A,B,C);
    D:=H.Allocate(4); E:=H.Allocate(5); F:=H.Allocate(6);
    Inner:=TGCProtectedCapture.Create(H,Lexical,2,D,E,F);
    Require((H.ScopeDepth=2) and (H.Collect=0),
      'вкладений GC scope загубив reachable комірки');
    Inner.Free;Inner:=nil;
    Require((H.ScopeDepth=1) and (H.Collect=3) and
      H.IsAlive(A) and H.IsAlive(B) and H.IsAlive(C),
      'внутрішній вихід знищив зовнішнє замикання');
    Outer.Free;Outer:=nil;
    Require((H.ScopeDepth=0) and (H.Collect=3) and (H.LiveCount=0),
      'зовнішній вихід не звільнив graph');
  finally
    Inner.Free;Outer.Free;H.Free;
  end;
end;

procedure RepeatBounded;
var
  H:TGCHeap;
  Lexical:IEnvFrame;
  Guard:TGCProtectedCapture;
  A,B,C:TGCHandle;
  I:SizeInt;
begin
  H:=TGCHeap.Create;
  Guard:=nil;
  try
    Lexical:=NewEnvFrame(nil);
    for I:=1 to 128 do begin
      A:=H.Allocate(I);
      B:=H.Allocate(I+128);
      C:=H.Allocate(I+256);
      Guard:=TGCProtectedCapture.Create(H,Lexical,I,A,B,C);
      Require((H.LiveCount=3) and (H.Collect=0),
        'довга сесія втратила живе захоплення');
      Guard.Free;Guard:=nil;
      Require((H.Collect=3) and (H.LiveCount=0) and
        (H.ScopeDepth=0) and (H.ScopedRootCount=0),
        'корені або об’єкти протекли в довгій сесії');
      Require(H.SlotCount=3,'збирач не повторно використовує слоти');
    end;
  finally
    Guard.Free;H.Free;
  end;
end;

begin
  OneCapture;
  ForeignAndStale;
  NestedCaptures;
  RepeatBounded;
  WriteLn('GC-ЗАХОПЛЕННЯ-ГАРАЗД frame=refcount closure=scope ',
    'graph=3 cycle=так orphan=1 negatives=foreign,stale,nil ',
    'nested=2 reuse=так sessions=128');
end.
