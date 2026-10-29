{ G6.97 / G6.137 — одна canonical фізична D2 програма з 1..8 вкладених
  бінарних D5:01010 / D5:01011 та своїм D12 правим аргументом.
  Мовна authority лише pinned SENS Contract 12.0; FPC — механіка.
  Результат — owned ELF64 PIE з N машинними ADD/SUB і T5M stdout. }
unit wsm.irarithchain;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRArithChainError=class(Exception);
function BuildIRArithChainELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.numericsub,
  wsm.elfd12add,wsm.elfd12sub,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; StepBytes=5; MaxSteps=8;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRArithChainError.Create(Why);
end;

{ IR — managed і позичений. Preorder:
  [D2 list, pinned W5 head] × N, один W12 base,
  N окремих opaque W12 правих аргументів (від inner до outer).
  G6.137: межа N=8 лише квота механічної композиції, не новий
  мовний домен або закон; кожну голову знову посвідчує pinned D5.
  Ратифіковані координати звіряємо з pinned Tables[5].
  Out Steps залишається 0 аж до успішного допуску.
  Питання: чому 3*N+1 вузлів? Чому W12 opaque?
  Чому ParentIndex і ChildIndex важливіші за текстову назву?
  Чому другий корінь не можна проігнорувати? }
procedure VerifyChain(const IR:TWideIR;const Stats:TWideIRGuardStats;
  const Tables:TDomainSet;out Steps:SizeInt);
var N,I,L,H,Arg:SizeInt;Node:TWideIRNode;K:TDomainKey;Row:TDomainRow;
begin
  Steps:=0;
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Stats.Nodes>=4) and (Stats.Nodes<=3*MaxSteps+1) and
       ((Stats.Nodes-1) mod 3=0),
       'потрібна одна вкладена D5 програма з 1..8 кроків');
  N:=(Stats.Nodes-1) div 3;
  Need((Stats.PhysicalLeaves=2*N+1) and (Stats.OpaqueLeaves=N+1),
       'непогоджені D5/D12 фізичні листки');
  for I:=0 to N-1 do begin
    L:=2*I;H:=L+1;
    Node:=IR.Nodes[L];
    Need((Node.Kind=wkList) and Node.OwnWord and (Node.Depth=I) and
         (Node.RootIndex=0) and
         (((I=0) and (Node.ParentIndex=-1) and (Node.ChildIndex=0)) or
          ((I>0) and (Node.ParentIndex=L-2) and (Node.ChildIndex=1))),
         'порушена вкладеність exact D2 списку');
    Node:=IR.Nodes[H];
    Need((Node.Kind=wkAtom) and Node.OwnWord and Node.HasPinnedKey and
         (Node.Width=5) and
         ((Node.Bits='01010') or (Node.Bits='01011')) and
         (Node.ParentIndex=L) and (Node.ChildIndex=0) and
         (Node.Depth=I+1) and (Node.RootIndex=0) and
         SameKey(Node.NarrowKey,ExactKey(Node.Bits)),
         'потрібна exact pinned D5:01010 або D5:01011');
    K:=ExactKey(Node.Bits);
    Need(DomainRowByKey(Tables[5],K,Row) and SameKey(Row.Key,K),
         'не підтверджено pinned D5 закон');
  end;
  Node:=IR.Nodes[2*N];
  Need((Node.Kind=wkAtom) and Node.OwnWord and (Node.Width=12) and
       (not Node.HasPinnedKey) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=2*(N-1)) and (Node.ChildIndex=1) and
       (Node.Depth=N) and (Node.RootIndex=0),
       'один базовий фізичний D12 атом обов’язковий');
  for I:=0 to N-1 do begin
    Arg:=2*N+1+I;
    Node:=IR.Nodes[Arg];
    Need((Node.Kind=wkAtom) and Node.OwnWord and (Node.Width=12) and
         (Length(Node.Bits)=12) and (not Node.HasPinnedKey) and
         (Node.ParentIndex=2*(N-1-I)) and (Node.ChildIndex=2) and
         (Node.Depth=N-I) and (Node.RootIndex=0),
         'кожна D5 голова потребує свого exact D12 правого аргумента');
  end;
  Steps:=N;
end;

{ Вхід Image — owned ELF64 host bytes; LE64 fields at byte offsets.
  Це механічний ELF, не числовий закон мови.
  Питання: що гарантує p_filesz=p_memsz?
  Чому не можна патчити тільки довжину string?
  Чому VerifySENSELF64 викликається після сплайсингу? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
       'поле ELF виходить за межі фізичного образу');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Physical — canonical borrowed packed T5M; AuthorityRoot — pinned path.
  Existing Add/SubNumericPhysical здійснюють КОЖЕН числовий admission.
  D12→D24 promotion — відмова, а не таємне звуження.
  Механічний splice: header від фінального ELF, MOV+OP з першого,
  потім N-1 окремих 5-byte OP із verified emitters, решта фінального
  writer+tables. Усі RIP-relative LEA і таблиці рухаються РАЗОМ.
  Процесор виконує N арифметичних дій; FPC не пише ready-answer literal.
  Питання: чому виконання x86-64 перевіряє більше ніж objdump?
  Де гарантія порядку від inner до outer? Коли вивільняються Images?
  Чому восьмий крок не можна допускати без перевірки проміжного D12?
  Чому 12-бітовий знак не інтерпретується як D7 текст? }
function BuildIRArithChainELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded,AtomWords:TExactWords;N,I,Index:SizeInt;
    Current,Arg,Next,Image:RawByteString;
    Images:array[0..MaxSteps-1] of RawByteString;
    Number:TExplicitNumeric;Geometry:TELFGeometry;OldLen:SizeInt;
    Code:AnsiChar;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=512),
       'порожня або завелика фізична D5 програма');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,'не канонічний фізичний T5M');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyChain(IR,Stats,Tables,N);
  SetLength(AtomWords,1);
  AtomWords[0]:=IR.Nodes[2*N].Bits;
  Current:=EncodeT5M(AtomWords);
  Number:=ReadNumericPhysical(Current,12);
  Need((Number.DomainWidth=12) and
       (Number.ExactBits=IR.Nodes[2*N].Bits),
       'базовий opaque W12 не пройшов D12 numeric admission');
  for I:=0 to N-1 do begin
    AtomWords[0]:=IR.Nodes[2*N+1+I].Bits;
    Arg:=EncodeT5M(AtomWords);
    Number:=ReadNumericPhysical(Arg,12);
    Need((Number.DomainWidth=12) and
         (Number.ExactBits=AtomWords[0]),
         'правий opaque W12 не пройшов D12 numeric admission');
    Index:=2*(N-1-I)+1;
    if IR.Nodes[Index].Bits='01010' then begin
      Next:=AddNumericPhysical(Current,Arg,12);
      Code:=#$05; { host x86-64 ADD EAX,imm32; не SENS opcode }
    end else begin
      Next:=SubtractNumericPhysical(Current,Arg,12);
      Code:=#$2D; { host x86-64 SUB EAX,imm32; не SENS opcode }
    end;
    Number:=ReadNumericPhysical(Next,12);
    Need(Number.DomainWidth=12,'проміжний або фінальний D12→D24 заборонено');
    if Code=#$05 then Image:=BuildD12AddELF(Current,Arg)
    else Image:=BuildD12SubELF(Current,Arg);
    VerifySENSELF64(Image,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
         (Length(Image)>HeaderBytes+MovBytes+StepBytes) and
         (Image[HeaderBytes+1]=#$B8) and
         (Image[HeaderBytes+MovBytes+1]=Code),
         'змінився машинний пролог злитого backend');
    Images[I]:=Image;
    Current:=Next;
  end;
  if N=1 then Result:=Images[0]
  else begin
    OldLen:=Length(Images[N-1]);
    Need(OldLen<1024*1024-(N-1)*StepBytes,'перевищено ELF квоту');
    Result:=Copy(Images[N-1],1,HeaderBytes)+
      Copy(Images[0],HeaderBytes+1,MovBytes+StepBytes);
    for I:=1 to N-1 do
      Result:=Result+Copy(Images[I],HeaderBytes+MovBytes+1,StepBytes);
    Result:=Result+Copy(Images[N-1],HeaderBytes+MovBytes+StepBytes+1,
      OldLen-HeaderBytes-MovBytes-StepBytes);
    Need(Length(Result)=OldLen+(N-1)*StepBytes,
         'втрата фізичних машинних байтів');
    PutLE64(Result,96,Length(Result));
    PutLE64(Result,104,Length(Result));
  end;
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Result)),
       'фінальний ELF64 PIE не пройшов геометрію');
end;
end.
