{ G6.242 — двійковий SENS D5:10110 → pinned WideIR → SIMD PMULUDQ.
  Єдиний мовний допуск і D12/D24 арифметичний закон виконує
  чинний BuildIRWideMulELF; цей модуль змінює ТІЛЬКИ host machine code.
  Фізичний вхід — borrowed canonical packed .sens / T5M. Root — borrowed
  pinned SENS; вихід — власний керований RawByteString ELF64 ET_DYN.
  PMULUDQ обчислює unsigned low32 × low32 → low64. Нижні 24 біти
  дорівнюють двійковому signed D12 добутку modulo 2^24, оскільки
  обидва D12 операнди мають модуль <=2048. Точну вихідну ширину
  визначено ДО цього постпроходу; T5M LUT і writer не змінюються.
  1) Чому не можна допустити D12 із самого написання «помножити»?
  2) Чому нижні 24 біти unsigned добутку дорівнюють signed результату?
  3) Навіщо звіряти машинний IMUL-пролог до вставки SSE2?
  4) Чому таблиці RIP-rel32 залишаються чинними після вставки?
  5) Хто володіє ELF байтами та що повертається при відмові? }
unit wsm.irwidemulsse2;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideMulSSE2Error=class(Exception);
function BuildIRWideMulSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwidemul,wsm.x64code,wsm.elfgeometry;
const
  HeaderBytes=120;
  OriginalPrefixBytes=11; { B8 imm32; 69 C0 imm32 }
  SSE2PrefixBytes=30;

procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise EIRWideMulSSE2Error.Create(Why);
end;

function ReadLE32(const Bytes:RawByteString;At0:SizeInt):LongWord;
var J:SizeInt;
begin
  Need((At0>=0) and (At0<=Length(Bytes)-4),
       'поза 32-бітним полем допущеного IMUL');
  Result:=0;
  for J:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Bytes[At0+J+1]));
end;

procedure PutLE64(var Bytes:RawByteString;At0:SizeInt;Value:QWord);
var J:SizeInt;
begin
  Need((At0>=0) and (At0<=Length(Bytes)-8),
       'поле ELF64 поза фізичним образом');
  UniqueString(Bytes);
  for J:=0 to 7 do begin
    Bytes[At0+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Усі числові, структурні та D5 exact-domain перевірки відбуваються
  у єдиному старому компіляторі. Новий SIMD пролог вставлено перед
  незмінним T5M writer; тому відносні адреси LEA→LUT не змінюються.
  Original, Prologue і Candidate — managed bytes із FPC lifetime;
  Result публікується тільки після ELF64 guard. }
function BuildIRWideMulSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Original,Prologue,Candidate:RawByteString;
    Code:TX64Code;G:TELFGeometry;LeftImm,RightImm:LongWord;
begin
  Result:='';
  Original:=BuildIRWideMulELF(ProgramPhysical,AuthorityRoot);
  VerifySENSELF64(Original,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Original)) and
       (Length(Original)>HeaderBytes+OriginalPrefixBytes+36),
       'первісний pinned ELF64 не відповідає точному профілю множення');
  Need((Original[HeaderBytes+1]=#$B8) and
       (Original[HeaderBytes+6]=#$69) and
       (Original[HeaderBytes+7]=#$C0) and
       (Original[HeaderBytes+12]=#$48),
       'первісний IMUL-пролог змінився, SIMD patch заборонено');
  LeftImm:=ReadLE32(Original,HeaderBytes+1);
  RightImm:=ReadLE32(Original,HeaderBytes+7);

  X64Reset(Code);
  X64MovImm32(Code,xrAX,LeftImm);
  X64MovImm32(Code,xrCX,RightImm);
  { MOVD XMM8,EAX / MOVD XMM9,ECX: старші 96 біт XMM = 0.
    PMULUDQ XMM8,XMM9: low32×low32 → low64.
    MOVD EAX,XMM8: low32, достатньо для signed D12×D12 → D24. }
  Code.Bytes:=Code.Bytes+#$66#$44#$0F#$6E#$C0+
                          #$66#$44#$0F#$6E#$C9+
                          #$66#$45#$0F#$F4#$C1+
                          #$66#$44#$0F#$7E#$C0;
  Prologue:=X64Image(Code);
  Need((Length(Prologue)=SSE2PrefixBytes) and
       (Copy(Prologue,11,5)=#$66#$44#$0F#$6E#$C0) and
       (Copy(Prologue,16,5)=#$66#$44#$0F#$6E#$C9) and
       (Copy(Prologue,21,5)=#$66#$45#$0F#$F4#$C1) and
       (Copy(Prologue,26,5)=#$66#$44#$0F#$7E#$C0),
       'пошкоджено machine opcode MOVD/PMULUDQ');

  Candidate:=Copy(Original,1,HeaderBytes)+Prologue+
    Copy(Original,HeaderBytes+OriginalPrefixBytes+1,
         Length(Original)-HeaderBytes-OriginalPrefixBytes);
  Need(Length(Candidate)=Length(Original)+
       SSE2PrefixBytes-OriginalPrefixBytes,
       'змінена довжина ELF після машинного SIMD зниження');
  PutLE64(Candidate,96,QWord(Length(Candidate)));
  PutLE64(Candidate,104,QWord(Length(Candidate)));
  VerifySENSELF64(Candidate,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Candidate)),
       'не пройдено остаточну ELF64 геометрію');
  Result:=Candidate;
end;
end.
