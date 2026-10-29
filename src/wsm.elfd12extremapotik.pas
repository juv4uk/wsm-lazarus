{ G6.114 — повторно використовуваний x86-64 signed D12 мінімум/максимум
  над ДВОМА окремими канонічними T5M W12 зі stdin (6 host байтів).
  Механічно повторно використовує перевірений G6.88 transport, не
  дублює кодек T5M і не визначає нових законів SENS. }
unit wsm.elfd12extremapotik;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  ED12ExtremaStream=class(Exception);
  TExtremaMachine=(emMin,emMax); { host machine profile, НЕ SENS закон }
function BuildD12ExtremaStreamELF(Kind:TExtremaMachine):RawByteString;
implementation
uses wsm.elfd12potik,wsm.elfgeometry,wsm.x64frameio;
const HeaderBytes=120; AluBytes=35;

procedure Must(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12ExtremaStream.Create(Why) end;

{ Result: owned RawByteString ELF64 PIE. Existing machine emits canonical
  W12 decode/encode via tables derived from wsm.t5m.EncodeT5M and strict
  six-byte host framing. We verify every byte of the only ALU block that
  can be replaced, including pinned ADD overflow branches, then replace
  that SAME-LENGTH block with signed CMP+CMOV and NOP padding. No
  displacements, RIP-relative tables, stdout or error paths move.
  Physical signed D12 sign-extension happened in the original decoder;
  CPU still computes signed min/max at execution time (not in Pascal).
  The external caller must bind pinned exact D6:110101/110111; Kind is
  a host compilation profile, never a name-based language dispatch.
  1) Чому 6 host байтів не означають одну канонічну .sens програму?
  2) Чому перевірка шаблону повинна відмовляти після зміни донора?
  3) Чому signed CMOVG/CMOVL, а не unsigned?
  4) Чому довжина ALU залишається рівно 35 байтів?
  5) Хто володіє ELF і де перевірено геометрію після заміни? }
function BuildD12ExtremaStreamELF(Kind:TExtremaMachine):RawByteString;
var Base,Patch,Needle:RawByteString;At:SizeInt;G:TELFGeometry;
begin
  Base:=BuildD12StreamAddELF;
  VerifySENSELF64(Base,G);
  Must((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Base)),'донор не є перевіреним ELF64 PIE');
  Needle:=#$44#$89#$C0#$44#$01#$C8;
  At:=Pos(Needle,Base);
  Must((At>HeaderBytes) and (At+AluBytes-1<=Length(Base)),
    'немає точного machine ALU шаблону донора');
  Must(Pos(Needle,Copy(Base,At+1,Length(Base)-At))=0,
    'неоднозначний машинний ALU шаблон');
  Must((Copy(Base,At+6,5)=#$3D#$FF#$07#0#0) and
    (Copy(Base,At+11,2)=#$0F#$8F) and
    (Copy(Base,At+17,5)=#$3D#0#$F8#$FF#$FF) and
    (Copy(Base,At+22,2)=#$0F#$8C) and
    (Copy(Base,At+28,5)=#$25#$FF#$0F#0#0) and
    (Copy(Base,At+33,2)=#$89#$C3),
    'після зміни базового компілятора треба повторно довести ALU');
  { R8D/R9D already sign-extended exact D12 by donor decoder.
    44 89 C0 = mov eax,r8d; 44 39 C8 = cmp eax,r9d;
    41 0F 4F/4C C1 = signed cmovg/cmovl eax,r9d;
    25 FF 0F 00 00 = and eax,4095; 89 C3 = mov ebx,eax.
    Replaced 2047/-2048 ADD-only overflow guards are NOP because
    min/max of two admitted D12 is itself always a D12. }
  Patch:=#$44#$89#$C0#$44#$39#$C8;
  case Kind of
    emMin:Patch:=Patch+#$41#$0F#$4F#$C1;
    emMax:Patch:=Patch+#$41#$0F#$4C#$C1;
  else raise ED12ExtremaStream.Create('непідтриманий host machine profile')
  end;
  Patch:=Patch+#$25#$FF#$0F#0#0+#$89#$C3;
  Must(Length(Patch)=17,'некоректна довжина x86 signed CMOV');
  Patch:=Patch+StringOfChar(AnsiChar($90),AluBytes-Length(Patch));
  Must(Length(Patch)=AluBytes,'змінено машинну геометрію');
  Result:=Copy(Base,1,At-1)+Patch+
    Copy(Base,At+AluBytes,Length(Base)-(At+AluBytes)+1);
  Must(Length(Result)=Length(Base),'змінена довжина ELF/таблиць');
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'скомпонований signed D12 ELF64 PIE не підтверджений');
  { G6.121: bounded host-only I/O wrapper. CPU receives exactly two
    canonical W12 through repeated read syscalls and one EOF probe;
    the existing D6 signed CMOV and T5M lookup remain bit-identical.
    1) Чому відмовляємо після надлишкового байта?
    2) Чому оновлюється ELF phdr, але не самі T5M таблиці?
    3) Де перевіряється збереження донорських x86 інструкцій? }
  Result:=WrapExactSixByteFrame(Result);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'потоковий ELF64 PIE не підтверджений');
end;
end.
