{ G6 — точний HOST x86-64 механізм знакового розширення 12 бітів.
  Це НЕ ратифікація D12, не SENS evaluator, не оракул мовних законів.
  Вхід: LongInt з довільними старшими 20 бітами; результат LongInt
  з двійковим доповняльним знаковим розширенням лише low12.
  Без heap, без state; cdecl — Linux SysV x86-64 ABI.
  Питання: чому cdecl? чому EDI? чому 20? навіщо всі 4096?
  чому ця механічна рівність ще не доводить SENS D12 семантику? }
program test_d12_znak_asm;
{$mode objfpc}{$H+}{$codepage utf8}
{$asmmode intel}
{$if not defined(CPUX86_64)}
  {$fatal Потрібен Linux x86-64}
{$endif}
{$if not defined(LINUX)}
  {$fatal Потрібен Linux x86-64 SysV ABI}
{$endif}
uses SysUtils;

function PascalExtend12(const X:LongInt):LongInt;
var Low:LongInt;
begin
  Low:=X and $FFF;
  if (Low and $800)<>0 then
    Result:=Low-$1000
  else
    Result:=Low;
end;

{ cdecl на Linux/x86-64: перший 32-bit параметр у EDI;
  без звернення до Pascal імені з невизначеним register allocation.
  Змінюємо тільки caller-saved EAX; nostackframe не торкає стек. }
function AsmExtend12(const X:LongInt):LongInt; cdecl; nostackframe; assembler;
asm
  mov eax,edi
  shl eax,20
  sar eax,20
end;

var Checks:LongInt=0;
procedure Check(const X:LongInt);
var P,A:LongInt;
begin
  P:=PascalExtend12(X);
  A:=AsmExtend12(X);
  if (P<>A) or ((A and $FFF)<>(X and $FFF)) or
     (A < -2048) or (A > 2047) then begin
    WriteLn(StdErr,'Д12-АСМ-ПОМИЛКА вхід=',X,
      ' Pascal=',P,' ASM=',A);
    Halt(1);
  end;
  Inc(Checks);
end;

var Bits:LongInt;
begin
  for Bits:=0 to 4095 do begin
    Check(Bits);
    Check(Bits or $12345000);
    Check(Bits or LongInt(-4096));
    Check(Bits or LongInt(-65536));
  end;
  { Граничні знакові 32-бітові host значення і типові переходи. }
  Check(Low(LongInt));
  Check(High(LongInt));
  Check(-2049);
  Check(-2048);
  Check(-1);
  Check(0);
  Check(2047);
  Check(2048);
  Check(4095);
  Check(4096);
  if Checks<>16394 then begin
    WriteLn(StdErr,'Д12-АСМ-ПОМИЛКА лічильник=',Checks);
    Halt(2);
  end;
  WriteLn('Д12-АСМ-ГАРАЗД фігур=4096 контекстів=4 перевірок=',
    Checks,' Pascal=exact ASM=exact ABI=linux-x64 energy=NOT-MEASURED');
end.
