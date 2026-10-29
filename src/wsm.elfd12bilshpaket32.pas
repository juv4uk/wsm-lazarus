{ G6.94. Один Linux x86-64 PIE: 32 runtime-порівняння
  ратифікованого D5:11011 «більше?» над двома точними signed D12.
  Вхід: 192 host bytes = 64 ОКРЕМІ канонічні packed W12 атоми,
  не один документ .sens. Вихід: 32 окремі packed W1 D1 атоми.
  Мовний закон — pinned juv4uk/sens Contract12 / d5.lisp;
  тут ТІЛЬКИ ISA механізми та таблиці чинного wsm.t5m.
  Немає Pascal A>B, англійського dispatch або власного registry. }
unit wsm.elfd12bilshpaket32;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12GreaterBatchError=class(Exception);
function BuildD12GreaterBatch32ELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120;
      InvalidByte=255;
type TJump=record Pos,Bytes:SizeInt end;
     TLea=record Pos:SizeInt; Kind:Byte end;
     TJumpList=array of TJump;
     TLeaList=array of TLea;

procedure Need(Ok:Boolean;const Message:String);
begin if not Ok then raise ED12GreaterBatchError.Create(Message) end;

{ Image, Code та LUT — FPC-owned managed RawByteString, lifespan
  одного виклику емітера; результат — перевірені фізичні ELF bytes.
  Машинний runtime — 512 власних stack bytes: 193 input + 32 output,
  без heap чи FPC evaluator. R12 = число прочитаних host bytes;
  R13/R14 = pointer на input/output, RBX — host лічильник пар.
  Кожний W12 допущено канонічною таблицею, породженою EncodeT5M.
  Питання: 1) Чому W12 розбивається на W5/W5/W2?
  2) Чому read(193) дозволяє знайти surplus після 192?
  3) Чому signed SAR на 20 потрібний до CMP/SETG?
  4) Чому помилка у 64-му атомі не створює частковий stdout?
  5) Чому 32 W1 bytes не є одним канонічним .sens документом? }
function BuildD12GreaterBatch32ELF:RawByteString;
var W:TExactWords;
    Decode5,Decode2,Table,Diagnostic,Code,E:RawByteString;
    Rejects:TJumpList;Leas:TLeaList;
    I,J,Total,InputLoop,InputEnd,CompareLoop,OutputWrite,RejectStart,
    Table5At,Table2At,ResultAt,ErrorAt:SizeInt;
    JReadEOF,JReadNext,JInputSize,JCompareDone,JCompareNext:TJump;
    G:TELFGeometry;

  procedure Emit(const Bytes:RawByteString);
  begin
    Need(Length(Code)+Length(Bytes)<4096,'перевищено машинний бюджет');
    Code:=Code+Bytes;
  end;
  procedure Emit32(X:LongWord);
  var K:SizeInt;
  begin for K:=0 to 3 do begin Emit(AnsiChar(X and $FF));X:=X shr 8 end end;
  procedure Patch32(Pos:SizeInt;X:LongWord);
  var K:SizeInt;
  begin
    Need((Pos>=0) and (Pos+4<=Length(Code)),'зміщення x86 поза кодом');
    for K:=0 to 3 do begin
      Code[Pos+K+1]:=AnsiChar(X and $FF);X:=X shr 8;
    end;
  end;
  function Jcc(Opcode:AnsiChar):TJump;
  begin Result.Pos:=Length(Code);Result.Bytes:=6;
    Emit(#$0F+Opcode+#0#0#0#0) end;
  function Jmp:TJump;
  begin Result.Pos:=Length(Code);Result.Bytes:=5;Emit(#$E9#0#0#0#0) end;
  procedure Link(const Jump:TJump;Target:SizeInt);
  begin
    Need((Jump.Bytes in [5,6]) and (Jump.Pos>=0) and
      (Jump.Pos+Jump.Bytes<=Length(Code)) and
      (Target>=0) and (Target<=Length(Code)),'неправильний machine jump');
    Patch32(Jump.Pos+Jump.Bytes-4,
      LongWord(LongInt(Target-Jump.Pos-Jump.Bytes)));
  end;
  procedure FailOn(Opcode:AnsiChar);
  var N:SizeInt;
  begin
    N:=Length(Rejects);SetLength(Rejects,N+1);
    Rejects[N]:=Jcc(Opcode);
  end;
  procedure Lea(Kind:Byte);
  var N:SizeInt;
  begin
    N:=Length(Leas);SetLength(Leas,N+1);
    Leas[N].Pos:=Length(Code);Leas[N].Kind:=Kind;
    Emit(#$48#$8D#$35#0#0#0#0); { lea rsi,[rip+table] }
  end;
  function Bits(WordValue,Width:SizeInt):RawByteString;
  var K:SizeInt;
  begin
    SetLength(Result,Width);
    for K:=1 to Width do
      if (WordValue and (1 shl (Width-K)))<>0 then Result[K]:='1'
      else Result[K]:='0';
  end;
  procedure DecodeAtom(Offset:Byte;Second:Boolean);
  var K:Byte;
  begin
    for K:=0 to 2 do begin
      Emit(#$41#$0F#$B6#$45+AnsiChar(Offset+K));
      { movzx eax,byte [r13+disp8] }
      if K=2 then Lea(1) else Lea(0);
      Emit(#$0F#$B6#$04#$06); { movzx eax,byte [rsi+rax] }
      Emit(#$3D#$FF#0#0#0);  { cmp eax,255 }
      FailOn(#$84);           { je reject }
      if K=0 then Emit(#$C1#$E0#$07)
      else if K=1 then Emit(#$C1#$E0#$02);
      if Second then begin
        if K=0 then Emit(#$41#$89#$C1) { mov r9d,eax }
        else Emit(#$41#$09#$C1);      { or r9d,eax }
      end else begin
        if K=0 then Emit(#$41#$89#$C0) { mov r8d,eax }
        else Emit(#$41#$09#$C0);      { or r8d,eax }
      end;
    end;
    if Second then begin
      Emit(#$41#$C1#$E1#$14); { shl r9d,20 }
      Emit(#$41#$C1#$F9#$14); { sar r9d,20 }
    end else begin
      Emit(#$41#$C1#$E0#$14); { shl r8d,20 }
      Emit(#$41#$C1#$F8#$14); { sar r8d,20 }
    end;
  end;
  procedure Put(Offset:SizeInt;X:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset+Count<=Length(Result)),'ELF header поза образом');
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(X and $FF); X:=X shr 8;
    end;
  end;
var Target:SizeInt;
begin
  Result:='';SetLength(W,1);
  Decode5:=StringOfChar(AnsiChar(InvalidByte),256);
  Decode2:=StringOfChar(AnsiChar(InvalidByte),256);
  for I:=0 to 31 do begin
    W[0]:=Bits(I,5);E:=EncodeT5M(W);
    Need(Length(E)=1,'W5 T5M не вмістився у байт');
    J:=Ord(E[1]);
    Need(Decode5[J+1]=AnsiChar(InvalidByte),'колізія канонічного W5');
    Decode5[J+1]:=AnsiChar(I);
  end;
  for I:=0 to 3 do begin
    W[0]:=Bits(I,2);E:=EncodeT5M(W);
    Need(Length(E)=1,'W2 T5M не вмістився у байт');
    J:=Ord(E[1]);
    Need(Decode2[J+1]=AnsiChar(InvalidByte),'колізія канонічного W2');
    Decode2[J+1]:=AnsiChar(I);
  end;
  W[0]:='0';Table:=EncodeT5M(W);
  W[0]:='1';E:=EncodeT5M(W);
  Need((Length(Table)=1) and (Length(E)=1) and
    (Table<>E),'відсутні точні коди W1');
  Table:=Table+E;
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString(
    'Д12-БІЛЬШЕ-ПАКЕТ-ВІДМОВА: невірні 32 пари фізичних W12')))+#10;
  Code:='';SetLength(Rejects,0);SetLength(Leas,0);
  { Linux read loop. 193 sentinel для виявлення зайвого.
    Після кожного short read повертаємось у цикл, тільки 0 є EOF. }
  Emit(#$48#$81#$EC#0#$02#0#0); { sub rsp,512 }
  Emit(#$45#$31#$E4);           { xor r12d,r12d }
  InputLoop:=Length(Code);
  Emit(#$31#$C0);               { xor eax,eax, sys_read }
  Emit(#$31#$FF);               { xor edi,edi, fd 0 }
  Emit(#$48#$89#$E6);           { mov rsi,rsp }
  Emit(#$4C#$01#$E6);           { add rsi,r12 }
  Emit(#$BA#$C1#0#0#0);         { mov edx,193 }
  Emit(#$4C#$29#$E2);           { sub rdx,r12 }
  Emit(#$0F#$05);               { syscall }
  Emit(#$48#$85#$C0);           { test rax,rax }
  FailOn(#$88);                 { js reject }
  JReadEOF:=Jcc(#$84);          { je eof }
  Emit(#$49#$01#$C4);           { add r12,rax }
  Emit(#$49#$81#$FC#$C0#0#0#0); { cmp r12,192 }
  FailOn(#$87);                 { ja reject }
  JReadNext:=Jmp;
  InputEnd:=Length(Code);
  Emit(#$49#$81#$FC#$C0#0#0#0);
  JInputSize:=Jcc(#$85);        { jne reject }
  Emit(#$4C#$8D#$2C#$24);      { lea r13,[rsp] input ptr }
  Emit(#$4C#$8D#$B4#$24#0#$01#0#0); { lea r14,[rsp+256] output }
  Emit(#$31#$DB);               { xor ebx,ebx }
  CompareLoop:=Length(Code);
  Emit(#$83#$FB#$20);           { cmp ebx,32 }
  JCompareDone:=Jcc(#$84);
  DecodeAtom(0,False);DecodeAtom(3,True);
  Emit(#$45#$39#$C8);           { cmp r8d,r9d signed }
  Emit(#$0F#$9F#$C0);           { setg al }
  Emit(#$0F#$B6#$C0);           { movzx eax,al }
  Lea(2);                       { W1 D1 output table }
  Emit(#$8A#$04#$06);           { mov al,[rsi+rax] }
  Emit(#$41#$88#$06);           { mov [r14],al }
  Emit(#$49#$FF#$C6);           { inc r14 }
  Emit(#$49#$83#$C5#$06);       { add r13,6 }
  Emit(#$83#$C3#$01);           { add ebx,1 }
  JCompareNext:=Jmp;
  OutputWrite:=Length(Code);
  Emit(#$B8#$01#0#0#0);         { sys_write 1 }
  Emit(#$BF#$01#0#0#0);         { stdout }
  Emit(#$48#$8D#$B4#$24#0#$01#0#0); { rsi=rsp+256 }
  Emit(#$BA#$20#0#0#0);         { 32 W1 bytes }
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);         { sys_exit 0 }
  Emit(#$31#$FF);
  Emit(#$0F#$05);
  RejectStart:=Length(Code);
  Emit(#$B8#$01#0#0#0);         { write(2, diagnostic, len) }
  Emit(#$BF#$02#0#0#0);
  Lea(3);
  Emit(#$BA);Emit32(LongWord(Length(Diagnostic)));
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);         { exit 2 }
  Emit(#$BF#$02#0#0#0);
  Emit(#$0F#$05);
  Need(Length(Rejects)=8,'неповний reject gate');
  for I:=0 to High(Rejects) do Link(Rejects[I],RejectStart);
  Link(JReadEOF,InputEnd);Link(JReadNext,InputLoop);
  Link(JInputSize,RejectStart);
  Link(JCompareDone,OutputWrite);
  Link(JCompareNext,CompareLoop);
  Table5At:=Length(Code);
  Table2At:=Table5At+Length(Decode5);
  ResultAt:=Table2At+Length(Decode2);
  ErrorAt:=ResultAt+Length(Table);
  for I:=0 to High(Leas) do begin
    case Leas[I].Kind of
      0:Target:=Table5At;
      1:Target:=Table2At;
      2:Target:=ResultAt;
      3:Target:=ErrorAt;
    else raise ED12GreaterBatchError.Create('невідома T5M таблиця') end;
    Patch32(Leas[I].Pos+3,
      LongWord(LongInt(Target-(Leas[I].Pos+7))));
  end;
  Total:=HeaderBytes+Length(Code)+Length(Decode5)+Length(Decode2)+
    Length(Table)+Length(Diagnostic);
  Need((Total>HeaderBytes) and (Total<8192),'ELF завеликий');
  SetLength(Result,Total);FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  J:=HeaderBytes+Length(Code);
  for I:=1 to Length(Decode5) do Result[J+I]:=Decode5[I];
  Inc(J,Length(Decode5));
  for I:=1 to Length(Decode2) do Result[J+I]:=Decode2[I];
  Inc(J,Length(Decode2));
  for I:=1 to Length(Table) do Result[J+I]:=Table[I];
  Inc(J,Length(Table));
  for I:=1 to Length(Diagnostic) do Result[J+I]:=Diagnostic[I];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.FileBytes=Total) and
    (G.Entry=HeaderBytes),'неканонічна геометрія машинного ELF');
end;
end.
