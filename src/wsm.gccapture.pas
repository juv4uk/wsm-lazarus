{ G3.41 — адаптер життєвого циклу ЛЕКСИЧНОГО захоплення до вже
  існуючого wsm.gc. Це НЕ GC-сканер Pascal-інтерфейсів і не SENS evaluator.
  Семантичний авторитет тільки pinned external/sens Contract 12.

  Для існуючих фізичних комірок:
    closure --GC edge--> frame --GC edge--> captured value
  Один діючий root scope зберігає closure до закриття захоплення.
  IEnvFrame/ICapturedCode живуть окремо завдяки FPC reference counting.
  Саме по собі утримання IEnvFrame НЕ утримує GCHandle у TGCHeap.

  Власність: Heap і три GCHandle — позичені; після створення Heap має
  пережити адаптер, а ScopeGuard звільняють у LIFO порядку.
  GC комірки не видаляються деструктором: їх звільняє тільки Collect.
  Вихід: ICapturedCode старого wsm.envframe + захищені фізичні handles.
  Питання: чому інтерфейс не є коренем GC? Чому GCHandle має Owner?
  Чому Scope потребує LIFO? Хто звільняє комірки після Release?
  Чому EntryHandle — opaque host-токен, а не D1/D12 закон? }
unit wsm.gccapture;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.gc, wsm.envframe;

type
  { Короткоживучий захист уже створеного замикання, не allocator GC. }
  TGCProtectedCapture = class
  private
    FHeap: TGCHeap;
    FToken: TGCFrameToken;
    FActive: Boolean;
    FCode: ICapturedCode;
    FClosure, FFrameCell, FValueCell: TGCHandle;
  public
    constructor Create(AHeap:TGCHeap; const LexicalFrame:IEnvFrame;
      EntryHandle:QWord; const ClosureCell, FrameCell, ValueCell:TGCHandle);
    destructor Destroy; override;
    function CapturedCode:ICapturedCode;
    function ClosureHandle:TGCHandle;
  end;

implementation

constructor TGCProtectedCapture.Create(AHeap:TGCHeap;
  const LexicalFrame:IEnvFrame; EntryHandle:QWord;
  const ClosureCell,FrameCell,ValueCell:TGCHandle);
begin
  inherited Create;
  FHeap:=nil;
  FActive:=False;
  if AHeap=nil then
    raise EGCError.Create('немає чинної купи для лексичного захоплення');
  if LexicalFrame=nil then
    raise EGCError.Create('немає лексичного оточення для захоплення');
  { Відмова до відкриття GC scope: owner, покоління й live перевіряє
    виключно існуючий TGCHeap, без ручного порівняння slot. }
  if not AHeap.IsAlive(ClosureCell) or not AHeap.IsAlive(FrameCell) or
     not AHeap.IsAlive(ValueCell) then
    raise EGCError.Create('стороння або звільнена GC-комірка захоплення');
  FCode:=CaptureCode(LexicalFrame,EntryHandle);
  FHeap:=AHeap;
  FClosure:=ClosureCell;
  FFrameCell:=FrameCell;
  FValueCell:=ValueCell;
  FToken:=FHeap.BeginRootScope;
  FActive:=True;
  try
    FHeap.RootInScope(FToken,FClosure);
    FHeap.Link(FClosure,FFrameCell);
    FHeap.Link(FFrameCell,FValueCell);
  except
    FHeap.EndRootScope(FToken);
    FActive:=False;
    raise;
  end;
end;

destructor TGCProtectedCapture.Destroy;
begin
  { Caller повинен дотримуватися LIFO. EndRootScope не запускає Collect
    та не звільняє Pascal reference-counted лексичні об'єкти. }
  if FActive then begin
    FHeap.EndRootScope(FToken);
    FActive:=False;
  end;
  FCode:=nil;
  inherited Destroy;
end;

function TGCProtectedCapture.CapturedCode:ICapturedCode;
begin
  if not FActive then
    raise EGCError.Create('лексичне захоплення вже неактивне');
  Result:=FCode;
end;

function TGCProtectedCapture.ClosureHandle:TGCHandle;
begin
  if not FActive then
    raise EGCError.Create('лексичне захоплення вже неактивне');
  Result:=FClosure;
end;

end.
