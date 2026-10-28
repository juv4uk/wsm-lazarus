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

var H:TGCHeap; A,B,C,Old,Fresh,Loose,Head,Prev,Node,Missing:TGCHandle;
    I:Integer; Rejected:Boolean;
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
    WriteLn('GC-TEST-OK native-mark-sweep=1 cycles=1 deep=2049 ',
      'stale-handles=reject roots=explicit core4=NOT_IMPLEMENTED');
  finally H.Free; end;
end.
