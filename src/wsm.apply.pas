{ Застосування користувацької функції — простим шляхом: підстановка.

  Навіщо окремий модуль: wsm.nativeeval — принципово безстановий
  evaluator (Eval(N, Depth), без середовища). Додавати в нього кадр
  виклику означало б переписати те, що зараз працює. Тут — надбудова:
  підставити аргументи в тіло й віддати наявному Eval.

  Межа, названа прямо: це ПІДСТАНОВКА, а не замикання.
    • параметри замінюються на вже обчислені значення;
    • вільного захоплення змінних немає — тіло бачить лише параметри;
    • тому (функція (x) (+ x 1)) працює, а тіло з вільним y — ні,
      і це буде помилкою, а не тихою неправдою.

  Модель вузлів узята з wsm.source.pas, не вигадана:
    TSourceNode = class
      Kind: TSourceKind;            (skList, skAtom, skString)
      Text: RawByteString;
      Children: array of TSourceNode;
      procedure Add(Child: TSourceNode);

  Закони мови належать pinned SENS, не Pascal. Тут немає ні нових
  доменів, ні нових бітів, ні власного реєстру функцій. }
unit wsm.apply;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.source, wsm.nativeeval;
type
  EApplyError=class(ESourceError);

{ Чи це форма (функція (параметри) тіло…)?
  Перевіряється СТРУКТУРА: голова — список, перший атом «функція»,
  другий елемент — список параметрів. Назва тут — людська проєкція,
  а не семантичний dispatch: рішення ухвалює структура. }
function IsLambdaForm(Expr:TSourceNode):Boolean;

{ Перевірка арності ДО підстановки. Зайвий або відсутній аргумент —
  помилка, не порожнеча. }
procedure CheckArity(Expr:TSourceNode; ArgCount:SizeInt);

{ Підставити ВЖЕ обчислені аргументи в тіло й повернути новий вузол.

  Вхідне дерево не змінюється: будуємо копію. Викликач володіє
  результатом і звільняє його сам.

  Повертає тіло (одне) або список тіл (якщо їх кілька), готовий для
  Eval. Сам не обчислює — обчислення лишається за одним evaluator-ом,
  щоб не завести другий. }
function SubstituteArguments(Expr:TSourceNode;
  const Args:array of TSourceNode):TSourceNode;

implementation

function AtomText(N:TSourceNode):RawByteString;
begin
  Result:='';
  if (N<>nil) and (N.Kind=skAtom) then Result:=N.Text;
end;

function IsLambdaForm(Expr:TSourceNode):Boolean;
var Head:TSourceNode;
begin
  Result:=False;
  if (Expr=nil) or (Expr.Kind<>skList) then Exit;
  if Length(Expr.Children)<3 then Exit;          { голова, параметри, тіло }
  Head:=Expr.Children[0];
  if (Head=nil) or (Head.Kind<>skList) then Exit;
  if Length(Head.Children)<1 then Exit;
  if AtomText(Head.Children[0])<>'функція' then Exit;
  if (Expr.Children[1]=nil) or (Expr.Children[1].Kind<>skList) then Exit;
  Result:=True;
end;

procedure CheckArity(Expr:TSourceNode; ArgCount:SizeInt);
var Declared:SizeInt;
begin
  if not IsLambdaForm(Expr) then
    raise EApplyError.CreateAt('не форма (функція (…) …)', 0, 0, 0);
  Declared:=Length(Expr.Children[1].Children);
  if ArgCount<>Declared then
    raise EApplyError.CreateAt(Format(
      'арність: оголошено %d, передано %d', [Declared, ArgCount]), 0, 0, 0);
end;

function SubstituteArguments(Expr:TSourceNode;
  const Args:array of TSourceNode):TSourceNode;
var
  Names:array of RawByteString;
  I:SizeInt;

  { Копія вузла з підставленими параметрами.
    Нові вузли алокуються: TSourceNode — клас, і мутація вхідного
    дерева зіпсувала б AST викликача. }
  function Walk(N:TSourceNode):TSourceNode;
  var K:SizeInt; Vuzol:TSourceNode;
  begin
    if N=nil then Result:=nil; Exit;
    if N.Kind=skAtom then begin
      for K:=0 to High(Names) do
        if N.Text=Names[K] then Result:=Args[K]; Exit;
      Vuzol:=TSourceNode.Create;
      Vuzol.Kind:=N.Kind;
      Vuzol.Text:=N.Text;
      Vuzol.ByteOffset:=N.ByteOffset;
      Vuzol.Line:=N.Line;
      Vuzol.ByteColumn:=N.ByteColumn;
      Vuzol.EndByteExclusive:=N.EndByteExclusive;
      Result:=Vuzol; Exit;
    end;
    Vuzol:=TSourceNode.Create;
    Vuzol.Kind:=N.Kind;
    Vuzol.Text:=N.Text;
    Vuzol.ByteOffset:=N.ByteOffset;
    Vuzol.Line:=N.Line;
    Vuzol.ByteColumn:=N.ByteColumn;
    Vuzol.EndByteExclusive:=N.EndByteExclusive;
    for K:=0 to High(N.Children) do
      Vuzol.Add(Walk(N.Children[K]));
    Result:=Copy;
  end;

begin
  SetLength(Names, Length(Expr.Children[1].Children));
  for I:=0 to High(Names) do
    Names[I]:=AtomText(Expr.Children[1].Children[I]);

  if Length(Expr.Children)=3 then
    Result:=Walk(Expr.Children[2]); Exit;   { одне тіло }

  { Кілька тіл: повертаємо список тіл, щоб Eval обійшов їх
    як послідовність, а не як один вираз. }
  Result:=TSourceNode.Create;
  Result.Kind:=skList;
  for I:=2 to High(Expr.Children) do
    Result.Add(Walk(Expr.Children[I]));
end;

end.
