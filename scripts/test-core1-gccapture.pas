{ Механічні тести Core1 GC/лексичного захоплення. Це НЕ запуск Core1. }
program test_core1_gccapture;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.gc, wsm.domain, wsm.envframe, wsm.gccapture;

procedure Need(Ok:Boolean; const Why:String);
begin
  if not Ok then raise Exception.Create('CORE1-GC-ПОМИЛКА: '+Why);
end;

var
  H,Other:TGCHeap;
  Parent,Child,Act:TGCScopedLexical;
  ParentCode,ChildCode,A,B:ICapturedCode;
  P,Q,Orphan,Old,Foreign,Extra,RootHandle:TGCHandle;
  ParentAnchor:TGCHandle;
  Local:IEnvFrame;
  Opaque:QWord;
  I:Integer;
  Rejected:Boolean;
begin
  H:=TGCHeap.Create;
  Other:=TGCHeap.Create;
  Parent:=nil; Child:=nil; Act:=nil;
  ParentCode:=nil; ChildCode:=nil; A:=nil; B:=nil; Local:=nil;
  try
    Parent:=TGCScopedLexical.Create(H,nil);
    P:=H.Allocate(101);
    Orphan:=H.Allocate(999);
    Parent.BindLocal(ExactKey('001'),701,P);
    ParentCode:=Parent.Capture(700);
    ParentAnchor:=Parent.AnchorHandle;
    Parent.Free; Parent:=nil;
    Need(H.Collect=1,'непотрібна комірка не зібрана');
    Need(H.IsAlive(P) and H.IsAlive(ParentAnchor),
      'замикання втратило GC-корінь після виходу');
    Need((ParentCode.LexicalFrame.Resolve(ExactKey('001'))=701) and
      (ParentCode.EntryHandle=700),
      'захоплене оточення або непрозорий код');
    Need(H.ScopeDepth=0,'після виходу залишилася область стека');

    Child:=TGCScopedLexical.Create(H,ParentCode.LexicalFrame);
    Child.LinkAncestorRoot(ParentAnchor);
    Q:=H.Allocate(202);
    Child.BindLocal(ExactKey('001'),702,Q);
    H.Link(P,Q);
    H.Link(Q,P); { цикл не є причиною витоку, якщо немає кореня }
    ChildCode:=Child.Capture(800);
    Child.Free; Child:=nil;
    ParentCode:=nil;
    Need((H.Collect=0) and H.IsAlive(P) and H.IsAlive(Q),
      'вкладене замикання втратило доступні предкові комірки');
    Need((ChildCode.EntryHandle=800) and
      (ChildCode.LexicalFrame.Resolve(ExactKey('001'))=702),
      'локальне тінювання знищене після виходу');
    ChildCode:=nil;
    Need((H.Collect=4) and (H.LiveCount=0),
      'недоступний цикл предків або корені замикань не звільнені');
    Old:=P;

    Act:=TGCScopedLexical.Create(H,nil);
    P:=H.Allocate(303);
    Act.BindLocal(ExactKey('001'),909,P);
    A:=Act.Capture(1001);
    B:=Act.Capture(1002);
    Act.Free; Act:=nil;
    A:=nil;
    Need((H.Collect=0) and H.IsAlive(P),
      'друга копія кореня зникла після першого release');
    B:=nil;
    Need((H.Collect=2) and (H.LiveCount=0),
      'останній release не прибрав постійний корінь');
    Need(not H.IsAlive(Old),'застарілий handle знову ожив');

    Act:=TGCScopedLexical.Create(H,nil);
    P:=H.Allocate(404);
    Act.BindLocal(ExactKey('01'),17,P);
    Extra:=H.Allocate(405);
    Rejected:=False;
    try Act.BindLocal(ExactKey('01'),18,Extra);
    except on E:EFrameError do Rejected:=True; end;
    Need(Rejected,'дубль точного ключа прийнято');
    Local:=Act.LexicalFrame;
    Need((Local.Resolve(ExactKey('01'))=17) and
      (H.Collect=1) and not H.IsAlive(Extra),
      'невдала установка залишила зайвий GC-edge');
    Local:=nil;
    Foreign:=Other.Allocate(888);
    Rejected:=False;
    try Act.BindLocal(ExactKey('111'),19,Foreign);
    except on E:EGCCaptureError do Rejected:=True; end;
    Need(Rejected,'сторонній GC-handle прийнято');
    Local:=Act.LexicalFrame;
    Need(not Local.TryResolve(ExactKey('111'),Opaque),
      'чужа комірка залишила неповний лексичний binding');
    Local:=nil;
    Rejected:=False;
    try Act.LinkAncestorRoot(Old);
    except on E:EGCError do Rejected:=True; end;
    Need(Rejected,'stale ancestor не відхилено');
    Rejected:=False;
    try Act.LinkAncestorRoot(Foreign);
    except on E:EGCError do Rejected:=True; end;
    Need(Rejected,'сторонній lexical GC-anchor прийнято');
    Act.Free; Act:=nil;
    Need((H.Collect=2) and (H.LiveCount=0),
      'відмова не звільнила GC-область');

    { 64 послідовні захоплення, як у довгоживучому сеансі. }
    for I:=1 to 64 do begin
      Act:=TGCScopedLexical.Create(H,nil);
      P:=H.Allocate(I);
      Act.BindLocal(ExactKey('001'),QWord(I),P);
      A:=Act.Capture(QWord(I));
      Act.Free; Act:=nil;
      Need((H.Collect=0) and H.IsAlive(P) and
        (A.LexicalFrame.Resolve(ExactKey('001'))=QWord(I)),
        'живе замикання втратило параметр у повторному виклику');
      A:=nil;
      Need((H.Collect=2) and (H.LiveCount=0) and
        (H.ScopeDepth=0) and (H.RootCount=0),
        'витік кореня або heap після повторного виклику');
    end;
    Need(H.SlotCount<=6,'пам’ять зростає з кожним замиканням');

    { Перевірка виключення: try/finally має закрити область коренів. }
    Rejected:=False;
    try
      Act:=TGCScopedLexical.Create(H,nil);
      try
        P:=H.Allocate(777);
        Act.BindLocal(ExactKey('1'),77,P);
        raise Exception.Create('тестова відмова посеред виклику');
      finally
        Act.Free; Act:=nil;
      end;
    except on E:Exception do
      Rejected:=E.Message='тестова відмова посеред виклику';
    end;
    Need(Rejected and (H.ScopeDepth=0) and (H.Collect=2) and
      (H.LiveCount=0),'після виключення лишилися корені');
    WriteLn('CORE1-GC-ЗАХОПЛЕННЯ-ГАРАЗД ',
      'лексика=збережена покоління=захищені ',
      'багатокореневість=так цикли=зібрано ',
      'пізня-помилка=очищено повтори=64 ',
      'семантика-Core1=ЩЕ-НЕ-ВИКОНАНО');
  finally
    ChildCode:=nil; ParentCode:=nil; A:=nil; B:=nil; Local:=nil;
    Child.Free; Parent.Free; Act.Free;
    Other.Free;
    H.Free;
  end;
end.
