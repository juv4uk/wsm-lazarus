{ G6.101 — nested фізичні D6:001110 / D6:001111 через verified IR.
  Канонічний вхід — єдина packed D2/T5M форма, 1..16 вкладених
  точних унарних викликів над opaque фізичним D12 атомом.
  Мовні закони визначає лише pinned SENS Contract 12.0; FPC робить
  технічне складання ELF64 PIE, не локальний evaluator/registry. }
unit wsm.irmixedstep;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRMixedStepError=class(Exception);
function BuildIRMixedStepELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.numericsub,
  wsm.elfd12add,wsm.elfd12sub,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; OpBytes=5; MaxSteps=16;

procedure Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EIRMixedStepError.Create(Why);
end;

{ IR — borrowed managed record; Steps 1..16, order from inside out.
  Exact Key W6 is confirmed against pinned Tables[6], not D7 name.
  Shape = [D2-list,W6]×N, opaque W12, total 2*N+1 nodes.
  Pinned leaves count = N W6 heads; opaque leaf count = 1.
  Questions: Чому ширина W6 зберігає провідні нулі?
  Чому підтверджено кожен ParentIndex/ChildIndex?
  Чи заміняє українська назва фізичне зв'язування?
  Чому один зайвий D2-корінь відхиляється? }
procedure VerifyMixedSteps(const IR:TWideIR;
  const Stats:TWideIRGuardStats;const Tables:TDomainSet;
  out Steps:SizeInt);
var N,I,L:SizeInt;Node:TWideIRNode;Row:TDomainRow;K:TDomainKey;
begin
  Steps:=0;
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0) and (Stats.OpaqueLeaves=1) and
       (Stats.Nodes>=3) and (Stats.Nodes<=2*MaxSteps+1) and
       (Stats.Nodes mod 2=1) and
       (Stats.PhysicalLeaves=(Stats.Nodes+1) div 2),
       'потрібен один exact D2 корінь із 1..16 унарних форм');
  N:=(Stats.Nodes-1) div 2;
  for I:=0 to N-1 do begin
    L:=2*I;
    Node:=IR.Nodes[L];
    Need((Node.Kind=wkList) and Node.OwnWord and
         (Node.RootIndex=0) and (Node.Depth=I) and
         (((I=0) and (Node.ParentIndex=-1) and
           (Node.ChildIndex=0)) or
          ((I>0) and (Node.ParentIndex=L-2) and
           (Node.ChildIndex=1))),
         'некоректний фізичний D2 вузол/батько');
    Node:=IR.Nodes[L+1];
    Need((Node.Kind=wkAtom) and Node.OwnWord and
         Node.HasPinnedKey and (Node.RootIndex=0) and
         (Node.Width=6) and
         ((Node.Bits='001110') or (Node.Bits='001111')) and
         (Node.ParentIndex=L) and (Node.ChildIndex=0) and
         (Node.Depth=I+1) and
         SameKey(Node.NarrowKey,ExactKey(Node.Bits)),
         'потрібна лише pinned точна D6 голова кроку');
    K:=ExactKey(Node.Bits);
    Need(DomainRowByKey(Tables[6],K,Row) and SameKey(Row.Key,K),
         'відсутня ратифікована фізична координата D6');
  end;
  Node:=IR.Nodes[2*N];
  Need((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (not Node.HasPinnedKey) and
       (Node.ParentIndex=2*(N-1)) and
       (Node.ChildIndex=1) and (Node.Depth=N) and
       (Node.RootIndex=0),
       'потрібен єдиний opaque фізичний D12 аргумент');
  Steps:=N;
end;

{ Image — FPC-managed owned bytes, Offset — zero-based host ELF64.
  Оновлюємо ЛИШЕ p_filesz і p_memsz після splice машинного прологу;
  по завершенні VerifySENSELF64 перевіряє геометрію.
  Questions: Чому обидві довжини змінюються разом?
  Чому ELF офсети не є мовними адресами?
  Хто звільняє керований RawByteString? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
       'запис ELF поля поза образом');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Physical — borrowed canonical T5M, AuthorityRoot — pinned tables.
  Порядок обчислення: від найглибшої голови до зовнішньої.
  Після кожного кроку наявні числові механізми перевіряють D12.
  Для SUB fast-path додатково потрібен ВХІД >=1 (pinned machine
  profile, не новий закон мови). D12→D24 fail-closed до ELF emission.
  Existing BuildD12{Add,Sub}ELF дають перевірені машинні прологи.
  Result = LastHeader + FirstMOV + N x [ADD/SUB imm32] +
  LastTail(writer+lookup). RIP-relative адреси writer і lookup рухаються
  як цілий блок, тож відстань залишається незмінною.
  Questions: Чому precomputed Numeric є допуском, а не готовим
  машинним результатом? Де справжній SUB для CPU?
  Чому кожен крок перевірено до публікації?
  Як довести N exact opcode у objdump? }
function BuildIRMixedStepELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded,Word:TExactWords;N,I,Head:SizeInt;
    Number:TExplicitNumeric;Current,One,Next,Image:RawByteString;
    Images:array[0..MaxSteps-1] of RawByteString;
    Opcodes:array[0..MaxSteps-1] of AnsiChar;
    Geometry:TELFGeometry;OldLen:SizeInt;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=512),
       'порожня або завелика фізична D6 програма');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,'не канонічне T5M кодування');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyMixedSteps(IR,Stats,Tables,N);
  SetLength(Word,1);Word[0]:=IR.Nodes[2*N].Bits;
  Current:=EncodeT5M(Word);
  Number:=ReadNumericPhysical(Current,12);
  Need((Number.DomainWidth=12) and
       (Number.ExactBits=IR.Nodes[2*N].Bits),
       'відсутній точний числовий D12');
  One:=EncodeNumericDecimal('1',12);
  for I:=0 to N-1 do begin
    Head:=2*(N-1-I)+1;
    if IR.Nodes[Head].Bits='001110' then begin
      Next:=AddNumericPhysical(Current,One,12);
      Opcodes[I]:=#$05;
    end else begin
      Number:=ReadNumericPhysical(Current,12);
      Need((Number.ExactBits[1]='0') and
           (Number.ExactBits<>'000000000000'),
           'машинний fast-path D6 відняти-1 потребує D12 >=1');
      Next:=SubtractNumericPhysical(Current,One,12);
      Opcodes[I]:=#$2D;
    end;
    Number:=ReadNumericPhysical(Next,12);
    Need(Number.DomainWidth=12,'крок потребує D24, не можна звужувати');
    if Opcodes[I]=#$05 then Image:=BuildD12AddELF(Current,One)
    else Image:=BuildD12SubELF(Current,One);
    VerifySENSELF64(Image,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
         (Length(Image)>HeaderBytes+MovBytes+OpBytes) and
         (Image[HeaderBytes+1]=#$B8) and
         (Image[HeaderBytes+MovBytes+1]=Opcodes[I]),
         'пролог чинного машинного D12 backend не підтверджений');
    Images[I]:=Image;
    Current:=Next;
  end;
  if N=1 then Result:=Images[0]
  else begin
    OldLen:=Length(Images[N-1]);
    Need(OldLen<1024*1024-(N-1)*OpBytes,'перевищена host ELF квота');
    Result:=Copy(Images[N-1],1,HeaderBytes)+
      Copy(Images[0],HeaderBytes+1,MovBytes+OpBytes);
    for I:=1 to N-1 do
      Result:=Result+Copy(Images[I],HeaderBytes+MovBytes+1,OpBytes);
    Result:=Result+Copy(Images[N-1],HeaderBytes+MovBytes+OpBytes+1,
      OldLen-HeaderBytes-MovBytes-OpBytes);
    Need(Length(Result)=OldLen+(N-1)*OpBytes,
         'втрачено фізичні байти складеного ELF');
    PutLE64(Result,96,Length(Result));
    PutLE64(Result,104,Length(Result));
  end;
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Result)),
       'складений ELF64 PIE не пройшов перевірку');
end;
end.
