{ G6.57 — фізичний ExactIR -> двочастинний D3:110 -> виконуваний
  ELF64 PIE. Підмножина: 0..2 гілки з точними D1 тестом/виразом.
  SENS Contract 12 K12.3 — єдиний закон; це механізм, не нова семантика. }
unit wsm.ircond;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  EIRCondError = class(Exception);
  { Host-знижені регістрові біти; фізичні індекси — provenance.
    Ні чисел D12+, ні людських назв або SENS opcode в цьому record. }
  TIRCondClause = record
    TestBit, ExpressionBit: Byte;
    TestWord, ExpressionWord: SizeInt;
  end;
  TLoweredIRCond = record
    Count: Byte;
    HeadWord: SizeInt;
    Clauses: array[0..1] of TIRCondClause;
  end;

procedure LowerPinnedIRCond(const Physical, AuthorityRoot: RawByteString;
  out Lowered: TLoweredIRCond);
function BuildPinnedIRCondELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;

implementation
uses wsm.t5m, wsm.domain, wsm.bind, wsm.exactir,
  wsm.exactirguard, wsm.elfgeometry;

const
  ELFHeaderBytes = 120;
  MaxMachineBytes = 256; { host-бюджет, не мовний Dn-закон }

procedure Require(OK: Boolean; const Why: String);
begin
  if not OK then raise EIRCondError.Create(Why);
end;

procedure LowerPinnedIRCond(const Physical, AuthorityRoot: RawByteString;
  out Lowered: TLoweredIRCond);
var
  Tables: TDomainSet;
  IR: TExactIR;
  Stats: TExactIRGuardStats;
  Candidate: TLoweredIRCond;
  Count, I, Anchor, J: SizeInt;
begin
  FillChar(Lowered, SizeOf(Lowered), 0);
  FillChar(Candidate, SizeOf(Candidate), 0);
  Require((Length(Physical)>0) and (Length(Physical)<=65536),
    'Фізичне джерело .sens поза межею нативної умови');
  LoadPinnedDomains(AuthorityRoot, Tables);
  BuildExactIR(Physical, Tables, IR);
  VerifyExactIRStructure(IR, Stats);
  Require((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
          (Length(IR.Nodes)>=2) and
          (IR.Nodes[0].Kind=ikList) and
          (IR.Nodes[0].ParentIndex=-1) and
          (IR.Nodes[0].SubtreeEndExclusive=Length(IR.Nodes)),
    'Нативна умова потребує одного фізичного D2 списку');
  Require((IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
          SameKey(IR.Nodes[1].Key, ExactKey('110')) and
          (IR.Nodes[1].ParentIndex=0) and
          (IR.Nodes[1].ChildIndex=0),
    'Фізична голова не є точною pinned D3:110');
  Require(((Length(IR.Nodes)-2) mod 3=0) and
          ((Length(IR.Nodes)-2) div 3<=2),
    'Цей машинний зріз допускає лише 0..2 двочастинні гілки');
  Count := (Length(IR.Nodes)-2) div 3;
  Require(IR.BoundLeaves=1+2*Count,
    'Умовна форма має зайві або загублені точні доменні слова');
  Candidate.Count:=Byte(Count);
  Candidate.HeadWord:=IR.Nodes[1].WordIndex;
  for I:=0 to Count-1 do begin
    Anchor:=2+3*I;
    Require((IR.Nodes[Anchor].Kind=ikList) and
            (IR.Nodes[Anchor].ParentIndex=0) and
            (IR.Nodes[Anchor].ChildIndex=I+1) and
            (IR.Nodes[Anchor].SubtreeEndExclusive=Anchor+3),
      'Гілка COND мусить містити рівно два поля у фізичному D2');
    for J:=1 to 2 do
      Require((IR.Nodes[Anchor+J].Kind=ikIdentity) and
              IR.Nodes[Anchor+J].HasKey and
              (IR.Nodes[Anchor+J].ParentIndex=Anchor) and
              (IR.Nodes[Anchor+J].ChildIndex=J-1) and
              (IR.Nodes[Anchor+J].Key.Width=1) and
              (IR.Nodes[Anchor+J].Key.Bits<=1),
        'Тест і вираз гілки допускають лише точні D1 атоми');
    Candidate.Clauses[I].TestBit:=Byte(IR.Nodes[Anchor+1].Key.Bits);
    Candidate.Clauses[I].ExpressionBit:=Byte(IR.Nodes[Anchor+2].Key.Bits);
    Candidate.Clauses[I].TestWord:=IR.Nodes[Anchor+1].WordIndex;
    Candidate.Clauses[I].ExpressionWord:=IR.Nodes[Anchor+2].WordIndex;
  end;
  Lowered:=Candidate; { fail-closed: публікація тільки після повного guard }
end;

{ Емітер бере тільки знижений record: без Physical, ParseD2 або binder.
  Тест справді перевіряє x86-64 CMP/JNE під час запуску, а не Pascal.
  Вихід: рівно ОДИН байт pinned EncodeT5M(D1 або D3:000), без LF.
  ET_DYN без INTERP/DYNAMIC/relocation: PIE під Linux ASLR. }
function EmitLoweredIRCond(const Lowered: TLoweredIRCond): RawByteString;
var
  Machine, ZeroByte, OneByte, EmptyByte: RawByteString;
  Words: TExactWords;
  I, J, Total, SkipAt, From: SizeInt;
  ImageStats: TELFGeometry;

  procedure Add(B: Byte);
  begin
    if Length(Machine)>=MaxMachineBytes then
      raise EIRCondError.Create('Перевищено host-ліміт машинного коду');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure EmitWriteAndExit(Value: Byte);
  begin
    Add($B3);Add(Value);             { mov bl, canonical T5M byte }
    Add($48);Add($83);Add($EC);Add(8); { sub rsp,8 }
    Add($88);Add($1C);Add($24);     { mov [rsp],bl }
    Add($B8);Add(1);Add(0);Add(0);Add(0); { write }
    Add($BF);Add(1);Add(0);Add(0);Add(0); { stdout }
    Add($48);Add($89);Add($E6);     { rsi=rsp }
    Add($BA);Add(1);Add(0);Add(0);Add(0); { 1 physical byte }
    Add($0F);Add($05);             { syscall }
    Add($B8);Add($3C);Add(0);Add(0);Add(0); { exit }
    Add($31);Add($FF);Add($0F);Add($05);
  end;

  procedure PutLE(Offset: SizeInt; Value: QWord; Width: SizeInt);
  var K: SizeInt;
  begin
    Require((Offset>=0) and (Width>=1) and (Width<=8) and
            (Offset<=Length(Result)-Width), 'Поле ELF поза образом');
    for K:=0 to Width-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  Require(Lowered.Count<=2, 'Знижена умова перевищила 2 гілки');
  SetLength(Words,1);
  Words[0]:='0'; ZeroByte:=EncodeT5M(Words);
  Words[0]:='1'; OneByte:=EncodeT5M(Words);
  Words[0]:='000'; EmptyByte:=EncodeT5M(Words);
  Require((Length(ZeroByte)=1) and (Length(OneByte)=1) and
          (Length(EmptyByte)=1) and
          (ZeroByte<>OneByte) and (ZeroByte<>EmptyByte) and
          (OneByte<>EmptyByte),
    'Три точні SENS відповіді не мають різних канонічних T5M байтів');
  Machine:='';
  for I:=0 to Lowered.Count-1 do begin
    Require((Lowered.Clauses[I].TestBit<=1) and
            (Lowered.Clauses[I].ExpressionBit<=1),
      'Host-біт умови перестав бути D1');
    Add($B8); Add(Lowered.Clauses[I].TestBit); Add(0); Add(0); Add(0);
    Add($83);Add($F8);Add(1);       { cmp eax, exact D1:1 }
    Add($75); SkipAt:=Length(Machine)+1; Add(0); { jne next clause }
    From:=Length(Machine);
    if Lowered.Clauses[I].ExpressionBit=0 then
      EmitWriteAndExit(Byte(ZeroByte[1]))
    else
      EmitWriteAndExit(Byte(OneByte[1]));
    Require(Length(Machine)-From<=127,
      'Машинний відносний перехід поза rel8');
    Machine[SkipAt]:=AnsiChar(Length(Machine)-From);
  end;
  { Вичерпання гілок є точною D3:000, ніколи D1:0. }
  EmitWriteAndExit(Byte(EmptyByte[1]));
  Total:=ELFHeaderBytes+Length(Machine);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(0,$464C457F,4);          { ELF64 little endian }
  PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
  PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4); { ET_DYN/AMD64 }
  PutLE(24,ELFHeaderBytes,8);PutLE(32,64,8);
  PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
  PutLE(64,1,4);PutLE(68,5,4); { PT_LOAD RX }
  PutLE(80,0,8);PutLE(88,0,8);
  PutLE(96,Total,8);PutLE(104,Total,8);PutLE(112,$1000,8);
  for J:=1 to Length(Machine) do Result[ELFHeaderBytes+J]:=Machine[J];
  VerifySENSELF64(Result,ImageStats);
  Require((ImageStats.Kind=3) and (ImageStats.MachineBytes=Length(Machine)),
    'Породжений PIE не пройшов незалежну ELF64-геометрію');
end;

function BuildPinnedIRCondELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;
var Lowered:TLoweredIRCond;
begin
  Result:='';
  try
    LowerPinnedIRCond(Physical,AuthorityRoot,Lowered);
    Result:=EmitLoweredIRCond(Lowered);
  except
    Result:='';
    raise;
  end;
end;

{ Пам'ять: Physical borrowed RawByteString не змінюється; таблиці та
  ExactIR — локальні FPC керовані масиви; зниження — фіксований stack
  record, без heap і текстового проміжного коду. ELF — owned byte string.
  Машинний стек виділяє 8 байтів і завершує процес без runtime/GC.
  Питання: 1) Чому D3:000 не є D1:0?
  2) Чому JNE виконується машинно, а не Pascal?
  3) Чому ключ D7 не можна прийняти як предикат?
  4) Чому ET_DYN/PIE не визначає закон SENS?
  5) Чому stdout не містить людський текст чи LF? }
end.
