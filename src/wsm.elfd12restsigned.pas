{ G6.184 — знакова Д6:010100 остача двох runtime D12 T5M.
  Мовний закон тільки в pinned external/sens Contract 12.0.
  PhysicalAnchor: borrowed packed .sens; Result: owned ELF64 PIE bytes.
  1) Навіщо pinned Д6 admission перед машинним patch?
  2) Чому регістр EDX після IDIV, а не Pascal mod?
  3) Чому відмову від нульового дільника не можна видаляти?
  4) Чому result numeric D12 незалежний від D7 surface? }
unit wsm.elfd12restsigned;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ESignedRestELF=class(Exception);
function BuildSignedD12RestStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwiderest,wsm.elfd12quotadaptive,wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120;MaxBytes=8192;
procedure Need(Allowed:Boolean;const Why:String);
begin
  if not Allowed then raise ESignedRestELF.Create(Why);
end;

{ Proof від незалежного pinned BuildIRWideRestELF підтверджує Д6 голову,
  точність усіх бітів і рівно два numeric D12. Лише ДЛЯ донорського
  машинного механізму створюємо secondary canonical D5:10111(7,7).
  Donor отримує реальний x86 IDIV, bounded EOF, T5M writer, reject.
  Єдина зміна в owned Result: test edx; jne reject (8 машинних байтів)
  стає mov eax,edx; nop×6: остача — значення, не відмова.
  Всі інші байти, rel32, JE zero-divisor, ELF PT_LOAD збережено.
  Donor, Proof, Words — тимчасова керована пам'ять.
  1) Чому вторинна Д5 форма не створює нового закону Д6?
  2) Чому 8 байтів patch зберігають усі rel32 адреси?
  3) Чому не змінюємо стару діагностичну гілку?
  4) Хто перевіряє sign convention на 20 signed випадках?
  5) Хто володіє фізичними байтами Result після повернення? }
function BuildSignedD12RestStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,DonorPhysical,Donor,Needle:RawByteString;
    Words:TExactWords;G:TELFGeometry;At,I:SizeInt;
begin
  Result:='';
  Proof:=BuildIRWideRestELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Proof)),
       'не підтверджено pinned Д6:010100 якір');
  DecodeT5M(PhysicalAnchor,Words);
  Need((Length(Words)=5) and (Words[0]='10') and
       (Words[1]='010100') and
       (Length(Words[2])=12) and (Length(Words[3])=12) and
       (Words[4]='01') and (EncodeT5M(Words)=PhysicalAnchor),
       'неповне canonical D2/D6 фізичне джерело');
  Words[1]:='10111';              { pinned D5 donor only }
  Words[2]:='000000000111';      { two exact positive W12 7 }
  Words[3]:='000000000111';
  DonorPhysical:=EncodeT5M(Words);
  Donor:=BuildAdaptiveD12QuotStreamELF(DonorPhysical,AuthorityRoot);
  VerifySENSELF64(Donor,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Donor)) and (Length(Donor)<MaxBytes),
       'непідтверджений x86 IDIV/T5M донор');
  Needle:=#$41#$F7#$F9#$85#$D2#$0F#$85;
  At:=Pos(Needle,Donor);
  Need(At>HeaderBytes+30,
       'не знайдено post-IDIV fingerprint: offset='+IntToStr(At));
  { Після IDIV рівно 8 байтів guard і 5 байтів JMP rel32:
    останній потрібний індекс є At+15, включно. }
  Need(At+15<=Length(Donor),'post-IDIV вийшла за ELF');
  Need(Pos(Needle,Copy(Donor,At+1,Length(Donor)-At))=0,
       'post-IDIV не унікальна');
  Need(Copy(Donor,At+11,1)=#$E9,
       'post-IDIV не має очікуваного JMP: At='+IntToStr(At)+
       ' opcode='+IntToStr(Byte(Donor[At+11])));
  Result:=Donor;
  UniqueString(Result);
  Result[At+3]:=#$89;             { mov eax,edx }
  Result[At+4]:=#$D0;
  for I:=5 to 10 do Result[At+I]:=#$90;
  Need((Copy(Result,At,11)=#$41#$F7#$F9#$89#$D0+
        StringOfChar(AnsiChar($90),6)) and
       (Length(Result)=Length(Donor)) and
       (Copy(Result,1,At+2)=Copy(Donor,1,At+2)) and
       (Copy(Result,At+11,Length(Result)-At-10)=
        Copy(Donor,At+11,Length(Donor)-At-10)),
       'змінено решту машинного донора');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)),
       'native Д6 signed ELF64 не пройшов перевірку');
end;
end.
