{ G5.4 — обмежене виконання D3 через вже злитий оцінювач G3.2.
  Двійкові доменні координати та закони належать pinned SENS.
  Українська «ук» — людиночитана проєкція на вході, НЕ оракул.
  Немає визначень змінних, замикань, Core4 або повноцінного REPL.
  Переданий лексичний контейнер лишається власністю сеансу; п'ять
  підтриманих механізмів G3.2 наразі не читають і не змінюють його. }
unit wsm.sessiond3;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.session;
function NewNativeD3Executor(const PinnedRoot:RawByteString):IFormExecutor;
implementation
uses wsm.source, wsm.envframe, wsm.nativeeval;
type
  TNativeD3Executor=class(TInterfacedObject,IFormExecutor)
  private
    FEvaluator:TNativeEvaluator;
  public
    constructor Create(const PinnedRoot:RawByteString);
    destructor Destroy; override;
    function Execute(const Node:TSourceNode; const Frame:IEnvFrame):RawByteString;
  end;
constructor TNativeD3Executor.Create(const PinnedRoot:RawByteString);
begin
  inherited Create;
  FEvaluator:=TNativeEvaluator.Create(PinnedRoot);
end;
destructor TNativeD3Executor.Destroy;
begin
  FEvaluator.Free;
  inherited Destroy;
end;
function TNativeD3Executor.Execute(const Node:TSourceNode;
  const Frame:IEnvFrame):RawByteString;
begin
  if Frame=nil then
    raise ESessionError.Create('відсутнє середовище сеансу');
  { Не копіюємо семантику: точні D3 біти диспетчеризує лише G3.2.
    Нова інтеграція передає вже розібраний AST без подвійного читання. }
  Result:=FEvaluator.EvaluateNode(Node);
end;
function NewNativeD3Executor(const PinnedRoot:RawByteString):IFormExecutor;
begin
  Result:=TNativeD3Executor.Create(PinnedRoot);
end;
end.
