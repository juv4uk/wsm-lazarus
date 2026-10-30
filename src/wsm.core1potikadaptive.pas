{ G6.168 — оригінальний фізичний Core1 додає D12 зі справжнім D24 результатом.
  Тіла бібліотеки НЕ відтворюються в Pascal. Спочатку чинний Core1
  зчитує pinned core1.sens і допускає реальний DEFINE/LAMBDA;
  далі незалежна перевірка точного D5/WideIR якоря і вже злитий
  машинний адаптивний x86-64 backend. Ніякого D7 spelling dispatch. }
unit wsm.core1potikadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ECore1AdaptiveError=class(Exception);
function BuildPinnedCore1AdaptiveAddELF(const RepoRoot:String):RawByteString;
implementation
uses wsm.core1potik,wsm.numericplane,wsm.t5m,
     wsm.irwidedynadd,wsm.elfd12addpotikadaptive,wsm.elfgeometry;

procedure Demand(Ok:Boolean;const Why:String);
begin if not Ok then raise ECore1AdaptiveError.Create(Why) end;

{ RepoRoot — позичений host-шлях до єдиного pinned external/sens.
  Existing — власний managed ELF64 байтовий свідок оригінального Core1.
  Anchor — canonical packed фізична D2 форма точної D5:01010 з
  двома D12 нулями з чинного numeric codec; це лише механічний якір.
  Result — owned managed ELF64 PIE. Тепер він виконує справжній
  signed CPU ADD над двома окремими D12 runtime аргументами і вибирає
  exact 3-byte D12 або 5-byte D24 T5M після машинної арифметики.
  Власність TExactWords, строків та ELF — FPC; runtime stack — Linux.
  Підміна ширини чи невідомий Core1 DEFINE відхиляються ДО emission.

  1) Чому свідок pinned Core1 має бути отриманий до адаптивного ELF?
  2) Чому byte-exact зіставлення з існуючим потоком гарантує механізм?
  3) Чому один host кадр із двох W12 не є SENS D2 .sens документом?
  4) Хто зберігає фізичну ширину D12/D24 результату?
  5) Чому новий модуль не визначає жодної власної функції Core1? }
function BuildPinnedCore1AdaptiveAddELF(const RepoRoot:String):RawByteString;
var Zero,Narrow,Anchor,Authority,Existing,Reference:RawByteString;
    Number:TExplicitNumeric;Words:TExactWords;Geom:TELFGeometry;
begin
  Result:='';
  Demand((RepoRoot<>'') and (Length(RepoRoot)<=4096),
    'відсутній корінь pinned SENS');
  { Це повний admission справжнього фізичного pinned DEFINE, а не
    окремо виписане Pascal тіло Core1. }
  Existing:=BuildPinnedCore1StreamELF(RepoRoot,cpAdd);
  VerifySENSELF64(Existing,Geom);
  Demand((Geom.Kind=3) and (Geom.Entry=120) and
         (Geom.FileBytes=Length(Existing)),
    'оригінальне Core1 не дало перевіреного ELF64');
  Zero:=EncodeNumericDecimal('0',12);
  Number:=ReadNumericPhysical(Zero,12);
  Demand((Number.DomainWidth=12) and
         (Length(Number.ExactBits)=12) and (Length(Zero)=3),
    'змінено фізичне D12 кодування нуля');
  Narrow:=Number.ExactBits;
  SetLength(Words,5);
  Words[0]:='10';Words[1]:='01010';Words[2]:=Narrow;
  Words[3]:=Narrow;Words[4]:='01';
  Anchor:=EncodeT5M(Words);
  Authority:=RawByteString(IncludeTrailingPathDelimiter(
    ExpandFileName(RepoRoot))+'external/sens');
  { Незмінний вузький механізм Core1 та такий самий pinned D5
    механічний якір МУСЯТЬ мати рівно однакові машинні байти. }
  Reference:=BuildVerifiedDynamicD12AddELF(Anchor,Authority);
  Demand(Existing=Reference,
    'порушено byte-exact provenance Core1 / pinned WideIR');
  Result:=BuildAdaptiveD12AddStreamELF(Anchor,Authority);
  VerifySENSELF64(Result,Geom);
  Demand((Geom.Kind=3) and (Geom.Entry=120) and
         (Geom.MachineBytes>0) and (Geom.FileBytes=Length(Result)),
    'не отримано фізичного адаптивного ELF64 PIE');
end;
end.
