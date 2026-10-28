{ G5.5: міст до ВЖЕ перевірених upstream фізичних свідків G3.2.
  Не створює власної таблиці функцій, не обчислює семантику за назвами.
  Українська .lisp є лише проєкцією; закони D3 — pinned juv4uk/sens.
  Лексичні визначення користувача та Core4 цим механізмом НЕ виконуються. }
unit wsm.nativeadapter;
{$mode objfpc}{$H+}
interface
uses wsm.session;
function NovyiVykonavetsD3(const KorinSENS:RawByteString):IFormExecutor;
implementation
uses SysUtils, wsm.source, wsm.nativeeval, wsm.envframe;

type
  TObmezhenyiVykonavetsD3=class(TInterfacedObject,IFormExecutor)
  private
    FMekhanizm:TNativeEvaluator;
  public
    function Object() { [native code] } Create(const KorinSENS:RawByteString);
    destructor Destroy; override;
    function Execute(const Node:TSourceNode;const Frame:IEnvFrame):RawByteString;
  end;

function Object() { [native code] } TObmezhenyiVykonavetsD3.Create(const KorinSENS:RawByteString);
begin
  inherited Create;
  FMekhanizm:=TNativeEvaluator.Create(KorinSENS);
end;

destructor TObmezhenyiVykonavetsD3.Destroy;
begin
  FMekhanizm.Free;
  inherited Destroy;
end;

function TObmezhenyiVykonavetsD3.Execute(
  const Node:TSourceNode;const Frame:IEnvFrame):RawByteString;
begin
  if Frame=nil then
    raise ESessionError.Create('відсутній кадр нативної сесії');
  { Кадр фізично зберігається сесією, але п'ять D3-примітивів
    не підтримують user-defined змінних. Його навмисно не читаємо. }
  try
    Result:=FMekhanizm.EvaluateNode(Node);
  except
    on E:ENativeEvalError do
      raise ESessionError.CreateFmt('джерело: рядок=%d байт=%d стовпчик=%d: %s',
        [E.Line,E.ByteOffset,E.ByteColumn,E.Message]);
  end;
end;

function NovyiVykonavetsD3(const KorinSENS:RawByteString):IFormExecutor;
begin
  Result:=TObmezhenyiVykonavetsD3.Create(KorinSENS);
end;
end.
