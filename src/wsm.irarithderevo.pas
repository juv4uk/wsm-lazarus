{ G6.146: нативний механізм обох довільно вкладених D5-піддерев.
  Чинні закони — ВИКЛЮЧНО pinned external/sens Contract 12.0.
  Межа 31 D5 вузол — host-квота, НЕ обмеження мови SENS. }
unit wsm.irarithderevo;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRMixedTreeError=class(Exception);
function BuildIRMixedTreeELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.numericsub,
  wsm.elfd12add,wsm.elfgeometry;
const HeaderBytes=120;MovBytes=5;StepBytes=5;
      MaxOperations=31;MaxPhysicalBytes=8192;
type
  TThreeIndices=array[0..2] of SizeInt;
  TChildMap=array of TThreeIndices;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise EIRMixedTreeError.Create(Why) end;
procedure PutLE64(var Image:RawByteString;At:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((At>=0) and (At<=Length(Image)-8),'пошкоджено ELF64 поле');
  for I:=0 to 7 do begin
    Image[At+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function Word12(const Bits:RawByteString):RawByteString;
var W:TExactWords;Number:TExplicitNumeric;
begin
  Need(Length(Bits)=12,'не exact W12');
  SetLength(W,1);W[0]:=Bits;
  Result:=EncodeT5M(W);
  Number:=ReadNumericPhysical(Result,12);
  Need((Number.DomainWidth=12) and (Number.ExactBits=Bits),
    'числовий D12 допуск не підтверджено');
end;

{ Physical — borrowed packed T5M. IR та ChildMap — локально owned arrays,
  Data/Code — managed bytes. Жодна назва D7 не обирає закон або ISA.
  Перевіряємо КОЖНУ D5 голову за точним ключем і pinned таблицею;
  КОЖЕН проміжний результат за Add/SubNumericPhysical і D12 gate.
  Рекурсивний кодогенератор:
     left → PUSH RAX → right → POP RCX → ADD EAX,ECX
  або SUB ECX,EAX / MOV EAX,ECX (саме left - right).
  Writer T5M/RIP-relative таблиці позичені із BuildD12AddELF як
  незмінний суфікс; він переміщується разом з усіма таблицями.
  RSP збалансований: кожен PUSH має один POP, в тому ж вузлі.
  Питання: чому SUB EAX,ECX порушило б некомутативність?
  Чому W12 opaque без ReadNumericPhysical не має числової влади?
  Де виключаємо зайву четверту дитину і чужий D5 ключ?
  Чому RIP-relative displacement не треба змінювати?
  Коли код може вперше стати зовнішнім ELF? }
function BuildIRMixedTreeELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Children:TChildMap;W:TExactWords;
    I,J,Parent,OpsCount:SizeInt;
    Base,Zero,OutputValue,Ops,Image:RawByteString;
    G:TELFGeometry;

  procedure CompileNode(NodeIndex:SizeInt;out Value,Code:RawByteString);
  var N,Head:TWideIRNode;LValue,RValue,LCode,RCode,Next:RawByteString;
      T:TExplicitNumeric;Donor:RawByteString;LocalG:TELFGeometry;
      K:TDomainKey;R:TDomainRow;
  begin
    Need((NodeIndex>=0) and (NodeIndex<Length(IR.Nodes)),
      'WideIR вузол поза межами');
    N:=IR.Nodes[NodeIndex];
    case N.Kind of
      wkAtom:begin
        Need((N.Width=12) and (Length(N.Bits)=12) and
             (not N.HasPinnedKey) and N.OwnWord,
             'листок дерева не є фізичним exact D12');
        Value:=Word12(N.Bits);
        { Реальний перевірений emitter надає MOV, не готовий результат. }
        Donor:=BuildD12AddELF(Value,Zero);
        VerifySENSELF64(Donor,LocalG);
        Need((LocalG.Kind=3) and (LocalG.Entry=HeaderBytes) and
             (Length(Donor)=Length(Base)) and
             (Donor[HeaderBytes+1]=#$B8) and
             (Donor[HeaderBytes+MovBytes+1]=#$05) and
             (Copy(Donor,HeaderBytes+MovBytes+StepBytes+1,
                Length(Donor)-HeaderBytes-MovBytes-StepBytes)=
              Copy(Base,HeaderBytes+MovBytes+StepBytes+1,
                Length(Base)-HeaderBytes-MovBytes-StepBytes)),
             'змінився перевірений ELF64 MOV/T5M донор');
        Code:=Copy(Donor,HeaderBytes+1,MovBytes);
      end;
      wkList:begin
        Inc(OpsCount);
        Need(OpsCount<=MaxOperations,'понад 31 D5 операцію');
        Need((Children[NodeIndex][0]>=0) and
             (Children[NodeIndex][1]>=0) and
             (Children[NodeIndex][2]>=0),
             'D5 список має мати рівно три поля');
        Head:=IR.Nodes[Children[NodeIndex][0]];
        Need((Head.Kind=wkAtom) and (Head.Width=5) and
             Head.HasPinnedKey and Head.OwnWord and
             ((Head.Bits='01010') or (Head.Bits='01011')) and
             SameKey(Head.NarrowKey,ExactKey(Head.Bits)),
             'голова не точна pinned D5:01010/01011');
        K:=ExactKey(Head.Bits);
        Need(DomainRowByKey(Tables[5],K,R) and SameKey(R.Key,K),
             'відсутній ратифікований D5 ключ у pinned SENS');
        CompileNode(Children[NodeIndex][1],LValue,LCode);
        CompileNode(Children[NodeIndex][2],RValue,RCode);
        if Head.Bits='01010' then begin
          Next:=AddNumericPhysical(LValue,RValue,12);
          { push rax; right; pop rcx; add eax,ecx }
          Code:=LCode+#$50+RCode+#$59+#$01#$C8;
        end else begin
          Next:=SubtractNumericPhysical(LValue,RValue,12);
          { push rax; right; pop rcx; sub ecx,eax; mov eax,ecx }
          Code:=LCode+#$50+RCode+#$59+#$29#$C1#$89#$C8;
        end;
        T:=ReadNumericPhysical(Next,12);
        Need((T.DomainWidth=12) and (Length(T.ExactBits)=12),
             'проміжне D12→D24 підвищення заборонено');
        Need(Length(Code)<4096,'перевищена квота машинного коду');
        Value:=Next;
      end;
      else Need(False,'D2 не є виконуваним D5 деревом');
    end;
  end;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=MaxPhysicalBytes),
       'порожня чи завелика фізична програма');
  DecodeT5M(Physical,W);
  Need(EncodeT5M(W)=Physical,'неканонічний фізичний T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)>=4) and
       (Length(IR.Nodes)<=3*MaxOperations+1) and
       ((Length(IR.Nodes)-1) mod 3=0) and
       (IR.Nodes[0].Kind=wkList),
       'потрібне одне 1..31 D5 дерево');
  SetLength(Children,Length(IR.Nodes));
  for I:=0 to High(Children) do
    for J:=0 to 2 do Children[I][J]:=-1;
  for I:=1 to High(IR.Nodes) do begin
    Parent:=IR.Nodes[I].ParentIndex;
    Need((Parent>=0) and (Parent<I),
      'неправильний батько фізичного дерева');
    Need(IR.Nodes[Parent].Kind=wkList,
      'недопустима пара або атом-батько D5');
    J:=IR.Nodes[I].ChildIndex;
    Need((J>=0) and (J<=2) and (Children[Parent][J]=-1),
      'невірна арність або повторний child index');
    Children[Parent][J]:=I;
  end;
  { У списках рівно три дочірні вузли, без втрат і неявних операндів. }
  for I:=0 to High(IR.Nodes) do
    if IR.Nodes[I].Kind=wkList then
      Need((Children[I][0]>=0) and (Children[I][1]>=0) and
           (Children[I][2]>=0),'невірна арність D5 дерева');
  Zero:=Word12('000000000000');
  Base:=BuildD12AddELF(Zero,Zero);
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (Length(Base)>HeaderBytes+MovBytes+StepBytes) and
       (Base[HeaderBytes+1]=#$B8) and
       (Base[HeaderBytes+MovBytes+1]=#$05) and
       (Base[HeaderBytes+MovBytes+StepBytes+1]=#$25),
       'донор ELF змінив машинний пролог чи T5M writer');
  OpsCount:=0;
  CompileNode(0,OutputValue,Ops);
  Need((OpsCount>=1) and
       (Length(IR.Nodes)=3*OpsCount+1),
       'частину WideIR не включено в машинне дерево');
  Need(Length(Ops)<4096,'машинна квота перевищена');
  Image:=Copy(Base,1,HeaderBytes)+Ops+
    Copy(Base,HeaderBytes+MovBytes+StepBytes+1,
      Length(Base)-HeaderBytes-MovBytes-StepBytes);
  Need(Length(Image)=Length(Base)-MovBytes-StepBytes+Length(Ops),
    'довжина ELF64 не відповідає реально виданим байтам');
  PutLE64(Image,96,Length(Image));
  PutLE64(Image,104,Length(Image));
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Image)),
       'остаточний ELF64 PIE не пройшов верифікацію');
  Result:=Image;
end;
end.
