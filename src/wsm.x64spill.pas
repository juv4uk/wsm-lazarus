{ G6.113. Детермінований spill-планувальник для host x86-64.
  НЕ приймає .sens / Dn / текстові проєкції: caller повинен уже
  перевірити мову pinned SENS. Slot = local machine integer 1..4095.
  [First,After) = напіввідкритий інтервал між позиціями IR/lowering.
  Результат: caller-owned динамічний масив, фізичний host регістр
  R8..R15 АБО окремий 8-байтовий stack slot з offset 0..120.
  Для spilled значення caller ЗОБОВ'ЯЗАНИЙ зберегти його у слот і
  відновити перед використанням; цей planner не емітує machine code.
  FrameBytes 16-byte aligned, при відмові Plan=[], FrameBytes=0.
  Заборонено неявний eviction або автоматичне перенесення зі стеку.
  1) Чому [0,2) і [2,3) можуть ділити той самий offset?
  2) Чому stack offset є host byte, не доменом D12?
  3) Хто зберігає/відновлює spilled значення?
  4) Чому відмова на 25 одночасних значеннях атомарна?
  5) Чому потрібні 16-byte frame alignment і lifetime ordering? }
unit wsm.x64spill;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64lifetimes,wsm.x64rex;
type
  EX64SpillError=class(Exception);
  TX64SpillAssignment=record
    Slot,First,After:LongInt;
    InRegister:Boolean;
    Reg:TX64WideReg;
    StackOffset:LongInt; { -1 = register; 0,8,..120 = spill }
  end;
  TSpillPlan=array of TX64SpillAssignment;
  TSpillFrame=record
    FrameBytes,PeakSpills:LongInt;
  end;
procedure PlanX64Spills(const Lives:array of TX64LiveInterval;
                        out Plan:TSpillPlan;out Frame:TSpillFrame);
procedure VerifyX64SpillPlan(const Lives:array of TX64LiveInterval;
                             const Plan:TSpillPlan;const Frame:TSpillFrame);
implementation
const MaxIntervals=128; MaxPosition=1024;
      MaxVirtualSlot=4095; MaxStackSlots=16; MaxRegisters=8;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EX64SpillError.Create(Why);
end;
{ G6.239 — незалежний механічний postcondition: жодні два
  одночасно живі host slots не можуть отримати однакове фізичне місце.
  Lives та Plan — borrowed arrays; Frame — borrowed scalar record.
  Немає алокацій поза локальними змінними, немає .sens, D7, SENS laws.
  Exception означає, що caller НЕ повинен публікувати ELF/план.
  1) Чому [0,2) і [2,4) можуть ділити R8 або stack offset?
  2) Чому невірний FrameBytes є помилкою навіть за відсутності alias?
  3) Чому virtual Slot — не SENS domain/width/bits?
  4) Де саме PlanX64Spills публікує результат після перевірки?
  5) Чому цей guard не доводить виконання Core1? }
procedure VerifyX64SpillPlan(const Lives:array of TX64LiveInterval;
                             const Plan:TSpillPlan;const Frame:TSpillFrame);
var I,J,LiveSpills,MaxLiveSpills,Required:LongInt;
    Overlap:Boolean;
begin
  Need((Length(Lives)>0) and (Length(Lives)<=128) and
       (Length(Plan)=Length(Lives)),
       'postcondition: невідповідна кількість інтервалів');
  Need((Frame.PeakSpills>=0) and (Frame.PeakSpills<=16) and
       (Frame.FrameBytes>=0) and (Frame.FrameBytes<=128) and
       (Frame.FrameBytes mod 16=0),
       'postcondition: некоректна межа spill frame');
  MaxLiveSpills:=0;
  for I:=0 to High(Plan) do begin
    Need((Lives[I].Slot>=1) and (Lives[I].Slot<=4095) and
         (Lives[I].First>=0) and (Lives[I].First<Lives[I].After) and
         (Lives[I].After<=1024),
         'postcondition: некоректний original live interval');
    Need((Plan[I].Slot=Lives[I].Slot) and
         (Plan[I].First=Lives[I].First) and
         (Plan[I].After=Lives[I].After),
         'postcondition: план змінив original interval');
    if I>0 then
      Need((Lives[I-1].First<Lives[I].First) or
           ((Lives[I-1].First=Lives[I].First) and
            (Lives[I-1].Slot<Lives[I].Slot)),
           'postcondition: неупорядковані live intervals');
    if Plan[I].InRegister then
      Need((Ord(Plan[I].Reg)>=Ord(wrR8)) and
           (Ord(Plan[I].Reg)<=Ord(wrR15)) and
           (Plan[I].StackOffset=-1),
           'postcondition: register assignment недопустимий')
    else
      Need((Plan[I].StackOffset>=0) and
           (Plan[I].StackOffset<=120) and
           (Plan[I].StackOffset mod 8=0) and
           (Plan[I].StackOffset+8<=Frame.FrameBytes),
           'postcondition: spill поза власним кадром');
    LiveSpills:=0;
    for J:=0 to High(Plan) do begin
      if I<>J then Need(Lives[I].Slot<>Lives[J].Slot,
                       'postcondition: duplicate virtual slot');
      Overlap:=(Plan[I].First<Plan[J].After) and
               (Plan[J].First<Plan[I].After);
      if Overlap and (I<J) then begin
        if Plan[I].InRegister and Plan[J].InRegister then
          Need(Plan[I].Reg<>Plan[J].Reg,
               'postcondition: одночасні значення в одному host register')
        else if (not Plan[I].InRegister) and
                (not Plan[J].InRegister) then
          Need(Plan[I].StackOffset<>Plan[J].StackOffset,
               'postcondition: одночасні значення в одному spill slot');
      end;
      if (not Plan[J].InRegister) and
         (Plan[J].First<=Plan[I].First) and
         (Plan[I].First<Plan[J].After) then Inc(LiveSpills);
    end;
    if LiveSpills>MaxLiveSpills then MaxLiveSpills:=LiveSpills;
  end;
  Required:=((MaxLiveSpills*8+15) div 16)*16;
  Need((Frame.PeakSpills=MaxLiveSpills) and
       (Frame.FrameBytes=Required),
       'postcondition: spill peak/frame не відповідає live ranges');
end;

procedure PlanX64Spills(const Lives:array of TX64LiveInterval;
                        out Plan:TSpillPlan;out Frame:TSpillFrame);
var Candidate:TSpillPlan; NextFrame:TSpillFrame;
    EndReg:array[0..MaxRegisters-1] of LongInt;
    EndSpill:array[0..MaxStackSlots-1] of LongInt;
    I,J,FreeReg,FreeSpill,UsedSpills:LongInt;
begin
  SetLength(Plan,0);
  Frame.FrameBytes:=0;
  Frame.PeakSpills:=0;
  Need((Length(Lives)>0) and (Length(Lives)<=MaxIntervals),
       '1..128 host live intervals необхідні');
  { Повний вхід валідується до будь-якого published результату.
    Упорядкування за (First,Slot), а Slot глобально унікальний. }
  for I:=0 to High(Lives) do begin
    Need((Lives[I].Slot>=1) and (Lives[I].Slot<=MaxVirtualSlot),
         'virtual machine slot поза 1..4095');
    Need((Lives[I].First>=0) and (Lives[I].First<Lives[I].After) and
         (Lives[I].After<=MaxPosition),
         'неприпустимий напіввідкритий interval');
    if I>0 then
      Need((Lives[I-1].First<Lives[I].First) or
           ((Lives[I-1].First=Lives[I].First) and
            (Lives[I-1].Slot<Lives[I].Slot)),
           'інтервали не впорядковані за (First,Slot)');
    for J:=0 to I-1 do
      Need(Lives[J].Slot<>Lives[I].Slot,'дубльований machine slot');
  end;
  for J:=0 to MaxRegisters-1 do EndReg[J]:=-1;
  for J:=0 to MaxStackSlots-1 do EndSpill[J]:=-1;
  SetLength(Candidate,Length(Lives));
  NextFrame.FrameBytes:=0; NextFrame.PeakSpills:=0;
  for I:=0 to High(Lives) do begin
    FreeReg:=-1;
    for J:=0 to MaxRegisters-1 do
      if EndReg[J]<=Lives[I].First then begin
        FreeReg:=J;Break
      end;
    Candidate[I].Slot:=Lives[I].Slot;
    Candidate[I].First:=Lives[I].First;
    Candidate[I].After:=Lives[I].After;
    Candidate[I].StackOffset:=-1;
    Candidate[I].Reg:=wrR8; { не використовується, якщо InRegister=false }
    if FreeReg>=0 then begin
      Candidate[I].InRegister:=True;
      Candidate[I].Reg:=TX64WideReg(Ord(wrR8)+FreeReg);
      EndReg[FreeReg]:=Lives[I].After;
    end else begin
      FreeSpill:=-1;
      for J:=0 to MaxStackSlots-1 do
        if EndSpill[J]<=Lives[I].First then begin
          FreeSpill:=J;Break
        end;
      Need(FreeSpill>=0,
        'R8..R15 та 16 spill slots зайняті: fail-closed');
      Candidate[I].InRegister:=False;
      Candidate[I].StackOffset:=FreeSpill*8;
      EndSpill[FreeSpill]:=Lives[I].After;
      { Пікове число активних spill-записів, без залежності від
        історичного найвищого індексу слоту. }
      UsedSpills:=0;
      for J:=0 to MaxStackSlots-1 do
        if EndSpill[J]>Lives[I].First then Inc(UsedSpills);
      if UsedSpills>NextFrame.PeakSpills then
        NextFrame.PeakSpills:=UsedSpills;
    end;
  end;
  if NextFrame.PeakSpills>0 then
    NextFrame.FrameBytes:=((NextFrame.PeakSpills*8+15) div 16)*16;
  Need((NextFrame.FrameBytes>=0) and
       (NextFrame.FrameBytes<=128) and
       ((NextFrame.FrameBytes mod 16)=0),
       'поганий frame size / alignment');
  VerifyX64SpillPlan(Lives,Candidate,NextFrame);
  Plan:=Candidate;
  Frame:=NextFrame;
end;
end.
