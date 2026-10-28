{ G6.7: локальний in-memory gate вже побудованого ExactIR перед lowering.
  Не читає/пише EIR1, не визначає мовних законів і не перевиконує SENS. }
unit wsm.exactirguard;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.exactir, wsm.domain;

type
  EExactIRGuardError = class(Exception);
  TExactIRGuardStats = record
    Nodes, Roots, BoundLeaves, StructuralNodes, MaxDepth: SizeInt;
  end;

procedure VerifyExactIRStructure(const IR: TExactIR;
  out Stats: TExactIRGuardStats);

implementation

procedure Reject(const MessageText: String);
begin
  raise EExactIRGuardError.Create(MessageText);
end;

procedure VerifyExactIRStructure(const IR: TExactIR;
  out Stats: TExactIRGuardStats);
var
  Candidate: TExactIRGuardStats;
  ChildCounts: array of SizeInt;
  ActiveAncestors: array of SizeInt; { відкриті вузли DFS preorder }
  ActiveCount: SizeInt;
  I, Parent, RootNo: SizeInt;
  N: TExactIRNode;
  Bits: RawByteString;
begin
  { Статистика з'являється зовні лише після повного успіху. }
  FillChar(Stats, SizeOf(Stats), 0);
  FillChar(Candidate, SizeOf(Candidate), 0);
  if (Length(IR.Nodes) < 1) or
     (Length(IR.Nodes) > MaxExactIRNodes) or
     (Length(IR.Roots) < 1) or
     (Length(IR.Roots) > Length(IR.Nodes)) then
    Reject('некоректна кількість вузлів або коренів IR');
  SetLength(ChildCounts, Length(IR.Nodes));
  SetLength(ActiveAncestors, Length(IR.Nodes));
  ActiveCount := 0;
  for I := 0 to High(ChildCounts) do ChildCounts[I] := 0;
  RootNo := -1;
  for I := 0 to High(IR.Nodes) do begin
    N := IR.Nodes[I];
    if N.ParentIndex < -1 then
      Reject('від’ємний індекс батька IR');
    if N.ParentIndex = -1 then begin
      { Нова верхня форма закриває всі попередні піддерева. }
      ActiveCount := 0;
      Inc(RootNo);
      if (RootNo >= Length(IR.Roots)) or
         (IR.Roots[RootNo] <> I) or
         (N.RootIndex <> RootNo) or
         (N.ChildIndex <> RootNo) or
         (N.Depth <> 0) then
        Reject('порушено послідовність кореневих форм IR');
    end else begin
      Parent := N.ParentIndex;
      if (Parent >= I) or (Parent < 0) then
        Reject('неприпустимий preorder індекс батька');
      { ParentIndex/Depth/ChildIndex самі по собі недостатні: DFS
        не має права повертатися до предка після переходу до його
        сусіда. Шукати батька лише у ще активному стеку. }
      while (ActiveCount > 0) and
            (ActiveAncestors[ActiveCount-1] <> Parent) do
        Dec(ActiveCount);
      if ActiveCount = 0 then
        Reject('розірваний preorder: повернення до закритого піддерева');
      if not (IR.Nodes[Parent].Kind in [ikList,ikPair]) then
        Reject('листок IR містить дочірній вузол');
      if (N.RootIndex <> IR.Nodes[Parent].RootIndex) or
         (N.Depth <> IR.Nodes[Parent].Depth + 1) or
         (N.Depth > MaxExactIRDepth) then
        Reject('порушено глибину або походження кореня IR');
      if N.ChildIndex <> ChildCounts[Parent] then
        Reject('порушено порядок дочірніх вузлів IR');
      Inc(ChildCounts[Parent]);
    end;

    if N.WordIndex < 1 then
      Reject('неприпустимий індекс фізичного слова IR');
    if (N.Physical.WordIndex <> N.WordIndex) or
       N.Physical.IsEOF or
       (N.Physical.TritStart < 0) or
       (N.Physical.TritEnd <= N.Physical.TritStart) or
       (N.Physical.ByteStart < 0) or
       (N.Physical.ByteEnd <= N.Physical.ByteStart) or
       { Фізична адреса в IR — 0-based напіввідкрита; T5M
         пакує рівно 5 тритів у байт. Без оригінальних байтів
         можна підтвердити цю формулу, але не декодувати payload.
         Ceil без додавання 4 до SizeInt, захист від overflow. }
       (N.Physical.ByteStart <> N.Physical.TritStart div 5) or
       (N.Physical.ByteEnd <> ((N.Physical.TritEnd-1) div 5)+1) then
      Reject('пошкоджено фізичний трит-/байтовий інтервал IR');
    { Для ikPair це фізична АДРЕСА ОПОРНОГО D2, не власний токен пари. }
    case N.Kind of
      ikList, ikPair: begin
        Inc(Candidate.StructuralNodes);
        if N.HasKey or (N.Key.Width <> 0) or (N.Key.Bits <> 0) then
          Reject('структурний D2 вузол отримав доменну координату');
        if (N.Physical.TritEnd - N.Physical.TritStart <> 2) then
          Reject('структурний вузол не посилається на D2 ширини 2');
      end;
      ikIdentity, ikEmpty: begin
        if not N.HasKey then
          Reject('доменний листок без точної координати');
        if (N.Key.Width < 1) or (N.Key.Width > 9) or
           (N.Key.Width = 2) then
          Reject('неприпустима ширина доменного ключа');
        try
          Bits := KeyBits(N.Key);
        except
          on E: EDomainError do
            Reject('пошкоджені точні двійкові біти ключа');
        end;
        if Length(Bits) <> N.Physical.TritEnd - N.Physical.TritStart then
          Reject('точна ширина не відповідає фізичним тритам');
        if (N.Kind = ikEmpty) <> (Bits = '000') then
          Reject('підміна D3:000 і фізичного доменного листка');
        Inc(Candidate.BoundLeaves);
      end;
      else Reject('незареєстрований тип структурного вузла IR');
    end;
    if N.Depth > Candidate.MaxDepth then Candidate.MaxDepth := N.Depth;
    if N.Kind in [ikList,ikPair] then begin
      ActiveAncestors[ActiveCount] := I;
      Inc(ActiveCount);
    end;
  end;
  if RootNo + 1 <> Length(IR.Roots) then
    Reject('зайві або пропущені корені IR');
  for I := 0 to High(IR.Nodes) do begin
    if (IR.Nodes[I].Kind in [ikIdentity,ikEmpty]) and
       (ChildCounts[I] <> 0) then
      Reject('доменний листок має нащадків');
    if (IR.Nodes[I].Kind = ikPair) and (ChildCounts[I] <> 2) then
      Reject('похідна крапкова пара не має рівно двох частин');
  end;
  if IR.BoundLeaves <> Candidate.BoundLeaves then
    Reject('лічильник зв’язаних листків IR не збігається');
  Candidate.Nodes := Length(IR.Nodes);
  Candidate.Roots := Length(IR.Roots);
  Stats := Candidate;
end;
end.
