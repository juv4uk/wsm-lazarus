{ G3.41: чинні wsm.gc + wsm.envframe, без SENS-evaluator.
  Усі payload — непрозорі host Int64; exact key не означає викличність. }
program test_gclexical;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.gc, wsm.domain, wsm.envframe, wsm.gclexical;
var
  H,Foreign:TGCHeap;
  A,B,CodeCell,Orphan,ForeignCell,Transient,Old,Fresh:TGCHandle;
  Root,Child,WrongParent:IRootedFrame;
  Closure:IRootedCode;
  Token:TGCFrameToken;
  Raised:Boolean;
  I,Checks:SizeInt;

procedure Need(Condition:Boolean; const Description:String);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,'GC-LEXICAL-ПРОВАЛ: ',Description);
    Halt(1);
  end;
end;

begin
  Checks:=0;
  H:=TGCHeap.Create;
  Foreign:=TGCHeap.Create;
  try
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
    Need(Closure.Captured.EntryHandle<>0,
         'чинний CaptureCode не створив opaque host ticket');
    Need(SameHandle(Closure.CapturedFrame.Resolve(ExactKey('1')),B),
         'замикання не утримало lexical child');
    Need(SameHandle(Closure.CapturedFrame.Resolve(ExactKey('000')),
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
    Need(SameHandle(Closure.CapturedFrame.Resolve(ExactKey('1')),B),
         'захоплене лексичне значення зникло після Collect');
    Need(SameHandle(Closure.CapturedFrame.Resolve(ExactKey('000')),
                    Closure.CapturedFrame.Resolve(ExactKey('000'))),
         'захоплене порожнє значення втрачено');
    Need(H.Collect=0,'живі корені були звільнені повторним Collect');
    Closure:=nil;
    Need(H.RootCount=0,'знищене замикання залишило GC-корені');
    Need(H.Collect=4,'не всі лексичні значення звільнені');
    Need(H.LiveCount=0,'GC не очистив купу після замикання');

    Old:=B;
    Fresh:=H.Allocate(66);
    Need(not H.IsAlive(Old) and H.IsAlive(Fresh),
         'застарілий handle воскрес після повторного використання');
    Raised:=False;
    try Root:=NewRootedFrame(H,nil); Root.Bind(ExactKey('1'),Old);
    except on E:EGCError do Raised:=True; end;
    Need(Raised and H.RootCount=0,'застарілий handle потрапив у фрейм');
    Root:=nil;
    Need(H.Collect=1,'комірка після відмови лишилася');

    { Активні стекові області GC — через чинний Begin/Root/End,
      включно із винятком, без другого збирача сміття. }
    Token:=H.BeginRootScope;
    Transient:=H.Allocate(888);
    try
      H.RootInScope(Token,Transient);
      try
        Need(H.Collect=0 and H.IsAlive(Transient),
             'активний корінь стека втрачений');
        raise Exception.Create('тестовий виняток виконавця');
      except on E:Exception do
        Need(E.Message='тестовий виняток виконавця',
             'помилка поглинута або змінена');
      end;
    finally
      H.EndRootScope(Token);
    end;
    Need(H.ScopeDepth=0 and H.ScopedRootCount=0,
         'GC-root стека не звільнено після винятку');
    Need(H.Collect=1 and (not H.IsAlive(Transient)),
         'витік стекового значення після помилки');

    { 32 життєвих цикли замикань без накопичення в купі. }
    for I:=1 to 32 do begin
      Root:=NewRootedFrame(H,nil);
      A:=H.Allocate(I);
      Root.Bind(ExactKey('0000001'),A);
      CodeCell:=H.Allocate(1000+I);
      Closure:=CaptureRooted(Root,CodeCell);
      Root:=nil;
      Need(H.Collect=0 and H.LiveCount=2,
           'досяжні лексичні корені втрачено');
      Need(H.ValueOf(Closure.CapturedFrame.Resolve(ExactKey('0000001')))=I,
           'перезаписаний payload на наступному циклі');
      Closure:=nil;
      Need(H.RootCount=0 and H.Collect=2 and H.LiveCount=0,
           'довгий сеанс накопичив невивільнені GC комірки');
    end;
    Need(H.SlotCount<=6,'повторне використання GC-комірок не обмежило heap');
    Need(Foreign.IsAlive(ForeignCell),'відмова не повинна зачіпати іншу купу');
    Need(Foreign.Collect=1,'foreign heap не можна звільнити через наш root');
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
