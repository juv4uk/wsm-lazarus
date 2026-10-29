program test_core1gcbridge;
{$mode objfpc}{$H+}
uses SysUtils,wsm.gc,wsm.domain,wsm.core1gcbridge;
procedure Check(B:Boolean;const S:String);
begin
  if not B then begin WriteLn(StdErr,'CORE1-GC-FAIL ',S);Halt(1) end;
end;

{ Межа процедури — справжній термін життя локальних інтерфейсів FPC.
  Відпускати їх лише присвоєнням nil всередині того самого scope недостатньо:
  compiler-managed temporaries можуть жити до виходу з процедури.
  Тому root count перевіряємо ПІСЛЯ цієї межі, а не раніше. }
procedure ExerciseCapture(const M,Other:ICore1Memory;out Retired:TGCHandle);
var
  Root,Child,Foreign:ICore1Frame;
  Code:ICore1Closure;
  A,B,C,Entry,Unrooted,Temp:TGCHandle;
  Outer,Inner:TGCFrameToken;
  Rejected:Boolean;
begin
  Root:=NewCore1Frame(M,nil);
  A:=M.NewValue(10);B:=M.NewValue(20);
  Retired:=A;
  M.Link(A,B);M.Link(B,A);
  Root.Bind(ExactKey('1'),A);
  Child:=NewCore1Frame(M,Root);
  C:=M.NewValue(30);
  Child.Bind(ExactKey('001'),C);
  Child.Bind(ExactKey('0'),B);
  Check(M.Roots=3,'roots for three frame values');
  Check(M.Collect=0,'live cycle reclaimed');
  Check(SameHandle(Child.Resolve(ExactKey('1')),A),'lexical parent');
  Check(SameHandle(Child.Resolve(ExactKey('001')),C),'three-bit key');
  Check(SameHandle(Child.Resolve(ExactKey('0')),B),'D1:0 not D3:000');

  Rejected:=False;
  try Child.Bind(ExactKey('001'),M.NewValue(77));
  except on E:Exception do Rejected:=True end;
  Check(Rejected and (M.Roots=3),'duplicate pin leaked');

  Foreign:=NewCore1Frame(Other,nil);
  Rejected:=False;
  try Foreign.Bind(ExactKey('1'),A);
  except on E:Exception do Rejected:=True end;
  Check(Rejected and (Other.Roots=0),'cross heap accepted');
  Rejected:=False;
  try Foreign:=NewCore1Frame(Other,Root);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,'foreign parent accepted');

  Entry:=M.NewValue(404);
  Code:=Child.Capture(Entry);
  Check(M.Roots=4,'closure code not rooted');
  Check(M.Collect=1,'failed duplicate orphan should be collected');
  Check(SameHandle(Code.Entry,Entry),'captured code lost');
  Check(SameHandle(Code.Resolve(ExactKey('1')),A),'captured lexical parent lost');
  Check(SameHandle(Code.Resolve(ExactKey('001')),C),'captured local lost');

  Outer:=M.BeginStack;
  Unrooted:=M.NewValue(55);M.StackRoot(Outer,Unrooted);
  Inner:=M.BeginStack;
  Temp:=M.NewValue(66);M.StackRoot(Inner,Temp);
  Check(M.Collect=0,'stack root lost');
  Rejected:=False;
  try M.EndStack(Outer);
  except on E:EGCError do Rejected:=True end;
  Check(Rejected,'non-LIFO end accepted');
  M.EndStack(Inner);
  Check(M.Collect=1,'inner scope not reclaimed');
  Check(not M.Alive(Temp),'inner stale object alive');
  M.EndStack(Outer);
  Check(M.Collect=1,'outer scope not reclaimed');

  { Точне закриття scope відбувається при виході з ПРОЦЕДУРИ:
    жоден compiler-managed interface temporary не зберігає корінь. }
  Code:=nil;Child:=nil;Root:=nil;Foreign:=nil;
end;

procedure SingleIteration(const M:ICore1Memory;I:Integer);
var Frame:ICore1Frame;Code:ICore1Closure;
    A,Entry:TGCHandle;
begin
  Frame:=NewCore1Frame(M,nil);
  A:=M.NewValue(I);Frame.Bind(ExactKey('1'),A);
  Entry:=M.NewValue(I+1000);
  Code:=Frame.Capture(Entry);
  Check(M.Collect=0,'active closure collected');
  Check(SameHandle(Code.Resolve(ExactKey('1')),A),'closure lifetime lost');
  Code:=nil;Frame:=nil;
end;

var M,Other:ICore1Memory;Stale:TGCHandle;
    Root:ICore1Frame;Rejected:Boolean;I:Integer;
begin
  M:=NewCore1Memory;Other:=NewCore1Memory;
  ExerciseCapture(M,Other,Stale);
  Check(M.Roots=0,'end of lexical lifetime leaked roots');
  Check(M.Collect=4,'released closure graph was not reclaimed');
  Check(M.LiveCount=0,'heap not empty after lexical scope');
  Rejected:=False;
  Root:=NewCore1Frame(M,nil);
  try Root.Bind(ExactKey('1'),Stale);
  except on E:Exception do Rejected:=True end;
  Check(Rejected and (M.Roots=0),'stale handle admitted');
  Root:=nil;
  for I:=1 to 128 do begin
    SingleIteration(M,I);
    Check(M.Roots=0,'iteration leaked GC roots');
    Check(M.Collect=2,'iteration failed to reclaim');
    Check(M.LiveCount=0,'iteration retained heap cells');
  end;
  Check(M.Roots=0,'final roots remain');
  WriteLn('CORE1-GC-МІСТ-ГАРАЗД цикли=зібрані кадри=утримані ',
    'стек=LIFO stale=відхилено чужа-купа=відхилено ',
    '128-сеансів=пройдено виконання-Core1=НЕ-ДОВЕДЕНО');
end.
