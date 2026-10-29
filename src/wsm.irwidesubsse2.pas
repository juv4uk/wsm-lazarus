{ G6.128 — machine-only SSE2 PSUBQ lowering для pinned фізичного D5:01011.
  Закон, D12/D24 promotion і допуск виклику — ТІЛЬКИ у pinned SENS
  та перевіреному wsm.irwidesub; цей модуль не визначає віднімання.
  ProgramPhysical/AuthorityRoot — borrowed RawByteString; Result —
  власний керований ELF64 ET_DYN; локальні буфери звільняє FPC.
  1) Де перевірено точну голову D5 і обидва D12 операнди?
  2) Чому MOVD/PSUBQ/MOVD бере лише молодші 32 біти?
  3) Хто вирішує, коли потрібний ширший D24 результат?
  4) Чому RIP-відносні адреси в незмінному хвості лишаються вірні?
  5) Чому геометрія ELF та реальне виконання — різні докази? }
unit wsm.irwidesubsse2;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideSubSSE2Error=class(Exception);
function BuildIRWideSubSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwidesub,wsm.x64code,wsm.elfgeometry;
const
  HeaderBytes=120;
  PreviousPrologueBytes=10; { MOV EAX,imm32; SUB EAX,imm32 }
  SIMDPrologueBytes=30;     { MOV EAX/ECX, MOVD x2, PSUBQ, MOVD }
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideSubSSE2Error.Create(Why);
end;
function Read32(const Bytes:RawByteString;Offset:SizeInt):LongWord;
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Bytes)-4),
       'machine immediate за межами ELF');
  Result:=0;
  for I:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Bytes[Offset+I+1]));
end;
procedure Put64(var Bytes:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Bytes)-8),
       'поле довжини ELF поза образом');
  for I:=0 to 7 do begin
    Bytes[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function BuildIRWideSubSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Original,Prologue,Candidate:RawByteString;
    Code:TX64Code;Geometry:TELFGeometry;
    LeftImm,RightImm:LongWord;
begin
  Result:='';
  { Єдиний допуск фізичного D5/D12 і рішення D12→D24 — downstream
    чинного pinned WideIR. Жодного власного числового закону. }
  Original:=BuildIRWideSubELF(ProgramPhysical,AuthorityRoot);
  VerifySENSELF64(Original,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Original)) and
       (Length(Original)>HeaderBytes+PreviousPrologueBytes+36),
       'неочікувана геометрія перевіреного D5 SUB ELF');
  Need((Original[HeaderBytes+1]=#$B8) and
       (Original[HeaderBytes+6]=#$2D) and
       (Original[HeaderBytes+11]=#$48) and
       (Original[HeaderBytes+12]=#$83) and
       (Original[HeaderBytes+13]=#$EC) and
       (Original[HeaderBytes+14]=#$08),
       'змінено pinned D5 SUB machine profile; патч заборонено');
  LeftImm:=Read32(Original,HeaderBytes+1);
  RightImm:=Read32(Original,HeaderBytes+6);

  X64Reset(Code);
  X64MovImm32(Code,xrAX,LeftImm);
  X64MovImm32(Code,xrCX,RightImm);
  { MOVD XMM8,EAX і MOVD XMM9,ECX обнуляють верхні біти XMM.
    SSE2 PSUBQ виконує host 64-bit subtraction; low32 точний як
    signed two's-complement result у допущених D12/D24 випадках.
    Цей перенос — host ISA, а НЕ нова операція SENS. }
  Code.Bytes:=Code.Bytes+#$66#$44#$0F#$6E#$C0+
                         #$66#$44#$0F#$6E#$C9+
                         #$66#$45#$0F#$FB#$C1+
                         #$66#$44#$0F#$7E#$C0;
  Prologue:=X64Image(Code);
  Need((Length(Prologue)=SIMDPrologueBytes) and
       (Copy(Prologue,11,5)=#$66#$44#$0F#$6E#$C0) and
       (Copy(Prologue,16,5)=#$66#$44#$0F#$6E#$C9) and
       (Copy(Prologue,21,5)=#$66#$45#$0F#$FB#$C1) and
       (Copy(Prologue,26,5)=#$66#$44#$0F#$7E#$C0),
       'machine PSUBQ XMM8,XMM9 пролог не пройшов guard');

  { Замінено тільки пролог; RIP-relative LEA/таблиці T5M у хвості
    зсуваються разом, тому відстані між ними не міняються. }
  Candidate:=Copy(Original,1,HeaderBytes)+Prologue+
    Copy(Original,HeaderBytes+PreviousPrologueBytes+1,
         Length(Original)-HeaderBytes-PreviousPrologueBytes);
  Need(Length(Candidate)=Length(Original)+
       SIMDPrologueBytes-PreviousPrologueBytes,
       'довжина PSUBQ ELF64 не зберегла точну геометрію');
  Put64(Candidate,96,QWord(Length(Candidate)));
  Put64(Candidate,104,QWord(Length(Candidate)));
  VerifySENSELF64(Candidate,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Candidate)),
       'PSUBQ ELF64 не пройшов фінальну геометрію');
  Result:=Candidate;
end;
end.
