{ G6.119 — одна вкладена фізична D3:101 композиція у 3 CALL/RET.
  SENS закон НЕ визначається цим host модулем. Ратифіковані D3:101
  і D1:0/1 допускає pinned domain binder + ExactIR/guard із
  juv4uk/sens Contract 12.0. Кожен внутрішній D3:101 виконується
  справжнім машинним CALL до ОДНІЄЇ shared CMP/SETE/RET процедури;
  її два результати стають аргументами третього CALL.
  Перший результат зберігається у [RSP] як qword, не підміняється
  попередньо обчисленою константою у Pascal. Кадр 16 байтів.
  Межа: рівно 10 verified ExactIR вузлів / 3 рівності / 4 D1 атоми.
  Вхід Physical borrowed canonical T5M, результат owned ELF64 PIE.
  Всі збої fail closed без публікації образу, max 256 host bytes.
  Питання: (1) чому 2 вкладені EQ — 3 CPU CALL?
  (2) чому збереження RAX qword важливіше за Pascal precompute?
  (3) чому D3:000 <> D1:0, навіть коли текст схожий?
  (4) чому call rel32 відносний до кінця інструкції?
  (5) кому належать managed IR, фізичні слова і байти ELF? }
unit wsm.irnestedeqcall;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRNestedEqCallError=class(Exception);
function BuildPhysicalNestedEqCallELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
{ Лише host донор для оптимізатора; raw ELF не публікувати як завершений результат. }
function BuildPhysicalNestedEqCallDonorELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,wsm.exactirguard,
  wsm.x64code,wsm.x64stack,wsm.x64call,wsm.elfgeometry,
  wsm.elfwriteguard;

const HeaderBytes=120; MaxMachineBytes=256;
type TLoweredNested = record
  Bit:array[0..3] of Byte;
  SourceWord:array[0..3] of SizeInt;
end;

procedure Need(Yes:Boolean;const Why:String);
begin
  if not Yes then raise EIRNestedEqCallError.Create(Why);
end;

procedure AdmitHead(const IR:TExactIR;Index,Parent,Child,Depth:SizeInt);
var N:TExactIRNode;
begin
  N:=IR.Nodes[Index];
  Need((N.Kind=ikIdentity) and N.HasKey and (N.RootIndex=0) and
    (N.ParentIndex=Parent) and (N.ChildIndex=Child) and
    (N.Depth=Depth) and (N.SubtreeEndExclusive=Index+1) and
    (N.Key.Width=3) and
    SameKey(N.Key,ExactKey('101')),
    'виклик має містити точну ратифіковану pinned D3:101 голову');
end;

function AdmitD1(const IR:TExactIR;Index,Parent,Child,Depth:SizeInt):Byte;
var N:TExactIRNode;Bits:RawByteString;
begin
  N:=IR.Nodes[Index];
  Need((N.Kind=ikIdentity) and N.HasKey and (N.RootIndex=0) and
    (N.ParentIndex=Parent) and (N.ChildIndex=Child) and
    (N.Depth=Depth) and (N.SubtreeEndExclusive=Index+1) and
    (N.Key.Width=1),
    'аргумент має бути виключно точним D1, а не D3:000/D7/D12');
  Bits:=KeyBits(N.Key);
  if Bits='0' then Exit(0);
  if Bits='1' then Exit(1);
  raise EIRNestedEqCallError.Create('невідоме pinned D1 слово');
end;

procedure LowerNested(const Physical,AuthorityRoot:RawByteString;
  out Lowered:TLoweredNested);
var Tables:TDomainSet;IR:TExactIR;Stats:TExactIRGuardStats;
    Words:TExactWords;Candidate:TLoweredNested;I,J,Anchor:SizeInt;
begin
  FillChar(Lowered,SizeOf(Lowered),0);
  FillChar(Candidate,SizeOf(Candidate),0);
  Need((Length(Physical)>0) and (Length(Physical)<=512),
    'порожня або завелика packed фізична програма');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,
    'фізичний T5M не є канонічним round-trip');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildExactIR(Physical,Tables,IR);
  VerifyExactIRStructure(IR,Stats);
  Need((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=10) and (Stats.Roots=1) and
    (Stats.Nodes=10) and (Stats.BoundLeaves=7) and
    (IR.BoundLeaves=7),
    'непідтримана форма: потрібні 3 D3 рівності і 4 D1 атоми');
  Need((IR.Nodes[0].Kind=ikList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].Depth=0) and
    (IR.Nodes[0].SubtreeEndExclusive=10),
    'потрібен рівно один D2-root');
  AdmitHead(IR,1,0,0,1);
  for I:=0 to 1 do begin
    Anchor:=2+I*4;
    Need((IR.Nodes[Anchor].Kind=ikList) and
      (IR.Nodes[Anchor].RootIndex=0) and
      (IR.Nodes[Anchor].ParentIndex=0) and
      (IR.Nodes[Anchor].ChildIndex=I+1) and
      (IR.Nodes[Anchor].Depth=1) and
      (IR.Nodes[Anchor].SubtreeEndExclusive=Anchor+4),
      'порушено повний порядок двох D3 піддерев');
    AdmitHead(IR,Anchor+1,Anchor,0,2);
    for J:=0 to 1 do begin
      Candidate.Bit[I*2+J]:=AdmitD1(
        IR,Anchor+2+J,Anchor,J+1,2);
      Candidate.SourceWord[I*2+J]:=IR.Nodes[Anchor+2+J].WordIndex;
    end;
  end;
  Lowered:=Candidate;
end;

procedure Emit(var C:TX64Code;const Bytes:RawByteString);
begin
  Need((Length(Bytes)>0) and (Length(Bytes)<=MaxMachineBytes) and
       (Length(C.Bytes)<=MaxMachineBytes-Length(Bytes)),
       'машинний складений виклик перевищив квоту');
  C.Bytes:=C.Bytes+Bytes;
end;

procedure PutLE(var Image:RawByteString;Off:SizeInt;
  Value:QWord;Width:SizeInt);
var I:SizeInt;
begin
  Need((Off>=0) and (Width>=1) and (Width<=8) and
    (Off<=Length(Image)-Width),'ELF64 поле поза host образом');
  for I:=0 to Width-1 do begin
    Image[Off+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function EmitELF(const Plan:TLoweredNested):RawByteString;
var C:TX64Code;Encoded0,Encoded1:RawByteString;
    Words:TExactWords;Fix:array[0..2] of SizeInt;
    FunctionAt,Total,Delta,I:SizeInt;Geom:TELFGeometry;
begin
  Result:='';
  for I:=0 to 3 do Need(Plan.Bit[I]<=1,'пошкоджений D1 lower bit');
  SetLength(Words,1);
  Words[0]:='0';Encoded0:=EncodeT5M(Words);
  Words[0]:='1';Encoded1:=EncodeT5M(Words);
  Need((Length(Encoded0)=1) and (Length(Encoded1)=1) and
    (Ord(Encoded1[1])>Ord(Encoded0[1])) and
    (Ord(Encoded1[1])-Ord(Encoded0[1])<=127),
    'не допущено pinned T5M кодек двох різних D1');
  Delta:=Ord(Encoded1[1])-Ord(Encoded0[1]);

  X64Reset(C);
  Emit(C,#$48#$83#$E4#$F0); { AND RSP,-16; перед кожним CALL }
  X64StackSubtract(C,16);  { private aligned frame for left D1 }
  X64MovImm32(C,xrDI,Plan.Bit[0]);
  X64MovImm32(C,xrSI,Plan.Bit[1]);
  X64EmitLocalCall(C,Fix[0]);
  X64StackStore(C,xrAX,0); { actual CPU result of FIRST EQ }

  X64MovImm32(C,xrDI,Plan.Bit[2]);
  X64MovImm32(C,xrSI,Plan.Bit[3]);
  X64EmitLocalCall(C,Fix[1]);
  Emit(C,#$89#$C6);              { MOV ESI,EAX: 2nd EQ result }
  X64StackLoad(C,xrDI,0);         { MOV RDI,[RSP]: first EQ result }
  X64EmitLocalCall(C,Fix[2]);    { outer EQ on TWO RUNTIME results }

  Emit(C,#$6B#$C0+AnsiChar(Delta));
  Emit(C,#$83#$C0+Encoded0[1]);
  Emit(C,#$88#$04#$24);         { MOV [RSP],AL: physical D1 byte }
  X64MovImm32(C,xrAX,1);
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60);
  X64XorEDI(C);
  X64Syscall(C);

  FunctionAt:=Length(C.Bytes);
  Emit(C,#$39#$F7);            { shared CMP EDI,ESI }
  X64SetEAL(C);
  X64MovzxEAXAL(C);
  X64Return(C);
  for I:=0 to 2 do X64PatchLocalCall(C,Fix[I],FunctionAt);
  Need((FunctionAt>=1) and (Length(C.Bytes)<=MaxMachineBytes),
    'shared CALL/RET вийшли за machine quota');
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
  VerifySENSELF64(Result,Geom);
  Need((Geom.Kind=3) and (Geom.FileBytes=Total) and
    (Geom.MachineBytes=Length(C.Bytes)),
    'реальний ELF64 PIE не пройшов перевірку геометрії');
end;

function BuildPhysicalNestedEqCallDonorELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Plan:TLoweredNested;
begin
  Result:='';
  try
    LowerNested(Physical,AuthorityRoot,Plan);
    Result:=EmitELF(Plan);
  except
    on E:EIRNestedEqCallError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRNestedEqCallError.Create('Вкладений CALL відхилено: '+E.Message);
    end;
  end;
end;

{ Публічний завершений ELF відокремлено від raw машинного донора.
  Physical/AuthorityRoot позичені, RawByteString Result — owned FPC buffer.
  CPU робить рівно три CALL; guard перевіряє host syscall RAX=RDX,
  не змінюючи вже перевірений pinned D3:101 або фізичний D1/T5M.
  1) Чому guard має стояти ПІСЛЯ exact-domain admission?
  2) Чому raw donor потрібен старому інлайнеру, але не користувачеві?
  3) Чому Linux ENOSPC не є значенням D1:0?
  4) Чому JMP до checked epilogue не змінює жодного CALL rel32? }
function BuildPhysicalNestedEqCallELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:='';
  try
    Result:=RequireCompleteNativeWrite(
      BuildPhysicalNestedEqCallDonorELF(Physical,AuthorityRoot));
  except
    on E:EIRNestedEqCallError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRNestedEqCallError.Create(
        'Нативний вкладений CALL/T5M write відхилено: '+E.Message);
    end;
  end;
end;
end.
