{ Нативний міст існуючих GC і лексичних кадрів для майбутнього Core1.
  Не є SENS evaluator, законом, Core1 loader чи власним збирачем. }
unit wsm.core1gcbridge;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.gc,wsm.domain,wsm.envframe;
type
  ECore1GCError=class(Exception);
  ICore1Memory=interface
    ['{275B56CE-314D-4A95-BB2B-E7DE2276407D}']
    function NewValue(Payload:Int64):TGCHandle;
    function Alive(const H:TGCHandle):Boolean;
    function Collect:SizeInt;
    function LiveCount:SizeInt;
    function Roots:SizeInt;
    function BeginStack:TGCFrameToken;
    procedure StackRoot(const Token:TGCFrameToken;const H:TGCHandle);
    procedure EndStack(const Token:TGCFrameToken);
    procedure Link(const A,B:TGCHandle);
    procedure Pin(const H:TGCHandle);
    procedure Unpin(const H:TGCHandle);
    function RegisterHandle(const H:TGCHandle):QWord;
    procedure UndoHandle(Token:QWord);
    function Lookup(Token:QWord):TGCHandle;
  end;
  ICore1Frame=interface;
  ICore1Closure=interface
    ['{30F35F0F-C1AF-4FA9-98EC-7C6706D6B90B}']
    function Entry:TGCHandle;
    function LexicalFrame:ICore1Frame;
  end;
  ICore1Frame=interface
    ['{ADBC4E16-8BFD-4467-8382-57152AF39788}']
    function Memory:ICore1Memory;
    function NativeFrame:IEnvFrame;
    procedure Bind(const Key:TDomainKey;const H:TGCHandle);
    function Resolve(const Key:TDomainKey):TGCHandle;
    function Capture(const Entry:TGCHandle):ICore1Closure;
  end;
function NewCore1Memory:ICore1Memory;
function NewCore1Frame(const M:ICore1Memory;
  const Parent:ICore1Frame):ICore1Frame;
implementation
const MaxHandles=65536; { тільки host quota }
type
  TMemory=class(TInterfacedObject,ICore1Memory)
  private
    H:TGCHeap;
    Handles:TGCHandles;
  public
    constructor Create;
    destructor Destroy;override;
    function NewValue(Payload:Int64):TGCHandle;
    function Alive(const V:TGCHandle):Boolean;
    function Collect:SizeInt;
    function LiveCount:SizeInt;
    function Roots:SizeInt;
    function BeginStack:TGCFrameToken;
    procedure StackRoot(const Token:TGCFrameToken;const V:TGCHandle);
    procedure EndStack(const Token:TGCFrameToken);
    procedure Link(const A,B:TGCHandle);
    procedure Pin(const V:TGCHandle);
    procedure Unpin(const V:TGCHandle);
    function RegisterHandle(const V:TGCHandle):QWord;
    procedure UndoHandle(Token:QWord);
    function Lookup(Token:QWord):TGCHandle;
  end;
  TFrame=class(TInterfacedObject,ICore1Frame)
  private
    M:ICore1Memory;
    Parent:ICore1Frame;
    Native:IEnvFrame;
    Pinned:TGCHandles;
  public
    constructor Create(const Owner:ICore1Memory;const Ancestor:ICore1Frame);
    destructor Destroy;override;
    function Memory:ICore1Memory;
    function NativeFrame:IEnvFrame;
    procedure Bind(const Key:TDomainKey;const V:TGCHandle);
    function Resolve(const Key:TDomainKey):TGCHandle;
    function Capture(const Code:TGCHandle):ICore1Closure;
  end;
  TClosure=class(TInterfacedObject,ICore1Closure)
  private
    M:ICore1Memory;
    Frame:ICore1Frame;
    Captured:ICapturedCode;
    H:TGCHandle;
  public
    constructor Create(const Owner:ICore1Frame;const Code:TGCHandle);
    destructor Destroy;override;
    function Entry:TGCHandle;
    function LexicalFrame:ICore1Frame;
  end;

constructor TMemory.Create;
begin inherited Create;H:=TGCHeap.Create end;
destructor TMemory.Destroy;
begin H.Free;inherited Destroy end;
function TMemory.NewValue(Payload:Int64):TGCHandle;
begin Result:=H.Allocate(Payload) end;
function TMemory.Alive(const V:TGCHandle):Boolean;
begin Result:=H.IsAlive(V) end;
function TMemory.Collect:SizeInt;
begin Result:=H.Collect end;
function TMemory.LiveCount:SizeInt;
begin Result:=H.LiveCount end;
function TMemory.Roots:SizeInt;
begin Result:=H.RootCount end;
function TMemory.BeginStack:TGCFrameToken;
begin Result:=H.BeginRootScope end;
procedure TMemory.StackRoot(const Token:TGCFrameToken;const V:TGCHandle);
begin H.RootInScope(Token,V) end;
procedure TMemory.EndStack(const Token:TGCFrameToken);
begin H.EndRootScope(Token) end;
procedure TMemory.Link(const A,B:TGCHandle);
begin H.Link(A,B) end;
procedure TMemory.Pin(const V:TGCHandle);
begin H.AddRoot(V) end;
procedure TMemory.Unpin(const V:TGCHandle);
begin H.RemoveRoot(V) end;
function TMemory.RegisterHandle(const V:TGCHandle):QWord;
var N:SizeInt;
begin
  if not H.IsAlive(V) then raise ECore1GCError.Create('чужий або stale GC-хендл');
  N:=Length(Handles);
  if N>=MaxHandles then raise ECore1GCError.Create('ліміт host GC-реєстру');
  SetLength(Handles,N+1);Handles[N]:=V;Result:=QWord(N)+1;
end;
procedure TMemory.UndoHandle(Token:QWord);
begin
  if (Token=0) or (Token<>QWord(Length(Handles))) then
    raise ECore1GCError.Create('непослідовний відкат токена');
  SetLength(Handles,Length(Handles)-1);
end;
function TMemory.Lookup(Token:QWord):TGCHandle;
begin
  if (Token=0) or (Token>QWord(Length(Handles))) then
    raise ECore1GCError.Create('невідомий host-токен');
  Result:=Handles[SizeInt(Token-1)];
  if not H.IsAlive(Result) then raise ECore1GCError.Create('звільнений об’єкт');
end;

constructor TFrame.Create(const Owner:ICore1Memory;const Ancestor:ICore1Frame);
var Base:IEnvFrame;
begin
  inherited Create;
  if Owner=nil then raise ECore1GCError.Create('відсутній GC-контекст');
  if (Ancestor<>nil) and (Ancestor.Memory<>Owner) then
    raise ECore1GCError.Create('батьківський кадр з іншої купи');
  M:=Owner;Parent:=Ancestor;Base:=nil;
  if Ancestor<>nil then Base:=Ancestor.NativeFrame;
  Native:=NewEnvFrame(Base);
end;
destructor TFrame.Destroy;
var I:SizeInt;
begin
  for I:=High(Pinned) downto 0 do M.Unpin(Pinned[I]);
  Native:=nil;Parent:=nil;
  inherited Destroy;
end;
function TFrame.Memory:ICore1Memory;
begin Result:=M end;
function TFrame.NativeFrame:IEnvFrame;
begin Result:=Native end;
procedure TFrame.Bind(const Key:TDomainKey;const V:TGCHandle);
var N:SizeInt;Token:QWord;PinnedNow,Registered:Boolean;
begin
  { Окремі exact keys задає вже чинний wsm.envframe, а не текст. }
  N:=Length(Pinned);SetLength(Pinned,N+1);
  PinnedNow:=False;Registered:=False;Token:=0;
  try
    M.Pin(V);PinnedNow:=True;
    Token:=M.RegisterHandle(V);Registered:=True;
    Native.InstallLocal(Key,Token);
    Pinned[N]:=V;
  except
    if Registered then M.UndoHandle(Token);
    if PinnedNow then M.Unpin(V);
    SetLength(Pinned,N);
    raise;
  end;
end;
function TFrame.Resolve(const Key:TDomainKey):TGCHandle;
begin Result:=M.Lookup(Native.Resolve(Key)) end;
function TFrame.Capture(const Code:TGCHandle):ICore1Closure;
begin Result:=TClosure.Create(Self as ICore1Frame,Code) end;

constructor TClosure.Create(const Owner:ICore1Frame;const Code:TGCHandle);
var Token:QWord;Registered,PinnedNow:Boolean;
begin
  inherited Create;
  if Owner=nil then raise ECore1GCError.Create('замикання без кадру');
  Frame:=Owner;M:=Owner.Memory;H:=Code;
  Registered:=False;PinnedNow:=False;Token:=0;
  try
    M.Pin(H);PinnedNow:=True;
    Token:=M.RegisterHandle(H);Registered:=True;
    Captured:=CaptureCode(Owner.NativeFrame,Token);
  except
    if Registered then M.UndoHandle(Token);
    if PinnedNow then M.Unpin(H);
    raise;
  end;
end;
destructor TClosure.Destroy;
begin
  Captured:=nil;
  M.Unpin(H);
  Frame:=nil;
  inherited Destroy;
end;
function TClosure.Entry:TGCHandle;
begin Result:=M.Lookup(Captured.EntryHandle) end;
function TClosure.LexicalFrame:ICore1Frame;
begin Result:=Frame end;
function NewCore1Memory:ICore1Memory;
begin Result:=TMemory.Create end;
function NewCore1Frame(const M:ICore1Memory;
  const Parent:ICore1Frame):ICore1Frame;
begin Result:=TFrame.Create(M,Parent) end;
end.

{ Типи і життя: TGCHandle з GUID+slot+generation належить wsm.gc;
  кадр реєструє opaque QWord у wsm.envframe і GC-root окремо,
  замикання тримає ICapturedCode і кодовий root до кінця свого життя.
  QWord НЕ є числом D12+, TDomainKey W1..W10 НЕ є повним ім'ям D7;
  у цьому зрізі немає функціонального допуску або SENS eval.
  Реєстр host має 65536 слоти/сеанс, не ущільнюється; однопотоковий.
  Питання: чому UID купи важливий? Що утримує батьківський кадр?
  Чому ці roots не еквівалентні semantics? Коли звільняється цикл?
  Чому D1:0 не перетворюється на D3:000? }
