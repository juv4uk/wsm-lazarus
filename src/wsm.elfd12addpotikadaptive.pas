{ G6.162 — адаптивний фізичний результат signed D12/D24 у native ADD.
  Єдиний закон D5:01010 допускає вже існуючий pinned WideIR backend.
  Тут тільки host x86-64 code island, НЕ новий SENS evaluator/registry.
  Input PhysicalAnchor — borrowed packed D2 .sens; AuthorityRoot — pinned.
  Result — owned RawByteString ELF64 PIE, managed FPC string lifetime.
  TExactWords — тимчасовий managed array для таблиць з EncodeT5M.
  1) Чому код не обирає закон за текстом?
  2) Чому D12 і D24 повинні мати різні фізичні довжини?
  3) Чому 12-bit signed sum завжди вкладається в signed D24?
  4) Яким чином донорський exact stdin і D12 fast path незмінні?
  5) Чому адреси x86 branch та RIP-relative таблиць перевіряються? }
unit wsm.elfd12addpotikadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EAdaptiveAddELF=class(Exception);
function BuildAdaptiveD12AddStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
{ Обидва API повертають власні байти ELF64; source — borrowed T5M.
  Host вибір opcode НЕ є dispatch мови: кожна голова окремо проходить
  pinned WideIR admission. Жодного локального SENS реєстру.
  1) Чому D5:01011 перевіряється перед x86 SUB?
  2) Чому reuse ADD донора не означає виконання ADD?
  3) Де D12/D24 вирішується вже відомим машинним шляхом?
  4) Хто звільняє ELF byte string після повернення? }
function BuildAdaptiveD12SubStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
{ G6.240: окремі host EOF-framed входи, а не зміна донорського API.
  Позичений pinned-якір проходить той самий WideIR, власні ELF bytes
  доповнюються наявним повторним read/EINTR/EOF префіксом.
  1) Чому незагорнутий ADD потрібний адаптивному QUOT?
  2) Чому Linux read може повернути 2 із 6 байтів?
  3) Чому другий wrapper повинен відмовити?
  4) Хто звільняє тимчасовий Base у FPC? }
function BuildAdaptiveD12AddFramedELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
function BuildAdaptiveD12SubFramedELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.elfd12potik,wsm.irwideaddreg,wsm.irwidesub,
     wsm.elfgeometry,wsm.x64frameio;
type TAdaptiveAlu=(aaAdd,aaSub);
const HeaderBytes=120; PreviousAluBytes=35; MaxBytes=8192;

procedure Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EAdaptiveAddELF.Create(Why);
end;

{ Binary bit pattern W5 або W4 для ВИКЛЮЧНО T5M table generation.
  Value host-only index; Result FPC owned byte string, NOT numeric law.
  1) Чому провідний нуль зберігається?
  2) Чому довжина є частиною ключа?
  3) Чому не слід будувати таблицю з ASCII-коду символів? }
function BitPattern(Value,Width:SizeInt):RawByteString;
var I:SizeInt;
begin
  Need((Width in [4,5]) and (Value>=0) and
    (Value<(1 shl Width)),'фізична таблиця T5M поза шириною');
  SetLength(Result,Width);
  for I:=1 to Width do
    if (Value and (1 shl (Width-I)))<>0 then Result[I]:='1'
    else Result[I]:='0';
end;

{ I: zero-based entry in Code. Rel32: signed 32-bit machine displacement.
  Code — owned byte string, mutated only after exact bounds check.
  1) Чому запис LE використовує чотири байти?
  2) Чому signed displacement треба перевіряти до LongInt?
  3) Чому зміна поля не змінює геометрію острова? }
procedure Write32(var Code:RawByteString;At0:SizeInt;Value:Int64);
var I:SizeInt;B:LongWord;
begin
  Need((At0>=0) and (At0+4<=Length(Code)) and
    (Value>=Low(LongInt)) and (Value<=High(LongInt)),
    'x86 rel32 поза перевіреними межами');
  B:=LongWord(LongInt(Value));
  UniqueString(Code);
  for I:=0 to 3 do begin
    Code[At0+I+1]:=AnsiChar(Byte(B and $FF));B:=B shr 8;
  end;
end;

{ У PT_LOAD: 64-bit fields FileSz/MemSz, raw physical ELF64 bytes.
  Це змінює ТІЛЬКИ host geometry, не домен і не закон SENS. }
procedure Write64(var Image:RawByteString;At0:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((At0>=0) and (At0+8<=Length(Image)),
    'ELF64 PT_LOAD поза образом');
  UniqueString(Image);
  for I:=0 to 7 do begin
    Image[At0+I+1]:=AnsiChar(Byte(Value and $FF));Value:=Value shr 8;
  end;
end;

{ Вхід двох exact W12 декодує ПОВНІСТЮ існуючий донор, включно
  з host EOF. Додаємо code island ПІСЛЯ байтів донора. Перша JMP
  переправляє управління після physical decode до машинного ADD:
    - signed sum ∈ D12 → НЕЗМІНЕНИЙ donor encode3;
    - інакше → exact D24 encode5 lookup через EncodeT5M.
  Base та Island належать функції, вихідний ELF — caller.
  Ніяких констант обчислення чи FPC-додавення мовних даних.
  1) Чому старі decoder RIP-rel32 лишаються незмінними?
  2) Чому JMP не можна направляти на байти таблиці?
  3) Що гарантує signed compare після 32-bit ADD?
  4) Чому треба записати 5 canonical T5M байтів для D24?
  5) Що станеться при короткому syscall write? }
function BuildAdaptiveD12ArithmeticELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString;
  const ALU:TAdaptiveAlu):RawByteString;
var Base,Island,Table5,Table4,WordsEncoded,Pattern,AnchorProof:RawByteString;
    Words:TExactWords;
    G:TELFGeometry;At,JumpTarget,DonorEncode,WideAt:SizeInt;
    UpperBranch,LowerBranch,ToDonor,WriteFail:SizeInt;
    ReadLea:array[0..4] of SizeInt;
    I,K,Shift,ChunkMask,TableSize,Offset,Count:SizeInt;

  procedure Emit(const Bytes:RawByteString);
  begin
    Need((Length(Bytes)>0) and (Length(Island)+Length(Bytes)<2048),
      'x86 D24 code island перевищив квоту');
    Island:=Island+Bytes;
  end;
  procedure Emit32(Value:LongWord);
  var J:SizeInt;
  begin
    for J:=0 to 3 do begin
      Emit(AnsiChar(Byte(Value and $FF)));Value:=Value shr 8;
    end;
  end;
  procedure JumpTo(const Target:SizeInt;const PatchAt0:SizeInt;
    const InstructionBytes:SizeInt);
  begin
    Write32(Island,PatchAt0,
      Int64(Target)-Int64(Length(Base)+PatchAt0+4));
  end;
begin
  Result:='';
  { Admission коректного фізичного D5 ADD якоря здійснює вже ратифікований
    pinned D2/WideIR шлях. ELF якоря — лише перевірка допуску,
    а runtime отримує нові два W12 зі stdin. }
  if ALU=aaAdd then
    AnchorProof:=BuildIRWideAddRegisterELF(PhysicalAnchor,AuthorityRoot)
  else
    AnchorProof:=BuildIRWideSubELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(AnchorProof,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes),
    'фізичний D5 ADD/SUB якір не пройшов pinned WideIR');
  Base:=BuildD12StreamAddELF;
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Base)) and (Length(Base)<MaxBytes),
    'donor ELF64 PIE не підтверджено');
  Pattern:=#$44#$89#$C0#$44#$01#$C8;
  At:=Pos(Pattern,Base);
  Need((At>HeaderBytes+60) and
    (At+PreviousAluBytes+10<Length(Base)) and
    (Pos(Pattern,Copy(Base,At+1,Length(Base)-At))=0),
    'machine ADD slot не унікальний');
  DonorEncode:=At+PreviousAluBytes-1; { absolute 0-based ELF offset }
  Need(Copy(Base,At+PreviousAluBytes,5)=#$89#$D8#$C1#$E8#$07,
    'донорський exact D12 encoder змінився');
  SetLength(Words,1);
  Table5:='';Table4:='';
  for I:=0 to 31 do begin
    Words[0]:=BitPattern(I,5);
    WordsEncoded:=EncodeT5M(Words);
    Need(Length(WordsEncoded)=1,'невірний T5M W5 lookup');
    Table5:=Table5+WordsEncoded;
  end;
  for I:=0 to 15 do begin
    Words[0]:=BitPattern(I,4);
    WordsEncoded:=EncodeT5M(Words);
    Need(Length(WordsEncoded)=1,'невірний T5M W4 lookup');
    Table4:=Table4+WordsEncoded;
  end;
  Need((Length(Table5)=32) and (Length(Table4)=16) and
    (Length(Base)+512+Length(Table5)+Length(Table4)<MaxBytes),
    'T5M D24 lookup поза квотою');

  Island:='';
  Emit(#$44#$89#$C0);                   { mov eax,r8d }
  if ALU=aaAdd then
    Emit(#$44#$01#$C8)                  { add eax,r9d }
  else
    Emit(#$44#$29#$C8);                 { sub eax,r9d }
  Emit(#$89#$C3);                       { mov ebx,eax: signed sum }
  Emit(#$3D#$FF#$07#0#0);              { cmp eax,2047 }
  UpperBranch:=Length(Island);
  Emit(#$0F#$8F#0#0#0#0);               { jg wide }
  Emit(#$3D#0#$F8#$FF#$FF);             { cmp eax,-2048 }
  LowerBranch:=Length(Island);
  Emit(#$0F#$8C#0#0#0#0);               { jl wide }
  Emit(#$81#$E3#$FF#$0F#0#0);          { and ebx,4095 }
  ToDonor:=Length(Island);
  Emit(#$E9#0#0#0#0);                   { jmp existing encode3 }
  WideAt:=Length(Island);
  Emit(#$81#$E3#$FF#$FF#$FF#0);        { and ebx,0FFFFFFh }
  for I:=0 to 4 do begin
    Shift:=24-((I+1)*5);
    if Shift<0 then Shift:=0;
    if I=4 then ChunkMask:=15 else ChunkMask:=31;
    Emit(#$89#$D8);                     { mov eax,ebx }
    if Shift<>0 then begin
      Emit(#$C1#$E8);Emit(AnsiChar(Byte(Shift))); { shr eax,imm8 }
    end;
    Emit(#$83#$E0);Emit(AnsiChar(Byte(ChunkMask)));
    ReadLea[I]:=Length(Island);
    Emit(#$48#$8D#$35#0#0#0#0);        { lea rsi,[rip+T5M lookup] }
    Emit(#$8A#$04#$06);                { mov al,[rsi+rax] }
    if I=0 then Emit(#$88#$04#$24)
    else begin
      Emit(#$88#$44#$24);Emit(AnsiChar(Byte(I)));
    end;
  end;
  Emit(#$B8#$01#0#0#0);                { write(stdout,rsp,5) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$05#0#0#0);
  Emit(#$0F#$05);
  Emit(#$48#$83#$F8#$05);              { cmp rax,5 }
  WriteFail:=Length(Island);
  Emit(#$0F#$85#0#0#0#0);              { jne fail exit(2) }
  Emit(#$B8#$3C#0#0#0);                { exit(0) }
  Emit(#$31#$FF);
  Emit(#$0F#$05);
  JumpTarget:=Length(Island);
  Emit(#$B8#$3C#0#0#0);                { exit(2) }
  Emit(#$BF#$02#0#0#0);
  Emit(#$0F#$05);

  Write32(Island,UpperBranch+2,WideAt-(UpperBranch+6));
  Write32(Island,LowerBranch+2,WideAt-(LowerBranch+6));
  Write32(Island,WriteFail+2,JumpTarget-(WriteFail+6));
  { Destination of original donor D12 T5M encode, absolute file offset. }
  Write32(Island,ToDonor+1,
    Int64(DonorEncode)-(Int64(Length(Base))+Int64(ToDonor)+5));
  for I:=0 to 4 do begin
    if I=4 then Offset:=Length(Table5) else Offset:=0;
    Write32(Island,ReadLea[I]+3,
      Int64(Length(Island)+Offset)-Int64(ReadLea[I]+7));
  end;
  Need(Length(Base)+Length(Island)+Length(Table5)+Length(Table4)<MaxBytes,
    'ELF D24 розширення поза квотою');
  Result:=Base+Island+Table5+Table4;
  { Replace only exact machine entry of already-verified ALU; all
    original code, input checks, D12 encoder and RIP tables unchanged. }
  Need(Copy(Result,At,Length(Pattern))=Pattern,
    'неочікуваний x86 machine body до вставки переходу');
  UniqueString(Result);
  Result[At]:=#$E9;                    { jmp appended code island }
  Write32(Result,At,Int64(Length(Base))-(Int64(At)+4));
  Write64(Result,96,Length(Result));     { ELF p_filesz }
  Write64(Result,104,Length(Result));    { ELF p_memsz }
  Need((Copy(Result,At,1)=#$E9) and
    (Copy(Result,At+PreviousAluBytes,5)=#$89#$D8#$C1#$E8#$07),
    'втрачено machine fast path');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'ELF64 D12/D24 PIE geometry не підтверджено');
end;

function BuildAdaptiveD12AddStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:=BuildAdaptiveD12ArithmeticELF(PhysicalAnchor,AuthorityRoot,aaAdd);
end;

function BuildAdaptiveD12SubStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:=BuildAdaptiveD12ArithmeticELF(PhysicalAnchor,AuthorityRoot,aaSub);
end;

{ G6.240: не змінюємо жодного з двох донорських Build...StreamELF.
  Передаємо нові owned ELF байти спільному x64frameio лише після
  точного pinned WideIR admission і вже перевіреної PIE геометрії.
  Префікс повторює Linux read до шести байтів, потім перевіряє EOF.
  Ці функції призначені тільки для CLI host stdin, не для QUOT.
  1) Що зберігає оригінальний x86-64 RIP-relative displacement?
  2) Чому донор не може бути загорнутий двічі?
  3) Чому це механізм, не семантика D5?
  4) Який lifetime проміжного RawByteString? }
function WrapAdaptive(const Donor:RawByteString):RawByteString;
var G:TELFGeometry;
begin
  Result:=WrapExactSixByteFrame(Donor);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)) and (Length(Result)>Length(Donor)),
    'адаптивний D12/D24 ELF після EOF-префікса має невірну PIE геометрію');
end;

function BuildAdaptiveD12AddFramedELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:=WrapAdaptive(BuildAdaptiveD12AddStreamELF(PhysicalAnchor,AuthorityRoot));
end;

function BuildAdaptiveD12SubFramedELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:=WrapAdaptive(BuildAdaptiveD12SubStreamELF(PhysicalAnchor,AuthorityRoot));
end;
end.
