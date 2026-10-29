program test_gc;
{$mode objfpc}{$H+}
uses SysUtils, wsm.gc;

procedure Check(const Good:Boolean; const Reason:String);
begin
  if not Good then begin
    WriteLn(StdErr,'GC-FAIL ',Reason);
    Halt(1);
  end;
end;

{ Regression: formerly both heaps used slot=0,generation=1, and a
  handle from heap B was accepted as heap A's own object. }
procedure TestForeignHeapHandles;
var AHeap, BHeap, LaterHeap:TGCHeap;
    A, B, Later, Forged:TGCHandle;
    Token, ForeignToken, OtherToken:TGCFrameToken;
    Rejected:Boolean;
begin
  AHeap:=TGCHeap.Create;
  BHeap:=TGCHeap.Create;
  try
    A:=AHeap.Allocate(11);
    B:=BHeap.Allocate(22);
    Check((A.Slot=B.Slot) and (A.Generation=B.Generation),
      'cross-heap collision witness missing');
    Check(not SameHandle(A,B),'foreign handles compare equal');
    Check((not AHeap.IsAlive(B)) and (not BHeap.IsAlive(A)),
      'foreign handles silently accepted by IsAlive');

    Rejected:=False;
    try AHeap.ValueOf(B); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign read accepted');
    Rejected:=False;
    try AHeap.SetValue(B,77); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign mutation accepted');
    Check((AHeap.ValueOf(A)=11) and (BHeap.ValueOf(B)=22),
      'foreign mutation changed a live value');

    Rejected:=False;
    try AHeap.AddRoot(B); except on E:EGCError do Rejected:=True; end;
    Check(Rejected and (AHeap.RootCount=0),'foreign permanent root accepted');
    Rejected:=False;
    try AHeap.RemoveRoot(B); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign root removal accepted');
    Rejected:=False;
    try AHeap.Link(A,B); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign child edge accepted');
    Rejected:=False;
    try AHeap.Link(B,A); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign parent edge accepted');
    Rejected:=False;
    try AHeap.Unlink(A,B); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'foreign child unlink accepted');

    Token:=AHeap.BeginRootScope;
    try
      AHeap.RootInScope(Token,A);
      Rejected:=False;
      try AHeap.RootInScope(Token,B);
      except on E:EGCError do Rejected:=True; end;
      Check(Rejected and (AHeap.ScopedRootCount=1),
        'foreign scoped root accepted');
      { Дві незалежні купи мають однаковий початковий serial.
        Підміна адреси моделює її повторне використання після звільнення. }
      OtherToken:=BHeap.BeginRootScope;
      try
        Check(Token.Serial=OtherToken.Serial,
          'свідок повторного серійного номера GC відсутній');
        ForeignToken:=Token;
        ForeignToken.Owner:=BHeap;
        Rejected:=False;
        try BHeap.RootInScope(ForeignToken,B);
        except on E:EGCError do Rejected:=True; end;
        Check(Rejected and (BHeap.ScopedRootCount=0) and
          (BHeap.ScopeDepth=1),
          'сторонній токен змінив корені після підміни адреси');

        Rejected:=False;
        try BHeap.EndRootScope(ForeignToken);
        except on E:EGCError do Rejected:=True; end;
        Check(Rejected and (BHeap.ScopeDepth=1),
          'сторонній токен закрив чужу область після підміни адреси');

        BHeap.RootInScope(OtherToken,B);
        Check((BHeap.ScopedRootCount=1) and (BHeap.Collect=0) and
          BHeap.IsAlive(B),
          'дійсний токен перестав зберігати корінь');
      finally
        BHeap.EndRootScope(OtherToken);
      end;
      Check(AHeap.Collect=0,'local scoped root was lost');
    finally
      AHeap.EndRootScope(Token);
    end;

    Forged:=A;
    FillChar(Forged.Owner,SizeOf(Forged.Owner),0);
    Check(not AHeap.IsAlive(Forged),'zero heap owner accepted');
    Rejected:=False;
    try AHeap.SetValue(Forged,99);
    except on E:EGCError do Rejected:=True; end;
    Check(Rejected and (AHeap.ValueOf(A)=11),
      'zero-owner mutation reached local object');

    Check(AHeap.Collect=1,'local object not reclaimed');
    Check(BHeap.IsAlive(B) and (BHeap.ValueOf(B)=22),
      'independent heap corrupted by local collect');
  finally
    BHeap.Free;
    AHeap.Free;
  end;
  { Heap identity must also survive destruction followed by new allocation,
    not merely compare pointer addresses of heap objects. }
  LaterHeap:=TGCHeap.Create;
  try
    Later:=LaterHeap.Allocate(33);
    Check((Later.Slot=A.Slot) and (Later.Generation=A.Generation),
      'post-destruction collision witness missing');
    Check(not SameHandle(A,Later),'destroyed-heap handle aliased new heap');
    Check(not LaterHeap.IsAlive(A),'destroyed-heap handle was resurrected');
    Check(LaterHeap.Collect=1,'new heap orphan collection');
  finally LaterHeap.Free; end;
  WriteLn('GC-OWNER-OK cross-heap=reject slot-generation-collision=1 ',
    'foreign-mutation=reject roots=isolated recycled-owner=reject');
end;

var H:TGCHeap; A,B,C,Old,Fresh,Loose,Head,Prev,Node,Missing:TGCHandle;
    I:Integer; Rejected:Boolean; FirstWave,FirstAgain,Guard:TGCHandle;
begin
  H:=TGCHeap.Create;
  try
    { Physical graph: A<->B is a reachable cycle, C is unrooted. }
    A:=H.Allocate(11); B:=H.Allocate(12); C:=H.Allocate(13);
    H.Link(A,B); H.Link(B,A); H.AddRoot(A);
    Check(H.LiveCount=3,'allocation count');
    Check(H.Collect=1,'collect orphan');
    Check(H.IsAlive(A) and H.IsAlive(B) and not H.IsAlive(C),
      'reachable cycle retained, orphan freed');
    Check((H.ValueOf(A)=11) and (H.ValueOf(B)=12),'payload retained');
    H.RemoveRoot(A);
    Check(H.Collect=2,'unreachable cycle reclaimed');
    Check(H.LiveCount=0,'cycle leak');
    Check(H.Collect=0,'second collection not idempotent');

    { Reuse the slot without allowing old handle to alias fresh payload. }
    Old:=A;
    Fresh:=H.Allocate(44);
    Check((Fresh.Slot=Old.Slot) and
      (Fresh.Generation>Old.Generation),'generation on slot reuse');
    Check(not H.IsAlive(Old),'stale alias was accepted');
    Rejected:=False;
    try H.SetValue(Old,12345); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'stale mutation accepted');
    Rejected:=False;
    try H.Link(Fresh,Old); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'stale graph edge accepted');
    Check(H.ValueOf(Fresh)=44,'stale mutation changed live node');

    { Multiple explicit roots: one removal does not collect the node. }
    H.AddRoot(Fresh); H.AddRoot(Fresh);
    H.RemoveRoot(Fresh);
    Check(H.RootCount=1,'root multiplicity');
    Check(H.Collect=0,'node with second root was collected');
    H.RemoveRoot(Fresh);
    Check(H.Collect=1,'rootless node not collected');
    Rejected:=False;
    try H.AddRoot(Fresh); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'root resurrected stale node');

    { Unlink one edge; the child must become unreachable next sweep. }
    A:=H.Allocate(1); B:=H.Allocate(2);
    H.AddRoot(A); H.Link(A,B);
    Check(H.Collect=0,'linked child collected');
    H.Unlink(A,B);
    Check(H.Collect=1,'unlinked child survived');
    H.RemoveRoot(A);
    Check(H.Collect=1,'unrooted parent survived');

    { Marking must not recurse on the Pascal stack. }
    Head:=H.Allocate(100);
    H.AddRoot(Head);
    Prev:=Head;
    for I:=1 to 2048 do begin
      Node:=H.Allocate(I);
      H.Link(Prev,Node);
      Prev:=Node;
    end;
    Check(H.Collect=0,'reachable deep chain collected');
    Check(H.LiveCount=2049,'deep chain count');
    Check(H.ValueOf(Prev)=2048,'deep chain tail');
    H.RemoveRoot(Head);
    Check(H.Collect=2049,'deep graph leak');
    Check(H.LiveCount=0,'heap leak after deep chain');

    Missing.Slot:=-1; Missing.Generation:=1;
    Rejected:=False;
    try H.AddRoot(Missing); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'invalid slot accepted');
    Loose:=H.Allocate(99);
    Rejected:=False;
    try H.RemoveRoot(Loose); except on E:EGCError do Rejected:=True; end;
    Check(Rejected,'unregistered root removal accepted');
    Check(H.Collect=1,'last orphan');
    { Repeated reuse must not grow the arena or alias a previous handle.
      An O(N) scan on every Allocate would make this path quadratic. }
    for I:=1 to 8192 do begin
      Node:=H.Allocate(I);
      if I=1 then FirstWave:=Node;
    end;
    Check(H.LiveCount=8192,'first full allocation count');
    Check(H.SlotCount=8192,'unbounded initial arena growth');
    Check(H.FreeCount=0,'free cells counted as live');
    Check(H.Collect=8192,'first bulk sweep');
    Check(H.FreeCount=8192,'free-list count after bulk sweep');
    for I:=1 to 8192 do begin
      Node:=H.Allocate(I+10000);
      if I=1 then FirstAgain:=Node;
    end;
    Check(SameHandle(FirstWave,FirstAgain)=False,
      'stale identity aliased across full free-list reuse');
    Check((FirstWave.Slot=FirstAgain.Slot) and
      (FirstAgain.Generation>FirstWave.Generation),
      'generation did not advance on bulk reuse');
    Check(not H.IsAlive(FirstWave),'stale bulk handle still live');
    Check((H.SlotCount=8192) and (H.FreeCount=0) and
      (H.LiveCount=8192),'free-list did not reuse bounded capacity');
    Check(H.Collect=8192,'second bulk sweep');
    Check((H.FreeCount=8192) and (H.LiveCount=0),
      'second sweep lost free slots');
    { A live root must never be placed onto the free list. }
    Guard:=H.Allocate(991);
    H.AddRoot(Guard);
    for I:=1 to 8191 do H.Allocate(I);
    Check(H.Collect=8191,'partial sweep reclaimed rooted cell');
    Check(H.IsAlive(Guard) and (H.ValueOf(Guard)=991),
      'guard was collected during partial sweep');
    Check((H.FreeCount=8191) and (H.LiveCount=1),
      'partial free-list count');
    for I:=1 to 8191 do H.Allocate(I+20000);
    Check(H.IsAlive(Guard) and (H.ValueOf(Guard)=991),
      'reuse overwrote rooted cell');
    Check((H.SlotCount=8192) and (H.FreeCount=0),
      'partial reuse grew arena');
    Check(H.Collect=8191,'partial reused children not swept');
    H.RemoveRoot(Guard);
    Check(H.Collect=1,'guard not freed after removing root');
    Check((H.FreeCount=8192) and (H.LiveCount=0),
      'free-count invariant after final sweep');
    WriteLn('GC-FREELIST-OK slots=8192 reuse=8192 roots=preserved ',
      'stale-handles=reject');
    TestForeignHeapHandles;
    WriteLn('GC-TEST-OK native-mark-sweep=1 cycles=1 deep=2049 ',
      'stale-handles=reject roots=explicit core4=NOT_IMPLEMENTED');
  finally H.Free; end;
end.
