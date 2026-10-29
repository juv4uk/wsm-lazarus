{ G6.127 — один повторно використовуваний native ELF64 D5:01011 «відняти».
  Type: borrowed PhysicalAnchor (canonical packed D2 .sens), authority root;
  Result: owned managed RawByteString ELF64 PIE, released by FPC caller.
  Ратифікований закон і точний домен перевіряє ВЖЕ ЗЛИТИЙ
  BuildIRWideSubELF: не вводимо local registry або D7 name dispatch.
  Два runtime D12 input атоми у stdin — host frame 6 байтів, НЕ
  повна .sens програма. Decode5/Decode2/Encode5/Encode2/PIE/branch
  лишаються з existing BuildD12StreamAddELF. Тільки один opcode byte
  ADD→SUB міняється машинно (44 01 C8→44 29 C8), без reloc.
  Реальні CPU SUB і pinned D12 fail-closed overflow, а не Pascal math.
  1) Чому Word 01011 визначається лише разом із D5 і законом?
  2) Чому W12 stdin окремо не визначає числову семантику?
  3) Чому міняємо тільки один байт і перевіряємо унікальність?
  4) Хто володіє T5M codec та RIP-relative tables?
  5) Що станеться, якщо результат потребуватиме D24? }
unit wsm.elfd12subpotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12SubStreamError=class(Exception);
function BuildVerifiedD12SubStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwidesub,wsm.elfd12potik,wsm.elfgeometry;

procedure Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise ED12SubStreamError.Create(Why);
end;

function BuildVerifiedD12SubStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
const Original:RawByteString=
  #$44#$89#$C0#$44#$01#$C8#$3D#$FF#$07#0#0;
var Proof,OriginalELF:RawByteString;
    G:TELFGeometry;Start,I,Diff:SizeInt;
begin
  Result:='';
  { Без pinned перевірки ЦІЛОГО root D2 виразу kernel не допускається. }
  Proof:=BuildIRWideSubELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Proof)),
    'якір не підтвердив exact D5 native compilation');
  OriginalELF:=BuildD12StreamAddELF;
  VerifySENSELF64(OriginalELF,G);
  Need((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(OriginalELF)),
    'потоковий T5M ELF64 механізм не допущений');
  Start:=Pos(Original,OriginalELF);
  Need((Start>=121) and (Start+Length(Original)-1<=Length(OriginalELF)),
    'не знайдено exact один машинний ALU-fragment');
  Need(Pos(Original,Copy(OriginalELF,Start+Length(Original),
    Length(OriginalELF)))=0,
    'машинний SUB-slot неоднозначний');
  Need(OriginalELF[Start+4]=#$01,
    'невідомий ADD opcode перед SUB patch');
  Result:=OriginalELF;
  UniqueString(Result);
  Result[Start+4]:=#$29;  { 44 01 C8 ADD eax,r9d → 44 29 C8 SUB eax,r9d }
  Need(Copy(Result,Start,Length(Original))=
    #$44#$89#$C0#$44#$29#$C8#$3D#$FF#$07#0#0,
    'машинний SUB не отримано');
  Diff:=0;
  for I:=1 to Length(Result) do
    if Result[I]<>OriginalELF[I] then Inc(Diff);
  Need((Diff=1) and (Length(Result)=Length(OriginalELF)),
    'порушено рівно однобайтову зміну без RIP-reloc');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(Result)),
    'SUB patch змінив фізичну ELF64 геометрію');
end;
end.
