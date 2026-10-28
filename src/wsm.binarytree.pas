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
function BinaryTreeCaption(const Entry: TBinaryTreeEntry): RawByteString;

implementation
const MaxTreeNodes = 100000;

procedure ReadBinaryTree(const Physical: RawByteString;
  const Tables: TDomainSet; out Entries: TBinaryTreeEntries);
var
  Document: TD2Document;
  Spans: TPhysicalWordSpans;
  Bound: TBinaryWords;
  BoundByWord: array of SizeInt;
  Used, Capacity, I: SizeInt;

  procedure Visit(const Node: TD2Node; Root, Parent,
    Child, Depth: SizeInt);
  var N, J, BoundIndex: SizeInt; Item: TBinaryTreeEntry;
  begin
    if Node = nil then raise EBinaryTreeError.Create('відсутній вузол дерева');
    if Depth > MaxD2SyntaxDepth then
      raise EBinaryTreeError.Create('перевищено глибину дерева D2');
    if Used >= MaxTreeNodes then
      raise EBinaryTreeError.Create('перевищено межу вузлів дерева');
    if (Node.WordIndex < 1) or (Node.WordIndex > Length(Spans)) then
      raise EBinaryTreeError.Create('вузол поза фізичним потоком');
    if Used = Capacity then begin
      if Capacity = 0 then Capacity := 32 else Capacity := Capacity * 2;
      if Capacity > MaxTreeNodes then Capacity := MaxTreeNodes;
      SetLength(Entries, Capacity);
    end;
    N := Used;
    Inc(Used);
    Item.Kind := Node.Kind;
    Item.RootIndex := Root;
    Item.ParentIndex := Parent;
    Item.ChildIndex := Child;
    Item.Depth := Depth;
    Item.AnchorWordIndex := Node.WordIndex;
    Item.HasPhysicalWord := Node.Kind <> dkPair;
    Item.Key.Width := 0;
    Item.Key.Bits := 0;
    Item.Ukrainian := '';
    { Похідна пара не має власного слова в T5M. Жодної фіктивної
      фізичної адреси для неї не присвоюємо. }
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
    Entries[N] := Item;
    for J := 0 to High(Node.Children) do
      Visit(Node.Children[J], Root, N, J, Depth + 1);
  end;

begin
  SetLength(Entries, 0);
  Document := ReadD2WithPhysicalLocations(Physical, Spans);
  try
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
    SetLength(Entries, Used);
  finally
    Document.Free;
  end;
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
