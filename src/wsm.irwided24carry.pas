{ G6.257 — повна фізична D5:01010(D24,D24) через verified WideIR.
  Точний закон є ЛИШЕ pinned SENS, тут — перевірка доступного
  виклику та передача двох фізичних opaque D24 атомів уже перевіреному
  машинному ADD/ADC. Немає людського dispatch або власного реєстру.
  ProgramPhysical — позичений packed T5M; AuthorityRoot — шлях pinned
  таблиць; Result — власний verified ELF64 PIE (managed RawByteString).
  Контекст належить цьому виклику і звільняється у finally.
  Запитання:
  1) Чому W24 не вважаємо числом до допуску голови D5:01010?
  2) Чому одноразовий контекст повинен відмовити на іншій голові?
  3) Чому числові байти не можна отримати з проєкції en?
  4) Хто перевіряє фізичний provenance кореня D2?
  5) Чому success ELF не означає загальну підтримку Core1? }
unit wsm.irwided24carry;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideD24Carry=class(Exception);
function BuildIRWideD24CarryELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.wideir,wsm.wideirguard,wsm.domain,
     wsm.verifiedwidecontext,wsm.numericplane,wsm.elfd24carry;

procedure Require(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRWideD24Carry.Create(Why);
end;

{ N — позичений validated opaque WideIR leaf.
  EncodeT5M віддає новий canonical атом, а ReadNumericPhysical повторно
  перевіряє саме D24; назва проєкції й десятковий рядок не беруть участі.
  Власність Result — managed FPC; час життя завершує викликач. }
function CheckedD24Atom(const N:TWideIRNode):RawByteString;
var W:TExactWords;Value:TExplicitNumeric;
begin
  Require((N.Kind=wkAtom) and N.OwnWord and (N.Width=24) and
          (Length(N.Bits)=24) and (not N.HasPinnedKey) and
          (N.NarrowKey.Width=0) and (N.NarrowKey.Bits=0),
          'потрібен непрозорий фізичний W24 атом');
  SetLength(W,1);
  W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  Value:=ReadNumericPhysical(Result,24);
  Require((Value.DomainWidth=24) and (Value.ExactBits=N.Bits),
          'не збережено фізичне двійкове D24 слово');
end;

{ Інваріанти структури встановив TVerifiedWideContext, тут перевіряємо
  вузьку форму допуску: рівно 1 голова pinned D5:01010 і два opaque
  W24 листки, без додаткових даних та гілок. Ні SENS evaluation, ні
  таблиця законів тут не з'являються. Host T5M результат ELF створює
  незмінений donor wsm.elfd24carry. }
function LowerD24(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var Head:TWideIRNode;LeftAtom,RightAtom:RawByteString;I:SizeInt;
begin
  Result:='';
  Require((Stats.Roots=1) and (Stats.Nodes=4) and
          (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
          (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
          (Length(IR.Nodes)=4),'потрібна одна D5 форма з двома D24');
  Require((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
          (IR.Nodes[0].ParentIndex=-1) and
          (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].Depth=0),
          'неправильний фізичний корінь D2');
  Head:=IR.Nodes[1];
  Require((Head.Kind=wkAtom) and Head.OwnWord and
          Head.HasPinnedKey and (Head.Width=5) and
          (Head.Bits='01010') and
          SameKey(Head.NarrowKey,ExactKey('01010')) and
          (Head.ParentIndex=0) and (Head.ChildIndex=0) and
          (Head.Depth=1) and (Head.RootIndex=0),
          'голова не є ратифікованим D5:01010');
  for I:=2 to 3 do
    Require((IR.Nodes[I].Kind=wkAtom) and IR.Nodes[I].OwnWord and
            (IR.Nodes[I].ParentIndex=0) and
            (IR.Nodes[I].ChildIndex=I-1) and
            (IR.Nodes[I].Depth=1) and (IR.Nodes[I].RootIndex=0),
            'неправильний фізичний порядок двох атомів');
  LeftAtom:=CheckedD24Atom(IR.Nodes[2]);
  RightAtom:=CheckedD24Atom(IR.Nodes[3]);
  Result:=BuildD24CarryAddELF(LeftAtom,RightAtom);
end;

{ Новий verified context на КОЖЕН виклик, callback лише один раз.
  Контекст читає canonical T5M, pinned D1..D9, WideIR + structural
  guard. Жоден текстовий рядок .lisp не видається за source байти. }
function BuildIRWideD24CarryELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Context:TVerifiedWideContext;
begin
  Result:='';
  Context:=TVerifiedWideContext.Create(ProgramPhysical,AuthorityRoot);
  try
    Result:=Context.Lower(@LowerD24);
  finally
    Context.Free;
  end;
end;
end.
