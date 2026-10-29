{ G6.111 — один багаторазовий x86-64 ELF64 для фізичного НСД D6:010101.
  Єдиний мовний закон pinned juv4uk/sens Contract 12, lib/domains/d6.lisp.
  Host stdin: 6 байтів = два окремі canonical T5M D12; не один .sens документ.
  Будь-який знаковий D12 допущено; signed вихід точно -2048..2047.
  Знаки обробляє CPU: SENS-оракул на (3,-1) повертає -1, НЕ +1.
  Знак виходу: знак другого операнда, або першого, якщо другий нуль.
  Тільки runtime-інструкції (без host gcd), signed D12 вихід fail-closed.
  Спільний механічний transport засновано на вже доведеному G6.88 D12 ADD;
  таблиці T5M виводяться лише через чинний EncodeT5M.
  D7 текст та англійські назви не є семантичним dispatch.
}
unit wsm.elfd12nsdpotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12NsdStreamELFError=class(Exception);
function BuildD12StreamNsdELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry;

const HeaderBytes=120;
      MaxCode=4096;
      InvalidByte=255;
type TOffsetArray=array of SizeInt;
     TLeaKindArray=array of Byte;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12NsdStreamELFError.Create(Why);
end;

{ Result: owned FPC RawByteString bytes Linux x86-64 ELF64 ET_DYN.
  Input під час роботи машини: 6 host-байтів, два окремі W12,
  не один багатослівний .sens; read(0,rsp,7) перевіряє зайві байти.
  12-бітне signed ADD виконує CPU, не Pascal host.
  Вихід: 3 canonical packed T5M байти, підібрані за реальним EAX.
  Тимчасові таблиці й Code — managed RawByteString з lifetime виклику.
  Питання: 1) Чому W12 має 5+5+2 трити? 2) Чому 6 байтів stdin
  не означають один .sens файл? 3) Чому reject при D12→D24?
  4) Чому x86-64 ADD недостатній без канонічного T5M codec?
  5) Як RIP-rel32 працює за PIE/ASLR? }
function BuildD12StreamNsdELF:RawByteString;
var Words:TExactWords;
    Decode5,Decode2,Encode5,Encode2,Diagnostic,Code,Encoded:RawByteString;
    Branches,Leas:TOffsetArray;
    LeaKinds:TLeaKindArray;
    I,J,CodeBytes,RejectAt,Data5,Data2,Out5,Out2,ErrorAt,Total,LoopPos,LoopJz,LoopJmp,LoopEnd:SizeInt;
    Geometry:TELFGeometry;

  procedure Emit(const Bytes:RawByteString);
  begin
    Need(Length(Code)+Length(Bytes)<MaxCode,'машинний код перевищив бюджет');
    Code:=Code+Bytes;
  end;
  procedure Emit32(Value:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin
      Emit(AnsiChar(Byte(Value and $FF))); Value:=Value shr 8;
    end;
  end;
  procedure Patch32(Pos0:SizeInt;SignedValue:LongInt);
  var K:SizeInt;V:LongWord;
  begin
    Need((Pos0>=0) and (Pos0+4<=Length(Code)),'RIP/branch patch поза образом');
    V:=LongWord(SignedValue);
    for K:=0 to 3 do begin
      Code[Pos0+K+1]:=AnsiChar(Byte(V and $FF)); V:=V shr 8;
    end;
  end;
  procedure Put(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset+Count<=Length(Result)),'ELF поле поза образом');
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(Value and $FF));Value:=Value shr 8;
    end;
  end;
  { x86 near Jcc rel32; ціль — одна fail-closed гілка. }
  procedure RejectOn(ConditionOpcode:AnsiChar);
  var P:SizeInt;
  begin
    P:=Length(Code);
    Emit(#$0F+ConditionOpcode+#0#0#0#0);
    SetLength(Branches,Length(Branches)+1);
    Branches[High(Branches)]:=P;
  end;
  { lea rsi,[rip+table], table kind = 0:decode5,1:decode2,
    2:encode5,3:encode2,4:utf8 diagnostic. }
  procedure LeaTable(Kind:Byte);
  var N:SizeInt;
  begin
    N:=Length(Leas);
    SetLength(Leas,N+1);SetLength(LeaKinds,N+1);
    Leas[N]:=Length(Code);LeaKinds[N]:=Kind;
    Emit(#$48#$8D#$35#0#0#0#0);
  end;
  function BitWord(Value,Width:SizeInt):RawByteString;
  var K:SizeInt;
  begin
    SetLength(Result,Width);
    for K:=1 to Width do
      if (Value and (1 shl (Width-K)))<>0 then
        Result[K]:='1' else Result[K]:='0';
  end;
  { Decode двох W12 у r8d,r9d, з повною перевіркою кожного
    фізичного T5M байта. Декодер бере словник лише з EncodeT5M,
    ніколи не виводить SENS закон з ASCII чи з довжини слова. }
  procedure DecodeAtom(Base:Byte;Second:Boolean);
  var K:Byte;
  begin
    for K:=0 to 2 do begin
      Emit(#$0F#$B6#$44#$24+AnsiChar(Base+K));
      if K=2 then LeaTable(1) else LeaTable(0);
      Emit(#$0F#$B6#$04#$06);       { movzx eax,byte [rsi+rax] }
      Emit(#$3D#$FF#0#0#0);          { cmp eax,255 invalid }
      RejectOn(#$84);               { je reject }
      if K=0 then Emit(#$C1#$E0#$07)
      else if K=1 then Emit(#$C1#$E0#$02);
      if Second then begin
        if K=0 then Emit(#$41#$89#$C1) else Emit(#$41#$09#$C1);
      end else begin
        if K=0 then Emit(#$41#$89#$C0) else Emit(#$41#$09#$C0);
      end;
    end;
    if Second then begin
      Emit(#$41#$C1#$E1#$14); { shl r9d,20 }
      Emit(#$41#$C1#$F9#$14); { sar r9d,20 signed D12 }
    end else begin
      Emit(#$41#$C1#$E0#$14); { shl r8d,20 }
      Emit(#$41#$C1#$F8#$14); { sar r8d,20 signed D12 }
    end;
  end;
  procedure EncodeChunk(Chunk:Byte);
  begin
    Emit(#$89#$D8);                 { mov eax,ebx (sum 12 bits) }
    if Chunk=0 then Emit(#$C1#$E8#$07)
    else if Chunk=1 then Emit(#$C1#$E8#$02);
    if Chunk=2 then Emit(#$83#$E0#$03) else Emit(#$83#$E0#$1F);
    if Chunk=2 then LeaTable(3) else LeaTable(2);
    Emit(#$8A#$04#$06);             { mov al,[rsi+rax] }
    if Chunk=0 then Emit(#$88#$04#$24)
    else Emit(#$88#$44#$24+AnsiChar(Chunk));
  end;
var Target:SizeInt;
begin
  Result:='';
  SetLength(Words,1);
  Decode5:=StringOfChar(AnsiChar(InvalidByte),256);
  Decode2:=StringOfChar(AnsiChar(InvalidByte),256);
  SetLength(Encode5,32);SetLength(Encode2,4);
  for I:=0 to 31 do begin
    Words[0]:=BitWord(I,5);Encoded:=EncodeT5M(Words);
    Need(Length(Encoded)=1,'W5 codec порушено');
    J:=Ord(Encoded[1]);
    Need(Decode5[J+1]=AnsiChar(InvalidByte),'колізія W5 T5M');
    Decode5[J+1]:=AnsiChar(I); Encode5[I+1]:=Encoded[1];
  end;
  for I:=0 to 3 do begin
    Words[0]:=BitWord(I,2);Encoded:=EncodeT5M(Words);
    Need(Length(Encoded)=1,'W2 codec порушено');
    J:=Ord(Encoded[1]);
    Need(Decode2[J+1]=AnsiChar(InvalidByte),'колізія W2 T5M');
    Decode2[J+1]:=AnsiChar(I); Encode2[I+1]:=Encoded[1];
  end;
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString(
    'Д12-НСД-ПОТІК-ВІДМОВА: некоректний T5M або вихід поза signed D12')))+#10;
  Code:='';SetLength(Branches,0);SetLength(Leas,0);SetLength(LeaKinds,0);
  Emit(#$48#$83#$EC#$20);        { sub rsp,32 }
  Emit(#$31#$C0);                { xor eax,eax = read }
  Emit(#$31#$FF);                { xor edi,edi = stdin }
  Emit(#$48#$89#$E6);            { mov rsi,rsp }
  Emit(#$BA#$07#0#0#0);          { edx=7 to catch surplus input }
  Emit(#$0F#$05);                { syscall read }
  Emit(#$48#$83#$F8#$06);        { cmp rax,6 exact host frame }
  RejectOn(#$85);               { jne invalid }
  DecodeAtom(0,False);
  DecodeAtom(3,True);
  { Упереджений host-sign normalization ЗАБОРОНЕНО: pinned SENS
    реально повертає -1 для D6:010101(3,-1).
    Після точного D12 admission знакові біти збережено в r8d/r9d.
    Вибір знака machine-only: r9d, а якщо r9d=0, то r8d.
    CMOVZ тільки механічний x86 вибір, жодного D7 dispatch.
    Абсолютні модулі рахуються CPU, включно з magnitude(-2048)=2048.
    Після Euclid знак відновлює CPU; -2048 вкладається у signed D12. }
  Emit(#$45#$89#$CA);              { mov r10d,r9d }
  Emit(#$45#$85#$D2);              { test r10d,r10d }
  Emit(#$45#$0F#$44#$D0);         { cmovz r10d,r8d; fallback when right=0 }
  Emit(#$41#$C1#$FA#$1F);         { sar r10d,31: 0 or -1 }
  Emit(#$44#$89#$C0);              { mov eax,r8d signed D12 }
  Emit(#$99);                       { cdq = sign mask in edx }
  Emit(#$31#$D0);                   { xor eax,edx }
  Emit(#$29#$D0);                   { sub eax,edx = abs }
  Emit(#$44#$89#$C9);              { mov ecx,r9d signed D12 }
  Emit(#$89#$CA);                   { mov edx,ecx }
  Emit(#$C1#$FA#$1F);              { sar edx,31 = sign mask }
  Emit(#$31#$D1);                   { xor ecx,edx }
  Emit(#$29#$D1);                   { sub ecx,edx = abs }
  LoopPos:=Length(Code);
  Emit(#$85#$C9);                   { test ecx,ecx }
  LoopJz:=Length(Code);
  Emit(#$0F#$84#0#0#0#0);           { jz finished }
  Emit(#$31#$D2);                   { xor edx,edx before unsigned div }
  Emit(#$F7#$F1);                   { div ecx: remainder in edx }
  Emit(#$89#$C8);                   { mov eax,ecx }
  Emit(#$89#$D1);                   { mov ecx,edx }
  LoopJmp:=Length(Code);
  Emit(#$E9#0#0#0#0);               { jmp loop }
  LoopEnd:=Length(Code);
  Patch32(LoopJz+2,LongInt(LoopEnd-(LoopJz+6)));
  Patch32(LoopJmp+1,LongInt(LoopPos-(LoopJmp+5)));
  Emit(#$44#$31#$D0);              { xor eax,r10d: result signed }
  Emit(#$44#$29#$D0);              { sub eax,r10d }
  Emit(#$3D#$FF#$07#0#0);          { cmp eax,2047 signed }
  RejectOn(#$8F);                   { jg: result requires larger Dn }
  Emit(#$3D#0#$F8#$FF#$FF);       { cmp eax,-2048 signed }
  RejectOn(#$8C);                   { jl: result outside signed D12 }
  Emit(#$25#$FF#$0F#0#0);         { exact signed 12-bit output }
  Emit(#$89#$C3);                  { mov ebx,eax; shared T5M output }
  for I:=0 to 2 do EncodeChunk(Byte(I));
  Emit(#$B8#$01#0#0#0);          { write(1,rsp,3) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$03#0#0#0);
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);          { exit(0) }
  Emit(#$31#$FF);
  Emit(#$0F#$05);
  RejectAt:=Length(Code);
  Emit(#$B8#$01#0#0#0);          { write(2,diagnostic,n) }
  Emit(#$BF#$02#0#0#0);
  LeaTable(4);
  Emit(#$BA);Emit32(LongWord(Length(Diagnostic)));
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);          { exit(2) }
  Emit(#$BF#$02#0#0#0);
  Emit(#$0F#$05);
  Need(Length(Branches)=9,'бракує 9 фізичних/знакових branch gates');
  for I:=0 to High(Branches) do
    Patch32(Branches[I]+2,LongInt(RejectAt-(Branches[I]+6)));

  CodeBytes:=Length(Code);
  Data5:=CodeBytes;
  Data2:=Data5+Length(Decode5);
  Out5:=Data2+Length(Decode2);
  Out2:=Out5+Length(Encode5);
  ErrorAt:=Out2+Length(Encode2);
  for I:=0 to High(Leas) do begin
    case LeaKinds[I] of
      0:Target:=Data5;
      1:Target:=Data2;
      2:Target:=Out5;
      3:Target:=Out2;
      4:Target:=ErrorAt;
    else raise ED12NsdStreamELFError.Create('невідомий host T5M table kind')
    end;
    Patch32(Leas[I]+3,LongInt(Target-(Leas[I]+7)));
  end;

  Total:=HeaderBytes+CodeBytes+Length(Decode5)+Length(Decode2)+
    Length(Encode5)+Length(Encode2)+Length(Diagnostic);
  Need((Total>HeaderBytes) and (Total<8192),'ELF поза квотою');
  SetLength(Result,Total);FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Result[HeaderBytes+I]:=Code[I];
  J:=HeaderBytes+CodeBytes;
  for I:=1 to Length(Decode5) do Result[J+I]:=Decode5[I];
  Inc(J,Length(Decode5));
  for I:=1 to Length(Decode2) do Result[J+I]:=Decode2[I];
  Inc(J,Length(Decode2));
  for I:=1 to Length(Encode5) do Result[J+I]:=Encode5[I];
  Inc(J,Length(Encode5));
  for I:=1 to Length(Encode2) do Result[J+I]:=Encode2[I];
  Inc(J,Length(Encode2));
  for I:=1 to Length(Diagnostic) do Result[J+I]:=Diagnostic[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
    (Geometry.FileBytes=Total),'ELF PIE геометрія відхилена');
end;
end.
