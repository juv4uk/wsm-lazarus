{ Core1.2 — GC-корені для майбутнього лексичного Core1, без власного збирача.
  Мовні закони/викличність НЕ визначаються: pinned external/sens Contract 12.
  Не виконання Core1, а доведений зв'язок wsm.envframe + wsm.gc. }
unit wsm.core1roots;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain, wsm.envframe, wsm.gc;

type
  ECore1RootsError = class(Exception);

  { Heap належить caller; він зобов'язаний жити довше цього об'єкта.
    FClosure — ПОВНИЙ TGCHandle, rooted у тій самій купі.
    FCaptured містить повні owner/slot/generation клітинок.
    FFrame містить лише приватний QWord квиток у FCaptured, не адресу.
    ICapturedCode тримає той самий reference-counted лексичний фрейм.
    Немає власного mark/sweep або повторного таблицювання законів SENS. }
  TCore1RootedClosure = class
  private
    FHeap:TGCHeap;
    FClosure:TGCHandle;
    FFrame:IEnvFrame;
    FCode:ICapturedCode;
    FCaptured:TGCHandles;
    FCallDepth:SizeInt;
    FReleased:Boolean;
    procedure NeedActive;
  public
    constructor Create(AHeap:TGCHeap; const Entry:TGCHandle);
    destructor Destroy; override;
    procedure CaptureExact(const Key:TDomainKey;const Value:TGCHandle);
    function ResolveExact(const Key:TDomainKey):TGCHandle;
    function BeginCall(const Argument:TGCHandle):TGCFrameToken;
    procedure EndCall(const Token:TGCFrameToken);
    function ClosureHandle:TGCHandle;
    procedure Release;
  end;

implementation

procedure TCore1RootedClosure.NeedActive;
begin
  if FReleased then raise ECore1RootsError.Create('замикання вже звільнене');
end;

constructor TCore1RootedClosure.Create(AHeap:TGCHeap;
  const Entry:TGCHandle);
begin
  inherited Create;
  if AHeap=nil then raise ECore1RootsError.Create('відсутня GC-купа');
  if not AHeap.IsAlive(Entry) then
    raise ECore1RootsError.Create('чужий або застарілий вхідний GC-хендл');
  FHeap:=AHeap; FReleased:=True; FCallDepth:=0;
  FFrame:=NewEnvFrame(nil);
  { EntryHandle — тільки приватний host-квиток; не код SENS. }
  FCode:=CaptureCode(FFrame,1);
  FClosure:=FHeap.Allocate(0);
  FHeap.Link(FClosure,Entry);
  FHeap.AddRoot(FClosure);
  FReleased:=False;
end;

destructor TCore1RootedClosure.Destroy;
begin
  if not FReleased then Release;
  inherited Destroy;
end;

{ Key — точна, вже допущена зовні координата, не текстова назва.
  Value повинен бути live TGCHandle цієї самої купи; ані Slot, ані
  десятковий payload не використано для мовної ідентичності.
  Після успішного InstallLocal квиток довговічний до Release.
  GC-ребро від rooted closure залишає значення доступним при Collect.
  Питання: чому QWord у фреймі не можна вважати GCHandle?
  Чому власник/покоління залишаються у FCaptured?
  Чому дубль exact-ключа мусить бути помилкою?
  Чому значення не є D1 навіть якщо payload=1? }
procedure TCore1RootedClosure.CaptureExact(const Key:TDomainKey;
  const Value:TGCHandle);
var Ticket,Existing:QWord; Count:SizeInt;
begin
  NeedActive;
  if not FHeap.IsAlive(Value) then
    raise ECore1RootsError.Create('чужий або застарілий захоплений хендл');
  { Перевірка точного ключа — існуючий wsm.domain, не новий закон. }
  KeyBits(Key);
  if FFrame.TryResolve(Key,Existing) then
    raise ECore1RootsError.Create('повторний точний лексичний ключ');
  Count:=Length(FCaptured);
  if QWord(Count)>=High(QWord)-1 then
    raise ECore1RootsError.Create('вичерпано host-квитки');
  Ticket:=QWord(Count)+1;
  { FHeap.Link може відмовити; у такому випадку фрейм не змінюється. }
  FHeap.Link(FClosure,Value);
  SetLength(FCaptured,Count+1);
  FCaptured[Count]:=Value;
  FFrame.InstallLocal(Key,Ticket);
end;

function TCore1RootedClosure.ResolveExact(const Key:TDomainKey):TGCHandle;
var Ticket:QWord;
begin
  NeedActive;
  Ticket:=FCode.LexicalFrame.Resolve(Key);
  if (Ticket=0) or (Ticket>QWord(Length(FCaptured))) then
    raise ECore1RootsError.Create('некоректний host-квиток замикання');
  Result:=FCaptured[SizeInt(Ticket-1)];
  if not FHeap.IsAlive(Result) then
    raise ECore1RootsError.Create('застаріле захоплене GC-значення');
end;

{ Один stack-frame GC на кожен фізичний виклик, жодного REPL/evaluator.
  RootInScope захищає аргумент до EndCall; caller використовує finally.
  Token — справжній власницький LIFO TGCFrameToken, не SENS значення.
  Питання: чому не можна EndCall зовнішньої рамки першою?
  Коли аргумент стає доступним для Collect?
  Чому цей метод не є семантичним apply? }
function TCore1RootedClosure.BeginCall(
  const Argument:TGCHandle):TGCFrameToken;
begin
  NeedActive;
  if not FHeap.IsAlive(Argument) then
    raise ECore1RootsError.Create('невірний фізичний аргумент GC');
  Result:=FHeap.BeginRootScope;
  try
    FHeap.RootInScope(Result,Argument);
  except
    FHeap.EndRootScope(Result);
    raise;
  end;
  Inc(FCallDepth);
end;

procedure TCore1RootedClosure.EndCall(const Token:TGCFrameToken);
begin
  NeedActive;
  if FCallDepth=0 then
    raise ECore1RootsError.Create('немає активного виклику');
  FHeap.EndRootScope(Token); { перевірка власника/покоління/LIFO — wsm.gc }
  Dec(FCallDepth);
end;

function TCore1RootedClosure.ClosureHandle:TGCHandle;
begin
  NeedActive;
  Result:=FClosure;
end;

procedure TCore1RootedClosure.Release;
begin
  NeedActive;
  if FCallDepth<>0 then
    raise ECore1RootsError.Create('не можна звільнити активне замикання');
  FHeap.RemoveRoot(FClosure);
  FReleased:=True;
  FCode:=nil;
  FFrame:=nil;
  SetLength(FCaptured,0);
  { Повертаємо корені, а не викликаємо Collect примусово.
    Єдиний GC залишився у wsm.gc, збір вирішує власник Heap. }
end;

end.
