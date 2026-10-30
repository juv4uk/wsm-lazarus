{ G6.88 — один повторно використовуваний ELF64 PIE: два ДИНАМІЧНІ
  фізичні D12 зі stdin (host framing = два окремих packed W12 атоми).
  Тільки механізм x86-64, жодних нових мовних законів або D7 dispatch.
  На overflow виходить exit(2), а НЕ завужене SENS D12 число.
  Таблиці допуску й пакування породжує чинний wsm.t5m.EncodeT5M. }
unit wsm.elfd12potik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12StreamELFError=class(Exception);
function BuildD12StreamAddELF:RawByteString;
function BuildD12StreamAddFramedELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry,wsm.x64frameio;

const HeaderBytes=120;
      MaxCode=4096;
      InvalidByte=255;
type TOffsetArray=array of SizeInt;
     TLeaKindArray=array of Byte;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12StreamELFError.Create(Why);
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
function BuildD12StreamAddELF:RawByteString;
var Words:TExactWords;
    Decode5,Decode2,Encode5,Encode2,Diagnostic,Code,Encoded:RawByteString;
    Branches,Leas:TOffsetArray;
    LeaKinds:TLeaKindArray;
    I,J,CodeBytes,RejectAt,Data5,Data2,Out5,Out2,ErrorAt,Total:SizeInt;
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
    'Д12-ПОТІК-ВІДМОВА: неканонічні операнди або вихід поза D12')))+#10;
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
  Emit(#$44#$89#$C0);            { mov eax,r8d }
  Emit(#$44#$01#$C8);            { add eax,r9d in CPU }
  Emit(#$3D#$FF#$07#0#0);        { cmp eax,2047 }
  RejectOn(#$8F);               { jg D12 overflow }
  Emit(#$3D#0#$F8#$FF#$FF);      { cmp eax,-2048 }
  RejectOn(#$8C);               { jl D12 overflow }
  Emit(#$25#$FF#$0F#0#0);        { and eax,4095 }
  Emit(#$89#$C3);                { mov ebx,eax }
  for I:=0 to 2 do EncodeChunk(Byte(I));
  Emit(#$B8#$01#0#0#0);          { write(1,rsp,3) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$03#0#0#0);
  Emit(#$0F#$05);                { справжній sys_write(1,rsp,3) }
  { G6.221 — відповідь існує тільки після повного запису canonical
    D12 T5M, рівно 3 байти. Linux RAX=кількість байтів або -errno.
    При короткому/нульовому записі, -EBADF чи -ENOSPC використовуємо
    ВЖЕ НАЯВНУ машинну відмову stderr + exit(2), а не фальшивий exit(0).
    Це host I/O, не D5 закон, не локальний SENS evaluator.
    Типи: RAX signed 64-bit host, ConditionOpcode JNE; Branches —
    managed FPC масив 0-based фізичних 32-bit displacement; його
    lifetime тільки під час codegen, результат — owned ELF bytes.
    1) Чому RAX, а не значення signed ADD у EBX?
    2) Чому точно 3 packed T5M байти?
    3) Чому використовуємо існуючу RejectAt, а не новий dispatcher?
    4) Як перевіряється RIP/branch геометрія після доданого JNE? }
  Emit(#$48#$83#$F8#$03);        { cmp rax,3 }
  RejectOn(#$85);                { jne до чинного exit(2) }
  Emit(#$B8#$3C#0#0#0);          { exit(0) лише після повного write }
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
  Need(Length(Branches)=10,'бракує 9 фізичних/overflow gates та 1 stdout-write gate');
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
    else raise ED12StreamELFError.Create('невідомий host T5M table kind')
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

{ G6.231: замість зміни договору донорського API створено окрему
  host-обгортку для CLI, який приймає фрагментовані stdin frames.
  BuildD12StreamAddELF повертає незагорнутий, точно допущений ELF64
  для вже наявних wsm.elfd12mulpotik і wsm.elfd12quotpotik, які самі
  загортають свої змінені донори. Double wrap fail-closed.
  Фізичне W12 і точність двох атомів зберігає єдиний T5M codec.
  Результат — новий owned ELF image; Base/Geometry живуть тут.
  1) Чому один read не гарантує повні 6 байтів?
  2) Чому зміна базового API зламала вкладені машинні профілі?
  3) Як strict admission відкидає повторний prefix?
  4) Чому вихідна SENS семантика не визначається host frame? }
function BuildD12StreamAddFramedELF:RawByteString;
var Base:RawByteString; G:TELFGeometry;
begin
  Base:=BuildD12StreamAddELF;
  Result:=WrapExactSixByteFrame(Base);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)) and (Length(Result)>Length(Base)),
    'потоковий ELF із EOF-префіксом не пройшов перевірку геометрії');
end;
end.
