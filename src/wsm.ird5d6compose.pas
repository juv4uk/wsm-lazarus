{ G6.106 — справжня міждоменна SENS-компіляція:
  (D5:01010/01011 (D6:001110/001111 D12) D12) → один ELF64 PIE.
  Доменні закони — лише pinned external/sens Contract 12.0.
  Текстові проєкції не визначають викличність. Обмежений exact D12
  host profile, не універсальний компілятор. }
unit wsm.ird5d6compose;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRComposeError=class(Exception);
function BuildIRComposedD5D6ELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
  wsm.numericplane,wsm.numericadd,wsm.numericsub,
  wsm.elfd12add,wsm.elfd12sub,wsm.elfgeometry;
const HeaderBytes=120;MovBytes=5;AluBytes=5;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRComposeError.Create(Why);
end;

{ IR — керовані borrowed nodes, Tables — короткоживучий pinned
  authority; це рівно 6 preorder вузлів:
  0 list D5, 1 W5 head, 2 list D6, 3 W6 head,
  4 opaque W12 base, 5 opaque W12 right.
  Питання: чому дві фізичні W12 не є числом без pinned контексту?
  Чому структура D2 та ChildIndex перевіряється окремо?
  Чому W5 та W6 не можна порівнювати тільки за host integer?
  Хто перевіряє physical spans усіх шести вузлів? }
procedure VerifyComposition(const IR:TWideIR;
  const Stats:TWideIRGuardStats;const Tables:TDomainSet);
  procedure Head(Index,Width,Parent,Depth:SizeInt;
    const A,B:RawByteString);
  var N:TWideIRNode;K:TDomainKey;Row:TDomainRow;
  begin
    N:=IR.Nodes[Index];
    Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
      (N.Width=Width) and ((N.Bits=A) or (N.Bits=B)) and
      (N.ParentIndex=Parent) and (N.ChildIndex=0) and
      (N.Depth=Depth) and (N.RootIndex=0) and
      SameKey(N.NarrowKey,ExactKey(N.Bits)),
      'підмінена фізична ратифікована голова D5/D6');
    K:=ExactKey(N.Bits);
    Need(DomainRowByKey(Tables[Width],K,Row) and SameKey(Row.Key,K),
      'відсутня pinned D5/D6 координата');
  end;
  procedure NumericLeaf(Index,Parent,Child,Depth:SizeInt);
  var N:TWideIRNode;
  begin
    N:=IR.Nodes[Index];
    Need((N.Kind=wkAtom) and N.OwnWord and
      (N.Width=12) and (Length(N.Bits)=12) and
      (not N.HasPinnedKey) and (N.ParentIndex=Parent) and
      (N.ChildIndex=Child) and (N.Depth=Depth) and
      (N.RootIndex=0),'числовий аргумент мусить бути opaque exact W12');
  end;
var N:TWideIRNode;
begin
  Need((Stats.Nodes=6) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=4) and (Stats.OpaqueLeaves=2) and
       (Stats.MaxDepth=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=6),
       'потрібен один канонічний D5(D6 D12) D12 вираз');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and (N.ParentIndex=-1) and
       (N.ChildIndex=0) and (N.Depth=0) and (N.RootIndex=0),
       'зовнішня D2 форма не є коренем');
  Head(1,5,0,1,'01010','01011');
  N:=IR.Nodes[2];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.ParentIndex=0) and (N.ChildIndex=1) and
       (N.Depth=1) and (N.RootIndex=0),
       'лівий аргумент D5 не є вкладеною D6 формою');
  Head(3,6,2,2,'001110','001111');
  NumericLeaf(4,2,1,2);
  NumericLeaf(5,0,2,1);
end;

{ ELF Image — owned RawByteString, Offset 0-based host LE64 field.
  Змінюємо лише p_filesz/p_memsz після вставки ДРУГОЇ ALU інструкції.
  Питання: чому переміщуємо writer та lookup-таблиці разом?
  Чому це не змінює їх RIP-relative відстані?
  Чому повторно перевіряємо фінальну ELF геометрію? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
       'ELF поле за межею фізичного образу');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Canonical Physical — borrowed packed T5M; числові атоми/ELF — owned
  RawByteString, звільняються FPC після повернення.
  1) D6 inner stage — signed D12 +1/-1, для SUB fastpath base>=1.
  2) D5 outer stage — signed D12 +/- окремий signed D12 right.
  3) Перевірені numeric gates відхиляють D12→D24 ДО emission.
  4) Existing BuildD12{Add,Sub}ELF — фактичний ISA witness.
  5) Один ELF: [outer ELF header][inner MOV+ALU][outer ALU+writer].
  Два машинних ALU виконуються CPU; готову відповідь не записуємо.
  Питання: хто перевіряє окремо обидва проміжні значення?
  Чому перший MOV походить саме із inner emitter?
  Як машинний disassembly доводить порядок D6→D5?
  Чому українські назви тут тільки у документації/діагностиці?
  Що відбувається при спробі повторно опублікувати ELF? }
function BuildIRComposedD5D6ELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words,OneWord:TExactWords;N:TExplicitNumeric;
    Base,Right,One,Middle,FinalValue:RawByteString;
    InnerELF,OuterELF:RawByteString;
    InnerOpcode,OuterOpcode:AnsiChar;
    InnerGeometry,OuterGeometry,FinalGeometry:TELFGeometry;
    OldLength:SizeInt;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=256),
       'порожня або завелика фізична програма D5/D6');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'порушено canonical фізичне T5M');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyComposition(IR,Stats,Tables);
  SetLength(OneWord,1);
  OneWord[0]:=IR.Nodes[4].Bits;
  Base:=EncodeT5M(OneWord);
  OneWord[0]:=IR.Nodes[5].Bits;
  Right:=EncodeT5M(OneWord);
  N:=ReadNumericPhysical(Base,12);
  Need((N.DomainWidth=12) and (N.ExactBits=IR.Nodes[4].Bits),
       'не підтверджено базове exact D12 число');
  N:=ReadNumericPhysical(Right,12);
  Need((N.DomainWidth=12) and (N.ExactBits=IR.Nodes[5].Bits),
       'не підтверджено праве exact D12 число');
  One:=EncodeNumericDecimal('1',12);
  if IR.Nodes[3].Bits='001110' then begin
    Middle:=AddNumericPhysical(Base,One,12);
    InnerOpcode:=#$05;
  end else begin
    N:=ReadNumericPhysical(Base,12);
    Need((N.ExactBits[1]='0') and
         (N.ExactBits<>'000000000000'),
         'pinned CPU D6 відняти-1 fastpath потребує D12 >=1');
    Middle:=SubtractNumericPhysical(Base,One,12);
    InnerOpcode:=#$2D;
  end;
  N:=ReadNumericPhysical(Middle,12);
  Need(N.DomainWidth=12,'вкладений D6 крок потребує D24');
  if InnerOpcode=#$05 then
    InnerELF:=BuildD12AddELF(Base,One)
  else
    InnerELF:=BuildD12SubELF(Base,One);
  if IR.Nodes[1].Bits='01010' then begin
    FinalValue:=AddNumericPhysical(Middle,Right,12);
    OuterOpcode:=#$05;
  end else begin
    FinalValue:=SubtractNumericPhysical(Middle,Right,12);
    OuterOpcode:=#$2D;
  end;
  N:=ReadNumericPhysical(FinalValue,12);
  Need(N.DomainWidth=12,'зовнішній D5 крок потребує D24');
  if OuterOpcode=#$05 then
    OuterELF:=BuildD12AddELF(Middle,Right)
  else
    OuterELF:=BuildD12SubELF(Middle,Right);
  VerifySENSELF64(InnerELF,InnerGeometry);
  VerifySENSELF64(OuterELF,OuterGeometry);
  Need((InnerGeometry.Kind=3) and (OuterGeometry.Kind=3) and
       (InnerGeometry.Entry=HeaderBytes) and
       (OuterGeometry.Entry=HeaderBytes) and
       (Length(InnerELF)>=HeaderBytes+10) and
       (Length(OuterELF)>=HeaderBytes+10) and
       (InnerELF[HeaderBytes+1]=#$B8) and
       (OuterELF[HeaderBytes+1]=#$B8) and
       (InnerELF[HeaderBytes+MovBytes+1]=InnerOpcode) and
       (OuterELF[HeaderBytes+MovBytes+1]=OuterOpcode),
       'машинний пролог чинних D12 backend не підтверджений');
  OldLength:=Length(OuterELF);
  Need(OldLength<1024*1024-AluBytes,'перевищено ELF квоту');
  Result:=Copy(OuterELF,1,HeaderBytes)+
    Copy(InnerELF,HeaderBytes+1,MovBytes+AluBytes)+
    Copy(OuterELF,HeaderBytes+MovBytes+1,
      OldLength-HeaderBytes-MovBytes);
  Need(Length(Result)=OldLength+AluBytes,
       'втрачено фізичні machine bytes');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
       (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=Length(Result)),
       'остаточний PIE ELF64 не пройшов геометрію');
end;
end.
