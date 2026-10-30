{ G6.x — нативний D12-додавач із десятковим stdout.
  Тут справжня машинна інструкція add: x86-64 код сам додає два
  точні D12-операнди й сам переводить суму в десяткові ASCII-цифри.
  Жодного готового байта відповіді в образі немає.
  Числова семантика належить pinned SENS і вже злитим FPC-механізмам
  wsm.numericplane / wsm.numericadd; цей unit лише механічно
  перекладає перевірені біти в один RX PT_LOAD.
  Питання: 1) Чому операнди — точні D12, а не host Integer?
  2) Де саме відхиляється D12→D24? 3) Чому буфер цифр на стеку,
  а не в сегменті? 4) Що саме робить доказ «число залежить від
  інструкції»? 5) Чому текстова форма розпізнає лише українську
  голову «додати»? }
unit wsm.elfd12adddesiatka;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  EDesiatkaError = class(Exception);
const
  { Host-метадані контейнера, не SENS-закон: 64-байтовий ELF-заголовок
    плюс рівно один 56-байтовий program header. }
  D12DesiatkaHeaderBytes = 120;
  { 0-based зсув опкоду add у машинному коді — позитивний свідок тесту. }
  D12DesiatkaAddOpcodeAt = 10;
  D12DesiatkaAddOpcodeLo = $01;
  D12DesiatkaAddOpcodeHi = $D8;

{ Канонічна українська голова форми — рівно ті UTF-8 байти, що й у
  pinned проєкції. Жодних англійських синонімів і жодного прихованого
  семантичного dispatch: це єдина дозволена поверхня. }
function AddHeadText: RawByteString;

{ Розбирає рівно одну форму «(додати <доданок> <доданок>)».
  Повертає True лише для канонічного запису; Decimal — нормалізований
  десятковий текст, з якого pinned кодувальник робить фізичний D12. }
function ParseAddProgram(const ProgramText: RawByteString;
  out LeftDecimal, RightDecimal: RawByteString): Boolean;

{ Будує ELF64 ET_DYN, який обчислює суму інструкцією add і друкує її
  десятковими ASCII-цифрами в stdout (з завершальним LF). }
function BuildD12AddDecimalELF(const LeftDecimal,
  RightDecimal: RawByteString): RawByteString;

implementation
uses wsm.numericplane, wsm.numericadd, wsm.elfgeometry;

procedure Need(Ok: Boolean; const Why: String);
begin
  if not Ok then raise EDesiatkaError.Create(Why);
end;

function AddHeadText: RawByteString;
begin
  { «додати» у UTF-8; байти виписані явно, щоб жодна кодова
    сторінка компілятора не впливала на розпізнавання голови. }
  Result := #$D0#$B4#$D0#$BE#$D0#$B4#$D0#$B0#$D1#$82#$D0#$B8;
end;

function IsBlank(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

{ Доданок — десятковий запис у межах D12 (-2048..2047).
  Value — host-межа лише для перевірки домену; самі біти далі
  кодуються pinned EncodeNumericDecimal, не цим кодом. }
function ParseLiteral(const Text: RawByteString;
  out Decimal: RawByteString): Boolean;
var
  I, Digits: SizeInt;
  Negative: Boolean;
  Value: LongInt;
begin
  Result := False;
  Decimal := '';
  Need(Length(Text) > 0, 'доданок не може бути порожнім');
  Negative := Text[1] = '-';
  if Negative then I := 2 else I := 1;
  Need(I <= Length(Text), 'доданок без цифр');
  Digits := Length(Text) - I + 1;
  Need(Digits <= 4, 'доданок поза десятковим бюджетом D12');
  Value := 0;
  while I <= Length(Text) do begin
    Need(Text[I] in ['0'..'9'], 'доданок мусить бути десятковим цілим');
    Value := Value * 10 + (Ord(Text[I]) - Ord('0'));
    Inc(I);
  end;
  if Negative then Value := -Value;
  Need((Value >= -2048) and (Value <= 2047), 'доданок поза D12');
  Decimal := RawByteString(IntToStr(Value));
  Result := True;
end;

function ParseAddProgram(const ProgramText: RawByteString;
  out LeftDecimal, RightDecimal: RawByteString): Boolean;
var
  S, Token: RawByteString;
  P, N, Count, Start: SizeInt;
  Tokens: array[0..3] of RawByteString;
  Closed: Boolean;
begin
  Result := False;
  LeftDecimal := '';
  RightDecimal := '';
  S := ProgramText;
  N := Length(S);
  P := 1;
  while (P <= N) and IsBlank(S[P]) do Inc(P);
  while (N >= P) and IsBlank(S[N]) do Dec(N);
  Need(P <= N, 'порожня програма');
  Need(S[P] = '(', 'програма мусить бути в дужках');
  Inc(P);
  Count := 0;
  Closed := False;
  while P <= N do begin
    while (P <= N) and IsBlank(S[P]) do Inc(P);
    if P > N then Break;
    if S[P] = ')' then begin
      Closed := True;
      Inc(P);
      Break;
    end;
    Need(Count < 3, 'у формі зайвий доданок');
    Start := P;
    while (P <= N) and (not IsBlank(S[P])) and (S[P] <> ')') do Inc(P);
    Token := Copy(S, Start, P - Start);
    Need(Length(Token) > 0, 'порожній елемент форми');
    Tokens[Count] := Token;
    Inc(Count);
  end;
  Need(Closed, 'форма не закрита дужкою');
  while (P <= N) and IsBlank(S[P]) do Inc(P);
  Need(P > N, 'після закриваючої дужки є зайвий текст');
  Need(Count = 3, 'форма мусить мати голову і рівно два доданки');
  Need(Tokens[0] = AddHeadText, 'голова мусить бути «додати»');
  Need(ParseLiteral(Tokens[1], LeftDecimal), 'неприпустимий лівий доданок');
  Need(ParseLiteral(Tokens[2], RightDecimal), 'неприпустимий правий доданок');
  Result := True;
end;

{ Точні 12 бітів → знакове 32-бітове машинне безпосереднє значення.
  Жодного десяткового проміжного SENS: біти вже перевірені pinned
  ReadNumericPhysical, тут лише знакове розширення для mov imm32. }
function Immediate12(const Exact: RawByteString): LongInt;
var
  I: SizeInt;
  Unsigned: LongInt;
begin
  Need(Length(Exact) = 12, 'операнд має бути точним D12');
  Unsigned := 0;
  for I := 1 to 12 do begin
    Need(Exact[I] in ['0', '1'], 'пошкоджений двійковий D12');
    Unsigned := Unsigned * 2 + Ord(Exact[I]) - Ord('0');
  end;
  if Exact[1] = '1' then Result := Unsigned - 4096 else Result := Unsigned;
end;

function BuildD12AddDecimalELF(const LeftDecimal,
  RightDecimal: RawByteString): RawByteString;
var
  LeftPhysical, RightPhysical, Expected, Code: RawByteString;
  L, R, Answer: TExplicitNumeric;
  A, B, Machine, I, CodeBytes, LoopAt, JumpAt, Disp: SizeInt;
  Geometry: TELFGeometry;

  procedure Add(const Bytes: RawByteString);
  begin
    Code := Code + Bytes;
    Need(Length(Code) < 2048, 'неприпустима довжина машинного коду');
  end;

  procedure Add32(V: LongWord);
  var
    K: SizeInt;
  begin
    for K := 0 to 3 do begin
      Add(AnsiChar(V and $FF));
      V := V shr 8;
    end;
  end;

  procedure Put(Off: SizeInt; V: QWord; Count: SizeInt);
  var
    K: SizeInt;
  begin
    Need((Off >= 0) and (Count > 0) and (Count <= 8) and
      (Off <= Length(Result) - Count), 'ELF поле поза довжиною');
    for K := 0 to Count - 1 do begin
      Result[Off + K + 1] := AnsiChar(Byte(V and $FF));
      V := V shr 8;
    end;
  end;

begin
  Result := '';
  Code := '';
  { Єдине джерело числової механіки — наявні pinned module gates. }
  LeftPhysical := EncodeNumericDecimal(LeftDecimal, 12);
  RightPhysical := EncodeNumericDecimal(RightDecimal, 12);
  L := ReadNumericPhysical(LeftPhysical, 12);
  R := ReadNumericPhysical(RightPhysical, 12);
  Expected := AddNumericPhysical(LeftPhysical, RightPhysical, 12);
  try
    Answer := ReadNumericPhysical(Expected, 12);
  except
    on E: Exception do
      raise EDesiatkaError.Create(
        'D12→D24 потребує іншого backend: ' + E.Message);
  end;
  A := Immediate12(L.ExactBits);
  B := Immediate12(R.ExactBits);
  { Знакова 12-бітова сума, яку виконає машина. Вона мусить збігатися
    з pinned законом ДО emission — інакше ELF не будується. }
  Machine := (A + B) and $FFF;
  if Machine >= 2048 then Machine := Machine - 4096;
  Need(Immediate12(Answer.ExactBits) = Machine,
    'машинна сума розійшлася з pinned законом додавання');

  { mov eax,L; mov ebx,R; add eax,ebx; shl/sar 20 — точна 12-бітова
    знакова сума в EAX. Далі сума сама стає десятковими цифрами:
    ділення на 10 у циклі, мінус перед цифрами, один sys_write. }
  Add(#$B8); Add32(LongWord(A));
  Add(#$BB); Add32(LongWord(B));
  Need(Length(Code) = D12DesiatkaAddOpcodeAt,
    'змінився зсув опкоду add');
  Add(#$01#$D8);
  Add(#$C1#$E0#$14);
  Add(#$C1#$F8#$14);
  Add(#$89#$C1);
  Add(#$F7#$D9);
  Add(#$85#$C0);
  Add(#$0F#$48#$C1);
  Add(#$41#$0F#$9C#$C2);
  Add(#$45#$0F#$B6#$D2);
  Add(#$48#$83#$EC#$20);
  Add(#$C6#$44#$24#$1F#$0A);
  Add(#$4C#$8D#$44#$24#$1F);
  Add(#$B9#$0A#$00#$00#$00);
  LoopAt := Length(Code);
  Add(#$31#$D2);
  Add(#$F7#$F1);
  Add(#$80#$C2#$30);
  Add(#$49#$FF#$C8);
  Add(#$41#$88#$10);
  Add(#$85#$C0);
  JumpAt := Length(Code);
  Add(#$75);
  Disp := LoopAt - (JumpAt + 2);
  Add(AnsiChar(Byte(Disp and $FF)));
  Add(#$45#$85#$D2);
  JumpAt := Length(Code);
  Add(#$74);
  Add(#$00);                       { disp8 патчимо нижче }
  Add(#$49#$FF#$C8);
  Add(#$41#$C6#$00#$2D);
  Code[JumpAt + 2] := AnsiChar(Byte(Length(Code) - (JumpAt + 2)));
  Add(#$4C#$89#$C6);
  Add(#$48#$8D#$44#$24#$20);
  Add(#$4C#$29#$C0);
  Add(#$48#$89#$C2);
  Add(#$B8#$01#$00#$00#$00);
  Add(#$BF#$01#$00#$00#$00);
  Add(#$0F#$05);
  { G6.223: для десяткового stdout довжина в RDX = 2..6;
    Linux sys_write повертає в RAX кількість байтів або -errno.
    Linux x86-64 syscall зберігає RDX (clobber лише RCX/R11).
    Partial write, -EBADF, -ENOSPC не означають SENS-успіх.
    Вхідні managed D12 T5M власні для FPC builder, а процес ELF
    використовує приватний стек і не зберігає текстових законів.
    Питання: 1) Чому порівнюємо два регістри, не число 3?
    2) Чому RCX непридатний після syscall?
    3) Чому host exit=2 не є D1?
    4) Хто допускає точну числову ширину?
    5) Як довести короткий запис і відновлення? }
  Add(#$48#$39#$D0);              { cmp rax,rdx: записати всі байти }
  Add(#$75#$09);                  { jne +9 -> exit(2) }
  Add(#$B8#$3C#$00#$00#$00);      { exit(0): тільки повний stdout }
  Add(#$31#$FF);
  Add(#$0F#$05);
  Add(#$B8#$3C#$00#$00#$00);      { exit(2): host write failure }
  Add(#$BF#$02#$00#$00#$00);
  Add(#$0F#$05);
  CodeBytes := Length(Code);

  SetLength(Result, D12DesiatkaHeaderBytes + CodeBytes);
  FillChar(Result[1], Length(Result), 0);
  { PIE ELF64, одна RX PT_LOAD від нульового file offset, адреси
    лише RIP-relative або регістрові. RW-стек надає Linux. }
  Put(0, $464C457F, 4);
  Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
  Put(16, 3, 2); Put(18, 62, 2); Put(20, 1, 4);
  Put(24, D12DesiatkaHeaderBytes, 8); Put(32, 64, 8);
  Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
  Put(64, 1, 4); Put(68, 5, 4);
  Put(80, 0, 8); Put(88, 0, 8);
  Put(96, Length(Result), 8); Put(104, Length(Result), 8);
  Put(112, $1000, 8);
  for I := 1 to CodeBytes do
    Result[D12DesiatkaHeaderBytes + I] := Code[I];
  VerifySENSELF64(Result, Geometry);
  Need((Geometry.Kind = 3) and (Geometry.FileBytes = Length(Result)) and
    (Geometry.MachineBytes = CodeBytes),
    'непідтверджена геометрія нативного ELF64');
  { Останній локальний доказ: у фізичному образі справді лежить add. }
  Need(Byte(Result[D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt + 1]) =
      D12DesiatkaAddOpcodeLo, 'у образі немає опкоду add (lo)');
  Need(Byte(Result[D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt + 2]) =
      D12DesiatkaAddOpcodeHi, 'у образі немає опкоду add (hi)');
end;

end.
