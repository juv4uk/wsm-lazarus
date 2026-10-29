{ G6.115 — механічний x86-64 SSE2 MOVDQU (без SENS функцій).
  Матриця байтів 2 напрями × 16 XMM × 16 GPR × 7 displacement.
  Самостійний GNU as є ISA-оракул, не мовний SENS REPL.
  FPC керовані рядки і явне вивільнення TFileStream/TStringList.
  Питання: 1) Чому тестуємо RSP і R12 окремо?
  2) Чому RBP та R13 із 0 потребують нульового disp8?
  3) Чи може test на ELF пройти, якщо MOVDQU не виконався?
  4) Де гарантія no-mutation?
  5) Які обмеження машинного ISA оракула? }
program TestX64SSE2Memory;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64sse2memory,wsm.elfgeometry;
const
  Bases:array[0..15] of String=
    ('rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi',
     'r8','r9','r10','r11','r12','r13','r14','r15');
  Disps:array[0..6] of LongInt=(-129,-128,-1,0,1,127,128);
var C:TX64Code;Op:TX64SSE2MemoryOperation;
    R,B,I,Count,NegativeCount:Integer;
    Dir:String;Assembly:TStringList;Payload:RawByteString;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('SSE2-ПАМ-ТЕСТ: '+Why) end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then
      Need(F.Write(Bytes[1],Length(Bytes))=Length(Bytes),'неповний файл');
  finally F.Free end;
end;
function DispText(V:LongInt):String;
begin
  if V=0 then Result:=''
  else if V>0 then Result:='+'+IntToStr(V)
  else Result:=IntToStr(V);
end;
procedure Golden(O:TX64SSE2MemoryOperation;X,B:Integer;
                 Disp:LongInt;const Want:RawByteString);
begin
  X64Reset(C);X64SSE2Memory(C,O,X,B,Disp);
  Need(X64Image(C)=Want,'розбіжність x86-64 machine golden');
end;
procedure Goldens;
begin
  Golden(smLoad,0,0,0,#$F3#$0F#$6F#$00);
  Golden(smLoad,15,12,0,#$F3#$45#$0F#$6F#$3C#$24);
  Golden(smStore,8,5,0,#$F3#$44#$0F#$7F#$45#$00);
  Golden(smLoad,9,13,-129,#$F3#$45#$0F#$6F#$8D#$7F#$FF#$FF#$FF);
  Golden(smStore,7,4,127,#$F3#$0F#$7F#$7C#$24#$7F);
  Golden(smLoad,0,12,128,#$F3#$41#$0F#$6F#$84#$24#$80#0#0#0);
end;
procedure Reject(O:TX64SSE2MemoryOperation;X,B:Integer;
                 Disp:LongInt;const Initial:RawByteString);
var Old:RawByteString;Failed:Boolean;
begin
  X64Reset(C);C.Bytes:=Initial;Old:=X64Image(C);Failed:=False;
  try X64SSE2Memory(C,O,X,B,Disp)
  except on E:Exception do Failed:=True end;
  Need(Failed and (X64Image(C)=Old),'неатомарна відмова / overrun');
  Inc(NegativeCount);
end;
procedure Negatives;
var InvalidOp:Byte;
begin
  NegativeCount:=0;
  Reject(smLoad,-1,0,0,#$90);
  Reject(smLoad,16,0,0,#$90);
  Reject(smStore,255,0,0,#$90);
  Reject(smStore,0,-1,0,#$90);
  Reject(smLoad,0,16,0,#$90);
  Reject(smLoad,0,255,0,#$90);
  InvalidOp:=2;
  Reject(TX64SSE2MemoryOperation(InvalidOp),0,0,0,#$90);
  InvalidOp:=255;
  Reject(TX64SSE2MemoryOperation(InvalidOp),15,15,128,#$90);
  Reject(smLoad,0,0,0,StringOfChar(#$90,253));   { 4 bytes }
  Reject(smStore,8,0,0,StringOfChar(#$90,252));  { 5 bytes }
  Reject(smLoad,8,12,0,StringOfChar(#$90,251)); { 6 bytes; 257 > 256 }
  Reject(smStore,8,13,-129,StringOfChar(#$90,248)); { 9 bytes }
  Reject(smLoad,0,4,128,StringOfChar(#$90,248)); { 9 bytes }
  Reject(smStore,0,0,0,StringOfChar(#$90,257));
  X64Reset(C);C.Bytes:=StringOfChar(#$90,252);
  X64SSE2Memory(C,smLoad,0,0,0);
  Need(Length(C.Bytes)=256,'помилка точного кордону 4 байтів');
  X64Reset(C);C.Bytes:=StringOfChar(#$90,250);
  X64SSE2Memory(C,smLoad,15,12,0);
  Need(Length(C.Bytes)=256,'помилка точного кордону 6 байтів');
  X64Reset(C);X64SSE2Memory(C,smLoad,15,12,0);
  Need(X64Image(C)=#$F3#$45#$0F#$6F#$3C#$24,'відновлення після відмов');
  Need(NegativeCount=14,'число негативів');
end;
procedure Matrix;
var Line,Address:String;
begin
  Assembly:=TStringList.Create;
  try
    Assembly.Add('.intel_syntax noprefix');
    Assembly.Add('.text');
    Assembly.Add('.global _start');
    Assembly.Add('_start:');
    Count:=0;Payload:='';
    for Op:=Low(TX64SSE2MemoryOperation) to High(TX64SSE2MemoryOperation) do
      for R:=0 to 15 do for B:=0 to 15 do
        for I:=Low(Disps) to High(Disps) do begin
          X64Reset(C);
          X64SSE2Memory(C,Op,R,B,Disps[I]);
          Payload:=Payload+X64Image(C);
          Address:='XMMWORD PTR ['+Bases[B]+DispText(Disps[I])+']';
          if Op=smLoad then
            Line:='  movdqu xmm'+IntToStr(R)+','+Address
          else Line:='  movdqu '+Address+',xmm'+IntToStr(R);
          Assembly.Add(Line);
          Inc(Count);
        end;
    Need(Count=3584,'відсутня частина SSE2 матриці');
    Need(Length(Payload)>15000,'занижений буфер матриці');
    Assembly.SaveToFile(Dir+'/matrix.s');
    Save(Dir+'/matrix.fpc.bin',Payload);
  finally Assembly.Free end;
end;
procedure PutLE(var Bytes:RawByteString;Offset:Integer;Value:QWord;N:Integer);
var K:Integer;
begin
  Need((Offset>=0) and (N>0) and (N<=8) and (Offset+N<=Length(Bytes)),
       'поле ELF поза образом');
  for K:=0 to N-1 do begin
    Bytes[Offset+K+1]:=AnsiChar(Value and $FF);
    Value:=Value shr 8;
  end;
end;
procedure EmitELF(const Name:String;UseR12:Boolean;InputByte:Byte);
var Code,Image:RawByteString;J:Integer;Geometry:TELFGeometry;
begin
  { Вивід системним exit: код повернення походить із фізичного
    MOVDQU [base+1] → XMM → [base+21] → GPR, а не FPC обчислення. }
  Code:=#$48#$83#$EC#$40+ { sub rsp,64 }
        #$B8+AnsiChar(InputByte)+#0#0#0+ { mov eax,<value> }
        #$89#$44#$24#$01; { mov [rsp+1],eax }
  if UseR12 then begin
    Code:=Code+#$49#$89#$E4; { mov r12,rsp }
    X64Reset(C);
    X64SSE2Memory(C,smLoad,15,12,1);
    X64SSE2Memory(C,smStore,15,12,21);
  end else begin
    X64Reset(C);
    X64SSE2Memory(C,smLoad,0,4,1);
    X64SSE2Memory(C,smStore,0,4,21);
  end;
  Code:=Code+X64Image(C)+
        #$8B#$7C#$24#$15+ { mov edi,[rsp+21] }
        #$81#$E7#$FF#0#0#0+ { and edi,255 }
        #$B8#$3C#0#0#0+#$0F#$05; { exit(edi) }
  SetLength(Image,120+Length(Code));FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4);PutLE(Image,4,2,1);
  PutLE(Image,5,1,1);PutLE(Image,6,1,1);
  PutLE(Image,16,3,2);PutLE(Image,18,62,2);
  PutLE(Image,20,1,4);PutLE(Image,24,120,8);
  PutLE(Image,32,64,8);PutLE(Image,52,64,2);
  PutLE(Image,54,56,2);PutLE(Image,56,1,2);
  PutLE(Image,64,1,4);PutLE(Image,68,5,4);
  PutLE(Image,96,Length(Image),8);PutLE(Image,104,Length(Image),8);
  PutLE(Image,112,$1000,8);
  for J:=1 to Length(Code) do Image[120+J]:=Code[J];
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Image)),'не підтверджений ELF64 PIE');
  Save(Dir+'/'+Name+'.elf',Image);
end;
begin
  Need(ParamCount=1,'потрібен каталог для свідків');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'немає каталогу свідків');
  Goldens;Negatives;Matrix;
  EmitELF('rsp',False,90);
  EmitELF('r12',True,107);
  WriteLn('SSE2-MEM-OK matrix=3584 golden=6 negative=14 boundary=2 recovery=1 elf=2');
end.
