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
    (парне?/непарне? D24)   → test + setz/setnz + movzx (D1)
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
function LowerBodyTwoParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical: RawByteString): RawByteString;
function LowerBodyTwoParamsWithSelfELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical,
  SelfPhysical: RawByteString): RawByteString;
function LowerBodyWithSelfELF(const BodyPhysical, ParamPhysical,
  ArgPhysical, SelfPhysical: RawByteString): RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.numericplane;

var
  { Другий параметр тіла ('' — тіло з одним параметром). Стан одного
    зниження; регістр rsi — механізм SysV x86-64, не мовний закон. }
  Param2Bits: RawByteString = '';
  { Другий аргумент у 32-бітному ABI; діє лише коли Param2Bits<>''. }
  Arg2Value: LongWord = 0;

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
begin
  Result := False;
  if Node = nil then Exit;
  if IsGlyphSequence(Node) then begin
    Result := (GlyphBits(Node) = ParamBits) or
      ((Param2Bits <> '') and (GlyphBits(Node) = Param2Bits));
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

type
  TCodeBuf = array[0..MaxCodeBytes - 1] of Byte;

procedure Compile(const Node: TD2Node; const ParamBits, SelfBits: RawByteString;
  const FuncOffset: SizeInt; const TempDepth: SizeInt;
  var Code: TCodeBuf; var At: SizeInt);
var
  Head, Clause, Test: TD2Node;
  Value: LongWord;
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
  Need(Node <> nil, 'порожній вузол тіла');
  if IsGlyphSequence(Node) then begin
    if GlyphBits(Node) = ParamBits then begin
      Emit([$89, $F8]);                     { mov eax, edi }
      Exit;
    end;
    if (Param2Bits <> '') and (GlyphBits(Node) = Param2Bits) then begin
      Emit([$89, $F0]);                     { mov eax, esi }
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
    Need((SelfBits <> '') and (GlyphBits(Head) = SelfBits),
      'виклик чужого визначення поза підмножиною зниження');
    { Аргументи обчислюються з НАШИХ rdi/rsi, тому обидва регістри
      зберігаються навколо виклику: каллі зберігає власні, не наші. }
    if Length(Node.Children) = 3 then begin
      { Два аргументи: перший рахуємо і кладемо в стек, другий — після
        нього, бо обидва мусять бачити ЩЕ НЕ змінені rdi та rsi. }
      Emit([$57]);                          { push rdi }
      Emit([$56]);                          { push rsi }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);                          { push rax — перший аргумент }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$89, $C6]);                     { mov esi, eax — другий }
      Emit([$5F]);                          { pop rdi — перший }
      Delta := FuncOffset - (At + 5);
      Emit([$E8, Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
        Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
      Emit([$5E]);                          { pop rsi — відновити наш m }
      Emit([$5F]);                          { pop rdi — відновити наш n }
      Exit;
    end;
    Need(Length(Node.Children) = 2, 'самовиклик приймає один або два аргументи');
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    Delta := FuncOffset - (At + 5);
    Emit([$E8, Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
      Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
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
    Emit([$89, $C1]);                       { mov ecx, eax — правий D24 }
    Emit([$58]);                            { pop rax — лівий D24 }
    Emit([$39, $C8]);                       { cmp eax, ecx }
    Emit([$0F, $94, $C0]);                  { sete al: точний біт D1 }
    Emit([$0F, $B6, $C0]);                  { movzx eax, al }
    Exit;
  end;

  { G6.150: ТІЛЬКИ exact pinned D6:010000/010001. Поверхня укр —
    людська проєкція, ніколи не machine dispatch; width=6 важливий.
    Дозволено рівно один exact D24: D7 параметр або D3:001 D24.
    Host x86 TEST/SETcc повертає один D1-біт без Pascal обчислення.
    Result живе в EAX; локальний стек не змінюється.
    Питання: чому W12 з таким самим числовим вмістом не D24?
    Чому використовуємо TEST AL,1 для negative two's complement?
    Чому SETZ і SETNZ дають протилежні D1 біти?
    Чому ядро SENS, а не ця процедура, визначає закон D6? }
  if (Width = 6) and
    ((Head.Bits = '010000') or (Head.Bits = '010001')) then begin
    Need(Length(Node.Children) = 2,
      'D6 парність приймає рівно один D24 аргумент');
    Need(IsExactD24Operand(Node.Children[1], ParamBits),
      'D6 парність допускає лише лексичний D24 або цитату exact D24');
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset,
      TempDepth + 1, Code, At);
    Emit([$A8, $01]);                        { test al, 1 }
    if Head.Bits = '010000' then
      Emit([$0F, $94, $C0])                  { setz al: парне? }
    else
      Emit([$0F, $95, $C0]);                 { setnz al: непарне? }
    Emit([$0F, $B6, $C0]);                   { movzx eax, al: D1 }
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
      Emit([$89, $C1]);                     { mov ecx, eax }
      Emit([$58]);                          { pop rax }
      if Head.Bits = '01010' then Emit([$01, $C8]) else Emit([$29, $C8]);
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
      Emit([$89, $C1]);
      Emit([$58]);
      Emit([$39, $C8]);                     { cmp eax, ecx — EAX лівий }
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
        Compile(Test, ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
        Emit([$83, $F8, $01]);              { cmp eax, 1 }
        JneAt := At;
        Emit([$0F, $85, $00, $00, $00, $00]); { jne next }
      end;
      Compile(Clause.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
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
    Need((SelfBits <> '') and (GlyphBits(Head) = SelfBits),
      'виклик чужого визначення поза підмножиною зниження');
    Need(Length(Node.Children) = 2, 'самовиклик приймає рівно один аргумент');
    { Аргумент обчислюється з edi (наш параметр), тому зберігаємо edi
      навколо виклику: каллі зберігає власний rdi, але не наш. }
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    Delta := FuncOffset - (At + 5);
    Emit([$E8, Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
      Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
    Exit;
  end;

  raise ELowerD24Error.Create(UkrBytes(
    'форма поза підмножиною зниження: параметр, (як-є D24), додати, ' +
    'відняти, менше?, тотожне?, парне?/непарне?, за-умовою, самовиклик'));
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
  SavedBits: RawByteString;
  SavedArg2: LongWord;
  Words: TExactWords;
begin
  DecodeT5M(Arg2Physical, Words);
  Need((Length(Words) = 1) and (Length(Words[0]) = D24Width),
    'другий аргумент мусить бути точним D24');
  Need(BitsToLong(Words[0], Arg2Value), 'другий аргумент не влазить у 32 біти');
  Arg2Value := SignExtendD24(Arg2Value);
  SavedBits := Param2Bits;
  SavedArg2 := Arg2Value;
  Param2Bits := StripNameBits(Param2Physical);
  try
    Result := LowerBodyWithSelfELF(BodyPhysical, Param1Physical,
      Arg1Physical, SelfPhysical);
  finally
    Param2Bits := SavedBits;
    Arg2Value := SavedArg2;
  end;
end;

function LowerBodyTwoParamsELF(const BodyPhysical, Param1Physical,
  Param2Physical, Arg1Physical, Arg2Physical: RawByteString): RawByteString;
begin
  Result := LowerBodyTwoParamsWithSelfELF(BodyPhysical, Param1Physical,
    Param2Physical, Arg1Physical, Arg2Physical, '');
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

begin
  Result := '';
  ParamBits := StripNameBits(ParamPhysical);
  Need(Length(ParamBits) > 0, 'ключ параметра порожній');
  SelfBits := '';
  if SelfPhysical <> '' then SelfBits := StripNameBits(SelfPhysical);

  DecodeT5M(ArgPhysical, ArgWords);
  Need(Length(ArgWords) = 1, 'аргумент мусить бути одним словом');
  Need(Length(ArgWords[0]) = D24Width, 'аргумент мусить бути точним D24');
  Need(BitsToLong(ArgWords[0], Arg), 'аргумент не влазить у 32 біти');
  Arg := SignExtendD24(Arg); { точне фізичне D24 -> signed 32-bit ABI }

  DecodeT5M(BodyPhysical, BodyWords);
  Doc := ParseD2WordsWide(BodyWords);
  try
    Need(Length(Doc.Roots) = 1, 'тіло мусить мати рівно один корінь');
    At := 0;
    { _start: 5 + 5 + 2 + 3 + 5 + 2 = 22 байти. }
    Code[0] := $BF;                                   { mov edi, arg32 }
    Code[1] := Byte(Arg and $FF);
    Code[2] := Byte((Arg shr 8) and $FF);
    Code[3] := Byte((Arg shr 16) and $FF);
    Code[4] := Byte((Arg shr 24) and $FF);
    At := 5;
    if Param2Bits <> '' then begin
      Code[At] := $BE; Inc(At);                       { mov esi, arg2_32 }
      Code[At] := Byte(Arg2Value and $FF); Inc(At);
      Code[At] := Byte((Arg2Value shr 8) and $FF); Inc(At);
      Code[At] := Byte((Arg2Value shr 16) and $FF); Inc(At);
      Code[At] := Byte((Arg2Value shr 24) and $FF); Inc(At);
    end;
    Code[At] := $E8;                                  { call F }
    CallFixAt := At; Inc(At);
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
    Code[At] := $57; Inc(At);                         { push rdi — зберегти n }
    if Param2Bits <> '' then begin
      Code[At] := $56; Inc(At);                       { push rsi — зберегти m }
    end;
    Code[At] := $53; Inc(At);                         { push rbx — тимчасовий }
    Compile(Doc.Roots[0], ParamBits, SelfBits, FuncOffset, 0, Code, At);
    Code[At] := $5B; Inc(At);                         { pop rbx }
    if Param2Bits <> '' then begin
      Code[At] := $5E; Inc(At);                       { pop rsi }
    end;
    Code[At] := $5F; Inc(At);                         { pop rdi }
    Code[At] := $C3; Inc(At);                         { ret }

    Delta := FuncOffset - (CallFixAt + 5);
    Code[CallFixAt + 1] := Byte(Delta and $FF);
    Code[CallFixAt + 2] := Byte((Delta shr 8) and $FF);
    Code[CallFixAt + 3] := Byte((Delta shr 16) and $FF);
    Code[CallFixAt + 4] := Byte((Delta shr 24) and $FF);

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
  end;
end;

end.
