{ G6.100 — повна packed D2/T5M форма D5:01010(D12,D12)
  → pinned verified WideIR → вже перевірений x86-64 register ALU ELF.
  ЗАКОН ТІЛЬКИ у external/sens Contract12 та lib/domains/d5.lisp;
  цей модуль не визначає numeric add, не виводить домен із байтової
  довжини та не читає людські назви. Поза профілем — fail closed.
  Вхід borrowed RawByteString з фізичними тритами T5M.
  Вихід owned RawByteString ELF64 PIE після VerifySENSELF64.
  1) Чим exact D5 head відрізняється від текстового "додати"?
  2) Чому W12 не є числом аж до перевіреного контексту D5?
  3) Де виявляється D12→D24 overflow?
  4) Хто володіє IR, атомами, отриманим ELF?
  5) Чому успішний WideIR ще не доказ результату машинної арифметики? }
unit wsm.irwideaddreg;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideAddRegError=class(Exception);
function BuildIRWideAddRegisterELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12addreg,wsm.elfgeometry;

procedure Need(Allowed:Boolean;const Why:String);
begin
  if not Allowed then raise EIRWideAddRegError.Create(Why);
end;

{ IR — позичені записи з фізичними span/provenance;
  лише формальний exact D5:01010 має право допустити дві W12.
  Статистика не є semantic law; перевірка арності захищає lowering. }
procedure VerifyPinnedAddForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var I:SizeInt;N:TWideIRNode;
begin
  Need((Stats.Roots=1) and (Stats.Nodes=4) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),'потрібна одна повна D5 форма з двома D12');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.ParentIndex=-1) and (N.ChildIndex=0) and
       (N.Depth=0) and (N.RootIndex=0),
       'некоректний фізичний корінь D2');
  N:=IR.Nodes[1];
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
       (N.Width=5) and (N.Bits='01010') and
       SameKey(N.NarrowKey,ExactKey('01010')) and
       (N.ParentIndex=0) and (N.ChildIndex=0) and
       (N.Depth=1) and (N.RootIndex=0),
       'дозволена тільки ратифікована голова D5:01010');
  for I:=2 to 3 do begin
    N:=IR.Nodes[I];
    Need((N.Kind=wkAtom) and N.OwnWord and (N.Width=12) and
         (Length(N.Bits)=12) and (not N.HasPinnedKey) and
         (N.ParentIndex=0) and (N.ChildIndex=I-1) and
         (N.Depth=1) and (N.RootIndex=0),
         'операнд мусить бути opaque exact W12 листком');
  end;
end;

{ Borrowed IR leaf; Result — owned packed T5M атом, не текст.
  Numerical admission викликаємо ТІЛЬКИ після pinned D5 перевірки.
  Кодер T5M не призначає закон і не змінює провідні нулі. }
function NumericAtom(const N:TWideIRNode):RawByteString;
var Words:TExactWords;Number:TExplicitNumeric;
begin
  SetLength(Words,1);
  Words[0]:=N.Bits;
  Result:=EncodeT5M(Words);
  Number:=ReadNumericPhysical(Result,12);
  Need((Number.DomainWidth=12) and (Number.ExactBits=N.Bits),
       'змінено фізичний D12 під час atom admission');
end;

function BuildIRWideAddRegisterELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded:TExactWords;Left,Right:RawByteString;Geometry:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'порожній або завеликий packed .sens');
  DecodeT5M(ProgramPhysical,Decoded);
  Need(EncodeT5M(Decoded)=ProgramPhysical,
       'пошкоджена канонічність фізичного T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyPinnedAddForm(IR,Stats);
  Left:=NumericAtom(IR.Nodes[2]);
  Right:=NumericAtom(IR.Nodes[3]);
  { Єдиний numeric overflow gate — в існуючому machine backend.
    Цей backend перед ALU emitter вимагає чинне AddNumericPhysical. }
  Result:=BuildD12RegisterAddELF(Left,Right);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Result)),
       'остаточний native ELF64 не пройшов геометрію');
end;
end.
