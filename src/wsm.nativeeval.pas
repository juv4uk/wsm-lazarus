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
    { FNodes — тіла закриттів. Клітинка зберегти вузол не може, а Eval
      приймає саме TSourceNode. Тому тіло лежить тут, а ncClosure тримає
      лише індекс. Розмір TNativeCell не змінений. }
    FNodes:array of TSourceNode;
    { Захоплене локальне оточення для кожного FNodes[I]. Живе лише в
      одній FCells-арені до Reset, не є доменним словом або новим законом.
      Паралельні масиви зберігають розмір TNativeCell і точні ключі.
      Це ПОСИЛАННЯ на ланцюг пар (імʼя . значення), не копія значень:
      тому SETQ (D5:00111) міняє значення наявної пари (FindBinding),
      і замикання, створене раніше, бачить нове звʼязування. }
    FClosureEnvs:array of SizeInt;
    { FGlobalEnv — верхній рівень оточення (аліста на ncPair), 0 = порожне.
      Причина окремого поля: Eval приймає Env ЗА ЗНАЧЕННЯМ, тому форма, що
      звʼязує імʼя, не могла б передати нове оточення далі. Core1 робить це
      так само у два рівні: спершу локальне оточення, потім глобальне
      (external/sens/lib/core1.lisp:155-167, ядро1-значення-із-локального-пошуку).
      Час життя БЕЗ сесії — рівно одне обчислення: Reset обнуляє поле, бо
      вузли TSourceNode належать TSourceDocument і звільняються разом із
      ним. У сесії (BeginSession) поле переживає форму, і тоді AST кожної
      форми приймається сесією — див. FSessionDocs. }
    FGlobalEnv:SizeInt;
    { Постійне (сесійне) оточення. FSessionMode вмикає режим, у якому Reset
      НЕ обнуляє ні арену, ні FGlobalEnv: визначення переживають обчислення.
      FSessionDocs — володіння AST форм сесії. Навіщо: тіло замикання
      (FNodes) — це вузол TSourceNode, а вузли належать TSourceDocument;
      без власника виклик замикання з наступної форми читав би звільнену
      памʼять. Звільняються в EndSession і в деструкторі. }
    FSessionMode:Boolean;
    FSessionDocs:array of TSourceDocument;
    FUsed,FMaxCells,FMaxSteps,FSteps,FMaxDepth:SizeInt;
    FKeyedMode,FPhysicalOutput:Boolean;
    FKeyedAtoms:TNativeKeyedAtoms;
    FPairNodes:TNativePairNodes;
    { Скільки звʼязувань останній SaveImage НЕ зміг покласти в образ
      (значення містить замикання, імʼя без D7-проєкції). Окреме поле,
      а не виняток: замикання — законна межа зрізу, і мовчазне зникнення
      звʼязування було б гіршим за названу втрату. }
    FImageSkipped:SizeInt;
    { Механічна індексація Borrowed Node -> pinned exact key.
      In-place heapsort без додаткового key-registry, O(N log N). }
    procedure SortKeyedAtoms;
    procedure SortPairNodes;
    function IsPhysicalPairNode(N:TSourceNode):Boolean;
    function KeyForNode(N:TSourceNode; const ErrorText:String):TDomainKey;
    { Reset обнуляє арену й FGlobalEnv — але у відкритій сесії лише скидає
      бюджет кроків: саме тому визначення переживають обчислення. }
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
    function ClosureCell(Params,Env:SizeInt; BodyNode:TSourceNode; N:TSourceNode):SizeInt;
    function Assoc(const Name:RawByteString; Env:SizeInt; N:TSourceNode):SizeInt;
    { Комірка звʼязування (пара імʼя . значення), а не значення.
      Потрібна SETQ: змінити треба САМУ пару, щоб її побачили всі, хто
      тримає на неї посилання. 0 — імені не звʼязано. }
    function FindBinding(const Name:RawByteString; Env:SizeInt):SizeInt;
    { Імʼя як ЗНАЧЕННЯ, а не як написання. Потрібне D5:00110 (встановити),
      де назва обчислюється (pinned core1.lisp:1360-1363). }
    function NameTextFromDatum(Cell:SizeInt; N:TSourceNode):RawByteString;
    { Звʼязування вже обчислених аргументів із параметрами (D10:0101100010).
      Відрізняється від Pairlis: там елемент аргументу — пара (як-є . значення)
      після Appq, тут — саме значення. }
    function BindParams(Params,Args,Env:SizeInt; N:TSourceNode):SizeInt;
    { Предикат хребта списку параметрів (D10:0101100001). Повертає D1:0/D1:1,
      як решта предикатів цього обчислювача; нового закону не вводить. }
    function RestParamP(Params:SizeInt; N:TSourceNode):SizeInt;
    function Pairlis(Params,Args,Env:SizeInt; N:TSourceNode):SizeInt;
    function TryKeyForNode(N:TSourceNode; out Key:TDomainKey):Boolean;
    function Evlis(N:TSourceNode; From,Depth,Env:SizeInt):SizeInt;
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
    { Деструктор закриває сесію, якщо вона ще відкрита: AST форм сесії та
      арена звільняються тут, а не в невідомому місці. }
    destructor Destroy; override;
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
    { ---- Постійне (сесійне) середовище: визначення переживають обчислення.
      Без сесії кожен EvaluateSource починається з порожнього FGlobalEnv, і
      це обчислювач одного виразу, а не REPL. BeginSession відкриває сесію,
      EvaluateSessionSource/EvaluateSessionNode обчислюють форму в НІЙ,
      EndSession (і деструктор) повертають усе до не-сесійного стану.
      Семантика одного обчислення не змінена: EvaluateNode під час сесії
      відмовляє явно, а не мовчки скидає сесію. }
    procedure BeginSession;
    procedure EndSession;
    { Прийняти AST форми у власність сесії (її звільнить EndSession).
      Викликається лише у відкриту сесію; nil ігнорується. }
    procedure RetainDocument(const Doc:TSourceDocument);
    function EvaluateSessionNode(N:TSourceNode):RawByteString;
    function EvaluateSessionSource(const Source:RawByteString):RawByteString;
    { Скільки імен звʼязано у верхньому (глобальному) рівні сесії.
      0 — сесія порожня; це не доменне слово й не D1-значення. }
    function SessionBindings:SizeInt;
    { ---- Образ середовища на диску: перший крок до системних образів.
      ЩО СЕРІАЛІЗУЄТЬСЯ: рівно звʼязування верхнього рівня (FGlobalEnv) —
      пари (імʼя . значення). Імʼя пишеться D7-ланцюгом літер (наявна
      ратифікована клавіатурна проєкція Д7), значення — D2/D3 структурою
      точних pinned ключів (ncDomain/ncPair/ncEmpty), тобто тими самими
      словами, які вже виробляє RenderPhysical.
      ФОРМАТ: канонічний T5M (EncodeT5M/DecodeT5M) — той самий фізичний
      .sens-транспорт, що й фізичний вивід. Жодного нового текстового
      формату, жодного заголовка, версії або Pascal-серіалізації: слова
      перевіряються наново проти pinned таблиць під час читання, тому
      образ чужої ревізії відмовляє, а не тлумачиться навмання.
      ЩО НЕ СЕРІАЛІЗУЄТЬСЯ: тіла замикань (FNodes) — це вузли AST
      документа сесії, вони не переживають процес за побудовою. Тому
      звʼязування, чиє значення містить ncClosure (або імʼя якого не має
      D7-проєкції, або значення якого — D2-обрамлення), в образ НЕ
      потрапляє і рахується в ImageSkippedBindings. FNames, FNodes,
      FClosureEnvs і FCells — похідні: вони будуються наново з образу,
      а не переносяться.
      Повертає кількість записаних / відновлених звʼязувань. }
    function SaveImage(const FileName:RawByteString):SizeInt;
    function LoadImage(const FileName:RawByteString):SizeInt;
    function ImageSkippedBindings:SizeInt;
  end;
{ Границя host Appq→Pairlis: параметр отримує саме значення, не цитату.
  QuotedPair і QuoteHead — клітинки тієї ж тимчасової арени; ця функція
  не виділяє нічого, повертає лише індекс borrowed value. Exact D3:001
  відрізняється від D1:1 навіть за тотожного числового payload.
  Питання: хто володіє value handle? Чому width обов'язкова?
  Чому при відмові результат обнуляється? Чому не потрібен текст укр? }
function TryAppqActual(const QuotedPair,QuoteHead:TNativeCell;
  out ValueHandle:SizeInt):Boolean;
implementation
uses wsm.t5m, wsm.d2source, Classes;
function TryAppqActual(const QuotedPair,QuoteHead:TNativeCell;
  out ValueHandle:SizeInt):Boolean;
begin
  ValueHandle:=0;
  Result:=(QuotedPair.Kind=ncPair) and
          (QuoteHead.Kind=ncDomain) and
          (QuoteHead.Key.Width=3) and
          (QuoteHead.Key.Bits=1) and
          (QuotedPair.Rest>=0);
  if Result then ValueHandle:=QuotedPair.Rest;
end;
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
  { У відкритій сесії Reset не має права обнуляти арену й FGlobalEnv:
    саме це й робило оточення одноразовим. Скидається лише бюджет кроків —
    він і в не-сесійному режимі рахується на одне обчислення. }
  if FSessionMode then begin
    FSteps:=0;
    Exit;
  end;
  SetLength(FCells,0); SetLength(FCells,1);
  SetLength(FNames,0); SetLength(FNodes,0);
  SetLength(FClosureEnvs,0); { Env cell handles стають недійсні з Reset. }
  FCells[0].Kind:=ncEmpty;
  FCells[0].Key:=ExactKey('000'); { D3:000, не D1:0. }
  FUsed:=1; FSteps:=0;
  { Без сесії звʼязування живе рівно одне обчислення (див. FGlobalEnv). }
  FGlobalEnv:=0;
end;
{ ---------------------------------------------------------------- сесія --
  Три питання, на які цей блок відповідає прямо:
    1) хто обнуляв оточення — САМ обчислювач, у Reset на вході й у finally
       EvaluateNode, а не зовнішній драйвер;
    2) чи був готовий механізм збереження — ні, окремого сховища не було;
       був лише транспорт сеансу (wsm.session), який не читав і не зберігав
       нічого з цієї арени;
    3) що з цього виходить — сесійний режим тут, у тому самому обчислювачі:
       жодного другого оточення, жодного другого пошуку імен. }
procedure TNativeEvaluator.BeginSession;
begin
  if FSessionMode then Exit; { ідемпотентно: повторне відкриття нічого не скидає }
  Reset;                     { старт сесії — з чистої арени }
  FSessionMode:=True;
end;

procedure TNativeEvaluator.EndSession;
var I:SizeInt;
begin
  FSessionMode:=False;
  for I:=0 to High(FSessionDocs) do FSessionDocs[I].Free;
  SetLength(FSessionDocs,0);
  Reset;                     { повне обнулення, як у не-сесійному режимі }
end;

procedure TNativeEvaluator.RetainDocument(const Doc:TSourceDocument);
var I:SizeInt;
begin
  if Doc=nil then Exit;
  if not FSessionMode then
    raise ENativeEvalError.CreateAt(
      'AST можна прийняти лише у відкриту сесію (немає BeginSession)',1,1,1);
  I:=Length(FSessionDocs);
  SetLength(FSessionDocs,I+1);
  FSessionDocs[I]:=Doc;
end;

function TNativeEvaluator.EvaluateSessionNode(N:TSourceNode):RawByteString;
var H:SizeInt;
begin
  if not FSessionMode then
    raise ENativeEvalError.CreateAt(
      'сесійне оточення не відкрите: спершу BeginSession',1,1,1);
  if N=nil then
    raise ENativeEvalError.CreateAt('відсутня форма для обчислення',1,1,1);
  { Жодного Reset арени: FGlobalEnv і клітинки лишаються від попередніх
    форм. Скидається лише бюджет кроків — він завжди на одне обчислення. }
  FSteps:=0;
  H:=Eval(N,0);
  if FPhysicalOutput then Result:=RenderPhysical(H,0)
  else Result:=Render(H,0);
end;

function TNativeEvaluator.EvaluateSessionSource(const Source:RawByteString):RawByteString;
var Doc:TSourceDocument;
begin
  if not FSessionMode then
    raise ENativeEvalError.CreateAt(
      'сесійне оточення не відкрите: спершу BeginSession',1,1,1);
  Doc:=ReadUkrainianSource(Source);
  { Приймаємо AST ДО обчислення: якщо форма створить замикання, її вузол
    стане тілом (FNodes), і звільняти документ після форми вже не можна. }
  RetainDocument(Doc);
  if Length(Doc.Forms)<>1 then
    raise ENativeEvalError.CreateAt('native evaluation requires one form',1,1,1);
  Result:=EvaluateSessionNode(Doc.Forms[0]);
end;

function TNativeEvaluator.SessionBindings:SizeInt;
var E:SizeInt;
begin
  Result:=0; E:=FGlobalEnv;
  while (E<>0) and (FCells[E].Kind=ncPair) do begin
    Inc(Result); E:=FCells[E].Rest;
  end;
end;

destructor TNativeEvaluator.Destroy;
begin
  EndSession; { звільняє AST сесії та арену }
  inherited Destroy;
end;
procedure TNativeEvaluator.Fail(N:TSourceNode; const MessageText:String);
begin
  { N=nil буває лише на шляху відновлення образу: там вузла AST немає, бо
    значення народжується з файлу, а не з джерела. Тоді чесніше назвати
    невідоме місце (1,1,1), ніж упасти на розіменуванні nil і замінити
    змістовну відмову порожнім segfault. Місце помилки — не семантика. }
  if N=nil then
    raise ENativeEvalError.CreateAt(MessageText,1,1,1);
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

function TNativeEvaluator.ClosureCell(Params,Env:SizeInt; BodyNode:TSourceNode; N:TSourceNode):SizeInt;
var C:TNativeCell; I:SizeInt;
begin
  { Key лишається порожнім: закриття не має доменної адреси, і видавати
    йому ключ означало б вигадати новий домен. }
  { Rest тепер — індекс у FNodes, а не ланцюг клітинок. }
  I:=Length(FNodes);
  SetLength(FNodes,I+1);
  SetLength(FClosureEnvs,I+1);
  FNodes[I]:=BodyNode; FClosureEnvs[I]:=Env;
  { Env — borrowed handle у цій арені; клітинка ncClosure не володіє
    іншою пам'яттю, після Reset обидва масиви й посилання недійсні.
    1) Чому брати Env створення, а не викликача?
    2) Чому FNodes та FClosureEnvs мають спільний індекс?
    3) Хто звільняє тіло AST?
    4) Чому це не змінює фізичні байти SENS? }
  C:=Default(TNativeCell); C.Kind:=ncClosure; C.First:=Params; C.Rest:=I;
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
var E,Pair,Cell:SizeInt; Stage:SizeInt;
begin
  { Два рівні, як у core1.lisp:155-167: спершу локальне оточення виклику,
    потім глобальне (FGlobalEnv). Без другого рівня форма звʼязування імені
    (Д5:00100/00111) не мала б де лишитися: Eval приймає Env за значенням. }
  for Stage:=0 to 1 do begin
    if Stage=0 then E:=Env
    else begin
      if (FGlobalEnv=0) or (FGlobalEnv=Env) then Break;
      E:=FGlobalEnv;
    end;
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
  end;
  Result:=0;
end;

{ Знайти ПАРУ (імʼя . значення) в алісті-оточенні — ту саму комірку, а не
  її значення. Порядок той самий, що в Assoc: спершу локальне оточення
  виклику, потім FGlobalEnv; затінення виграє так само (перша пара).
  Навіщо окремо від Assoc: SETQ мусить змінити значення наявної пари,
  а не додати нову, інакше замикання бачить знімок, а не комірку. }
function TNativeEvaluator.FindBinding(const Name:RawByteString; Env:SizeInt):SizeInt;
var E,Pair,Cell,Stage:SizeInt;
begin
  for Stage:=0 to 1 do begin
    if Stage=0 then E:=Env
    else begin
      if (FGlobalEnv=0) or (FGlobalEnv=Env) then Break;
      E:=FGlobalEnv;
    end;
    while E<>0 do begin
      if FCells[E].Kind<>ncPair then Break;
      Pair:=FCells[E].First;
      if (Pair<>0) and (FCells[Pair].Kind=ncPair) then begin
        Cell:=FCells[Pair].First;
        if (Cell<>0) and (FCells[Cell].Kind=ncName)
           and (FNames[FCells[Cell].First]=Name) then
          Exit(Pair);
      end;
      E:=FCells[E].Rest;
    end;
  end;
  Result:=0;
end;

{ Імʼя як значення. core1.lisp:1360-1363 обчислює НАЗВУ (друге поле форми)
  перед записом, тому встановити мусить узяти назву зі ЗНАЧЕННЯ, а не з
  написання — саме цим воно й відрізняється від встановити-імʼя (SETQ).
  У цьому обчислювачі імʼя не має власного домену: воно або вже є клітинкою
  ncName (параметри замикання), або приходить як D7-дані — (як-є атом) дає
  ланцюг D7-клітинок, по одній на літеру (Quote/IndexedUkrainianInDomain).
  Обидві форми — та сама структурна тотожність, яку core1 порівнює через
  назви-рівні?. Зворотне відображення бере ук-поверхню ЛИШЕ з pinned таблиці
  D7 (DomainRowByKey), тобто жодного нового словника й жодної нової літери. }
function TNativeEvaluator.NameTextFromDatum(Cell:SizeInt; N:TSourceNode):RawByteString;
var E,Item:SizeInt; Row:TDomainRow; Text:RawByteString;
begin
  if (Cell<=0) or (Cell>=FUsed) then
    Fail(N,'імʼя: очікую імʼя або D7-дані, а не порожнечу');
  if FCells[Cell].Kind=ncName then Exit(FNames[FCells[Cell].First]);
  Text:='';
  E:=Cell;
  while E<>0 do begin
    if (E<0) or (E>=FUsed) or (FCells[E].Kind<>ncPair) then
      Fail(N,'імʼя: очікую правильний список D7-літер');
    Item:=FCells[E].First;
    if (Item<=0) or (Item>=FUsed) or (FCells[Item].Kind<>ncDomain) or
       (FCells[Item].Key.Width<>7) then
      Fail(N,'імʼя: кожен елемент мусить бути D7-літерою');
    if not DomainRowByKey(FDomains[7],FCells[Item].Key,Row) then
      Fail(N,'імʼя: D7-літери немає в pinned таблиці');
    Text:=Text+Row.Ukrainian;
    E:=FCells[E].Rest;
  end;
  if Text='' then Fail(N,'імʼя: порожнє D7-імʼя');
  Result:=Text;
end;

{ зв'язати-параметри (D10:0101100010, d10.lisp:365). Pinned закон —
  core1.lisp:193-207 поєднати-параметри (параметри передані-значення оточення):
    порожні параметри + порожні аргументи -> оточення
    порожні параметри, але є аргументи   -> ARITY TOO-MANY-ARGUMENTS
    є параметри, але немає аргументів    -> ARITY TOO-FEW-ARGUMENTS
    інакше -> cons(cons(param, arg), pairlis(rest, rest, env))
  Ті самі дві РІЗНІ помилки арності, що й у Pairlis: це два різні випадки
  джерела. Порядок cons-ів той самий, тому останній параметр стоїть першим —
  як і в core1, і саме він виграє в Assoc (затінення першою парою). }
function TNativeEvaluator.BindParams(Params,Args,Env:SizeInt; N:TSourceNode):SizeInt;
var P,A:SizeInt; NameText:RawByteString;
begin
  if (Env<0) or (Env>=FUsed) then Fail(N,'звʼязати-параметри: оточення поза ареною');
  if (Env<>0) and (FCells[Env].Kind<>ncPair) then
    Fail(N,'звʼязати-параметри: оточення мусить бути алістою або ()');
  P:=Params; A:=Args;
  while (P<>0) and (A<>0) do begin
    if (P<0) or (P>=FUsed) or (FCells[P].Kind<>ncPair) then
      Fail(N,'звʼязати-параметри: очікую список параметрів');
    if (A<0) or (A>=FUsed) or (FCells[A].Kind<>ncPair) then
      Fail(N,'звʼязати-параметри: очікую список аргументів');
    NameText:=NameTextFromDatum(FCells[P].First,N);
    Env:=PairCell(PairCell(NameCell(NameText,N),FCells[A].First,N),Env,N);
    P:=FCells[P].Rest; A:=FCells[A].Rest;
  end;
  if (P=0) and (A<>0) then Fail(N,'ARITY: TOO-MANY-ARGUMENTS');
  if (P<>0) and (A=0) then Fail(N,'ARITY: TOO-FEW-ARGUMENTS');
  Result:=Env;
end;

{ є-параметр-залишку? (D10:0101100001, d10.lisp:364). Pinned закон —
  external/sens/lib/meta-eval.lisp:477-484 лямбда-має-параметр-залишку?
  (параметри):
      (атом? параметри) і параметри тотожне ()  -> ні
      (атом? параметри) і параметри не ()      -> так
      інакше (пара)                             -> лямбда-має-параметр-залишку? (решта параметри)
  Тобто предикат іде по ХРЕБТУ списку параметрів і нічого не читає з голів:
      (х у)        — хребет закінчується на () — залишку немає (D1:0);
      (х у . z)    — хребет закінчується на атом z — залишок є (D1:1);
      z            — сам атом, не () — залишок є (D1:1);
      ()           — порожній хребет — залишку немає (D1:0).
  Це та сама структура, з якої порахувати-обовʼязкові-параметри-лямбди
  (meta-eval.lisp:466-470) бере фіксовану кількість, тому жодної нової
  семантики не вводиться — лише читання вже наявного ланцюга ncPair.
  Порожній список у цій арені — комірка 0 (D3:000), як і в BindParams.
  D1:0/D1:1 будуються тим самим DomainCell, що й у предикатів D3.
  Єдина межа типів — контейнер ncClosure: він не є SENS-датумом узагалі,
  тому замикання як СПИСОК ПАРАМЕТРІВ відхиляється названою діагностикою,
  а не мовчки витлумачується як атом. }
function TNativeEvaluator.RestParamP(Params:SizeInt; N:TSourceNode):SizeInt;
var P:SizeInt;
begin
  P:=Params;
  { Хребет: поки комірка — пара, крок праворуч. Цикл, а не рекурсія:
    глибина списку параметрів не має власного бюджету кроків. }
  while (P<>0) and (P>=0) and (P<FUsed) and (FCells[P].Kind=ncPair) do
    P:=FCells[P].Rest;
  if (P<0) or (P>=FUsed) then
    Fail(N,'є-параметр-залишку? (D10:0101100001): параметри поза ареною');
  if P=0 then Exit(DomainCell(ExactKey('0'),N)); { () — залишку немає }
  if FCells[P].Kind=ncClosure then
    Fail(N,'є-параметр-залишку? (D10:0101100001): замикання не є списком параметрів');
  Result:=DomainCell(ExactKey('1'),N); { атом, відмінний від () — залишок є }
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
var P,A,Element,QuoteHead,Value:SizeInt;
begin
  P:=Params; A:=Args;
  while (P<>0) and (A<>0) do begin
    if (P<0) or (P>=FUsed) or (A<0) or (A>=FUsed) then
      Fail(N,'недопустимий індекс параметра або аргументу');
    if (FCells[P].Kind<>ncPair) or (FCells[A].Kind<>ncPair) then
      Fail(N,'очікувався список параметрів та аргументів');
    { Appq вже побудував пару (D3:001 . обчислене_значення).
      Pairlis передає значення, але лише після перевірки, що перша
      клітинка справді ТОЧНА D3:001, а не D1:1 або довільний ncName.
      Усі індекси обмежені поточною ареною; нового закону немає. }
    Element:=FCells[A].First;
    if (Element<=0) or (Element>=FUsed) or
       (FCells[Element].Kind<>ncPair) then
      Fail(N,'APPQ: очікується цитована пара');
    QuoteHead:=FCells[Element].First;
    if (QuoteHead<=0) or (QuoteHead>=FUsed) then
      Fail(N,'APPQ: відсутня голова D3:001');
    if not TryAppqActual(FCells[Element],FCells[QuoteHead],Value) then
      Fail(N,'APPQ: некоректний точний домен цитати');
    if Value>=FUsed then Fail(N,'APPQ: значення поза ареною');
    Env:=PairCell(PairCell(FCells[P].First,Value,N),Env,N);
    P:=FCells[P].Rest; A:=FCells[A].Rest;
  end;
  if (P=0) and (A<>0) then Fail(N,'ARITY: TOO-MANY-ARGUMENTS');
  if (P<>0) and (A=0) then Fail(N,'ARITY: TOO-FEW-ARGUMENTS');
  Result:=Env;
end;

{ evlis: обчислити кожен аргумент форми в оточенні Env і зібрати в ланцюг.
  Порядок збережений: обчислюємо зліва направо, ланцюг будуємо ззаду. }
function TNativeEvaluator.Evlis(N:TSourceNode; From,Depth,Env:SizeInt):SizeInt;
var I:SizeInt;
begin
  if N.Kind<>skList then Fail(N,'evlis потребує список');
  Result:=0;
  { From — з якого нащадка почати: у формі виклику це 1, бо 0 — голова. }
  for I:=Length(N.Children)-1 downto From do
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

{ Не-кидаючий пошук ключа. Потрібен, бо голова форми може бути
  ІМ'ЯМ ПАРАМЕТРА, а не доменним словом: KeyForNode на такому законно
  кидає, і саме тому параметр не міг стати головою. Тут відсутність
  ключа — не помилка, а привід пошукати в оточенні. }
function TNativeEvaluator.TryKeyForNode(N:TSourceNode; out Key:TDomainKey):Boolean;
begin
  try
    Key:=KeyForNode(N,'немає ключа');
    Result:=True;
  except
    on ENativeEvalError do begin
      Key.Width:=0; Key.Bits:=0;
      Result:=False;
    end;
  end;
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
    NameText:RawByteString;
begin
  Step(N,Depth);
  if N.Kind=skAtom then begin
    { D1 значення від pinned binder мають перевагу над текстом імені.
      Якщо ж точного доменного ключа немає, дозволений лише пошук
      параметра у ВЖЕ створеному лексичному оточенні цього виклику.
      Env і value handle — індекси тимчасової FCells; власник evaluator.
      Нового доменного слова чи глобального визначення не створюємо.
      Питання: чому спершу exact key? Чому відсутнє ім'я — помилка?
      Як зберігається D1:0 ≠ D3:000? Хто володіє Env? }
    if TryKeyForNode(N,Key) then begin
      { D1 є самодостатнім значенням. Текстова D7-проєкція
        параметра може вже мати pinned координату, проте доменне
        слово НЕ стає значенням саме по собі. Дозволяємо лише
        знайдений у поточному Env лексичний аргумент. }
      if Key.Width=1 then Exit(DomainCell(Key,N));
      if (Env<>0) or (FGlobalEnv<>0) then begin
        A:=Assoc(N.Text,Env,N);
        if A<>0 then Exit(A);
      end;
      Fail(N,'unsupported native value domain');
    end;
    if (Env<>0) or (FGlobalEnv<>0) then begin
      A:=Assoc(N.Text,Env,N);
      if A<>0 then Exit(A);
    end;
    Fail(N,'unknown native binding');
  end;
  if N.Kind<>skList then Fail(N,'unsupported native string value');
  if IsPhysicalPairNode(N) then
    Fail(N,'фізична D2 крапкова пара є значенням, не формою виклику');
  if Length(N.Children)=0 then Exit(0);
  { Обчислена голова — лише реально створений D10 closure.
    Ніяких host назв-функцій, індексів як opcode або evaluator fallback.
    Обчислення голови відбувається в поточному Env; байти фізичного
    результату визначає чинний pinned D1 renderer після Eval тіла.
    Значення/тіло живуть у FCells/FNodes до кінця одного EvaluateNode.
    Питання: чому замикання перевіряється за Kind? Де перевіряємо
    арність? Чому не можна викликати довільну pair-голову?
    Коли Reset звільняє borrowed вузли? }
  if N.Children[0].Kind<>skAtom then begin
    A:=Eval(N.Children[0],Depth+1,Env);
    if (A<=0) or (A>=FUsed) or (FCells[A].Kind<>ncClosure) then
      Fail(N.Children[0],'обчислена голова не є перевіреним замиканням');
    B:=Appq(Evlis(N,1,Depth+1,Env),N);
    Exit(Eval(FNodes[FCells[A].Rest],Depth+1,
              Pairlis(FCells[A].First,B,FClosureEnvs[FCells[A].Rest],N)));
  end;
  { Голова може бути ім'ям параметра, а не доменним словом. Тоді шукаємо
    закриття в оточенні: Evlis -> Appq -> Pairlis -> Eval тіла.
    Це і є apply Маккарті, зібраний із шести частин, кожна з яких уже є. }
  if not TryKeyForNode(N.Children[0],Key) then begin
    A:=Assoc(N.Children[0].Text,Env,N);
    if (A<>0) and (FCells[A].Kind=ncClosure) then begin
      B:=Appq(Evlis(N,1,Depth+1,Env),N);
      Exit(Eval(FNodes[FCells[A].Rest],Depth+1,
                Pairlis(FCells[A].First,B,FClosureEnvs[FCells[A].Rest],N)));
    end;
    Fail(N.Children[0],'unknown native call head');
  end;
  { Поверхня вже стала точним ключем; подальший dispatch лише D3+біти.
    Членство у таблиці НЕ дозволяє довільний виклик. Решта BLOCKED. }
  if not (Key.Width in [3,5,10]) then
    Fail(N.Children[0],'unsupported native callable domain');
  { D10: замикання. Адреси з pinned lib/domains/d10.lisp:
      0100111100 створити-лямбда-замикання
      0101100010 зв'язати-параметри
      0101100001 є-параметр-залишку?
    Диспетч за бітами, не за назвами. Реалізовано створення замикання,
    зв'язати-параметри (0101100010) і є-параметр-залишку? (0101100001).
    Решта адрес D10 свідомо відмовляє, а не прикидається виконаною. }
  { D5: мітка (LABEL). Адреса з pinned lib/domains/d5.lisp:13:
      00100 мітка / LABEL
    Мітка — це іменоване закриття: тіло плюс зв'язування імені з самим
    собою в оточенні. Саме тому вона окремо від D10, де замикання.
    Другий ширино-5 ключ — 00111 встановити-імʼя (SETQ), d5.lisp:16.
    Обидві форми лише звʼязують імʼя в FGlobalEnv; обчислювану голову
    вони не вмикають і не вимикають — це окреме рішення (рядок 584). }
  if Key.Width=5 then begin
    { Варіант Б: імʼя звʼязує ОКРЕМА форма, а не обчислювана голова.
      Форми пишуться так, як їх пише сам Core1:
        (визначити імʼя (мітка імʼя (функція (...) ...)))  — рекурсивна,
        (визначити імʼя (функція (...) ...))              — нерекурсивна
      (core1.lisp:76-78, 89-96, 194-207 — рекурсивні визначення через
      мітка; нерекурсивні, напр. core1.lisp:61-63, без неї). }
    if Key.Bits=%00100 then begin
      { мітка (LABEL), d5.lisp:13. Core1 обчислює лише ТРЕТЄ поле
        (core1.lisp:399-400) — імʼя в обчисленні не бере участі.
        Тут імʼя додатково звʼязується з самим замиканням, щоб рекурсивний
        виклик у тілі знайшовся через Assoc: інакше мітка нічим не
        відрізнялась би від створити-лямбда-замикання. }
      if Length(N.Children)<>3 then
        Fail(N,'мітка (D5:00100): не реалізовано для форми без тіла (#804)');
      if N.Children[1].Kind<>skAtom then
        Fail(N.Children[1],
          'мітка (D5:00100): не реалізовано для неатомного імені (#804)');
      A:=Eval(N.Children[2],Depth+1,Env);
      if FCells[A].Kind<>ncClosure then
        Fail(N.Children[2],'мітка (D5:00100): тіло мусить дати замикання');
      B:=PairCell(NameCell(N.Children[1].Text,N),A,N);
      FGlobalEnv:=PairCell(B,FGlobalEnv,N);
      Exit(A);
    end;
    if Key.Bits=%00111 then begin
      { встановити-імʼя (SETQ), d5.lisp:16 — єдиний ширино-5 ключ, що
        звʼязує імʼя зі значенням; у самому core1.lisp він не вживається
        (0 згадок), тому семантика взята з назви та рядка 16 таблиці Д5:
        обчислити другий аргумент і покласти його під імʼя першого. }
      if Length(N.Children)<>3 then
        Fail(N,'встановити-імʼя (D5:00111): очікую імʼя і вираз');
      if N.Children[1].Kind<>skAtom then
        Fail(N.Children[1],'встановити-імʼя (D5:00111): імʼя мусить бути атомом');
      A:=Eval(N.Children[2],Depth+1,Env);
      { СПІЛЬНА КОМІРКА, А НЕ ЗНІМОК. Замикання тримає індекс ланцюга
        пар (імʼя . значення), а не копію значення, тому присвоєння
        мусить змінити ЗНАЧЕННЯ наявної пари — тоді кожне замикання,
        створене раніше, бачить нове звʼязування (як SETQ у SBCL).
        Раніше тут завжди додавалася НОВА пара в FGlobalEnv: локальна
        пара захопленого оточення лишалася зі старим значенням, і
        замикання поводилося як знімок. Незвʼязане імʼя, як і досі,
        додається в FGlobalEnv — нової семантики для нього немає. }
      B:=FindBinding(N.Children[1].Text,Env);
      if B<>0 then
        FCells[B].Rest:=A
      else begin
        B:=PairCell(NameCell(N.Children[1].Text,N),A,N);
        FGlobalEnv:=PairCell(B,FGlobalEnv,N);
      end;
      Exit(A);
    end;
    if Key.Bits=%00110 then begin
      { встановити (SET), d5.lisp:15. Відміна від встановити-імʼя (00111)
        рівно одна й названа в pinned core1.lisp:1360-1363: НАЗВА
        обчислюється (обчислити-форму-ядра (друге ...)), а далі обидві
        форми йдуть тим самим продовженням продовжити-запис-програми
        (core1.lisp:1319-1326) до оновити-зв'язування-програми. Тому тут
        спершу обчислюється назва, потім вираз, і запис робить та сама
        спільна комірка (FindBinding), що й у SETQ: наявна пара змінюється,
        незвʼязане імʼя додається в FGlobalEnv. Значення форми — записане. }
      if Length(N.Children)<>3 then
        Fail(N,'встановити (D5:00110): очікую назву і вираз');
      A:=Eval(N.Children[1],Depth+1,Env);
      NameText:=NameTextFromDatum(A,N.Children[1]);
      B:=Eval(N.Children[2],Depth+1,Env);
      I:=FindBinding(NameText,Env);
      if I<>0 then
        FCells[I].Rest:=B
      else begin
        I:=PairCell(NameCell(NameText,N),B,N);
        FGlobalEnv:=PairCell(I,FGlobalEnv,N);
      end;
      Exit(B);
    end;
    Fail(N.Children[0],'unsupported D5 callable');
  end;
  if Key.Width=10 then begin
    if Key.Bits=%0100111100 then begin
      if Length(N.Children)<>3 then
        Fail(N,'closure needs parameters and body');
      Exit(ClosureCell(StructuralCells(N.Children[1],Depth+1),
                       Env,N.Children[2],N));
    end;
    if Key.Bits=%0101100010 then begin
      { зв'язати-параметри (BIND-PARAMS), d10.lisp:365. Три аргументи, як у
        pinned (функція (параметри передані-значення оточення)) — усі три
        обчислюються: параметри приходять D7-даними (як-є (х у)), аргументи —
        обчисленим списком значень, оточення — наявною алістою або ().
        Результат — нова аліста; жодного запису в FGlobalEnv тут немає. }
      if Length(N.Children)<>4 then
        Fail(N,'звʼязати-параметри (D10:0101100010): очікую параметри, аргументи й оточення');
      A:=Eval(N.Children[1],Depth+1,Env); { параметри }
      B:=Eval(N.Children[2],Depth+1,Env); { аргументи }
      I:=Eval(N.Children[3],Depth+1,Env); { оточення }
      Exit(BindParams(A,B,I,N));
    end;
    if Key.Bits=%0101100001 then begin
      { є-параметр-залишку? (MY-REST-PARAM?), d10.lisp:364. Рівно один
        аргумент — список параметрів, як у pinned meta-eval.lisp:477-484
        (функція (параметри) ...). Аргумент ОБЧИСЛЮЄТЬСЯ: параметри
        приходять даними ((як-є (х у))), а не написанням форми.
        Результат — D1:0 або D1:1, як у решти предикатів. }
      if Length(N.Children)<>2 then
        Fail(N,'є-параметр-залишку? (D10:0101100001): очікую список параметрів');
      A:=Eval(N.Children[1],Depth+1,Env);
      Exit(RestParamP(A,N));
    end;
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
      { Оточення мусить іти далі: тіло замикання — це теж код, і
        параметр у ньому шукається лише в Env. }
      A:=Eval(Clause.Children[0],Depth+2,Env);
      if (FCells[A].Kind<>ncDomain) or (FCells[A].Key.Width<>1) then
        Fail(Clause.Children[0],'D3:110 перевірка потребує D1:0 або D1:1');
      { Порівнювати точне слово, не host truthiness і не Pascal bool.
        Будь-яке невизначене представлення відхиляється. }
      case FCells[A].Key.Bits of
        0: ; { Залишаємося на наступній гілці; expression НЕ виконуємо. }
        1: Exit(Eval(Clause.Children[1],Depth+2,Env));
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
  A:=Eval(N.Children[1],Depth+1,Env);
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
      B:=Eval(N.Children[2],Depth+1,Env);
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
      B:=Eval(N.Children[2],Depth+1,Env);
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
      ncClosure: begin
        { Замикання не має ратифікованої текстової проєкції в SENS, і
          вигадувати їй доменну адресу не можна. Але й зникати з виводу
          воно не сміє, і відмовляти на ньому теж не можна: свідок #866
          вимагає, щоб створення замикання було ПРИЙНЯТО. Тому — явний
          внутрішній маркер плюс параметри (наявний ланцюг клітинок) і
          місце тіла в FNodes. }
        Put('<замикання ');
        Emit(FCells[Cell].First,Nesting+1);
        Put(' тіло#');
        Put(IntToStr(FCells[Cell].Rest));
        Put('>');
      end;
      ncName: begin
        { Ім'я — ні доменне слово, ні число: тексту в TNativeCell немає,
          він лежить у FNames. Без цієї гілки ім'я параметра зникало б
          мовчки, і <замикання ()> брехало б про арність. }
        Put('<імʼя:');
        Put(FNames[FCells[Cell].First]);
        Put('>');
      end;
      { ncClosure/ncName — внутрішні host-комірки, не фізичні D1/D7
        значення і не завершена українська проєкція. Раніше відсутній
        else давав ПОРОЖНІЙ успішний вивід замість явної відмови.
        Ніякого прихованого serializing/evaluator fallback. }
      else raise ENativeEvalError.CreateAt(
        'NATIVE-INTERNAL-VALUE: недопустимий внутрішній тип результату native evaluator',1,1,1);
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
      { ncClosure/ncName не мають ратифікованого фізичного слова.
        Не створювати порожній або обрізаний T5M як успішну відповідь. }
      else raise ENativeEvalError.CreateAt(
        'NATIVE-INTERNAL-VALUE: недопустимий внутрішній тип фізичного результату',1,1,1);
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
  { Під час сесії EvaluateNode мовчки скинув би FGlobalEnv у finally —
    тобто знищив би саме те, заради чого сесія відкрита. Відмовляємо явно. }
  if FSessionMode then
    raise ENativeEvalError.CreateAt(
      'відкрито сесійне оточення: EvaluateNode скинув би його; вживайте EvaluateSessionSource',1,1,1);
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
{ ------------------------------------------------------------ образ ------
  Питання, на які цей блок відповідає прямо:
    1) що таке стан, а що похідне — стан це РІВНО FGlobalEnv (аліста
       (імʼя . значення)); FNames/FNodes/FClosureEnvs/FCells — це
       представлення, яке будується наново з образу;
    2) чому не можна просто вилити FCells у файл — індекси клітинок і
       адреси вузлів дійсні лише в межах однієї арени й одного процесу;
    3) чому D7 — не новий формат — тому що це вже ратифікована
       клавіатурна проєкція Д7, та сама, якою Quote цитує атом.

  Формат образу — ОДИН корінь у канонічному T5M:
      '10'                         D2 open  (корінь — список звʼязувань)
        '10'                       D2 open  (одне звʼязування)
          '10' <літера> ... '01'   імʼя: D7-ланцюг літер
          <значення>               D3/D2 структура точних ключів
        '01'
        ...
      '01'
  Це рівно ті слова, які вже виробляє RenderPhysical; жодного нового
  слова, заголовка чи текстового формату не введено. Порядок
  звʼязувань збережений: перше звʼязування в образі — перше в алісті,
  тому затінення після відновлення те саме. }

function TNativeEvaluator.ImageSkippedBindings:SizeInt;
begin
  Result:=FImageSkipped;
end;

function TNativeEvaluator.SaveImage(const FileName:RawByteString):SizeInt;
var
  Words:TExactWords; Used,Cap:SizeInt;
  E,Pair,NameIdx:SizeInt;
  Written:SizeInt;
  Binding:TExactWords;
  I:SizeInt;
  Data:RawByteString;
  Stream:TFileStream;

  procedure Push(const W:RawByteString);
  begin
    if Used=Cap then begin
      if Cap=0 then Cap:=64 else Cap:=Cap*2;
      SetLength(Words,Cap);
    end;
    Words[Used]:=W; Inc(Used);
  end;

  { Імʼя -> D7-ланцюг. Відмова не змінює OutWords: частково записане імʼя
    в образі було б гіршим за відсутнє звʼязування. }
  function NameWords(const Name:RawByteString; out OutWords:TExactWords):Boolean;
  var I,Width,N:SizeInt; Ch:RawByteString; Key:TDomainKey;
  begin
    OutWords:=nil; Result:=False;
    if Length(Name)=0 then Exit;
    N:=0; SetLength(OutWords,1); OutWords[0]:='10';
    I:=1;
    while I<=Length(Name) do begin
      if Ord(Name[I])<$80 then Width:=1
      else if Ord(Name[I])<$E0 then Width:=2
      else if Ord(Name[I])<$F0 then Width:=3 else Width:=4;
      Ch:=Copy(Name,I,Width);
      { Та сама проєкція Д7, якою Quote будує літери: не новий кодек. }
      try Key:=IndexedUkrainianInDomain(FIndex,Ch,7);
      except
        on EBindError do begin OutWords:=nil; Exit; end;
      end;
      Inc(N); SetLength(OutWords,N+1); OutWords[N]:=KeyBits(Key);
      Inc(I,Width);
    end;
    Inc(N); SetLength(OutWords,N+1); OutWords[N]:='01';
    Result:=True;
  end;

  { Значення -> слова D3/D2. Той самий обхід, що й RenderPhysical, тому
    байти образу й фізичний вивід описують структуру однаково.
    ncClosure/ncName і D2-обрамлення не мають ратифікованого слова —
    відмова, а не вигаданий маркер. }
  function ValueWords(H,Depth:SizeInt; out OutWords:TExactWords):Boolean;
  var Buf:TExactWords; BU,BC:SizeInt; Tail,Item:SizeInt;
      Bits:RawByteString; Sub:TExactWords;

    procedure BPut(const W:RawByteString);
    begin
      if BU=BC then begin
        if BC=0 then BC:=16 else BC:=BC*2;
        SetLength(Buf,BC);
      end;
      Buf[BU]:=W; Inc(BU);
    end;

  begin
    OutWords:=nil; Result:=False;
    if (Depth>256) or (H<0) or (H>=FUsed) then Exit;
    case FCells[H].Kind of
      ncEmpty: begin
        SetLength(OutWords,1); OutWords[0]:='000'; Result:=True;
      end;
      ncDomain: begin
        { D2 — фізичне обрамлення ('10'/'01'/'11'), а не значення:
          його слово збіглося б із синтаксисом образу. }
        if not (FCells[H].Key.Width in [1,3,4,5,6,7,8,9,10]) then Exit;
        Bits:=KeyBits(FCells[H].Key);
        if Bits='' then Exit;
        SetLength(OutWords,1); OutWords[0]:=Bits; Result:=True;
      end;
      ncPair: begin
        BU:=0; BC:=0; Buf:=nil;
        BPut('10');
        Tail:=H;
        while FCells[Tail].Kind=ncPair do begin
          if not ValueWords(FCells[Tail].First,Depth+1,Sub) then Exit;
          for Item:=0 to High(Sub) do BPut(Sub[Item]);
          Tail:=FCells[Tail].Rest;
        end;
        if FCells[Tail].Kind<>ncEmpty then begin
          BPut('11');
          if not ValueWords(Tail,Depth+1,Sub) then Exit;
          for Item:=0 to High(Sub) do BPut(Sub[Item]);
        end;
        BPut('01');
        SetLength(Buf,BU); OutWords:=Buf; Result:=True;
      end;
      else Exit; { ncClosure, ncName — не переживають процес }
    end;
  end;

  function BindingWords(const Name:RawByteString; V:SizeInt;
    out OutWords:TExactWords):Boolean;
  var Nw,Vw:TExactWords; I,N:SizeInt;
  begin
    OutWords:=nil; Result:=False;
    if not NameWords(Name,Nw) then Exit;
    if not ValueWords(V,0,Vw) then Exit;
    N:=2+Length(Nw)+Length(Vw);
    SetLength(OutWords,N);
    OutWords[0]:='10';
    for I:=0 to High(Nw) do OutWords[1+I]:=Nw[I];
    for I:=0 to High(Vw) do OutWords[1+Length(Nw)+I]:=Vw[I];
    OutWords[N-1]:='01';
    Result:=True;
  end;

begin
  FImageSkipped:=0;
  Words:=nil; Used:=0; Cap:=0; Written:=0;
  Push('10');
  E:=FGlobalEnv;
  while (E<>0) and (FCells[E].Kind=ncPair) do begin
    Pair:=FCells[E].First;
    NameIdx:=-1;
    if (Pair<>0) and (FCells[Pair].Kind=ncPair) then begin
      if (FCells[Pair].First<>0) and
         (FCells[FCells[Pair].First].Kind=ncName) then
        NameIdx:=FCells[FCells[Pair].First].First;
      if (NameIdx<0) or (NameIdx>High(FNames)) then
        Inc(FImageSkipped)
      else if not BindingWords(FNames[NameIdx],FCells[Pair].Rest,Binding) then
        Inc(FImageSkipped)
      else begin
        for I:=0 to High(Binding) do Push(Binding[I]);
        Inc(Written);
      end;
    end
    else Inc(FImageSkipped);
    E:=FCells[E].Rest;
  end;
  Push('01');
  SetLength(Words,Used);
  { Єдиний чинний T5M-кодек: жодного власного запису байтів. }
  Data:=EncodeT5M(Words);
  if Length(Data)>MAX_T5M_FILE_BYTES then
    raise ENativeEvalError.CreateAt('образ: перевищено межу T5M-файлу',1,1,1);
  Stream:=TFileStream.Create(FileName,fmCreate);
  try
    Stream.WriteBuffer(Data[1],Length(Data));
  finally
    Stream.Free;
  end;
  Result:=Written;
end;

function TNativeEvaluator.LoadImage(const FileName:RawByteString):SizeInt;
var
  Stream:TFileStream;
  Data:RawByteString;
  Words:TExactWords;
  Cur:SizeInt;
  NameList:array of RawByteString;
  ValueList:array of SizeInt;
  Count,I,Val:SizeInt;
  W,Nm:RawByteString;

  function NextWord(out OutW:RawByteString):Boolean;
  begin
    Result:=Cur<=High(Words);
    if Result then begin OutW:=Words[Cur]; Inc(Cur); end else OutW:='';
  end;

  { Кожна літера перевіряється проти pinned Д7: біти, яких у таблиці
    немає, — це не «схоже на імʼя», а зіпсований образ. }
  function ParseName(out Name:RawByteString):Boolean;
  var LW,Txt:RawByteString; Wd,Bits,Idx:SizeInt;
  begin
    Name:=''; Result:=False;
    if not NextWord(LW) then Exit;
    if LW<>'10' then Exit;
    while True do begin
      if not NextWord(LW) then Exit;
      if LW='01' then Break;
      Wd:=Length(LW);
      if Wd<>7 then Exit;
      Bits:=0;
      for Idx:=1 to Wd do begin
        if not (LW[Idx] in ['0','1']) then Exit;
        Bits:=Bits*2+(Ord(LW[Idx])-Ord('0'));
      end;
      if Bits>High(FDomains[7]) then Exit;
      Txt:=FDomains[7][Bits].Ukrainian;
      if Txt='' then Exit; { керувальна координата без проєкції }
      Name:=Name+Txt;
    end;
    Result:=Length(Name)>0;
    if not Result then Name:='';
  end;

  { -1 — відмова. Ніякого «найближчого» тлумачення невідомого слова. }
  function ParseValue(Depth:SizeInt):SizeInt;
  var LW:RawByteString; Wd,Bits,Idx:SizeInt; Key:TDomainKey; Row:TDomainRow;
      Items:array of SizeInt; NItems,Item,Head:SizeInt;
  begin
    Result:=-1;
    if Depth>256 then Exit;
    if not NextWord(LW) then Exit;
    if LW='000' then Exit(0);
    if LW='10' then begin
      NItems:=0; Head:=0;
      while True do begin
        if Cur>High(Words) then Exit;
        LW:=Words[Cur];
        if LW='01' then begin Inc(Cur); Break; end;
        if LW='11' then begin
          Inc(Cur);
          Item:=ParseValue(Depth+1);
          if Item<0 then Exit;
          Head:=Item;
          if not NextWord(LW) then Exit;
          if LW<>'01' then Exit;
          Break;
        end;
        Item:=ParseValue(Depth+1);
        if Item<0 then Exit;
        SetLength(Items,NItems+1); Items[NItems]:=Item; Inc(NItems);
      end;
      Result:=Head;
      for Idx:=NItems-1 downto 0 do
        Result:=PairCell(Items[Idx],Result,nil);
      Exit;
    end;
    Wd:=Length(LW);
    if not (Wd in [1,3,4,5,6,7,8,9,10]) then Exit;
    Bits:=0;
    for Idx:=1 to Wd do begin
      if not (LW[Idx] in ['0','1']) then Exit;
      Bits:=Bits*2+(Ord(LW[Idx])-Ord('0'));
    end;
    Key.Width:=Wd; Key.Bits:=Bits;
    if not DomainRowByKey(FDomains[Wd],Key,Row) then Exit;
    Result:=DomainCell(Key,nil);
  end;

begin
  if not FSessionMode then
    raise ENativeEvalError.CreateAt(
      'образ завантажують у відкриту сесію: спершу BeginSession',1,1,1);
  { Образ — це СТАН, а не злиття з наявним: інакше затінення залежало б
    від того, що встигли визначити до завантаження. }
  if FGlobalEnv<>0 then
    raise ENativeEvalError.CreateAt(
      'образ завантажують у порожню сесію: у ній уже є звʼязування',1,1,1);

  Stream:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size>MAX_T5M_FILE_BYTES then
      raise ENativeEvalError.CreateAt('образ: перевищено межу T5M-файлу',1,1,1);
    SetLength(Data,Stream.Size);
    if Length(Data)>0 then Stream.ReadBuffer(Data[1],Length(Data));
  finally
    Stream.Free;
  end;
  if Length(Data)=0 then
    raise ENativeEvalError.CreateAt('образ: порожній файл',1,1,1);
  { Канонічний декодер T5M: зіпсований файл відмовляє цілком, а не
    наполовину. }
  DecodeT5M(Data,Words);

  Cur:=0; Count:=0;
  SetLength(NameList,0); SetLength(ValueList,0);
  if not NextWord(W) or (W<>'10') then
    raise ENativeEvalError.CreateAt('образ: корінь мусить бути списком',1,1,1);
  while True do begin
    if Cur>High(Words) then
      raise ENativeEvalError.CreateAt('образ: корінь не закритий',1,1,1);
    if Words[Cur]='01' then begin Inc(Cur); Break; end;
    if not NextWord(W) or (W<>'10') then
      raise ENativeEvalError.CreateAt(
        'образ: звʼязування мусить бути списком із двох полів',1,1,1);
    if not ParseName(Nm) then
      raise ENativeEvalError.CreateAt(
        'образ: імʼя не має проєкції Д7',1,1,1);
    Val:=ParseValue(0);
    if Val<0 then
      raise ENativeEvalError.CreateAt(
        'образ: значення не має фізичної проєкції',1,1,1);
    if not NextWord(W) or (W<>'01') then
      raise ENativeEvalError.CreateAt('образ: звʼязування не закрите',1,1,1);
    SetLength(NameList,Count+1); NameList[Count]:=Nm;
    SetLength(ValueList,Count+1); ValueList[Count]:=Val;
    Inc(Count);
  end;
  if Cur<>Length(Words) then
    raise ENativeEvalError.CreateAt('образ: зайві слова після кореня',1,1,1);

  { Порядок алісти відновлюється точно: перше звʼязування образу стає
    першим у FGlobalEnv, тому затінення те саме, що було в процесі А. }
  for I:=Count-1 downto 0 do
    FGlobalEnv:=PairCell(
      PairCell(NameCell(NameList[I],nil),ValueList[I],nil),FGlobalEnv,nil);
  Result:=Count;
end;
end.
