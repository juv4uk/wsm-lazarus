{ G6.96 — зниження ТІЛА SENS у машинний код із РЕКУРСІЄЮ.
  Тіло розбирається тим самим ParseD2WordsWide, що й обчислювач, і
  перекладається в x86-64 для підмножини:

    <параметр>              → mov eax, edi
    (як-є <D24>)            → mov eax, imm32
    (додати A B)            → gen A; push; gen B; mov ecx,eax; pop; add
    (відняти A B)           → те саме з sub
    (менше? A B)            → cmp + setl + movzx  (точний D1)
    (більше? A B)            → cmp + setg + movzx  (точний D1)
    (тотожне? D24 D24)      → cmp + sete + movzx  (точний D1)
    (за-умовою …)           → гілки зверху вниз, «так» = інакше
    (<власне імʼя> X)       → самовиклик через call

  Угода виклику (host-механізм, не закон SENS): аргумент в edi,
  результат в eax; функція зберігає rdi (push/pop у пролозі).

  Поза підмножиною — ЯВНА відмова, без «майже правильно». }
unit wsm.lowerd24;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  ELowerD24Error = class(Exception);

{ BodyPhysical — packed T5M байти ТІЛА (функція з одним параметром).
  ParamPhysical — точний D7-ключ параметра, ArgPhysical — D24-аргумент.
  SelfPhysical — точний D7-ключ власного імені ('' — самовиклик заборонено).
  Результат — ELF64 ET_EXEC: exit(low8(тіло(аргумент))). }
function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;
function LowerPairELF(const BodyA, NameA, BodyB, NameB,
  ParamPhysical, ArgPhysical: RawByteString): RawByteString;
function LowerBodyTwoParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical: RawByteString): RawByteString;
{ G6.257: трипараметрове тіло. Третій аргумент приходить у edx (SysV x86-64),
  тому він теж зберігається в кадрі, а посилання на нього — mov eax, edx. }
function LowerBodyThreeParamsWithSelfELF(const BodyPhysical, Param1Physical,
  Param2Physical, Param3Physical, Arg1Physical, Arg2Physical,
  Arg3Physical, SelfPhysical: RawByteString): RawByteString;
function LowerBodyThreeParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Param3Physical, Arg1Physical, Arg2Physical,
  Arg3Physical: RawByteString): RawByteString;
function LowerBodyTwoParamsWithSelfELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical,
  SelfPhysical: RawByteString): RawByteString;
function LowerBodyWithSelfELF(const BodyPhysical, ParamPhysical,
  ArgPhysical, SelfPhysical: RawByteString): RawByteString;
{ G6.258: загальний вхід для 1..6 параметрів. Ключі — точні фізичні
  D7-слова, аргументи — точні D24-слова. Понад 6 — явна відмова:
  сьомий аргумент SysV кладе в стек, а такого шляху тут немає. }
function LowerBodyNParamsELF(const BodyPhysical: RawByteString;
  const ParamKeys, ArgKeys: array of RawByteString): RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.numericplane;

const
  { SysV x86-64: перші шість аргументів — у регістрах. Більше не беремо. }
  MaxParams = 6;

type
  { Відкладене виправлення rel32: ціль може бути ще не відома
    (виклик уперед до другої функції пари). }
  TCallFixup = record
    At: SizeInt;      { зсув байта $E8 }
    Target: Byte;     { 0 — своя функція, 1 — парна }
    Owner: Byte;      { у якій функції це виправлення: 0 або 1 }
  end;

type
  { СТАН ОДНОГО ЗНИЖЕННЯ. Раніше це були окремі глобали, і вони
    протікали між викликами: залишок від парного зниження вимикав
    хвостовий стрибок, а застарілі виправлення писали в чужий образ.
    Тепер стан зберігається й відновлюється ЦІЛКОМ на кожному вході. }
  TLowerState = record
    PairBits: RawByteString;
    PairOffset: SizeInt;
    { G6.258: параметри як масиви. SysV x86-64 передає ПЕРШІ ШІСТЬ
      аргументів у регістрах (rdi, rsi, rdx, rcx, r8, r9), тому 4..6
      параметрів — це та сама механіка, а не новий ABI. Раніше кожен
      додатковий параметр вимагав нової копії коду в п'яти місцях. }
    ParamBits: array[0..MaxParams-1] of RawByteString;
    ArgValue: array[0..MaxParams-1] of LongWord;
    ParamCount: Byte;
    CurFunc: Byte;
    TailCtx: Boolean;
    Fixups: array of TCallFixup;
  end;

var
  State: TLowerState;
  FixupCount: SizeInt = 0;

const
  ELFBase = $400000;
  HeaderBytes = 64 + 56;
  MaxCodeBytes = 4096;
  D24Width = 24;

function UkrBytes(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Need(Ok: Boolean; const Why: UnicodeString);
begin
  if not Ok then raise ELowerD24Error.Create(UkrBytes(Why));
end;

function BitsToLong(const Bits: RawByteString; out Value: LongWord): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  Value := 0;
  if Length(Bits) > 32 then Exit;
  for I := 1 to Length(Bits) do begin
    Need((Bits[I] = '0') or (Bits[I] = '1'), 'слово містить не двійковий знак');
    Value := (Value shl 1) or LongWord(Ord(Bits[I]) - Ord('0'));
  end;
  Result := True;
end;

{ Фізичний D24 — signed two's complement за pinned SENS 12.0.
  Знаки розширюємо тільки в ABI x86-64; ні ширину джерела, ні його
  байти T5M, ні семантичну доменну ідентичність не змінюємо. }
function SignExtendD24(Value: LongWord): LongWord;
begin
  Result := Value;
  if (Value and (LongWord(1) shl (D24Width - 1))) <> 0 then
    Result := Value or $FF000000;
end;

function IsGlyphSequence(Node: TD2Node): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  if (Node = nil) or (Node.Kind <> dkList) or (Length(Node.Children) = 0) then Exit;
  for I := 0 to High(Node.Children) do
    if (Node.Children[I].Kind <> dkIdentity) or (Node.Children[I].Width <> 7) then Exit;
  Result := True;
end;

function GlyphBits(Node: TD2Node): RawByteString;
var
  I: SizeInt;
begin
  Result := '';
  for I := 0 to High(Node.Children) do Result := Result + Node.Children[I].Bits;
end;

{ Дозволена форма операнда D3:101 тільки в ЦЬОМУ D24 lowering:
  1) точна лексична D7-послідовність оголошеного параметра, який
     при виклику отримує саме D24 атом; 2) D3:001 над exact D24.
  Ні D1, ні D12, ні довільний список, ні арифметичний вираз тут
  не можна тихо перетворювати на D24 лише через host-регістр. }
function IsExactD24Operand(Node: TD2Node;
  const ParamBits: RawByteString): Boolean;
var
  Head, Atom: TD2Node;
  I: SizeInt;
begin
  Result := False;
  if Node = nil then Exit;
  if IsGlyphSequence(Node) then begin
    Result := GlyphBits(Node) = ParamBits;
    if Result then Exit;
    for I := 0 to State.ParamCount - 1 do
      if GlyphBits(Node) = State.ParamBits[I] then begin Result := True; Exit; end;
    Exit;
  end;
  if (Node.Kind <> dkList) or (Length(Node.Children) <> 2) then Exit;
  Head := Node.Children[0];
  Atom := Node.Children[1];
  Result := (Head <> nil) and (Atom <> nil) and
    (Head.Kind = dkIdentity) and (Head.Width = 3) and
    (Head.Bits = '001') and (Atom.Kind = dkIdentity) and
    (Atom.Width = D24Width);
end;

{ Вузьке статичне доведення D24 для операндів предиката D5.
  Borrowed TD2Node належить TD2Document; нічого не алокуємо тут.
  Наявні самовиклики та D3-твори не вважаємо D24 без аналізу
  повернення цілої функції: краще явна відмова, ніж D1/D24 колізія.
  1) Чому ширина 24 важлива? 2) Чому D1:1 не число 1?
  3) Чому невиведена форма відхиляється? }
function IsTypedD24Term(Node: TD2Node;
  const ParamBits: RawByteString): Boolean;
var
  Head: TD2Node;
begin
  Result := IsExactD24Operand(Node, ParamBits);
  if Result or (Node = nil) then Exit;
  if (Node.Kind <> dkList) or (Length(Node.Children) <> 3) then Exit;
  Head := Node.Children[0];
  if (Head = nil) or (Head.Kind <> dkIdentity) or
    (Head.Width <> 5) or
    ((Head.Bits <> '01010') and (Head.Bits <> '01011')) then Exit;
  Result := IsTypedD24Term(Node.Children[1], ParamBits) and
    IsTypedD24Term(Node.Children[2], ParamBits);
end;

{ Тест D3:110 зобов'язаний повертати ТОЧНО D1:0 або D1:1.
  Замість host truthiness розпізнаємо лише вже підтримані ратифіковані
  предикати, а для їхніх числових аргументів — точний D24.
  Лексичне D7 ім'я параметра не є D1 лише через машинний біт.
  Result — host Boolean допуску, не нова семантична функція SENS.
  1) Чому D24:+1 тут не D1:1? 2) Хто володіє Node?
  3) Чому лише дві частини у предиката? 4) Де закріплено D5 координати? }
function IsExactD1Test(Node: TD2Node;
  const ParamBits: RawByteString): Boolean;
var
  Head: TD2Node;
begin
  Result := False;
  if Node = nil then Exit;
  if Node.Kind = dkIdentity then begin
    Result := (Node.Width = 1) and
      ((Node.Bits = '0') or (Node.Bits = '1'));
    Exit;
  end;
  if (Node.Kind <> dkList) or (Length(Node.Children) <> 3) then Exit;
  Head := Node.Children[0];
  if (Head = nil) or (Head.Kind <> dkIdentity) then Exit;
  if (Head.Width = 3) and (Head.Bits = '101') then begin
    Result := IsExactD24Operand(Node.Children[1], ParamBits) and
      IsExactD24Operand(Node.Children[2], ParamBits);
    Exit;
  end;
  if (Head.Width = 5) and
    ((Head.Bits = '11010') or (Head.Bits = '11011')) then
    Result := IsTypedD24Term(Node.Children[1], ParamBits) and
      IsTypedD24Term(Node.Children[2], ParamBits);
end;

type
  TCodeBuf = array[0..MaxCodeBytes - 1] of Byte;

procedure Compile(const Node: TD2Node; const ParamBits, SelfBits: RawByteString;
  const FuncOffset: SizeInt; const TempDepth: SizeInt;
  var Code: TCodeBuf; var At: SizeInt);
var
  Head, Clause, Test: TD2Node;
  Value: LongWord;
  CallTarget: Byte;
  MyTail, SavedTail: Boolean;
  Width, K, JneAt, I: SizeInt;
  Delta: LongInt;
  IsElse: Boolean;
  Jumps: array of SizeInt;

  procedure Emit(const Bytes: array of Byte);
  var
    J: SizeInt;
  begin
    Need(At + Length(Bytes) <= MaxCodeBytes, 'згенерований код задовгий');
    for J := 0 to High(Bytes) do begin
      Code[At] := Bytes[J];
      Inc(At);
    end;
  end;

  { Яку з двох функцій пари кличе голова-імʼя: 0 — своя, 1 — парна. }
  function CallTargetOf(const Head: TD2Node): Byte;
  var
    Bits: RawByteString;
  begin
    Bits := GlyphBits(Head);
    if (SelfBits <> '') and (Bits = SelfBits) then Exit(0);
    if (State.PairBits <> '') and (Bits = State.PairBits) then Exit(1);
    raise ELowerD24Error.Create(UkrBytes('виклик чужого визначення поза ' +
      'підмножиною зниження'));
  end;

  { Виклик із ВІДКЛАДЕНИМ rel32: ціль може бути ще не емітована. }
  procedure EmitCall(Target: Byte);
  begin
    Emit([$E8, 0, 0, 0, 0]);
    SetLength(State.Fixups, Length(State.Fixups) + 1);
    State.Fixups[High(State.Fixups)].At := At - 5;
    State.Fixups[High(State.Fixups)].Target := Target;
    State.Fixups[High(State.Fixups)].Owner := State.CurFunc;
  end;


  procedure EmitImm32(const Opcode: Byte; const V: LongWord);
  begin
    Emit([Opcode, Byte(V and $FF), Byte((V shr 8) and $FF),
      Byte((V shr 16) and $FF), Byte((V shr 24) and $FF)]);
  end;

  procedure PatchRel32(const AtOpcode: SizeInt);
  begin
    Delta := At - (AtOpcode + 5);
    Code[AtOpcode + 1] := Byte(Delta and $FF);
    Code[AtOpcode + 2] := Byte((Delta shr 8) and $FF);
    Code[AtOpcode + 3] := Byte((Delta shr 16) and $FF);
    Code[AtOpcode + 4] := Byte((Delta shr 24) and $FF);
  end;

begin
  { Хвостовість стосується ЛИШЕ цього вузла: вкладені підвирази
    скидають її, інакше самовиклик в аргументі теж став би jmp. }
  MyTail := State.TailCtx;
  State.TailCtx := False;
  Need(Node <> nil, 'порожній вузол тіла');
  if IsGlyphSequence(Node) then begin
    if GlyphBits(Node) = ParamBits then begin
      Emit([$89, $F8]);                     { mov eax, edi }
      Exit;
    end;
    for I := 0 to State.ParamCount - 1 do
      if GlyphBits(Node) = State.ParamBits[I] then begin
        case I of
          1: Emit([$89, $F0]);              { mov eax, esi }
          2: Emit([$89, $D0]);              { mov eax, edx }
          3: Emit([$89, $C8]);              { mov eax, ecx }
          4: Emit([$44, $89, $C0]);         { mov eax, r8d }
          5: Emit([$44, $89, $C8]);         { mov eax, r9d }
        end;
        Exit;
      end;
    raise ELowerD24Error.Create(UkrBytes('імʼя поза параметрами: ' +
      RawByteString(GlyphBits(Node))));
  end;
  Need(Node.Kind = dkList, 'тіло мусить бути списком або параметром');
  Need(Length(Node.Children) >= 1, 'порожній список у тілі');
  Head := Node.Children[0];
  Need(Head <> nil, 'порожня голова в тілі');
  { Голова-ІМʼЯ: або самовиклик, або явна відмова. Перевіряємо ДО вимоги
    «голова — координата», бо вузол-імʼя сам є списком. }
  if IsGlyphSequence(Head) then begin
    CallTarget := CallTargetOf(Head);
    { Аргументи обчислюються з НАШИХ rdi/rsi, тому обидва регістри
      зберігаються навколо виклику: каллі зберігає власні, не наші. }
    if Length(Node.Children) = 3 then begin
      if MyTail then begin
        { ХВОСТОВИЙ двoаргументний самовиклик: результат виклику і є
          результатом функції. r8 — тимчасовий (каллі-збережений),
          тому другий аргумент переживає зняття власного кадру. }
        Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
        Emit([$41, $89, $C0]);              { mov r8d, eax — другий }
        Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
        { Кадр двопараметрової функції: push rdi, push rsi, push rbx —
          тому знімаємо РІВНО стільки ж і в зворотному порядку. }
        Emit([$5B]);                        { pop rbx }
        Emit([$5E]);                        { pop rsi }
        Emit([$5F]);                        { pop rdi }
        Emit([$89, $C7]);                   { mov edi, eax — перший }
        Emit([$44, $89, $C6]);              { mov esi, r8d — другий }
        Emit([$E9, 0, 0, 0, 0]);            { jmp F }
        SetLength(State.Fixups, Length(State.Fixups) + 1);
        State.Fixups[High(State.Fixups)].At := At - 5;
        State.Fixups[High(State.Fixups)].Target := CallTarget;
        State.Fixups[High(State.Fixups)].Owner := State.CurFunc;
        Exit;
      end;
      { Два аргументи: перший рахуємо і кладемо в стек, другий — після
        нього, бо обидва мусять бачити ЩЕ НЕ змінені rdi та rsi. }
      Emit([$57]);                          { push rdi }
      Emit([$56]);                          { push rsi }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);                          { push rax — перший аргумент }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$89, $C6]);                     { mov esi, eax — другий }
      Emit([$5F]);                          { pop rdi — перший }
      EmitCall(CallTarget);
      Emit([$5E]);                          { pop rsi — відновити наш m }
      Emit([$5F]);                          { pop rdi — відновити наш n }
      Exit;
    end;
    if Length(Node.Children) = 4 then begin
      { G6.257: триаргументний самовиклик. Усі три аргументи рахуються з
        ЩЕ не змінених rdi/rsi/rdx, тому: спершу зберігаємо свої три
        регістри, далі кладемо на стек три результати, потім розкладаємо
        їх у edi/esi/edx. r8/r9 не використовуємо: вкладений самовиклик
        в аргументі їх би зіпсував. }
      Emit([$57]);                          { push rdi }
      Emit([$56]);                          { push rsi }
      Emit([$52]);                          { push rdx }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);                          { push rax — перший }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);                          { push rax — другий }
      Compile(Node.Children[3], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);                          { push rax — третій }
      if MyTail then begin
        { Хвіст: СПЕРШУ беремо три аргументи у регістри — вони лежать на
          верху стека. Порядок важливий: якщо спершу знімати кадр, то
          pop'и дістануть аргументи замість збережених регістрів (саме ця
          помилка дала SIGSEGV на першій спробі). Після аргументів стек
          містить РІВНО 7 наших збережень: 3 власні регістри + кадр
          (rbx, rdx, rsi, rdi) — їх знімаємо одним add rsp, 56. }
        Emit([$5A]);                        { pop rdx — третій аргумент }
        Emit([$5E]);                        { pop rsi — другий }
        Emit([$5F]);                        { pop rdi — перший }
        Emit([$48, $83, $C4, 56]);          { add rsp, 56 — зняти кадр }
        Emit([$E9, 0, 0, 0, 0]);            { jmp F }
        SetLength(State.Fixups, Length(State.Fixups) + 1);
        State.Fixups[High(State.Fixups)].At := At - 5;
        State.Fixups[High(State.Fixups)].Target := CallTarget;
        State.Fixups[High(State.Fixups)].Owner := State.CurFunc;
        Exit;
      end;
      Emit([$5A]);                          { pop rdx — третій аргумент }
      Emit([$5E]);                          { pop rsi — другий }
      Emit([$5F]);                          { pop rdi — перший }
      EmitCall(CallTarget);
      Emit([$5A]);                          { pop rdx — відновити наш k }
      Emit([$5E]);                          { pop rsi — відновити наш m }
      Emit([$5F]);                          { pop rdi — відновити наш n }
      Exit;
    end;
    Need(Length(Node.Children) = 2, 'самовиклик приймає один, два або три аргументи');
    if MyTail then begin
      { ХВОСТОВИЙ самовиклик: результат виклику і є результатом функції,
        тому не call+ret, а jmp. Перед стрибком знімаємо ВЛАСНИЙ кадр,
        інакше стек ріс би на кожному кроці. }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$5B]);                          { pop rbx }
      Emit([$5F]);                          { pop rdi }
      Emit([$89, $C7]);                     { mov edi, eax }
      Emit([$E9, 0, 0, 0, 0]);              { jmp F — rel32 у виправленні }
      SetLength(State.Fixups, Length(State.Fixups) + 1);
      State.Fixups[High(State.Fixups)].At := At - 5;
      { Ціль — ТА САМА, що й у звичайного виклику: у парі хвостовий
        виклик іде в сусідню функцію, а не в себе. }
      State.Fixups[High(State.Fixups)].Target := CallTarget;
      State.Fixups[High(State.Fixups)].Owner := State.CurFunc;
      Exit;
    end;
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    EmitCall(CallTarget);
    Emit([$5F]);                            { pop rdi — відновити наш n }
    Exit;
  end;
  Need(Head.Kind = dkIdentity, 'голова мусить бути координатою');
  Width := Head.Width;

  if (Width = 3) and (Head.Bits = '001') then begin
    Need(Length(Node.Children) = 2, 'цитата приймає рівно один аргумент');
    Need(Node.Children[1].Kind = dkIdentity, 'цитата тут лише над атомом');
    Need(Node.Children[1].Width = D24Width,
      'цей D24 lowering допускає в цитаті тільки точне D24 слово');
    Need(BitsToLong(Node.Children[1].Bits, Value), 'літерал ширший за 32 біти');
    EmitImm32($B8, SignExtendD24(Value));                  { mov eax, imm32 }
    Exit;
  end;

  if (Width = 3) and (Head.Bits = '101') then begin
    Need(Length(Node.Children) = 3, 'тотожне? приймає рівно два аргументи');
    Need(IsExactD24Operand(Node.Children[1], ParamBits) and
      IsExactD24Operand(Node.Children[2], ParamBits),
      'тотожне? в цьому lowering допускає лише два точні атоми D24');
    { Тільки exact D24: повна 24-бітова тотожність після однакового
      sign-extension еквівалентна CMP 32-bit. Не зіставляємо D1/D12/D7
      з D24 та не порівнюємо списки через адресу чи host-число.
      Stack-balanced навіть усередині вкладеної D3 умови. }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset,
      TempDepth + 1, Code, At);
    Emit([$50]);                            { push rax — лівий D24 }
    Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset,
      TempDepth + 1, Code, At);
    Emit([$41, $89, $C2]);                  { mov r10d, eax — правий D24 }
    Emit([$58]);                            { pop rax — лівий D24 }
    Emit([$44, $39, $D0]);                  { cmp eax, r10d }
    Emit([$0F, $94, $C0]);                  { sete al: точний біт D1 }
    Emit([$0F, $B6, $C0]);                  { movzx eax, al }
    Exit;
  end;

  if (Width = 5) and ((Head.Bits = '01010') or (Head.Bits = '01011')) then begin
    Need(Length(Node.Children) = 3, 'арифметика приймає рівно два аргументи');
    if TempDepth = 0 then begin
      { Глибина 0: лівий операнд живе в rbx — жодного звертання до стеку.
        rbx зберігається і прологом функції, і самовикликом. }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$89, $C3]);                     { mov ebx, eax }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      if Head.Bits = '01010' then Emit([$01, $D8])   { add eax, ebx }
      else begin
        Emit([$29, $C3]);                   { sub ebx, eax }
        Emit([$89, $D8]);                   { mov eax, ebx }
      end;
    end else begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$41, $89, $C2]);                { mov r10d, eax }
      Emit([$58]);                          { pop rax }
      if Head.Bits = '01010' then Emit([$44, $01, $D0])   { add eax, r10d }
      else Emit([$44, $29, $D0]);                        { sub eax, r10d }
    end;
    Exit;
  end;

  if (Width = 5) and
    ((Head.Bits = '11010') or (Head.Bits = '11011')) then begin
    { Обидві голови — точні ратифіковані D5 координати: менше? / більше?.
      Однаковий signed CMP обчислює лівий мінус правий; SETL/SETG
      відрізняються лише умовою CPU, а не семантичним host-іменем.
      D24 sign-extension аргументів робить 32-bit signed прапорці
      еквівалентними порівнянню точних 24-бітних two's complement. }
    Need(Length(Node.Children) = 3,
      'порівняння D5 потребує рівно два аргументи');
    { Новий шлях D5:11011 має вузький exact-D24 admission.
      Host CMP не може законно перетворити D1-предикат, інший домен
      чи список у D24 лише через те, що всі мають машинні біти.
      Існуючий D5:11010 не звужуємо цим окремим зрізом. }
    if Head.Bits = '11011' then
      Need(IsExactD24Operand(Node.Children[1], ParamBits) and
        IsExactD24Operand(Node.Children[2], ParamBits),
        'D5:11011 приймає в цьому lowering лише два exact D24 атоми');
    if TempDepth = 0 then begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$89, $C3]);                     { mov ebx, eax }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$39, $C3]);                     { cmp ebx, eax — EBX лівий, EAX правий }
    end else begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$41, $89, $C2]);
      Emit([$58]);
      Emit([$44, $39, $D0]);                { cmp eax, r10d — EAX лівий }
    end;
    if Head.Bits = '11010' then
      Emit([$0F, $9C, $C0])                 { setl al }
    else
      Emit([$0F, $9F, $C0]);                { setg al }
    Emit([$0F, $B6, $C0]);                  { movzx eax, al — D1 }
    Exit;
  end;

  if (Width = 3) and (Head.Bits = '110') then begin
    Need(Length(Node.Children) >= 2, 'за-умовою потребує бодай одну гілку');
    { Контракт 12.0: вичерпання D3:110 повертає структурне D3:000,
      не D1:0 і не числовий D24. Наш ELF вихід — лише low8(D24),
      тому не можна мовчки закодувати структурну порожнечу нулем.
      Допускаємо тільки суцільні умови з останнім точним D1:1.
      Перевіряємо форму ДО будь-якого машинного коду цієї умови. }
    for K := 1 to High(Node.Children) do begin
      Clause := Node.Children[K];
      Need((Clause <> nil) and (Clause.Kind = dkList) and
        (Length(Clause.Children) = 2), 'гілка мусить бути (тест тіло)');
      Test := Clause.Children[0];
      IsElse := (Test <> nil) and (Test.Kind = dkIdentity) and
        (Test.Width = 1) and (Test.Bits = '1');
      Need((not IsElse) or (K = High(Node.Children)),
        'безумовна D1:1 гілка мусить бути останньою');
      Need(IsExactD1Test(Test, ParamBits),
        'тест D3:110 має бути точним D1, а не числовим D12/D24');
      if K = High(Node.Children) then
        Need(IsElse, 'несуцільна умова: вичерпання повертає D3:000, а не D24');
    end;
    Jumps := nil;
    for K := 1 to High(Node.Children) do begin
      Clause := Node.Children[K];
      Need((Clause <> nil) and (Clause.Kind = dkList) and
        (Length(Clause.Children) = 2), 'гілка мусить бути (тест тіло)');
      Test := Clause.Children[0];
      IsElse := (Test <> nil) and (Test.Kind = dkIdentity) and
        (Test.Width = 1) and (Test.Bits = '1');
      JneAt := -1;
      if not IsElse then begin
        if Test.Kind = dkIdentity then
          Emit([$31, $C0])                 { exact D1:0 -> xor eax,eax }
        else
          Compile(Test, ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
        Emit([$83, $F8, $01]);              { cmp eax, 1, лише exact D1 }
        JneAt := At;
        Emit([$0F, $85, $00, $00, $00, $00]); { jne next }
      end;
      SavedTail := State.TailCtx;
      State.TailCtx := True;
      Compile(Clause.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      State.TailCtx := SavedTail;
      SetLength(Jumps, Length(Jumps) + 1);
      Jumps[High(Jumps)] := At;
      Emit([$E9, $00, $00, $00, $00]);      { jmp end }
      { jne — ШЕСТИбайтна форма (0F 85 + rel32), тому кінець = +6. }
      if JneAt >= 0 then begin
        Delta := At - (JneAt + 6);
        Code[JneAt + 2] := Byte(Delta and $FF);
        Code[JneAt + 3] := Byte((Delta shr 8) and $FF);
        Code[JneAt + 4] := Byte((Delta shr 16) and $FF);
        Code[JneAt + 5] := Byte((Delta shr 24) and $FF);
      end;
    end;
    { Останній exact D1:1 гарантовано обирає гілку;
      відсутня підміна D3:000 машинним D1:0. }
    for I := 0 to High(Jumps) do begin
      Delta := At - (Jumps[I] + 5);
      Code[Jumps[I] + 1] := Byte(Delta and $FF);
      Code[Jumps[I] + 2] := Byte((Delta shr 8) and $FF);
      Code[Jumps[I] + 3] := Byte((Delta shr 16) and $FF);
      Code[Jumps[I] + 4] := Byte((Delta shr 24) and $FF);
    end;
    Exit;
  end;

  if IsGlyphSequence(Head) then begin
    CallTarget := CallTargetOf(Head);
    Need(Length(Node.Children) = 2, 'самовиклик приймає рівно один аргумент');
    { Аргумент обчислюється з edi (наш параметр), тому зберігаємо edi
      навколо виклику: каллі зберігає власний rdi, але не наш. }
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    EmitCall(CallTarget);
    Exit;
  end;

  raise ELowerD24Error.Create(UkrBytes(
    'форма поза підмножиною зниження: параметр, (як-є D24), додати, ' +
    'відняти, менше?, тотожне?, за-умовою, самовиклик'));
end;

{ D7 ім'я в ABI цього lowering — один непорожній D2-список
  точних 7-бітових фізичних слів, а не конкатенація довільних слів.
  Не декодуємо людинозрозумілі назви та не визначаємо тут мовний закон. }
function StripNameBits(const Physical: RawByteString): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(Physical, Words);
  Need(Length(Words) >= 3, 'фізичне D7-імʼя має бути непорожнім списком');
  Need((Words[0] = '10') and (Words[High(Words)] = '01'),
    'фізичне D7-імʼя потребує точних D2-меж');
  Result := '';
  for I := 1 to High(Words) - 1 do begin
    Need(Length(Words[I]) = 7, 'усі слова D7-імені мусять бути 7-бітові');
    Result := Result + Words[I];
  end;
end;

function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;
begin
  Result := LowerBodyWithSelfELF(BodyPhysical, ParamPhysical, ArgPhysical, '');
end;

function LowerBodyTwoParamsWithSelfELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical,
  SelfPhysical: RawByteString): RawByteString;
var
  SavedState: TLowerState;
  Words: TExactWords;
begin
  SavedState := State;
  State := Default(TLowerState);
  State.ParamCount := 2;
  State.ParamBits[1] := StripNameBits(Param2Physical);
  { Аргумент розбираємо ПІСЛЯ скидання: інакше State := Default
    знищив би щойно записане значення — саме ця помилка й дала
    «другий аргумент = 0». }
  DecodeT5M(Arg2Physical, Words);
  Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
    'другий аргумент мусить бути точним D24');
  Need(BitsToLong(Words[0], State.ArgValue[1]), 'другий аргумент не влазить у 32 біти');
  State.ArgValue[1] := SignExtendD24(State.ArgValue[1]);
  try
    Result := LowerBodyWithSelfELF(BodyPhysical, Param1Physical,
      Arg1Physical, SelfPhysical);
  finally
    State := SavedState;
  end;
end;

function LowerBodyTwoParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical: RawByteString): RawByteString;
begin
  Result := LowerBodyTwoParamsWithSelfELF(BodyPhysical, Param1Physical,
    Param2Physical, Arg1Physical, Arg2Physical, '');
end;

{ G6.257: трипараметровий вхід. Порядок як у двопараметрового: спершу
  скидаємо стан, ПОТІМ розбираємо аргументи (інакше скидання знищило б
  щойно записане значення — ця помилка вже траплялася). }
function LowerBodyThreeParamsWithSelfELF(const BodyPhysical, Param1Physical,
  Param2Physical, Param3Physical, Arg1Physical, Arg2Physical,
  Arg3Physical, SelfPhysical: RawByteString): RawByteString;
var
  SavedState: TLowerState;
  Words: TExactWords;
begin
  SavedState := State;
  State := Default(TLowerState);
  State.ParamCount := 3;
  State.ParamBits[1] := StripNameBits(Param2Physical);
  State.ParamBits[2] := StripNameBits(Param3Physical);
  DecodeT5M(Arg2Physical, Words);
  Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
    'другий аргумент мусить бути точним D24');
  Need(BitsToLong(Words[0], State.ArgValue[1]), 'другий аргумент не влазить у 32 біти');
  State.ArgValue[1] := SignExtendD24(State.ArgValue[1]);
  DecodeT5M(Arg3Physical, Words);
  Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
    'третій аргумент мусить бути точним D24');
  Need(BitsToLong(Words[0], State.ArgValue[2]), 'третій аргумент не влазить у 32 біти');
  State.ArgValue[2] := SignExtendD24(State.ArgValue[2]);
  try
    Result := LowerBodyWithSelfELF(BodyPhysical, Param1Physical,
      Arg1Physical, SelfPhysical);
  finally
    State := SavedState;
  end;
end;

function LowerBodyThreeParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Param3Physical, Arg1Physical, Arg2Physical,
  Arg3Physical: RawByteString): RawByteString;
begin
  Result := LowerBodyThreeParamsWithSelfELF(BodyPhysical, Param1Physical,
    Param2Physical, Param3Physical, Arg1Physical, Arg2Physical,
    Arg3Physical, '');
end;

function LowerBodyNParamsELF(const BodyPhysical: RawByteString;
  const ParamKeys, ArgKeys: array of RawByteString): RawByteString;
var
  SavedState: TLowerState;
  Words: TExactWords;
  I: SizeInt;
begin
  Need(Length(ParamKeys) = Length(ArgKeys), 'кількість ключів і аргументів різна');
  Need(Length(ParamKeys) >= 1, 'потрібен бодай один параметр');
  Need(Length(ParamKeys) <= MaxParams,
    'понад шість параметрів: сьомий SysV кладе в стек — цей шлях не підтримано');
  SavedState := State;
  State := Default(TLowerState);
  State.ParamCount := Length(ParamKeys);
  for I := 1 to High(ParamKeys) do
    State.ParamBits[I] := StripNameBits(ParamKeys[I]);
  for I := 1 to High(ArgKeys) do begin
    DecodeT5M(ArgKeys[I], Words);
    Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
      'аргумент мусить бути точним D24');
    Need(BitsToLong(Words[0], State.ArgValue[I]), 'аргумент не влазить у 32 біти');
    State.ArgValue[I] := SignExtendD24(State.ArgValue[I]);
  end;
  try
    Result := LowerBodyWithSelfELF(BodyPhysical, ParamKeys[0], ArgKeys[0], '');
  finally
    State := SavedState;
  end;
end;

function LowerBodyWithSelfELF(const BodyPhysical, ParamPhysical,
  ArgPhysical, SelfPhysical: RawByteString): RawByteString;
var
  BodyWords, ArgWords: TExactWords;
  Doc: TD2Document;
  Code: TCodeBuf;
  At, I, FuncOffset, CallFixAt, FileSize: SizeInt;
  Arg: LongWord;
  ParamBits, SelfBits: RawByteString;
  Delta: LongInt;

  procedure Put(Offset: SizeInt; Number: QWord; Width: SizeInt);
  var
    K: SizeInt;
  begin
    for K := 0 to Width - 1 do begin
      Result[Offset + K + 1] := AnsiChar(Byte(Number and $FF));
      Number := Number shr 8;
    end;
  end;

var
  SavedState: TLowerState;
begin
  Result := '';
  { Стан одного зниження: зберігаємо ЦІЛКОМ і відновлюємо у finally. }
  SavedState := State;
  { Скидаємо ЛИШЕ те, що належить цьому образу: список виправлень,
    роль функції й пару. Param2Bits/Arg2Value міг задати викликач
    (двопараметровий вхід) — їх не чіпаємо. }
  State.Fixups := nil;
  State.CurFunc := 0;
  State.TailCtx := False;
  State.PairBits := '';
  State.PairOffset := 0;
  ParamBits := StripNameBits(ParamPhysical);
  Need(Length(ParamBits) > 0, 'ключ параметра порожній');
  SelfBits := '';
  if SelfPhysical <> '' then SelfBits := StripNameBits(SelfPhysical);

  DecodeT5M(ArgPhysical, ArgWords);
  Need(Length(ArgWords) = 1, 'аргумент мусить бути одним словом');
  Need(Length(ArgWords[0]) = D24Width, 'аргумент мусить бути точним D24');
  Need(BitsToLong(ArgWords[0], Arg), 'аргумент не влазить у 32 біти');
  Arg := SignExtendD24(Arg); { точне фізичне D24 -> signed 32-bit ABI }
  { G6.258: перший параметр теж живе в масиві. Без цього ParamCount
    лишався б 0 для однопараметрового входу — пролог не зберіг би rdi,
    епілог не зняв би його, і КОЖЕН образ падав би SIGSEGV. }
  { ParamCount міг задати викликач (двo/трипараметрові входи) — тоді
    НЕ зменшуємо його: саме ця помилка з'їла другий параметр і дала
    «імʼя поза параметрами». }
  if State.ParamCount = 0 then State.ParamCount := 1;
  State.ParamBits[0] := ParamBits;
  State.ArgValue[0] := Arg;

  DecodeT5M(BodyPhysical, BodyWords);
  Doc := ParseD2WordsWide(BodyWords);
  try
    Need(Length(Doc.Roots) = 1, 'тіло мусить мати рівно один корінь');
    At := 0;
    { Кожне зниження починає з ПУСТОГО списку виправлень: інакше
      застарілі записи попереднього образу переписали б байти цього. }
    SetLength(State.Fixups, 0);
    State.CurFunc := 0;
    { _start: 5 + 5 + 2 + 3 + 5 + 2 = 22 байти. }
    Code[0] := $BF;                                   { mov edi, arg32 }
    Code[1] := Byte(Arg and $FF);
    Code[2] := Byte((Arg shr 8) and $FF);
    Code[3] := Byte((Arg shr 16) and $FF);
    Code[4] := Byte((Arg shr 24) and $FF);
    At := 5;
    for I := 1 to State.ParamCount - 1 do begin
      case I of
        1: begin Code[At] := $BE; Inc(At); end;       { mov esi, arg }
        2: begin Code[At] := $BA; Inc(At); end;       { mov edx, arg }
        3: begin Code[At] := $B9; Inc(At); end;       { mov ecx, arg }
        4: begin Code[At] := $41; Inc(At); Code[At] := $B8; Inc(At); end; { mov r8d }
        5: begin Code[At] := $41; Inc(At); Code[At] := $B9; Inc(At); end; { mov r9d }
      end;
      Code[At] := Byte(State.ArgValue[I] and $FF); Inc(At);
      Code[At] := Byte((State.ArgValue[I] shr 8) and $FF); Inc(At);
      Code[At] := Byte((State.ArgValue[I] shr 16) and $FF); Inc(At);
      Code[At] := Byte((State.ArgValue[I] shr 24) and $FF); Inc(At);
    end;
    Code[At] := $E8;                                  { call F }
    CallFixAt := At; Inc(At);
    { Вхідний виклик — теж відкладене виправлення: ціль (початок
      функції) стає відома лише після емісії тіла. }
    SetLength(State.Fixups, Length(State.Fixups) + 1);
    State.Fixups[High(State.Fixups)].At := CallFixAt;
    State.Fixups[High(State.Fixups)].Target := 0;
    State.Fixups[High(State.Fixups)].Owner := 0;
    Code[At] := 0; Inc(At); Code[At] := 0; Inc(At);
    Code[At] := 0; Inc(At); Code[At] := 0; Inc(At);   { rel32 заповнимо }
    Code[At] := $89; Inc(At); Code[At] := $C7; Inc(At); { mov edi, eax }
    Code[At] := $83; Inc(At); Code[At] := $E7; Inc(At);
    Code[At] := $FF; Inc(At);                         { and edi, 255 }
    Code[At] := $B8; Inc(At); Code[At] := $3C; Inc(At);
    Code[At] := $00; Inc(At); Code[At] := $00; Inc(At);
    Code[At] := $00; Inc(At);                         { mov eax, 60 }
    Code[At] := $0F; Inc(At); Code[At] := $05; Inc(At); { syscall }
    FuncOffset := At;
    At := FuncOffset;
    { Пролог: зберігаємо КОЖЕН регістр-аргумент, бо тіло й самовиклики
      їх перезаписують. Порядок push = порядок регістрів. }
    for I := 0 to State.ParamCount - 1 do begin
      case I of
        0: begin Code[At] := $57; Inc(At); end;       { push rdi }
        1: begin Code[At] := $56; Inc(At); end;       { push rsi }
        2: begin Code[At] := $52; Inc(At); end;       { push rdx }
        3: begin Code[At] := $51; Inc(At); end;       { push rcx }
        4: begin Code[At] := $41; Inc(At); Code[At] := $50; Inc(At); end; { push r8 }
        5: begin Code[At] := $41; Inc(At); Code[At] := $51; Inc(At); end; { push r9 }
      end;
    end;
    Code[At] := $53; Inc(At);                         { push rbx — тимчасовий }
    Compile(Doc.Roots[0], ParamBits, SelfBits, FuncOffset, 0, Code, At);
    Code[At] := $5B; Inc(At);                         { pop rbx }
    for I := State.ParamCount - 1 downto 0 do begin
      case I of
        0: begin Code[At] := $5F; Inc(At); end;       { pop rdi }
        1: begin Code[At] := $5E; Inc(At); end;       { pop rsi }
        2: begin Code[At] := $5A; Inc(At); end;       { pop rdx }
        3: begin Code[At] := $59; Inc(At); end;       { pop rcx }
        4: begin Code[At] := $41; Inc(At); Code[At] := $58; Inc(At); end; { pop r8 }
        5: begin Code[At] := $41; Inc(At); Code[At] := $59; Inc(At); end; { pop r9 }
      end;
    end;
    Code[At] := $C3; Inc(At);                         { ret }

    { Усі відкладені виклики: ціль тепер відома. }
    for I := 0 to High(State.Fixups) do begin
      if State.Fixups[I].Owner <> State.CurFunc then Continue;
      if State.Fixups[I].Target = 0 then Delta := FuncOffset
      else Delta := State.PairOffset;
      Delta := Delta - (State.Fixups[I].At + 5);
      Code[State.Fixups[I].At + 1] := Byte(Delta and $FF);
      Code[State.Fixups[I].At + 2] := Byte((Delta shr 8) and $FF);
      Code[State.Fixups[I].At + 3] := Byte((Delta shr 16) and $FF);
      Code[State.Fixups[I].At + 4] := Byte((Delta shr 24) and $FF);
    end;

    FileSize := HeaderBytes + At;
    SetLength(Result, FileSize);
    for I := 1 to Length(Result) do Result[I] := #0;
    Put(0, $464C457F, 4);
    Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
    Put(16, 2, 2); Put(18, 62, 2); Put(20, 1, 4);
    Put(24, ELFBase + HeaderBytes, 8);
    Put(32, 64, 8);
    Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
    Put(64, 1, 4); Put(68, 5, 4);
    Put(80, ELFBase, 8); Put(88, ELFBase, 8);
    Put(96, FileSize, 8); Put(104, FileSize, 8); Put(112, $1000, 8);
    for I := 0 to At - 1 do
      Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
  finally
    Doc.Free;
    State := SavedState;
  end;
end;


{ ДВІ функції в одному ELF: взаємна рекурсія (evenodd).
  Вхід кличе A; A і B кликають одна одну. Цілі викликів стають відомі
  лише після емісії обох тіл, тому всі rel32 відкладені. }
function LowerPairELF(const BodyA, NameA, BodyB, NameB,
  ParamPhysical, ArgPhysical: RawByteString): RawByteString;
var
  DocA, DocB: TD2Document;
  Words, WordsA, WordsB: TExactWords;
  Code: TCodeBuf;
  At, I, FileSize, OffA, OffB, EntryFix, Delta: SizeInt;
  Arg: LongWord;
  BitsA, BitsB, ParamBits2: RawByteString;
  SavedState: TLowerState;

  procedure Put(Offset: SizeInt; Number: QWord; Width: SizeInt);
  var
    K: SizeInt;
  begin
    for K := 0 to Width - 1 do begin
      Result[Offset + K + 1] := AnsiChar(Byte(Number and $FF));
      Number := Number shr 8;
    end;
  end;

  procedure EmitFunction(const Doc: TD2Document; const SelfName: RawByteString);
  begin
    Code[At] := $57; Inc(At);                 { push rdi }
    Code[At] := $53; Inc(At);                 { push rbx }
    Compile(Doc.Roots[0], ParamBits2, SelfName, 0, 0, Code, At);
    Code[At] := $5B; Inc(At);                 { pop rbx }
    Code[At] := $5F; Inc(At);                 { pop rdi }
    Code[At] := $C3; Inc(At);                 { ret }
  end;

begin
  DecodeT5M(ArgPhysical, Words);
  Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
    'аргумент мусить бути точним D24');
  Need(BitsToLong(Words[0], Arg), 'аргумент не влазить у 32 біти');
  Arg := SignExtendD24(Arg);

  BitsA := StripNameBits(NameA);
  BitsB := StripNameBits(NameB);
  ParamBits2 := StripNameBits(ParamPhysical);
  Need((BitsA <> '') and (BitsB <> '') and (BitsA <> BitsB),
    'пара потребує двох різних імен');
  Need(ParamBits2 <> '', 'пара потребує імені параметра');

  SetLength(State.Fixups, 0);
  DecodeT5M(BodyA, WordsA);
  DecodeT5M(BodyB, WordsB);
  DocA := ParseD2WordsWide(WordsA);
  try
    DocB := ParseD2WordsWide(WordsB);
    try
      At := 0;
      Code[0] := $BF;
      Code[1] := Byte(Arg and $FF);
      Code[2] := Byte((Arg shr 8) and $FF);
      Code[3] := Byte((Arg shr 16) and $FF);
      Code[4] := Byte((Arg shr 24) and $FF);
      At := 5;
      Code[At] := $E8; EntryFix := At; Inc(At);
      Code[At] := 0; Inc(At); Code[At] := 0; Inc(At);
      Code[At] := 0; Inc(At); Code[At] := 0; Inc(At);
      SetLength(State.Fixups, 1);
      State.Fixups[0].At := EntryFix; State.Fixups[0].Target := 0; State.Fixups[0].Owner := 0;
      Code[At] := $89; Inc(At); Code[At] := $C7; Inc(At);
      Code[At] := $83; Inc(At); Code[At] := $E7; Inc(At);
      Code[At] := $FF; Inc(At);
      Code[At] := $B8; Inc(At); Code[At] := $3C; Inc(At);
      Code[At] := $00; Inc(At); Code[At] := $00; Inc(At);
      Code[At] := $00; Inc(At);
      Code[At] := $0F; Inc(At); Code[At] := $05; Inc(At);

      OffA := At;
      State.CurFunc := 0;
      State.PairBits := BitsB;
      EmitFunction(DocA, BitsA);

      OffB := At;
      State.CurFunc := 1;
      State.PairBits := BitsA;
      EmitFunction(DocB, BitsB);

      for I := 0 to High(State.Fixups) do begin
        if State.Fixups[I].Target = 0 then begin
          if State.Fixups[I].Owner = 0 then Delta := OffA else Delta := OffB;
        end else begin
          if State.Fixups[I].Owner = 0 then Delta := OffB else Delta := OffA;
        end;
        Delta := Delta - (State.Fixups[I].At + 5);
        Code[State.Fixups[I].At + 1] := Byte(Delta and $FF);
        Code[State.Fixups[I].At + 2] := Byte((Delta shr 8) and $FF);
        Code[State.Fixups[I].At + 3] := Byte((Delta shr 16) and $FF);
        Code[State.Fixups[I].At + 4] := Byte((Delta shr 24) and $FF);
      end;

      FileSize := HeaderBytes + At;
      SetLength(Result, FileSize);
      for I := 1 to Length(Result) do Result[I] := #0;
      Put(0, $464C457F, 4);
      Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
      Put(16, 2, 2); Put(18, 62, 2); Put(20, 1, 4);
      Put(24, ELFBase + HeaderBytes, 8);
      Put(32, 64, 8);
      Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
      Put(64, 1, 4); Put(68, 5, 4);
      Put(80, ELFBase, 8); Put(88, ELFBase, 8);
      Put(96, FileSize, 8); Put(104, FileSize, 8); Put(112, $1000, 8);
      for I := 0 to At - 1 do
        Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
    finally
      DocB.Free;
    end;
  finally
    DocA.Free;
    State := SavedState;
  end;
end;

end.
