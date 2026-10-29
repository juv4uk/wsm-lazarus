{ G6.86 — фізична програмна D2/T5M форма D5:01000 «нуль?» над
  одним exact D12 входом → verified WideIR → існуючий native ELF backend.
  Лише pinned Contract12 / D5:01000 / machine profile є семантикою;
  цей unit НЕ створює функцію, opcode, SID8 або регістр законів SENS. }
unit wsm.irwidezero;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideZeroError=class(Exception);
function BuildIRWideZeroELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12zero,wsm.elfgeometry;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EIRWideZeroError.Create(Why);
end;

{ Borrowed TWideIR and its managed Node fields; source is canonical T5M.
  Структурна D5 координата НЕ є людською назвою: pinned ExactKey('01000').
  Листок W12 opaque; явний D12 numeric admission перевірить окремий
  чинний ReadNumericPhysical тільки після повного structural IR proof.
  1) Чому W12 саме по собі не має математичного закону?
  2) Чому потрібні і перевірка IR, і числовий admission?
  3) Чому D5 листок має мати HasPinnedKey, а W12 — не мати?
  4) Де відхиляється другий корінь чи третій аргумент? }
procedure VerifyOnlyZeroForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var Head,Value:TWideIRNode;
begin
  Need((Stats.Nodes=3) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=2) and (Stats.OpaqueLeaves=1) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=3),'потрібна єдина фізична форма D5:01000(D12)');
  Need((IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
       'викличний корінь повинен бути структурою D2');
  Head:=IR.Nodes[1]; Value:=IR.Nodes[2];
  Need((Head.Kind=wkAtom) and Head.HasPinnedKey and
       (Head.Width=5) and (Head.Bits='01000') and
       SameKey(Head.NarrowKey,ExactKey('01000')) and
       (Head.ParentIndex=0) and (Head.ChildIndex=0) and
       (Head.Depth=1) and Head.OwnWord,
       'голова має бути точною ратифікованою D5:01000');
  Need((Value.Kind=wkAtom) and (Value.Width=12) and
       (Length(Value.Bits)=12) and (not Value.HasPinnedKey) and
       (Value.ParentIndex=0) and (Value.ChildIndex=1) and
       (Value.Depth=1) and Value.OwnWord,
       'дозволений тільки один opaque D12 фізичний листок');
end;

{ ProgramPhysical: borrowed canonical D2/T5M bytes, explicit pinned root.
  Result: owned ELF64 ET_DYN managed bytes, не структурне IR-as-result.
  Фізичну D12 координату листка перепаковуємо без проміжного
  текстового/десяткового/англійського перетворення. Лише існуючий
  BuildD12ZeroELF породжує machine TEST/SETE/MOVZX.
  1) Чому тут немає власного x86 emitter?
  2) Чому після EncodeT5M потрібен ReadNumericPhysical?
  3) Чому не можна вивести D1 із True/False Free Pascal?
  4) Хто звільняє керовані масиви IR/Words після return?
  5) Який бар'єр захищає від пошкодженої ELF геометрії? }
function BuildIRWideZeroELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Words:TExactWords; Decoded:TExactWords; Numeric:TExplicitNumeric;
    AtomPhysical:RawByteString; Geometry:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'розмір фізичної програми поза межею');
  DecodeT5M(ProgramPhysical,Decoded);
  Need(EncodeT5M(Decoded)=ProgramPhysical,
    'не канонічне фізичне пакування T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyOnlyZeroForm(IR,Stats);
  SetLength(Words,1);
  Words[0]:=IR.Nodes[2].Bits;
  AtomPhysical:=EncodeT5M(Words);
  Numeric:=ReadNumericPhysical(AtomPhysical,12);
  Need((Numeric.DomainWidth=12) and
       (Numeric.ExactBits=IR.Nodes[2].Bits),
       'не підтверджений фізичний D12 аргумент');
  Result:=BuildD12ZeroELF(AtomPhysical);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
       (Geometry.Entry=120),'пошкоджено ELF64 PIE машинного предиката');
end;
end.
