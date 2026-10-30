{ G6.161 — один повторно виконуваний ELF64 D5:10111 із двома D12 у stdin.
  Відмінність від старого IDIV — аргументи НЕ baked into machine image.
  Машинна частка допускається лише для exact integer результату у D12:
  нульовий дільник, дробовий результат і D24 promotion — відмова.
  Жодного Pascal ділення, локального SENS закону чи D7 dispatch. }
unit wsm.elfd12quotpotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12QuotStreamError=class(Exception);
function BuildVerifiedD12QuotStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwidequot,wsm.elfd12potik,wsm.x64frameio,
     wsm.elfgeometry;
const HeaderBytes=120; ALUBytes=35;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12QuotStreamError.Create(Why) end;

{ S: borrowed immutable bytes, At1: one-based physical index.
  Return signed rel32 machine offset, no SENS numeric inference.
  1) Чому LE32 складають за бітами, не текстом?
  2) Чому LongInt має зберігати sign?
  3) Що відбувається при зіпсованих границях? }
function Read32(const S:RawByteString;At1:SizeInt):LongInt;
var I:SizeInt;V:LongWord;
begin
  Need((At1>=1) and (At1+3<=Length(S)),'rel32 поза фізичним ELF');
  V:=0;
  for I:=0 to 3 do V:=V or
    (LongWord(Byte(S[At1+I])) shl (8*I));
  Result:=LongInt(V);
end;

{ Bytes: owned mutable FPC buffer; At0: 0-based rel32 offset.
  Value: signed machine displacement, not a SENS number.
  1) Чому потрібно перевірити bounds?
  2) Що гарантує UniqueString?
  3) Чому машинний rel32 не є доменною координатою? }
procedure Write32(var Bytes:RawByteString;At0:SizeInt;Value:Int64);
var I:SizeInt;V:LongWord;
begin
  Need((At0>=0) and (At0+4<=Length(Bytes)) and
    (Value>=Low(LongInt)) and (Value<=High(LongInt)),
    'machine rel32 вийшов за перевірений бюджет');
  UniqueString(Bytes);
  V:=LongWord(LongInt(Value));
  for I:=0 to 3 do begin
    Bytes[At0+I+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

procedure Write64(var Bytes:RawByteString;At0:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((At0>=0) and (At0+8<=Length(Bytes)),
    'заголовок ELF64 вийшов за фізичні межі');
  UniqueString(Bytes);
  for I:=0 to 7 do begin
    Bytes[At0+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ PhysicalAnchor — borrowed canonical packed D2/T5M SENS form.
  Викличність D5:10111 і цілісне дерево спочатку перевіряє
  pinned BuildIRWideQuotELF (вузький рівний ненульовий якір).
  Base та Island — owned managed FPC byte strings, без alias до SENS.
  Старі syscall decode, canonical T5M output, error handler, lookup
  таблиці й всі RIP-relative displacement залишаються незмінними.
  Старий 35-byte ALU slot замінюється JMP+NOP у точно тому ж місці.
  Island розміщено ПІСЛЯ всього ELF data у тому самому RX PT_LOAD:
    mov eax,r8d; cdq; test r9d,r9d; je reject; idiv r9d;
    test edx,edx; jne reject; D12 bounds; mask; mov ebx,eax;
    jmp original canonical T5M writer.
  Всі переходи патчаться у signed rel32, квоти обмежено.
  1) Чому CDQ потрібен для від'ємних D12?
  2) Чому EDX<>0 відхиляє дробову частку, а не змінює мовний закон?
  3) Чому D24 promotion мусить бути fail-closed?
  4) Чому donor decoder/reject branch не можна переписати непомітно?
  5) Чому пізніший WrapExactSixByteFrame не псує ці rel32? }
function BuildVerifiedD12QuotStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,Base,Island,Patch,Needle:RawByteString;
    G:TELFGeometry;At,Reject0,Encode0,NewLen:SizeInt;
    Upper,Lower:LongInt;
    OffZero,OffFrac,OffUpper,OffLower,OffEncode:SizeInt;

  procedure Emit(const Bytes:RawByteString);
  begin
    Need((Length(Bytes)>0) and (Length(Island)+Length(Bytes)<256),
      'IDIV island перевищив квоту');
    Island:=Island+Bytes;
  end;
  { Pos0 is an island-relative rel32 field, target absolute ELF offset.
    Передачі управління не можуть потрапити на дані або за PT_LOAD. }
  procedure FixJump(Pos0,Target0:SizeInt);
  begin
    Need((Target0>=HeaderBytes) and (Target0<Length(Base)) and
      (Pos0>=0) and (Pos0+4<=Length(Island)),
      'неприпустима адреса машинного переходу');
    Write32(Island,Pos0,
      Int64(Target0)-(Int64(Length(Base))+Int64(Pos0)+4));
  end;
begin
  Result:='';
  Proof:=BuildIRWideQuotELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Proof)),
    'pinned D5:10111 не підтвердив повний фізичний якір');
  Base:=BuildD12StreamAddELF;
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Base)) and (Length(Base)<8192-512),
    'канонічний D12/stdin донор не допущено');

  Needle:=#$44#$89#$C0#$44#$01#$C8;
  At:=Pos(Needle,Base);
  Need((At>HeaderBytes+28) and
    (At+ALUBytes-1<Length(Base)) and
    (Pos(Needle,Copy(Base,At+1,Length(Base)-At))=0),
    'донор змінив машинний ALU slot');
  Need((Copy(Base,At+6,5)=#$3D#$FF#$07#0#0) and
    (Copy(Base,At+11,2)=#$0F#$8F) and
    (Copy(Base,At+17,5)=#$3D#0#$F8#$FF#$FF) and
    (Copy(Base,At+22,2)=#$0F#$8C) and
    (Copy(Base,At+28,5)=#$25#$FF#$0F#0#0) and
    (Copy(Base,At+33,2)=#$89#$C3) and
    (Copy(Base,At+ALUBytes,5)=#$89#$D8#$C1#$E8#$07),
    'не підтверджено exact D12/overflow/encode donor');
  Upper:=Read32(Base,At+13);
  Lower:=Read32(Base,At+24);
  Reject0:=At+16+SizeInt(Upper);
  Need((Reject0=At+27+SizeInt(Lower)) and
    (Reject0>At+ALUBytes) and
    (Reject0+5<=Length(Base)) and
    (Copy(Base,Reject0+1,5)=#$B8#$01#0#0#0),
    'донорська fail-closed гілка зіпсована');
  Encode0:=At+ALUBytes-1;

  Island:='';
  Emit(#$44#$89#$C0);                  { mov eax,r8d }
  Emit(#$99);                          { cdq sign-extend eax into edx }
  Emit(#$45#$85#$C9);                  { test r9d,r9d }
  Emit(#$0F#$84#0#0#0#0);             { je donor reject }
  OffZero:=Length(Island)-4;
  Emit(#$41#$F7#$F9);                  { idiv r9d, signed quotient }
  Emit(#$85#$D2);                      { test edx,edx (remainder) }
  Emit(#$0F#$85#0#0#0#0);             { jne reject non-integral }
  OffFrac:=Length(Island)-4;
  Emit(#$3D#$FF#$07#0#0);             { cmp eax, 2047 }
  Emit(#$0F#$8F#0#0#0#0);             { jg reject D24 promotion }
  OffUpper:=Length(Island)-4;
  Emit(#$3D#0#$F8#$FF#$FF);           { cmp eax, -2048 }
  Emit(#$0F#$8C#0#0#0#0);             { jl reject D24 promotion }
  OffLower:=Length(Island)-4;
  Emit(#$25#$FF#$0F#0#0);             { and eax, 0FFFh }
  Emit(#$89#$C3);                      { mov ebx,eax }
  Emit(#$E9#0#0#0#0);                  { jmp donor T5M encoder }
  OffEncode:=Length(Island)-4;
  FixJump(OffZero,Reject0);
  FixJump(OffFrac,Reject0);
  FixJump(OffUpper,Reject0);
  FixJump(OffLower,Reject0);
  FixJump(OffEncode,Encode0);

  Patch:=#$E9#0#0#0#0+StringOfChar(AnsiChar($90),ALUBytes-5);
  Need(Length(Patch)=ALUBytes,'заміна ALU не зберегла offset');
  Write32(Patch,1,Int64(Length(Base))-Int64(At+4));
  Need(Length(Base)+Length(Island)<8192,
    'розширення PT_LOAD перевищило квоту');
  Result:=Copy(Base,1,At-1)+Patch+
    Copy(Base,At+ALUBytes,Length(Base)-At-ALUBytes+1)+Island;
  NewLen:=Length(Base)+Length(Island);
  Need(Length(Result)=NewLen,'втрачено байти донорського ELF');
  Write64(Result,96,QWord(NewLen));
  Write64(Result,104,QWord(NewLen));
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=NewLen) and
    (Copy(Result,At,5)=Copy(Patch,1,5)),
    'новий x86 IDIV ELF не пройшов перевірку');

  { Exact 6-byte host transport охоплює short reads/EOF/зайві байти.
    Попередній донор та island зміщуються разом — кожен rel32 незмінний. }
  Result:=WrapExactSixByteFrame(Result);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'native D12 quotient/EOF ELF геометрія не підтверджена');
end;
end.
