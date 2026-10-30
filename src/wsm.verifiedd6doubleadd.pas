{ G6.210 — D6:001110 «подвійне додавання» через ОДНОРАЗОВИЙ
  перевірений контекст.
  Восьма хвиля рою після G6.190 (D5:01000), G6.191 (D5:11010),
  G6.192 (D5:01011), G6.199 (D5:10110), G6.200 (D5:10111),
  G6.206 (D6:010100) і G6.209 (D6:110101/110111): той самий шаблон
  поширено на машинний профіль ВКЛАДЕНОГО подвійного додавання D12.

  Тут НЕМАЄ ні DecodeT5M, ні перевірки канонічності EncodeT5M, ні
  LoadPinnedDomains, ні BuildWideIR, ні VerifyWideIRStructure — усе це
  вже зробив TVerifiedWideContext РІВНО ОДИН раз на цю програму.
  Лишається тільки те, що належить САМЕ цьому машинному профілю:
  вкладена форма D2, ДВІ pinned-голови D6:001110 (зовнішня й
  внутрішня), числовий допуск єдиного opaque D12 листка, зшивання
  двох машинних ELF64 і геометрія результату.

  Машинний генератор не змінюється і не дублюється: той самий
  BuildD12AddELF із wsm.elfd12add, який двічі викликає чинний
  wsm.ird6doubleadd.BuildIRDoubleAddELF. Разом із ним незмінно
  успадковується ЙОГО числова межа: обидва доданки й проміжний
  результат точно D12, будь-який D24 promotion відхиляється — жодної
  нової чи ослабленої числової перевірки цей unit не додає.
  1) Чому повторний DecodeT5M тут був би другим проходом, а не захистом?
  2) Чому ширина W12 сама по собі не робить листок числом?
  3) Чому перевіряємо ДВІ голови, а не лише зовнішню?
  4) Чому проміжний D12 обчислює чинний AddNumericPhysical, а не цей unit?
  5) Хто звільняє позичений IR і власні байти ELF після return? }
unit wsm.verifiedd6doubleadd;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedD6DoubleAddError=class(Exception);

{ Нижній рівень для TVerifiedWideContext.Lower: отримує ПОЗИЧЕНИЙ
  read-only IR і не має права його змінювати. Повертає власні байти ELF. }
function LowerVerifiedD6DoubleAdd(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane, wsm.numericadd,
     wsm.elfd12add, wsm.elfgeometry;

const HeaderBytes=120; MovBytes=5; AddBytes=5;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedD6DoubleAddError.Create(Why) end;

{ Точний opaque W12 аргумент: ширина НЕ робить слово числом.
  Числовий допуск — окремий чинний ReadNumericPhysical, як і раніше.
  Крайній signed D12 -2048 тут НЕ відкидається: це межа машинного
  профілю, і вона мусить лишитися рівно там, де її тримає
  BuildD12AddELF. ExactBits звіряються з фізичними бітами вузла. }
function AdmitLeaf(const Node:TWideIRNode):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Must((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (not Node.HasPinnedKey) and (Node.NarrowKey.Width=0) and
       (Node.ParentIndex=2) and (Node.ChildIndex=1) and
       (Node.Depth=2) and (Node.RootIndex=0),
       'не підтверджено точний opaque W12 листок подвійного додавання');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

{ Профільна перевірка форми: одна вкладена D6:001110 форма
  D2(001110, D2(001110, D12)). Обидві голови pinned і обидві
  перевіряються за exact 6 бітами, а не за назвою чи текстом. }
procedure VerifyNestedProfile(const IR:TWideIR;
  const Stats:TWideIRGuardStats);
  procedure Head(const N:TWideIRNode;Parent,Child,Depth:SizeInt);
  begin
    Must((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
         (N.Width=6) and (Length(N.Bits)=6) and (N.Bits='001110') and
         SameKey(N.NarrowKey,ExactKey('001110')) and
         (N.ParentIndex=Parent) and (N.ChildIndex=Child) and
         (N.Depth=Depth) and (N.RootIndex=0),
         'очікується тільки pinned D6:001110 у точній голові');
  end;
begin
  Must((Stats.Nodes=5) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=1) and
       (Length(IR.Nodes)=5) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),
       'одна вкладена D6 форма повинна мати 5 вузлів');
  Must((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].Depth=0) and
       (IR.Nodes[0].ChildIndex=0),
       'зовнішній D2 виклик має бути списком');
  Head(IR.Nodes[1],0,0,1);
  Must((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
       (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
       (IR.Nodes[2].Depth=1) and (IR.Nodes[2].RootIndex=0),
       'другий аргумент зовнішнього виклику — вкладений список');
  Head(IR.Nodes[3],2,0,2);
  Must((IR.Nodes[4].Kind=wkAtom) and IR.Nodes[4].OwnWord and
       (IR.Nodes[4].Width=12) and (Length(IR.Nodes[4].Bits)=12) and
       (not IR.Nodes[4].HasPinnedKey) and
       (IR.Nodes[4].ParentIndex=2) and (IR.Nodes[4].ChildIndex=1) and
       (IR.Nodes[4].Depth=2) and (IR.Nodes[4].RootIndex=0),
       'вкладений аргумент — тільки один opaque D12 атом');
end;

{ Patch змінює лише host ELF metadata. Host QWord LE — НЕ новий
  числовий домен: це та сама фізична геометрія p_filesz/p_memsz,
  яку чинний backend оновлює після вставки 5 машинних байтів. }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;V:QWord);
var I:SizeInt;
begin
  Must((Offset>=0) and (Offset+8<=Length(Image)),
    'поза фізичною ELF геометрією');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

{ IR/Stats — позичені; Result — окремий власний ELF64.
  Дві ADD у машині: перший перевірений D12 emitter дає MOV+ADD,
  другий — ADD+writer. Заміняємо лише MOV другого на MOV+ADD
  першого; інструкція ADD другого зберігається; весь його код разом
  із RIP-таблицями зсувається на 5 байтів. Проміжний D12 обчислює
  чинний AddNumericPhysical — жодного саморобного evaluator тут немає.
  Фізичні RawByteString і керовані масиви належать FPC managed heap. }
function LowerVerifiedD6DoubleAdd(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var Atom,One,Intermediate,FirstELF,SecondELF:RawByteString;
    Numeric:TExplicitNumeric; G1,G2,FinalGeometry:TELFGeometry;
    OldBytes:SizeInt;
begin
  Result:='';
  VerifyNestedProfile(IR,Stats);
  Atom:=AdmitLeaf(IR.Nodes[4]);
  One:=EncodeNumericDecimal('1',12);
  { Чинний AddNumericPhysical визначає promotion; ніякого Wrap12
    чи саморобного математичного evaluator тут немає. }
  Intermediate:=AddNumericPhysical(Atom,One,12);
  Numeric:=ReadNumericPhysical(Intermediate,12);
  Must(Numeric.DomainWidth=12,'перше додавання вийшло за D12');
  { Той самий незмінний машинний генератор, що й у чинному backend.
    Саме він тримає D12-допуск доданків і геометрію ELF64 PIE. }
  FirstELF:=BuildD12AddELF(Atom,One);
  SecondELF:=BuildD12AddELF(Intermediate,One);
  VerifySENSELF64(FirstELF,G1);
  VerifySENSELF64(SecondELF,G2);
  Must((G1.Kind=3) and (G2.Kind=3) and
       (G1.Entry=HeaderBytes) and (G2.Entry=HeaderBytes) and
       (Length(FirstELF)>=HeaderBytes+10) and
       (Length(SecondELF)>=HeaderBytes+10),
       'дві незалежні нативні ELF машини не пройшли admission');
  Must((FirstELF[HeaderBytes+1]=#$B8) and
       (FirstELF[HeaderBytes+6]=#$05) and
       (SecondELF[HeaderBytes+1]=#$B8) and
       (SecondELF[HeaderBytes+6]=#$05),
       'змінено пролог pinned нативного D12 ADD backend');
  OldBytes:=Length(SecondELF);
  Must(OldBytes<1024*1024-AddBytes,'перевищено host ELF квоту');
  Result:=Copy(SecondELF,1,HeaderBytes)+
    Copy(FirstELF,HeaderBytes+1,MovBytes+AddBytes)+
    Copy(SecondELF,HeaderBytes+MovBytes+1,
      OldBytes-HeaderBytes-MovBytes);
  Must(Length(Result)=OldBytes+AddBytes,'втрачено машинні байти');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Must((FinalGeometry.Kind=3) and
       (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=Length(Result)),
       'складений ELF64 PIE не пройшов геометрію');
end;

end.
