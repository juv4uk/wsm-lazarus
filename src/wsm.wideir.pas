{ Структурне широке IR: фізичні точні слова, а не новий закон SENS.
  1..9: pinned-домени (крім D2-маркерів); 10..192: лише непрозорі
  бінарні дані. Зокрема W12 саме по собі не допускає числа. }
unit wsm.wideir;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind;
const MaxWideIRNodes=8192;
type
  EWideIRError=class(Exception);
  TWideIRKind=(wkList,wkPair,wkAtom,wkEmpty);
  TWideIRNode=record
    Kind: TWideIRKind;
    RootIndex,ParentIndex,ChildIndex,Depth,WordIndex:SizeInt;
    Physical:TPhysicalWordSpan;
    OwnWord:Boolean; { Похідна пара не володіє окремим T5M словом. }
    Width:SizeInt;
    Bits:RawByteString; { Побітова тотожність, жодного Int64/float. }
    HasPinnedKey:Boolean; { Лише перевірені D1/D3..D9. }
    NarrowKey:TDomainKey;
  end;
  TWideIRNodes=array of TWideIRNode;
  TWideIR=record
    Nodes:TWideIRNodes;
    Roots:array of SizeInt;
    PhysicalLeaves,OpaqueLeaves:SizeInt;
  end;
procedure BuildWideIR(const Physical:RawByteString;
  const Tables:TDomainSet; out ResultIR:TWideIR);
implementation
type
  TPending=record
    Node:TD2Node;
    Root,Parent,Child,Level:SizeInt;
  end;

procedure BuildWideIR(const Physical:RawByteString;
  const Tables:TDomainSet; out ResultIR:TWideIR);
var
  Doc:TD2Document;
  Words:TExactWords;
  Spans:TPhysicalWordSpans;
  Staged:TWideIR;
  Stack:array of TPending;
  Count,StackCount,RootsCount,I,J,N,W:SizeInt;
  Pending:TPending;
  Item:TWideIRNode;
  K:TDomainKey;
  Row:TDomainRow;

  procedure Push(C:TD2Node; Root,Parent,Child,Level:SizeInt);
  begin
    if C=nil then raise EWideIRError.Create('Відсутній вузол фізичного D2');
    if Level>MaxD2SyntaxDepth then
      raise EWideIRError.Create('Перевищено максимальну глибину структури');
    if StackCount>=MaxWideIRNodes then
      raise EWideIRError.Create('Перевищено межу вузлів IR');
    if Length(Stack)=StackCount then
      SetLength(Stack,StackCount+32);
    Stack[StackCount].Node:=C;
    Stack[StackCount].Root:=Root;
    Stack[StackCount].Parent:=Parent;
    Stack[StackCount].Child:=Child;
    Stack[StackCount].Level:=Level;
    Inc(StackCount);
  end;

  procedure Add(const Candidate:TWideIRNode);
  begin
    if Count>=MaxWideIRNodes then
      raise EWideIRError.Create('Перевищено межу вузлів IR');
    if Length(Staged.Nodes)=Count then
      SetLength(Staged.Nodes,Count+32);
    Staged.Nodes[Count]:=Candidate;
    Inc(Count);
  end;
begin
  { Результат доступний лише після повного позитивного допуску. }
  SetLength(ResultIR.Nodes,0);
  SetLength(ResultIR.Roots,0);
  ResultIR.PhysicalLeaves:=0;
  ResultIR.OpaqueLeaves:=0;
  { Чинний T5M перевіряє байти/пакування; чинний D2 — структуру.
    Порядок і фізичні адреси встановлюються із тих самих слів. }
  DecodeT5MWithLocations(Physical,Words,Spans);
  Doc:=ParseD2WordsWide(Words);
  try
    for I:=1 to 9 do
      if Length(Tables[I]) <> (SizeInt(1) shl I) then
        raise EWideIRError.Create('Неповна pinned таблиця D'+IntToStr(I));
    RootsCount:=Length(Doc.Roots);
    if RootsCount>MaxWideIRNodes then
      raise EWideIRError.Create('Забагато кореневих форм');
    SetLength(Staged.Roots,RootsCount);
    SetLength(Staged.Nodes,0);
    Staged.PhysicalLeaves:=0;
    Staged.OpaqueLeaves:=0;
    Count:=0; StackCount:=0;
    for I:=High(Doc.Roots) downto 0 do
      Push(Doc.Roots[I],I,-1,I,0);
    while StackCount>0 do begin
      Dec(StackCount);
      Pending:=Stack[StackCount];
      FillChar(Item,SizeOf(Item),0);
      Item.RootIndex:=Pending.Root;
      Item.ParentIndex:=Pending.Parent;
      Item.ChildIndex:=Pending.Child;
      Item.Depth:=Pending.Level;
      Item.WordIndex:=Pending.Node.WordIndex;
      Item.Physical:=LocatePhysicalWord(Physical,Spans,Item.WordIndex);
      Item.OwnWord:=Pending.Node.Kind<>dkPair;
      if Item.Physical.IsEOF then
        raise EWideIRError.Create('Вузол не може мати позицію EOF');
      case Pending.Node.Kind of
        dkList: begin Item.Kind:=wkList; Item.Width:=0; end;
        dkPair: begin
          Item.Kind:=wkPair;
          if Length(Pending.Node.Children)<>2 then
            raise EWideIRError.Create('Крапкова пара не має двох частин');
        end;
        dkIdentity,dkEmpty: begin
          if Pending.Node.Kind=dkEmpty then Item.Kind:=wkEmpty
          else Item.Kind:=wkAtom;
          if Length(Pending.Node.Children)<>0 then
            raise EWideIRError.Create('Атом D2 має піддерево');
          Item.Bits:=Pending.Node.Bits;
          W:=Length(Item.Bits);
          Item.Width:=W;
          if (W<>Pending.Node.Width) or (W<1) or
             (W>MaxWideD2WordBits) or (W=2) or
             (Item.Physical.TritEnd-Item.Physical.TritStart<>W) then
            raise EWideIRError.Create('Втрачено точну фізичну ширину');
          for J:=1 to W do
            if not (Item.Bits[J] in ['0','1']) then
              raise EWideIRError.Create('Недвійкове фізичне слово');
          if (Item.Kind=wkEmpty) <> (Item.Bits='000') then
            raise EWideIRError.Create('Підміна D3:000');
          if W<=9 then begin
            K:=ExactKey(Item.Bits);
            if not DomainRowByKey(Tables[W],K,Row) then
              raise EWideIRError.Create('Не знайдено pinned координату');
            Item.HasPinnedKey:=True;
            Item.NarrowKey:=K;
          end else begin
            Item.HasPinnedKey:=False; { не виводити закон із W12! }
            Inc(Staged.OpaqueLeaves);
          end;
          Inc(Staged.PhysicalLeaves);
        end;
        else raise EWideIRError.Create('Невідомий вузол D2');
      end;
      N:=Count;
      Add(Item);
      if Item.ParentIndex=-1 then
        Staged.Roots[Item.RootIndex]:=N;
      if Pending.Node.Kind in [dkList,dkPair] then
        for J:=High(Pending.Node.Children) downto 0 do
          Push(Pending.Node.Children[J],Item.RootIndex,N,J,Item.Depth+1);
    end;
    SetLength(Staged.Nodes,Count);
    ResultIR:=Staged;
  finally
    Doc.Free;
  end;
end;
end.
