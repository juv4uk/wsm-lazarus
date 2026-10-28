{ G7.7: bounded physical GC profiling witness, not SENS language evaluation.
  Host GC handles are NOT binary SENS words or callable identities. }
program test_gc_profile;
{$mode objfpc}{$H+}
uses SysUtils, wsm.gc;
const
  NodeCount = 2048;
  CycleCount = 32;
procedure Require(const Good: Boolean; const Problem: String);
begin
  if not Good then begin
    WriteLn(StdErr, 'GC-PROFILE-FAIL ', Problem);
    Halt(1);
  end;
end;
var
  Heap: TGCHeap;
  Scope: TGCFrameToken;
  First, Previous, Node, Stale: TGCHandle;
  Cycle, I: LongInt;
  TotalAllocations, TotalCollections, TotalReclaimed: LongInt;
  Rejected: Boolean;
begin
  Heap := TGCHeap.Create;
  TotalAllocations := 0;
  TotalCollections := 0;
  TotalReclaimed := 0;
  try
    for Cycle := 1 to CycleCount do begin
      Scope := Heap.BeginRootScope;
      try
        First := Heap.Allocate(Int64(Cycle) * 100000 + 1);
        if Cycle = 1 then Stale := First;
        Inc(TotalAllocations);
        Heap.RootInScope(Scope, First);
        Previous := First;
        for I := 2 to NodeCount do begin
          Node := Heap.Allocate(Int64(Cycle) * 100000 + I);
          Heap.Link(Previous, Node);
          Previous := Node;
          Inc(TotalAllocations);
        end;
        { A cyclic graph must survive a collection through its scoped root. }
        Heap.Link(Previous, First);
        Require(Heap.LiveCount = NodeCount, 'live count before rooted collection');
        Require(Heap.RootCount = 0, 'permanent root leaked');
        Require(Heap.ScopedRootCount = 1, 'one temporary root expected');
        Require(Heap.ScopeDepth = 1, 'one scope expected');
        Require(Heap.Collect = 0, 'reachable cycle was collected');
        Inc(TotalCollections);
        Require(Heap.ValueOf(Previous) = Int64(Cycle)*100000+NodeCount,
          'tail payload corrupted under GC');
        Require(Heap.SlotCount = NodeCount, 'bounded slot count while rooted');
      finally
        Heap.EndRootScope(Scope);
      end;
      Require(Heap.ScopedRootCount = 0, 'temporary root not released');
      Require(Heap.ScopeDepth = 0, 'scope depth leak');
      Require(Heap.Collect = NodeCount, 'unrooted cyclic graph leaked');
      Inc(TotalCollections);
      Inc(TotalReclaimed, NodeCount);
      Require(Heap.LiveCount = 0, 'live cell leaked between cycles');
      Require(Heap.FreeCount = NodeCount, 'free list count mismatch');
      Require(Heap.SlotCount = NodeCount, 'slot reuse failed to stay bounded');
      Require(not Heap.IsAlive(First), 'current generation survived collection');
      Require(not Heap.IsAlive(Stale), 'stale generation alias was resurrected');
    end;
    Rejected := False;
    try Heap.AddRoot(Stale);
    except on E: EGCError do Rejected := True; end;
    Require(Rejected, 'stale root accepted');
    Require(TotalAllocations = NodeCount*CycleCount, 'allocation count incorrect');
    Require(TotalCollections = CycleCount*2, 'collection count incorrect');
    Require(TotalReclaimed = TotalAllocations, 'reclamation count incorrect');
    WriteLn('GC-PROFILE-OK rounds=32 nodes=2048 allocations=65536 ',
      'collections=64 slot-cap=2048 reclaimed=65536 stale=reject scope=pass');
  finally Heap.Free; end;
end.
