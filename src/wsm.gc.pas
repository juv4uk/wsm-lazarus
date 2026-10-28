{ Native SENS substrate memory mechanism, not a SENS semantic interpreter.
  Exact domain laws remain in pinned external/sens. }
unit wsm.gc;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  EGCError = class(Exception);
  TGCHeap = class;

  { A token belongs to one concrete heap instance and one activation.
    The owner must outlive all active scopes; EndRootScope is explicit. }
  TGCFrameToken = record
    Owner: TGCHeap;
    Serial: QWord;
  end;

  { Handles are identity by slot AND allocation generation.
    A stale handle cannot alias a different object in a recycled slot. }
  TGCHandle = record
    Slot: SizeInt;
    Generation: QWord;
  end;
  TGCHandles = array of TGCHandle;
  TGCFrame = record
    Token: TGCFrameToken;
    RootStart: SizeInt;
  end;

  TGCHeap = class
  private
    type
      TCell = record
        Live: Boolean;
        Marked: Boolean;
        Generation: QWord;
        Payload: Int64;             { Opaque host test payload, NO SENS law. }
        Edges: TGCHandles;
        NextFree: SizeInt;          { Intrusive free-list link, valid only if not Live. }
      end;
  private
    FCells: array of TCell;
    FRoots: TGCHandles;
    FScopedRoots: TGCHandles;
    FFrames: array of TGCFrame;
    FNextFrameSerial: QWord;
    FLiveCount: SizeInt;
    FFreeHead: SizeInt;             { -1 means no reusable cells. }
    FFreeCount: SizeInt;
    function Valid(const H:TGCHandle):Boolean;
    procedure NeedLive(const H:TGCHandle);
    procedure NeedCurrentScope(const Token:TGCFrameToken);
    procedure MarkCandidate(const H:TGCHandle;
      var Stack:TGCHandles; var Used:SizeInt);
  public
    constructor Create;
    function Allocate(const Payload:Int64):TGCHandle;
    procedure AddRoot(const H:TGCHandle);
    procedure RemoveRoot(const H:TGCHandle);
    function BeginRootScope:TGCFrameToken;
    procedure RootInScope(const Token:TGCFrameToken; const H:TGCHandle);
    procedure EndRootScope(const Token:TGCFrameToken);
    function ScopedRootCount:SizeInt;
    function ScopeDepth:SizeInt;
    procedure Link(const Parent,Child:TGCHandle);
    procedure Unlink(const Parent,Child:TGCHandle);
    function ValueOf(const H:TGCHandle):Int64;
    procedure SetValue(const H:TGCHandle; const Value:Int64);
    function IsAlive(const H:TGCHandle):Boolean;
    function Collect:SizeInt;
    function LiveCount:SizeInt;
    function SlotCount:SizeInt;
    function FreeCount:SizeInt;
    function RootCount:SizeInt;
  end;

function SameHandle(const A,B:TGCHandle):Boolean;

implementation

function SameHandle(const A,B:TGCHandle):Boolean;
begin
  Result:=(A.Slot=B.Slot) and (A.Generation=B.Generation);
end;

function TGCHeap.Valid(const H:TGCHandle):Boolean;
begin
  Result:=(H.Slot>=0) and (H.Slot<Length(FCells));
  if Result then
    Result:=FCells[H.Slot].Live and
      (FCells[H.Slot].Generation=H.Generation) and (H.Generation<>0);
end;

procedure TGCHeap.NeedLive(const H:TGCHandle);
begin
  if not Valid(H) then raise EGCError.Create('stale or invalid GC handle');
end;

function TGCHeap.IsAlive(const H:TGCHandle):Boolean;
begin Result:=Valid(H); end;

constructor TGCHeap.Create;
begin
  inherited Create;
  FFreeHead:=-1;
end;

function TGCHeap.Allocate(const Payload:Int64):TGCHandle;
var Slot:SizeInt;
begin
  { Reuse is O(1): do not scan every allocated cell on each allocation.
    Fresh growth follows the usual FPC dynamic-array allocation policy. }
  if FFreeHead>=0 then begin
    Slot:=FFreeHead;
    if FCells[Slot].Live then
      raise EGCError.Create('GC free-list points at a live slot');
    if FCells[Slot].Generation=High(QWord) then
      raise EGCError.Create('GC generation overflow');
    FFreeHead:=FCells[Slot].NextFree;
    Dec(FFreeCount);
  end else begin
    Slot:=Length(FCells);
    SetLength(FCells,Slot+1);
  end;
  if FCells[Slot].Generation=High(QWord) then
    raise EGCError.Create('GC generation overflow');
  FCells[Slot].NextFree:=-1;
  Inc(FCells[Slot].Generation);
  FCells[Slot].Live:=True;
  FCells[Slot].Marked:=False;
  FCells[Slot].Payload:=Payload;
  SetLength(FCells[Slot].Edges,0);
  Inc(FLiveCount);
  Result.Slot:=Slot;
  Result.Generation:=FCells[Slot].Generation;
end;

procedure TGCHeap.AddRoot(const H:TGCHandle);
var N:SizeInt;
begin
  NeedLive(H);
  N:=Length(FRoots); SetLength(FRoots,N+1); FRoots[N]:=H;
end;

procedure TGCHeap.RemoveRoot(const H:TGCHandle);
var I,J:SizeInt;
begin
  { Handle identity is checked before lookup; dropping stale roots is an error. }
  NeedLive(H);
  for I:=0 to High(FRoots) do
    if SameHandle(FRoots[I],H) then begin
      for J:=I to High(FRoots)-1 do FRoots[J]:=FRoots[J+1];
      SetLength(FRoots,Length(FRoots)-1);
      Exit;
    end;
  raise EGCError.Create('GC root not registered');
end;

procedure TGCHeap.NeedCurrentScope(const Token:TGCFrameToken);
var Last:SizeInt;
begin
  Last:=High(FFrames);
  if (Token.Owner<>Self) or (Token.Serial=0) or (Last<0) then
    raise EGCError.Create('GC root scope invalid or belongs to other heap');
  if FFrames[Last].Token.Serial<>Token.Serial then
    raise EGCError.Create('GC root scope LIFO violation');
end;

function TGCHeap.BeginRootScope:TGCFrameToken;
var N:SizeInt;
begin
  if FNextFrameSerial=High(QWord) then
    raise EGCError.Create('GC root scope serial overflow');
  Inc(FNextFrameSerial);
  Result.Owner:=Self;
  Result.Serial:=FNextFrameSerial;
  N:=Length(FFrames);
  SetLength(FFrames,N+1);
  FFrames[N].Token:=Result;
  FFrames[N].RootStart:=Length(FScopedRoots);
end;

procedure TGCHeap.RootInScope(const Token:TGCFrameToken; const H:TGCHandle);
var N:SizeInt;
begin
  NeedCurrentScope(Token);
  NeedLive(H);
  N:=Length(FScopedRoots);
  SetLength(FScopedRoots,N+1);
  FScopedRoots[N]:=H;
end;

procedure TGCHeap.EndRootScope(const Token:TGCFrameToken);
var N:SizeInt;
begin
  NeedCurrentScope(Token);
  N:=High(FFrames);
  { Releasing roots only drops references, never frees a live object
    until the next explicit Collect. Caller uses try/finally for cleanup. }
  SetLength(FScopedRoots,FFrames[N].RootStart);
  SetLength(FFrames,N);
end;

function TGCHeap.ScopedRootCount:SizeInt;
begin Result:=Length(FScopedRoots); end;

function TGCHeap.ScopeDepth:SizeInt;
begin Result:=Length(FFrames); end;

procedure TGCHeap.Link(const Parent,Child:TGCHandle);
var N:SizeInt;
begin
  NeedLive(Parent);
  NeedLive(Child);
  N:=Length(FCells[Parent.Slot].Edges);
  SetLength(FCells[Parent.Slot].Edges,N+1);
  FCells[Parent.Slot].Edges[N]:=Child;
end;

procedure TGCHeap.Unlink(const Parent,Child:TGCHandle);
var I,J:SizeInt;
begin
  NeedLive(Parent);
  NeedLive(Child);
  for I:=0 to High(FCells[Parent.Slot].Edges) do
    if SameHandle(FCells[Parent.Slot].Edges[I],Child) then begin
      for J:=I to High(FCells[Parent.Slot].Edges)-1 do
        FCells[Parent.Slot].Edges[J]:=FCells[Parent.Slot].Edges[J+1];
      SetLength(FCells[Parent.Slot].Edges,
        Length(FCells[Parent.Slot].Edges)-1);
      Exit;
    end;
  raise EGCError.Create('GC edge not registered');
end;

function TGCHeap.ValueOf(const H:TGCHandle):Int64;
begin NeedLive(H); Result:=FCells[H.Slot].Payload; end;

procedure TGCHeap.SetValue(const H:TGCHandle; const Value:Int64);
begin NeedLive(H); FCells[H.Slot].Payload:=Value; end;

procedure TGCHeap.MarkCandidate(const H:TGCHandle;
  var Stack:TGCHandles; var Used:SizeInt);
begin
  NeedLive(H);
  if FCells[H.Slot].Marked then Exit;
  FCells[H.Slot].Marked:=True;
  if Used=Length(Stack) then SetLength(Stack,Used*2+16);
  Stack[Used]:=H;
  Inc(Used);
end;

function TGCHeap.Collect:SizeInt;
var I,J,Used:SizeInt; Stack:TGCHandles; Current:TGCHandle;
begin
  { Iterative marking: an arbitrarily deep cons graph does not consume
    Pascal call-stack depth. Root multiplicity is reference-counted by
    repeated entries, so removing one root cannot expose a second. }
  SetLength(Stack,0); Used:=0;
  for I:=0 to High(FRoots) do MarkCandidate(FRoots[I],Stack,Used);
  for I:=0 to High(FScopedRoots) do
    MarkCandidate(FScopedRoots[I],Stack,Used);
  while Used>0 do begin
    Dec(Used);
    Current:=Stack[Used];
    for J:=0 to High(FCells[Current.Slot].Edges) do
      MarkCandidate(FCells[Current.Slot].Edges[J],Stack,Used);
  end;
  Result:=0;
  { Sweep backwards and prepend reclaimed indices. This preserves the
    historical first-lowest-free-slot behaviour for a fresh sweep, while
    each subsequent Allocate is O(1) instead of scanning the arena. }
  for I:=High(FCells) downto 0 do
    if FCells[I].Live then begin
      if not FCells[I].Marked then begin
        FCells[I].Live:=False;
        FCells[I].Payload:=0;
        SetLength(FCells[I].Edges,0);
        FCells[I].NextFree:=FFreeHead;
        FFreeHead:=I;
        Inc(FFreeCount);
        Dec(FLiveCount);
        Inc(Result);
      end else FCells[I].Marked:=False;
    end;
end;

function TGCHeap.LiveCount:SizeInt;
begin Result:=FLiveCount; end;
function TGCHeap.SlotCount:SizeInt;
begin Result:=Length(FCells); end;
function TGCHeap.RootCount:SizeInt;
begin Result:=Length(FRoots); end;
function TGCHeap.FreeCount:SizeInt;
begin Result:=FFreeCount; end;
end.
