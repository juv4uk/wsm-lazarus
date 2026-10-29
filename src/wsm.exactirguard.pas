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
  LastRealWordIndex, LastRealTritEnd: SizeInt;
  SharedPairAnchor: Boolean;
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
  LastRealWordIndex := 0; LastRealTritEnd := 0;
  for I := 0 to High(IR.Nodes) do begin
    N := IR.Nodes[I];
    { G6.46: SubtreeEndExclusive — 0-based край ПІСЛЯ піддерева
      серед вузлів in-memory ExactIR, не слово .sens та не Dn.
      Перевіряємо ДО використання інтервалу в lowering чи LCL.
      Один SizeInt, жодної нової алокації; статистика атомарна. }
    if (N.SubtreeEndExclusive <= I) or
       (N.SubtreeEndExclusive > Length(IR.Nodes)) then
      Reject('некоректна піввідкрита межа піддерева IR');
    if N.ParentIndex < -1 then
      Reject('від’ємний індекс батька IR');
    if N.ParentIndex = -1 then begin
      { Новий корінь замикає ВСІ попередні активні піддерева
        точно на цьому preorder індексі, не раніше й не пізніше. }
      while ActiveCount > 0 do begin
        if IR.Nodes[ActiveAncestors[ActiveCount-1]].SubtreeEndExclusive<>I then
          Reject('піддерево IR перетнуло наступний корінь');
        Dec(ActiveCount);
      end;
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
            (ActiveAncestors[ActiveCount-1] <> Parent) do begin
        if IR.Nodes[ActiveAncestors[ActiveCount-1]].SubtreeEndExclusive<>I then
          Reject('піддерево IR має неточну межу між сусідами');
        Dec(ActiveCount);
      end;
      if ActiveCount = 0 then
        Reject('розірваний preorder: повернення до закритого піддерева');
      if N.SubtreeEndExclusive>IR.Nodes[Parent].SubtreeEndExclusive then
        Reject('дочірнє піддерево виходить за межі батька');
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

    if (N.Kind in [ikIdentity,ikEmpty]) and
       (N.SubtreeEndExclusive<>I+1) then
      Reject('листок IR не може охоплювати інші вузли');
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
    { Перша ikPair фізичного крапкового списку володіє опорою
      його D2 OPEN, як ikList. Лише її правий похідний ланцюг
      повторює ТОЙ САМИЙ OPEN без нового фізичного слова.
      Вкладений фізичний список має вже іншу опору.
      ParentIndex позичає перевірений попередній value record;
      SharedPairAnchor — локальний Boolean, без allocation.
      Порівнюємо поля, не record padding або текстову проєкцію. }
    SharedPairAnchor := False;
    if (N.Kind = ikPair) and (N.ParentIndex >= 0) then begin
      Parent := N.ParentIndex;
      if (IR.Nodes[Parent].Kind = ikPair) and
         (N.WordIndex = IR.Nodes[Parent].WordIndex) then begin
        if (N.ChildIndex <> 1) or
           (N.Physical.TritStart <> IR.Nodes[Parent].Physical.TritStart) or
           (N.Physical.TritEnd <> IR.Nodes[Parent].Physical.TritEnd) or
           (N.Physical.ByteStart <> IR.Nodes[Parent].Physical.ByteStart) or
           (N.Physical.ByteEnd <> IR.Nodes[Parent].Physical.ByteEnd) then
          Reject('пошкоджено спільну фізичну опору похідної пари IR');
        SharedPairAnchor := True;
      end;
    end;
    { Кожна нова фізична опора і кожен листок мають зберігати
      порядок джерела; спільна права опора не рухає цей курсор.
      D2:00 проміжні пропуски дозволені, тому інтервал
      наступного фізичного слова може починатися ПІЗНІШЕ,
      але не раніше кінця попереднього.
      Перевірка не декодує байтів і не тлумачить закон SENS. }
    if not SharedPairAnchor then begin
      if (N.WordIndex <= LastRealWordIndex) or
         (N.Physical.TritStart < LastRealTritEnd) then
        Reject('перекрито або переставлено фізичні слова IR');
      LastRealWordIndex := N.WordIndex;
      LastRealTritEnd := N.Physical.TritEnd;
    end;
    if N.Depth > Candidate.MaxDepth then Candidate.MaxDepth := N.Depth;
    if N.Kind in [ikList,ikPair] then begin
      ActiveAncestors[ActiveCount] := I;
      Inc(ActiveCount);
    end;
  end;
  { Закриття останнього кореня має припадати рівно на EOF вузлів.
    Кожен структурний предок замикається максимум один раз: O(N),
    використано вже існуючий стек ActiveAncestors без дубля AST. }
  while ActiveCount > 0 do begin
    if IR.Nodes[ActiveAncestors[ActiveCount-1]].SubtreeEndExclusive<>
       Length(IR.Nodes) then
      Reject('останнє піддерево IR не завершується на кінці документа');
    Dec(ActiveCount);
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
{ Запитання до перевірки опор:
  1) Чому перша ikPair має враховувати фізичний D2 OPEN?
  2) Чим права похідна пара відрізняється від вкладеної фізичної?
  3) Чому однаковий WordIndex вимагає тотожних тритів і байтів?
  4) Чому Stats залишається нульовим після пізньої відмови?
  5) Чому цей структурний доказ не допускає виклик SENS? }
end.
