{ G6.17: незалежний механічний допуск уже побудованого широкого IR.
  W12/W24/... тут НЕ отримують мовного числового закону SENS.
  Немає нового reader, registry, evaluator чи semantic dispatch. }
unit wsm.wideirguard;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.wideir;

type
  EWideIRGuardError = class(Exception);
  TWideIRGuardStats = record
    Nodes, Roots, PhysicalLeaves, OpaqueLeaves, MaxDepth: SizeInt;
  end;

procedure VerifyWideIRStructure(const IR: TWideIR;
  out Stats: TWideIRGuardStats);

implementation
uses wsm.d2source, wsm.domain;

procedure Reject(const Why: String);
begin
  raise EWideIRGuardError.Create(Why);
end;

procedure VerifyWideIRStructure(const IR: TWideIR;
  out Stats: TWideIRGuardStats);
var
  Candidate: TWideIRGuardStats;
  ChildCount, Ancestors: array of SizeInt;
  Active, I, J, Parent, RootNumber: SizeInt;
  LastWordIndex, LastTritEnd: SizeInt;
  SharedPairAnchor: Boolean;
  N: TWideIRNode;
begin
  { Ніколи не випускати часткову статистику після відмови. }
  FillChar(Stats, SizeOf(Stats), 0);
  FillChar(Candidate, SizeOf(Candidate), 0);
  if (Length(IR.Nodes)<1) or (Length(IR.Nodes)>MaxWideIRNodes) or
     (Length(IR.Roots)<1) or (Length(IR.Roots)>Length(IR.Nodes)) then
    Reject('некоректна кількість вузлів або коренів широкого IR');
  SetLength(ChildCount,Length(IR.Nodes));
  SetLength(Ancestors,Length(IR.Nodes));
  Active:=0;
  RootNumber:=-1;
  LastWordIndex:=0;
  LastTritEnd:=0;
  for I:=0 to High(IR.Nodes) do begin
    N:=IR.Nodes[I];
    if N.ParentIndex= -1 then begin
      Active:=0;
      Inc(RootNumber);
      if (RootNumber>=Length(IR.Roots)) or
         (IR.Roots[RootNumber]<>I) or (N.RootIndex<>RootNumber) or
         (N.ChildIndex<>RootNumber) or (N.Depth<>0) then
        Reject('невірна коренева послідовність широкого IR');
    end else begin
      Parent:=N.ParentIndex;
      if (Parent<0) or (Parent>=I) then
        Reject('некоректний індекс батька широкого IR');
      while (Active>0) and (Ancestors[Active-1]<>Parent) do
        Dec(Active);
      if Active=0 then
        Reject('розірваний preorder широкого IR');
      if not (IR.Nodes[Parent].Kind in [wkList,wkPair]) then
        Reject('атом широкого IR має нащадка');
      if (N.RootIndex<>IR.Nodes[Parent].RootIndex) or
         (N.Depth<>IR.Nodes[Parent].Depth+1) or
         (N.Depth>MaxD2SyntaxDepth) then
        Reject('порушено глибину або походження вузла');
      if N.ChildIndex<>ChildCount[Parent] then
        Reject('непослідовні номери дітей широкого IR');
      Inc(ChildCount[Parent]);
    end;

    if (N.WordIndex<1) or (N.Physical.WordIndex<>N.WordIndex) or
       N.Physical.IsEOF or (N.Physical.TritStart<0) or
       (N.Physical.TritEnd<=N.Physical.TritStart) or
       (N.Physical.ByteStart<>N.Physical.TritStart div 5) or
       { Запис ceil без додавання 4: немає переповнення SizeInt. }
       (N.Physical.ByteEnd<>((N.Physical.TritEnd-1) div 5)+1) then
      Reject('сфальшований фізичний інтервал широкого IR');

    case N.Kind of
      wkList,wkPair: begin
        if (N.Kind=wkList)<>N.OwnWord then
          Reject('невірна власність структурного слова');
        if (N.Width<>0) or (Length(N.Bits)<>0) or N.HasPinnedKey or
           (N.NarrowKey.Width<>0) or (N.NarrowKey.Bits<>0) or
           (N.Physical.TritEnd-N.Physical.TritStart<>2) then
          Reject('структура D2 підмінена атомом');
      end;
      wkAtom,wkEmpty: begin
        if not N.OwnWord then
          Reject('атом без власного фізичного слова');
        if (N.Width<1) or (N.Width>192) or (N.Width=2) or
           (Length(N.Bits)<>N.Width) or
           (N.Physical.TritEnd-N.Physical.TritStart<>N.Width) then
          Reject('пошкоджено точну ширину двійкового слова');
        for J:=1 to N.Width do
          if not (N.Bits[J] in ['0','1']) then
            Reject('недвійковий біт фізичного слова');
        if (N.Kind=wkEmpty)<>(N.Bits='000') then
          Reject('підміна порожньої D3:000');
        if N.Width<=9 then begin
          if not N.HasPinnedKey then
            Reject('вузький листок втратив точний ключ');
          if not SameKey(N.NarrowKey,ExactKey(N.Bits)) then
            Reject('підмінена координата pinned листка');
        end else begin
          { W12 і навіть W192 самі по собі НЕ доводять D12+ identity. }
          if N.HasPinnedKey or (N.NarrowKey.Width<>0) or
             (N.NarrowKey.Bits<>0) then
            Reject('недозволене призначення закону широкому слову');
          Inc(Candidate.OpaqueLeaves);
        end;
        Inc(Candidate.PhysicalLeaves);
      end;
      else Reject('невідомий тип вузла широкого IR');
    end;

    { IR — позичений керований масив записів, N — локальна копія.
      Перша wkPair фізичного списку посилається на його D2 OPEN;
      лише правий похідний ланцюг повторює цю точну опору.
      OwnWord лишається False для ВСІХ похідних wkPair: жодного
      нового фізичного токена пари не створено. Локальний Boolean
      відрізняє повторення опори від її першого входження. }
    SharedPairAnchor:=False;
    if (N.Kind=wkPair) and (N.ParentIndex>=0) then begin
      Parent:=N.ParentIndex;
      if (IR.Nodes[Parent].Kind=wkPair) and
         (N.WordIndex=IR.Nodes[Parent].WordIndex) then begin
        if (N.ChildIndex<>1) or
           (N.Physical.TritStart<>IR.Nodes[Parent].Physical.TritStart) or
           (N.Physical.TritEnd<>IR.Nodes[Parent].Physical.TritEnd) or
           (N.Physical.ByteStart<>IR.Nodes[Parent].Physical.ByteStart) or
           (N.Physical.ByteEnd<>IR.Nodes[Parent].Physical.ByteEnd) then
          Reject('пошкоджено спільну опору широкої похідної пари');
        SharedPairAnchor:=True;
      end;
    end;
    { Для кожного нового фізичного слова порядок WordIndex строгий,
      трити не перекриваються; спільні байти й пропущені D2:00 законні.
      Не додаємо ширину до адреси: перевірені TritEnd вже точні,
      тому арифметичного переповнення на цій межі немає.
      Локальні SizeInt/Boolean не виділяють пам'яті; тільки повністю
      перевірена Candidate наприкінці стає публічною Stats. }
    if not SharedPairAnchor then begin
      if (N.WordIndex<=LastWordIndex) or
         (N.Physical.TritStart<LastTritEnd) then
        Reject('перекрито або переставлено фізичні слова широкого IR');
      LastWordIndex:=N.WordIndex;
      LastTritEnd:=N.Physical.TritEnd;
    end;
    if N.Depth>Candidate.MaxDepth then Candidate.MaxDepth:=N.Depth;
    if N.Kind in [wkList,wkPair] then begin
      Ancestors[Active]:=I;
      Inc(Active);
    end;
  end;
  if RootNumber+1<>Length(IR.Roots) then
    Reject('невідповідність кількості коренів');
  for I:=0 to High(IR.Nodes) do begin
    if (IR.Nodes[I].Kind in [wkAtom,wkEmpty]) and (ChildCount[I]<>0) then
      Reject('листок широкого IR має дочірні вузли');
    if (IR.Nodes[I].Kind=wkPair) and (ChildCount[I]<>2) then
      Reject('крапкова пара не має рівно двох складників');
  end;
  if (Candidate.PhysicalLeaves<>IR.PhysicalLeaves) or
     (Candidate.OpaqueLeaves<>IR.OpaqueLeaves) then
    Reject('пошкоджено лічильники широких листків');
  Candidate.Nodes:=Length(IR.Nodes);
  Candidate.Roots:=Length(IR.Roots);
  Stats:=Candidate;
end;
{ Запитання до фізичного порядку:
  1) Чому два різні слова можуть ділити байт, але не трит?
  2) Чому перша wkPair має враховувати опору D2 OPEN?
  3) Чому спільна опора дозволена лише правій похідній парі?
  4) Чому W192 і провідні нулі не дають числового закону?
  5) Чому після пізньої відмови Stats залишається нульовою? }
end.
