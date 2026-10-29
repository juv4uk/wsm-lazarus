{ G2.9: фізичне дерево двійкової SENS для headless/Lazarus UI.
  Вхід — тільки T5M; фізика і D2 розбираються чинними модулями.
  Не встановлює допустимість виклику або значення функції. }
unit wsm.binarytree;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind;
type
  EBinaryTreeError = class(Exception);
  TBinaryTreeEntry = record
    Kind: TD2Kind;
    RootIndex, ParentIndex, ChildIndex, Depth: SizeInt;
    AnchorWordIndex: SizeInt;   { для похідної пари це D2 OPEN, не власне слово }
    HasPhysicalWord: Boolean;  { хибно для похідної крапкової пари }
    Physical: TPhysicalWordSpan; { лише якщо HasPhysicalWord }
    Key: TDomainKey;            { лише dkIdentity або dkEmpty }
    Ukrainian: RawByteString;   { лише проєкція «ук» із pinned таблиці }
  end;
  TBinaryTreeEntries = array of TBinaryTreeEntry;

procedure ReadBinaryTree(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries);
{ Лише явно обраний D10: фізичний wide-reader + pinned binder.
  Це не надає викличності, не виводить D12+ із ширини. }
procedure ReadBinaryTreeD10(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries);
function BinaryTreeCaption(const Entry: TBinaryTreeEntry): RawByteString;

implementation
const MaxTreeNodes = 100000;

procedure ReadBinaryTreeBounded(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries;
  AllowD10: Boolean);
var
  Document: TD2Document;
  Spans: TPhysicalWordSpans;
  Bound: TBinaryWords;
  BoundByWord: array of SizeInt;
  Used, Capacity, I: SizeInt;
  Staged: TBinaryTreeEntries; { приватний масив до завершення всіх перевірок }

  { Вхідний ParseD2Words обмежує синтаксичну вкладеність 256.
    Довгий коректний крапковий список породжує тисячі ПОХІДНИХ
    dkPair при вкладеності фізичних дужок 1. Не плутаємо ці глибини.
    Плоский preorder будуємо на явному стеку, без рекурсії хоста. }
  procedure Visit(const StartNode: TD2Node; Root, Parent,
    Child, Depth: SizeInt);
  type
    TPendingNode = record
      Node: TD2Node;  { позичений вузол: власник Document }
      Root, Parent, Child, Depth: SizeInt;
    end;
  var
    Stack: array of TPendingNode;
    StackUsed, StackCapacity: SizeInt;
    Pending: TPendingNode;
    Node: TD2Node;
    N, J, BoundIndex: SizeInt;
    Item: TBinaryTreeEntry;

    procedure Push(NextNode: TD2Node; NextRoot, NextParent,
      NextChild, NextDepth: SizeInt);
    begin
      if NextNode = nil then
        raise EBinaryTreeError.Create('відсутній вузол дерева');
      if StackUsed >= MaxTreeNodes then
        raise EBinaryTreeError.Create('перевищено межу вузлів дерева');
      if StackUsed = StackCapacity then begin
        if StackCapacity = 0 then StackCapacity := 32
        else StackCapacity := StackCapacity * 2;
        if StackCapacity > MaxTreeNodes then StackCapacity := MaxTreeNodes;
        SetLength(Stack, StackCapacity);
      end;
      Stack[StackUsed].Node := NextNode;
      Stack[StackUsed].Root := NextRoot;
      Stack[StackUsed].Parent := NextParent;
      Stack[StackUsed].Child := NextChild;
      Stack[StackUsed].Depth := NextDepth;
      Inc(StackUsed);
    end;

  begin
    StackUsed := 0;
    StackCapacity := 0;
    Push(StartNode, Root, Parent, Child, Depth);
    while StackUsed > 0 do begin
      Dec(StackUsed);
      Pending := Stack[StackUsed];
      Stack[StackUsed].Node := nil;
      Node := Pending.Node;
      { Ліміт вузлів, а не похідної глибини. Власне D2 вже перевірено. }
      if Used >= MaxTreeNodes then
        raise EBinaryTreeError.Create('перевищено межу вузлів дерева');
      if (Node.WordIndex < 1) or (Node.WordIndex > Length(Spans)) then
        raise EBinaryTreeError.Create('вузол поза фізичним потоком');
      if Used = Capacity then begin
        if Capacity = 0 then Capacity := 32 else Capacity := Capacity * 2;
        if Capacity > MaxTreeNodes then Capacity := MaxTreeNodes;
        SetLength(Staged, Capacity);
      end;
      N := Used;
      Inc(Used);
      Item.Kind := Node.Kind;
      Item.RootIndex := Pending.Root;
      Item.ParentIndex := Pending.Parent;
      Item.ChildIndex := Pending.Child;
      Item.Depth := Pending.Depth;
      Item.AnchorWordIndex := Node.WordIndex;
      Item.HasPhysicalWord := Node.Kind <> dkPair;
      Item.Key.Width := 0;
      Item.Key.Bits := 0;
      Item.Ukrainian := '';
      Item.Physical.WordIndex := 0;
      Item.Physical.TritStart := 0;
      Item.Physical.TritEnd := 0;
      Item.Physical.ByteStart := 0;
      Item.Physical.ByteEnd := 0;
      Item.Physical.IsEOF := False;
      if Item.HasPhysicalWord then begin
        Item.Physical := LocatePhysicalWord(Physical, Spans, Node.WordIndex);
        if Item.Physical.IsEOF then
          raise EBinaryTreeError.Create('вузол на адресі кінця файлу');
      end;
      case Node.Kind of
        dkIdentity, dkEmpty: begin
          if Length(Node.Children) <> 0 then
            raise EBinaryTreeError.Create('листок має дочірні вузли');
          BoundIndex := BoundByWord[Node.WordIndex];
          if (BoundIndex < 0) or (BoundIndex >= Length(Bound)) then
            raise EBinaryTreeError.Create('двійковий листок не має координати');
          Item.Key := Bound[BoundIndex].Key;
          Item.Ukrainian := Bound[BoundIndex].Ukrainian;
          if (Item.Key.Width <> Length(Node.Bits)) or
             (KeyBits(Item.Key) <> Node.Bits) or
             (Item.Physical.TritEnd-Item.Physical.TritStart <> Item.Key.Width) then
            raise EBinaryTreeError.Create('втрачено точну ширину або біти');
          if (Node.Kind = dkEmpty) <> (Node.Bits = '000') then
            raise EBinaryTreeError.Create('підміна порожньої структури D3');
        end;
        dkList, dkPair: begin
          if (Node.Kind = dkPair) and (Length(Node.Children) <> 2) then
            raise EBinaryTreeError.Create('крапкова пара без двох частин');
          if (Node.Kind = dkList) and
             (Item.Physical.TritEnd-Item.Physical.TritStart <> 2) then
            raise EBinaryTreeError.Create('D2 OPEN не має ширини два');
        end;
        else raise EBinaryTreeError.Create('невідомий тип вузла');
      end;
      Staged[N] := Item;
      { LIFO: додаємо дітей справа наліво, зберігаючи точний preorder. }
      for J := High(Node.Children) downto 0 do
        Push(Node.Children[J], Pending.Root, N, J, Pending.Depth + 1);
    end;
  end;

begin
  { OUT очищається до будь-якого читання: збій не повинен показувати
    часткові або старі вузли компілятору чи інспектору Lazarus. }
  SetLength(Entries, 0);
  SetLength(Staged, 0);
  if AllowD10 then
    Document := ReadD2WideWithPhysicalLocations(Physical, Spans)
  else
    Document := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    if AllowD10 then
      BindD2BinaryD10(Document, Tables, Bound)
    else
      BindD2Binary(Document, Tables, Bound);
    SetLength(BoundByWord, Length(Spans) + 1);
    for I := 0 to High(BoundByWord) do BoundByWord[I] := -1;
    for I := 0 to High(Bound) do begin
      if (Bound[I].WordIndex < 1) or
         (Bound[I].WordIndex > Length(Spans)) or
         (BoundByWord[Bound[I].WordIndex] >= 0) then
        raise EBinaryTreeError.Create('неоднозначний індекс двійкового слова');
      BoundByWord[Bound[I].WordIndex] := I;
    end;
    Used := 0;
    Capacity := 0;
    for I := 0 to High(Document.Roots) do
      Visit(Document.Roots[I], I, -1, -1, 0);
    { Єдине місце публікації дерева — після всього обходу. }
    SetLength(Staged, Used);
    Entries := Staged;
  finally
    Document.Free;
  end;
end;

{ Фізичний T5M — borrowed bytes. Entries — керований масив, який
  стає видимим лише після повного D2 + pinned exact-domain допуску.
  Обидва публічні API користуються одним preorder побудовником. }
procedure ReadBinaryTree(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries);
begin
  ReadBinaryTreeBounded(Physical, Tables, Entries, False);
end;

procedure ReadBinaryTreeD10(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries);
begin
  ReadBinaryTreeBounded(Physical, Tables, Entries, True);
end;

function BinaryTreeCaption(const Entry: TBinaryTreeEntry): RawByteString;
begin
  case Entry.Kind of
    dkList: Result := 'список D2';
    dkPair: Result := 'похідна крапкова пара';
    dkEmpty: Result := 'порожня структура D3:000';
    dkIdentity: Result := 'домен ' + IntToStr(Entry.Key.Width) +
      ' біти ' + KeyBits(Entry.Key);
    else raise EBinaryTreeError.Create('невідомий тип вузла');
  end;
  if (Entry.Kind in [dkIdentity, dkEmpty]) and
     (Entry.Ukrainian <> '') then
    Result := Result + ' — ' + Entry.Ukrainian;
end;
end.
