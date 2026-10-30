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
{ Checked x86 rel32 and ELF64 p_filesz/p_memsz — host offsets only.
  Bytes is owned, modified with copy-on-write; no SENS interpretation.
  1) Чому перевіряємо signed rel32 ще до запису?
  2) Чому зміна розміру вимагає оновити обидва PT_LOAD поля?
  3) Чому endian-порядок тут little-endian? }
procedure Put32(var Bytes:RawByteString;At0:SizeInt;Value:Int64);
var J:SizeInt;V:LongWord;
begin
  Need((At0>=0) and (At0+4<=Length(Bytes)) and
       (Value>=Low(LongInt)) and (Value<=High(LongInt)),
       'machine rel32 поза перевіреними межами');
  UniqueString(Bytes);V:=LongWord(LongInt(Value));
  for J:=0 to 3 do begin
    Bytes[At0+J+1]:=AnsiChar(Byte(V and 255));V:=V shr 8;
  end;
end;
procedure Put64(var Bytes:RawByteString;At0:SizeInt;Value:QWord);
var J:SizeInt;
begin
  Need((At0>=0) and (At0+8<=Length(Bytes)),
       'ELF PT_LOAD поза образом');
  UniqueString(Bytes);
  for J:=0 to 7 do begin
    Bytes[At0+J+1]:=AnsiChar(Byte(Value and 255));Value:=Value shr 8;
  end;
end;
function Get32(const Bytes:RawByteString;At1:SizeInt):LongInt;
var J:SizeInt;V:LongWord;
begin
  Need((At1>=1) and (At1+3<=Length(Bytes)),
       'machine donor rel32 поза образом');
  V:=0;
  for J:=0 to 3 do V:=V or (LongWord(Byte(Bytes[At1+J])) shl (8*J));
  Result:=LongInt(V);
end;

function BuildSignedD12RestStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,DonorPhysical,Donor,Needle,Island:RawByteString;
    Words:TExactWords;G:TELFGeometry;
    At,I,Writer0,PosJe,PosJns,PosWriter,DoneTarget:SizeInt;
    OldDisp:LongInt;
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
  { Pinned Core4: Д6 остача = a - b * floor(a/b).
    IDIV EDX is truncating remainder. Only when EDX <> 0 and signs
    of EDX / divisor differ do we add the divisor (machine integer):
      -1 mod 3 = 2, 7 mod -3 = -2, -7 mod -3 = -1.
    All arithmetic happens in x86, not a duplicated Pascal law.
    1) Чому модульна остача має знак дільника, а не діленого?
    2) Чому нульова EDX не потребує жодної корекції?
    3) Чому XOR знаків достатньо після exact IDIV?
    4) Як збережено JE відмови за нульового дільника?
    5) Чому для D12 два signed операнди мають D12 остачу? }
  OldDisp:=Get32(Donor,At+12);
  Writer0:=At+15+SizeInt(OldDisp);
  Need((Writer0>=HeaderBytes) and (Writer0+7<Length(Donor)) and
       (Copy(Donor,Writer0+1,2)=#$89#$C3),
       'не знайдено точний machine writer після донорського IDIV');
  Island:='';
  Island:=Island+#$85#$D2;                { test edx,edx }
  PosJe:=Length(Island)+2;
  Island:=Island+#$0F#$84#0#0#0#0;      { je done if rem=0 }
  Island:=Island+#$89#$D1;               { mov ecx,edx }
  Island:=Island+#$44#$31#$C9;          { xor ecx,r9d, compare signs }
  PosJns:=Length(Island)+2;
  Island:=Island+#$0F#$89#0#0#0#0;      { jns done if signs match }
  Island:=Island+#$44#$01#$CA;          { add edx,r9d if differ }
  DoneTarget:=Length(Island);
  Island:=Island+#$89#$D0;              { mov eax,edx }
  PosWriter:=Length(Island)+1;
  Island:=Island+#$E9#0#0#0#0;          { jmp existing encoder }
  Put32(Island,PosJe,DoneTarget-(PosJe+4));
  Put32(Island,PosJns,DoneTarget-(PosJns+4));
  Put32(Island,PosWriter,
       Int64(Writer0)-(Int64(Length(Donor))+PosWriter+4));
  Need((Length(Island)<128) and (Length(Donor)+Length(Island)<MaxBytes),
       'machine signed-rest острів поза квотою');
  Result:=Donor+Island;
  { Old post-IDIV 8 bytes -> JMP rel32 + NOP*3. Every donor byte after
    this precise slice is preserved, including the existing writer. }
  UniqueString(Result);
  Result[At+3]:=#$E9;                   { jmp appended Euclidean correction }
  Put32(Result,At+3,Int64(Length(Donor))-Int64(At+7));
  for I:=At+8 to At+10 do Result[I]:=#$90;
  Put64(Result,96,Length(Result));
  Put64(Result,104,Length(Result));
  Need((Copy(Result,At,3)=#$41#$F7#$F9) and
       (Copy(Result,At+3,1)=#$E9) and
       (Copy(Result,At+8,3)=#$90#$90#$90) and
       (Copy(Result,HeaderBytes+1,At+2-HeaderBytes)=
        Copy(Donor,HeaderBytes+1,At+2-HeaderBytes)) and
       (Copy(Result,At+11,Length(Donor)-At-10)=
        Copy(Donor,At+11,Length(Donor)-At-10)),
       'машинний patch пошкодив непризначену секцію');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)),
       'native Д6 floor-modulo ELF64 не пройшов перевірку');
end;
end.
