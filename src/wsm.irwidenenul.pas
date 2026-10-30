{ G6.171 — ратифікована D4:0100( D5:01000( exact D12 )) у
  справжній Linux x86-64 ELF64 з TEST/SETNE і canonical D1 T5M stdout.
  NOT(D5 ZERO) є вкладеним викликом, не новим SENS законом. }
unit wsm.irwidenenul;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideNenulError=class(Exception);
function BuildIRWideNenulELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12zero,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideNenulError.Create(Why) end;

{ IR — позичене, усі Nodes зберігають фізичні точні ширини і біти.
  Корінь та вкладеність походять з D2, ключі — з pinned таблиць.
  Не можна плутати W12 opaque із автоматично викличним законом.
  1) Чому D4 і D5 мають різні Width навіть якщо битове слово схоже?
  2) Чому потрібен RootIndex і ChildIndex кожного вузла?
  3) Чому 5 вузлів (а не 3) — необхідна форма двох викликів?
  4) Чим підтверджується викличність кожного pinned ключа? }
procedure VerifyOneForm(const IR:TWideIR;const Stats:TWideIRGuardStats;
                         const Tables:TDomainSet);
var R:TDomainRow;K:TDomainKey;N:TWideIRNode;
begin
  Need((Stats.Roots=1) and (Stats.Nodes=5) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=1) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=5),
       'потрібна одна точна вкладена D4(D5(D12)) форма');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.RootIndex=0) and (N.ParentIndex=-1) and
       (N.ChildIndex=0) and (N.Depth=0),'помилковий D2 корінь');
  N:=IR.Nodes[1];
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
       (N.Width=4) and (N.Bits='0100') and
       SameKey(N.NarrowKey,ExactKey('0100')) and
       (N.RootIndex=0) and (N.ParentIndex=0) and
       (N.ChildIndex=0) and (N.Depth=1),
       'потрібна pinned D4:0100 хибне?');
  K:=ExactKey('0100');
  Need(DomainRowByKey(Tables[4],K,R) and SameKey(R.Key,K),
       'немає pinned D4 координати');
  N:=IR.Nodes[2];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.RootIndex=0) and (N.ParentIndex=0) and
       (N.ChildIndex=1) and (N.Depth=1),
       'потрібен єдиний вкладений виклик D5');
  N:=IR.Nodes[3];
  Need((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
       (N.Width=5) and (N.Bits='01000') and
       SameKey(N.NarrowKey,ExactKey('01000')) and
       (N.RootIndex=0) and (N.ParentIndex=2) and
       (N.ChildIndex=0) and (N.Depth=2),
       'потрібна pinned D5:01000 нуль?');
  K:=ExactKey('01000');
  Need(DomainRowByKey(Tables[5],K,R) and SameKey(R.Key,K),
       'немає pinned D5 координати');
  N:=IR.Nodes[4];
  Need((N.Kind=wkAtom) and N.OwnWord and (not N.HasPinnedKey) and
       (N.NarrowKey.Width=0) and (N.Width=12) and
       (Length(N.Bits)=12) and (N.RootIndex=0) and
       (N.ParentIndex=2) and (N.ChildIndex=1) and (N.Depth=2),
       'потрібен єдиний opaque D12 аргумент');
end;

{ ProgramPhysical: borrowed canonical binary T5M bytes; AuthorityRoot:
  borrowed pinned source path. Result: owned Free Pascal RawByteString
  з Linux ELF64 ET_DYN, не інтерпретований результат.
  BuildD12ZeroELF генерує справжній machine TEST EAX,EAX + SETE AL,
  після guarded exact machine signature замінюємо тільки SETE→SETNE.
  Сам процесор рахує істинність, Pascal не виконує нульову перевірку.
  1) Чому 0F 95 є SETNE, а 0F 94 — SETE?
  2) Що станеться, якщо зміниться пролог наявного емітера?
  3) Чому ELF після патча перевіряється повторно?
  4) Чому незалежний pinned REPL є додатковим обов'язковим доказом?
  5) Чому D12 не дозволено розширювати за шириною без закону? }
function BuildIRWideNenulELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Decoded,Single:TExactWords; V:TExplicitNumeric;
    Image,AtomPhysical:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'фізична програма порожня або перевищує 64К');
  DecodeT5M(ProgramPhysical,Decoded);
  Need(EncodeT5M(Decoded)=ProgramPhysical,'не канонічний packed T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyOneForm(IR,Stats,Tables);
  SetLength(Single,1);
  Single[0]:=IR.Nodes[4].Bits;
  AtomPhysical:=EncodeT5M(Single);
  V:=ReadNumericPhysical(AtomPhysical,12);
  Need((V.DomainWidth=12) and (V.ExactBits=IR.Nodes[4].Bits),
       'немає точного фізичного D12 числового допуску');
  Image:=BuildD12ZeroELF(AtomPhysical);
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Image)) and (Length(Image)>140) and
       (Image[121]=#$B8) and (Image[126]=#$85) and
       (Image[127]=#$C0) and
       (Image[128]=#$0F) and (Image[129]=#$94) and
       (Image[130]=#$C0) and
       (Image[131]=#$0F) and (Image[132]=#$B6) and
       (Image[133]=#$C0),
       'пролог чинного TEST/SETE/MOVZX змінився — відмова');
  Image[129]:=#$95; { 0F 95 C0 — машинний SETNE AL }
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Image)) and
       (G.MachineBytes=Length(Image)-120),
       'не підтверджений нативний ELF64 PIE');
  Result:=Image;
end;
end.
