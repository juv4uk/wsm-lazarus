{ Core1.4 — фізичний маршрут D7-індекс -> наявне перше замикання.
  Ні власного evaluator, ні реєстру законів, ні текстового dispatch.
  Канонічна SENS семантика належить pinned external/sens Contract12.
  Ключ маршруту — повна точна D7 послідовність із поточного T5M. }
unit wsm.core1dispatch;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.core1index, wsm.core1first, wsm.physloc;
type
  ECore1DispatchError=class(Exception);
  { Host-діагностика, не нова мовна тотожність: вказує фізичну D7-голову. }
  ECore1HeadError=class(ECore1DispatchError)
  public
    Span:TPhysicalNodeSpan;
    constructor CreateAt(const Why:String; const At:TPhysicalNodeSpan);
  end;

  TCore1Dispatch=class
  private
    FIndex:TCore1Index;           { власний індекс усіх pinned DEFINE }
    FFirst:TCore1FirstRuntime;   { власне вже перевірене перше замикання }
  public
    constructor Create(const WorkspaceRoot:String);
    destructor Destroy; override;
    function Count:SizeInt;
    function ExecutePhysical(const Physical:RawByteString):RawByteString;
  end;

implementation
uses wsm.t5m, wsm.d2source;

{ Span — copied host координати фізичного D2-вузла; не посилання
  на дерево, яке буде звільнено. Word 1-based, trit/byte 0-based.
  Відповідь є винятком з точним діапазоном; SENS закон не змінено.
  Питання: кому належить Span? Чому byte span може охопити сусіднє
  слово? Чому діагностика не визначає викличність? }
constructor ECore1HeadError.CreateAt(const Why:String;
  const At:TPhysicalNodeSpan);
begin
  inherited Create(Why+
    ' word=['+IntToStr(At.WordStart)+','+IntToStr(At.WordEndExclusive)+')'+
    ' trit=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+')'+
    ' byte=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')');
  Span:=At;
end;

procedure Need(Ok:Boolean; const Why:UnicodeString);
begin
  if not Ok then
    raise ECore1DispatchError.Create(RawByteString(UTF8Encode(Why)));
end;

{ Вхід N: запозичена голова фізичного D2-виклику із Doc.
  Результат: власний масив точних бітів D7, ніколи UTF-8 ім'я.
  Життя: Doc лишається живим до звільнення у ExecutePhysical.
  Питання: чому ширина W7 не дорівнює числу D7?
  Чому без склеювання бітів можливе хибне prefix match?
  Хто звільняє фізичний Doc? }
function PhysicalD7Head(N:TD2Node):TExactWords;
var I:SizeInt;
begin
  Need((N<>nil) and (N.Kind=dkList) and
       (Length(N.Children)>0) and (Length(N.Children)<=256),
       'голова виклику має бути непорожнім фізичним D7-списком');
  SetLength(Result,Length(N.Children)+2);
  Result[0]:='10';
  for I:=0 to High(N.Children) do begin
    Need((N.Children[I]<>nil) and
       (N.Children[I].Kind=dkIdentity) and
       (N.Children[I].Width=7) and
       (Length(N.Children[I].Bits)=7),
       'невірне точне слово фізичного D7-ідентифікатора');
    Result[I+1]:=N.Children[I].Bits;
  end;
  Result[High(Result)]:='01';
end;

{ Власність: два чинних компоненти живуть один раз протягом
  багатьох ExecutePhysical, не запозичують TD2Node з інших викликів.
  Кожен конструктор має exception-safe cleanup; крім SENS pin
  жодних додаткових таблиць ключів.
  Питання: що лишається живим після помилкового виклику?
  Чому index і runtime порівнюють саме копію точних D7-бітів?
  Чому другий закон не додається у маршрутизатор? }
constructor TCore1Dispatch.Create(const WorkspaceRoot:String);
var Upstream:String;
begin
  inherited Create;
  FIndex:=nil; FFirst:=nil;
  try
    Need(WorkspaceRoot<>'','потрібний корінь pinned робочого дерева');
    FIndex:=TCore1Index.Create(WorkspaceRoot);
    Upstream:=IncludeTrailingPathDelimiter(ExpandFileName(WorkspaceRoot))+
      'external'+PathDelim+'sens';
    FFirst:=TCore1FirstRuntime.Create(Upstream,WorkspaceRoot);
    Need(FIndex.Count>=1,'індекс pinned Core1 порожній');
    Need(FIndex.Definition(1).NameBits=FFirst.FirstIdentifier,
      'розбіжність фізичного D7-ключа першого замикання і Core1 індексу');
  except
    FreeAndNil(FFirst);
    FreeAndNil(FIndex);
    raise;
  end;
end;

destructor TCore1Dispatch.Destroy;
begin
  FFirst.Free;
  FIndex.Free;
  inherited Destroy;
end;

function TCore1Dispatch.Count:SizeInt;
begin
  Result:=FIndex.Count;
end;

{ Physical: borrowed canonical packed T5M, жодного UTF-8 читання.
  Doc: owned тільки під час маршрутизації; FIndex/FFirst owned довше.
  Результат: нові canonical packed T5M байти, отримані ВИКЛЮЧНО
  через TCore1FirstRuntime.ExecutePhysicalCall.
  Точний D7-голова знаходиться у всіх 96 DEFINE, але зараз
  callable admission має тільки ПЕРШЕ завантажене визначення:
  інші — явний BLOCKED, НЕ виконання і не NIL як false.
  На помилках відповідь відсутня, стан first runtime зберігається.
  Питання: чому index/find не дорівнює дозволу виклику?
  Чому незнайома D7 не переадресовується на першу функцію?
  Чому повний T5M парситься ДО будь-якого виконання?
  Чому не можна підміняти D1:0 структурним D3:000? }
function TCore1Dispatch.ExecutePhysical(
  const Physical:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Call:TD2Node;
  Head:TExactWords;
  Spans:TPhysicalWordSpans;
  HeadAt:TPhysicalNodeSpan;
  Definition:RawByteString;
begin
  Result:='';
  Doc:=nil;
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
    'порожній або надмірний фізичний виклик Core1');
  { Той самий T5M/D2 reader з перевіреною фізичною геометрією.
    Він перевіряє канонічність до передачі дерева та адрес. }
  Doc:=ReadD2WideWithPhysicalLocations(Physical,Spans);
  try
    Need(Length(Doc.Roots)=1,'потрібна рівно одна фізична D2-форма');
    Call:=Doc.Roots[0];
    Need((Call<>nil) and (Call.Kind=dkList) and
         (Length(Call.Children)=2),
         'очікується фізичний виклик з одним аргументом');
    HeadAt:=LocatePhysicalNodeSpan(Physical,Spans,Call.Children[0]);
    try
      Head:=PhysicalD7Head(Call.Children[0]);
      { Пошук рівно ОДНОГО DEFINE з pinned index, без host-імен. }
      Definition:=FIndex.FindPhysicalDefinition(EncodeT5M(Head));
      Need(Definition=FIndex.PhysicalDefinition(1),
        'відоме визначення Core1 поки не підтримано виконавцем');
    except
      { Суворо після D2 та фізичного допуску. Жоден error/blocked
        не може потрапити до виконавця чи змінити його стан. }
      on E:Exception do raise ECore1HeadError.CreateAt(E.Message,HeadAt);
    end;
  finally
    Doc.Free;
  end;
  { Делегуємо закон та виконання вже злитому механізму.
    Клієнт не має змоги непомітно виконати інше DEFINE. }
  Result:=FFirst.ExecutePhysicalCall(Physical);
end;

end.
