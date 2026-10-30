{ G6.57 — фізичний ExactIR -> двочастинний D3:110 -> виконуваний
  ELF64 PIE. Підмножина: 0..32 гілки: D1 або D3:101(D1,D1)
  у кожному тесті та виразі; тільки pinned SENS вирішує закон.
  Один машинний вихід замість дублювання write/exit для кожної гілки.
  SENS Contract 12 K12.3 — єдиний закон; це механізм, не нова семантика. }
unit wsm.ircond;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  EIRCondError = class(Exception);
  { Host-знижені регістрові біти; фізичні індекси — provenance.
    Ні чисел D12+, ні людських назв або SENS opcode в цьому record. }
  TIRCondValue = record
    { 0 = exact D1; 1 = exact D3:101(D1,D1). Лише механічний IR kind. }
    Kind, LeftBit, RightBit: Byte;
    SourceWord: SizeInt;
  end;
  TIRCondClause = record
    TestValue, ExpressionValue: TIRCondValue;
  end;
  TLoweredIRCond = record
    Count: Byte;
    HeadWord: SizeInt;
    Clauses: array[0..31] of TIRCondClause;
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
  MaxClauses = 32; { host-бюджет, не мовний Dn-закон }
  MaxMachineBytes = 2048; { bounded ET_DYN машинний образ }

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
  Count, Cursor, Anchor, BoundCount: SizeInt;

  function AdmitD1(Index, Parent, Child: SizeInt): Byte;
  begin
    Require((Index>=0) and (Index<Length(IR.Nodes)),
      'Відсутній точний D1-вузол IR');
    Require((IR.Nodes[Index].Kind=ikIdentity) and
            IR.Nodes[Index].HasKey and
            (IR.Nodes[Index].ParentIndex=Parent) and
            (IR.Nodes[Index].ChildIndex=Child) and
            (IR.Nodes[Index].SubtreeEndExclusive=Index+1) and
            (IR.Nodes[Index].Key.Width=1) and
            (IR.Nodes[Index].Key.Bits<=1),
      'D3-умова потребує точного D1, не D7/D12/D3:000');
    Result:=Byte(IR.Nodes[Index].Key.Bits);
  end;

  { Вузький, без рекурсії, direct ExactIR admission. Повертає перший
    індекс після піддерева. Provenance перевірено BuildExactIR+guard,
    тут структурно допускаємо тільки D1 або D3:101(D1,D1). }
  function AdmitValue(Index, Parent, Child: SizeInt;
    out Value: TIRCondValue): SizeInt;
  begin
    FillChar(Value,SizeOf(Value),0);
    Require((Index>=0) and (Index<Length(IR.Nodes)),
      'Відсутнє значення гілки ExactIR');
    Require((IR.Nodes[Index].ParentIndex=Parent) and
            (IR.Nodes[Index].ChildIndex=Child),
      'Порушено батька/порядок ExactIR значення');
    Value.SourceWord:=IR.Nodes[Index].WordIndex;
    if IR.Nodes[Index].Kind=ikIdentity then begin
      Value.Kind:=0;
      Value.LeftBit:=AdmitD1(Index,Parent,Child);
      Result:=Index+1;
    end else begin
      Require((IR.Nodes[Index].Kind=ikList) and
              (Index<=Length(IR.Nodes)-4) and
              (IR.Nodes[Index].SubtreeEndExclusive=Index+4),
        'Вкладене значення має бути списком рівно з трьох фізичних слів');
      Require((IR.Nodes[Index+1].Kind=ikIdentity) and
              IR.Nodes[Index+1].HasKey and
              (IR.Nodes[Index+1].ParentIndex=Index) and
              (IR.Nodes[Index+1].ChildIndex=0) and
              (IR.Nodes[Index+1].SubtreeEndExclusive=Index+2) and
              SameKey(IR.Nodes[Index+1].Key,ExactKey('101')),
        'Вкладений виклик має точну pinned D3:101 голову');
      Value.Kind:=1;
      Value.LeftBit:=AdmitD1(Index+2,Index,1);
      Value.RightBit:=AdmitD1(Index+3,Index,2);
      Result:=Index+4;
    end;
  end;
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
  Count:=0;Cursor:=2;BoundCount:=1; { перша фізична голова D3:110 }
  while Cursor<Length(IR.Nodes) do begin
    Require(Count<MaxClauses,
      'Цей машинний зріз допускає лише 0..32 двочастинні гілки');
    Anchor:=Cursor;
    Require((IR.Nodes[Anchor].Kind=ikList) and
            (IR.Nodes[Anchor].ParentIndex=0) and
            (IR.Nodes[Anchor].ChildIndex=Count+1) and
            (IR.Nodes[Anchor].SubtreeEndExclusive>Anchor+1),
      'Гілка D3:110 мусить бути точним двочастинним D2-списком');
    Cursor:=AdmitValue(Anchor+1,Anchor,0,
      Candidate.Clauses[Count].TestValue);
    if Candidate.Clauses[Count].TestValue.Kind=0 then Inc(BoundCount)
    else Inc(BoundCount,3);
    Cursor:=AdmitValue(Cursor,Anchor,1,
      Candidate.Clauses[Count].ExpressionValue);
    if Candidate.Clauses[Count].ExpressionValue.Kind=0 then Inc(BoundCount)
    else Inc(BoundCount,3);
    Require(Cursor=IR.Nodes[Anchor].SubtreeEndExclusive,
      'Гілка D3:110 має зайве третє поле або зламані ExactIR межі');
    Inc(Count);
  end;
  Require((Cursor=Length(IR.Nodes)) and (IR.BoundLeaves=BoundCount),
    'Умовна форма має зайві або загублені точні доменні слова');
  Candidate.Count:=Byte(Count);
  Candidate.HeadWord:=IR.Nodes[1].WordIndex;
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
  I, J, Total, TailStart, Delta, SkipAt: SizeInt;
  JumpPatchAt: array[0..31] of SizeInt;
  ImageStats: TELFGeometry;

  procedure Add(B: Byte);
  begin
    if Length(Machine)>=MaxMachineBytes then
      raise EIRCondError.Create('Перевищено host-ліміт машинного коду');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure EmitWriteAndExit;
  begin
    { BL уже містить точний pinned T5M байт із вибраної гілки. }
    Add($48);Add($83);Add($EC);Add(8); { sub rsp,8 }
    Add($88);Add($1C);Add($24);     { mov [rsp],bl }
    Add($B8);Add(1);Add(0);Add(0);Add(0); { write }
    Add($BF);Add(1);Add(0);Add(0);Add(0); { stdout }
    Add($48);Add($89);Add($E6);     { rsi=rsp }
    Add($BA);Add(1);Add(0);Add(0);Add(0); { 1 physical byte }
    Add($0F);Add($05);             { Linux sys_write(1,rsp,1) }
    { G6.267 — фізичний T5M-байт прийнятий лише якщо ядро
      підтвердило РІВНО 1 записаний байт. Host RDX=1 зберігається
      через syscall, RAX=-errno/0/1 є кількістю, не D1 значенням.
      cmp rax,rdx; jne +9 пропускає exit(0) лише за невдачі.
      Немає часткового успіху у згенерованому native ELF.
      1) Чому RAX=1 необхідний для успішного фізичного stdout?
      2) Чому host errno не можна сприйняти як SENS D12?
      3) Чому +9 пропускає точно три інструкції exit(0)?
      4) Де незалежно перевірити це на /dev/full і закритому fd? }
    Add($48);Add($39);Add($D0);     { cmp rax,rdx }
    Add($75);Add($09);              { jne exit(2) }
    Add($B8);Add($3C);Add(0);Add(0);Add(0); { exit(0) }
    Add($31);Add($FF);Add($0F);Add($05);
    Add($B8);Add($3C);Add(0);Add(0);Add(0); { exit(2) }
    Add($BF);Add(2);Add(0);Add(0);Add(0);
    Add($0F);Add($05);
  end;

  procedure EmitValueEAX(const Value: TIRCondValue);
  begin
    Require((Value.Kind<=1) and (Value.LeftBit<=1) and
            (Value.RightBit<=1),
      'Неприпустиме знижене D1/EQ значення для машини');
    Add($B8);Add(Value.LeftBit);Add(0);Add(0);Add(0); { mov eax,left }
    if Value.Kind=1 then begin
      Add($B9);Add(Value.RightBit);Add(0);Add(0);Add(0); { mov ecx,right }
      Add($39);Add($C8);              { cmp eax,ecx }
      Add($0F);Add($94);Add($C0);    { sete al }
      Add($0F);Add($B6);Add($C0);    { movzx eax,al }
    end;
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
  Require(Lowered.Count<=MaxClauses, 'Знижена умова перевищила 32 гілки');
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
    { D3:101 обчислює x86-64 лише під час виконання ELF, не Pascal.
      Згідно з pinned machine-domain-profile: CMP/SETE. }
    EmitValueEAX(Lowered.Clauses[I].TestValue);
    Add($83);Add($F8);Add(1);      { cmp eax, exact D1:1 }
    Add($75);SkipAt:=Length(Machine)+1;Add(0); { jne next clause }
    if Lowered.Clauses[I].ExpressionValue.Kind=0 then begin
      Add($B3);
      if Lowered.Clauses[I].ExpressionValue.LeftBit=0 then
        Add(Byte(ZeroByte[1]))
      else
        Add(Byte(OneByte[1]));
    end else begin
      EmitValueEAX(Lowered.Clauses[I].ExpressionValue);
      { Результат EAX=D1:0/1; тільки машинний bit вибирає T5M. }
      Add($B3);Add(Byte(ZeroByte[1])); { mov bl, exact D1:0 }
      Add($85);Add($C0);           { test eax,eax }
      Add($74);Add(2);             { je пропустити mov bl,one }
      Add($B3);Add(Byte(OneByte[1]));
    end;
    Add($E9);                      { jmp rel32 до спільного write/exit }
    JumpPatchAt[I]:=Length(Machine)+1;
    for J:=0 to 3 do Add(0);
    Require(Length(Machine)-SkipAt<=127,
      'Поза rel8 межами пропуск машинного виразу D3:110');
    Machine[SkipAt]:=AnsiChar(Length(Machine)-SkipAt);
  end;
  { Лише якщо жоден тест не D1:1 — структурна D3:000, не D1:0. }
  Add($B3); Add(Byte(EmptyByte[1]));
  TailStart:=Length(Machine);      { 0-based початок спільного epilogue }
  for I:=0 to Lowered.Count-1 do begin
    { Кінець rel32 поля має 0-based адресу JumpPatchAt+3.
      Зміщення рахуємо саме від адреси наступної інструкції. }
    Delta:=TailStart-(JumpPatchAt[I]+3);
    Require((Delta>=0) and (Delta<=MaxMachineBytes),
      'Машинний перехід до спільного виходу поза host-бюджетом');
    for J:=0 to 3 do
      Machine[JumpPatchAt[I]+J]:=
        AnsiChar(Byte((DWord(Delta) shr (8*J)) and $FF));
  end;
  EmitWriteAndExit;
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
  Машинний стек виділяє 8 байтів один раз у спільному виході;
  0..32 гілки — лише локальна ресурсна межа, не закон мови.
  База: 17 байтів/гілку + 55 спільного перевіреного виходу; EQ додає
  13 байтів у тесті або 24 у виразі. Не виконувати EQ-expression,
  доки D1-тест не вибрав його; відмова не залишає часткового ELF.
  Питання: 1) Чому D3:000 не є D1:0?
  2) Чому EQ у тесті та вибраному виразі обчислюється x86-64?
  3) Чому ключ D7 не можна прийняти як предикат?
  4) Чому ET_DYN/PIE не визначає закон SENS?
  5) Чому rel32 патч рахується від наступної інструкції JMP? }
end.
