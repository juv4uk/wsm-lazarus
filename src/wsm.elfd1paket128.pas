{ G6.90. Один виконуваний x86-64 ELF64 PIE для ПАКЕТНОГО D3:101
  «тотожне?» над 128 фізичними парами W1. Пакетні 256 байтів
  = 256 ОКРЕМИХ канонічних T5M D1:0/1 атомів, а НЕ одна .sens форма.
  Вихід — 128 окремих T5M W1 байтів в host-пакеті.
  Мовний закон лише з pinned external/sens Contract12 / D3:101;
  цей unit містить ТІЛЬКИ host ABI та машинні x86-64 механізми.
  Вхід перевіряється ВЕСЬ перед ПЕРШИМ stdout syscall. }
unit wsm.elfd1paket128;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EBatchD1ELFError=class(Exception);
function BuildD1Batch128ELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry;
const FixedHeader=120;
type TPatch=record
  Position:SizeInt;
  Size:SizeInt;
end;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EBatchD1ELFError.Create(Why) end;

{ Image: власні managed bytes компілятора; Code: тимчасовий owned
  RawByteString (звільнить FPC); runtime: 512 власних bytes на Linux
  стеку (257 input + 128 output). Немає runtime heap, FPC law dispatch,
  текстового reader або довільної інтерпретації .sens.
  Контроль input — до побудови output, no partial stdout на rejection.
  Питання: (1) чому input 256, а read budget 257?
  (2) чому short read не означає кінець вводу?
  (3) чому перевіряємо ВСІ 256 W1 перед output?
  (4) чому SETE виконує CPU, а не Free Pascal?
  (5) що зберігає доменну ідентичність кожного окремого W1 байта? }
function BuildD1Batch128ELF:RawByteString;
var W:TExactWords;
    NoByte,YesByte,Table,Diagnostic,Code:RawByteString;
    I,Total,InputLoop,InputEnd,ValidateLoop,ValidWord,ComputeLoop,
    OutputStart,OutputWrite,RejectStart,TableLea,ErrorLea:SizeInt;
    JError,JEnd,JOver,JLength,JValidDone,JValidWord,JBadWord,
    JComputeDone,JNextInput,JNextValidate,
    JNextCompute,JShortWrite:TPatch;
    G:TELFGeometry;

  procedure Add(const Data:RawByteString);
  begin
    Need(Length(Code)+Length(Data)<2048,'завеликий машинний код');
    Code:=Code+Data;
  end;
  procedure AddU32(X:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin
      Add(AnsiChar(X and $FF));
      X:=X shr 8;
    end;
  end;
  procedure PatchU32(AtZero:SizeInt; X:LongWord);
  var K:SizeInt;
  begin
    Need((AtZero>=0) and (AtZero<=Length(Code)-4),
      'помилковий відносний машинний покажчик');
    for K:=0 to 3 do begin
      Code[AtZero+K+1]:=AnsiChar(X and $FF);
      X:=X shr 8;
    end;
  end;
  function BranchJcc(Opcode:AnsiChar):TPatch;
  begin
    Result.Position:=Length(Code);
    Result.Size:=6;
    Add(#$0F+Opcode+#0#0#0#0);
  end;
  function BranchJmp:TPatch;
  begin
    Result.Position:=Length(Code);
    Result.Size:=5;
    Add(#$E9#0#0#0#0);
  end;
  procedure Link(const P:TPatch;Target:SizeInt);
  var Delta:LongInt;
  begin
    Need((Target>=0) and (Target<=Length(Code)) and
      (P.Size in [5,6]) and (P.Position>=0) and
      (P.Position+P.Size<=Length(Code)),
      'помилковий перехід x86-64');
    Delta:=LongInt(Target-(P.Position+P.Size));
    PatchU32(P.Position+P.Size-4,LongWord(Delta));
  end;
  procedure Put(Offset:SizeInt;X:QWord;Width:SizeInt);
  var K:SizeInt;
  begin
    Need((Offset>=0) and (Width>=1) and (Width<=8) and
      (Offset<=Length(Result)-Width),'ELF header overflow');
    for K:=0 to Width-1 do begin
      Result[Offset+K+1]:=AnsiChar(X and $FF);
      X:=X shr 8;
    end;
  end;
begin
  Result:='';
  SetLength(W,1);
  W[0]:='0';NoByte:=EncodeT5M(W);
  W[0]:='1';YesByte:=EncodeT5M(W);
  Need((Length(NoByte)=1) and (Length(YesByte)=1) and
    (NoByte<>YesByte),'невідомі два канонічні фізичні W1 коди');
  Table:=NoByte+YesByte;
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString(
    'Д1-ПАКЕТ-ВІДМОВА: потрібно рівно 128 пар canonical W1 T5M')))+#10;
  Code:='';

  { sub rsp,512; xor r12d,r12d — скільки байтів отримано.
    Читаємо допоки read не поверне EOF; Linux дозволяє short reads.
    Budget 257 = 256 expected + 1 extra sentinel, reject overflow. }
  Add(#$48#$81#$EC#0#$02#0#0);
  Add(#$45#$31#$E4);
  InputLoop:=Length(Code);
  Add(#$31#$C0);             { read syscall #0 }
  Add(#$31#$FF);             { fd 0 }
  Add(#$48#$89#$E6);         { rsi=rsp }
  Add(#$4C#$01#$E6);         { rsi += r12 }
  Add(#$BA#$01#$01#0#0);     { edx=257 }
  Add(#$4C#$29#$E2);         { edx -= r12 (64-bit) }
  Add(#$0F#$05);             { syscall }
  Add(#$48#$85#$C0);         { test rax,rax }
  JError:=BranchJcc(#$88);   { js reject (read error) }
  JEnd:=BranchJcc(#$84);     { je EOF }
  Add(#$49#$01#$C4);         { add r12,rax }
  Add(#$49#$81#$FC#0#$01#0#0); { cmp r12,256 }
  JOver:=BranchJcc(#$87);    { ja reject }
  JNextInput:=BranchJmp;
  InputEnd:=Length(Code);
  Add(#$49#$81#$FC#0#$01#0#0);
  JLength:=BranchJcc(#$85);  { jne reject }

  { admission: один із двох byte-exact W1 codec байтів у КОЖНОМУ
    slot, ніяка D7 цифра, байт ASCII чи часткова відповідь. }
  Add(#$31#$DB);             { xor ebx,ebx }
  ValidateLoop:=Length(Code);
  Add(#$81#$FB#0#$01#0#0);  { cmp ebx,256 }
  JValidDone:=BranchJcc(#$84);
  Add(#$8A#$04#$1C);        { mov al,[rsp+rbx] }
  Add(#$3C+NoByte);          { cmp al,D1:0 packed byte }
  JValidWord:=BranchJcc(#$84);
  Add(#$3C+YesByte);         { cmp al,D1:1 packed byte }
  JBadWord:=BranchJcc(#$85);
  ValidWord:=Length(Code);
  Add(#$83#$C3#$01);        { add ebx,1 }
  JNextValidate:=BranchJmp;

  { Всі 256 входів допущені; тепер реальний цикл 128 CMP/SETE. }
  OutputStart:=Length(Code);
  Add(#$31#$DB);            { xor ebx,ebx }
  Add(#$4C#$8D#$AC#$24#$10#$01#0#0); { lea r13,[rsp+272] }
  ComputeLoop:=Length(Code);
  Add(#$81#$FB#0#$01#0#0);  { cmp ebx,256 }
  JComputeDone:=BranchJcc(#$84);
  Add(#$8A#$04#$1C);        { mov al,[rsp+rbx] }
  Add(#$3A#$44#$1C#$01);   { cmp al,[rsp+rbx+1] }
  Add(#$0F#$94#$C0);       { sete al }
  Add(#$0F#$B6#$C0);       { movzx eax,al }
  TableLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0); { lea rsi,[rip+Table] }
  Add(#$8A#$04#$06);        { mov al,[rsi+rax] }
  Add(#$41#$88#$45#$00);   { mov [r13],al }
  Add(#$49#$FF#$C5);       { inc r13 }
  Add(#$83#$C3#$02);       { add ebx,2 }
  JNextCompute:=BranchJmp;

  { ОДИН syscall output 128 W1 host bytes після повного admission. }
  OutputWrite:=Length(Code);
  Add(#$B8#$01#0#0#0);     { write }
  Add(#$BF#$01#0#0#0);     { stdout }
  Add(#$48#$8D#$B4#$24#$10#$01#0#0); { rsi=rsp+272 }
  Add(#$BA#$80#0#0#0);     { 128 bytes }
  Add(#$0F#$05);
  Add(#$48#$3D#$80#0#0#0); { cmp rax,128 }
  JShortWrite:=BranchJcc(#$85);
  Add(#$B8#$3C#0#0#0);     { exit(0) }
  Add(#$31#$FF);
  Add(#$0F#$05);

  RejectStart:=Length(Code);
  Add(#$B8#$01#0#0#0);      { write diagnostic to fd=2 }
  Add(#$BF#$02#0#0#0);
  ErrorLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0);
  Add(#$BA);AddU32(LongWord(Length(Diagnostic)));
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);     { exit(2) }
  Add(#$BF#$02#0#0#0);
  Add(#$0F#$05);

  { Усі RIP-relative й control-transfer displacement — host ELF
    абсолютного номера domain не кодують і з PIE ASLR сумісні. }
  Link(JError,RejectStart);Link(JEnd,InputEnd);
  Link(JOver,RejectStart);Link(JLength,RejectStart);
  Link(JNextInput,InputLoop);
  Link(JValidDone,OutputStart);Link(JValidWord,ValidWord);
  Link(JBadWord,RejectStart);Link(JNextValidate,ValidateLoop);
  Link(JComputeDone,OutputWrite);
  Link(JNextCompute,ComputeLoop);Link(JShortWrite,RejectStart);
  PatchU32(TableLea+3,LongWord(LongInt(
    Length(Code)-(TableLea+7))));
  PatchU32(ErrorLea+3,LongWord(LongInt(
    Length(Code)+Length(Table)-(ErrorLea+7))));

  Total:=FixedHeader+Length(Code)+Length(Table)+Length(Diagnostic);
  Need((Total>FixedHeader) and (Total<4096),'ELF > 4096');
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,FixedHeader,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[FixedHeader+I]:=Code[I];
  for I:=1 to Length(Table) do
    Result[FixedHeader+Length(Code)+I]:=Table[I];
  for I:=1 to Length(Diagnostic) do
    Result[FixedHeader+Length(Code)+Length(Table)+I]:=Diagnostic[I];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.FileBytes=Total) and
    (G.MachineBytes=Total-FixedHeader),
    'невдала незалежна перевірка native ELF64 PIE');
end;
end.
