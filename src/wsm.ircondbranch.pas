{ G6.100 — чинний verified ExactIR D3:110 -> host x86-64 rel32 -> ELF64 PIE.
  СЕМАНТИКА, domain identity, кількість/форма умов і допустимі
  D1/EQ значення визначає ВИКЛЮЧНО LowerPinnedIRCond з wsm.ircond.
  Новий модуль тільки обчислює машинні переходи і виводить packed
  T5M байти pinned D1:0/1 або структурної D3:000. Ніякого власного
  registry, текстового dispatch, Core1/4 визначення чи нового reader.

  Фізичний вхід: позичений packed RawByteString .sens; AuthorityRoot:
  шлях до pinned external/sens. Lowered — stack record, машинні байти
  у TX64Code (керований RawByteString); повертається owned ELF64.
  Всі fixup 0-based, безпечне двофазне патчування; на відмові немає
  частково опублікованого ELF. Квоти 4 D3-гілки / 256 machine bytes.

  Запитання: 1) Чому D3:000 не замінюємо D1:0?
  2) Чому JZ перевіряє машинне D1:1, а не host truthiness?
  3) Навіщо дві різні цілі — наступна гілка і спільний вихід?
  4) Чому відповідь із незалежного SENS потрібна після ELF?
  5) Де закінчується SENS-закон і починається host codegen? }
unit wsm.ircondbranch;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRCondBranchError=class(Exception);
function BuildIRCondBranchELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.ircond,wsm.x64code,wsm.x64branch,wsm.t5m,wsm.elfgeometry;

const
  HeaderBytes=120;
  MaxClauses=4;    { host-ресурс, не закон мови }
  MaxCodeBytes=256;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRCondBranchError.Create(Why) end;

procedure Emit(var C:TX64Code;const Data:RawByteString);
begin
  Need((Length(Data)>0) and
       (Length(C.Bytes)<=MaxCodeBytes-Length(Data)),
       'Переповнено host-буфер x86-64');
  C.Bytes:=C.Bytes+Data;
end;

procedure EmitValue(var C:TX64Code;const V:TIRCondValue);
begin
  Need((V.Kind<=1) and (V.LeftBit<=1) and (V.RightBit<=1),
       'Пошкоджено verified lower value');
  X64MovImm32(C,xrAX,V.LeftBit);
  if V.Kind=1 then begin
    X64MovImm32(C,xrCX,V.RightBit);
    { CMP EAX,ECX ; SETE AL ; MOVZX EAX,AL. EQ виконує CPU. }
    Emit(C,#$39#$C8#$0F#$94#$C0#$0F#$B6#$C0);
  end;
end;

procedure EmitTail(var C:TX64Code);
begin
  X64SubRsp8(C,8);
  Emit(C,#$88#$1C#$24); { MOV [RSP],BL, рівно 1 packed T5M byte }
  X64MovImm32(C,xrAX,1);
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  { Linux sys_write повертає RAX=1 тільки при повному записі
    одного фізичного T5M байта; RDX=1 є host довжиною, НЕ D1.
    CMP RAX,RDX; JNE +9 пропускає рівно exit(0) при -errno,
    нулі чи короткому записі. Помилка завершується exit(2).
    1) Чому навіть нульовий write не доводить повний D1/D3?
    2) Чому ця перевірка є host механікою, не новим SENS законом?
    3) Чому JNE має перескочити саме дев'ять машинних байтів?
    4) Чому відхилений stdout не може повертати exit(0)? }
  Emit(C,#$48#$39#$D0#$75#$09); { cmp rax,rdx; jne exit(2) }
  X64MovImm32(C,xrAX,60);
  X64XorEDI(C);
  X64Syscall(C);                { exit(0) тільки після RAX=1 }
  X64MovImm32(C,xrAX,60);
  X64MovImm32(C,xrDI,2);
  X64Syscall(C);                { exit(2) при Linux I/O відмові }
end;

procedure PutLE(var Image:RawByteString;Offset:SizeInt;
  Value:QWord;Count:SizeInt);
var J:SizeInt;
begin
  Need((Offset>=0) and (Count>=1) and (Count<=8) and
       (Offset<=Length(Image)-Count),'ELF поле поза образом');
  for J:=0 to Count-1 do begin
    Image[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function MakePIE(const C:TX64Code):RawByteString;
var Size,J:SizeInt; Geometry:TELFGeometry;
begin
  Need((Length(C.Bytes)>0) and (Length(C.Bytes)<=MaxCodeBytes),
       'Немає допущеного машинного коду');
  Size:=HeaderBytes+Length(C.Bytes);
  SetLength(Result,Size);
  FillChar(Result[1],Size,0);
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,3,2);PutLE(Result,18,62,2);PutLE(Result,20,1,4);
  PutLE(Result,24,HeaderBytes,8);PutLE(Result,32,64,8);
  PutLE(Result,52,64,2);PutLE(Result,54,56,2);PutLE(Result,56,1,2);
  PutLE(Result,64,1,4);PutLE(Result,68,5,4);
  PutLE(Result,80,0,8);PutLE(Result,88,0,8);
  PutLE(Result,96,Size,8);PutLE(Result,104,Size,8);PutLE(Result,112,$1000,8);
  for J:=1 to Length(C.Bytes) do Result[HeaderBytes+J]:=C.Bytes[J];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.MachineBytes=Length(C.Bytes)),
       'Породжений PIE не пройшов host ELF64 перевірку');
end;

function BuildIRCondBranchELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var
  Lowered:TLoweredIRCond;
  C:TX64Code;
  Words:TExactWords;
  EncZero,EncOne,EncEmpty:RawByteString;
  Delta:SizeInt;
  I,TrueFix,FalseFix,PreviousFalse,TailStart,Start:SizeInt;
  TailFix:array[0..MaxClauses-1] of SizeInt;
begin
  Result:='';
  try
    LowerPinnedIRCond(Physical,AuthorityRoot,Lowered);
    Need(Lowered.Count<=MaxClauses,
      'Потрібна умова з не більш як 4 перевіреними гілками');
    SetLength(Words,1);
    Words[0]:='0'; EncZero:=EncodeT5M(Words);
    Words[0]:='1'; EncOne:=EncodeT5M(Words);
    Words[0]:='000'; EncEmpty:=EncodeT5M(Words);
    Need((Length(EncZero)=1) and (Length(EncOne)=1) and
         (Length(EncEmpty)=1) and (EncZero<>EncOne) and
         (EncZero<>EncEmpty) and (EncOne<>EncEmpty),
         'Pinned T5M D1/D3 відповіді неоднозначні');
    Delta:=Ord(EncOne[1])-Ord(EncZero[1]);
    Need((Delta>0) and (Delta<=127),
         'Pinned T5M різниця D1 не вмістилась у signed imm8');
    X64Reset(C);
    PreviousFalse:=-1;
    for I:=0 to Lowered.Count-1 do begin
      { NOP дає живу інструкцію-ціль для попередньої false-гілки. }
      Start:=Length(C.Bytes);
      Emit(C,#$90);
      if PreviousFalse>=0 then
        X64PatchBranch(C,xbJump,PreviousFalse,Start);

      EmitValue(C,Lowered.Clauses[I].TestValue);
      Emit(C,#$83#$F8#$01); { CMP EAX, exact D1:1 }
      X64EmitBranch(C,xbZero,TrueFix);  { JZ selected expression }
      X64EmitBranch(C,xbJump,FalseFix);{ JMP next clause }
      Start:=Length(C.Bytes);
      { Вираз не виконується, доки CPU не вибрав його. }
      EmitValue(C,Lowered.Clauses[I].ExpressionValue);
      { Runtime: D1 bit у EAX -> канонічний T5M byte.
        IMUL EAX,EAX,delta; ADD AL,zero; MOV BL,AL. }
      Emit(C,#$6B#$C0+AnsiChar(Delta)+#$04+EncZero[1]+#$88#$C3);
      X64EmitBranch(C,xbJump,TailFix[I]);
      X64PatchBranch(C,xbZero,TrueFix,Start);
      PreviousFalse:=FalseFix;
    end;

    { Вичерпання всіх D1:0 тестів — лише структурна D3:000. }
    Start:=Length(C.Bytes);
    Emit(C,#$B3+EncEmpty[1]);
    if PreviousFalse>=0 then
      X64PatchBranch(C,xbJump,PreviousFalse,Start);
    TailStart:=Length(C.Bytes);
    EmitTail(C);
    for I:=0 to Lowered.Count-1 do
      X64PatchBranch(C,xbJump,TailFix[I],TailStart);
    Result:=MakePIE(C);
  except
    on E:EIRCondBranchError do begin Result:=''; raise end;
    on E:Exception do begin
      Result:='';
      raise EIRCondBranchError.Create('Відхилено нативну IR-умову: '+E.Message);
    end;
  end;
end;
end.
