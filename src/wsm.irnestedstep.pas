{ G6.93 — фізична вкладеність D6:001110, один справжній ELF x86-64.
  Єдина семантика: pinned SENS Contract12; тут лише IR та host lowering.
  Глибина 1..5 — вузький host compile profile, НЕ властивість SENS.
  Вхід: canonical packed D2/T5M; вихід: owned ET_DYN ELF байти. }
unit wsm.irnestedstep;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRNestedStepError=class(Exception);
function BuildNestedStepELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.elfd12add,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; AddBytes=5; MaxSteps=5;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRNestedStepError.Create(Why);
end;

{ IR — borrowed managed records, N — 1..5 host compile limit.
  Preorder: [list, exact D6 head] × N, then ONE opaque D12 leaf.
  Head identity — only W6:001110 pinned row, not text 'додати-1'.
  Out Steps stays zero until entire structural form admitted.
  1) Чому кожен list має рівно 2 дітей і preorder?
  2) Що захищає проти іншого D6 слова?
  3) Чому W12 не дає автоматично числової семантики?
  4) Чим nested program відрізняється від п'яти окремих викликів?
  5) Хто перевіряє фізичні addresses кожного IR node? }
procedure VerifyNestedSteps(const IR:TWideIR;
  const Stats:TWideIRGuardStats;out Steps:SizeInt);
var N,I,L,H:SizeInt;Node:TWideIRNode;
begin
  Steps:=0;
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0) and (Stats.OpaqueLeaves=1),
       'потрібна одна фізична D2 програма з одним D12 листком');
  Need((Stats.Nodes>=3) and (Stats.Nodes<=2*MaxSteps+1) and
       (Stats.Nodes mod 2=1) and (Stats.PhysicalLeaves=(Stats.Nodes+1) div 2),
       'неприпустима глибина чи структура вкладених викликів');
  N:=(Stats.Nodes-1) div 2;
  Need((N>=1) and (N<=MaxSteps),'неприпустима глибина');
  for I:=0 to N-1 do begin
    L:=2*I;H:=L+1;
    Node:=IR.Nodes[L];
    Need((Node.Kind=wkList) and Node.OwnWord and (Node.RootIndex=0) and
         (Node.Depth=I) and
         (((I=0) and (Node.ParentIndex=-1) and (Node.ChildIndex=0)) or
          ((I>0) and (Node.ParentIndex=L-2) and (Node.ChildIndex=1))),
         'порушено D2 вкладеність exact списку');
    Node:=IR.Nodes[H];
    Need((Node.Kind=wkAtom) and Node.OwnWord and Node.HasPinnedKey and
         (Node.Width=6) and (Node.Bits='001110') and
         SameKey(Node.NarrowKey,ExactKey('001110')) and
         (Node.ParentIndex=L) and (Node.ChildIndex=0) and
         (Node.Depth=I+1) and (Node.RootIndex=0),
         'потрібна лише pinned D6:001110 як кожна голова');
  end;
  Node:=IR.Nodes[2*N];
  Need((Node.Kind=wkAtom) and Node.OwnWord and (Node.Width=12) and
       (Length(Node.Bits)=12) and (not Node.HasPinnedKey) and
       (Node.ParentIndex=2*(N-1)) and (Node.ChildIndex=1) and
       (Node.Depth=N) and (Node.RootIndex=0),
       'єдиний кінцевий атом повинен мати exact D12');
  Steps:=N;
end;

{ Image — owned FPC managed byte string, offset/size — host ELF64 LE64.
  Механічний ELF layout не стає координатою SENS.
  Питання: чому змінюємо p_filesz і p_memsz одночасно?
  Чому потрібна VerifySENSELF64 після зміни?
  Чому не можна просто склеїти ELF файли? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;V:QWord);
var K:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
       'неприпустимий host ELF offset');
  for K:=0 to 7 do begin
    Image[Offset+K+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

{ Physical — borrowed canonical packed T5M, AuthorityRoot — pinned path.
  Per-step AddNumericPhysical виконує допуск exact D12; кожне
  переповнення, що потребує D24, відхиляється до ELF.
  First має MOV+ADD; Last має ADD+writer. Для N>=2:
  [header Last] + [MOV+ADD First] + (N-2)*[ADD First]
  + [ADD+writer+tables Last].
  RIP-relative зміщення залишаються ті самі, бо весь хвіст рухається
  одночасно; після зшивання незалежний ELF guard.
  1) Чому не можна обчислити тільки фінальне N+1 на хості?
  2) Чому процесор справді виконує N ADD?
  3) Як обмежено код і allocation?
  4) Як забезпечено byte parity фізичного T5M?
  5) Чому CLI ніколи не публікує частковий ELF? }
function BuildNestedStepELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;Steps,I:SizeInt;
    Decoded,Words:TExactWords;Number:TExplicitNumeric;
    Atom,One,Current,Next,FirstELF,LastELF,Image:RawByteString;
    Geometry:TELFGeometry;OldLen:SizeInt;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=512),
       'порожня або завелика фізична D6 програма');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,'не канонічний фізичний T5M');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyNestedSteps(IR,Stats,Steps);
  SetLength(Words,1);
  Words[0]:=IR.Nodes[2*Steps].Bits;
  Atom:=EncodeT5M(Words);
  Number:=ReadNumericPhysical(Atom,12);
  Need((Number.DomainWidth=12) and
       (Number.ExactBits=IR.Nodes[2*Steps].Bits),
       'не підтверджено exact D12 числовий атом');
  One:=EncodeNumericDecimal('1',12);
  Current:=Atom;
  FirstELF:='';LastELF:='';
  for I:=1 to Steps do begin
    { Тільки перевірені існуючі механізми задають numeric promotion. }
    Next:=AddNumericPhysical(Current,One,12);
    Number:=ReadNumericPhysical(Next,12);
    Need(Number.DomainWidth=12,'крок потребує D24, вузький профіль відхиляє');
    Image:=BuildD12AddELF(Current,One);
    VerifySENSELF64(Image,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
         (Length(Image)>HeaderBytes+MovBytes+AddBytes) and
         (Image[HeaderBytes+1]=#$B8) and (Image[HeaderBytes+6]=#$05),
         'машинний D12 ADD emitter змінив точний пролог');
    if I=1 then FirstELF:=Image;
    if I=Steps then LastELF:=Image;
    Current:=Next;
  end;
  if Steps=1 then Result:=FirstELF
  else begin
    OldLen:=Length(LastELF);
    Need(OldLen<1024*1024-(Steps-1)*AddBytes,'перевищено ELF квоту');
    Result:=Copy(LastELF,1,HeaderBytes)+
      Copy(FirstELF,HeaderBytes+1,MovBytes+AddBytes);
    for I:=1 to Steps-2 do
      Result:=Result+Copy(FirstELF,HeaderBytes+MovBytes+1,AddBytes);
    Result:=Result+Copy(LastELF,HeaderBytes+MovBytes+1,
      OldLen-HeaderBytes-MovBytes);
    Need(Length(Result)=OldLen+(Steps-1)*AddBytes,
         'втрачено фізичні машинні байти');
    PutLE64(Result,96,Length(Result));
    PutLE64(Result,104,Length(Result));
  end;
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Result)),
       'складений PIE ELF64 не пройшов перевірку');
end;
end.
