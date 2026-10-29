{ G6.108 — обмежений детермінований linear-scan allocator для host x86-64.
  Це лише механізм: Caller до виклику перевірив SENS WideIR/закони.
  Слот: ціле число caller-local 1..4095, НЕ двійкове слово SENS;
  Live [First,After): інтервал між машинними позиціями 0..1024,
  обидві межі caller-owned; After не включається.
  Вихід — TRegLifetimes, managed dynamic array, володіє caller.
  Кожен живий слот має лише один фізичний host wrR8..wrR15;
  жодного spill/перезаписування зайнятого регістра.
  Помилка залишає out-результат порожнім, без опублікованого коду.
  Питання:
  1) Чому [0,2) і [2,4) дозволяють повторно взяти R8?
  2) Чому slot id не дорівнює SENS domain id?
  3) Чому дев'ятий одночасно живий слот відхиляється?
  4) Чому однакова позиція початку потребує стабільного порядку?
  5) Де відбувається встановлення виходу тільки після всіх guard? }
unit wsm.x64lifetimes;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64rex;
type
  EX64LifetimesError=class(Exception);
  TX64LiveInterval=record
    Slot:LongInt;
    First,After:LongInt;
  end;
  TX64LiveAssignment=record
    Slot:LongInt;
    First,After:LongInt;
    Reg:TX64WideReg;
  end;
  TRegLifetimes=array of TX64LiveAssignment;
procedure AssignX64Lifetimes(const Lives:array of TX64LiveInterval;
                             out Assigned:TRegLifetimes);
implementation
const MaxIntervals=128; MaxPosition=1024; MaxSlot=4095;
procedure Demand(OK:Boolean;const Why:String);
begin
  if not OK then raise EX64LifetimesError.Create(Why);
end;
procedure AssignX64Lifetimes(const Lives:array of TX64LiveInterval;
                             out Assigned:TRegLifetimes);
var Candidate:TRegLifetimes;
    UntilPosition:array[0..7] of LongInt;
    I,J,FreeIndex:LongInt;
begin
  SetLength(Assigned,0);
  Demand((Length(Lives)>0) and (Length(Lives)<=MaxIntervals),
    'живих інтервалів має бути від 1 до 128');
  { Повна валідація BEFORE allocation. Одночасні First сортуємо
    за Slot; дублікати заборонені навіть якщо інтервали не перетинаються. }
  for I:=0 to High(Lives) do begin
    Demand((Lives[I].Slot>=1) and (Lives[I].Slot<=MaxSlot),
      'віртуальний slot поза caller host квотою');
    Demand((Lives[I].First>=0) and
           (Lives[I].First<Lives[I].After) and
           (Lives[I].After<=MaxPosition),
      'порожній або недопустимий інтервал життя');
    if I>0 then
      Demand((Lives[I-1].First<Lives[I].First) or
             ((Lives[I-1].First=Lives[I].First) and
              (Lives[I-1].Slot<Lives[I].Slot)),
        'інтервали не впорядковані за (First,Slot)');
    for J:=0 to I-1 do
      Demand(Lives[J].Slot<>Lives[I].Slot,
        'повторний віртуальний slot');
  end;
  for J:=Low(UntilPosition) to High(UntilPosition) do
    UntilPosition[J]:=-1;
  SetLength(Candidate,Length(Lives));
  for I:=0 to High(Lives) do begin
    FreeIndex:=-1;
    for J:=0 to High(UntilPosition) do
      if UntilPosition[J]<=Lives[I].First then begin
        FreeIndex:=J;
        Break;
      end;
    Demand(FreeIndex>=0,
      'вісім R8..R15 зайняті: spill не підтримується');
    UntilPosition[FreeIndex]:=Lives[I].After;
    Candidate[I].Slot:=Lives[I].Slot;
    Candidate[I].First:=Lives[I].First;
    Candidate[I].After:=Lives[I].After;
    Candidate[I].Reg:=TX64WideReg(Ord(wrR8)+FreeIndex);
  end;
  Assigned:=Candidate;
end;
end.
