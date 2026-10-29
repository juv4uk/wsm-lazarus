{ G6.111: 1024 SSE2 byte exact GNU as oracle, 2 виконуваних ELF64.
  Типові x86-64 XMM мають host-індекси, без доменів SENS.
  Масиви/рядки FPC managed; TFileStream/TStringList звільняє caller.
  Питання: 1) Чому порівняння GNU as незалежне?
  2) Чому один ELF перевіряє саме обчислене, а не статичне значення?
  3) Де є fail-closed no mutation?
  4) Чому тут немає жодного виклику D6?
  5) Де перевіряється придатність ELF64? }
program TestX64SSE2;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64sse2,wsm.elfgeometry;
var OutDir:String; C:TX64Code; D,S,Count,NegativeCount:Integer;
    Op:TX64SSE2Operation; Assembly:TStringList; Matrix,Image:RawByteString;
procedure Guard(B:Boolean;const Why:String);
begin if not B then raise Exception.Create('SSE2-ВІДМОВА: '+Why) end;
function Mnemonic(O:TX64SSE2Operation):String;
begin
  case O of
    soXor:Result:='pxor'; soAnd:Result:='pand';
    soOr:Result:='por'; soAddQ:Result:='paddq';
  else raise Exception.Create('невідома операція') end;
end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then
      Guard(F.Write(Bytes[1],Length(Bytes))=Length(Bytes),
        'неповний запис');
  finally F.Free end;
end;
procedure Golden;
begin
  X64Reset(C);X64SSE2RegReg(C,soXor,0,1);
  Guard(X64Image(C)=#$66#$0F#$EF#$C1,'PXOR xmm0,xmm1');
  X64Reset(C);X64SSE2RegReg(C,soXor,8,15);
  Guard(X64Image(C)=#$66#$45#$0F#$EF#$C7,'PXOR xmm8,xmm15');
  X64Reset(C);X64SSE2RegReg(C,soOr,15,8);
  Guard(X64Image(C)=#$66#$45#$0F#$EB#$F8,'POR xmm15,xmm8');
  X64Reset(C);X64SSE2RegReg(C,soAddQ,8,0);
  Guard(X64Image(C)=#$66#$44#$0F#$D4#$C0,'PADDQ xmm8,xmm0');
end;
procedure Reject(O:TX64SSE2Operation;Dest,Src:Integer;
                 const Initial:RawByteString);
var Original:RawByteString; Failed:Boolean;
begin
  X64Reset(C);C.Bytes:=Initial;
  Original:=X64Image(C);Failed:=False;
  try X64SSE2RegReg(C,O,Dest,Src)
  except on E:Exception do Failed:=True end;
  Guard(Failed and (X64Image(C)=Original),
        'неатомарна відмова host ISA');
  Inc(NegativeCount);
end;
procedure Negatives;
var BadOp:Integer;
begin
  NegativeCount:=0;BadOp:=4;
  Reject(soXor,-1,1,#$90);
  Reject(soXor,16,1,#$90);
  Reject(soXor,256,1,#$90);
  Reject(soAnd,1,-1,#$90);
  Reject(soAnd,1,16,#$90);
  Reject(soAnd,1,256,#$90);
  Reject(TX64SSE2Operation(BadOp),1,1,#$90);
  BadOp:=255;Reject(TX64SSE2Operation(BadOp),1,1,#$90);
  Reject(soXor,1,1,StringOfChar(#$90,253));
  Reject(soXor,8,1,StringOfChar(#$90,252));
  Reject(soOr,1,1,StringOfChar(#$90,256));
  Reject(soAddQ,8,9,StringOfChar(#$90,257));
  X64Reset(C);C.Bytes:=StringOfChar(#$90,252);
  X64SSE2RegReg(C,soXor,0,1);
  Guard(Length(C.Bytes)=256,'точна квота чотирьох байтів');
  X64Reset(C);C.Bytes:=StringOfChar(#$90,251);
  X64SSE2RegReg(C,soXor,8,9);
  Guard(Length(C.Bytes)=256,'точна квота п’яти байтів');
  X64Reset(C);X64SSE2RegReg(C,soAddQ,8,15);
  Guard(X64Image(C)=#$66#$45#$0F#$D4#$C7,'відновлення');
  Guard(NegativeCount=12,'неповна негативна матриця');
end;
procedure MatrixGolden;
var LabelLine:String;
begin
  Assembly:=TStringList.Create;
  try
    Assembly.Add('.intel_syntax noprefix');
    Assembly.Add('.text');
    Assembly.Add('.global _start');
    Assembly.Add('_start:');
    Matrix:='';Count:=0;
    for Op:=Low(TX64SSE2Operation) to High(TX64SSE2Operation) do
      for D:=0 to 15 do for S:=0 to 15 do begin
        X64Reset(C);
        X64SSE2RegReg(C,Op,D,S);
        Matrix:=Matrix+X64Image(C);
        LabelLine:='  '+Mnemonic(Op)+' xmm'+IntToStr(D)+
                   ',xmm'+IntToStr(S);
        Assembly.Add(LabelLine);
        Inc(Count);
      end;
    Guard(Count=1024,'немає всіх 1024 ISA комбінацій');
    Guard(Length(Matrix)=4864,'хибна сума байтів SSE2 матриці');
    Assembly.SaveToFile(OutDir+'/matrix.s');
    Save(OutDir+'/matrix.fpc.bin',Matrix);
  finally Assembly.Free end;
end;
procedure PutLE(var Bytes:RawByteString;Offset:Integer;
                Value:QWord;N:Integer);
var I:Integer;
begin
  Guard((Offset>=0) and (N>=1) and (N<=8) and
    (Offset+N<=Length(Bytes)),'поле ELF за межами');
  for I:=0 to N-1 do begin
    Bytes[Offset+I+1]:=AnsiChar(Value and $FF);
    Value:=Value shr 8;
  end;
end;
procedure MachineELF(Operation:TX64SSE2Operation;const Name:String);
var Code:RawByteString;E:RawByteString;Geom:TELFGeometry;
begin
  { mov eax,1; mov ecx,3; movd xmm0,eax; movd xmm1,ecx.
    ЦЕ лише host дані тесту ISA; не SENS D12 чи мовні функції. }
  Code:=#$B8#$01#0#0#0+#$B9#$03#0#0#0+
        #$66#$0F#$6E#$C0+#$66#$0F#$6E#$C9;
  X64Reset(C);X64SSE2RegReg(C,Operation,0,1);
  Code:=Code+X64Image(C);
  { movd eax,xmm0; mov edi,eax; mov eax,60; syscall.
    Exit status залежить від фактично обчисленого SSE2 числа:
    PXOR(1,3)=2; PADDQ(1,3)=4. }
  Code:=Code+#$66#$0F#$7E#$C0+#$89#$C7+
             #$B8#$3C#0#0#0+#$0F#$05;
  SetLength(E,120+Length(Code));FillChar(E[1],Length(E),0);
  PutLE(E,0,$464C457F,4);PutLE(E,4,2,1);PutLE(E,5,1,1);
  PutLE(E,6,1,1);PutLE(E,16,3,2);PutLE(E,18,62,2);
  PutLE(E,20,1,4);PutLE(E,24,120,8);PutLE(E,32,64,8);
  PutLE(E,52,64,2);PutLE(E,54,56,2);PutLE(E,56,1,2);
  PutLE(E,64,1,4);PutLE(E,68,5,4);
  PutLE(E,96,Length(E),8);PutLE(E,104,Length(E),8);
  PutLE(E,112,$1000,8);
  VerifySENSELF64(E,Geom);
  Guard((Geom.Kind=3) and (Geom.Entry=120) and
         (Geom.FileBytes=Length(E)),'непридатний ELF64 PIE');
  Save(OutDir+'/'+Name+'.elf',E);
end;
begin
  Guard(ParamCount=1,'потрібен каталог для побайтових свідків');
  OutDir:=ParamStr(1);
  Guard(DirectoryExists(OutDir),'каталог не існує');
  Golden;Negatives;MatrixGolden;
  MachineELF(soXor,'xor');
  MachineELF(soAddQ,'addq');
  WriteLn('X64-SSE2-OK matrix=1024 golden=4 negative=12 quota=2 recovery=1 elf=2');
end.
