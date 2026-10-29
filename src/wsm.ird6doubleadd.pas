{ G6.90 — один canonical D2/T5M вираз із двома вкладеними D6:001110.
  Pinned SENS Contract12 визначає закони. Цей unit — лише FPC lowering
  через перевірений WideIR та вже злитий машинний D12 ADD backend.
  Вихід: ОДИН ELF64 PIE, що під час запуску виконує ДВІ інструкції ADD.
  Межа: обидва числові етапи точно D12; D24 promotion відхиляється. }
unit wsm.ird6doubleadd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRDoubleAddError=class(Exception);
function BuildIRDoubleAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.numericadd,wsm.elfd12add,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; AddBytes=5;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRDoubleAddError.Create(Why);
end;

{ IR — позичені керовані exact-width слова та перевірені фізичні адреси.
  Вузькі D6 голови — ТІЛЬКИ ключ W6:001110 із pinned таблиці.
  W12 листок лишається opaque до окремого ReadNumericPhysical.
  Ні укр-назва, ні host integer, ні D7 не створює callable identity.
  Питання: де встановлена межа між reader і викличністю?
  Чому перевіряємо дві голови, а не лише першу?
  Чому не дозволяємо ширину W24 навіть при рівних молодших бітах?
  Чи може інший D2-корінь пройти цей admission? }
procedure VerifyOnlyNestedAdd(const IR:TWideIR;
  const Stats:TWideIRGuardStats);
var N:TWideIRNode;
  procedure Head(const N:TWideIRNode;Parent,Child,Depth:SizeInt);
  begin
    Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
      (N.Width=6) and (N.Bits='001110') and
      SameKey(N.NarrowKey,ExactKey('001110')) and
      (N.ParentIndex=Parent) and (N.ChildIndex=Child) and
      (N.Depth=Depth) and (N.RootIndex=0),
      'очікується тільки pinned D6:001110 у точній голові');
  end;
begin
  Need((Stats.Nodes=5) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=1) and
       (Length(IR.Nodes)=5) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),'одна вкладена D6 форма повинна мати 5 вузлів');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].Depth=0) and
       (IR.Nodes[0].ChildIndex=0),
       'зовнішній D2 виклик має бути списком');
  Head(IR.Nodes[1],0,0,1);
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
       (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
       (IR.Nodes[2].Depth=1) and (IR.Nodes[2].RootIndex=0),
       'другий аргумент зовнішнього виклику — вкладений список');
  Head(IR.Nodes[3],2,0,2);
  N:=IR.Nodes[4];
  Need((N.Kind=wkAtom) and N.OwnWord and (N.Width=12) and
       (Length(N.Bits)=12) and (not N.HasPinnedKey) and
       (N.ParentIndex=2) and (N.ChildIndex=1) and
       (N.Depth=2) and (N.RootIndex=0),
       'вкладений аргумент — тільки один opaque D12 атом');
end;

{ Result: owned ELF байти; Patch змінює лише host ELF metadata.
  Host QWord LE — НЕ новий числовий домен.
  Питання: чому змінюємо p_filesz і p_memsz?
  Чому не можна вставляти пролог після RIP-relative LEA?
  Як виявляємо зміни машинного прологу upstream emitter? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;V:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
    'поза фізичною ELF геометрією');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

{ Physical — borrowed canonical T5M, AuthorityRoot — borrowed pinned
  каталог. Таблиці, IR і часові packed атоми належать FPC managed heap.
  Перший перевірений D12 emitter дає MOV+ADD; другий — ADD+writer.
  Заміняємо лише MOV другого на MOV+ADD першого: інструкція ADD другого
  зберігається; весь його код разом з RIP таблицями зсувається на 5
  байтів. У машинному ELF дві реальні ADD, не готова константа виходу.
  1) Де перевірено обидва exact D12 результати та overflow?
  2) Чому 5 байтів вставки не змінюють RIP відстані до таблиць?
  3) Чому після компіляції потрібен справжній запуск ELF?
  4) Чи є результати зворотними у canonical T5M?
  5) Хто звільнить тимчасові зображення та IR? }
function BuildIRDoubleAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Decoded,Words:TExactWords; Numeric:TExplicitNumeric;
    Atom,One,Intermediate,FirstELF,SecondELF:RawByteString;
    G1,G2,FinalGeometry:TELFGeometry; OldBytes:SizeInt;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=256),
    'порожня або завелика фізична вкладена програма');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,
    'вхід має бути канонічним фізичним T5M');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyOnlyNestedAdd(IR,Stats);
  SetLength(Words,1);
  Words[0]:=IR.Nodes[4].Bits;
  Atom:=EncodeT5M(Words);
  Numeric:=ReadNumericPhysical(Atom,12);
  Need((Numeric.DomainWidth=12) and
       (Numeric.ExactBits=IR.Nodes[4].Bits),
       'невдалий explicit D12 numeric admission');
  One:=EncodeNumericDecimal('1',12);
  { Чинний AddNumericPhysical визначає promotion; ніякого
    Wrap12 чи саморобного математичного evaluator тут немає. }
  Intermediate:=AddNumericPhysical(Atom,One,12);
  Numeric:=ReadNumericPhysical(Intermediate,12);
  Need(Numeric.DomainWidth=12,'перше додавання вийшло за D12');
  FirstELF:=BuildD12AddELF(Atom,One);
  SecondELF:=BuildD12AddELF(Intermediate,One);
  VerifySENSELF64(FirstELF,G1);
  VerifySENSELF64(SecondELF,G2);
  Need((G1.Kind=3) and (G2.Kind=3) and
       (G1.Entry=HeaderBytes) and (G2.Entry=HeaderBytes) and
       (Length(FirstELF)>=HeaderBytes+10) and
       (Length(SecondELF)>=HeaderBytes+10),
       'дві незалежні нативні ELF машини не пройшли admission');
  Need((FirstELF[HeaderBytes+1]=#$B8) and
       (FirstELF[HeaderBytes+6]=#$05) and
       (SecondELF[HeaderBytes+1]=#$B8) and
       (SecondELF[HeaderBytes+6]=#$05),
       'змінено пролог pinned нативного D12 ADD backend');
  OldBytes:=Length(SecondELF);
  Need(OldBytes<1024*1024-AddBytes,'перевищено host ELF квоту');
  Result:=Copy(SecondELF,1,HeaderBytes)+
    Copy(FirstELF,HeaderBytes+1,MovBytes+AddBytes)+
    Copy(SecondELF,HeaderBytes+MovBytes+1,
      OldBytes-HeaderBytes-MovBytes);
  Need(Length(Result)=OldBytes+AddBytes,'втрачено машинні байти');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
       (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=Length(Result)),
       'складений ELF64 PIE не пройшов геометрію');
end;
end.
