{ Вузький адаптер між СПРАВЖНІМ фізичним D3 evaluator та вже наявним
  TGCHeap. Не виконує Core1, не визначає законів і не є другим GC.
  TGCHeap зберігає reachability; RawByteString залишається в host-таблиці
  лише для актуального handle (GUID/slot/generation). }
unit wsm.gcexecution;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.gc, wsm.binaryexec;

type
  EGCExecution = class(Exception);
  { Значення — exact packed T5M, без текстового декодування та Dn coercion.
    Комірка живе, поки TGCHeap вважає її досяжною; не перетворюємо
    координати на host integer або на QWord-предикат. }
  TPhysicalCell = record
    Handle: TGCHandle;
    Physical: RawByteString;
  end;

  TGCExecution = class
  private
    FHeap: TGCHeap;
    FExecutor: TBinaryExecutor;
    FCells: array of TPhysicalCell;
    function NeedPhysical(const Handle: TGCHandle): SizeInt;
  public
    constructor Create(const AuthorityRoot: RawByteString);
    destructor Destroy; override;
    function BeginScope: TGCFrameToken;
    procedure EndScope(const Token: TGCFrameToken);
    { Вхід — канонічний T5M однієї D2/D3 форми. Вихід — heap handle;
      сама відповідь доступна через PhysicalOf та живе до Collect.
      Token — актуальна область коренів, не SENS D1. }
    function ExecutePhysical(const Physical: RawByteString;
      const Token: TGCFrameToken): TGCHandle;
    function PhysicalOf(const Handle: TGCHandle): RawByteString;
    procedure Link(const Parent, Child: TGCHandle);
    procedure Unlink(const Parent, Child: TGCHandle);
    function Collect: SizeInt;
    function IsAlive(const Handle: TGCHandle): Boolean;
    function LiveCount: SizeInt;
    function SlotCount: SizeInt;
    function ScopeDepth: SizeInt;
    function ScopedRoots: SizeInt;
  end;
implementation
uses wsm.t5m;

constructor TGCExecution.Create(const AuthorityRoot: RawByteString);
begin
  inherited Create;
  FHeap := TGCHeap.Create;
  try
    FExecutor := TBinaryExecutor.Create(AuthorityRoot);
  except
    FHeap.Free;
    raise;
  end;
end;

destructor TGCExecution.Destroy;
begin
  FExecutor.Free;
  FHeap.Free;
  inherited Destroy;
end;

function TGCExecution.BeginScope: TGCFrameToken;
begin
  Result := FHeap.BeginRootScope;
end;

procedure TGCExecution.EndScope(const Token: TGCFrameToken);
begin
  FHeap.EndRootScope(Token);
end;

{ Повертаємо тільки активний handle того САМОГО heap. Після повторного
  використання slot старий Generation не може читати нові фізичні байти.
  Керований Physical належить TGCExecution до наступного Collect/Destroy. }
function TGCExecution.NeedPhysical(const Handle: TGCHandle): SizeInt;
begin
  if (not FHeap.IsAlive(Handle)) or
     (Handle.Slot < 0) or (Handle.Slot >= Length(FCells)) or
     (not SameHandle(FCells[Handle.Slot].Handle, Handle)) or
     (FCells[Handle.Slot].Physical = '') then
    raise EGCExecution.Create('неживий, сторонній або повторно використаний фізичний handle');
  Result := Handle.Slot;
end;

{ Делегує виконання без жодного дублювання D3. Лише ПІСЛЯ повного
  виконання і канонічного round-trip виділяємо GC-об’єкт. Результат
  ховаємо до успішного RootInScope. Якщо Token недійсний, TGCHeap
  відмовляє; недосяжна тимчасова комірка забереться наступним Collect.
  Не торкаємося пам'яті приватної арени TNativeEvaluator. }
function TGCExecution.ExecutePhysical(const Physical: RawByteString;
  const Token: TGCFrameToken): TGCHandle;
var
  Answer: RawByteString;
  Words: TExactWords;
  NewHandle: TGCHandle;
  OldCount: SizeInt;
begin
  if Token.Owner <> FHeap then
    raise EGCExecution.Create('токен належить іншій купі');
  Answer := FExecutor.ExecutePhysicalT5M(Physical);
  DecodeT5M(Answer, Words);
  if EncodeT5M(Words) <> Answer then
    raise EGCExecution.Create('неканонічна фізична відповідь evaluator');
  NewHandle := FHeap.Allocate(0);
  try
    FHeap.RootInScope(Token, NewHandle);
  except
    { Пізній failure до публікації результату: не залишаємо даних
      у фізичній таблиці. Комірку збере виключно штатний TGCHeap. }
    raise;
  end;
  OldCount := Length(FCells);
  if NewHandle.Slot >= OldCount then
    SetLength(FCells, NewHandle.Slot + 1);
  FCells[NewHandle.Slot].Handle := NewHandle;
  FCells[NewHandle.Slot].Physical := Answer;
  Result := NewHandle;
end;

function TGCExecution.PhysicalOf(const Handle: TGCHandle): RawByteString;
begin
  Result := FCells[NeedPhysical(Handle)].Physical;
end;

procedure TGCExecution.Link(const Parent, Child: TGCHandle);
begin
  NeedPhysical(Parent);
  NeedPhysical(Child);
  FHeap.Link(Parent, Child);
end;

procedure TGCExecution.Unlink(const Parent, Child: TGCHandle);
begin
  NeedPhysical(Parent);
  NeedPhysical(Child);
  FHeap.Unlink(Parent, Child);
end;

{ Саме TGCHeap робить mark/sweep та reuse. Після його sweep видаляємо
  managed RawByteString тільки мертвих поколінь; жодного другого обходу
  графа й жодних посилань GC на текстові назви SENS. }
function TGCExecution.Collect: SizeInt;
var I: SizeInt;
begin
  Result := FHeap.Collect;
  for I := 0 to High(FCells) do
    if (FCells[I].Physical <> '') and
       (not FHeap.IsAlive(FCells[I].Handle)) then begin
      FCells[I].Physical := '';
      FCells[I].Handle := Default(TGCHandle);
    end;
end;

function TGCExecution.IsAlive(const Handle: TGCHandle): Boolean;
begin
  Result := FHeap.IsAlive(Handle) and
    (Handle.Slot >= 0) and (Handle.Slot < Length(FCells)) and
    SameHandle(FCells[Handle.Slot].Handle, Handle) and
    (FCells[Handle.Slot].Physical <> '');
end;

function TGCExecution.LiveCount: SizeInt;
begin Result := FHeap.LiveCount; end;
function TGCExecution.SlotCount: SizeInt;
begin Result := FHeap.SlotCount; end;
function TGCExecution.ScopeDepth: SizeInt;
begin Result := FHeap.ScopeDepth; end;
function TGCExecution.ScopedRoots: SizeInt;
begin Result := FHeap.ScopedRootCount; end;
end.
{ Питання: 1) Чому Handle з поколінням не є SENS-словом?
  2) Чому ExecutePhysical зберігає тільки canon T5M-вихід?
  3) Що утримує значення між Collect у вкладених областях?
  4) Чому очищення Physical не виконує власний mark/sweep?
  5) Чому адаптер ще НЕ забезпечує lifetime замикань Core1? }
