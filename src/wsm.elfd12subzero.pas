{ G6.241 — один нативний x86-64 ELF64: D12 віднімання, потім D12 «нуль?».
  Два механізми мають власний pinned admission у чинних донорських модулях;
  цей composer не додає ратифікованих законів, реєстру чи текстового dispatch.
  Borrowed фізичні T5M входи не мутують; Result — owned FPC RawByteString.
  Переповнення різниці до D24 відхиляємо до ELF, бо донор «нуль?» є D12-only.
  Запитання: 1) Чому D24 не можна мовчки обрізати до W12?
  2) Чому machine SUB зберігає runtime-обчислення?
  3) Чому RIP-relative displacement не змінюється від вставки до LEA?
  4) Хто володіє ELF Result після повернення?
  5) Чому D1:0 тут не є числовим нулем? }
unit wsm.elfd12subzero;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ESubZeroELFError=class(Exception);
function BuildD12SubZeroELF(
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericsub,wsm.numericplane,wsm.elfd12sub,wsm.elfd12zero,
     wsm.elfgeometry;
const HeaderBytes=120;PrefixBytes=5;SubBytes=5;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise ESubZeroELFError.Create(Why);
end;

{ Image is owned managed ELF64. Offset is ZERO-based physical offset
  of the two little-endian ELF PT_LOAD length fields, not a SENS domain. }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
       'поле ELF64 поза фізичним образом');
  UniqueString(Image);
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ SubELF emits MOV EAX,left; SUB EAX,right + verified T5M output.
  ZeroELF emits MOV EAX,difference; TEST/SETE/MOVZX + verified D1 T5M.
  Only replace the first MOV of ZeroELF with verified MOV+SUB of SubELF.
  The extra 5 bytes precede ALL zero-writer LEA and its lookup table;
  their relative positions remain identical. No constant-fold result. }
function BuildD12SubZeroELF(
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var SubImage,ZeroImage,Difference:RawByteString;
    Number:TExplicitNumeric;
    SubGeometry,ZeroGeometry,FinalGeometry:TELFGeometry;
begin
  Result:='';
  SubImage:=BuildD12SubELF(LeftPhysical,RightPhysical);
  Difference:=SubtractNumericPhysical(LeftPhysical,RightPhysical,12);
  Number:=ReadNumericPhysical(Difference,12);
  Need((Number.DomainWidth=12) and (Length(Number.ExactBits)=12),
       'D12→D24: вузька композиція не підтримує просування');
  ZeroImage:=BuildD12ZeroELF(Difference);
  VerifySENSELF64(SubImage,SubGeometry);
  VerifySENSELF64(ZeroImage,ZeroGeometry);
  Need((SubGeometry.Kind=3) and (ZeroGeometry.Kind=3) and
       (SubGeometry.Entry=HeaderBytes) and
       (ZeroGeometry.Entry=HeaderBytes) and
       (SubGeometry.FileBytes=Length(SubImage)) and
       (ZeroGeometry.FileBytes=Length(ZeroImage)),
       'донорські ELF64 PIE не пройшли перевірку геометрії');
  Need((Length(SubImage)>HeaderBytes+10) and
       (Length(ZeroImage)>HeaderBytes+10),
       'завершено неповний x86-64 машинний префікс');
  Need((SubImage[HeaderBytes+1]=#$B8) and
       (SubImage[HeaderBytes+6]=#$2D) and
       (ZeroImage[HeaderBytes+1]=#$B8) and
       (Copy(ZeroImage,HeaderBytes+6,5)=#$85#$C0#$0F#$94#$C0),
       'донорські машинні шаблони MOV/SUB/TEST/SETE змінилися');
  Need(Length(ZeroImage)<1024*1024-SubBytes,
       'машинний образ перевищує обмежену квоту');
  Result:=Copy(ZeroImage,1,HeaderBytes)+
          Copy(SubImage,HeaderBytes+1,PrefixBytes+SubBytes)+
          Copy(ZeroImage,HeaderBytes+PrefixBytes+1,
               Length(ZeroImage)-HeaderBytes-PrefixBytes);
  Need(Length(Result)=Length(ZeroImage)+SubBytes,
       'втрачено байти при фізичній композиції');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=Length(Result)) and
       (Copy(Result,HeaderBytes+1,1)=#$B8) and
       (Copy(Result,HeaderBytes+6,1)=#$2D) and
       (Copy(Result,HeaderBytes+11,5)=#$85#$C0#$0F#$94#$C0),
       'не підтверджено кінцевий нативний SUB/TEST/SETE ELF64');
end;
end.
