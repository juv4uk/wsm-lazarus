{ G6.258: фізична матриця MOVZX r32,r16 та чотири реальні PIE.
  Вхід: host регістри й тестові 16-бітові значення; вихід: ELF64
  і exact T5M W1 через pinned кодек. Буфери owned, без SENS dispatch.
  Питання: чому 0F B7? Чому ModRM.reg=ціль? Чому W1 не D12?
  Як відмови зберігають RIP fixups? Чому негативний свідок відрізняє MOVZX від MOVSX? }
program test_x64movzx;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64movzx,wsm.x64alu,
  wsm.x64setcc,wsm.x64pie,wsm.t5m,wsm.elfgeometry;
const
  N32:array[0..7] of String=('eax','ecx','edx','ebx','esp','ebp','esi','edi');
  N16:array[0..7] of String=('ax','cx','dx','bx','sp','bp','si','di');
  Invalid:array[0..2] of Integer=(-1,8,255);
var C:TX64Code;Root:String;D,S,I,Side,Neg:Integer;
    Source:TX64Reg;Lines:TStringList;
    Old,Fix,Image,Zero,One:RawByteString;
    Raised:Boolean;G:TELFGeometry;
procedure Check(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('MOVZX: '+Why) end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
 F:=TFileStream.Create(Name,fmCreate);
 try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
 finally F.Free end;
end;
function W1(Bit:Integer):RawByteString;
var W:TExactWords;
begin
 SetLength(W,1);
 if Bit=0 then W[0]:='0' else W[0]:='1';
 Result:=EncodeT5M(W);
 Check(Length(Result)=1,'точний фізичний W1');
end;
{$R-}
function Forged(N:Integer):TX64Reg;
begin Result:=TX64Reg(N) end;
{$R+}
procedure Reject(Dest,Src:TX64Reg;Count:Integer);
begin
 X64Reset(C);C.Bytes:=StringOfChar(#$90,Count);
 C.PatchedRIP:=#$04;Old:=C.Bytes;Fix:=C.PatchedRIP;
 Raised:=False;
 try X64MovZX16to32(C,Dest,Src)
 except on E:EX64CodeError do Raised:=True end;
 Check(Raised and (C.Bytes=Old) and (C.PatchedRIP=Fix),
   'неатомарна відмова');
 Inc(Neg);
end;
procedure Machine(K:Integer;Src:TX64Reg;Input,Expected:LongWord;Bit:Integer);
var X:TX64Code;
begin
 X64Reset(X);
 X64MovImm32(X,Src,Input);
 X64MovZX16to32(X,xrAX,Src);
 X64MovImm32(X,xrCX,Expected);
 X64ALU32(X,xaCmp,xrAX,xrCX);
 X64SetCondition8(X,4,xrAX);
 X64MovzxEAXAL(X);
 X64MovImm32(X,xrDX,0);
 X64ALU32(X,xaAdd,xrDX,xrAX);
 X64ImulEDX8(X,Ord(One[1])-Ord(Zero[1]));
 X64AddEDX8(X,Ord(Zero[1]));
 X64SubRsp8(X,8);
 X64StoreRspQword(X,xrDX,0);
 X64MovImm32(X,xrAX,1);
 X64MovImm32(X,xrDI,1);
 X64MovRSIRsp(X);
 X64MovImm32(X,xrDX,1);
 X64Syscall(X);
 X64MovImm32(X,xrCX,1);
 X64ALU32(X,xaCmp,xrAX,xrCX);
 X64MovImm32(X,xrAX,0);
 X64SetCondition8(X,5,xrAX);
 X64MovzxEAXAL(X);
 X64MovImm32(X,xrDI,0);
 X64ALU32(X,xaAdd,xrDI,xrAX);
 X64MovImm32(X,xrAX,60);
 X64Syscall(X);
 Image:=BuildX64PIE(X);
 VerifySENSELF64(Image,G);
 Check((G.Kind=3) and (G.Entry=120) and
       (G.MachineBytes=Length(X.Bytes)),'ELF геометрія');
 Save(Root+'case'+IntToStr(K)+'.elf',Image);
 Save(Root+'case'+IntToStr(K)+'.sens',W1(Bit));
end;
begin
 Check(ParamCount=1,'потрібна тека');
 Root:=IncludeTrailingPathDelimiter(ParamStr(1));
 Check(DirectoryExists(Root),'тека відсутня');
 Zero:=W1(0);One:=W1(1);
 Check((Byte(Zero[1])=$50) and (Byte(One[1])=$A1),'pinned T5M');
 Lines:=TStringList.Create;
 try
  Lines.Add('.intel_syntax noprefix');Lines.Add('.text');
  X64Reset(C);
  for D:=0 to 7 do for S:=0 to 7 do begin
    X64MovZX16to32(C,TX64Reg(D),TX64Reg(S));
    Lines.Add('movzx '+N32[D]+', '+N16[S]);
  end;
  Check(Length(C.Bytes)=192,'матриця 64 * 3');
  Lines.SaveToFile(Root+'reference.s');
  Save(Root+'actual.bin',X64Image(C));
 finally Lines.Free end;
 Neg:=0;
 for I:=0 to 2 do for Side:=0 to 1 do begin
  Source:=Forged(Invalid[I]);
  if Side=0 then Reject(Source,xrAX,1)
  else Reject(xrAX,Source,1);
 end;
 Reject(xrAX,xrCX,254);Reject(xrAX,xrCX,256);
 Check(Neg=8,'вісім негативів');
 X64Reset(C);C.Bytes:=StringOfChar(#$90,253);
 X64MovZX16to32(C,xrAX,xrCX);
 Check(Length(C.Bytes)=256,'межова квота');
 X64Reset(C);X64MovZX16to32(C,xrAX,xrCX);
 Check(X64Image(C)=#$0F#$B7#$C1,'відновлення');
 Machine(0,xrCX,$00008001,$00008001,1);
 Machine(1,xrDX,$ABCD7FFF,$00007FFF,1);
 Machine(2,xrBX,$0000FFFF,$FFFFFFFF,0);
 Machine(3,xrSI,$12348000,$00008000,1);
 WriteLn('G6-258-MOVZX-PASS matrix=64 negative=8 recovery=1 elf=4');
end.
