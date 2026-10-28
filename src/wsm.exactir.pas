{ G6.4. Структурне двійково-первинне IR до lowering.
  Точні доменні координати беруться ЛИШЕ із чинного pinned binder.
  Фізичні позиції — з T5M/D2 reader. Жодних нових законів,
  семантичних викликів, оптимізацій чи машинного коду тут немає. }
unit wsm.exactir;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind;

const MaxExactIRNodes = 100000;
      MaxExactIRDepth = 256;

type
  EExactIRError = class(Exception);
  TExactIRKind = (ikList, ikPair, ikIdentity, ikEmpty);
  TExactIRNode = record
    Kind: TExactIRKind;
    RootIndex, ParentIndex, ChildIndex, Depth: SizeInt;
    WordIndex: SizeInt;
    Physical: TPhysicalWordSpan;
    HasKey: Boolean;   { у структурних маркерів немає callable domain key }
    Key: TDomainKey;   { чинний pinned exact(domain width,bits) }
  end;
  TExactIRNodes = array of TExactIRNode;
  TExactIR = record
    Nodes: TExactIRNodes;       { preorder; індекси з нуля }
    Roots: array of SizeInt;   { індекси коренів у Nodes }
    BoundLeaves: SizeInt;
  end;

procedure BuildExactIR(const Physical: RawByteString;
  const Tables: TDomainSet; out ProgramIR: TExactIR);

implementation

type
  TPending = record
    Node: TD2Node;
    RootIndex, ParentIndex, ChildIndex, Depth: SizeInt;
  end;

procedure BuildExactIR(const Physical: RawByteString;
  const Tables: TDomainSet; out ProgramIR: TExactIR);
var
  Doc: TD2Document;
  Spans: TPhysicalWordSpans;
  Bound: TBinaryWords;
  Temp: TExactIR;
  Stack: array of TPending;
  StackCount, StackCapacity, Count, Capacity, Leaf, I, J, N: SizeInt;
  Work: TPending;
  Entry: TExactIRNode;

  procedure Push(Node: TD2Node; Root, Parent, Child, Level: SizeInt);
  begin
    if Node = nil then raise EExactIRError.Create('відсутній структурний вузол');
    if Level > MaxExactIRDepth then
      raise EExactIRError.Create('перевищено глибину двійкового IR');
    if StackCount >= MaxExactIRNodes then
      raise EExactIRError.Create('перевищено межу стека двійкового IR');
    if StackCount = StackCapacity then begin
      if StackCapacity = 0 then StackCapacity := 16
      else StackCapacity := StackCapacity * 2;
      if StackCapacity > MaxExactIRNodes then StackCapacity := MaxExactIRNodes;
      SetLength(Stack, StackCapacity);
    end;
    Stack[StackCount].Node := Node;
    Stack[StackCount].RootIndex := Root;
    Stack[StackCount].ParentIndex := Parent;
    Stack[StackCount].ChildIndex := Child;
    Stack[StackCount].Depth := Level;
    Inc(StackCount);
  end;

  procedure Append(const Item: TExactIRNode);
  begin
    if Count >= MaxExactIRNodes then
      raise EExactIRError.Create('перевищено межу вузлів двійкового IR');
    if Count = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity * 2;
      if Capacity > MaxExactIRNodes then Capacity := MaxExactIRNodes;
      SetLength(Temp.Nodes, Capacity);
    end;
    Temp.Nodes[Count] := Item;
    Inc(Count);
  end;

begin
  { За будь-якої відмови публічний результат порожній. }
  SetLength(ProgramIR.Nodes, 0);
  SetLength(ProgramIR.Roots, 0);
  ProgramIR.BoundLeaves := 0;
  Doc := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    { Перевіряє повні pinned таблиці і кожну точну ідентичність.
      Ніяких назв як первинної семантичної адреси. }
    BindD2Binary(Doc, Tables, Bound);
    if Length(Doc.Roots) > MaxExactIRNodes then
      raise EExactIRError.Create('забагато кореневих форм');
    SetLength(Temp.Roots, Length(Doc.Roots));
    SetLength(Temp.Nodes, 0);
    Temp.BoundLeaves := 0;
    StackCount := 0; StackCapacity := 0;
    Count := 0; Capacity := 0; Leaf := 0;
    for I := High(Doc.Roots) downto 0 do
      Push(Doc.Roots[I], I, -1, I, 0);
    while StackCount > 0 do begin
      Dec(StackCount);
      Work := Stack[StackCount];
      if Work.Node = nil then
        raise EExactIRError.Create('відсутній вузол D2');
      FillChar(Entry, SizeOf(Entry), 0);
      Entry.RootIndex := Work.RootIndex;
      Entry.ParentIndex := Work.ParentIndex;
      Entry.ChildIndex := Work.ChildIndex;
      Entry.Depth := Work.Depth;
      Entry.WordIndex := Work.Node.WordIndex;
      Entry.Physical := LocatePhysicalWord(Physical, Spans, Entry.WordIndex);
      if Entry.Physical.IsEOF then
        raise EExactIRError.Create('вузол IR не може мати адресу EOF');
      Entry.HasKey := False;
      case Work.Node.Kind of
        dkList: Entry.Kind := ikList;
        dkPair: begin
          Entry.Kind := ikPair;
          if Length(Work.Node.Children) <> 2 then
            raise EExactIRError.Create('крапкова пара без двох елементів');
        end;
        dkIdentity, dkEmpty: begin
          if Work.Node.Kind = dkEmpty then Entry.Kind := ikEmpty
          else Entry.Kind := ikIdentity;
          if Length(Work.Node.Children) <> 0 then
            raise EExactIRError.Create('атом IR містить нащадків');
          if Leaf >= Length(Bound) then
            raise EExactIRError.Create('загублено зв’язану доменну координату');
          if (Bound[Leaf].WordIndex <> Entry.WordIndex) or
             (Bound[Leaf].RootIndex <> Entry.RootIndex) or
             (Bound[Leaf].IsEmpty <> (Entry.Kind = ikEmpty)) or
             (KeyBits(Bound[Leaf].Key) <> Work.Node.Bits) or
             (Bound[Leaf].Key.Width <> Work.Node.Width) then
            raise EExactIRError.Create('неузгоджено вузол і pinned координату');
          Entry.HasKey := True;
          Entry.Key := Bound[Leaf].Key;
          Inc(Leaf);
        end;
        else raise EExactIRError.Create('невідомий вузол D2');
      end;
      N := Count;
      Append(Entry);
      if Work.ParentIndex = -1 then
        Temp.Roots[Work.RootIndex] := N;
      if Work.Node.Kind in [dkList, dkPair] then
        for J := High(Work.Node.Children) downto 0 do
          Push(Work.Node.Children[J], Work.RootIndex, N, J,
            Work.Depth + 1);
    end;
    if Leaf <> Length(Bound) then
      raise EExactIRError.Create('доменні слова залишилися без вузлів IR');
    SetLength(Temp.Nodes, Count);
    Temp.BoundLeaves := Leaf;
    ProgramIR := Temp;
  finally
    Doc.Free;
  end;
end;
end.
