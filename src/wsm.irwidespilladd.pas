{ G6.120 — один справжній фізичний D5 compiler path з машинним spill.
  МОВНИЙ допуск належить тільки pinned BuildIRWideRexAddELF:
  повний binary T5M D2/WideIR, точний D5 01010, дві D12 ширини та
  numeric overflow gate. Тут немає власного SENS evaluator/registry.
  Host lowering замінює ЛИШЕ доведені 26 байтів машинного прологу.
  План із 9 host-live slots: R8–R15 + [RSP+0], 16-byte stack frame.
  Другий operand з оригінального verified MOVABS фізично спочатку
  записується на стек, потім з нього читається ПІД ЧАС виконання.
  Нейтральні подвійні XOR на R9–R15 демонструють споживання всіх
  регістрів після store та до reload. Решта T5M writer незмінна.
  Вхід: borrowed RawByteString .sens, шлях pinned authority.
  Вихід: owned ELF64; помилка не публікує жодного образу.
  1) Чому host слот не може визначати закон D5?
  2) Хто вирішує D12→D24 overflow?
  3) Чому XOR двічі залишає A незмінним?
  4) Чому rel32 хвоста не потребує patch при однаковому зсуві?
  5) Хто відновлює RSP перед чинним T5M writer? }
unit wsm.irwidespilladd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideSpillAddError=class(Exception);
function BuildIRWideSpillAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwiderexadd,wsm.x64spill,wsm.x64lifetimes,
     wsm.x64rex,wsm.x64stack,wsm.x64code,wsm.elfgeometry;
const HeaderBytes=120; OldPrologueBytes=26; NewPrologueBytes=154;
procedure Demand(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideSpillAddError.Create(Why) end;
function ReadLE64(const S:RawByteString;Offset:SizeInt):QWord;
var I:LongInt;
begin
  Demand((Offset>=0) and (Offset<=Length(S)-8),
    'машинний immediate поза фізичними байтами');
  Result:=0;
  for I:=7 downto 0 do
    Result:=(Result shl 8) or QWord(Byte(S[Offset+I+1]));
end;
procedure PutLE64(var S:RawByteString;Offset:SizeInt;Value:QWord);
var I:LongInt;
begin
  Demand((Offset>=0) and (Offset<=Length(S)-8),
    'ELF64 поле поза образом');
  for I:=0 to 7 do begin
    S[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function BuildIRWideSpillAddELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var OldELF,Prologue,Candidate:RawByteString;
    Geometry:TELFGeometry;Code:TX64Code;
    Lives:array[0..8] of TX64LiveInterval;
    Plan:TSpillPlan;Frame:TSpillFrame;
    LeftImm,RightImm:QWord;I:LongInt;
begin
  Result:='';
  { Тут без повторного парсингу української людської проєкції:
    вузький, вже ratified binary compiler admission викликається
    ПЕРЕД будь-яким емісією або читанням machine immediates. }
  OldELF:=BuildIRWideRexAddELF(Physical,AuthorityRoot);
  VerifySENSELF64(OldELF,Geometry);
  Demand((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
         (Geometry.FileBytes=Length(OldELF)) and
         (Length(OldELF)>HeaderBytes+OldPrologueBytes+36),
         'не підтримано verified ELF64 профіль');
  Demand((Copy(OldELF,HeaderBytes+1,2)=#$49#$B8) and
         (Copy(OldELF,HeaderBytes+11,2)=#$49#$B9) and
         (Copy(OldELF,HeaderBytes+21,6)=#$4D#$01#$C8#$4C#$89#$C0) and
         (OldELF[HeaderBytes+27]=#$25),
         'оригінальний compiler змінив машинний пролог');
  LeftImm:=ReadLE64(OldELF,HeaderBytes+2);
  RightImm:=ReadLE64(OldELF,HeaderBytes+12);
  for I:=0 to 8 do begin
    Lives[I].Slot:=I+1;Lives[I].First:=0;Lives[I].After:=2;
  end;
  PlanX64Spills(Lives,Plan,Frame);
  Demand((Length(Plan)=9) and (Frame.FrameBytes=16) and
         (Frame.PeakSpills=1) and (not Plan[8].InRegister) and
         (Plan[8].StackOffset=0),'host allocator не допустив 9 значень');
  for I:=0 to 7 do
    Demand(Plan[I].InRegister and
           (Plan[I].Reg=TX64WideReg(Ord(wrR8)+I)) and
           (Plan[I].StackOffset=-1),
           'host allocator змінив регістровий профіль');
  X64Reset(Code);
  X64StackSubtract(Code,Frame.FrameBytes);
  X64RexMovAbs(Code,wrAX,RightImm);
  { Власність: Code — caller-owned machine bytes; Plan — локальний
    checked spill-план із PlanX64Spills; Frame — власний 16-byte RSP
    кадр. Дві D12 фізичні величини вже допущено upstream pinned
    BuildIRWideRexAddELF, жоден host STORE не реалізує закон D5.
    Використовуємо єдиний checked facade X64StackStore (вже протестований
    66 GNU-as інструкціями): aligned offset [0..120], Reg<>RSP,
    strong exception-safety; байти MOV лишаються НЕЗМІННИМИ.
    1) Чому [rsp+offset] не є координатою SENS?
    2) Де планувальник гарантує відсутність двох live spill у слоті?
    3) Хто виділяє та звільняє стековий frame?
    4) Чому саме xrAX, а не регістр R8?
    5) Чому нижчий unchecked X64StoreRspQword більше не потрібен? }
  X64StackStore(Code,xrAX,Plan[8].StackOffset);
  for I:=0 to 7 do
    if I=0 then X64RexMovAbs(Code,Plan[I].Reg,LeftImm)
    else X64RexMovAbs(Code,Plan[I].Reg,QWord(I*17+1));
  for I:=1 to 7 do begin
    X64RexReg64(Code,roXor,Plan[0].Reg,Plan[I].Reg);
    X64RexReg64(Code,roXor,Plan[0].Reg,Plan[I].Reg);
  end;
  X64StackLoad(Code,xrAX,Plan[8].StackOffset);
  X64RexReg64(Code,roAdd,Plan[0].Reg,wrAX);
  X64RexReg64(Code,roMove,wrAX,Plan[0].Reg);
  X64StackAdd(Code,Frame.FrameBytes);
  Prologue:=X64Image(Code);
  Demand((Length(Prologue)=NewPrologueBytes) and
         (Copy(Prologue,1,4)=#$48#$83#$EC#$10) and
         (Copy(Prologue,NewPrologueBytes-3,4)=#$48#$83#$C4#$10),
         'справжній spill-пролог не має очікуваних machine байтів');
  Candidate:=Copy(OldELF,1,HeaderBytes)+Prologue+
             Copy(OldELF,HeaderBytes+OldPrologueBytes+1,
                  Length(OldELF)-HeaderBytes-OldPrologueBytes);
  Demand(Length(Candidate)=Length(OldELF)+
                            NewPrologueBytes-OldPrologueBytes,
         'невірне перенесення verified ELF64 writer');
  PutLE64(Candidate,96,QWord(Length(Candidate)));
  PutLE64(Candidate,104,QWord(Length(Candidate)));
  VerifySENSELF64(Candidate,Geometry);
  Demand((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
         (Geometry.FileBytes=Length(Candidate)),
         'кінцевий spill ELF64 не пройшов геометрію');
  Result:=Candidate;
end;
end.
