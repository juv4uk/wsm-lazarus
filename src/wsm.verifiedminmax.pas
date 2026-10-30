{ G6.209 — D6:110101 «найменше» і D6:110111 «найбільше» через
  ОДНОРАЗОВИЙ перевірений контекст.
  Сьома хвиля рою після G6.190 (D5:01000), G6.191 (D5:11010),
  G6.192 (D5:01011), G6.199 (D5:10110), G6.200 (D5:10111) і
  G6.206 (D6:010100): той самий шаблон поширено на машинний
  профіль фізичного мінімуму й максимуму D12.

  Тут НЕМАЄ ні DecodeT5M, ні перевірки канонічності EncodeT5M, ні
  LoadPinnedDomains, ні BuildWideIR, ні VerifyWideIRStructure — усе це
  вже зробив TVerifiedWideContext РІВНО ОДИН раз на цю програму.
  Лишається тільки те, що належить САМЕ цьому машинному профілю:
  форма D2, pinned-голова D6:110101/110111, D12-допуск операндів,
  ELF-геометрія.

  Машинний генератор не змінюється і не дублюється: ті самі
  BuildD12MinELF із wsm.elfd12min та BuildD12MaxELF із wsm.elfd12max,
  які викликає чинний wsm.irwideminmax.BuildIRWideMinMaxELF. Разом із
  ними незмінно успадковується ЙОГО відмова на будь-який не-D12
  операнд і на невиконану геометрію ELF64 PIE — жодної нової чи
  ослабленої числової перевірки цей unit не додає.
  1) Чому повторний DecodeT5M тут був би другим проходом, а не захистом?
  2) Чому ширина W12 сама по собі не робить листок числом?
  3) Чому дві різні pinned-голови дозволені, а третя — ні?
  4) Чому вибір CMP/CMOVG чи CMP/CMOVL лишається в машинному генераторі?
  5) Хто звільняє позичений IR і власні байти ELF після return? }
unit wsm.verifiedminmax;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedMinMaxError=class(Exception);

{ Нижній рівень для TVerifiedWideContext.Lower: отримує ПОЗИЧЕНИЙ
  read-only IR і не має права його змінювати. Повертає власні байти ELF. }
function LowerVerifiedMinMax(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane, wsm.elfd12min,
     wsm.elfd12max, wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedMinMaxError.Create(Why) end;

{ Точний opaque W12 аргумент: ширина НЕ робить слово числом.
  Числовий допуск — окремий чинний ReadNumericPhysical, як і раніше.
  Крайній signed D12 -2048 тут НЕ відкидається: це межа машинного
  профілю, і вона мусить лишитися рівно там, де її тримають
  BuildD12MinELF / BuildD12MaxELF. }
function AdmitOperand(const Node:TWideIRNode;Child:SizeInt):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Must((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=0) and (Node.RootIndex=0) and
       (Node.ChildIndex=Child) and (Node.Depth=1) and
       (not Node.HasPinnedKey) and (Node.NarrowKey.Width=0),
       'не підтверджено точний opaque W12 аргумент D6-мінімуму/максимуму');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

{ IR/Stats — позичені; Result — окремий власний ELF64.
  Тут лише профільні інваріанти: один плоский D2, pinned 110101 або
  110111, два opaque W12, і незмінний машинний CMP/CMOVG або CMP/CMOVL.
  Обидві дозволені голови відрізняються шістьма точними бітами, тому
  маршрут вибирається за бітами голови, а не за назвою чи текстом. }
function LowerVerifiedMinMax(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString; G:TELFGeometry;
    Head:TWideIRNode;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна плоска D6:110101/110111(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Head:=IR.Nodes[1];
  Must((Head.Kind=wkAtom) and Head.OwnWord and
       Head.HasPinnedKey and (Head.Width=6) and (Length(Head.Bits)=6) and
       SameKey(Head.NarrowKey,ExactKey(Head.Bits)) and
       ((Head.Bits='110101') or (Head.Bits='110111')) and
       (Head.ParentIndex=0) and (Head.RootIndex=0) and
       (Head.ChildIndex=0) and (Head.Depth=1),
       'потрібна pinned D6:110101 «найменше» або D6:110111 «найбільше» голова');
  LeftPhysical:=AdmitOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitOperand(IR.Nodes[3],2);
  { Ті самі незмінні машинні генератори, що й у чинному backend.
    Саме вони тримають D12-допуск операндів і геометрію ELF64 PIE —
    ці перевірки не послаблені. }
  if Head.Bits='110101' then
    Result:=BuildD12MinELF(LeftPhysical,RightPhysical)
  else
    Result:=BuildD12MaxELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and (G.Entry=120),
       'чинний backend не повернув перевірений ELF64 PIE');
end;

end.
