{ G6.122: тільки машинний host-lowering уже перевіреної фізичної D3:110.
  Єдиний мовний допуск: LowerPinnedIRCond (pinned Contract 12.0):
  0..2 двочастинні гілки, значення exact D1 або D3:101(D1,D1).
  Цей модуль НЕ визначає SENS закон: D3:000 ≠ D1:0; порівняння
  виконується лише x86 CMP/SETE під час CALL/RET, не в Pascal.
  Умовні переходи не виконують false-expression, а всі D3:101
  викликають ту саму host-функцію. Початковий RSP вирівняно до 16.
  Physical і AuthorityRoot позичені; Lowered — локальний record;
  TX64Code.Bytes та ELF — managed host-байти, власність caller-а.
  Квота 256 машинних байтів та 2 гілки — host-ресурс, НЕ SENS закон.

  Питання: 1) Чому спільна EQ функція не є мовним registry?
  2) Чому false expression не виконується до відповідного JZ?
  3) Де D1 bit перетворюється на pinned physical T5M byte?
  4) Чому CALL fixup патчиться після визначення єдиного callee?
  5) Чому вузький ELF не підтверджує повний Core1/4 compiler? }
unit wsm.ircondcall;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRCondCallError=class(Exception);
function BuildIRCondCallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.ircond,wsm.x64code,wsm.x64branch,wsm.x64call,
     wsm.t5m,wsm.elfgeometry;

const HeaderBytes=120;MaxClauses=2;MaxBytes=256;MaxCalls=4;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRCondCallError.Create(Why);
end;

{ C — managed buffer owned by caller. Data — host binary bytes, not
  a serialized SENS value. Exception preserves already emitted code,
  but ELF is never published on failure.
  Запитання: 1) Навіщо перевірка квоти перед конкатенацією?
  2) Чому байти коду не трактуються як домен Dn?
  3) Хто відповідає за можливі переповнення? }
procedure Emit(var C:TX64Code;const Data:RawByteString);
begin
  Need((Length(Data)>0) and (Length(Data)<=MaxBytes) and
       (Length(C.Bytes)<=MaxBytes-Length(Data)),
       'COND/CALL: перевищено host 256 byte machine quota');
  C.Bytes:=C.Bytes+Data;
end;

{ Lowered від pinned guard: лише kind 0=literal D1, 1=вкладена
  D3:101 із двох D1. Для D3:101 машинні EDI/ESI беруться з exact
  D1, а EAX з'являється ВИКЛЮЧНО після справжнього CALL.
  Fixes — local host offsets, 0-based bytes; no SENS allocation.
  Запитання: 1) Чому kind=1 не можна обчислити наперед?
  2) Чи впливає проєкція «укр» на host CALL?
  3) Чому потрібен єдиний callee для всіх гілок? }
procedure EmitValue(var C:TX64Code;const V:TIRCondValue;
  var CallCount:SizeInt;var Calls:array of SizeInt);
begin
  Need((V.Kind<=1) and (V.LeftBit<=1) and (V.RightBit<=1),
    'COND/CALL: пошкоджено pinned lowering');
  if V.Kind=0 then
    X64MovImm32(C,xrAX,V.LeftBit)
  else begin
    Need((CallCount>=0) and (CallCount<Length(Calls)),
      'COND/CALL: забагато shared callsite');
    X64MovImm32(C,xrDI,V.LeftBit);
    X64MovImm32(C,xrSI,V.RightBit);
    X64EmitLocalCall(C,Calls[CallCount]);
    Inc(CallCount);
  end;
end;

procedure EmitTail(var C:TX64Code);
begin
  X64SubRsp8(C,8);
  Emit(C,#$88#$1C#$24);   { mov [rsp],bl — 1 canonical T5M byte }
  X64MovImm32(C,xrAX,1); { write(1,rsp,1) }
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60);
  X64XorEDI(C);
  X64Syscall(C);
end;

procedure PutLE(var Image:RawByteString;Off:SizeInt;V:QWord;Width:SizeInt);
var I:SizeInt;
begin
  Need((Off>=0) and (Width>=1) and (Width<=8) and
       (Off<=Length(Image)-Width),'COND/CALL: ELF host field out of range');
  for I:=0 to Width-1 do begin
    Image[Off+I+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

function MakePIE(const C:TX64Code):RawByteString;
var Total,I:SizeInt;G:TELFGeometry;
begin
  Need((Length(C.Bytes)>0) and (Length(C.Bytes)<=MaxBytes),
    'COND/CALL: невалідний machine buffer');
  Total:=HeaderBytes+Length(C.Bytes);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,3,2);PutLE(Result,18,62,2);PutLE(Result,20,1,4);
  PutLE(Result,24,HeaderBytes,8);PutLE(Result,32,64,8);
  PutLE(Result,52,64,2);PutLE(Result,54,56,2);PutLE(Result,56,1,2);
  PutLE(Result,64,1,4);PutLE(Result,68,5,4);
  PutLE(Result,80,0,8);PutLE(Result,88,0,8);
  PutLE(Result,96,Total,8);PutLE(Result,104,Total,8);
  PutLE(Result,112,$1000,8);
  for I:=1 to Length(C.Bytes) do
    Result[HeaderBytes+I]:=C.Bytes[I];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Total) and (G.MachineBytes=Length(C.Bytes)),
       'COND/CALL: ELF64 PIE geometry не підтверджено');
end;

function BuildIRCondCallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var L:TLoweredIRCond;C:TX64Code;Words:TExactWords;
    EncZero,EncOne,EncEmpty:RawByteString;
    CallFix:array[0..MaxCalls-1] of SizeInt;
    TailFix:array[0..MaxClauses-1] of SizeInt;
    I,CallCount,Delta,TrueFix,FalseFix,PrevFalse,
    Start,TailStart,FunctionAt:SizeInt;
begin
  Result:='';
  try
    LowerPinnedIRCond(Physical,AuthorityRoot,L);
    Need(L.Count<=MaxClauses,
      'COND/CALL: дозволено не більш як дві pinned гілки');
    SetLength(Words,1);
    Words[0]:='0';EncZero:=EncodeT5M(Words);
    Words[0]:='1';EncOne:=EncodeT5M(Words);
    Words[0]:='000';EncEmpty:=EncodeT5M(Words);
    Need((Length(EncZero)=1) and (Length(EncOne)=1) and
         (Length(EncEmpty)=1) and
         (EncZero<>EncOne) and (EncOne<>EncEmpty) and
         (EncZero<>EncEmpty),
      'COND/CALL: три pinned D1/D3 коди не є різними однобайтовими');
    Delta:=Ord(EncOne[1])-Ord(EncZero[1]);
    Need((Delta>0) and (Delta<=127),
      'COND/CALL: pinned T5M D1 delta не вміщується signed imm8');
    X64Reset(C);
    { Host ABI: initial process RSP aligned before every local CALL.
      RSI/EDI may be clobbered after CALL; branch result only in EAX. }
    Emit(C,#$48#$83#$E4#$F0);
    CallCount:=0;PrevFalse:=-1;
    for I:=0 to L.Count-1 do begin
      Start:=Length(C.Bytes);
      Emit(C,#$90); { live NOP target for previous false jump }
      if PrevFalse>=0 then
        X64PatchBranch(C,xbJump,PrevFalse,Start);
      EmitValue(C,L.Clauses[I].TestValue,CallCount,CallFix);
      Emit(C,#$83#$F8#$01);   { CMP EAX, exact D1:1 }
      X64EmitBranch(C,xbZero,TrueFix);
      X64EmitBranch(C,xbJump,FalseFix);
      Start:=Length(C.Bytes);
      { Вибраний expression виконуватиметься виключно через JZ. }
      EmitValue(C,L.Clauses[I].ExpressionValue,CallCount,CallFix);
      Emit(C,#$6B#$C0+AnsiChar(Delta)+#$04+EncZero[1]+#$88#$C3);
      X64EmitBranch(C,xbJump,TailFix[I]);
      X64PatchBranch(C,xbZero,TrueFix,Start);
      PrevFalse:=FalseFix;
    end;
    Start:=Length(C.Bytes);
    Emit(C,#$B3+EncEmpty[1]);  { only structural D3:000 when exhausted }
    if PrevFalse>=0 then
      X64PatchBranch(C,xbJump,PrevFalse,Start);
    TailStart:=Length(C.Bytes);
    EmitTail(C);
    for I:=0 to L.Count-1 do
      X64PatchBranch(C,xbJump,TailFix[I],TailStart);
    FunctionAt:=Length(C.Bytes);
    Emit(C,#$39#$F7); { shared cmp edi,esi }
    X64SetEAL(C);
    X64MovzxEAXAL(C);
    X64Return(C);
    for I:=0 to CallCount-1 do
      X64PatchLocalCall(C,CallFix[I],FunctionAt);
    Result:=MakePIE(C);
  except
    on E:EIRCondCallError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRCondCallError.Create('COND/CALL відхилено: '+E.Message);
    end;
  end;
end;
end.
