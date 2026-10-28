{ G5.5: міст до ВЖЕ перевірених upstream фізичних свідків G3.2.
  Не створює власної таблиці функцій, не обчислює семантику за назвами.
  Українська .lisp є лише проєкцією; закони D3 — pinned juv4uk/sens.
  Лексичні визначення користувача та Core4 цим механізмом НЕ виконуються. }
unit wsm.nativeadapter;
{$mode objfpc}{$H+}
interface
uses wsm.session;
function НовийВиконавецьD3(const КоріньSENS:RawByteString):IFormExecutor;
implementation
uses SysUtils, wsm.source, wsm.nativeeval, wsm.envframe;

type
  TОбмеженийВиконавецьD3=class(TInterfacedObject,IFormExecutor)
  private
    FМеханізм:TNativeEvaluator;
  public
    constructor Create(const КоріньSENS:RawByteString);
    destructor Destroy; override;
    function Execute(const Node:TSourceNode;const Frame:IEnvFrame):RawByteString;
  end;

constructor TОбмеженийВиконавецьD3.Create(const КоріньSENS:RawByteString);
begin
  inherited Create;
  FМеханізм:=TNativeEvaluator.Create(КоріньSENS);
end;

destructor TОбмеженийВиконавецьD3.Destroy;
begin
  FМеханізм.Free;
  inherited Destroy;
end;

function TОбмеженийВиконавецьD3.Execute(
  const Node:TSourceNode;const Frame:IEnvFrame):RawByteString;
begin
  if Frame=nil then
    raise ESessionError.Create('відсутній кадр нативної сесії');
  { Кадр фізично зберігається сесією, але п'ять D3-примітивів
    не підтримують user-defined змінних. Його навмисно не читаємо. }
  try
    Result:=FМеханізм.EvaluateNode(Node);
  except
    on E:ENativeEvalError do
      raise ESessionError.CreateFmt('джерело: рядок=%d байт=%d стовпчик=%d: %s',
        [E.Line,E.ByteOffset,E.ByteColumn,E.Message]);
  end;
end;

function НовийВиконавецьD3(const КоріньSENS:RawByteString):IFormExecutor;
begin
  Result:=TОбмеженийВиконавецьD3.Create(КоріньSENS);
end;
end.
