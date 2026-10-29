{ G6.77 — точний native D5:01000 предикат "нуль?" над D12.
  Закон і профіль є ЛИШЕ у pinned SENS 12.0:
    lib/domains/d5.lisp, machine/profile/current-domain-x86-64.lisp.
  Механізм: x86-64 TEST/SETE/MOVZX, НЕ FPC precomputed true/false.
  Один D12 packed T5M вхід -> executable ELF64 PIE -> D1 packed T5M. }
unit wsm.elfd12zero;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12ZeroELFError=class(Exception);
function BuildD12ZeroELF(const Physical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;

const HeaderBytes=120;
procedure Require(Ok:Boolean;const Why:RawByteString);
begin
  if not Ok then raise ED12ZeroELFError.Create(Why);
end;

{ Borrowed exact D12 bits, signed immediate in host LongInt.
  Не змінює ownership ані домен, ані ширину; тільки значення для x86 MOV.
  1) Чому Width має бути 12, не 8/16?
  2) Чому провідна одиниця — signed value?
  3) Чому цей MOV не створює нової SENS функції? }
function Immediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Require(Length(Bits)=12,'потрібна рівно фізична ширина D12');
  V:=0;
  for I:=1 to 12 do begin
    Require(Bits[I] in ['0','1'],'неприпустимий біт D12');
    V:=V*2+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

{ Фізичні байти відповіді D1:0/1 походять тільки з pinned T5M codec.
  Не ототожнювати індекс host-таблиці з доменом SENS.
  1) Де встановлюється точний D1?
  2) Чому таблиця має рівно 2 байти?
  3) Хто володіє Words та Result? }
function D1PhysicalByte(Bit:AnsiChar):AnsiChar;
var Words:TExactWords; Packed:RawByteString;
begin
  Require(Bit in ['0','1'],'недопущений біт D1');
  SetLength(Words,1);Words[0]:=Bit;
  Packed:=EncodeT5M(Words);
  Require(Length(Packed)=1,'канонічна D1 одиниця не є одним T5M байтом');
  Result:=Packed[1];
end;

{ Physical — borrowed, ReadNumericPhysical вимагає точно D12.
  Result — managed owned ELF64 ET_DYN image, виконується Linux x86-64.
  TEST eax,eax -> SETE al -> MOVZX eax,al, лише потім [D1 table + eax].
  Наприкінці Linux write(1,rsp,1), exit(0); немає готової відповіді.
  Verified image має один RX PT_LOAD, stack є власністю ядра Linux.
  1) Чим machine SETE відрізняється від Pascal порівняння?
  2) Чому Result не може бути D12 числом або D3:000?
  3) Чому не дозволяємо іншого Dn через довжину байтів?
  4) Як RIP displacement працює при ASLR?
  5) Чому VerifySENSELF64 перед поверненням? }
function BuildD12ZeroELF(const Physical:RawByteString):RawByteString;
var Number:TExplicitNumeric; V:LongInt;
    Code,Table:RawByteString;
    LeaPos,CodeBytes,I:SizeInt;
    Geometry:TELFGeometry;

  procedure Emit(const S:RawByteString);
  begin
    Code:=Code+S;
    Require(Length(Code)<4096,'машинна програма поза лімітом');
  end;

  procedure Emit32(Val:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin Emit(AnsiChar(Val and $FF));Val:=Val shr 8 end;
  end;

  procedure Patch32(var S:RawByteString;Pos0:SizeInt;Val:LongWord);
  var K:SizeInt;
  begin
    Require((Pos0>=0) and (Pos0+4<=Length(S)),
      'неприпустима RIP-relative геометрія');
    for K:=0 to 3 do begin
      S[Pos0+K+1]:=AnsiChar(Val and $FF);
      Val:=Val shr 8;
    end;
  end;

  procedure Put(Off:SizeInt;Value:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Require((Off>=0) and (Count>0) and (Count<=8) and
      (Off+Count<=Length(Result)),'поле ELF поза фізичним образом');
    for K:=0 to Count-1 do begin
      Result[Off+K+1]:=AnsiChar(Value and $FF);
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  Number:=ReadNumericPhysical(Physical,12);
  Require(Number.DomainWidth=12,'потрібен явний точний D12');
  V:=Immediate12(Number.ExactBits);
  Table:=D1PhysicalByte('0')+D1PhysicalByte('1');
  Require(Length(Table)=2,'відсутній перевірений двійковий D1');

  Code:='';
  Emit(#$B8);Emit32(LongWord(V));    { MOV eax,explicit signed D12 }
  Emit(#$85#$C0);                  { TEST eax,eax — не Pascal }
  Emit(#$0F#$94#$C0);              { SETE al -> внутрішній 0/1 }
  Emit(#$0F#$B6#$C0);              { MOVZX eax,al -> 0 або 1 }
  LeaPos:=Length(Code);
  Emit(#$48#$8D#$35#0#0#0#0);      { LEA rsi,[rip+D1 table] }
  Emit(#$8A#$14#$06);              { MOV dl,[rsi+rax] }
  Emit(#$48#$83#$EC#$08);          { приватний стек-буфер }
  Emit(#$88#$14#$24);              { MOV [rsp],dl }
  Emit(#$B8#$01#0#0#0);            { Linux write(fd=1,buf=rsp,n=1) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$01#0#0#0);
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);            { Linux exit(0) }
  Emit(#$31#$FF#$0F#$05);
  CodeBytes:=Length(Code);
  Patch32(Code,LeaPos+3,LongWord(CodeBytes-(LeaPos+7)));

  SetLength(Result,HeaderBytes+CodeBytes+Length(Table));
  FillChar(Result[1],Length(Result),0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to Length(Table) do Result[HeaderBytes+CodeBytes+I]:=Table[I];
  VerifySENSELF64(Result,Geometry);
  Require((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
    (Geometry.Entry=HeaderBytes),'не підтверджена ELF64 PIE геометрія');
end;
end.
