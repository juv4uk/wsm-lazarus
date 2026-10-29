{ G3.41: міст ВЖЕ наявних GC і точних лексичних фреймів.
  Не створює законів SENS: TGCHandle зберігається повністю окремо від
  QWord opaque-ticket чинного IEnvFrame; життєвий цикл керує TGCHeap.
  Купою володіє зовнішній runtime, він мусить пережити всі IRootedFrame. }
unit wsm.gclexical;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.gc, wsm.envframe, wsm.domain;
type
  ERootedFrameError = class(Exception);
  IRootedFrame = interface
    ['{1FDFBB3A-CC09-4058-B19D-C6CDA3558821}']
    procedure Bind(const Key:TDomainKey; const Value:TGCHandle);
    function Resolve(const Key:TDomainKey):TGCHandle;
    function NativeFrame:IEnvFrame;
    function Heap:TGCHeap;
  end;
  IRootedCode = interface
    ['{A725418C-A859-410D-A0DE-56AA440EC5BB}']
    function Captured:ICapturedCode;
    function CapturedFrame:IRootedFrame;
    function Entry:TGCHandle;
  end;

function NewRootedFrame(AHeap:TGCHeap;
  const Parent:IRootedFrame):IRootedFrame;
function CaptureRooted(const Frame:IRootedFrame;
  const Entry:TGCHandle):IRootedCode;

implementation
type
  TFullBinding = record
    Key:TDomainKey;
    Value:TGCHandle; { owner GUID, slot, generation — ніколи не стискаємо }
  end;
  TRootedFrameImpl = class(TInterfacedObject,IRootedFrame)
  private
    FHeap:TGCHeap;                 { borrowed: власник зовнішній runtime }
    FParent:IRootedFrame;         { утримує GC-корені lexical ancestors }
    FFrame:IEnvFrame;
    FBindings:array of TFullBinding;
  public
    constructor Create(AHeap:TGCHeap; const Parent:IRootedFrame);
    destructor Destroy; override;
    procedure Bind(const Key:TDomainKey; const Value:TGCHandle);
    function Resolve(const Key:TDomainKey):TGCHandle;
    function NativeFrame:IEnvFrame;
    function Heap:TGCHeap;
  end;
  TRootedCodeImpl = class(TInterfacedObject,IRootedCode)
  private
    FFrame:IRootedFrame;
    FCode:ICapturedCode;
    FHeap:TGCHeap;              { borrowed, переживає TRootedCodeImpl }
    FEntry:TGCHandle;          { повна фізична ідентичність GC-комірки }
    FRooted:Boolean;
  public
    constructor Create(const Frame:IRootedFrame; const Entry:TGCHandle);
    destructor Destroy; override;
    function Captured:ICapturedCode;
    function CapturedFrame:IRootedFrame;
    function Entry:TGCHandle;
  end;

constructor TRootedFrameImpl.Create(AHeap:TGCHeap; const Parent:IRootedFrame);
var RawParent:IEnvFrame;
begin
  inherited Create;
  if AHeap=nil then
    raise ERootedFrameError.Create('відсутня купа GC');
  if (Parent<>nil) and (Parent.Heap<>AHeap) then
    raise ERootedFrameError.Create('лексичний батько з іншої купи');
  FHeap:=AHeap;
  FParent:=Parent;
  RawParent:=nil;
  if Parent<>nil then RawParent:=Parent.NativeFrame;
  FFrame:=NewEnvFrame(RawParent);
end;

{ Кожен bind створює РІВНО ОДИН persistent GC-root.
  Той самий exact key/handle записано окремо від локального ticket.
  При будь-якій відмові GC-root повертається в початковий стан.
  Питання: чому QWord ticket не TGCHandle? Хто видаляє root?
  Чому замикання повинно втримувати лексичного батька?
  Чому дублікат не може створити додаткового GC-root? }
procedure TRootedFrameImpl.Bind(const Key:TDomainKey;
  const Value:TGCHandle);
var N:SizeInt;
begin
  FHeap.AddRoot(Value);  { foreign/stale перевіряє існуючий GC }
  try
    N:=Length(FBindings);
    if N>=High(QWord) then
      raise ERootedFrameError.Create('переповнення host ticket');
    { Резерв ПЕРЕД публікацією в IEnvFrame — allocation не може
      залишити прихованого ticket після невдалої SetLength. }
    SetLength(FBindings,N+1);
    try
      FFrame.InstallLocal(Key,QWord(N)+1);
    except
      SetLength(FBindings,N);
      raise;
    end;
    FBindings[N].Key:=Key;
    FBindings[N].Value:=Value;
  except
    FHeap.RemoveRoot(Value);
    raise;
  end;
end;

function TRootedFrameImpl.Resolve(const Key:TDomainKey):TGCHandle;
var I:SizeInt; Ticket:QWord;
begin
  { Чинний IEnvFrame є джерелом lexical lookup, не цей масив.
    Пошук повного хендла обмежений лише локальним фреймом; предок
    делегує через власний IRootedFrame без колізії однакових ticket. }
  if not FFrame.TryResolve(Key,Ticket) then
    raise ERootedFrameError.Create('немає точного lexical ключа');
  for I:=0 to High(FBindings) do
    if SameKey(FBindings[I].Key,Key) then begin
      if Ticket<>QWord(I)+1 then
        raise ERootedFrameError.Create('пошкоджений opaque host ticket');
      Result:=FBindings[I].Value;
      if not FHeap.IsAlive(Result) then
        raise ERootedFrameError.Create('звільнений GC handle у фреймі');
      Exit;
    end;
  if FParent<>nil then Exit(FParent.Resolve(Key));
  raise ERootedFrameError.Create('неможливо знайти lexical handle');
end;

function TRootedFrameImpl.NativeFrame:IEnvFrame;
begin Result:=FFrame end;
function TRootedFrameImpl.Heap:TGCHeap;
begin Result:=FHeap end;

destructor TRootedFrameImpl.Destroy;
var I:SizeInt;
begin
  { Корені відпускаються при останньому посиланні на інтерфейс.
    RootedCode утримує IRootedFrame; GC не залежить від FPC RC самих
    клітинок. Умова: живий heap, без concurrent Collect/destruction. }
  if FHeap<>nil then
    for I:=High(FBindings) downto 0 do
      FHeap.RemoveRoot(FBindings[I].Value);
  inherited Destroy;
end;

constructor TRootedCodeImpl.Create(const Frame:IRootedFrame;
  const Entry:TGCHandle);
begin
  inherited Create;
  if Frame=nil then
    raise ERootedFrameError.Create('не можна захопити відсутній фрейм');
  FHeap:=Frame.Heap;
  FRooted:=False;
  FHeap.AddRoot(Entry);
  FRooted:=True;
  try
    FFrame:=Frame;
    FEntry:=Entry;
    { ICapturedCode.EntryHandle — лише host ticket, не SENS domain і
      НЕ точний TGCHandle. Повний handle живе в FEntry; не відновлювати
      owner/generation із slot-токена. }
    FCode:=CaptureCode(Frame.NativeFrame,QWord(Entry.Slot)+1);
  except
    FHeap.RemoveRoot(Entry);
    FRooted:=False;
    raise;
  end;
end;

destructor TRootedCodeImpl.Destroy;
begin
  if FRooted then FHeap.RemoveRoot(FEntry);
  inherited Destroy;
end;

function TRootedCodeImpl.Captured:ICapturedCode;
begin Result:=FCode end;
function TRootedCodeImpl.CapturedFrame:IRootedFrame;
begin Result:=FFrame end;
function TRootedCodeImpl.Entry:TGCHandle;
begin Result:=FEntry end;

function NewRootedFrame(AHeap:TGCHeap;
  const Parent:IRootedFrame):IRootedFrame;
begin Result:=TRootedFrameImpl.Create(AHeap,Parent) end;

function CaptureRooted(const Frame:IRootedFrame;
  const Entry:TGCHandle):IRootedCode;
begin Result:=TRootedCodeImpl.Create(Frame,Entry) end;
end.
