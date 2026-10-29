{ G6.113 — bounded 8 REX regs + 16 frame spill slots, справжній ELF.
  Тестуємо саме механіку machine storage: spilled value зберігається
  8-байтовим QWord у caller-owned stack frame; без ініціалізації
  слот не можна читати. Фізичний D1 результат походить з EncodeT5M,
  а НЕ з hardcoded літерала. Додаткову pinned D5 parity запускає
  незмінний scripts/test-x64lifetimes.sh у загальному CI.
  Питання: 1) Що доводить окремий GNU as?
  2) Чому [0,2) і [2,4) мають однаковий spill offset?
  3) Навіщо справжній машинний LOAD після STORE?
  4) Яку помилку ловить 25 одночасно живих значень?
  5) Чому виконаний ELF stdout все ще не є доказом довільного SENS? }
program test_x64spill;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64spill,wsm.x64lifetimes,wsm.x64rex,
     wsm.x64code,wsm.x64stack,wsm.t5m,wsm.elfgeometry;
var Dir:String; Lives:array of TX64LiveInterval; Plan:TSpillPlan;
    Frame:TSpillFrame; C:TX64Code; G:TELFGeometry;
    PosCount,NegCount,I,J,BitValue,SpilledCount:LongInt;
    Code,ELF,Expected:RawByteString; AsmLines:TStringList;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('SPILL-ПРОВАЛ: '+Why);
end;
procedure Prepare(Index,Slot,First,After:LongInt);
begin
  Lives[Index].Slot:=Slot;Lives[Index].First:=First;
  Lives[Index].After:=After;
end;
procedure Save(const Path:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data))
  finally S.Free end;
end;
procedure Reject(const Why:String);
var Err:Boolean;
begin
  SetLength(Plan,1);
  Plan[0].Slot:=777;
  Frame.FrameBytes:=777;Frame.PeakSpills:=777;
  Err:=False;
  try PlanX64Spills(Lives,Plan,Frame)
  except on E:EX64SpillError do Err:=True end;
  Need(Err and (Length(Plan)=0) and (Frame.FrameBytes=0) and
       (Frame.PeakSpills=0),'неатомарна відмова: '+Why);
  Inc(NegCount);
end;
procedure ValidateNegatives;
begin
  NegCount:=0;
  SetLength(Lives,0);Reject('нуль інтервалів');
  SetLength(Lives,1);
  Prepare(0,0,0,1);Reject('slot нуль');
  Prepare(0,4096,0,1);Reject('slot 4096');
  Prepare(0,1,-1,1);Reject('негативний First');
  Prepare(0,1,1,1);Reject('порожній interval');
  Prepare(0,1,3,2);Reject('зворотний interval');
  Prepare(0,1,0,1025);Reject('поза MaxPosition');
  SetLength(Lives,2);
  Prepare(0,1,2,3);Prepare(1,2,1,4);
  Reject('невпорядкований First');
  Prepare(0,2,0,2);Prepare(1,1,0,2);
  Reject('невпорядкований tie Slot');
  Prepare(0,1,0,2);Prepare(1,1,2,4);
  Reject('duplicate slot');
  SetLength(Lives,129);
  for I:=0 to 128 do Prepare(I,I+1,I,I+1);
  Reject('129 інтервалів');
  SetLength(Lives,25);
  for I:=0 to 24 do Prepare(I,I+1,0,8);
  Reject('17 одночасних spilled');
  SetLength(Lives,2);
  Prepare(0,1,0,1);Prepare(1,1,1,2);
  Reject('duplicate slot при disjoint lifetimes');
  SetLength(Lives,1);
  Prepare(0,1,0,0);Reject('нульовий After');
  Need(NegCount=14,'невірна кількість негативів');
end;
procedure ValidatePositives;
begin
  PosCount:=0;
  SetLength(Lives,128);
  for I:=0 to 127 do
    Prepare(I,I+1,(I div 16)*2,((I div 16)+1)*2);
  PlanX64Spills(Lives,Plan,Frame);
  Need((Length(Plan)=128) and (Frame.FrameBytes=64) and
       (Frame.PeakSpills=8),'128 регістрово-стекових інтервалів');
  for I:=0 to 127 do begin
    if (I mod 16)<8 then
      Need(Plan[I].InRegister and
           (Plan[I].Reg=TX64WideReg(Ord(wrR8)+(I mod 8))) and
           (Plan[I].StackOffset=-1),'неправильний reuse R8..R15')
    else
      Need((not Plan[I].InRegister) and
           (Plan[I].StackOffset=(I mod 8)*8),'неправильний spill reuse');
    Inc(PosCount);
  end;
  SetLength(Lives,24);
  for I:=0 to 23 do Prepare(I,I+1,0,8);
  PlanX64Spills(Lives,Plan,Frame);
  Need((Frame.PeakSpills=16) and (Frame.FrameBytes=128),
       'максимальний frame не 128');
  for I:=0 to 23 do begin
    if I<8 then Need(Plan[I].InRegister,'вісім регістрів')
    else Need((not Plan[I].InRegister) and
              (Plan[I].StackOffset=(I-8)*8),
              '16 spill slots поза [0..120]');
    Inc(PosCount);
  end;
  SetLength(Lives,9);
  for I:=0 to 8 do Prepare(I,I+1,0,2);
  PlanX64Spills(Lives,Plan,Frame);
  Need((Frame.FrameBytes=16) and (Frame.PeakSpills=1) and
       (not Plan[8].InRegister) and (Plan[8].StackOffset=0),
       'один spilled slot і 16-байтовий кадр');
  for I:=0 to 8 do Inc(PosCount);
  SetLength(Lives,18);
  for I:=0 to 8 do Prepare(I,I+1,0,2);
  for I:=9 to 17 do Prepare(I,I+1,2,4);
  PlanX64Spills(Lives,Plan,Frame);
  Need((Frame.FrameBytes=16) and (Frame.PeakSpills=1) and
       (Plan[17].StackOffset=0),'повторний spill на точній межі');
  for I:=0 to 17 do Inc(PosCount);
end;
function PhysicalD1(V:LongInt):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);
  if V=0 then W[0]:='0' else W[0]:='1';
  Result:=EncodeT5M(W);
  Need(Length(Result)=1,'D1 фізичне слово не має 1 байта');
end;
procedure PutLE(var Buffer:RawByteString;Offset:SizeInt;Value:QWord;
                Count:SizeInt);
var K:SizeInt;
begin
  Need((Offset>=0) and (Count>=1) and (Count<=8) and
       (Offset<=Length(Buffer)-Count),'ELF поле поза образом');
  for K:=0 to Count-1 do begin
    Buffer[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
procedure BuildMachine(V:LongInt);
var K:LongInt; Value:QWord; HexValue:String;
begin
  { Відновлюємо рівно один spilled slot у ще зайнятому R8..R15 кадрі. }
  SetLength(Lives,9);
  for K:=0 to 8 do Prepare(K,K+1,0,2);
  PlanX64Spills(Lives,Plan,Frame);
  Need((Frame.FrameBytes=16) and (Plan[8].StackOffset=0),
       'не можна відновити spilled значення');
  Expected:=PhysicalD1(V);
  Value:=QWord(Byte(Expected[1]));
  X64Reset(C);
  AsmLines:=TStringList.Create;
  try
    AsmLines.Add('.intel_syntax noprefix');
    AsmLines.Add('.text');
    AsmLines.Add('.global _start');
    AsmLines.Add('_start:');
    X64StackSubtract(C,Frame.FrameBytes);
    AsmLines.Add('  sub rsp,16');
    X64RexMovAbs(C,wrAX,Value);
    HexValue:=IntToHex(Value,16);
    AsmLines.Add('  movabs rax,0x'+HexValue);
    X64StoreRspQword(C,xrAX,Plan[8].StackOffset);
    AsmLines.Add('  mov QWORD PTR [rsp],rax');
    for K:=0 to 7 do begin
      Need(Plan[K].InRegister,'неправильна machine прив''язка');
      X64RexMovAbs(C,Plan[K].Reg,QWord(K+1));
      AsmLines.Add('  movabs r'+IntToStr(K+8)+',0x'+IntToHex(K+1,16));
    end;
    X64StackLoad(C,xrAX,Plan[8].StackOffset);
    AsmLines.Add('  mov rax,QWORD PTR [rsp]');
    X64StackAdd(C,Frame.FrameBytes);
    AsmLines.Add('  add rsp,16');
    X64SubRsp8(C,8);
    AsmLines.Add('  sub rsp,8');
    X64StoreRspQword(C,xrAX,0);
    AsmLines.Add('  mov QWORD PTR [rsp],rax');
    X64MovImm32(C,xrAX,1);
    AsmLines.Add('  mov eax,1');
    X64MovImm32(C,xrDI,1);
    AsmLines.Add('  mov edi,1');
    X64MovRSIRsp(C);
    AsmLines.Add('  mov rsi,rsp');
    X64MovImm32(C,xrDX,1);
    AsmLines.Add('  mov edx,1');
    X64Syscall(C);
    AsmLines.Add('  syscall');
    X64MovImm32(C,xrAX,60);
    AsmLines.Add('  mov eax,60');
    X64XorEDI(C);
    AsmLines.Add('  xor edi,edi');
    X64Syscall(C);
    AsmLines.Add('  syscall');
    Code:=X64Image(C);
    Need((Length(Code)>0) and (Length(Code)<=256),
         'справжній ELF вийшов з machine quota');
    AsmLines.SaveToFile(Dir+'/spill-'+IntToStr(V)+'.s');
  finally AsmLines.Free end;
  Save(Dir+'/spill-'+IntToStr(V)+'.fpc.bin',Code);
  SetLength(ELF,120+Length(Code));
  FillChar(ELF[1],Length(ELF),0);
  PutLE(ELF,0,$464C457F,4);PutLE(ELF,4,2,1);
  PutLE(ELF,5,1,1);PutLE(ELF,6,1,1);
  PutLE(ELF,16,3,2);PutLE(ELF,18,62,2);PutLE(ELF,20,1,4);
  PutLE(ELF,24,120,8);PutLE(ELF,32,64,8);
  PutLE(ELF,52,64,2);PutLE(ELF,54,56,2);PutLE(ELF,56,1,2);
  PutLE(ELF,64,1,4);PutLE(ELF,68,5,4);
  PutLE(ELF,96,Length(ELF),8);PutLE(ELF,104,Length(ELF),8);
  PutLE(ELF,112,$1000,8);
  for K:=1 to Length(Code) do ELF[120+K]:=Code[K];
  VerifySENSELF64(ELF,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(ELF)),'справжній ET_DYN помилковий');
  Save(Dir+'/spill-'+IntToStr(V)+'.elf',ELF);
  Save(Dir+'/spill-'+IntToStr(V)+'.expected.sens',Expected);
end;
begin
  Need(ParamCount=1,'необхідна приватна тека');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'тека відсутня');
  ValidatePositives;
  ValidateNegatives;
  for BitValue:=0 to 1 do BuildMachine(BitValue);
  WriteLn('X64-SPILL-OK positive=',PosCount,' negative=',NegCount,
          ' full-frame=128 elf=2');
end.
