{ G6.125 — canonical packed .sens D5:01010 → існуючий pinned WideIR
  admission → SSE2 PADDQ xmm8,xmm9 → НЕЗМІНЕНІ D12/T5M lookup + write.
  Закон «додати», його аргументи й overflow — ЛИШЕ в pinned SENS та
  перевіреному BuildIRWideAddRegisterELF, НЕ в цьому host-модулі.
  ProgramPhysical — borrowed бінарний T5M, AuthorityRoot — borrowed
  pinned шлях; Result — нові owned bytes ELF64 ET_DYN, або exception.
  Жодного dispatch за D7-іменами та власних числових визначень.
  1) Де відбувається pinned binding голови та D12?
  2) Чому MOVD+PADDQ+MOVD із результатом у EAX не міняє D12 writer?
  3) Чому rel32 лишаються незмінними після збільшення прологу?
  4) Чому без VerifySENSELF64 не можна повертати результат?
  5) Яку межу доказу ставить повний executable + незалежний REPL? }
unit wsm.irwideaddsse2;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideAddSSE2Error=class(Exception);
function BuildIRWideAddSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwideaddreg,wsm.x64code,wsm.x64sse2,wsm.elfgeometry;
const
  HeaderBytes=120;
  PreviousPrologueBytes=12; { MOV EAX,imm32; MOV ECX,imm32; ADD EAX,ECX }
  SIMDPrologueBytes=30;
procedure Require(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideAddSSE2Error.Create(Why);
end;
function Read32(const Bytes:RawByteString;Offset:SizeInt):LongWord;
var I:SizeInt;
begin
  Require((Offset>=0) and (Offset<=Length(Bytes)-4),
          'машинний immediate за межами ELF');
  Result:=0;
  for I:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Bytes[Offset+I+1]));
end;
procedure Put64(var Bytes:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Require((Offset>=0) and (Offset<=Length(Bytes)-8),
          'поля ELF за межами образу');
  for I:=0 to 7 do begin
    Bytes[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function BuildIRWideAddSSE2ELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Original,Prologue,Candidate:RawByteString;
    Code:TX64Code;Geom:TELFGeometry;LeftImm,RightImm:LongWord;
begin
  Result:='';
  { Єдиний допуск: уже злитий незалежно перевірений pinned D2/D5/W12
    WideIR та AddNumericPhysical. У разі помилки тут не буде ELF. }
  Original:=BuildIRWideAddRegisterELF(ProgramPhysical,AuthorityRoot);
  VerifySENSELF64(Original,Geom);
  Require((Geom.Kind=3) and (Geom.Entry=HeaderBytes) and
    (Geom.FileBytes=Length(Original)) and
    (Length(Original)>HeaderBytes+PreviousPrologueBytes+36),
    'попередній verified D5 ELF має неочікувану геометрію');
  Require((Original[HeaderBytes+1]=#$B8) and
    (Original[HeaderBytes+6]=#$B9) and
    (Original[HeaderBytes+11]=#$01) and
    (Original[HeaderBytes+12]=#$C8) and
    (Original[HeaderBytes+13]=#$25),
    'змінився завірений профіль D5 ALU; патч заборонено');
  LeftImm:=Read32(Original,HeaderBytes+1);
  RightImm:=Read32(Original,HeaderBytes+6);

  X64Reset(Code);
  X64MovImm32(Code,xrAX,LeftImm);
  X64MovImm32(Code,xrCX,RightImm);
  { MOVD XMM8,EAX; MOVD XMM9,ECX (66 REX.R 0F 6E /r).
    MOVD обнуляє 96 старших біт XMM — low 32 PADDQ є точною
    двійковою сумою mod 2^32; upstream D12 overflow уже відхилено.
    Це тільки машинний перенос, НЕ закон SENS. }
  Code.Bytes:=Code.Bytes+#$66#$44#$0F#$6E#$C0+
                          #$66#$44#$0F#$6E#$C9;
  X64SSE2RegReg(Code,soAddQ,8,9);
  { MOVD EAX,XMM8: із 64-бітного результату взято low32,
    наступний *наявний* 'AND EAX,0FFFh' і T5M writer незмінні. }
  Code.Bytes:=Code.Bytes+#$66#$44#$0F#$7E#$C0;
  Prologue:=X64Image(Code);
  Require((Length(Prologue)=SIMDPrologueBytes) and
    (Copy(Prologue,11,5)=#$66#$44#$0F#$6E#$C0) and
    (Copy(Prologue,16,5)=#$66#$44#$0F#$6E#$C9) and
    (Copy(Prologue,21,5)=#$66#$45#$0F#$D4#$C1) and
    (Copy(Prologue,26,5)=#$66#$44#$0F#$7E#$C0),
    'неповний машинний XMM8/XMM9 PADDQ lowering');

  { Зсув лише перед НЕЗМІНЕНИМ хвостом: rel32 відстані між
    адресами LEA й таблицями лишилися точними. Жодної перестановки
    байтів T5M, result constants або D12 bit-проекції. }
  Candidate:=Copy(Original,1,HeaderBytes)+Prologue+
    Copy(Original,HeaderBytes+PreviousPrologueBytes+1,
         Length(Original)-HeaderBytes-PreviousPrologueBytes);
  Require(Length(Candidate)=Length(Original)+
     SIMDPrologueBytes-PreviousPrologueBytes,
     'невірна фізична довжина SSE2 ELF');
  Put64(Candidate,96,QWord(Length(Candidate)));
  Put64(Candidate,104,QWord(Length(Candidate)));
  VerifySENSELF64(Candidate,Geom);
  Require((Geom.Kind=3) and (Geom.Entry=HeaderBytes) and
     (Geom.FileBytes=Length(Candidate)),
     'новий SSE2 ELF64 не пройшов геометрію');
  Result:=Candidate;
end;
end.
