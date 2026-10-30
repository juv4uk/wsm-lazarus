{ G3.2/G3.8: обмежений механізм виконання шести D3-операцій.
  Закони й проєкції належать pinned SENS Contract 12, не Pascal.
  Немає Core4, SID-сумісності, чисел або канонічного T5M reader. }
unit wsm.nativeeval;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.source, wsm.domain, wsm.bind, wsm.bindindex;
type
  ENativeEvalError=class(ESourceError);
  { Фізичні теги контейнера, а не другий реєстр мовних функцій. }
  { ncClosure — фізичний тег контейнера, як ncPair, а не мовна функція.
    Використовує наявні поля: First — список параметрів, Rest — тіло.
    Нового поля немає навмисно: розмір TNativeCell не змінюється, і всі
    наявні місця лишаються чинними.
    Навіщо: knowledge/core1-poverhnia.md показує 96 із 96 визначень
    core1.lisp, які без закриття не виконуються. }
  TNativeCellKind=(ncEmpty,ncDomain,ncPair,ncClosure,ncName);
  TNativeCell=record
    Kind:TNativeCellKind;
    Key:TDomainKey;
    First,Rest:SizeInt;
  end;
  { Довірені ключі лише після чинного pinned фізичного BindD2Binary.
    Вузли належать тимчасовому TSourceNode-дереву одного виклику. }
  TNativeKeyedAtom=record
    Node:TSourceNode;
    Key:TDomainKey;
  end;
  TNativeKeyedAtoms=array of TNativeKeyedAtom;
  { Borrowed adapter marks only physical D2 dotted-pair containers.
    Type: one borrowed TSourceNode pointer; PairNodes is its dynamic array.
    Parameters: filled by the binary adapter, then copied for one evaluator
    call. Physical form: the pointed node is skList with exactly two children;
    no spelling or domain key is minted. Allocation/lifetime: nodes belong to
    the caller's temporary AST, marker-array copy belongs to this call.
    Result: QuoteExact maps the marker to one native ncPair cell.
    Питання: хто володіє вузлом? Чому це не ключ? Де перевіряється арність? }
  TNativePairNode=record
    Node:TSourceNode;
  end;
  TNativePairNodes=array of TNativePairNode;
  TNativeEvaluator=class
  private
    FDomains:TDomainSet;
    FIndex:TBindIndex;
    FCells:array of TNativeCell;
    { Таблиця імен — ОКРЕМО від клітинок.
      Причина: TNativeCell не має поля для тексту, а ім'я параметра
      (доведено core1.lisp:93 — ядро1-назви-рівні? порівнює структурно)
      не є доменним ключем. Розширювати TNativeCell означало б змінити
      розмір запису й зачепити всі наявні місця. Окремий масив цього
      не робить — той самий принцип, що й ncClosure на наявних полях. }
    FNames:array of RawByteString;
    FUsed,FMaxCells,FMaxSteps,FSteps,FMaxDepth:SizeInt;
    FKeyedMode,FPhysicalOutput:Boolean;
    FKeyedAtoms:TNativeKeyedAtoms;
    FPairNodes:TNativePairNodes;
    { Механічна індексація Borrowed Node -> pinned exact key.
      In-place heapsort без додаткового key-registry, O(N log N). }
    procedure SortKeyedAtoms;
    procedure SortPairNodes;
    function IsPhysicalPairNode(N:TSourceNode):Boolean;
    function KeyForNode(N:TSourceNode; const ErrorText:String):TDomainKey;
    procedure Reset;
    procedure Fail(N:TSourceNode; const MessageText:String);
    procedure Step(N:TSourceNode; Depth:SizeInt);
    function Append(const Cell:TNativeCell; N:TSourceNode):SizeInt;
    function DomainCell(const Key:TDomainKey; N:TSourceNode):SizeInt;
    function PairCell(A,B:SizeInt; N:TSourceNode):SizeInt;
    { Закриття: параметри й тіло як індекси на наявні ланцюги.
      Нічого не обчислює і не викликає — лише пакує. }
    function NameCell(const Name:RawByteString; N:TSourceNode):SizeInt;
    function StructuralCells(N:TSourceNode; Depth:SizeInt):SizeInt;
    function ClosureCell(Params,Body:SizeInt; N:TSourceNode):SizeInt;
    function Assoc(const Name:RawByteString; Env:SizeInt; N:TSourceNode):SizeInt;
    function Pairlis(Params,Args,Env:SizeInt; N:TSourceNode):SizeInt;
    function Evlis(N:TSourceNode; Depth,Env:SizeInt):SizeInt;
    function Appq(Args:SizeInt; N:TSourceNode):SizeInt;
    function Quote(N:TSourceNode; Depth:SizeInt):SizeInt;
    function QuoteExact(N:TSourceNode; Depth:SizeInt):SizeInt;
    { Env — індекс клітинки-оточення (аліста на ncPair), 0 = порожнє.
      Перехідний крок: 2-арна форма лишається чинною й делегує сюди з
      Env=0, щоб жоден наявний виклик не змінив поведінки.
      Коли Env почне читатись, 2-арна форма стане «без оточення». }
    function Eval(N:TSourceNode; Depth:SizeInt):SizeInt; overload;
    function Eval(N:TSourceNode; Depth:SizeInt; Env:SizeInt):SizeInt; overload;
    function Render(H:SizeInt; Depth:SizeInt):RawByteString;
    function RenderPhysical(H:SizeInt; Depth:SizeInt):RawByteString;
  public
    constructor Create(const Root:RawByteString; Cells:SizeInt=4096;
      Steps:SizeInt=16384; Depth:SizeInt=128);
    function EvaluateNode(N:TSourceNode):RawByteString;
    { Виконати ТОЙ САМИЙ D3 механізм, але без українського bind/projection.
      Кожен atom N має вже перевірений exact-key; невідомий вузол — ERROR.
      Власник KeyedAtoms/N зберігає їх протягом цього синхронного виклику. }
    function EvaluateKeyedNode(N:TSourceNode;
      const KeyedAtoms:TNativeKeyedAtoms):RawByteString; overload;
    function EvaluateKeyedNode(N:TSourceNode;
      const KeyedAtoms:TNativeKeyedAtoms;
      { Borrowed pair markers preserve only the physical D2 constructor;
        they are not keys and live for this synchronous evaluation. }
      const PairNodes:TNativePairNodes):RawByteString; overload;
    { Повернути фізичні канонічні T5M-байти вже обчисленого значення.
      Ніякої реверсії через текст Render і жодного нового закону SENS. }
    function EvaluateKeyedNodePhysical(N:TSourceNode;
      const KeyedAtoms:TNativeKeyedAtoms):RawByteString; overload;
    function EvaluateKeyedNodePhysical(N:TSourceNode;
      const KeyedAtoms:TNativeKeyedAtoms;
      const PairNodes:TNativePairNodes):RawByteString; overload;
    function EvaluateSource(const Source:RawByteString):RawByteString;
  end;
implementation
uses wsm.t5m, wsm.d2source;
constructor TNativeEvaluator.Create(const Root:RawByteString;
  Cells:SizeInt; Steps:SizeInt; Depth:SizeInt);
begin
  inherited Create;
  if (Cells<1) or (Cells>65536) or (Steps<1) or (Steps>1048576) or
     (Depth<1) or (Depth>128) then
    raise ENativeEvalError.CreateAt('invalid native resource limits',1,1,1);
  FMaxCells:=Cells; FMaxSteps:=Steps; FMaxDepth:=Depth;
  FPhysicalOutput:=False;
  LoadPinnedDomains(Root,FDomains);
  BuildBindIndex(FDomains,FIndex);
  Reset;
end;
procedure TNativeEvaluator.SortKeyedAtoms;
var I, Last:SizeInt; Tmp:TNativeKeyedAtom;
  procedure SiftDown(StartPos, LastPos:SizeInt);
  var Root, Child:SizeInt; SwapItem:TNativeKeyedAtom;
  begin
    Root:=StartPos;
    while Root*2+1<=LastPos do begin
      Child:=Root*2+1;
      if (Child<LastPos) and
         (PtrUInt(FKeyedAtoms[Child].Node)<
          PtrUInt(FKeyedAtoms[Child+1].Node)) then Inc(Child);
      if PtrUInt(FKeyedAtoms[Root].Node)>=
         PtrUInt(FKeyedAtoms[Child].Node) then Exit;
      SwapItem:=FKeyedAtoms[Root];
      FKeyedAtoms[Root]:=FKeyedAtoms[Child];
      FKeyedAtoms[Child]:=SwapItem;
      Root:=Child;
    end;
  end;
begin
  { Max N=65536. Місце O(1) понад власну копію масиву,
    порівняння тільки адрес вузлів, а НЕ текст/біти/назви SENS. }
  for I:=Length(FKeyedAtoms) div 2-1 downto 0 do
    SiftDown(I,High(FKeyedAtoms));
  for Last:=High(FKeyedAtoms) downto 1 do begin
    Tmp:=FKeyedAtoms[0];
    FKeyedAtoms[0]:=FKeyedAtoms[Last];
    FKeyedAtoms[Last]:=Tmp;
    SiftDown(0,Last-1);
  end;
end;

{ SortPairNodes: in-place heapsort borrowed marker pointers by address.
  Parameters: none; input/output FPairNodes. Physical representation is the
  same borrowed AST pointers, ordered by PtrUInt only for lookup. No node or
  array allocation occurs here; storage lasts through EvaluateKeyedNode.
  Result: deterministic O(n log n) index for IsPhysicalPairNode.
  Питання: чи змінює це порядок D2? Чому PtrUInt тут не є мовним значенням?
  Яка складність пошуку після сортування? }
procedure TNativeEvaluator.SortPairNodes;
var I,Last:SizeInt; Tmp:TNativePairNode;
  procedure SiftDown(StartPos,LastPos:SizeInt);
  var Root,Child:SizeInt; SwapItem:TNativePairNode;
  begin
    Root:=StartPos;
    while Root*2+1<=LastPos do begin
      Child:=Root*2+1;
      if (Child<LastPos) and
         (PtrUInt(FPairNodes[Child].Node)<
          PtrUInt(FPairNodes[Child+1].Node)) then Inc(Child);
      if PtrUInt(FPairNodes[Root].Node)>=
         PtrUInt(FPairNodes[Child].Node) then Exit;
      SwapItem:=FPairNodes[Root];
      FPairNodes[Root]:=FPairNodes[Child];
      FPairNodes[Child]:=SwapItem;
      Root:=Child;
    end;
  end;
begin
  for I:=Length(FPairNodes) div 2-1 downto 0 do
    SiftDown(I,High(FPairNodes));
  for Last:=High(FPairNodes) downto 1 do begin
    Tmp:=FPairNodes[0];
    FPairNodes[0]:=FPairNodes[Last];
    FPairNodes[Last]:=Tmp;
    SiftDown(0,Last-1);
  end;
end;

{ Exact pointer membership only: N is the borrowed lookup parameter, result
  is a host Boolean, and the physical D2 bits remain in the source document.
  Binary search reads the temporary sorted array; it allocates nothing and is
  valid only while FKeyedMode keeps that call's borrowed lifetime active.
  Питання: чи може однаковий текст замінити адресу? Коли режим вимикається?
  Чому маркер не надає вузлу callable-домен? }
function TNativeEvaluator.IsPhysicalPairNode(N:TSourceNode):Boolean;
var L,R,M:SizeInt; AtPtr,MidPtr:PtrUInt;
begin
  if not FKeyedMode or (N=nil) then Exit(False);
  AtPtr:=PtrUInt(N); L:=0; R:=High(FPairNodes);
  while L<=R do begin
    M:=L+(R-L) div 2;
    MidPtr:=PtrUInt(FPairNodes[M].Node);
    if MidPtr=AtPtr then Exit(True);
    if MidPtr<AtPtr then L:=M+1 else R:=M-1;
  end;
  Result:=False;
end;

function TNativeEvaluator.KeyForNode(N:TSourceNode;
  const ErrorText:String):TDomainKey;
var L,R,M:SizeInt; AtPtr, MidPtr:PtrUInt;
begin
  if FKeyedMode then begin
    { Пошук O(log N); жодного fallback до написання ук.
      Exact key надходить лише з pinned binary binder викликача. }
    if N=nil then
      raise ENativeEvalError.CreateAt(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB,1,1,1);
    AtPtr:=PtrUInt(N);
    L:=0; R:=High(FKeyedAtoms);
    while L<=R do begin
      M:=L+(R-L) div 2;
      MidPtr:=PtrUInt(FKeyedAtoms[M].Node);
      if MidPtr=AtPtr then Exit(FKeyedAtoms[M].Key);
      if MidPtr<AtPtr then L:=M+1 else R:=M-1;
    end;
    Fail(N,#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D0#$BA#$D0#$BE#$D0#$BE#$D1#$80#$D0#$B4#$D0#$B8#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B0);
  end;
  try Result:=IndexedUkrainian(FIndex,N.Text);
  except on E:EBindError do Fail(N,ErrorText); end;
end;

procedure TNativeEvaluator.Reset;
begin
  SetLength(FCells,0); SetLength(FCells,1);
  SetLength(FNames,0);
  FCells[0].Kind:=ncEmpty;
  FCells[0].Key:=ExactKey('000'); { D3:000, не D1:0. }
  FUsed:=1; FSteps:=0;
end;
procedure TNativeEvaluator.Fail(N:TSourceNode; const MessageText:String);
begin
  raise ENativeEvalError.CreateAt(MessageText,N.ByteOffset,N.Line,N.ByteColumn);
end;
procedure TNativeEvaluator.Step(N:TSourceNode; Depth:SizeInt);
begin
  if Depth>FMaxDepth then Fail(N,'native depth limit');
  if FSteps>=FMaxSteps then Fail(N,'native step limit');
  Inc(FSteps);
end;
function TNativeEvaluator.Append(const Cell:TNativeCell; N:TSourceNode):SizeInt;
var Capacity:SizeInt;
begin
  if FUsed>=FMaxCells then Fail(N,'native cell limit');
  if FUsed=Length(FCells) then begin
    Capacity:=Length(FCells)*2;
    if Capacity>FMaxCells then Capacity:=FMaxCells;
    SetLength(FCells,Capacity);
  end;
  Result:=FUsed; FCells[Result]:=Cell; Inc(FUsed);
end;
function TNativeEvaluator.DomainCell(const Key:TDomainKey; N:TSourceNode):SizeInt;
var C:TNativeCell;
begin
  C:=Default(TNativeCell); C.Kind:=ncDomain; C.Key:=Key;
  Result:=Append(C,N);
end;
function TNativeEvaluator.PairCell(A,B:SizeInt; N:TSourceNode):SizeInt;
var C:TNativeCell;
begin
  C:=Default(TNativeCell); C.Kind:=ncPair; C.First:=A; C.Rest:=B;
  Result:=Append(C,N);
end;
{ Структурна копія вузла в клітинки: жодного пошуку доменних ключів.
  Потрібна саме тому, що імена параметрів і тіло функції — це НЕ доменні
  слова, і Quote на них законно відмовив би. Це не eval: вузол просто
  стає ланцюгом ncPair, як дані. }
function TNativeEvaluator.StructuralCells(N:TSourceNode; Depth:SizeInt):SizeInt;
var I:SizeInt; Head:SizeInt;
begin
  Step(N,Depth);
  if N.Kind=skAtom then
    { Ім'я йде в FNames, а клітинка тримає лише індекс. Розмір
      TNativeCell не змінений. }
    Exit(NameCell(N.Text,N));
  if N.Kind<>skList then Fail(N,'structural copy: unsupported node kind');
  Result:=0;
  for I:=Length(N.Children)-1 downto 0 do
    Result:=PairCell(StructuralCells(N.Children[I],Depth+1),Result,N);
end;

{ Ім'я як клітинка: Key порожній, First — індекс у FNames.
  Порівняння імен — порівняння рядків, як ядро1-назви-рівні?. }
function TNativeEvaluator.NameCell(const Name:RawByteString; N:TSourceNode):SizeInt;
var C:TNativeCell; I:SizeInt;
begin
  { Повтор імені не дублюємо: однакове ім'я — одна клітинка-індекс. }
  for I:=0 to High(FNames) do
    if FNames[I]=Name then begin
      C:=Default(TNativeCell); C.Kind:=ncName; C.First:=I;
      Exit(Append(C,N));
    end;
  I:=Length(FNames); SetLength(FNames,I+1); FNames[I]:=Name;
  C:=Default(TNativeCell); C.Kind:=ncName; C.First:=I;
  Result:=Append(C,N);
end;

function TNativeEvaluator.ClosureCell(Params,Body:SizeInt; N:TSourceNode):SizeInt;
var C:TNativeCell;
begin
  { Key лишається порожнім: закриття не має доменної адреси, і видавати
    йому ключ означало б вигадати новий домен. }
  C:=Default(TNativeCell); C.Kind:=ncClosure; C.First:=Params; C.Rest:=Body;
  Result:=Append(C,N);
end;
{ assoc: знайти ім'я в алісті-оточенні.
  Взято з core1.lisp:89 (ядро1-знайти-в-оточенні):
    атом замість оточення -> порожнє
    ім'я першої пари рівне  -> знайдене (решта пари)
    інакше                  -> шукати в решті оточення
  Порівняння імен — структурне (FNames), як ядро1-назви-рівні?.
  Повертає індекс клітинки-значення; 0 = не знайдено (ncEmpty). }
function TNativeEvaluator.Assoc(const Name:RawByteString; Env:SizeInt; N:TSourceNode):SizeInt;
var E,Pair,Cell:SizeInt;
begin
  E:=Env;
  while E<>0 do begin
    if FCells[E].Kind<>ncPair then Break;      { атом замість оточення }
    Pair:=FCells[E].First;
    if (Pair<>0) and (FCells[Pair].Kind=ncPair) then begin
      Cell:=FCells[Pair].First;
      if (Cell<>0) and (FCells[Cell].Kind=ncName)
         and (FNames[FCells[Cell].First]=Name) then
        Exit(FCells[Pair].Rest);
    end;
    E:=FCells[E].Rest;
  end;
  Result:=0;
end;

{ pairlis: зв'язати параметри з аргументами в алісту.
  Логіка взята з external/sens/lib/core1.lisp:193 (ядро1-поєднати-параметри):
    порожні параметри + порожні аргументи -> оточення
    порожні параметри, але є аргументи   -> ARITY TOO-MANY-ARGUMENTS
    є параметри, але немає аргументів    -> ARITY TOO-FEW-ARGUMENTS
    інакше -> cons(cons(param, arg), pairlis(rest, rest, env))
  Дві РІЗНІ помилки арності навмисно: це не одна перевірка, а два різні
  випадки в джерелі, і зливати їх означало б втратити діагностику. }
function TNativeEvaluator.Pairlis(Params,Args,Env:SizeInt; N:TSourceNode):SizeInt;
var P,A:SizeInt;
begin
  P:=Params; A:=Args;
  while (P<>0) and (A<>0) do begin
    Env:=PairCell(PairCell(FCells[P].First,FCells[A].First,N),Env,N);
    P:=FCells[P].Rest; A:=FCells[A].Rest;
  end;
  if (P=0) and (A<>0) then Fail(N,'ARITY: TOO-MANY-ARGUMENTS');
  if (P<>0) and (A=0) then Fail(N,'ARITY: TOO-FEW-ARGUMENTS');
  Result:=Env;
end;

{ evlis: обчислити кожен аргумент форми в оточенні Env і зібрати в ланцюг.
  Порядок збережений: обчислюємо зліва направо, ланцюг будуємо ззаду. }
function TNativeEvaluator.Evlis(N:TSourceNode; Depth,Env:SizeInt):SizeInt;
var I:SizeInt;
begin
  if N.Kind<>skList then Fail(N,'evlis потребує список');
  Result:=0;
  for I:=Length(N.Children)-1 downto 0 do
    Result:=PairCell(Eval(N.Children[I],Depth+1,Env),Result,N);
end;

{ appq: загорнути кожен уже обчислений аргумент у (як-є аргумент).
  БЕЗ цього значення обчислиться вдруге як код — причина названа в
  mccarthy-kernel.s:1626, і Core1 спіткнувся на ньому реальним segfault.
  як-є — це D3:001 (lib/domains/d3.lisp:15). }
function TNativeEvaluator.Appq(Args:SizeInt; N:TSourceNode):SizeInt;
var I:SizeInt; C:TNativeCell; Chain:SizeInt;
begin
  Result:=0;
  I:=Args;
  { Спершу збираємо в зворотному порядку, потім розвертаємо — інакше
    аргументи прийдуть дзеркально. }
  while I<>0 do begin
    C:=Default(TNativeCell); C.Kind:=ncDomain; C.Key:=ExactKey('001');
    Result:=PairCell(PairCell(Append(C,N),FCells[I].First,N),Result,N);
    I:=FCells[I].Rest;
  end;
  Chain:=0;
  while Result<>0 do begin
    Chain:=PairCell(FCells[Result].First,Chain,N);
    Result:=FCells[Result].Rest;
  end;
  Result:=Chain;
end;

function TNativeEvaluator.Quote(N:TSourceNode; Depth:SizeInt):SizeInt;
var I,J,Width,Count,Item:SizeInt; Ch:RawByteString;
    Letters:array of SizeInt; Key:TDomainKey;
begin
  Step(N,Depth);
  Result:=0;
  if N.Kind=skList then begin
    for I:=High(N.Children) downto 0 do begin
      Item:=Quote(N.Children[I],Depth+1);
      Result:=PairCell(Item,Result,N);
    end;
    Exit;
  end;
  if N.Kind<>skAtom then Fail(N,'unsupported native quoted string');
  if (N.Text='.') or (N.Text='') or (N.Text[1]='''') then
    Fail(N,'unsupported native reader syntax');
  { Quote-текст є D7-даними. Жодного Pascal symbol interning.
    Підтриманий тут вузький вхід — незакодовані літери таблиці D7.
    Числові літерали/escape/surface у лапках не вгадуємо. }
  I:=1; Count:=0; SetLength(Letters,0);
  while I<=Length(N.Text) do begin
    Step(N,Depth);
    if Ord(N.Text[I])<$80 then Width:=1
    else if Ord(N.Text[I])<$E0 then Width:=2
    else if Ord(N.Text[I])<$F0 then Width:=3 else Width:=4;
    Ch:=Copy(N.Text,I,Width);
    try Key:=IndexedUkrainianInDomain(FIndex,Ch,7);
    except on X:EBindError do Fail(N,'unsupported native D7 projection'); end;
    { Пунктуаційні/числові surface у таблиці мають лапки, тому цей
      прямий lookup не приймає їх як текстові літери. }
    SetLength(Letters,Count+1);
    Letters[Count]:=DomainCell(Key,N); Inc(Count); Inc(I,Width);
  end;
  for J:=Count-1 downto 0 do Result:=PairCell(Letters[J],Result,N);
end;
{ Цитування в уже зв'язаному фізичному режимі: вузли-позначення є
  точними pinned ключами. Жодного перетворення у літери D7.
  Час життя borrowed N — лише синхронний ExecutePhysical. }
{ QuoteExact consumes a borrowed node and recursion depth; it returns an index
  into this evaluator's native cell arena. Marked physical pair nodes become
  ncPair(head,tail), preserving D2's two-field structure; ordinary lists keep
  their existing path. The arena is allocated/reset by evaluator lifetime,
  while N is owned by the synchronous caller. No text projection is involved.
  Питання: чому спершу цитуються обидва поля? Де живе результат? Чому звичайний
  список не отримує ознаку пари? }
function TNativeEvaluator.QuoteExact(N:TSourceNode; Depth:SizeInt):SizeInt;
var I, Item, Head, Tail:SizeInt; Key:TDomainKey;
begin
  Step(N,Depth);
  if N.Kind=skList then begin
    if IsPhysicalPairNode(N) then begin
      if Length(N.Children)<>2 then
        Fail(N,'фізична D2 пара повинна мати голову і хвіст');
      Head:=QuoteExact(N.Children[0],Depth+1);
      Tail:=QuoteExact(N.Children[1],Depth+1);
      Exit(PairCell(Head,Tail,N));
    end;
    Result:=0; { D3:000, порожня структура, не D1:0 }
    for I:=High(N.Children) downto 0 do begin
      Item:=QuoteExact(N.Children[I],Depth+1);
      Result:=PairCell(Item,Result,N);
    end;
    Exit;
  end;
  if N.Kind<>skAtom then Fail(N,'фізична D3:001 цитата потребує атом або список');
  Key:=KeyForNode(N,'немає pinned координати цитованого слова');
  if (Key.Width<1) or (Key.Width>10) or (Key.Width=2) then
    Fail(N,'непідтримана ширина фізичної цитати');
  Result:=DomainCell(Key,N); { ті самі width + bits, ніякого eval }
end;

function TNativeEvaluator.Eval(N:TSourceNode; Depth:SizeInt):SizeInt;
begin
  { Без оточення — той самий шлях, що й досі. Жодної нової семантики. }
  Result:=Eval(N,Depth,0);
end;

function TNativeEvaluator.Eval(N:TSourceNode; Depth:SizeInt; Env:SizeInt):SizeInt;
var Key:TDomainKey; A,B,ArgCount,I:SizeInt; Clause:TSourceNode;
begin
  Step(N,Depth);
  if N.Kind=skAtom then begin
    Key:=KeyForNode(N,'unknown native binding');
    if Key.Width<>1 then Fail(N,'unsupported native value domain');
    Exit(DomainCell(Key,N));
  end;
  if N.Kind<>skList then Fail(N,'unsupported native string value');
  if IsPhysicalPairNode(N) then
    Fail(N,'фізична D2 крапкова пара є значенням, не формою виклику');
  if Length(N.Children)=0 then Exit(0);
  if N.Children[0].Kind<>skAtom then Fail(N.Children[0],
    'unsupported computed native head');
  Key:=KeyForNode(N.Children[0],'unknown native call head');
  { Поверхня вже стала точним ключем; подальший dispatch лише D3+біти.
    Членство у таблиці НЕ дозволяє довільний виклик. Решта BLOCKED. }
  if not (Key.Width in [3,10]) then
    Fail(N.Children[0],'unsupported native callable domain');
  { D10: замикання. Адреси з pinned lib/domains/d10.lisp:
      0100111100 створити-лямбда-замикання
      0101100010 зв'язати-параметри
      0101100001 є-параметр-залишку?
    Диспетч за бітами, не за назвами. Поки реалізовано ЛИШЕ створення
    замикання: воно нічого не обчислює й не викликає, тому небезпечне
    рівно настільки, наскільки безпечне пакування. Дві інші адреси
    свідомо відмовляють, а не прикидаються виконаними. }
  if Key.Width=10 then begin
    if Key.Bits=%0100111100 then begin
      if Length(N.Children)<>3 then
        Fail(N,'closure needs parameters and body');
      Exit(ClosureCell(StructuralCells(N.Children[1],Depth+1),
                       StructuralCells(N.Children[2],Depth+1),N));
    end;
    if Key.Bits=%0101100010 then
      Fail(N.Children[0],'bind-params: not implemented yet (#490)');
    if Key.Bits=%0101100001 then
      Fail(N.Children[0],'rest-param?: not implemented yet (#490)');
    Fail(N.Children[0],'unsupported D10 callable');
  end;
  { Contract 12 K12.3: D3:110 — послідовність рівно двопольових
    гілок (предикат вираз). Лінивість: не обчислювати expression,
    доки точний результат test НЕ D1:1. D1:0 переходить далі.
    Після вичерпання повернути структурний D3:000, не D1 false.
    Порядок, типи і ключ надходять лише від pinned binder. }
  if Key.Bits=%110 then begin
    for I:=1 to High(N.Children) do begin
      Clause:=N.Children[I];
      Step(Clause,Depth+1);
      if Clause.Kind<>skList then
        Fail(Clause,'D3:110 очікує гілку-список');
      if Length(Clause.Children)<>2 then
        Fail(Clause,'D3:110 очікує рівно два поля гілки');
      A:=Eval(Clause.Children[0],Depth+2);
      if (FCells[A].Kind<>ncDomain) or (FCells[A].Key.Width<>1) then
        Fail(Clause.Children[0],'D3:110 перевірка потребує D1:0 або D1:1');
      { Порівнювати точне слово, не host truthiness і не Pascal bool.
        Будь-яке невизначене представлення відхиляється. }
      case FCells[A].Key.Bits of
        0: ; { Залишаємося на наступній гілці; expression НЕ виконуємо. }
        1: Exit(Eval(Clause.Children[1],Depth+2));
      else
        Fail(Clause.Children[0],'D3:110 невідомий біт предиката');
      end;
    end;
    Exit(0); { D3:000 (структурне ()), НЕ D1:0. }
  end;
  case Key.Bits of
    %001,%010,%011,%100: ArgCount:=1;
    %101,%111: ArgCount:=2;
    else begin Fail(N.Children[0],'native mechanism not implemented'); ArgCount:=0; end;
  end;
  if Length(N.Children)<>ArgCount+1 then begin
    if Key.Bits=%001 then Fail(N,'D3:001 цитата потребує рівно один аргумент');
    Fail(N,'native arity error');
  end;
  if Key.Bits=%001 then begin
    if FKeyedMode then
      Exit(QuoteExact(N.Children[1],Depth+1))
    else
      Exit(Quote(N.Children[1],Depth+1));
  end;
  A:=Eval(N.Children[1],Depth+1);
  case Key.Bits of
    %010: begin
      Key:=ExactKey('0');
      if FCells[A].Kind<>ncPair then Key:=ExactKey('1');
      Result:=DomainCell(Key,N);
    end;
    %011,%100: begin
      if FCells[A].Kind<>ncPair then Fail(N,'native selector requires nonempty pair');
      if Key.Bits=%100 then Result:=FCells[A].First
      else Result:=FCells[A].Rest;
    end;
    %101: begin
      { G3.29 / Contract 12 K12.3: рівність обчислених ДОПУЩЕНИХ
        атомів, зараз рівно D1 або цитований D7. Type/ncDomain та
        фізичний pinned exact key походять з попереднього binder;
        D7 SYN — дані, а не команда. D3:000, pair, bare D7 та
        D12+ не стають допустимими значеннями. Два handles A/B
        належать тимчасовій FCells арені до Reset, результат —
        нова ncDomain комірка з D1:0 або D1:1.
        Питання: хто встановлює домен і ширину? Чому D7 треба
        цитувати? Де відхиляється pair? Чому однакові біти з
        різних доменів НЕ рівні? Хто звільняє result-cell? }
      B:=Eval(N.Children[2],Depth+1);
      if (FCells[A].Kind<>ncDomain) or
         not (FCells[A].Key.Width in [1,7]) then
        Fail(N.Children[1],'D3:101 очікує допущений атом D1 або цитований D7 зліва');
      if (FCells[B].Kind<>ncDomain) or
         not (FCells[B].Key.Width in [1,7]) then
        Fail(N.Children[2],'D3:101 очікує допущений атом D1 або цитований D7 справа');
      { SameKey порівнює точні domain width + bits з pinned binder,
        не українську/англійську назву, числову величину чи адресу. }
      Key:=ExactKey('0');
      if SameKey(FCells[A].Key,FCells[B].Key) then
        Key:=ExactKey('1');
      Result:=DomainCell(Key,N);
    end;
    %111: begin
      B:=Eval(N.Children[2],Depth+1);
      Result:=PairCell(A,B,N);
    end;
    else begin Fail(N,'native mechanism not implemented'); Result:=0; end;
  end;
end;
{ Лінійна фізична побудова текстового ВІДОБРАЖЕННЯ native cells.
  Доменна ідентичність уже допущена pinned binder; writer працює тільки
  з exact KeyBits і структурою TNativeCell. Текст НЕ є машинним .sens.
  Один геометричний байтовий буфер — без O(N^2) копій плоских списків. }
function TNativeEvaluator.Render(H:SizeInt; Depth:SizeInt):RawByteString;
var Buffer:RawByteString; Used,Capacity:SizeInt;

  procedure Put(const Part:RawByteString);
  var Count,Required,NextCapacity:SizeInt;
  begin
    Count:=Length(Part);
    if Count=0 then Exit;
    if Used>High(SizeInt)-Count then
      raise ENativeEvalError.CreateAt('native output size overflow',1,1,1);
    Required:=Used+Count;
    if Required>Capacity then begin
      NextCapacity:=Capacity;
      if NextCapacity=0 then NextCapacity:=64;
      while NextCapacity<Required do begin
        if NextCapacity>High(SizeInt) div 2 then begin
          NextCapacity:=Required;
          Break;
        end;
        NextCapacity:=NextCapacity*2;
      end;
      SetLength(Buffer,NextCapacity);
      Capacity:=NextCapacity;
    end;
    Move(Part[1],Buffer[Used+1],Count);
    Used:=Required;
  end;

  procedure Emit(Cell:SizeInt; Nesting:SizeInt);
  var Tail:SizeInt; First:Boolean;
  begin
    if Nesting>256 then
      raise ENativeEvalError.CreateAt('native output depth limit',1,1,1);
    case FCells[Cell].Kind of
      ncEmpty: Put('()');
      ncDomain: Put(KeyBits(FCells[Cell].Key));
      ncPair: begin
        Put('(');
        Tail:=Cell;
        First:=True;
        while FCells[Tail].Kind=ncPair do begin
          if not First then Put(' ');
          Emit(FCells[Tail].First,Nesting+1);
          First:=False;
          Tail:=FCells[Tail].Rest;
        end;
        if FCells[Tail].Kind<>ncEmpty then begin
          Put(' . ');
          Emit(Tail,Nesting+1);
        end;
        Put(')');
      end;
    end;
  end;

begin
  Buffer:='';
  Used:=0;
  Capacity:=0;
  Emit(H,Depth);
  SetLength(Buffer,Used); { caller owns an exact-sized RawByteString }
  Result:=Buffer;
end;
{ Той самий результат (FCells[H]), але не текстова проєкція.
  D2 «10/01/11» тут лише фізичне обрамлення: proper list / dotted
  tail. Слова атомів беруться тільки з pinned exact TDomainKey.
  W12+ не допускає чинний physical binder — writer не наділяє
  жодне слово числовим або викличним законом. }
function TNativeEvaluator.RenderPhysical(H:SizeInt; Depth:SizeInt):RawByteString;
var Words:TExactWords; Used,Capacity:SizeInt;

  procedure Put(const Bits:RawByteString);
  var NextCapacity:SizeInt;
  begin
    if Used>=MaxD2Words then
      raise ENativeEvalError.CreateAt('physical native output D2 word limit',1,1,1);
    if Used=Capacity then begin
      if Capacity=0 then NextCapacity:=16
      else if Capacity>MaxD2Words div 2 then NextCapacity:=MaxD2Words
      else NextCapacity:=Capacity*2;
      SetLength(Words,NextCapacity);
      Capacity:=NextCapacity;
    end;
    Words[Used]:=Bits;
    Inc(Used);
  end;

  procedure Emit(Cell:SizeInt; Nesting:SizeInt);
  var Tail:SizeInt;
  begin
    if Nesting>256 then
      raise ENativeEvalError.CreateAt('physical native output depth limit',1,1,1);
    case FCells[Cell].Kind of
      ncEmpty: Put('000'); { D3:000, не D1:0 }
      ncDomain: Put(KeyBits(FCells[Cell].Key));
      ncPair: begin
        Put('10'); { фізичний D2 open }
        Tail:=Cell;
        while FCells[Tail].Kind=ncPair do begin
          Emit(FCells[Tail].First,Nesting+1);
          Tail:=FCells[Tail].Rest;
        end;
        if FCells[Tail].Kind<>ncEmpty then begin
          Put('11'); { dotted tail тільки для неправильної пари }
          Emit(Tail,Nesting+1);
        end;
        Put('01'); { фізичний D2 close }
      end;
    end;
  end;

begin
  Used:=0; Capacity:=0;
  SetLength(Words,0);
  Emit(H,Depth);
  SetLength(Words,Used);
  { Єдиний чинний T5M encoder забезпечує транспортну канонічність.
    Масив Words живе тільки в цьому виклику; результатом володіє caller. }
  Result:=EncodeT5M(Words);
end;

{ Вхід із уже перевіреного AST: не перетворюємо українську проєкцію
  на повторний текст і не створюємо нового мовного dispatch. }
function TNativeEvaluator.EvaluateNode(N:TSourceNode):RawByteString;
var H:SizeInt;
begin
  if N=nil then
    raise ENativeEvalError.CreateAt(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$8F#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0#$20#$D0#$B4#$D0#$BB#$D1#$8F#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F,1,1,1);
  Reset;
  try
    H:=Eval(N,0);
    if FPhysicalOutput then Result:=RenderPhysical(H,0)
    else Result:=Render(H,0);
  finally
    Reset;
  end;
end;
{ Keyed physical entry point accepts the caller's AST, exact atom-key array,
  and optional physical-pair marker array. The key/marker arrays are copied,
  validated, sorted and released within this synchronous call; the AST remains
  borrowed. Result is the evaluator's exact physical output bytes. Existing
  overload without markers retains its old behavior.
  Питання: хто зв'язав ключі? Чому маркер не є таблицею законів? Який час життя
  мають копії? Яка форма відповіді повертається? }
function TNativeEvaluator.EvaluateKeyedNode(N:TSourceNode;
  const KeyedAtoms:TNativeKeyedAtoms):RawByteString;
begin
  Result:=EvaluateKeyedNode(N,KeyedAtoms,TNativePairNodes(nil));
end;

function TNativeEvaluator.EvaluateKeyedNode(N:TSourceNode;
  const KeyedAtoms:TNativeKeyedAtoms;
  const PairNodes:TNativePairNodes):RawByteString;
var I:SizeInt; Bits:RawByteString;
begin
  if FKeyedMode then
    raise ENativeEvalError.CreateAt(#$D0#$B2#$D0#$BA#$D0#$BB#$D0#$B0#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$65#$78#$61#$63#$74#$20#$D1#$80#$D0#$B5#$D0#$B6#$D0#$B8#$D0#$BC#$20#$D0#$B7#$D0#$B0#$D0#$B1#$D0#$BE#$D1#$80#$D0#$BE#$D0#$BD#$D0#$B5#$D0#$BD#$D0#$BE,1,1,1);
  if N=nil then
    raise ENativeEvalError.CreateAt(#$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B8,1,1,1);
  if Length(KeyedAtoms)>65536 then
    raise ENativeEvalError.CreateAt(#$D0#$BD#$D0#$B0#$D0#$B4#$D1#$82#$D0#$BE#$20#$D0#$B1#$D0#$B0#$D0#$B3#$D0#$B0#$D1#$82#$D0#$BE#$20#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D0#$B0#$D0#$BD#$D0#$B8#$D1#$85#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D1#$85#$20#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC#$D1#$96#$D0#$B2,1,1,1);
  if Length(PairNodes)>65536 then
    raise ENativeEvalError.CreateAt('забагато фізичних позначок крапкових D2 пар',1,1,1);
  for I:=0 to High(KeyedAtoms) do begin
    if KeyedAtoms[I].Node=nil then
      raise ENativeEvalError.CreateAt(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F,1,1,1);
    { KeyBits перевіряє width, діапазон і leading-zero exact identity. }
    Bits:=KeyBits(KeyedAtoms[I].Key);
    if Bits='' then
      raise ENativeEvalError.CreateAt(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D1#$96#$20#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8,1,1,1);
  end;
  { Копія не змінює порядок caller-даних; її життя лише один виклик.
    Дубльована borrowed-адреса робила б вибір exact key неоднозначним. }
  FKeyedAtoms:=Copy(KeyedAtoms,0,Length(KeyedAtoms));
  FPairNodes:=Copy(PairNodes,0,Length(PairNodes));
  try
    SortKeyedAtoms;
    for I:=1 to High(FKeyedAtoms) do
      if FKeyedAtoms[I-1].Node=FKeyedAtoms[I].Node then
        raise ENativeEvalError.CreateAt(
          #$D0#$BF#$D0#$BE#$D0#$B2#$D1#$82#$D0#$BE#$D1#$80#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D0#$B0#$D0#$B4#$D1#$80#$D0#$B5#$D1#$81#$D0#$B0#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0,1,1,1);
    SortPairNodes;
    for I:=0 to High(FPairNodes) do begin
      if (FPairNodes[I].Node=nil) or
         (FPairNodes[I].Node.Kind<>skList) or
         (Length(FPairNodes[I].Node.Children)<>2) then
        raise ENativeEvalError.CreateAt(
          'неправильна фізична позначка крапкової D2 пари',1,1,1);
      if (I>0) and
         (FPairNodes[I-1].Node=FPairNodes[I].Node) then
        raise ENativeEvalError.CreateAt(
          'повторна фізична позначка крапкової D2 пари',1,1,1);
    end;
    FKeyedMode:=True;
    Result:=EvaluateNode(N);
  finally
    FKeyedMode:=False;
    SetLength(FKeyedAtoms,0);
    SetLength(FPairNodes,0);
  end;
end;

{ Фізичний режим короткочасний, навіть коли evaluator кидає виняток.
  Усі ключі/AST borrowed; власник caller не змінюється. }
function TNativeEvaluator.EvaluateKeyedNodePhysical(N:TSourceNode;
  const KeyedAtoms:TNativeKeyedAtoms):RawByteString;
begin
  Result:=EvaluateKeyedNodePhysical(N,KeyedAtoms,TNativePairNodes(nil));
end;

function TNativeEvaluator.EvaluateKeyedNodePhysical(N:TSourceNode;
  const KeyedAtoms:TNativeKeyedAtoms;
  const PairNodes:TNativePairNodes):RawByteString;
begin
  if FPhysicalOutput then
    raise ENativeEvalError.CreateAt('вкладений фізичний режим не підтримано',1,1,1);
  FPhysicalOutput:=True;
  try
    Result:=EvaluateKeyedNode(N,KeyedAtoms,PairNodes);
  finally
    FPhysicalOutput:=False;
  end;
end;

function TNativeEvaluator.EvaluateSource(const Source:RawByteString):RawByteString;
var Doc:TSourceDocument;
begin
  Doc:=ReadUkrainianSource(Source);
  try
    if Length(Doc.Forms)<>1 then
      raise ENativeEvalError.CreateAt('native evaluation requires one form',1,1,1);
    Result:=EvaluateNode(Doc.Forms[0]);
  finally
    Doc.Free;
  end;
end;
end.
