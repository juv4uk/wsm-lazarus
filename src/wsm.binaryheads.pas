{ G2.11. Механічний індекс перших дітей фізичних D2-списків.
  Синтаксична голова НЕ означає викличність: списки можуть бути даними.
  Двійкові width+bits первинні; українська проєкція не використовується. }
unit wsm.binaryheads;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.d2source, wsm.domain, wsm.physloc, wsm.binarytree;
type
  EBinaryHeadsError = class(Exception);
  TBinaryHeadKind = (hkNoHead, hkExactHead, hkStructuralHead);
  TBinaryHead = record
    ListIndex: SizeInt;       { індекс D2-списку у плоскому preorder }
    RootIndex: SizeInt;       { індекс верхньої форми }
    HeadIndex: SizeInt;       { -1 для порожнього списку }
    Kind: TBinaryHeadKind;    { лише синтаксичний стан, НЕ callability }
    Key: TDomainKey;         { лише hkExactHead; 0-width в інших станах }
    WordIndex: SizeInt;      { лише hkExactHead, фізичний 1-based індекс }
    Physical: TPhysicalWordSpan; { лише hkExactHead; точні три-/байти }
  end;
  TBinaryHeads = array of TBinaryHead;
procedure CollectBinaryHeads(const Entries: TBinaryTreeEntries;
  out Heads: TBinaryHeads);
implementation
procedure CollectBinaryHeads(const Entries: TBinaryTreeEntries;
  out Heads: TBinaryHeads);
var
  NextChild: array of SizeInt;
  ActiveAncestors: array of SizeInt; { відкриті списки та пари preorder }
  ActiveCount: SizeInt;
  Staged: TBinaryHeads;
  I, P, Root, Count, Used, H: SizeInt;
  Item: TBinaryTreeEntry;
  Candidate: TBinaryHead;
begin
  SetLength(Heads, 0);
  Count := Length(Entries);
  if Count = 0 then raise EBinaryHeadsError.Create('відсутнє дерево D2');
  SetLength(NextChild, Count);
  SetLength(ActiveAncestors, Count);
  ActiveCount := 0;
  Used := 0;
  Root := -1;
  { ПОВНА перевірка структури перед публікацією — ні часткових голів. }
  for I := 0 to Count-1 do begin
    Item := Entries[I];
    P := Item.ParentIndex;
    if P = -1 then begin
      { Кожна нова верхня форма закриває попередній шлях. }
      ActiveCount := 0;
      Inc(Root);
      if (Item.RootIndex <> Root) or (Item.Depth <> 0) or
         (Item.ChildIndex <> -1) then
        raise EBinaryHeadsError.Create('невірна верхня форма');
    end else begin
      if (P < 0) or (P >= I) then
        raise EBinaryHeadsError.Create('невірний батьківський індекс');
      { Правильний preorder — суцільний обхід піддерева.
        Якщо предок уже закритий переходом до сусіднього піддерева,
        повертатися до нього заборонено, навіть якщо локальні
        ParentIndex/ChildIndex/Depth залишаються узгодженими. }
      while (ActiveCount > 0) and
            (ActiveAncestors[ActiveCount-1] <> P) do
        Dec(ActiveCount);
      if ActiveCount = 0 then
        raise EBinaryHeadsError.Create('розірваний preorder: закритий предок');
      if not (Entries[P].Kind in [dkList, dkPair]) then
        raise EBinaryHeadsError.Create('листок не може мати дітей');
      if (Item.RootIndex <> Entries[P].RootIndex) or
         (Item.Depth <> Entries[P].Depth+1) or
         (Item.ChildIndex <> NextChild[P]) then
        raise EBinaryHeadsError.Create('невірний порядковий номер дитини');
      if (Item.ChildIndex = 0) and (I <> P+1) then
        raise EBinaryHeadsError.Create('перша дитина не йде за батьком');
      Inc(NextChild[P]);
      if (Entries[P].Kind = dkPair) and (NextChild[P] > 2) then
        raise EBinaryHeadsError.Create('крапкова пара має понад дві частини');
    end;
    if Item.Kind in [dkIdentity, dkEmpty] then begin
      if not Item.HasPhysicalWord or (Item.Key.Width < 1) or
         (Item.Physical.IsEOF) or (Item.AnchorWordIndex < 1) or
         (Item.Physical.WordIndex <> Item.AnchorWordIndex) or
         (Item.Physical.TritEnd - Item.Physical.TritStart <> Item.Key.Width) then
        raise EBinaryHeadsError.Create('листок утратив фізичну координату');
    end else if (Item.Kind=dkPair) then begin
      if Item.HasPhysicalWord or (Item.Key.Width <> 0) then
        raise EBinaryHeadsError.Create('похідна пара має фіктивну координату');
    end else if (Item.Kind=dkList) then begin
      if not Item.HasPhysicalWord or (Item.Key.Width <> 0) or
         (Item.Physical.WordIndex <> Item.AnchorWordIndex) or
         (Item.Physical.TritEnd-Item.Physical.TritStart <> 2) then
        raise EBinaryHeadsError.Create('список утратив D2-маркер');
      Inc(Used);
    end else
      raise EBinaryHeadsError.Create('невідомий вид D2');
    if Item.Kind in [dkList, dkPair] then begin
      ActiveAncestors[ActiveCount] := I;
      Inc(ActiveCount);
    end;
  end;
  for I := 0 to Count-1 do
    if Entries[I].Kind in [dkList, dkPair] then begin
      if (Entries[I].Kind=dkPair) and (NextChild[I]<>2) then
        raise EBinaryHeadsError.Create('неповна крапкова пара');
      if (NextChild[I]>0) and
         ((I+1>=Count) or (Entries[I+1].ParentIndex<>I) or
          (Entries[I+1].ChildIndex<>0)) then
        raise EBinaryHeadsError.Create('втрачена перша дитина контейнера');
    end;
  SetLength(Staged, Used);
  H := 0;
  for I := 0 to Count-1 do begin
    if Entries[I].Kind <> dkList then Continue;
    Candidate.ListIndex := I;
    Candidate.RootIndex := Entries[I].RootIndex;
    Candidate.HeadIndex := -1;
    Candidate.Kind := hkNoHead;
    Candidate.Key.Width := 0;
    Candidate.Key.Bits := 0;
    Candidate.WordIndex := 0;
    Candidate.Physical.WordIndex := 0;
    Candidate.Physical.TritStart := 0;
    Candidate.Physical.TritEnd := 0;
    Candidate.Physical.ByteStart := 0;
    Candidate.Physical.ByteEnd := 0;
    Candidate.Physical.IsEOF := False;
    if NextChild[I] > 0 then begin
      Candidate.HeadIndex := I + 1;
      if Entries[I+1].Kind = dkIdentity then begin
        Candidate.Kind := hkExactHead;
        Candidate.Key := Entries[I+1].Key;
        Candidate.WordIndex := Entries[I+1].AnchorWordIndex;
        Candidate.Physical := Entries[I+1].Physical;
      end else
        Candidate.Kind := hkStructuralHead;
    end;
    Staged[H] := Candidate;
    Inc(H);
  end;
  Heads := Staged;
end;
end.
