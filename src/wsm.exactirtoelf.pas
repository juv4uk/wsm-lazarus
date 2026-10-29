{ G6.30 — спільний перевірений ExactIR для двох фізичних D3 backend.
  Тільки pinned SENS вирішує закон; тут — provenance і backend admission.
  D3:001 друкує незмінну цитату, D3:010 ВИКОНУЄ atom? на x86-64.
  Жодних локальних Lisp-законів, назв у dispatch або D12 арифметики. }
unit wsm.exactirtoelf;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.exactir;
type EVerifiedIRELFError=class(Exception);
function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
function BuildVerifiedAtomIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
function BuildVerifiedEqIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
function BuildVerifiedCondIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
function BuildVerifiedSelectorIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactirguard,
  wsm.elfquotet5m,wsm.elfatomt5m,wsm.elfcondt5m,
  wsm.elfselectort5m;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EVerifiedIRELFError.Create(Why);
end;

function SameNode(const A,B:TExactIRNode):Boolean;
begin
  { Не порівнюємо сирі record/padding. Точне походження до трита. }
  Result:=(A.Kind=B.Kind) and
    (A.RootIndex=B.RootIndex) and
    (A.ParentIndex=B.ParentIndex) and
    (A.ChildIndex=B.ChildIndex) and
    (A.Depth=B.Depth) and
    { ExactIR G6.45/G6.46: піввідкрита межа preorder теж
      належить перевіреному фізичному походженню. Окремий guard
      перевіряє її структурно; тут звіряємо з оригінальним T5M. }
    (A.SubtreeEndExclusive=B.SubtreeEndExclusive) and
    (A.WordIndex=B.WordIndex) and
    (A.HasKey=B.HasKey) and
    (A.Key.Width=B.Key.Width) and
    (A.Key.Bits=B.Key.Bits) and
    (A.Physical.WordIndex=B.Physical.WordIndex) and
    (A.Physical.TritStart=B.Physical.TritStart) and
    (A.Physical.TritEnd=B.Physical.TritEnd) and
    (A.Physical.ByteStart=B.Physical.ByteStart) and
    (A.Physical.ByteEnd=B.Physical.ByteEnd) and
    (A.Physical.IsEOF=B.Physical.IsEOF);
end;

{ Спільний довірений місток: не інтерпретує SENS і не створює IR
  з тексту. Вхід CandidateIR borrowed, ActualIR — власні FPC-managed
  масиви з незалежно зчитаних фізичних байтів; 64KiB — host-квота. }
procedure VerifyPhysicalExactIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR;out ActualIR:TExactIR);
var
  Tables:TDomainSet;
  CandidateStats,ActualStats:TExactIRGuardStats;
  I:SizeInt;
begin
  SetLength(ActualIR.Nodes,0);SetLength(ActualIR.Roots,0);
  ActualIR.BoundLeaves:=0;
  Require((Length(Physical)>=1) and (Length(Physical)<=65536),
    'Фізичне джерело поза host-межею');
  VerifyExactIRStructure(CandidateIR,CandidateStats);
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildExactIR(Physical,Tables,ActualIR);
  VerifyExactIRStructure(ActualIR,ActualStats);
  Require((Length(CandidateIR.Roots)=Length(ActualIR.Roots)) and
    (Length(CandidateIR.Nodes)=Length(ActualIR.Nodes)) and
    (CandidateIR.BoundLeaves=ActualIR.BoundLeaves),
    'Зовнішній IR не відповідає фізичному джерелу');
  Require((CandidateStats.Nodes=ActualStats.Nodes) and
    (CandidateStats.Roots=ActualStats.Roots) and
    (CandidateStats.BoundLeaves=ActualStats.BoundLeaves) and
    (CandidateStats.StructuralNodes=ActualStats.StructuralNodes) and
    (CandidateStats.MaxDepth=ActualStats.MaxDepth),
    'Статистика IR відрізняється від фізичного джерела');
  for I:=0 to High(ActualIR.Roots) do
    Require(CandidateIR.Roots[I]=ActualIR.Roots[I],
      'Підмінено фізичний покажчик кореня');
  for I:=0 to High(ActualIR.Nodes) do
    Require(SameNode(CandidateIR.Nodes[I],ActualIR.Nodes[I]),
      'Підмінено точне слово або фізичну адресу IR вузла '+IntToStr(I));
end;

{ Перевірка точного машинного входу: виключно один D2-список,
  фізична голова pinned D3 з рівно вказаними бітами. Не замінює
  повну перевірку арності/викличності в кожному чинному emitter. }
procedure RequireD3Head(const ActualIR:TExactIR;const ExactBits:RawByteString;
  AllowEmpty:Boolean=False);
begin
  Require((Length(ActualIR.Roots)=1) and
    ((Length(ActualIR.Nodes)>=3) or
     (AllowEmpty and (Length(ActualIR.Nodes)=2))),
    'Очікується одна фізична D3-форма');
  Require((ActualIR.Roots[0]=0) and
    (ActualIR.Nodes[0].Kind=ikList) and
    (ActualIR.Nodes[1].Kind=ikIdentity) and
    ActualIR.Nodes[1].HasKey and
    (ActualIR.Nodes[1].ParentIndex=0) and
    (ActualIR.Nodes[1].ChildIndex=0) and
    (ActualIR.Nodes[1].Key.Width=3) and
    (KeyBits(ActualIR.Nodes[1].Key)=ExactBits) and
    ((AllowEmpty and (Length(ActualIR.Nodes)=2)) or
     ((Length(ActualIR.Nodes)>=3) and
      (ActualIR.Nodes[2].ParentIndex=0) and
      (ActualIR.Nodes[2].ChildIndex=1))),
    'Непідтримана точна D3 голова');
end;

{ G6.59 — прямий host-emission D3:001 після ПОВНОЇ pinned IR перевірки.
  Викликається ЛИШЕ із BuildVerifiedQuoteIR для рівно одного атома
  D1 або D7. Key — підтверджені точні width,bits, не назва поверхні.
  Літерал SENS не обчислюється Pascal: цитований атом тотожний самому
  точному фізичному слову. D7 SYN тут тільки opaque дані.
  Машинний вихід: Linux ET_DYN ELF64 із RIP-відносним записом
  канонічних байтів, без runtime/heap/relocation та ASCII транзиту.
  Key — borrowed value, Words/Code/Literal локальні FPC-managed,
  результат — власний RawByteString ELF, на відмову нічого. }
function EmitVerifiedAtomicQuoteELF(const Key:TDomainKey):RawByteString;
const HeaderBytes=120; CodeBytes=33; MaxLiteralBytes=4096;
var
  Words,RoundTrip:TExactWords;
  Literal,Code,Bits:RawByteString;
  Total,DataOffset,Displacement,I:SizeInt;

  procedure PutLE(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset<=Length(Result)-Count),'Пошкоджені межі ELF64 цитати');
    for J:=0 to Count-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  Require((Key.Width=1) or (Key.Width=7),
    'Пряме цитування підтримує тільки точний D1 або D7 атом');
  Bits:=KeyBits(Key);
  Require(Length(Bits)=Key.Width,'Цитата втратила точну ширину домену');
  for I:=1 to Length(Bits) do
    Require((Bits[I]='0') or (Bits[I]='1'),
      'Цитата містить не двійкове слово');
  SetLength(Words,1);
  Words[0]:=Bits;
  Literal:=EncodeT5M(Words);
  Require((Length(Literal)>=1) and (Length(Literal)<=MaxLiteralBytes),
    'Цитований фізичний літерал поза host-межею');
  DecodeT5M(Literal,RoundTrip);
  Require((Length(RoundTrip)=1) and (RoundTrip[0]=Bits) and
    (EncodeT5M(RoundTrip)=Literal),
    'Цитований фізичний літерал не канонічний');
  { Той самий перевірений безадресний x86-64 writer, що у
    wsm.elfquotet5m, але тут він споживає ЛИШЕ допущений IR key.
    mov eax,1; mov edi,1; lea rsi,[rip+16]; mov edx,len;
    syscall write(1,literal,len); exit(0). }
  Code:=#$B8#$01#0#0#0+#$BF#$01#0#0#0+
    #$48#$8D#$35#0#0#0#0+#$BA#0#0#0#0+
    #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF+#$0F#$05;
  Require(Length(Code)=CodeBytes,'Змінився машинний writer цитати');
  DataOffset:=HeaderBytes+Length(Code);
  Displacement:=DataOffset-(HeaderBytes+17);
  Require((Displacement>=0) and (Displacement<=High(LongInt)),
    'Неправильне RIP-відносне зміщення літерала');
  Total:=DataOffset+Length(Literal);
  Require(Total<=HeaderBytes+CodeBytes+MaxLiteralBytes,
    'ELF цитати перевищив host-ліміт');
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(0,$464C457F,4);PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
  PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4);
  PutLE(24,HeaderBytes,8);PutLE(32,64,8);
  PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
  PutLE(64,1,4);PutLE(68,5,4);
  PutLE(80,0,8);PutLE(88,0,8);
  PutLE(96,QWord(Total),8);PutLE(104,QWord(Total),8);PutLE(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  PutLE(HeaderBytes+13,QWord(Displacement),4);
  PutLE(HeaderBytes+18,QWord(Length(Literal)),4);
  for I:=1 to Length(Literal) do Result[DataOffset+I]:=Literal[I];
end;
{ Ревізія:
  1) Чому цитування D7 SYN не перетворює SYN на викличний знак?
  2) Чому ExactIR key не можна брати до VerifyPhysicalExactIR?
  3) Які машинні інструкції пишуть T5M під час виконання?
  4) Чому D12 не допускається за аналогією лише з його Wn?
  5) Кому належать локальні FPC масиви і вихідний ELF64? }

function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'001');
    { Перевірений фізичний D3:001 з ОДНИМ атомом D1/D7:
      без другого T5M/D2/semantic evaluator в machine emitter.
      Складні цитати, D3:000, D9 і структури — старий перевірений
      emitter з попереднім повним admission, без зміни їхніх законів. }
    if (Length(ActualIR.Nodes)=3) and
       (ActualIR.BoundLeaves=2) and
       (ActualIR.Nodes[2].Kind=ikIdentity) and
       ActualIR.Nodes[2].HasKey and
       (ActualIR.Nodes[2].ParentIndex=0) and
       (ActualIR.Nodes[2].ChildIndex=1) and
       (ActualIR.Nodes[2].SubtreeEndExclusive=3) and
       ((ActualIR.Nodes[2].Key.Width=1) or
        (ActualIR.Nodes[2].Key.Width=7)) then
      Result:=EmitVerifiedAtomicQuoteELF(ActualIR.Nodes[2].Key)
    else
      Result:=BuildQuoteT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

{ G6.64: verified pinned ExactIR -> machine ATOM only for D1:0/1.
  Key is borrowed exact W1; Result is owned managed binary ELF64 ET_EXEC.
  VerifiedPhysicalExactIR checked the original T5M and provenance first.
  Reproduces existing BuildAtomT5MELF machine bytes: machine AND/CMP/
  SETNE/MOVZX computes the predicate, not Pascal Boolean.
  Questions: why no second reader? why is W1 not D12?
  who owns Result? where does runtime computation occur?
  why must ELF64 byte identity with the old emitter be checked? }
function EmitVerifiedD1AtomELF(const Key:TDomainKey):RawByteString;
const HeaderBytes=120; ELFBase:QWord=$400000;
var Bits,Zero,One,Machine:RawByteString;
    Words:TExactWords;
    Tag,Delta:Byte;
    I,Total:SizeInt;
  procedure PutLE(Offset:SizeInt;Value:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Width>=1) and (Width<=8) and
      (Offset<=Length(Result)-Width),'Прямий ATOM: ELF за межею');
    for J:=0 to Width-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  Require(Key.Width=1,'Прямий ATOM потребує тільки точний D1');
  Bits:=KeyBits(Key);
  if Bits='0' then Tag:=1
  else if Bits='1' then Tag:=2
  else raise EVerifiedIRELFError.Create('Непідтримана фізична D1 координата');
  SetLength(Words,1);
  Words[0]:='0';Zero:=EncodeT5M(Words);
  Words[0]:='1';One:=EncodeT5M(Words);
  Require((Length(Zero)=1) and (Length(One)=1) and
    (Ord(One[1])>Ord(Zero[1])) and
    (Ord(One[1])-Ord(Zero[1])<=127),'Змінено T5M D1 transport');
  Delta:=Byte(Ord(One[1])-Ord(Zero[1]));
  { Старий ABI: 2048-byte stack arena, D1 tagged=1/2,
    runtime tag!=3, фізичний одно-байтовий T5M output. }
  Machine:=
    #$48#$81#$EC#$00#$08#$00#$00+
    #$49#$89#$E4+
    #$B8+AnsiChar(Tag)+#0#0#0+
    #$83#$E0#$03+
    #$83#$F8#$03+
    #$0F#$95#$C0+
    #$0F#$B6#$C0+
    #$83#$C0#$01+
    #$83#$E8#$01+
    #$6B#$C0+AnsiChar(Delta)+#$04+Zero[1]+
    #$48#$83#$EC#$08+#$88#$04#$24+
    #$B8#$01#0#0#0+#$BF#$01#0#0#0+
    #$48#$89#$E6+#$BA#$01#0#0#0+
    #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF+#$0F#$05;
  Require((Length(Machine)>40) and (Length(Machine)<2048),
    'Прямий машинний ATOM поза бюджетом');
  Total:=HeaderBytes+Length(Machine);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(0,$464C457F,4);
  PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
  PutLE(16,2,2);PutLE(18,62,2);PutLE(20,1,4);
  PutLE(24,ELFBase+HeaderBytes,8);PutLE(32,64,8);
  PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
  PutLE(64,1,4);PutLE(68,5,4);
  PutLE(80,ELFBase,8);PutLE(88,ELFBase,8);
  PutLE(96,QWord(Total),8);PutLE(104,QWord(Total),8);
  PutLE(112,$1000,8);
  for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
end;

function BuildVerifiedAtomIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'010');
    { Existing BuildAtomT5MELF -> BuildAtomELF відповідає
      за повну викличність/арність і машинні AND/CMP/SETNE/MOVZX;
      у нас НЕМАЄ host constant-fold значення D1:0/1. }
    { ExactIR D1 має прямий машинний lowering без другого T5M/D2
      reader, binder та FPC evaluator. Інші форми — старий emitter. }
    if (Length(ActualIR.Nodes)=3) and
       (ActualIR.BoundLeaves=2) and
       (ActualIR.Nodes[2].Kind=ikIdentity) and
       ActualIR.Nodes[2].HasKey and
       (ActualIR.Nodes[2].ParentIndex=0) and
       (ActualIR.Nodes[2].ChildIndex=1) and
       (ActualIR.Nodes[2].SubtreeEndExclusive=3) and
       (ActualIR.Nodes[2].Key.Width=1) then
      Result:=EmitVerifiedD1AtomELF(ActualIR.Nodes[2].Key)
    else
      Result:=BuildAtomT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;


{ G6.53 — вперше lowering від verified ExactIR D1-операндів прямо в ELF.
  Це тільки host-механізм машинної рівності для ВЖЕ допущеного
  pinned D3:101, не таблиця законів, не D12 арифметика й не новий eval.
  Вхідні TDomainKey походять з щойно перебудованого Physical ExactIR;
  тут НЕ існує нового T5M/D2 reader, binder чи виклику старого emitter.
  Ідентичність D1 (ширина, точний біт) не зводиться до Pascal Boolean.
  Повертається owned ELF64 ET_DYN у RawByteString. Емітований код має
  лише регістрові D1 imm32, 8-байтовий тимчасовий стек і Linux syscalls;
  жодного heap, GC, relocation, FPC runtime або зовнішніх вказівників. }
function EmitVerifiedD1EqELF(const LeftKey,RightKey:TDomainKey):RawByteString;
const HeaderBytes=120; MaxMachineBytes=128;
var
  LeftBit,RightBit,Delta:Byte;
  Zero,One,Machine:RawByteString;
  Words:TExactWords;
  Total,I:SizeInt;

  function D1Immediate(const Key:TDomainKey):Byte;
  var B:RawByteString;
  begin
    Require(Key.Width=1,'Машинна рівність потребує точної D1 координати');
    B:=KeyBits(Key);
    if B='0' then Exit(0);
    if B='1' then Exit(1);
    raise EVerifiedIRELFError.Create('Непідтримане D1 слово для машини');
  end;

  procedure PutLE(Offset:SizeInt; Value:QWord; Count:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset<=Length(Result)-Count),'Вихід за межі ELF64');
    for J:=0 to Count-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  LeftBit:=D1Immediate(LeftKey);
  RightBit:=D1Immediate(RightKey);
  { D1 T5M — тільки pinned фізичний codec, не ASCII/host bool. }
  SetLength(Words,1);
  Words[0]:='0'; Zero:=EncodeT5M(Words);
  Words[0]:='1'; One:=EncodeT5M(Words);
  Require((Length(Zero)=1) and (Length(One)=1),
    'Змінено довжину фізичного D1 T5M');
  Require((Ord(Zero[1])<=127) and (Ord(One[1])>Ord(Zero[1])) and
    (Ord(One[1])-Ord(Zero[1])<=127),
    'Змінено підтверджену фізичну D1 проєкцію');
  Delta:=Ord(One[1])-Ord(Zero[1]);
  { x86-64: MOV EAX,лівий; MOV ECX,правий; CMP/SETE/MOVZX обчислює
    результат ПІД ЧАС виконання. IMUL переводить D1 0/1 у codec
    різницю канонічних T5M байтів. Linux write(1,rsp,1), exit(0).
    Жодного precomputed EQ outcome чи повторного парсингу source. }
  Machine:=
    #$B8+AnsiChar(LeftBit)+#0#0#0+
    #$B9+AnsiChar(RightBit)+#0#0#0+
    #$39#$C8#$0F#$94#$C0#$0F#$B6#$C0+
    #$6B#$C0+AnsiChar(Delta)+
    #$83#$C0+Zero[1]+
    #$48#$83#$EC#$08+#$88#$04#$24+
    #$B8#$01#0#0#0+#$BF#$01#0#0#0+
    #$48#$89#$E6+#$BA#$01#0#0#0+
    #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF#$0F#$05;
  Require((Length(Machine)>=40) and
    (Length(Machine)<=MaxMachineBytes),
    'Машинний D1 EQ поза межею коду');
  Total:=HeaderBytes+Length(Machine);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  { ELF64 ET_DYN / AMD64 / один RX PT_LOAD без relocation.
    Поля host контейнера — НЕ SENS Dn і не семантичний opcode. }
  PutLE(0,$464C457F,4);
  PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
  PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4);
  PutLE(24,HeaderBytes,8);PutLE(32,64,8);
  PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
  PutLE(64,1,4);PutLE(68,5,4);
  PutLE(80,0,8);PutLE(88,0,8);
  PutLE(96,QWord(Total),8);PutLE(104,QWord(Total),8);PutLE(112,$1000,8);
  for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
end;
{ Самоперевірка:
  1. Чому KeyBits не є виконуваною мовною таблицею законів?
  2. Де machine CMP/SETE реально обчислює результат, а не FPC?
  3. Чому два T5M байти отримані через EncodeT5M?
  4. Чому дозвіл на ELF не означає дозвіл на довільний D3/ D12?
  5. Хто володіє IR, ELF та 8 машинними байтами у стеку? }

{ G6.32 — перевірка physical provenance тепер веде до прямого G6.53
  D3:101 lowering, без повторного T5M/D2 parse в backend. }
function BuildVerifiedEqIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'101');
    Require(Length(ActualIR.Nodes)=4,
      'Потрібна фізична форма D3:101 з двома D1');
    Require((ActualIR.Nodes[2].Kind=ikIdentity) and
      ActualIR.Nodes[2].HasKey and
      (ActualIR.Nodes[2].ParentIndex=0) and
      (ActualIR.Nodes[2].ChildIndex=1) and
      (ActualIR.Nodes[2].Key.Width=1) and
      (ActualIR.Nodes[3].Kind=ikIdentity) and
      ActualIR.Nodes[3].HasKey and
      (ActualIR.Nodes[3].ParentIndex=0) and
      (ActualIR.Nodes[3].ChildIndex=2) and
      (ActualIR.Nodes[3].Key.Width=1),
      'Точна D3:101 підтримує лише два D1');
    { Verified ExactIR — ЄДИНЕ джерело операндів машинного емітера.
      Старий BuildEqT5MELF лишається лише незалежним test-baseline. }
    Result:=EmitVerifiedD1EqELF(ActualIR.Nodes[2].Key,ActualIR.Nodes[3].Key);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

{ G6.37 — верифікований фізичний D3:110 → реальні ELF64 CMP/JNE.
  Порожня умовна форма законно не має третього IR-вузла; тільки
  тут дозволяємо рівно два вузли (корінь D2 та точна D3 голова).
  Усі інші форми/арності остаточно допускає ВЖЕ наявний emitter. }
function BuildVerifiedCondIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'110',True);
    { Власної семантики умов у цьому містку немає: фізичні байти
      без змін проходять існуючий pinned BuildCondT5MELF. }
    Result:=BuildCondT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

{ G6.39 — довірений ExactIR → справжній машинний селектор D3:100/011.
  Borrowed CandidateIR не є авторитетом: його по полях перевіряють
  проти новозбудованого фізичного дерева canonical .sens, а вже наявний
  emitter сам допускає форму CONS/D1, генерує і виконує машинний вибір.
  Це не універсальний компілятор, диспетчер за проєкціями чи закон. }
function BuildVerifiedSelectorIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var
  ActualIR:TExactIR;
  Bits:RawByteString;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    Require((Length(ActualIR.Roots)=1) and
      (Length(ActualIR.Nodes)>=3),
      'Очікується одна фізична D3-форма селектора');
    Require(ActualIR.Nodes[1].HasKey and
      (ActualIR.Nodes[1].Key.Width=3),
      'Селектор потребує точної голови D3');
    Bits:=KeyBits(ActualIR.Nodes[1].Key);
    if Bits='100' then RequireD3Head(ActualIR,'100')
    else RequireD3Head(ActualIR,'011');
    { Жодних нових операцій над парою тут немає: точні двійкові
      байти, D2-рамку, D1-поля і викличність остаточно перевіряє
      чинний BuildSelectorT5MELF. Його ELF містить пам'ять CONS. }
    Result:=BuildSelectorT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR селектора відхилено: '+E.Message);
    end;
  end;
end;

{ Контракт: Physical — позичені канонічні паковані T5M байти,
  AuthorityRoot — позичений pinned каталог, CandidateIR — позичений
  exact-domain граф зі spans. ActualIR — локальний FPC-managed граф,
  Bits — локальне бітове слово W3. На успіх новий owned RawByteString
  ELF64 ET_DYN, на помилку EVerifiedIRELFError без часткового ELF.
  Запитання:
  1) Чому з IR не можна без перевірки читати аргументи селектора?
  2) Чому тільки D3:100 та D3:011, а не будь-яке W3?
  3) Де фактично виділяється машинна пара з двох QWord?
  4) Чому D7 SYN не є викличною головою?
  5) Чому успішний ELF не доводить весь Core4? }

{ Контракт: Physical — borrowed canonical packed .sens T5M,
  AuthorityRoot — pinned каталог; CandidateIR borrowed з точними D2
  word/trit/byte spans. ActualIR — локальна FPC-managed пам’ять.
  Результат — новий owned RawByteString ELF64 із машинним D3:110;
  у разі відмови виняток і порожній результат, без часткового ELF.
  Запитання:
  1) Чому порожній D3:110 має рівно два IR-вузли?
  2) Чому borrowed IR перевіряється проти первинних T5M-байтів?
  3) Чому D3:000 не є D1:0 для машинного предиката?
  4) Чому умова компілюється у CMP/JNE, а не у Pascal?
  5) Чому жодна текстова проєкція не може замінити exact D3 голову? }

{ Контракт/пам'ять: Physical та CandidateIR borrowed; ActualIR —
  локальна керована FPC пам'ять, ELF — новий owned RawByteString.
  На відмову EVerifiedIRELFError і нульовий результат.
  Питання:
  1) Чому структура IR не доводить його фізичне походження?
  2) Чому для двох backend-ів достатньо одного provenance guard?
  3) Чому машинний ATOM, а не Pascal, визначає вихідний D1?
  4) Чому D7 SYN дані не стають викличними головами?
  5) Чим цей вузький місток відрізняється від загального компілятора? }
end.
