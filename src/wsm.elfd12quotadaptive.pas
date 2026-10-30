{ G6.178 — signed D12 quotient з адаптивним фізичним D12/D24 виходом.
  Закон D5:10111 — виключно pinned SENS; тут лише перевірена ISA x86-64.
  Якір: повний borrowed canonical packed D2/T5M .sens (не .lisp).
  Результат: owned ELF64 PIE bytes; runtime — рівно два stdin T5M W12.
  Нецiла частка або нульовий дільник — fail-closed через donor reject.
  Для -2048/-1 машинний IDIV дає 2048: D24 writer, 5 bytes, не відмова.
  Жодного Pascal-ділення, host arithmetic evaluator або D7 dispatch.

  Запитання: чому фізичну голову перевіряємо ДО використання x86?
  Чому D24 потребує іншого T5M writer, але не нового закону у Pascal?
  Чому CDQ передує IDIV і чому важливий EDX після IDIV?
  Чому донора компілюємо через ще одну pinned фізичну форму?
  Чому rel32 і PT_LOAD переперевіряємо після кожного переходу? }
unit wsm.elfd12quotadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EAdaptiveQuotELF=class(Exception);
function BuildAdaptiveD12QuotStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwidequot,wsm.elfd12addpotikadaptive,wsm.t5m,
     wsm.x64frameio,wsm.elfgeometry;
const HeaderBytes=120; MaxBytes=8192;

procedure Need(Ok:Boolean;const Message:String);
begin
  if not Ok then raise EAdaptiveQuotELF.Create(Message);
end;

{ S: borrowed ELF image; At1 one-based LE32 offset, Result signed Int32.
  No pointer alias, no heap allocation, no SENS domain arithmetic.
  1) Why does rel32 carry a sign?
  2) Why are 4 bytes bounded before reading?
  3) Why not interpret this as D12? }
function Read32(const S:RawByteString;At1:SizeInt):LongInt;
var I:SizeInt;Value:LongWord;
begin
  Need((At1>=1) and (At1+3<=Length(S)),'rel32 поза фізичним ELF');
  Value:=0;
  for I:=0 to 3 do
    Value:=Value or (LongWord(Byte(S[At1+I])) shl (8*I));
  Result:=LongInt(Value);
end;

{ Bytes owned by caller, At0 zero-based physical ELF offset.
  Rel32 is a host machine displacement, not a SENS number.
  1) How do we preserve signed rel32?
  2) Why UniqueString before mutation?
  3) What happens to a too-large branch displacement? }
procedure Write32(var Bytes:RawByteString;At0:SizeInt;Offset:Int64);
var I:SizeInt;Value:LongWord;
begin
  Need((At0>=0) and (At0+4<=Length(Bytes)) and
       (Offset>=Low(LongInt)) and (Offset<=High(LongInt)),
       'x86 rel32 поза фізичними межами');
  UniqueString(Bytes);
  Value:=LongWord(LongInt(Offset));
  for I:=0 to 3 do begin
    Bytes[At0+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ PT_LOAD p_filesz/p_memsz on Linux ELF64, 0-based physical offsets;
  Result has no new allocation. No SENS numeric meaning.
  1) Why must file/memory lengths agree in this single RX image?
  2) Why not change the ELF entry?
  3) Why validate both bounds and geometry? }
procedure Write64(var Image:RawByteString;At0:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((At0>=0) and (At0+8<=Length(Image)),'заголовок ELF поза межею');
  UniqueString(Image);
  for I:=0 to 7 do begin
    Image[At0+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Borrowed canonical exact quotient form must pass pinned WideIR and
  native D5:10111 admission FIRST; its proof ELF is disposable managed data.
  Secondary donor anchor differs ONLY in D5 head, with two ZERO W12 values:
    (D5:01010 W12:0 W12:0), constructed from already checked D2 framing.
  This secondary proof DOES NOT choose output semantics, it only obtains
  the existing x86 D12/D24 physical writer from pinned admission.
  The original quotient head remains the sole law for the returned ELF.
  The adaptive ADD donor has a unique machine island:
    MOV EAX,R8D; ADD EAX,R9D; MOV EBX,EAX; CMP D12 bounds; ...
  Replace EXACT first 6 bytes by JMP+NOP to appended IDIV island:
    MOV EAX,R8D; CDQ; TEST R9D,R9D; JE donor reject;
    IDIV R9D; TEST EDX,EDX; JNE donor reject;
    JMP back to existing MOV EBX,EAX and unchanged D12/D24 encoding.
  All donor lookup tables, RIP offsets, output, fail-closed diagnostics
  and container framing are preserved bit-for-bit; no Pascal evaluator.
  Output is owned managed ELF64, caller publishes no-clobber.
  1) Why can -2048/-1 safely execute signed 32-bit IDIV?
  2) How do we prove quotient zero/divisibility checks are CPU-side?
  3) Why must the tail writer be the already-verified D24 donor?
  4) Why is old D5:01010 only a physical *writer* donor, not semantics?
  5) Why does wrapping the read prologue not change internal rel32? }
function BuildAdaptiveD12QuotStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,PhysicalAdd,Base,Island,Patch,Needle:RawByteString;
    Words:TExactWords;G:TELFGeometry;
    At,Reject0,Continue0,Start0,RelZero,RelFraction,RelContinue:SizeInt;
    P,Disp:LongInt;

  procedure Emit(const Code:RawByteString);
  begin
    Need((Length(Code)>0) and (Length(Island)+Length(Code)<256),
      'IDIV острів перевищив фізичний бюджет');
    Island:=Island+Code;
  end;

  { Pos0 is island-relative offset of rel32 *field*, target an absolute
    ELF offset in previously verified donor. Fail-closed on any invalid
    target, then Write32 emits the machine displacement.
    1) Why target must be inside executable donor?
    2) Why compute rel from end of displacement field?
    3) Why never jump into T5M lookup table? }
  procedure Fix(Pos0,Target0:SizeInt);
  begin
    Need((Target0>=HeaderBytes) and (Target0<Length(Base)) and
      (Pos0>=0) and (Pos0+4<=Length(Island)),
      'x86 перехід вийшов за машинний донор');
    Write32(Island,Pos0,
      Int64(Target0)-Int64(Length(Base)+Pos0+4));
  end;
begin
  Result:='';
  Proof:=BuildIRWideQuotELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Proof)),
       'pinned D5:10111 фізичний якір не підтверджений');

  DecodeT5M(PhysicalAnchor,Words);
  Need((Length(Words)=5) and
       (Words[0]='10') and (Words[1]='10111') and
       (Length(Words[2])=12) and (Length(Words[3])=12) and
       (Words[4]='01') and (EncodeT5M(Words)=PhysicalAnchor),
       'втрата повного canonical D2/T5M та provenance');
  Words[1]:='01010';                  { secondary pinned ADD donor only }
  Words[2]:='000000000000';          { signed D12 zero, NOT quotient input }
  Words[3]:='000000000000';
  PhysicalAdd:=EncodeT5M(Words);
  Base:=BuildAdaptiveD12AddStreamELF(PhysicalAdd,AuthorityRoot);
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Base)) and (Length(Base)<MaxBytes-256),
       'pinned adaptive D12/D24 T5M writer не підтверджений');

  { Unique 13-byte machine fingerprint: ADD 32-bit then MOV EBX,EAX,
    CMP EAX,2047. We never touch this writer's other instructions. }
  Needle:=#$44#$89#$C0#$44#$01#$C8#$89#$C3#$3D#$FF#$07#0#0;
  At:=Pos(Needle,Base);
  Need((At>HeaderBytes+100) and (At+Length(Needle)<Length(Base)) and
    (Pos(Needle,Copy(Base,At+1,Length(Base)-At))=0),
    'відсутній єдиний перевірений D12/D24 machine ALU острів');
  Continue0:=At-1+6;                 { MOV EBX,EAX after original ADD }
  Need(Copy(Base,Continue0+1,7)=#$89#$C3#$3D#$FF#$07#0#0,
    'адаптивний donor змінив початок D12/D24 writer');

  { This is the unchanged donor's *diagnostic* fail-closed target.
    The 28-byte read(0,rsp,7) prologue has JNE rel32 at 120+22,
    with displacement stored at physical 1-based 120+25. }
  Need(Copy(Base,HeaderBytes+1,22)=
       #$48#$83#$EC#$20+#$31#$C0+#$31#$FF+#$48#$89#$E6+
       #$BA#$07#0#0#0+#$0F#$05+#$48#$83#$F8#$06,
       'змінився перевірений 7-byte read prologue');
  Disp:=Read32(Base,HeaderBytes+25);
  Need((Disp>=0) and (Disp<=4096),'недійсний донорський reject rel32');
  Reject0:=HeaderBytes+28+SizeInt(Disp);
  Need((Reject0>HeaderBytes+28) and
       (Reject0+16<Length(Base)) and
       (Copy(Base,Reject0+1,5)=#$B8#$01#0#0#0),
       'немає канонічної machine diagnostic reject гілки');

  Island:='';
  Emit(#$44#$89#$C0);                 { mov eax,r8d }
  Emit(#$99);                         { cdq sign extend eax to edx }
  Emit(#$45#$85#$C9);                 { test r9d,r9d }
  Emit(#$0F#$84#0#0#0#0);            { je donor reject: divisor=0 }
  RelZero:=Length(Island)-4;
  Emit(#$41#$F7#$F9);                 { idiv r9d: signed 32-bit CPU }
  Emit(#$85#$D2);                     { test edx,edx; remainder }
  Emit(#$0F#$85#0#0#0#0);            { jne donor reject: noninteger }
  RelFraction:=Length(Island)-4;
  Emit(#$E9#0#0#0#0);                 { jmp old D12/D24 writer }
  RelContinue:=Length(Island)-4;
  Fix(RelZero,Reject0);
  Fix(RelFraction,Reject0);
  Fix(RelContinue,Continue0);

  Start0:=Length(Base);
  Patch:=#$E9#0#0#0#0+#$90;
  Need(Length(Patch)=6,'неповне переправлення ALU');
  Write32(Patch,1,Int64(Start0)-Int64(At+4));
  Result:=Copy(Base,1,At-1)+Patch+
    Copy(Base,At+6,Length(Base)-(At+6)+1)+Island;
  Need((Length(Result)=Length(Base)+Length(Island)) and
       (Length(Result)<MaxBytes),'новий IDIV ELF перевищив квоту');
  Write64(Result,96,Length(Result));
  Write64(Result,104,Length(Result));
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)) and
       (Copy(Result,At,6)=Patch),
       'x86 IDIV/D24 ELF не пройшов перевірку цілісності');
  Result:=WrapExactSixByteFrame(Result);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)) and
       (Pos(#$41#$F7#$F9,Result)>0),
       'повторна перевірка bounded stdin/EOF та IDIV не пройдена');
end;
end.
