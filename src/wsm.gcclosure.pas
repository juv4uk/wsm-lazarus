{ Core1.2: міст спільних wsm.gc і wsm.envframe для ФІЗИЧНИХ значень.
  Усі мовні закони бере pinned SENS; цей модуль не виконує Core1.
  GC-комірка зберігає тільки opaque host-token; T5M зберігаємо окремо
  та звільняємо лише після підтвердження смерті покоління. }
unit wsm.gcclosure;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.gc, wsm.envframe, wsm.domain;
type
  EGCClosureError=class(Exception);
  TGCClosureBridge=class;
  TGCActivation=class
  private
    FBridge:TGCClosureBridge; { borrowed: міст живе довше за активацію }
    FToken:TGCFrameToken;
    FAnchor:TGCHandle;
    FFrame:IEnvFrame;
    FScopeActive:Boolean;
    constructor Create(Bridge:TGCClosureBridge; Parent:TGCActivation);
  public
    destructor Destroy; override;
    function LexicalFrame:IEnvFrame;
    function Anchor:TGCHandle;
  end;
  TGCClosure=class
  private
    FBridge:TGCClosureBridge; { borrowed: міст живе довше за замикання }
    FCaptured:ICapturedCode; { чинне захоплення, НЕ новий evaluator }
    FAnchor:TGCHandle;
    constructor Create(Bridge:TGCClosureBridge; Activation:TGCActivation;
      Entry:QWord);
  public
    destructor Destroy; override;
    function EntryHandle:QWord;
  end;
  TGCClosureBridge=class
  private
    type TSlot=record
      Handle:TGCHandle;
      Physical:RawByteString; { managed owned canonical T5M, не Int64 }
    end;
  private
    FHeap:TGCHeap;
    FSlots:array of TSlot; { token = 1-based slot; ніколи не перевикористовуємо }
    function Lookup(Token:QWord):RawByteString;
    procedure CheckActivation(A:TGCActivation);
    procedure CheckClosure(C:TGCClosure);
  public
    constructor Create;
    destructor Destroy; override;
    function BeginActivation(Parent:TGCActivation=nil):TGCActivation;
    procedure BindPhysical(A:TGCActivation; const Key:TDomainKey;
      const Physical:RawByteString; ExplicitWidth:SizeInt);
    function ResolveActivation(A:TGCActivation; const Key:TDomainKey):RawByteString;
    function Capture(A:TGCActivation; Entry:QWord):TGCClosure;
    function ResolveClosure(C:TGCClosure; const Key:TDomainKey):RawByteString;
    function Collect:SizeInt;
    function LiveCount:SizeInt;
    function RootCount:SizeInt;
    function StoredTokens:SizeInt;
    function Heap:TGCHeap; { тільки для механічних тестів графа }
  end;
implementation
uses wsm.t5m;

{ Activation тримає РІВНО ОДИН scoped GC root. Parent є borrowed.
  Лексичний FFrame має RC; GC-якір має явне scope-lifetime.
  Тільки LIFO завершення областей, як у wsm.gc.BeginRootScope.
  Питання: чому RC не замінює GC? Що утримує parent? Чому LIFO? }
constructor TGCActivation.Create(Bridge:TGCClosureBridge;Parent:TGCActivation);
begin
  inherited Create;
  FBridge:=Bridge;
  FScopeActive:=False;
  FToken:=FBridge.FHeap.BeginRootScope;
  FScopeActive:=True;
  try
    FAnchor:=FBridge.FHeap.Allocate(0);
    FBridge.FHeap.RootInScope(FToken,FAnchor);
    if Parent<>nil then begin
      FBridge.CheckActivation(Parent);
      FBridge.FHeap.Link(FAnchor,Parent.FAnchor);
      FFrame:=NewEnvFrame(Parent.FFrame);
    end else FFrame:=NewEnvFrame(nil);
  except
    FBridge.FHeap.EndRootScope(FToken);
    FScopeActive:=False;
    raise;
  end;
end;
destructor TGCActivation.Destroy;
begin
  FFrame:=nil;
  if FScopeActive then FBridge.FHeap.EndRootScope(FToken);
  inherited Destroy;
end;
function TGCActivation.LexicalFrame:IEnvFrame;
begin Result:=FFrame end;
function TGCActivation.Anchor:TGCHandle;
begin Result:=FAnchor end;

{ Замикання використовує існуюче CaptureCode та окремий корінь
  НА ТОЙ САМИЙ якір кадру. Звільнення root не звільняє вузол до sweep.
  Питання: чому FCode зберігає лексичний parent? Чому Root додається
  перед поверненням об'єкта? Чому closure не містить нового закону? }
constructor TGCClosure.Create(Bridge:TGCClosureBridge;
  Activation:TGCActivation;Entry:QWord);
begin
  inherited Create;
  FBridge:=Bridge;
  FCaptured:=CaptureCode(Activation.FFrame,Entry);
  FAnchor:=Activation.FAnchor;
  FBridge.FHeap.AddRoot(FAnchor);
end;
destructor TGCClosure.Destroy;
begin
  FCaptured:=nil;
  FBridge.FHeap.RemoveRoot(FAnchor);
  inherited Destroy;
end;
function TGCClosure.EntryHandle:QWord;
begin Result:=FCaptured.EntryHandle end;

constructor TGCClosureBridge.Create;
begin
  inherited Create;
  FHeap:=TGCHeap.Create;
end;
destructor TGCClosureBridge.Destroy;
begin
  FHeap.Free;
  inherited Destroy;
end;
function TGCClosureBridge.Heap:TGCHeap;
begin Result:=FHeap end;
function TGCClosureBridge.LiveCount:SizeInt;
begin Result:=FHeap.LiveCount end;
function TGCClosureBridge.RootCount:SizeInt;
begin Result:=FHeap.RootCount end;
function TGCClosureBridge.StoredTokens:SizeInt;
begin Result:=Length(FSlots) end;
procedure TGCClosureBridge.CheckActivation(A:TGCActivation);
begin
  if (A=nil) or (A.FBridge<>Self) or not FHeap.IsAlive(A.FAnchor) then
    raise EGCClosureError.Create('чужа або недійсна активація');
end;
procedure TGCClosureBridge.CheckClosure(C:TGCClosure);
begin
  if (C=nil) or (C.FBridge<>Self) or not FHeap.IsAlive(C.FAnchor) then
    raise EGCClosureError.Create('чуже або недійсне замикання');
end;
function TGCClosureBridge.BeginActivation(Parent:TGCActivation):TGCActivation;
begin
  if Parent<>nil then CheckActivation(Parent);
  Result:=TGCActivation.Create(Self,Parent);
end;

{ Фізичний вхід: один canonical T5M-атом, явна ширина від caller.
  Тут немає визначення callable, integer, D1 чи D7 ролі. Результат
  install — тільки host token в існуючому IEnvFrame.
  Пам'ять TSlot.Physical звільняється при Collect після смерті handle.
  Питання: чому Decode+Encode? Де виключено змішану ширину?
  Чому дубль не публікує новий token? Хто очищує string після sweep? }
procedure TGCClosureBridge.BindPhysical(A:TGCActivation;
  const Key:TDomainKey;const Physical:RawByteString;ExplicitWidth:SizeInt);
var W:TExactWords; H:TGCHandle; Token:QWord; N:SizeInt;
begin
  CheckActivation(A);
  if (Physical='') or (Length(Physical)>65536) or
     (ExplicitWidth<1) or (ExplicitWidth>192) then
    raise EGCClosureError.Create('неприпустимий фізичний атом або ширина');
  DecodeT5M(Physical,W);
  if (Length(W)<>1) or (Length(W[0])<>ExplicitWidth) or
     (EncodeT5M(W)<>Physical) then
    raise EGCClosureError.Create('неканонічний одноатомний T5M / домен');
  N:=Length(FSlots);
  if N>=High(SizeInt)-1 then
    raise EGCClosureError.Create('перевищено межу host handle');
  Token:=QWord(N)+1;
  { Виділення capacity перед зміною frame; failed install не видиме. }
  SetLength(FSlots,N+1);
  H:=FHeap.Allocate(Int64(Token));
  try
    FHeap.Link(A.FAnchor,H);
    try A.FFrame.InstallLocal(Key,Token);
    except
      FHeap.Unlink(A.FAnchor,H);
      raise;
    end;
    FSlots[N].Handle:=H;
    FSlots[N].Physical:=Physical;
  except
    SetLength(FSlots,N);
    raise;
  end;
end;
function TGCClosureBridge.Lookup(Token:QWord):RawByteString;
var I:SizeInt;
begin
  if (Token=0) or (Token>QWord(Length(FSlots))) then
    raise EGCClosureError.Create('невідомий фізичний host handle');
  I:=SizeInt(Token-1);
  if not FHeap.IsAlive(FSlots[I].Handle) then
    raise EGCClosureError.Create('використання звільненого фізичного значення');
  Result:=FSlots[I].Physical;
  if Result='' then raise EGCClosureError.Create('фізичний об’єкт недоступний');
end;
function TGCClosureBridge.ResolveActivation(A:TGCActivation;
  const Key:TDomainKey):RawByteString;
begin
  CheckActivation(A);
  Result:=Lookup(A.FFrame.Resolve(Key));
end;
function TGCClosureBridge.Capture(A:TGCActivation;Entry:QWord):TGCClosure;
begin
  CheckActivation(A);
  Result:=TGCClosure.Create(Self,A,Entry);
end;
function TGCClosureBridge.ResolveClosure(C:TGCClosure;
  const Key:TDomainKey):RawByteString;
begin
  CheckClosure(C);
  Result:=Lookup(C.FCaptured.LexicalFrame.Resolve(Key));
end;
function TGCClosureBridge.Collect:SizeInt;
var I:SizeInt;
begin
  Result:=FHeap.Collect;
  for I:=0 to High(FSlots) do
    if not FHeap.IsAlive(FSlots[I].Handle) then
      FSlots[I].Physical:='';
end;
end.
