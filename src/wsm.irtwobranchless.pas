{ G6.100 — два незалежні вкладені арифметичні піддерева D5 → один ELF.
  pinned Contract12 — мовний закон. Free Pascal виконує лише механічне
  exact-width admission, верифікацію WideIR та перевірене machine lowering.
  D12→D24 у кожній гілці — явний блок, не обрізання молодших бітів. }
unit wsm.irtwobranchless;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRTwoBranchLessError=class(Exception);
function BuildIRTwoBranchLessELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.numericadd,wsm.numericsub,
     wsm.elfd12add,wsm.elfd12sub,wsm.elfd12greater,wsm.elfgeometry;

const HeaderBytes=120; MovBytes=5; ArithmeticBytes=5;
procedure Need(Condition:Boolean;const Reason:String);
begin
  if not Condition then raise EIRTwoBranchLessError.Create(Reason);
end;

{ Borrowed TWideIRNode — фізичні точні біти, а не D12 resident.
  D12 admission дозволений лише всередині трьох pinned D5 викликів.
  Result: owned RawByteString пакованого одиночного D12 T5M атома.
  Жодного десяткового чи D7 відображення до механічного backend.
  Питання: чому W12 сам по собі opaque?
  Як фіксується позиція чотирьох аргументів?
  Чому leading zeros не можна опускати?
  Хто володіє пам’яттю Result? }
function AdmitD12(const Node:TWideIRNode;
  Parent,Child,Depth:SizeInt):RawByteString;
var Words:TExactWords;Number:TExplicitNumeric;
begin
  Need((Node.Kind=wkAtom) and Node.OwnWord and
    (Node.Width=12) and (Length(Node.Bits)=12) and
    (not Node.HasPinnedKey) and (Node.ParentIndex=Parent) and
    (Node.ChildIndex=Child) and (Node.RootIndex=0) and
    (Node.Depth=Depth),'неправильна точна фізична D12 координата');
  SetLength(Words,1);Words[0]:=Node.Bits;
  Result:=EncodeT5M(Words);
  Number:=ReadNumericPhysical(Result,12);
  Need((Number.DomainWidth=12) and
    (Number.ExactBits=Node.Bits),
    'пошкоджено точну D12 ідентичність аргументу');
end;

{ ExactKey — pinned D5 word, не ASCII/укр dispatch.
  RootIndex/ParentIndex/ChildIndex/Depth — вимоги структурної програми.
  Питання: чи достатньо тільки Bits без домену?
  Чи може D7 назва бути callable без pinned координати?
  Чому HasPinnedKey перевіряється перед code emission?
  Як відхиляється перестановка піддерев? }
procedure Head(const N:TWideIRNode;
  const Bits:RawByteString;Parent,Child,Depth:SizeInt);
begin
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
    (N.Width=5) and (N.Bits=Bits) and
    SameKey(N.NarrowKey,ExactKey(Bits)) and
    (N.RootIndex=0) and (N.ParentIndex=Parent) and
    (N.ChildIndex=Child) and (N.Depth=Depth),
    'виклична голова не збігається із ратифікованою D5 адресою');
end;

{ Borrowed ELF result — owned managed bytes. Два ELF64 size-поля
  host little endian p_filesz/p_memsz; НЕ SENS D12-число.
  Усі вставки перед першою RIP-relative LEA, а lookup-таблиця
  переїздить разом з нею: relative displacement не змінюється.
  Питання: чому змінюємо обидва size поля?
  Яким guard доводимо безпечні межі Offset?
  Чому не патчимо вже verified RIP displacement?
  Коли звільняється Image? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Image)-8),
    'поле ELF64 поза межами образу');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Result: один owned executable ELF64 PIE, не готовий D1 literal.
  Точно один 10-node фізичний preorder D2 вираз:
    (D5:11010 (D5:01010 A B) (D5:01011 C D))
  Спочатку pinned WideIR + numeric law, відмова при D24 в будь-якій
  гілці. Далі механічна композиція машинних префіксів:
  - MOV EAX,A + ADD EAX,B (чинний verified ADD).
  - MOV ECX,C (чинний verified GREATER).
  - XCHG EAX,ECX (host x86-64 91), SUB EAX,D (verified SUB),
    XCHG EAX,ECX: EAX тепер сума, ECX різниця.
  - чинний CMP EAX,ECX, перевірений patch SETG→SETL/MOVZX/T5M D1 writer.
  Укладені значення на CPU рахуються без готового D1.
  Питання: чому XCHG не змінює арифметичні flags перед CMP?
  Чому SUB із verified emitter працює в EAX?
  Чому сума й різниця не можуть неявно перетворитись на D24?
  Чому це ще не довільний компілятор Core1?
  Де незалежна pinned SENS REPL перевірка обох піддерев? }
function BuildIRTwoBranchLessELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;N:TExplicitNumeric;
    A,B,C,D,Sum,Difference,AddImage,SubImage,GreaterImage:RawByteString;
    AG,SG,GG,FinalG:TELFGeometry;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
    'порожній або завеликий фізичний T5M файл');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'неканонічний фізичний T5M');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Nodes=10) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=7) and (Stats.OpaqueLeaves=4) and
    (Length(IR.Nodes)=10) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0),'потрібна одна фізична D5 форма з двома піддеревами');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
    (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].RootIndex=0) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'пошкоджений фізичний D2 корінь');
  Head(IR.Nodes[1],'11010',0,0,1);
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
    (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
    (IR.Nodes[2].Depth=1) and (IR.Nodes[2].RootIndex=0),
    'лівий аргумент має бути вкладеною D2 арифметикою');
  Head(IR.Nodes[3],'01010',2,0,2);
  A:=AdmitD12(IR.Nodes[4],2,1,2);
  B:=AdmitD12(IR.Nodes[5],2,2,2);
  Need((IR.Nodes[6].Kind=wkList) and IR.Nodes[6].OwnWord and
    (IR.Nodes[6].ParentIndex=0) and (IR.Nodes[6].ChildIndex=2) and
    (IR.Nodes[6].Depth=1) and (IR.Nodes[6].RootIndex=0),
    'правий аргумент має бути другим вкладеним D2 списком');
  Head(IR.Nodes[7],'01011',6,0,2);
  C:=AdmitD12(IR.Nodes[8],6,1,2);
  D:=AdmitD12(IR.Nodes[9],6,2,2);

  Sum:=AddNumericPhysical(A,B,12);
  Difference:=SubtractNumericPhysical(C,D,12);
  try
    N:=ReadNumericPhysical(Sum,12);
    Need(N.DomainWidth=12,'сума не точний D12');
    N:=ReadNumericPhysical(Difference,12);
    Need(N.DomainWidth=12,'різниця не точний D12');
  except on E:ENumericPlaneError do
    raise EIRTwoBranchLessError.Create(
      'проміжний результат потребує D24, вузький профіль лише D12: '+E.Message);
  end;

  AddImage:=BuildD12AddELF(A,B);
  SubImage:=BuildD12SubELF(C,D);
  GreaterImage:=BuildD12GreaterELF(Sum,C);
  VerifySENSELF64(AddImage,AG);
  VerifySENSELF64(SubImage,SG);
  VerifySENSELF64(GreaterImage,GG);
  Need((AG.Kind=3) and (SG.Kind=3) and (GG.Kind=3) and
    (AG.Entry=HeaderBytes) and (SG.Entry=HeaderBytes) and
    (GG.Entry=HeaderBytes),'потрібні три чинні ELF64 PIE emitter-и');
  Need((Length(AddImage)>=HeaderBytes+10) and
    (Length(SubImage)>=HeaderBytes+10) and
    (Length(GreaterImage)>=HeaderBytes+17) and
    (AddImage[HeaderBytes+1]=#$B8) and
    (AddImage[HeaderBytes+6]=#$05) and
    (SubImage[HeaderBytes+1]=#$B8) and
    (SubImage[HeaderBytes+6]=#$2D) and
    (GreaterImage[HeaderBytes+1]=#$B8) and
    (GreaterImage[HeaderBytes+6]=#$B9) and
    (GreaterImage[HeaderBytes+11]=#$39) and
    (GreaterImage[HeaderBytes+12]=#$C8) and
    (GreaterImage[HeaderBytes+13]=#$0F) and
    (GreaterImage[HeaderBytes+14]=#$9F) and
    (GreaterImage[HeaderBytes+15]=#$C0) and
    (GreaterImage[HeaderBytes+16]=#$0F) and
    (GreaterImage[HeaderBytes+17]=#$B6),
    'префікс чинного машинного backend змінився');

  Need(Length(GreaterImage)<1024*1024-12,'ELF64 поза квотою');
  Result:=Copy(GreaterImage,1,HeaderBytes)+
    Copy(AddImage,HeaderBytes+1,10)+
    Copy(GreaterImage,HeaderBytes+6,MovBytes)+
    #$91+Copy(SubImage,HeaderBytes+6,ArithmeticBytes)+#$91+
    Copy(GreaterImage,HeaderBytes+11,
      Length(GreaterImage)-HeaderBytes-10);
  Need(Length(Result)=Length(GreaterImage)+12,
    'втрата машинних байтів під час двогілкового lowering SETL');
  { Лише механічна зміна SETG у SETL після повної звірки байтів
    чинного x86-64 шаблону; D5:11010 підтверджено вище через
    pinned exact-domain WideIR, не через український напис. }
  Need((Length(Result)>=HeaderBytes+26) and
       (Result[HeaderBytes+26]=#$9F),
       'неочікуваний CMP/SETG host-префікс перед SETL');
  Result[HeaderBytes+26]:=#$9C;
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalG);
  Need((FinalG.Kind=3) and (FinalG.Entry=HeaderBytes) and
    (FinalG.FileBytes=Length(Result)),
    'двогілковий ELF64 не пройшов кінцевий guard');
end;
end.
