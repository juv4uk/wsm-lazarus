{ G6.134 — D5:10110, machine IMUL з двома фізичними D12 зі stdin.
  Закон, domain-qualified binding і повний D2 anchor перевіряє тільки
  pinned SENS через вже існуючий одноразовий TVerifiedWideContext/LowerVerifiedMul.
  Host transport / кодек / 6-байтовий frame — existing ELF donor.
  Result — owned RawByteString ELF64 PIE, життєвий цикл у викликачі.
  У D12→D24 — відмова, НЕ усічене 12-бітове значення.
  1) Чому машинний IMUL сам не встановлює мовний закон?
  2) Чому порівнюємо точні machine bytes до patch?
  3) Чому зміщення Jcc має зменшитися на одиницю?
  4) Чому xchg eax,ebx замінює двобайтовий mov ebx,eax?
  5) Де підтверджено Canonical T5M і відмову при D24? }
unit wsm.elfd12mulpotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12MulStream=class(Exception);
function BuildVerifiedD12MulStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.verifiedwidecontext,wsm.verifiedmul,
     wsm.elfd12potik,wsm.elfgeometry,wsm.x64frameio;
const HeaderBytes=120; AluBytes=35;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12MulStream.Create(Why) end;

{ S: borrowed машинний образ; At1: 1-based byte index.
  Result: signed little-endian rel32 без host pointer aliasing.
  1) Чому LongWord потрібен до перетворення в LongInt?
  2) Чому чотири байти читаються в явному порядку?
  3) Чому це host relocation, не SENS координата? }
function ReadDisp32(const S:RawByteString;At1:SizeInt):LongInt;
var I:SizeInt;V:LongWord;
begin
  Need((At1>=1) and (At1+3<=Length(S)),
    'machine rel32 поза ELF');
  V:=0;
  for I:=0 to 3 do V:=V or (LongWord(Byte(S[At1+I])) shl (I*8));
  Result:=LongInt(V);
end;

{ Value: signed rel32. Result: owned exact 4 bytes LE.
  1) Чому signed зберігається як bit-pattern?
  2) Коли ці чотири байти звільняє FPC?
  3) Чому endianness тут не задає закон D5? }
function Bytes32(Value:LongInt):RawByteString;
var I:SizeInt;V:LongWord;
begin
  V:=LongWord(Value);SetLength(Result,4);
  for I:=1 to 4 do begin
    Result[I]:=AnsiChar(Byte(V and $FF));V:=V shr 8;
  end;
end;

{ Старий 35-byte ALU:
   MOV EAX,R8D (3) ADD EAX,R9D (3)
   CMP 2047 (5) JG fail (6) CMP -2048 (5) JL fail (6)
   AND EAX,0FFFh (5) MOV EBX,EAX (2).
  Новий тієї ж ширини:
   MOV (3) IMUL EAX,R9D (4) CMP (5) JG (6) CMP (5) JL (6)
   AND (5) XCHG EAX,EBX (1).
  Обидва Jcc завершуються на 1 байт пізніше => disp-1,
  ціль відмови при цьому фізично НЕ рухається.
  Ніякої Pascal реалізації множення в machine function немає.
  1) Чому 3+4+5+6+5+6+5+1=35?
  2) Чому невідома донорська форма має бути відхилена?
  3) Чому CPU виконує signed IMUL лише після sign-extend D12?
  4) Що сталося б без disp-1?
  5) Чому відсутнє тихе D24→D12 звуження? }
function BuildVerifiedD12MulStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,Base,Patch,Needle:RawByteString;
    At,OldUpper,OldLower:SizeInt;G:TELFGeometry;
    Context:TVerifiedWideContext;
begin
  Result:='';
  { Підтвердити pinned D5:10110 та фізичні D12 одним WideIR;
    opaque Context живе лише в цьому блоці, отриманий Proof — власні
    FPC-managed ELF bytes, що не впливають на семантику потоку.
    1) Чому контекст не потрібно повторно декодувати?
    2) Чому обмеження D12 перевіряє LowerVerifiedMul, не host IMUL?
    3) Хто звільняє FIR/Stats після Lower?
    4) Чому proof ELF можна звільнити після перевірки геометрії? }
  Context:=TVerifiedWideContext.Create(PhysicalAnchor,AuthorityRoot);
  try Proof:=Context.Lower(@LowerVerifiedMul)
  finally Context.Free end;
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Proof)),
    'pinned D5:10110 WideIR не допустив цілісний D2 якір');
  Base:=BuildD12StreamAddELF;
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Base)),
    'потоковий T5M/D12 машинний донор не допущено');
  Needle:=#$44#$89#$C0#$44#$01#$C8;
  At:=Pos(Needle,Base);
  Need((At>HeaderBytes) and (At+AluBytes-1<=Length(Base)) and
    (Pos(Needle,Copy(Base,At+1,Length(Base)-At))=0),
    'не знайдено єдиного exact ALU slot');
  Need((Copy(Base,At+6,5)=#$3D#$FF#$07#0#0) and
    (Copy(Base,At+11,2)=#$0F#$8F) and
    (Copy(Base,At+17,5)=#$3D#0#$F8#$FF#$FF) and
    (Copy(Base,At+22,2)=#$0F#$8C) and
    (Copy(Base,At+28,5)=#$25#$FF#$0F#0#0) and
    (Copy(Base,At+33,2)=#$89#$C3),
    'донор змінив ALU або D12 overflow gates');
  OldUpper:=ReadDisp32(Base,At+13);
  OldLower:=ReadDisp32(Base,At+24);
  Need((OldUpper>0) and (OldUpper<4096) and
    (OldLower>0) and (OldLower<4096),
    'неочікувана адреса machine fail-closed jump');
  Patch:=#$44#$89#$C0 + #$41#$0F#$AF#$C1 +
         #$3D#$FF#$07#0#0 + #$0F#$8F+Bytes32(OldUpper-1) +
         #$3D#0#$F8#$FF#$FF + #$0F#$8C+Bytes32(OldLower-1) +
         #$25#$FF#$0F#0#0 + #$93;
  Need(Length(Patch)=AluBytes,'IMUL змінив x86 довжину або RIP таблиці');
  Result:=Copy(Base,1,At-1)+Patch+
    Copy(Base,At+AluBytes,Length(Base)-(At+AluBytes)+1);
  Need((Length(Result)=Length(Base)) and
    (ReadDisp32(Result,At+14)=OldUpper-1) and
    (ReadDisp32(Result,At+25)=OldLower-1),
    'IMUL не зберіг branch targets');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'IMUL ELF64 PIE зіпсував геометрію');
  { Існуючий exact-six-byte I/O префікс підтверджує повний кадр,
    включно з 7-м байтом, і не пересуває жоден внутрішній rel32. }
  Result:=WrapExactSixByteFrame(Result);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)),
    'після exact stdin перевірки ELF64 PIE не підтверджено');
end;
end.
