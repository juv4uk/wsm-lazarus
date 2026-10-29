{ G6.141: 1..16 ПРАВОВКЛАДЕНИХ D5 ADD/SUB. Єдині закони —
  pinned external/sens Contract12. Host x86 механіка запозичує MOV,
  ADD і повний T5M writer з уже перевіреного BuildD12AddELF.
  Це не interpreter і не перелік мовних імен. }
unit wsm.irarithpravy;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRArithPravyError=class(Exception);
function BuildIRArithPravyELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.numericsub,
  wsm.elfd12add,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; StepBytes=5;
      NegBytes=2; MaxSteps=16; MaxBytes=8192;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRArithPravyError.Create(Why) end;

{ IR — borrowed managed TWideIR. Правовкладений preorder:
  (D5 LEFT (D5 LEFT ... BASE)): N вузлів list (3*i), N pinned
  голів (3*i+1), N opaque LEFT (3*i+2), BASE в кінці (3*N).
  Ownership IR лишається BuildWideIR, Steps out=0 до повного admission.
  Питання: чому ChildIndex=2 для вкладеного списку?
  Чому не можна переставити аргументи віднімання?
  Чому W12 без pinned D5 голови не автоматично число?
  Чому жоден текст D7 не обирає machine backend? }
procedure VerifyRight(const IR:TWideIR;const S:TWideIRGuardStats;
  const Tables:TDomainSet;out Steps:SizeInt);
var I,N,L:SizeInt;Node:TWideIRNode;K:TDomainKey;R:TDomainRow;
begin
  Steps:=0;
  Need((S.Roots=1) and (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (S.Nodes>=4) and (S.Nodes<=3*MaxSteps+1) and
    ((S.Nodes-1) mod 3=0) and
    (Length(IR.Nodes)=S.Nodes),'потрібна 1..16-крокова D5 форма');
  N:=(S.Nodes-1) div 3;
  Need((S.PhysicalLeaves=2*N+1) and (S.OpaqueLeaves=N+1),
    'непогоджені фізичні D5/D12 листки');
  for I:=0 to N-1 do begin
    L:=3*I;Node:=IR.Nodes[L];
    Need((Node.Kind=wkList) and Node.OwnWord and
      (Node.Depth=I) and (Node.RootIndex=0) and
      (((I=0) and (Node.ParentIndex=-1) and (Node.ChildIndex=0)) or
       ((I>0) and (Node.ParentIndex=L-3) and (Node.ChildIndex=2))),
      'порушено праву вкладеність D2');
    Node:=IR.Nodes[L+1];
    Need((Node.Kind=wkAtom) and Node.OwnWord and Node.HasPinnedKey and
      (Node.Width=5) and ((Node.Bits='01010') or (Node.Bits='01011')) and
      (Node.ParentIndex=L) and (Node.ChildIndex=0) and
      (Node.Depth=I+1) and (Node.RootIndex=0) and
      SameKey(Node.NarrowKey,ExactKey(Node.Bits)),
      'непідтверджена pinned D5 голова');
    K:=ExactKey(Node.Bits);
    Need(DomainRowByKey(Tables[5],K,R) and SameKey(R.Key,K),
      'не знайдено точний ратифікований D5 закон');
    Node:=IR.Nodes[L+2];
    Need((Node.Kind=wkAtom) and Node.OwnWord and (Node.Width=12) and
      (Length(Node.Bits)=12) and (not Node.HasPinnedKey) and
      (Node.ParentIndex=L) and (Node.ChildIndex=1) and
      (Node.Depth=I+1) and (Node.RootIndex=0),
      'лівий аргумент не exact opaque W12');
  end;
  Node:=IR.Nodes[3*N];
  Need((Node.Kind=wkAtom) and Node.OwnWord and (Node.Width=12) and
    (Length(Node.Bits)=12) and (not Node.HasPinnedKey) and
    (Node.ParentIndex=3*(N-1)) and (Node.ChildIndex=2) and
    (Node.Depth=N) and (Node.RootIndex=0),
    'база правої вкладеності не exact W12');
  Steps:=N;
end;

function Atom12(const Bits:RawByteString):RawByteString;
var W:TExactWords;X:TExplicitNumeric;
begin
  Need(Length(Bits)=12,'не exact W12');
  SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W);
  X:=ReadNumericPhysical(Result,12);
  Need((X.DomainWidth=12) and (X.ExactBits=Bits),
    'числовий D12 допуск не підтверджено');
end;

procedure PutLE64(var B:RawByteString;At:SizeInt;X:QWord);
var I:SizeInt;
begin
  Need((At>=0) and (At<=Length(B)-8),'поза ELF64 заголовком');
  for I:=0 to 7 do begin
    B[At+I+1]:=AnsiChar(Byte(X and $FF));X:=X shr 8;
  end;
end;

{ Physical borrowed T5M; ELF returned owned RawByteString.
  Steps[0..N-1] — власні 5/7 машинних байтів у FPC managed memory.
  Числові результати перевіряє наявний pinned D12 numeric gate,
  а процесор РЕАЛЬНО виконує усі N операцій із базового MOV EAX.
  Для LEFT−EAX: NEG EAX; ADD EAX,signextend(LEFT), не SUB EAX,LEFT.
  MOV/ADD і вихідний T5M writer запозичені з BuildD12AddELF і
  кожного разу структурно звірені. Таблиці й RIP-relative LEA
  переміщуються разом із suffix, тому displacement незмінний.
  Питання: чому NEG для правовкладеного SUB стоїть ПЕРЕД ADD?
  Чому знак W12 зберігається в EAX, хоча там 32 біти?
  Чому 2048 після NEG може бути host проміжним, але не D12 результатом?
  Чому D12→D24 не обрізаємо, а відхиляємо?
  Кому належить memory Image після return? }
function BuildIRArithPravyELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;S:TWideIRGuardStats;
    Words:TExactWords;N,I:SizeInt;Zero,Current,Left,Next,Donor,BaseImage:RawByteString;
    Ops:RawByteString;G:TELFGeometry;X:TExplicitNumeric;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=MaxBytes),
    'порожня або завелика canonical .sens форма');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'неканонічний фізичний T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,S);
  VerifyRight(IR,S,Tables,N);
  Zero:=Atom12('000000000000');
  Current:=Atom12(IR.Nodes[3*N].Bits);
  BaseImage:=BuildD12AddELF(Current,Zero);
  VerifySENSELF64(BaseImage,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (Length(BaseImage)>HeaderBytes+MovBytes+StepBytes) and
    (BaseImage[HeaderBytes+1]=#$B8) and
    (BaseImage[HeaderBytes+MovBytes+1]=#$05) and
    (BaseImage[HeaderBytes+MovBytes+StepBytes+1]=#$25),
    'змінено byte-exact шаблон наявного ELF D12 ADD');
  Ops:='';
  for I:=N-1 downto 0 do begin
    Left:=Atom12(IR.Nodes[3*I+2].Bits);
    if IR.Nodes[3*I+1].Bits='01010' then
      Next:=AddNumericPhysical(Left,Current,12)
    else
      Next:=SubtractNumericPhysical(Left,Current,12);
    X:=ReadNumericPhysical(Next,12); { D24 promotion = fail-closed }
    Need((X.DomainWidth=12) and (Length(X.ExactBits)=12),
      'правовкладена операція вийшла за точний D12');
    { Donor(0,left) потрібен ЛИШЕ для доказового машинного immed32,
      не для заміни результату Pascal-ready числом. }
    Donor:=BuildD12AddELF(Zero,Left);
    VerifySENSELF64(Donor,G);
    Need((G.Kind=3) and (G.Entry=HeaderBytes) and
      (Length(Donor)=Length(BaseImage)) and
      (Donor[HeaderBytes+1]=#$B8) and
      (Donor[HeaderBytes+MovBytes+1]=#$05) and
      (Copy(Donor,HeaderBytes+MovBytes+StepBytes+1,
        Length(Donor)-HeaderBytes-MovBytes-StepBytes)=
       Copy(BaseImage,HeaderBytes+MovBytes+StepBytes+1,
        Length(BaseImage)-HeaderBytes-MovBytes-StepBytes)),
      'невідповідний машинний ADD донор');
    if IR.Nodes[3*I+1].Bits='01011' then
      Ops:=Ops+#$F7#$D8; { x86 NEG EAX: host-операція }
    Ops:=Ops+Copy(Donor,HeaderBytes+MovBytes+1,StepBytes);
    Current:=Next;
  end;
  Result:=Copy(BaseImage,1,HeaderBytes+MovBytes)+Ops+
    Copy(BaseImage,HeaderBytes+MovBytes+StepBytes+1,
      Length(BaseImage)-HeaderBytes-MovBytes-StepBytes);
  Need((Length(Result)=Length(BaseImage)-StepBytes+Length(Ops)) and
    (Length(Ops)>=N*StepBytes) and
    (Length(Ops)<=N*(StepBytes+NegBytes)),
    'збій машинного складання правого дерева');
  PutLE64(Result,96,Length(Result));PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)),
    'невірна геометрія остаточного machine ELF64 PIE');
end;
end.
