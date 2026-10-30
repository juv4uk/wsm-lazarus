{ G5.4 — обмежене виконання D3 через вже злитий оцінювач G3.2.
  Двійкові доменні координати та закони належать pinned SENS.
  Українська «ук» — людиночитана проєкція на вході, НЕ оракул.
  Немає Core4 і повноцінного REPL: сеанс виконує лише ті механізми, які
  вже є в G3.2 (D3, D5 мітка/SETQ, D10 замикання).

  G6.x — ПОСТІЙНЕ ОТОЧЕННЯ СЕАНСУ. Раніше виконавець кликав
  EvaluateNode, а той у Reset на вході й у finally обнуляв FGlobalEnv
  і арену: кожна форма починалася з порожнього оточення, тобто це був
  обчислювач одного виразу, а не сеанс. Тепер виконавець відкриває
  сесію оцінювача (BeginSession) і обчислює кожну форму в ній
  (EvaluateSessionNode): визначення переживають обчислення.

  Хто володіє AST: сеанс (TNativeSession) звільняв документ після кожної
  форми, а тіло замикання — це вузол TSourceDocument. Тому виконавець
  реалізує IFormExecutorRetains і ПРИЙМАЄ документ у власність; звільняє
  його сесія оцінювача в EndSession/деструкторі. Переданий лексичний
  контейнер IEnvFrame досі не читається і не змінюється — пошук імен
  живе в Assoc/FGlobalEnv оцінювача, і другого реєстру тут немає. }
unit wsm.sessiond3;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.session;
function NewNativeD3Executor(const PinnedRoot:RawByteString):IFormExecutor;
implementation
uses wsm.source, wsm.envframe, wsm.nativeeval;
type
  TNativeD3Executor=class(TInterfacedObject,IFormExecutor,IFormExecutorRetains)
  private
    FEvaluator:TNativeEvaluator;
  public
    constructor Create(const PinnedRoot:RawByteString);
    destructor Destroy; override;
    function Execute(const Node:TSourceNode; const Frame:IEnvFrame):RawByteString;
    { AST форми стає власністю сесії оцінювача. Без цього виклик замикання
      з наступної форми читав би звільнений TSourceDocument. }
    procedure RetainDocument(const Doc:TSourceDocument);
  end;
constructor TNativeD3Executor.Create(const PinnedRoot:RawByteString);
begin
  inherited Create;
  { Комірки не звільняються між формами сеансу, тому бюджет арени більший
    за одноразовий: інакше довгий сеанс упирався б у 'native cell limit'.
    Межа 65536 — та сама, що вже діє в TNativeEvaluator.Create. }
  FEvaluator:=TNativeEvaluator.Create(PinnedRoot,65536,16384,128);
  FEvaluator.BeginSession;
end;
destructor TNativeD3Executor.Destroy;
begin
  { EndSession (у деструкторі оцінювача) звільняє AST усіх форм сеансу. }
  FEvaluator.Free;
  inherited Destroy;
end;
procedure TNativeD3Executor.RetainDocument(const Doc:TSourceDocument);
begin
  FEvaluator.RetainDocument(Doc);
end;
function TNativeD3Executor.Execute(const Node:TSourceNode;
  const Frame:IEnvFrame):RawByteString;
begin
  if Frame=nil then
    raise ESessionError.Create('відсутнє середовище сеансу');
  { Не копіюємо семантику: точні D3 біти диспетчеризує лише G3.2.
    Нова інтеграція передає вже розібраний AST без подвійного читання
    і обчислює його в ПОСТІЙНОМУ оточенні сеансу. }
  Result:=FEvaluator.EvaluateSessionNode(Node);
end;
function NewNativeD3Executor(const PinnedRoot:RawByteString):IFormExecutor;
begin
  Result:=TNativeD3Executor.Create(PinnedRoot);
end;
end.
