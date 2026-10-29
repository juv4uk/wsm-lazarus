{ G6.125 — СПРАВЖНІ дві незалежні D5 множення + одне D5 додавання.
  Повна packed фізична D2/T5M:
   (D5:01010 (D5:10110 W12 W12) (D5:10110 W12 W12)).
  SENS Contract 12 / pinned lib/domains/d5.lisp — єдиний закон.
  Native machine: IMUL EAX; IMUL ECX; ADD EAX,ECX; T5M D12/D24 writer.
  Жоден готовий результат не кладеться у вихідний ELF. }
unit wsm.irtwomuladd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRTwoMulAddError=class(Exception);
function BuildIRTwoMulAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericmul,wsm.numericadd,
  wsm.elfd12mul,wsm.elfd12add,wsm.elfd12promote,wsm.elfgeometry,
  wsm.x64code,wsm.x64alu;

const HeaderBytes=120; OriginalPrefix=10; NewPrefix=24;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRTwoMulAddError.Create(Why);
end;

{ Позичений TWideIR — 10 preorder вузлів, чотири opaque W12.
  При відмові жоден операнд чи ELF не публікується. Pinned domain+bits
  обов'язкові; текстове «додати» ніколи не є dispatch.
  1) Чому вузлів рівно 10, а не 9?
  2) Чому Head має одночасно Width=5 та HasPinnedKey?
  3) Чому дві дочірні D2 структури не можна міняти на dotted pair?
  4) Чому фізична ширина W12 сама не визначає число?
  5) Хто володіє вузлами після виходу BuildIRTwoMulAddELF? }
procedure VerifyForm(const IR:TWideIR;const Stats:TWideIRGuardStats;
  const Tables:TDomainSet);
var I:SizeInt;N:TWideIRNode;Key:TDomainKey;Row:TDomainRow;
  procedure ListNode(Index,Parent,Child,Depth:SizeInt);
  var L:TWideIRNode;
  begin
    L:=IR.Nodes[Index];
    Need((L.Kind=wkList) and L.OwnWord and
      (L.ParentIndex=Parent) and (L.ChildIndex=Child) and
      (L.Depth=Depth) and (L.RootIndex=0),
      'пошкоджена фізична D2 структура');
  end;
  procedure HeadNode(Index,Parent,Child,Depth:SizeInt;
    const Bits:RawByteString);
  var H:TWideIRNode;
  begin
    H:=IR.Nodes[Index]; Key:=ExactKey(Bits);
    Need((H.Kind=wkAtom) and H.OwnWord and H.HasPinnedKey and
      (H.Width=5) and (H.Bits=Bits) and
      SameKey(H.NarrowKey,Key) and
      (H.ParentIndex=Parent) and (H.ChildIndex=Child) and
      (H.Depth=Depth) and (H.RootIndex=0) and
      DomainRowByKey(Tables[5],Key,Row) and SameKey(Row.Key,Key),
      'голова не є exact ратифікованою D5');
  end;
begin
  Need((Stats.Nodes=10) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=7) and (Stats.OpaqueLeaves=4) and
    (Length(IR.Nodes)=10) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0),'потрібен один D5 список із двома множеннями');
  ListNode(0,-1,0,0);
  HeadNode(1,0,0,1,'01010');
  ListNode(2,0,1,1);
  HeadNode(3,2,0,2,'10110');
  ListNode(6,0,2,1);
  HeadNode(7,6,0,2,'10110');
  for I:=0 to 3 do begin
    if I<2 then N:=IR.Nodes[4+I] else N:=IR.Nodes[6+I];
    Need((N.Kind=wkAtom) and N.OwnWord and
      (N.Width=12) and (Length(N.Bits)=12) and
      (not N.HasPinnedKey) and (N.NarrowKey.Width=0) and
      (N.RootIndex=0) and (N.Depth=2) and
      (N.ParentIndex=(2+4*(I div 2))) and
      (N.ChildIndex=1+(I mod 2)),
      'аргумент не є точним opaque W12 у власній гілці');
  end;
end;

{ W12 — borrowed opaque фізичний листок, Result — owned packed T5M
  ОДНОГО явного D12 атома. Ніде не переводимо в D7/decimal мову.
  1) Хто обрав explicit domain D12 у цьому компіляторному профілі?
  2) Чому перевіряємо саме ті самі ExactBits після roundtrip?
  3) Що буде, якщо leaf має 24 біти?
  4) Коли звільниться окремий Result? }
function AdmitD12(const N:TWideIRNode):RawByteString;
var W:TExactWords;Value:TExplicitNumeric;
begin
  SetLength(W,1);W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  Value:=ReadNumericPhysical(Result,12);
  Need((Value.DomainWidth=12) and (Value.ExactBits=N.Bits),
    'втрачено точне D12 при фізичному admission');
end;

{ Owned mutable ELF. Offset — host zero-based byte field, не SENS число.
  Тільки два ELF64 program-header поля після зміни довжини машинного
  прологу. RIP-relative T5M writer і таблиці переміщуються РАЗОМ.
  1) Чому пари p_filesz/p_memsz повинні збігатися?
  2) Чому це не є зміною значення SENS?
  3) Що гарантує наявність 8 байтів за Offset? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var J:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Image)-8),
    'ELF program header поза фізичним образом');
  for J:=0 to 7 do begin
    Image[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Real machine lowering (not host precomputed answer):
  MOV EAX,A; IMUL EAX,EAX,B; MOV ECX,C; IMUL ECX,ECX,D;
  ADD EAX,ECX; verified T5M D12/D24 writer.
  Machine witness for IMUL comes ONLY from already merged BuildD12MulELF;
  ADD register emitted by already merged X64ALU32. No handwritten T5M
  tables or intermediate constant result in ELF.
  Product1/Product2/Sum are short-lived owned numeric T5M W12/W24
  proof-only values. Intermediate D24 is explicitly REJECTED, never
  silently narrowed; final D24 is permitted by existing pinned
  AddNumericPhysical and BuildD12PromotedAddELF.
  1) Чому не можна з'єднати два ELF без спільного вихідного writer?
  2) Чому другий IMUL вимагає ModRM C9 замість C0?
  3) Чому правильна D24 final не дозволяє проміжний D24?
  4) Як пересування LEA та таблиць зберігає RIP relative?
  5) Де SENS REPL перевірить, що готова сума не вшита в ELF? }
function BuildIRTwoMulAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    W:TExactWords;A,B,C,D,P1,P2,Sum,M1,M2,BaseELF:RawByteString;
    N:TExplicitNumeric;G1,G2,GB,GF:TELFGeometry;
    Width,FinalSize:SizeInt;Code:TX64Code;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
    'фізичне джерело порожнє або завелике');
  DecodeT5M(Physical,W);
  Need(EncodeT5M(W)=Physical,'неканонічне packed T5M джерело');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyForm(IR,Stats,Tables);
  A:=AdmitD12(IR.Nodes[4]);B:=AdmitD12(IR.Nodes[5]);
  C:=AdmitD12(IR.Nodes[8]);D:=AdmitD12(IR.Nodes[9]);

  P1:=MultiplyNumericPhysical(A,B,12);
  P2:=MultiplyNumericPhysical(C,D,12);
  N:=ReadNumericPhysical(P1,12);
  Need(N.DomainWidth=12,'ліве множення потребує D24');
  N:=ReadNumericPhysical(P2,12);
  Need(N.DomainWidth=12,'праве множення потребує D24');
  Sum:=AddNumericPhysical(P1,P2,12);
  try N:=ReadNumericPhysical(Sum,12);Width:=12;
  except on E:ENumericPlaneError do begin
    N:=ReadNumericPhysical(Sum,24);Width:=24;
  end end;
  Need((N.DomainWidth=Width) and (Length(N.ExactBits)=Width),
    'кінцевий результат не є точним D12 або D24');

  M1:=BuildD12MulELF(A,B);M2:=BuildD12MulELF(C,D);
  if Width=12 then BaseELF:=BuildD12AddELF(P1,P2)
              else BaseELF:=BuildD12PromotedAddELF(P1,P2);
  VerifySENSELF64(M1,G1);VerifySENSELF64(M2,G2);
  VerifySENSELF64(BaseELF,GB);
  Need((G1.Kind=3) and (G2.Kind=3) and (GB.Kind=3) and
    (G1.Entry=HeaderBytes) and (G2.Entry=HeaderBytes) and
    (GB.Entry=HeaderBytes),
    'донорські механізми не є ELF64 PIE');
  Need((Length(M1)>=HeaderBytes+11) and
    (Length(M2)>=HeaderBytes+11) and
    (Length(BaseELF)>HeaderBytes+OriginalPrefix) and
    (M1[HeaderBytes+1]=#$B8) and (M1[HeaderBytes+6]=#$69) and
    (M1[HeaderBytes+7]=#$C0) and
    (M2[HeaderBytes+1]=#$B8) and (M2[HeaderBytes+6]=#$69) and
    (M2[HeaderBytes+7]=#$C0) and
    (BaseELF[HeaderBytes+1]=#$B8) and
    (BaseELF[HeaderBytes+6]=#$05),
    'неочікуваний MOV/IMUL/ADD донорський machine prefix');
  X64Reset(Code);
  Code.Bytes:=Copy(M1,HeaderBytes+1,11)+
    #$B9+Copy(M2,HeaderBytes+2,4)+
    #$69#$C9+Copy(M2,HeaderBytes+8,4);
  Need(Length(Code.Bytes)=22,'втрачено байти двох незалежних IMUL');
  X64ALU32(Code,xaAdd,xrAX,xrCX);
  Need((Length(Code.Bytes)=NewPrefix) and
    (Copy(Code.Bytes,23,2)=#$01#$C8),
    'неправильний машинний ADD EAX,ECX');

  FinalSize:=Length(BaseELF)+NewPrefix-OriginalPrefix;
  Need((FinalSize>HeaderBytes+NewPrefix) and (FinalSize<=1024*1024),
    'ELF64 переповнив фізичну квоту');
  Result:=Copy(BaseELF,1,HeaderBytes)+Code.Bytes+
    Copy(BaseELF,HeaderBytes+OriginalPrefix+1,
      Length(BaseELF)-HeaderBytes-OriginalPrefix);
  Need(Length(Result)=FinalSize,'неправильне склеювання machine + writer');
  PutLE64(Result,96,FinalSize);
  PutLE64(Result,104,FinalSize);
  VerifySENSELF64(Result,GF);
  Need((GF.Kind=3) and (GF.Entry=HeaderBytes) and
    (GF.FileBytes=FinalSize),
    'після подвійного IMUL ELF64 не пройшов незалежну геометрію');
end;
end.
