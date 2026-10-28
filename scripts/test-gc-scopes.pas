program test_gc_scopes;
{$mode objfpc}{$H+}
uses SysUtils, wsm.gc;

procedure Check(const Good:Boolean; const Why:String);
begin
  if not Good then begin
    WriteLn(StdErr,'GC-SCOPE-FAIL ',Why);
    Halt(1);
  end;
end;

var Heap, Other:TGCHeap;
    ParentScope, ChildScope, Reopened, Invalid:TGCFrameToken;
    A,B,C,Orphan,Persistent,Stale:TGCHandle;
    Raised:Boolean;
begin
  Heap:=TGCHeap.Create;
  Other:=TGCHeap.Create;
  try
    Persistent:=Heap.Allocate(5);
    Heap.AddRoot(Persistent);
    ParentScope:=Heap.BeginRootScope;
    Check(Heap.ScopeDepth=1,'open outer scope');
    A:=Heap.Allocate(10);
    B:=Heap.Allocate(20);
    Heap.Link(A,B);
    Heap.RootInScope(ParentScope,A);
    Orphan:=Heap.Allocate(30);

    ChildScope:=Heap.BeginRootScope;
    C:=Heap.Allocate(40);
    Heap.RootInScope(ChildScope,C);
    Check((Heap.ScopeDepth=2) and (Heap.ScopedRootCount=2),
      'nested scopes retain both roots');

    { Nested scopes are STRICT LIFO, even on an attempted failure. }
    Raised:=False;
    try Heap.EndRootScope(ParentScope);
    except on E:EGCError do Raised:=True; end;
    Check(Raised,'outer scope ended before inner');
    Raised:=False;
    try Heap.RootInScope(ParentScope,B);
    except on E:EGCError do Raised:=True; end;
    Check(Raised,'added root to outer while inner active');
    Check((Heap.ScopeDepth=2) and (Heap.ScopedRootCount=2),
      'failed scope mutation changed state');

    { Reject cross-heap token before modifying any roots. }
    Raised:=False;
    try Other.RootInScope(ChildScope,Other.Allocate(99));
    except on E:EGCError do Raised:=True; end;
    Check(Raised and (Other.ScopedRootCount=0),'cross-heap token accepted');
    Check(Other.Collect=1,'cross-heap rejected allocation leaked');

    { Failed attempt to root an invalid handle is atomic. }
    Stale:=Orphan;
    Check(Heap.Collect=1,'unrooted orphan not freed');
    Raised:=False;
    try Heap.RootInScope(ChildScope,Stale);
    except on E:EGCError do Raised:=True; end;
    Check(Raised and (Heap.ScopedRootCount=2),'stale scoped root admitted');
    Check(Heap.IsAlive(A) and Heap.IsAlive(B) and Heap.IsAlive(C),
      'live reachable values collected');

    Heap.EndRootScope(ChildScope);
    Check((Heap.ScopeDepth=1) and (Heap.ScopedRootCount=1),
      'child exit lost outer roots');
    Check(Heap.Collect=1,'child-only object retained after scope close');
    Check((not Heap.IsAlive(C)) and Heap.IsAlive(A) and Heap.IsAlive(B),
      'parent root lifetime violation');

    { Closing parent scope drops only temporary roots, NOT persistent ones. }
    Heap.EndRootScope(ParentScope);
    Check((Heap.ScopeDepth=0) and (Heap.ScopedRootCount=0),
      'parent scope exit');
    Check(Heap.Collect=2,'outer graph not freed');
    Check(Heap.IsAlive(Persistent) and (Heap.RootCount=1),
      'persistent root dropped during scope pop');
    Check(Heap.LiveCount=1,'unexpected final live count');

    { Token replay is rejected; a new scope has another serial. }
    Reopened:=Heap.BeginRootScope;
    Check(Reopened.Serial>ChildScope.Serial,'nonmonotone frame serial');
    Raised:=False;
    try Heap.EndRootScope(ChildScope);
    except on E:EGCError do Raised:=True; end;
    Check(Raised and (Heap.ScopeDepth=1),'replayed token was accepted');
    Invalid:=Reopened;
    Invalid.Serial:=0;
    Raised:=False;
    try Heap.EndRootScope(Invalid);
    except on E:EGCError do Raised:=True; end;
    Check(Raised,'zero scope serial accepted');
    Heap.RootInScope(Reopened,Persistent);
    Check(Heap.Collect=0,'rooted object collected');
    Heap.EndRootScope(Reopened);
    Heap.RemoveRoot(Persistent);
    Check(Heap.Collect=1,'last persistent object not reclaimed');
    Check((Heap.LiveCount=0) and (Heap.ScopeDepth=0),
      'heap leaks or still-open scopes');
    WriteLn('GC-SCOPES-OK physical-FPC=1 nested=1 LIFO=reject ',
      'cross-heap=reject stale=reject persistent-roots=preserved ',
      'core4=NOT_IMPLEMENTED');
  finally
    Other.Free;
    Heap.Free;
  end;
end.
