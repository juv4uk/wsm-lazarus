{ G6.177 — оригінальне фізичне Core1 «відняти» з точним runtime D12/D24.
  ТІЛО D4 DEFINE/LAMBDA читає незмінний pinned binary core1.sens.
  Статичний source-backed admission і вузький ELF має бути повністю
  byte-exact рівним самостійному pinned D5:01011 WideIR/D12 SUB.
  Після цього вже перевірений машинний адаптивний SUB виконує ОСОБИСТО
  дві runtime W12 без нової компіляції. Жодного повторного закону. }
unit wsm.core1vidniatyadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ECore1VidniatyAdaptive=class(Exception);
function BuildPinnedCore1AdaptiveSubELF(const RepoRoot:String):RawByteString;
implementation
uses wsm.core1potik,wsm.numericplane,wsm.t5m,
     wsm.elfd12subpotik,wsm.x64frameio,
     wsm.elfd12addpotikadaptive,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise ECore1VidniatyAdaptive.Create(Why) end;

{ RepoRoot — позичений host корінь з точним pinned external/sens.
  Core1Witness і Reference — власні managed ELF64 byte strings, які
  FPC звільнить після виходу функції; Zero, Anchor — точні packed T5M.
  Result — новий власний executable ELF64 PIE (machine x86-64 SUB).
  Інтерпретація імен Core1 не здійснюється локальним dispatch:
  чинний селектор читає фізичні D7 бітові ідентичності із Core1.
  Вхід ELF — два окремі числові T5M D12 атоми (по 3 байти); вихід
  після signed CPU SUB — один T5M D12 (3) чи D24 (5) без усічення.

  1) Чому фактичний pinned DEFINE читається до emission ELF?
  2) Який доказ відрізняє Core1-віднімання від довільного x86 SUB?
  3) Чому D12 і D24 не є взаємозамінними фізичними словами?
  4) Чому зіставлення Core1Witness=Reference є побайтовим?
  5) Чому D7 projection не вибирає машинний opcode? }
function BuildPinnedCore1AdaptiveSubELF(const RepoRoot:String):RawByteString;
var Zero,ZeroBits,Anchor,Authority,Core1Witness,Reference:RawByteString;
    Numeric:TExplicitNumeric;Words:TExactWords;Geometry:TELFGeometry;
begin
  Result:='';
  Need((RepoRoot<>'') and (Length(RepoRoot)<=4096),
    'потрібен корінь перевіреного pinned SENS');
  Core1Witness:=BuildPinnedCore1StreamELF(RepoRoot,cpSub);
  VerifySENSELF64(Core1Witness,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Core1Witness)),
    'pinned Core1 не породив справжній вузький ELF64');
  Zero:=EncodeNumericDecimal('0',12);
  Numeric:=ReadNumericPhysical(Zero,12);
  Need((Numeric.DomainWidth=12) and
       (Length(Numeric.ExactBits)=12) and (Length(Zero)=3),
    'порушено фізичну ширину signed D12');
  ZeroBits:=Numeric.ExactBits;
  SetLength(Words,5);
  Words[0]:='10';Words[1]:='01011';Words[2]:=ZeroBits;
  Words[3]:=ZeroBits;Words[4]:='01';
  Anchor:=EncodeT5M(Words);
  Authority:=RawByteString(IncludeTrailingPathDelimiter(
    ExpandFileName(RepoRoot))+'external/sens');
  Reference:=WrapExactSixByteFrame(
    BuildVerifiedD12SubStreamELF(Anchor,Authority));
  Need(Core1Witness=Reference,
    'pinned Core1 DEFINE не збігся з незалежним фізичним SUB/WideIR');
  Result:=BuildAdaptiveD12SubStreamELF(Anchor,Authority);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.MachineBytes>0) and
       (Geometry.FileBytes=Length(Result)),
    'не отримано виконуваний адаптивний SUB ELF64 PIE');
end;
end.
