{ G6.239 — незалежний постконтроль host linear-scan R8..R15 + spill.
  Жодних Dn законів у цьому тесті немає: First/After — приватні
  машинні інтервали. Справжній ELF-тест уже існує в test-x64spill.sh.
  Перевіряємо вкладеність 10/50/100 інтервалів, alias, невірний frame
  та чесну відмову при 25/50/100 ОДНОЧАСНИХ значеннях.
  1) Чому 100 інтервалів не дорівнює 100 живим одночасно?
  2) Де коректно перевикористовується R8 після межі After?
  3) Чому guard не можна вважати SENS REPL oracle?
  4) Хто володіє Plan при винятку та після відновлення? }
program test_spill_depth;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.x64spill,wsm.x64lifetimes,wsm.x64rex;
var Lives:array of TX64LiveInterval;
    Plan:TSpillPlan;
    Frame:TSpillFrame;
    PosCount,NegCount,I,Round,Active,Spilled,Slots:LongInt;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('SPILL-ГЛИБИНА-ПРОВАЛ: '+Why);
end;

procedure Prepare(N,Peak:LongInt;Simultaneous:Boolean);
var K,Start:LongInt;
begin
  SetLength(Lives,N);
  for K:=0 to N-1 do begin
    Lives[K].Slot:=K+1;
    if Simultaneous then Start:=0
    else Start:=(K div Peak)*2;
    Lives[K].First:=Start;
    Lives[K].After:=Start+2;
  end;
end;

procedure CheckDepth(N,Peak,ExpectedFrame:LongInt);
var K,J,LiveNow,LivePeak:LongInt;
begin
  Prepare(N,Peak,False);
  PlanX64Spills(Lives,Plan,Frame);
  VerifyX64SpillPlan(Lives,Plan,Frame);
  Need((Length(Plan)=N) and (Frame.FrameBytes=ExpectedFrame) and
       (Frame.PeakSpills=Peak-8),'помилковий frame/peak на '+IntToStr(N));
  LivePeak:=0;
  for K:=0 to N-1 do begin
    Need((Plan[K].Slot=Lives[K].Slot) and
         (Plan[K].First=Lives[K].First) and
         (Plan[K].After=Lives[K].After),
         'втрачено original interval');
    if (K mod Peak)<8 then
      Need(Plan[K].InRegister and
           (Ord(Plan[K].Reg)=Ord(wrR8)+(K mod Peak)) and
           (Plan[K].StackOffset=-1),'невірний фізичний R8..R15')
    else
      Need((not Plan[K].InRegister) and
           (Plan[K].StackOffset=((K mod Peak)-8)*8),
           'невірний spill slot');
    LiveNow:=0;
    for J:=0 to N-1 do
      if (Plan[J].First<=Plan[K].First) and
         (Plan[K].First<Plan[J].After) then
        Inc(LiveNow);
    if LiveNow>LivePeak then LivePeak:=LiveNow;
    Inc(PosCount);
  end;
  Need(LivePeak=Peak,'неправильна фізична peak-вкладеність');
end;

procedure RejectGuard(const Why:String);
var Failed:Boolean;
begin
  Failed:=False;
  try VerifyX64SpillPlan(Lives,Plan,Frame)
  except on E:EX64SpillError do Failed:=True end;
  Need(Failed,'guard прийняв '+Why);
  Inc(NegCount);
end;

procedure ResetPlan;
begin
  PlanX64Spills(Lives,Plan,Frame);
end;

procedure CorruptionMatrix;
begin
  Prepare(10,10,False);
  ResetPlan;
  Plan[1].Reg:=Plan[0].Reg;
  RejectGuard('два живі значення R8');ResetPlan;

  Plan[9].StackOffset:=Plan[8].StackOffset;
  RejectGuard('два живі spill за [rsp]');ResetPlan;

  Plan[8].StackOffset:=8+1;
  RejectGuard('невирівняний stack offset');ResetPlan;

  Plan[0].Reg:=wrAX;
  RejectGuard('rAX замість R8..R15');ResetPlan;

  Plan[0].StackOffset:=0;
  RejectGuard('регістрове значення одночасно у стеку');ResetPlan;

  Plan[0].Slot:=999;
  RejectGuard('заміна virtual slot');ResetPlan;

  Plan[0].First:=1;
  RejectGuard('заміна першої позиції');ResetPlan;

  Frame.FrameBytes:=0;
  RejectGuard('недостатній stack frame');ResetPlan;

  Frame.PeakSpills:=1;
  RejectGuard('неправдивий peak');ResetPlan;

  SetLength(Plan,9);
  RejectGuard('втрачений десятий interval');ResetPlan;

  VerifyX64SpillPlan(Lives,Plan,Frame);
end;

procedure RejectOvercapacity(Depth:LongInt);
var Failed:Boolean;
begin
  Prepare(Depth,Depth,True);
  SetLength(Plan,1);
  Plan[0].Slot:=777;
  Frame.FrameBytes:=777;Frame.PeakSpills:=777;
  Failed:=False;
  try PlanX64Spills(Lives,Plan,Frame)
  except on E:EX64SpillError do Failed:=True end;
  Need(Failed and (Length(Plan)=0) and (Frame.FrameBytes=0) and
       (Frame.PeakSpills=0),'перевищена одночасна вкладеність '+IntToStr(Depth));
  Inc(NegCount);
end;

begin
  PosCount:=0;NegCount:=0;
  CheckDepth(10,10,16);
  CheckDepth(50,20,96);
  CheckDepth(100,24,128);
  CorruptionMatrix;
  RejectOvercapacity(25);
  RejectOvercapacity(50);
  RejectOvercapacity(100);
  CheckDepth(10,10,16); { recovery після атомарних відмов }
  Need((PosCount=170) and (NegCount=13),'лічильники перевірок');
  WriteLn('G6.239-SPILL-DEPTH-PASS intervals=170 lengths=10,50,100 rejected=13 frame=16,96,128 oracle=NOT-RUN energy=NOT-MEASURED');
end.
