{ G6.261 — точні host-межі регістрів для чотирьох чинних x86-64 кодерів.
  Ніяких законів SENS, new opcode чи прихованого dispatch; негативи
  створюють навмисно зіпсований Pascal enum ЛИШЕ в тестовому помічнику.
  Production код збирається з -Cr -Co -Ci; приймаємо лише EX64CodeError.
  Код і метадані після невдалого Emit — власність викликача, незмінні. }
program test_verified_x64_regbounds;
{$mode objfpc}{$H+}
uses SysUtils,wsm.x64code,wsm.x64alu,wsm.x64cmov,
     wsm.x64bitscan,wsm.x64shift;
const InvalidRegisters:array[0..2] of LongInt=(-1,8,255);
var Code:TX64Code;
    I,Negatives,Recoveries:LongInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('G6.261-ФІЗИЧНИЙ-РЕГІСТР: '+Why);
end;

function RegFromHost(Value:LongInt):TX64Reg;
begin
  { Тільки тут: генеруємо недозволену enum-координату для негативів. }
  {$R-}
  Result:=TX64Reg(Value);
  {$R+}
end;
function ALUFromHost(Value:LongInt):TX64ALU;
begin
  {$R-}
  Result:=TX64ALU(Value);
  {$R+}
end;
function ScanFromHost(Value:LongInt):TX64BitScan;
begin
  {$R-}
  Result:=TX64BitScan(Value);
  {$R+}
end;
function ShiftFromHost(Value:LongInt):TX64Shift;
begin
  {$R-}
  Result:=TX64Shift(Value);
  {$R+}
end;

{ Kind 0=ALU,1=CMOV,2=BSF/BSR,3=SHIFT imm,4=SHIFT CL.
  Числа тут — тільки host test coordinates, НЕ SENS Dn. }
procedure MustReject(Kind,Op,Dst,Src,Arg:LongInt;const Why:String);
var OldBytes,OldRIP:RawByteString; Rejected:Boolean;
begin
  OldBytes:=Code.Bytes;
  OldRIP:=Code.PatchedRIP;
  Rejected:=False;
  try
    case Kind of
      0:X64ALU32(Code,ALUFromHost(Op),RegFromHost(Dst),RegFromHost(Src));
      1:X64CMov32(Code,Arg,RegFromHost(Dst),RegFromHost(Src));
      2:X64BitScan32(Code,ScanFromHost(Op),RegFromHost(Dst),RegFromHost(Src));
      3:X64ShiftImm32(Code,ShiftFromHost(Op),RegFromHost(Dst),Byte(Arg));
      4:X64ShiftCL32(Code,ShiftFromHost(Op),RegFromHost(Dst));
    else
      Check(False,'неіснуюча категорія тесту');
    end;
  except
    on E:EX64CodeError do Rejected:=True;
  end;
  Check(Rejected,Why+': не відхилено через host EX64CodeError');
  Check((Code.Bytes=OldBytes) and (Code.PatchedRIP=OldRIP),
        Why+': частково змінено machine bytes або RIP');
  Inc(Negatives);
end;

procedure TestRegBounds;
begin
  X64Reset(Code);
  Code.Bytes:=#$90;Code.PatchedRIP:=#$07;
  for I:=Low(InvalidRegisters) to High(InvalidRegisters) do begin
    MustReject(0,Ord(xaAdd),InvalidRegisters[I],Ord(xrCX),0,'ALU dest');
    MustReject(0,Ord(xaAdd),Ord(xrAX),InvalidRegisters[I],0,'ALU source');
    MustReject(1,0,InvalidRegisters[I],Ord(xrCX),4,'CMOV dest');
    MustReject(1,0,Ord(xrAX),InvalidRegisters[I],4,'CMOV source');
    MustReject(2,Ord(xbFirstSet),InvalidRegisters[I],Ord(xrCX),0,'BSF dest');
    MustReject(2,Ord(xbFirstSet),Ord(xrAX),InvalidRegisters[I],0,'BSF source');
    MustReject(3,Ord(xsShl),InvalidRegisters[I],0,1,'SHIFT imm dest');
    MustReject(4,Ord(xsSar),InvalidRegisters[I],0,0,'SHIFT CL dest');
  end;
  MustReject(0,-1,Ord(xrAX),Ord(xrCX),0,'ALU opcode -1');
  MustReject(0,255,Ord(xrAX),Ord(xrCX),0,'ALU opcode 255');
  MustReject(1,0,Ord(xrAX),Ord(xrCX),-1,'CMOV condition -1');
  MustReject(1,0,Ord(xrAX),Ord(xrCX),16,'CMOV condition 16');
  MustReject(2,-1,Ord(xrAX),Ord(xrCX),0,'BSF opcode -1');
  MustReject(2,255,Ord(xrAX),Ord(xrCX),0,'BSF opcode 255');
  MustReject(3,-1,Ord(xrAX),0,1,'SHIFT imm opcode -1');
  MustReject(3,Ord(xsShl),Ord(xrAX),0,32,'SHIFT imm count 32');
  MustReject(4,255,Ord(xrAX),0,0,'SHIFT CL opcode 255');
  { 24 регістрові + 9 інших = 33 негативи на валідному буфері. }
  Check(Negatives=33,'невірна кількість host негативів');
end;

procedure TestQuotaAndRecovery;
begin
  Code.Bytes:=StringOfChar(#$90,255);
  Code.PatchedRIP:=#$07;
  MustReject(0,Ord(xaAdd),Ord(xrAX),Ord(xrCX),0,'ALU quota');
  MustReject(1,0,Ord(xrAX),Ord(xrCX),4,'CMOV quota');
  MustReject(2,Ord(xbFirstSet),Ord(xrAX),Ord(xrCX),0,'BSF quota');
  MustReject(3,Ord(xsShl),Ord(xrAX),0,1,'SHIFT imm quota');
  MustReject(4,Ord(xsSar),Ord(xrAX),0,0,'SHIFT CL quota');
  Check(Negatives=38,'невірна кількість host квот');

  X64Reset(Code);
  X64ALU32(Code,xaAdd,xrAX,xrCX);
  Check((Code.Bytes=#$01#$C8) and (Code.PatchedRIP=''),
        'ALU не відновився'); Inc(Recoveries);
  X64Reset(Code);
  X64CMov32(Code,4,xrAX,xrCX);
  Check((Code.Bytes=#$0F#$44#$C1) and (Code.PatchedRIP=''),
        'CMOV не відновився'); Inc(Recoveries);
  X64Reset(Code);
  X64BitScan32(Code,xbFirstSet,xrDX,xrAX);
  Check((Code.Bytes=#$0F#$BC#$D0) and (Code.PatchedRIP=''),
        'BSF не відновився'); Inc(Recoveries);
  X64Reset(Code);
  X64ShiftImm32(Code,xsShl,xrAX,1);
  Check((Code.Bytes=#$C1#$E0#$01) and (Code.PatchedRIP=''),
        'SHIFT imm не відновився'); Inc(Recoveries);
  X64Reset(Code);
  X64ShiftCL32(Code,xsSar,xrDX);
  Check((Code.Bytes=#$D3#$FA) and (Code.PatchedRIP=''),
        'SHIFT CL не відновився'); Inc(Recoveries);
end;

begin
  Negatives:=0;Recoveries:=0;
  TestRegBounds;
  TestQuotaAndRecovery;
  Check((Negatives=38) and (Recoveries=5),'остаточні лічильники');
  WriteLn('G6.261-X64-REGBOUNDS-PASS negatives=38 recovery=5 coders=4');
end.
