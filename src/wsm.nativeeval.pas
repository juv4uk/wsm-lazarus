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
  TNativeCellKind=(ncEmpty,ncDomain,ncPair);
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
  TNativeEvaluator=class
  private
    FDomains:TDomainSet;
    FIndex:TBindIndex;
    FCells:array of TNativeCell;
    FUsed,FMaxCells,FMaxSteps,FSteps,FMaxDepth:SizeInt;
    FKeyedMode:Boolean;
    FKeyedAtoms:TNativeKeyedAtoms;
    { Механічна індексація Borrowed Node -> pinned exact key.
      In-place heapsort без додаткового key-registry, O(N log N). }
    procedure SortKeyedAtoms;
    function KeyForNode(N:TSourceNode; const ErrorText:String):TDomainKey;
    procedure Reset;
    procedure Fail(N:TSourceNode; const MessageText:String);
    procedure Step(N:TSourceNode; Depth:SizeInt);
    function Append(const Cell:TNativeCell; N:TSourceNode):SizeInt;
    function DomainCell(const Key:TDomainKey; N:TSourceNode):SizeInt;
    function PairCell(A,B:SizeInt; N:TSourceNode):SizeInt;
    function Quote(N:TSourceNode; Depth:SizeInt):SizeInt;
    function QuoteExact(N:TSourceNode; Depth:SizeInt):SizeInt;
    function Eval(N:TSourceNode; Depth:SizeInt):SizeInt;
    function Render(H:SizeInt; Depth:SizeInt):RawByteString;
  public
    constructor Create(const Root:RawByteString; Cells:SizeInt=4096;
      Steps:SizeInt=16384; Depth:SizeInt=128);
    function EvaluateNode(N:TSourceNode):RawByteString;
    { Виконати ТОЙ САМИЙ D3 механізм, але без українського bind/projection.
      Кожен atom N має вже перевірений exact-key; невідомий вузол — ERROR.
      Власник KeyedAtoms/N зберігає їх протягом цього синхронного виклику. }
    function EvaluateKeyedNode(N:TSourceNode;
      const KeyedAtoms:TNativeKeyedAtoms):RawByteString;
    function EvaluateSource(const Source:RawByteString):RawByteString;
  end;
implementation
constructor TNativeEvaluator.Create(const Root:RawByteString;
  Cells:SizeInt; Steps:SizeInt; Depth:SizeInt);
begin
  inherited Create;
  if (Cells<1) or (Cells>65536) or (Steps<1) or (Steps>1048576) or
     (Depth<1) or (Depth>128) then
    raise ENativeEvalError.CreateAt('invalid native resource limits',1,1,1);
  FMaxCells:=Cells; FMaxSteps:=Steps; FMaxDepth:=Depth;
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
function TNativeEvaluator.QuoteExact(N:TSourceNode; Depth:SizeInt):SizeInt;
var I, Item:SizeInt; Key:TDomainKey;
begin
  Step(N,Depth);
  if N.Kind=skList then begin
    Result:=0; { D3:000, порожня структура, не D1:0 }
    for I:=High(N.Children) downto 0 do begin
      Item:=QuoteExact(N.Children[I],Depth+1);
      Result:=PairCell(Item,Result,N);
    end;
    Exit;
  end;
  if N.Kind<>skAtom then Fail(N,'фізична D3:001 цитата потребує атом або список');
  Key:=KeyForNode(N,'немає pinned координати цитованого слова');
  if (Key.Width<1) or (Key.Width>9) or (Key.Width=2) then
    Fail(N,'непідтримана ширина фізичної цитати');
  Result:=DomainCell(Key,N); { ті самі width + bits, ніякого eval }
end;

function TNativeEvaluator.Eval(N:TSourceNode; Depth:SizeInt):SizeInt;
var Key:TDomainKey; A,B,ArgCount,I:SizeInt; Clause:TSourceNode;
begin
  Step(N,Depth);
  if N.Kind=skAtom then begin
    Key:=KeyForNode(N,'unknown native binding');
    if Key.Width<>1 then Fail(N,'unsupported native value domain');
    Exit(DomainCell(Key,N));
  end;
  if N.Kind<>skList then Fail(N,'unsupported native string value');
  if Length(N.Children)=0 then Exit(0);
  if N.Children[0].Kind<>skAtom then Fail(N.Children[0],
    'unsupported computed native head');
  Key:=KeyForNode(N.Children[0],'unknown native call head');
  { Поверхня вже стала точним ключем; подальший dispatch лише D3+біти.
    Членство у таблиці НЕ дозволяє довільний виклик. Решта BLOCKED. }
  if Key.Width<>3 then Fail(N.Children[0],'unsupported native callable domain');
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
      { Contract 12 K12.3: D3:101 EQ приймає тільки допущені
        атоми. Цей перший виконуваний зріз звужено до exact D1;
        ані D3:000, ані pair не стають булевим значенням або атомом.
        Операнди вже обчислено одним чинним D3 evaluator. }
      B:=Eval(N.Children[2],Depth+1);
      if (FCells[A].Kind<>ncDomain) or (FCells[A].Key.Width<>1) then
        Fail(N.Children[1],'D3:101 очікує атом D1 зліва');
      if (FCells[B].Kind<>ncDomain) or (FCells[B].Key.Width<>1) then
        Fail(N.Children[2],'D3:101 очікує атом D1 справа');
      { KeyBits перевіряє точний width та біти pinned координати.
        Не порівнюємо адреси комірок, десяткові/host числа чи spelling. }
      Key:=ExactKey('0');
      if KeyBits(FCells[A].Key)=KeyBits(FCells[B].Key) then
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
    Result:=Render(H,0);
  finally
    Reset;
  end;
end;
function TNativeEvaluator.EvaluateKeyedNode(N:TSourceNode;
  const KeyedAtoms:TNativeKeyedAtoms):RawByteString;
var I:SizeInt; Bits:RawByteString;
begin
  if FKeyedMode then
    raise ENativeEvalError.CreateAt(#$D0#$B2#$D0#$BA#$D0#$BB#$D0#$B0#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$65#$78#$61#$63#$74#$20#$D1#$80#$D0#$B5#$D0#$B6#$D0#$B8#$D0#$BC#$20#$D0#$B7#$D0#$B0#$D0#$B1#$D0#$BE#$D1#$80#$D0#$BE#$D0#$BD#$D0#$B5#$D0#$BD#$D0#$BE,1,1,1);
  if N=nil then
    raise ENativeEvalError.CreateAt(#$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B8,1,1,1);
  if Length(KeyedAtoms)>65536 then
    raise ENativeEvalError.CreateAt(#$D0#$BD#$D0#$B0#$D0#$B4#$D1#$82#$D0#$BE#$20#$D0#$B1#$D0#$B0#$D0#$B3#$D0#$B0#$D1#$82#$D0#$BE#$20#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D0#$B0#$D0#$BD#$D0#$B8#$D1#$85#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D1#$85#$20#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC#$D1#$96#$D0#$B2,1,1,1);
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
  try
    SortKeyedAtoms;
    for I:=1 to High(FKeyedAtoms) do
      if FKeyedAtoms[I-1].Node=FKeyedAtoms[I].Node then
        raise ENativeEvalError.CreateAt(
          #$D0#$BF#$D0#$BE#$D0#$B2#$D1#$82#$D0#$BE#$D1#$80#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D0#$B0#$D0#$B4#$D1#$80#$D0#$B5#$D1#$81#$D0#$B0#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0,1,1,1);
    FKeyedMode:=True;
    Result:=EvaluateNode(N);
  finally
    FKeyedMode:=False;
    SetLength(FKeyedAtoms,0);
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
