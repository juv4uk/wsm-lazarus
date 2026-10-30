{ G6.116 — два незалежні вкладені арифметичні піддерева D5 → один ELF.
  pinned Contract12 — мовний закон. Free Pascal виконує лише механічне
  exact-width admission, верифікацію WideIR та перевірене machine lowering.
  D12→D24 у кожній гілці — явний блок, не обрізання молодших бітів. }
unit wsm.irtwoarithchoice;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRTwoArithChoiceError=class(Exception);
function BuildIRTwoArithChoiceELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.numericadd,wsm.numericsub,
     wsm.elfd12add,wsm.elfd12sub,wsm.elfd12greater,wsm.elfgeometry;

const HeaderBytes=120; MovBytes=5; ArithmeticBytes=5;
procedure Need(Condition:Boolean;const Reason:String);
begin
  if not Condition then raise EIRTwoArithChoiceError.Create(Reason);
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
    (N.Width=Length(Bits)) and (N.Bits=Bits) and
    SameKey(N.NarrowKey,ExactKey(Bits)) and
    (N.RootIndex=0) and (N.ParentIndex=Parent) and
    (N.ChildIndex=Child) and (N.Depth=Depth),
    'виклична голова не збігається із ратифікованою D3/D5 адресою');
end;


{ Borrowed TWideIRNode: callable D5 head з точними pinned 5 бітами.
  Результат Boolean — host вибір уже перевіреного ADD/SUB emitter,
  НЕ додаткова SENS-ознака або D7-диспетчеризація.
  Керовані Bits/NarrowKey належать WideIR, тут не копіюються.
  Питання: чому ширина рівно 5? Чому перевіряємо HasPinnedKey?
  Чому лише дві координати? Де перевіряється numeric admission? }
function ArithmeticHead(const N:TWideIRNode;
  Parent,Child,Depth:SizeInt):Boolean;
begin
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
    (N.Width=5) and (Length(N.Bits)=5) and
    SameKey(N.NarrowKey,ExactKey(N.Bits)) and
    (N.RootIndex=0) and (N.ParentIndex=Parent) and
    (N.ChildIndex=Child) and (N.Depth=Depth),
    'недопустима точна фізична D5 голова');
  Need(SameKey(N.NarrowKey,ExactKey('01010')) or
       SameKey(N.NarrowKey,ExactKey('01011')),
    'підтримуються тільки pinned D5:01010 і D5:01011');
  Result:=SameKey(N.NarrowKey,ExactKey('01010'));
end;

{ Host-only x86-64 ALU opcode selector після перевірки pinned D5.
  Boolean походить із ArithmeticHead, не з тексту .lisp.
  Result: один байт перевіреного machine opcode, не SENS resident.
  Питання: чому $05 означає EAX ADD imm32? Чому $2D SUB?
  Хто перевіряє незмінність машинного прологу? }
function ExpectedALU(Plus:Boolean):AnsiChar;
begin if Plus then Result:=#$05 else Result:=#$2D end;

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

{ Вхід: одна canonical packed D3:101 фізична програма.
  Два окремі D5-вирази можуть вибирати ADD або SUB кожен:
    (D3:101 (D5:01010|01011 A B) (D5:01010|01011 C D))
  Pinned таблиці й WideIR визначають допуск, numeric D12 закони вже
  реалізовані окремо. Проміжні D24 відхиляються до емісії.
  Result: owned ELF64 PIE, обидва ALU виконуються CPU під час запуску,
  CMP/SETE формує D1. Шаблони беруться лише з уже verified emitter
  і перевіряються побайтово; no D7 чи decimal language dispatch.
  Питання: чому XCHG перед другим ALU? Чому не precomputed D1?
  Навіщо звірка opcode шаблонів? Чому D24 не усікаємо?
  Як незалежний pinned SENS перевіряє 4 комбінаторні форми? }
function BuildIRTwoArithChoiceELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;N:TExplicitNumeric;
    A,B,C,D,LeftValue,RightValue,LeftImage,RightImage,GreaterImage:RawByteString;
    LG,RG,GG,FinalG:TELFGeometry; LeftPlus,RightPlus:Boolean;
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
    (IR.Roots[0]=0),'потрібна одна фізична D3:101 форма з двома D5 піддеревами');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
    (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].RootIndex=0) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'пошкоджений фізичний D2 корінь');
  Head(IR.Nodes[1],'101',0,0,1);
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
    (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
    (IR.Nodes[2].Depth=1) and (IR.Nodes[2].RootIndex=0),
    'лівий аргумент має бути вкладеною D2 арифметикою');
  LeftPlus:=ArithmeticHead(IR.Nodes[3],2,0,2);
  A:=AdmitD12(IR.Nodes[4],2,1,2);
  B:=AdmitD12(IR.Nodes[5],2,2,2);
  Need((IR.Nodes[6].Kind=wkList) and IR.Nodes[6].OwnWord and
    (IR.Nodes[6].ParentIndex=0) and (IR.Nodes[6].ChildIndex=2) and
    (IR.Nodes[6].Depth=1) and (IR.Nodes[6].RootIndex=0),
    'правий аргумент має бути другим вкладеним D2 списком');
  RightPlus:=ArithmeticHead(IR.Nodes[7],6,0,2);
  C:=AdmitD12(IR.Nodes[8],6,1,2);
  D:=AdmitD12(IR.Nodes[9],6,2,2);


  if LeftPlus then LeftValue:=AddNumericPhysical(A,B,12)
              else LeftValue:=SubtractNumericPhysical(A,B,12);
  if RightPlus then RightValue:=AddNumericPhysical(C,D,12)
               else RightValue:=SubtractNumericPhysical(C,D,12);
  try
    N:=ReadNumericPhysical(LeftValue,12);
    Need(N.DomainWidth=12,'ліва арифметика потребує D24');
    N:=ReadNumericPhysical(RightValue,12);
    Need(N.DomainWidth=12,'права арифметика потребує D24');
  except on E:ENumericPlaneError do
    raise EIRTwoArithChoiceError.Create(
      'арифметичний результат не вміщується у D12: '+E.Message);
  end;
  if LeftPlus then LeftImage:=BuildD12AddELF(A,B)
              else LeftImage:=BuildD12SubELF(A,B);
  if RightPlus then RightImage:=BuildD12AddELF(C,D)
               else RightImage:=BuildD12SubELF(C,D);
  GreaterImage:=BuildD12GreaterELF(LeftValue,C);
  VerifySENSELF64(LeftImage,LG);
  VerifySENSELF64(RightImage,RG);
  VerifySENSELF64(GreaterImage,GG);
  Need((LG.Kind=3) and (RG.Kind=3) and (GG.Kind=3) and
    (LG.Entry=HeaderBytes) and (RG.Entry=HeaderBytes) and
    (GG.Entry=HeaderBytes),'потрібні три чинні ELF64 PIE emitter-и');
  Need((Length(LeftImage)>=HeaderBytes+10) and
    (Length(RightImage)>=HeaderBytes+10) and
    (Length(GreaterImage)>=HeaderBytes+17) and
    (LeftImage[HeaderBytes+1]=#$B8) and
    (LeftImage[HeaderBytes+6]= (ExpectedALU(LeftPlus))) and
    (RightImage[HeaderBytes+1]=#$B8) and
    (RightImage[HeaderBytes+6]= (ExpectedALU(RightPlus))) and
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
    Copy(LeftImage,HeaderBytes+1,10)+
    Copy(GreaterImage,HeaderBytes+6,MovBytes)+
    #$91+Copy(RightImage,HeaderBytes+6,ArithmeticBytes)+#$91+
    Copy(GreaterImage,HeaderBytes+11,
      Length(GreaterImage)-HeaderBytes-10);
  Need(Length(Result)=Length(GreaterImage)+12,
    'втрата машинних байтів під час двогілкового lowering SETE');
  { Лише механічна зміна SETG у SETE після повної звірки байтів
    чинного x86-64 шаблону; D3:101 підтверджено вище через
    pinned exact-domain WideIR, не через український напис. }
  Need((Length(Result)>=HeaderBytes+26) and
       (Result[HeaderBytes+26]=#$9F),
       'неочікуваний CMP/SETG host-префікс перед SETE');
  Result[HeaderBytes+26]:=#$94;
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalG);
  Need((FinalG.Kind=3) and (FinalG.Entry=HeaderBytes) and
    (FinalG.FileBytes=Length(Result)),
    'двогілковий ELF64 не пройшов кінцевий guard');
end;
end.
