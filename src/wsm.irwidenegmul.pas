{ G6.91 — вузька СКОМПІЛЬОВАНА повна фізична програма
  (D5:10110 D12:-1 D12:x) → WideIR → машинний x86 NEG → exact T5M.
  Жодного текстового або англійського semantic dispatch; джерело
  числового закону — лише pinned SENS Contract 12.0, а не Pascal. }
unit wsm.irwidenegmul;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideNegMulError=class(Exception);
function BuildIRWideNegMulELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12neg,wsm.elfgeometry;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRWideNegMulError.Create(Why);
end;

{ IR: borrowed managed array. Тут визнається рівно один D2 список із
  3 дітьми: pinned D5:10110 та ДВА opaque D12 атоми.
  Фізична адреса кожного вузла віддається вже чинним WideIR/Guard.
  Критерій -1: усі 12 бітів дорівнюють 1; жодних decimal fallbacks.
  1) Чому 111111111111 є exact D12:-1, а не D1?
  2) Чому не можна розпізнавати оператор за назвою «помножити»?
  3) Чому guard перевіряє і ширину, і ParentIndex/ChildIndex?
  4) Чому W24 значення заборонені на вході? }
procedure VerifyOnlyMinusOneMul(const IR:TWideIR;
  const Stats:TWideIRGuardStats);
var Head,MinusOne,Argument:TWideIRNode;
begin
  Need((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна повна D5:10110(D12:-1 D12) форма');
  Need((IR.Nodes[0].Kind=wkList) and
       (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
       'потрібен D2 кореневий список');
  Head:=IR.Nodes[1];
  MinusOne:=IR.Nodes[2];
  Argument:=IR.Nodes[3];
  Need((Head.Kind=wkAtom) and Head.OwnWord and
       Head.HasPinnedKey and (Head.Width=5) and
       (Head.Bits='10110') and
       SameKey(Head.NarrowKey,ExactKey('10110')) and
       (Head.ParentIndex=0) and (Head.ChildIndex=0) and
       (Head.Depth=1),
       'голова не є pinned D5:10110 помножити');
  Need((MinusOne.Kind=wkAtom) and MinusOne.OwnWord and
       (MinusOne.Width=12) and
       (MinusOne.Bits='111111111111') and
       (not MinusOne.HasPinnedKey) and
       (MinusOne.ParentIndex=0) and (MinusOne.ChildIndex=1) and
       (MinusOne.Depth=1),
       'перший операнд має бути точним D12:-1');
  Need((Argument.Kind=wkAtom) and Argument.OwnWord and
       (Argument.Width=12) and
       (Length(Argument.Bits)=12) and
       (not Argument.HasPinnedKey) and
       (Argument.ParentIndex=0) and (Argument.ChildIndex=2) and
       (Argument.Depth=1),
       'другий операнд має бути точним атомом D12');
end;

{ Physical: borrowed packed canonical .sens програма з повним D2.
  AuthorityRoot: borrowed pinned шлях до ратифікованих таблиць.
  Result: owned Free Pascal managed ELF64 ET_DYN байти. Проміжні
  RawByteString і масиви WideIR managed FPC, без витоку живих вузлів.
  Checked numeric admission обох атомів гарантує D12 і знак;
  BuildD12NegELF виконує pinned MUL(-1,x) admission та справжній
  NEG eax із фізичним D12 або D24 результатом. Це НЕ fold літералу.
  1) Чому numeric admission не заміняє pinned WideIR перевірку?
  2) Хто вирішує, чи D12 результат слід підвищити до D24?
  3) Чому текст .lisp не входить у backend?
  4) Чому ELF тут не може оголошуватися канонічним SENS?
  5) Хто звільняє локальні managed RawByteString? }
function BuildIRWideNegMulELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded,AtomWords:TExactWords;
    First,Second,MinusPhysical,AtomPhysical:RawByteString;
    LeftNumeric,RightNumeric:TExplicitNumeric;
    Geometry:TELFGeometry;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
       'довжина фізичної програми поза host-межею');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,'паковані байти T5M не канонічні');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyOnlyMinusOneMul(IR,Stats);
  SetLength(AtomWords,1);
  AtomWords[0]:=IR.Nodes[2].Bits;
  MinusPhysical:=EncodeT5M(AtomWords);
  AtomWords[0]:=IR.Nodes[3].Bits;
  AtomPhysical:=EncodeT5M(AtomWords);
  LeftNumeric:=ReadNumericPhysical(MinusPhysical,12);
  RightNumeric:=ReadNumericPhysical(AtomPhysical,12);
  Need((LeftNumeric.DomainWidth=12) and
       (LeftNumeric.ExactBits='111111111111') and
       (RightNumeric.DomainWidth=12) and
       (RightNumeric.ExactBits=IR.Nodes[3].Bits),
       'не допущені точні два D12 числа');
  Result:=BuildD12NegELF(AtomPhysical);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
       (Geometry.Entry=120),
       'зіпсована ELF64 PIE геометрія після native NEG');
end;
end.
