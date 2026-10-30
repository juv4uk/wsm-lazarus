{ G6.256 — фізичні D12 T5M входи → r32 sign lowering → Linux ELF64.
  Жодна функція не отримує права виклику SENS. D12 проходить наявний
  ReadNumericPhysical; результат ELF друкує pinned W1, не host текст.
  Негатив хибного zero-extension мусить дати фізичний D1:0.
  Типи: packed bytes та exact bits у FPC managed RawByteString.
  Власність: caller звільняє тимчасові файли; TFileStream локальний.
  Питання: 1) Чому знакове розширення починається з SHL 4?
  2) Чому окремо відхиляємо D24? 3) Чому локальний oracle не SENS REPL?
  4) Чому потрібні фактичні ELF-результати? 5) Хто володіє Code.Bytes? }
program test_x64d12sign;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64d12sign,wsm.x64alu,
  wsm.x64setcc,wsm.x64pie,wsm.elfgeometry,wsm.numericplane,wsm.t5m;
const
  Names32:array[0..7] of String=('eax','ecx','edx','ebx','esp','ebp','esi','edi');
  Names16:array[0..7] of String=('ax','cx','dx','bx','sp','bp','si','di');
  Invalid:array[0..2] of Integer=(-1,8,255);
  CaseText:array[0..8] of RawByteString=
    ('-2048','-2047','-1025','-1','0','1','1024','2047','-1');
  CaseExpected:array[0..8] of LongWord=
    ($FFFFF800,$FFFFF801,$FFFFFBFF,$FFFFFFFF,0,1,1024,2047,$00000FFF);
var
  C:TX64Code; G:TELFGeometry; Dir:String;
  Lines:TStringList;Input,Image,Old,OldFix,Zero,One:RawByteString;
  Num:TExplicitNumeric; I, J, NegativeCount:Integer; Failed:Boolean;
procedure Check(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('D12-SIGN: '+Why) end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
 F:=TFileStream.Create(Dir+Name,fmCreate);
 try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
 finally F.Free end;
end;
function W1(Bit:Integer):RawByteString;
var Words:TExactWords;
begin
 SetLength(Words,1);
 if Bit=0 then Words[0]:='0' else Words[0]:='1';
 Result:=EncodeT5M(Words);
 Check(Length(Result)=1,'W1 canonical T5M');
end;
function Bits12(const Bits:RawByteString):LongWord;
var K:Integer;
begin
 Check(Length(Bits)=12,'потрібно exact 12 біт');
 Result:=0;
 for K:=1 to 12 do begin
  Check(Bits[K] in ['0','1'],'бит не binary');
  Result:=(Result shl 1) or LongWord(Ord(Bits[K])-Ord('0'));
 end;
end;
{$R-}
function Forged(RegNum:Integer):TX64Reg;
begin Result:=TX64Reg(RegNum) end;
{$R+}
procedure Reject(Reg:TX64Reg;PrefixBytes:Integer);
begin
 X64Reset(C);
 C.Bytes:=StringOfChar(#$90,PrefixBytes);
 C.PatchedRIP:=#$03;Old:=C.Bytes;OldFix:=C.PatchedRIP;
 Failed:=False;
 try X64SignExtendD12(C,Reg)
 except on E:EX64CodeError do Failed:=True end;
 Check(Failed and (C.Bytes=Old) and (C.PatchedRIP=OldFix),
   'неатомарна квота / регістр');
 Inc(NegativeCount);
end;
procedure RefusePhysical(const Physical:RawByteString);
var Bad:TExplicitNumeric;
begin
 Failed:=False;
 try Bad:=ReadNumericPhysical(Physical,12)
 except on E:Exception do Failed:=True end;
 Check(Failed,'помилково прийнято фізичний не-D12');
 Inc(NegativeCount);
end;
procedure CompileCase(const K:Integer);
var E:TX64Code;Phys:RawByteString;Value:LongWord;Bit:Integer;
begin
 Phys:=EncodeNumericDecimal(CaseText[K],12);
 Num:=ReadNumericPhysical(Phys,12);
 Value:=Bits12(Num.ExactBits);
 X64Reset(E);
 X64MovImm32(E,xrAX,Value);
 X64SignExtendD12(E,xrAX);
 X64MovImm32(E,xrCX,CaseExpected[K]);
 X64ALU32(E,xaCmp,xrAX,xrCX);
 X64SetCondition8(E,4,xrAX);
 X64MovzxEAXAL(E);
 X64MovImm32(E,xrDX,0);
 X64ALU32(E,xaAdd,xrDX,xrAX);
 X64ImulEDX8(E,Ord(One[1])-Ord(Zero[1]));
 X64AddEDX8(E,Ord(Zero[1]));
 X64SubRsp8(E,8);X64StoreRspQword(E,xrDX,0);
 X64MovImm32(E,xrAX,1);X64MovImm32(E,xrDI,1);
 X64MovRSIRsp(E);X64MovImm32(E,xrDX,1);X64Syscall(E);
 X64MovImm32(E,xrCX,1);
 X64ALU32(E,xaCmp,xrAX,xrCX);
 X64MovImm32(E,xrAX,0);
 X64SetCondition8(E,5,xrAX);
 X64MovzxEAXAL(E);
 X64MovImm32(E,xrDI,0);X64ALU32(E,xaAdd,xrDI,xrAX);
 X64MovImm32(E,xrAX,60);X64Syscall(E);
 Image:=BuildX64PIE(E);
 VerifySENSELF64(Image,G);
 Check((G.Kind=3) and (G.Entry=120) and
   (G.MachineBytes=Length(E.Bytes)),'ELF64 geometry');
 Bit:=1; if K=8 then Bit:=0;
 Save('case'+IntToStr(K)+'.elf',Image);
 Save('case'+IntToStr(K)+'.sens',W1(Bit));
 Save('case'+IntToStr(K)+'.input.sens',Phys);
end;
begin
 Check(ParamCount=1,'потрібен каталог');
 Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
 Check(DirectoryExists(Dir),'каталог не існує');
 Zero:=W1(0);One:=W1(1);
 Check((Ord(Zero[1])=$50) and (Ord(One[1])=$A1),'pinned W1');
 Lines:=TStringList.Create;
 try
  Lines.Add('.intel_syntax noprefix');Lines.Add('.text');
  X64Reset(C);
  for I:=0 to 7 do begin
   X64SignExtendD12(C,TX64Reg(I));
   Lines.Add('shl '+Names32[I]+', 4');
   Lines.Add('movsx '+Names32[I]+', '+Names16[I]);
   Lines.Add('sar '+Names32[I]+', 4');
  end;
  Check(Length(C.Bytes)=72,'матриця 8*9');
  Lines.SaveToFile(Dir+'matrix.s');
  Save('matrix.bin',C.Bytes);
 finally Lines.Free end;
 NegativeCount:=0;
 for I:=0 to 2 do Reject(Forged(Invalid[I]),0);
 Reject(xrAX,248);Reject(xrAX,256);
 RefusePhysical(#$FF);
 RefusePhysical('');
 RefusePhysical(EncodeNumericDecimal('1',24));
 Check(NegativeCount=8,'негативи');
 X64Reset(C);C.Bytes:=StringOfChar(#$90,247);
 X64SignExtendD12(C,xrAX);
 Check(Length(C.Bytes)=256,'легальна квота 247+9');
 X64Reset(C);X64SignExtendD12(C,xrAX);
 Check(C.Bytes=#$C1#$E0#$04#$0F#$BF#$C0#$C1#$F8#$04,
   'відновлення exact host opcode');
 for J:=0 to 8 do CompileCase(J);
 WriteLn('G6-256-D12-SIGN-PASS matrix=8 bytes=72 negative=8 recovery=1 elf=9');
end.
