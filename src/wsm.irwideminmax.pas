{ G6.138 — одинадцятий і дванадцятий фізичні D6 машинні профілі.
  Єдиний мовний авторитет — pinned Contract 12.0, d6.lisp.
  Фізичне D2/T5M джерело -> pinned WideIR -> наявні CMP/CMOV
  генератори BuildD12MinELF / BuildD12MaxELF, без Pascal-мінімуму.
  Входи borrowed RawByteString: canonical packed .sens та root pinned;
  вихід — owned managed RawByteString перевіреного Linux ELF64 PIE.
  TDomainSet, TWideIR та packed bytes живуть до кінця виклику FPC.
  1) Чому в D6:110101 і D6:110111 відрізняються 6 точних бітів?
  2) Чому opaque W12 листок не є числом до D6-допуску?
  3) Чому CMOVG/CMOVL мають виконуватись процесором?
  4) Навіщо повторна перевірка фізичного пакування й ELF?
  5) Хто звільняє керовані масиви та повернений бінарний образ? }
unit wsm.irwideminmax;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideMinMaxError=class(Exception);
function BuildIRWideMinMaxELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12min,wsm.elfd12max,wsm.elfgeometry;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise EIRWideMinMaxError.Create(Why) end;

{ Лише повний вузький D2 список: root + pinned W6 head + два W12.
  Head.HasPinnedKey отримано ТІЛЬКИ з LoadPinnedDomains.
  Параметри IR/Stats запозичені; жодних нових вузлів/реєстрів.
  1) Чому парент-індекси захищають від прихованого вкладення?
  2) Чому однакова довжина W6 не робить іншу голову допустимою?
  3) Чому друга коренева форма є відмовою? }
procedure VerifyForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var N:TWideIRNode;I:SizeInt;
begin
  Need((Stats.Roots=1) and (Stats.Nodes=4) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна D6 форма з двома точними D12');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and (N.Depth=0) and
       (N.ParentIndex=-1) and (N.ChildIndex=0) and
       (N.RootIndex=0),'корінь має бути одним D2 списком');
  N:=IR.Nodes[1];
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
       (N.Width=6) and ((N.Bits='110101') or (N.Bits='110111')) and
       SameKey(N.NarrowKey,ExactKey(N.Bits)) and
       (N.Depth=1) and (N.ParentIndex=0) and
       (N.ChildIndex=0) and (N.RootIndex=0),
       'голова не є pinned D6:110101/110111');
  for I:=2 to 3 do begin
    N:=IR.Nodes[I];
    Need((N.Kind=wkAtom) and N.OwnWord and
         (N.Width=12) and (Length(N.Bits)=12) and
         (not N.HasPinnedKey) and (N.NarrowKey.Width=0) and
         (N.Depth=1) and (N.ParentIndex=0) and
         (N.ChildIndex=I-1) and (N.RootIndex=0),
         'операнди повинні бути двома opaque exact D12 атомами');
  end;
end;

{ Result — окремий owned packed W12 atom із вузла IR.
  Numeric admission явно запитує D12 — ширину не вгадуємо.
  1) Чому індекс W12 не створює окремий D12 закон?
  2) Де перевіряється canonical T5M?
  3) Чи не губиться двійковий знак та провідні нулі? }
function AdmitD12(const N:TWideIRNode):RawByteString;
var W:TExactWords;Value:TExplicitNumeric;
begin
  SetLength(W,1);W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  Value:=ReadNumericPhysical(Result,12);
  Need((Value.DomainWidth=12) and
       (Value.ExactBits=N.Bits),'D12 admission змінив фізичні біти');
end;

function BuildIRWideMinMaxELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;L,R:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'порожня або надмірна фізична програма');
  DecodeT5M(ProgramPhysical,Words);
  Need(EncodeT5M(Words)=ProgramPhysical,'не канонічний T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyForm(IR,Stats);
  L:=AdmitD12(IR.Nodes[2]);
  R:=AdmitD12(IR.Nodes[3]);
  if IR.Nodes[1].Bits='110101' then
    Result:=BuildD12MinELF(L,R)
  else if IR.Nodes[1].Bits='110111' then
    Result:=BuildD12MaxELF(L,R)
  else raise EIRWideMinMaxError.Create('невідомий pinned D6 профіль');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Result)),
       'наявний backend не повернув перевірений ELF64 PIE');
end;
end.
