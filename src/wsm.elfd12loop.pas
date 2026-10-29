{ G6.73 — перший нативний ЦИКЛ НАВАНТАЖЕННЯ для чесних енергобенчмарків.
  Один точно допущений фізичний D12 `.sens` стає машинним циклом
  x86-64: N разів `add eax, K`, завершення через `exit(low8)`.

  Що тут НАЛЕЖИТЬ SENS: сама D12-константа, допущена чинним
  ReadNumericPhysical (той самий шлях, що в злитому wsm.elfd12add),
  і її 12-бітне знакове розширення (той самий механізм).
  Що тут НЕ належить SENS: кількість ітерацій N і 64-бітний акумулятор —
  це ЯВНО оголошені host-параметри навантаження. Результат циклу
  НЕ оголошується SENS-значенням і не порівнюється з ним для великих N.

  Це НЕ повний компілятор: немає регістрового розподілу, IR-lowering
  довільних форм, D12→D24 переповнення, GC чи REPL. }
unit wsm.elfd12loop;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  EELFD12LoopError = class(Exception);

const
  { Межа host-навантаження: 1..10^9 ітерацій. Це ресурс хоста, не закон. }
  MinLoopCount = 1;
  MaxLoopCount = 1000000000;

{ Physical — позичені канонічні packed T5M байти одного D12-атома.
  AuthorityRoot — позичений шлях до pinned external/sens.
  Iterations — host-параметр навантаження.
  Результат — новий ELF64 ET_EXEC; жодного часткового образу на відмові. }
function BuildD12LoopELF(const Physical: RawByteString;
  Iterations: LongWord): RawByteString;

{ G6.80 — workload `loop` із pinned methodology: сума 0..N.
  CountPhysical — позичені packed T5M байти одного D24-атома (драбина
  доменів: D24 тримає до 8388607 ітерацій). N приходить ІЗ `.sens`,
  а не з host-аргументу; це дає artifact provenance для бенчмарків. }
function BuildD12SumLoopELF(const CountPhysical: RawByteString): RawByteString;

implementation
uses wsm.numericplane;

const
  ELFBase = $400000;
  HeaderBytes = 64 + 56;      { ELF64 заголовок + один PT_LOAD }
  CodeSize = 31;
  FileSize = HeaderBytes + CodeSize;
  D12Width = 12;
  D24Width = 24;
  SumCodeSize = 28;
  SumFileSize = HeaderBytes + SumCodeSize;

function UkrBytes(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Need(Ok: Boolean; const Why: UnicodeString);
begin
  if not Ok then raise EELFD12LoopError.Create(UkrBytes(Why));
end;

{ 12 точних бітів → signed 32-bit imm для `add eax, imm32`.
  Доповняльний код: старший біт 1 означає відʼємне значення.
  Жодного десяткового проміжного подання і жодної оцінки за довжиною.
  Питання: чому 12, а не 16 бітів? Чому розширення знакове?
  Чому це той самий механізм, що в wsm.elfd12add? }
function Immediate12(const Bits: RawByteString): LongWord;
var
  I: SizeInt;
  Unsigned: LongWord;
begin
  Need(Length(Bits) = D12Width, 'операнд має бути точним D12');
  Unsigned := 0;
  for I := 1 to D12Width do begin
    Need((Bits[I] = '0') or (Bits[I] = '1'), 'D12 містить не двійковий знак');
    Unsigned := (Unsigned shl 1) or LongWord(Ord(Bits[I]) - Ord('0'));
  end;
  if (Unsigned and (LongWord(1) shl (D12Width - 1))) <> 0 then
    Unsigned := Unsigned or $FFFFF000; { знакове розширення до 32 біт }
  Result := Unsigned;
end;

{ Physical: позичені канонічні packed T5M байти одного атома.
  Допуск робить ТОЙ САМИЙ чинний числовий механізм, що й у злитому
  wsm.elfd12add: ReadNumericPhysical(...,12). Жодного другого reader-а,
  жодного виведення домену з ширини чи десяткового подання.
  Питання: чому рівно D12? Хто звільняє тимчасові слова?
  Чому ExactBits зберігає провідні нулі? }
function AdmitD12(const Physical: RawByteString): RawByteString;
var
  Number: TExplicitNumeric;
begin
  try
    Number := ReadNumericPhysical(Physical, D12Width);
  except
    on E: Exception do
      raise EELFD12LoopError.Create(
        UkrBytes('фізичний D12 не допущено: ') + E.Message);
  end;
  Need(Number.DomainWidth = D12Width, 'допущено не дванадцятий домен');
  Need(Length(Number.ExactBits) = D12Width,
    'точний D12 мусить мати рівно дванадцять бітів');
  Result := Number.ExactBits;
end;

function BuildD12LoopELF(const Physical: RawByteString;
  Iterations: LongWord): RawByteString;
var
  Bits: RawByteString;
  Immediate: LongWord;
  Code: array[0..CodeSize - 1] of Byte;
  I: SizeInt;

  procedure Put(Offset: SizeInt; Number: QWord; Count: SizeInt);
  var
    K: SizeInt;
  begin
    for K := 0 to Count - 1 do begin
      Result[Offset + K + 1] := AnsiChar(Byte(Number and $FF));
      Number := Number shr 8;
    end;
  end;

  procedure Emit(At: SizeInt; const Bytes: array of Byte);
  var
    K: SizeInt;
  begin
    for K := 0 to High(Bytes) do Code[At + K] := Bytes[K];
  end;

begin
  Result := '';
  Need(Iterations >= MinLoopCount, 'кількість ітерацій мусить бути ≥ 1');
  Need(Iterations <= MaxLoopCount, 'кількість ітерацій поза host-межею');
  Bits := AdmitD12(Physical);
  Immediate := Immediate12(Bits);

  { mov eax,0                     B8 00000000
    mov ecx,N                     B9 NNNNNNNN
    L: add eax,K                  05 KKKKKKKK
       dec ecx                    FF C9
       jnz L                      75 F7      (ціль — зсув 10 від 19)
    mov edi,eax                   89 C7
    and edi,255                   83 E7 FF
    mov eax,60                    B8 3C000000
    syscall                       0F 05 }
  Emit(0, [$B8, $00, $00, $00, $00]);
  Emit(5, [$B9, Byte(Iterations), Byte(Iterations shr 8),
    Byte(Iterations shr 16), Byte(Iterations shr 24)]);
  Emit(10, [$05, Byte(Immediate), Byte(Immediate shr 8),
    Byte(Immediate shr 16), Byte(Immediate shr 24)]);
  Emit(15, [$FF, $C9]);
  Emit(17, [$75, $F7]);
  Emit(19, [$89, $C7]);
  Emit(21, [$83, $E7, $FF]);
  Emit(24, [$B8, $3C, $00, $00, $00]);
  Emit(29, [$0F, $05]);

  SetLength(Result, FileSize);
  for I := 1 to Length(Result) do Result[I] := #0;

  { ELF64: ELFCLASS64, little-endian, ET_EXEC, EM_X86_64, entry=0x400078. }
  Put(0, $464C457F, 4);
  Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
  Put(16, 2, 2); Put(18, 62, 2); Put(20, 1, 4);
  Put(24, ELFBase + HeaderBytes, 8);
  Put(32, 64, 8);
  Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
  { Один PT_LOAD RX на весь образ. }
  Put(64, 1, 4); Put(68, 5, 4);
  Put(80, ELFBase, 8); Put(88, ELFBase, 8);
  Put(96, FileSize, 8); Put(104, FileSize, 8); Put(112, $1000, 8);

  for I := 0 to CodeSize - 1 do
    Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
end;


{ D24-лічильник: 24 точні біти доповняльного коду → значення 1..MaxLoopCount.
  Питання: чому саме D24, а не D12? Чому нуль і відʼємне — відмова?
  Чому значення не стає SENS-числом, а лише host-лічильником циклу? }
function AdmitCount(const CountPhysical: RawByteString): LongWord;
var
  Number: TExplicitNumeric;
  Bits: RawByteString;
  I: SizeInt;
  Unsigned: LongWord;
  Negative: Boolean;
begin
  try
    Number := ReadNumericPhysical(CountPhysical, D24Width);
  except
    on E: Exception do
      raise EELFD12LoopError.Create(
        UkrBytes('фізичний D24-лічильник не допущено: ') + E.Message);
  end;
  Need(Number.DomainWidth = D24Width, 'лічильник має бути двадцять четвертого домену');
  Bits := Number.ExactBits;
  Need(Length(Bits) = D24Width, 'точний D24 мусить мати рівно 24 біти');
  Unsigned := 0;
  for I := 1 to D24Width do begin
    Need((Bits[I] = '0') or (Bits[I] = '1'), 'D24 містить не двійковий знак');
    Unsigned := (Unsigned shl 1) or LongWord(Ord(Bits[I]) - Ord('0'));
  end;
  Negative := (Unsigned and (LongWord(1) shl (D24Width - 1))) <> 0;
  Need(not Negative, 'лічильник не може бути відʼємним');
  Need(Unsigned >= MinLoopCount, 'кількість ітерацій мусить бути ≥ 1');
  Need(Unsigned <= MaxLoopCount, 'кількість ітерацій поза host-межею');
  Result := Unsigned;
end;

function BuildD12SumLoopELF(const CountPhysical: RawByteString): RawByteString;
var
  Count: LongWord;
  Code: array[0..SumCodeSize - 1] of Byte;
  I: SizeInt;

  procedure Put(Offset: SizeInt; Number: QWord; Width: SizeInt);
  var
    K: SizeInt;
  begin
    for K := 0 to Width - 1 do begin
      Result[Offset + K + 1] := AnsiChar(Byte(Number and $FF));
      Number := Number shr 8;
    end;
  end;

  procedure Emit(At: SizeInt; const Bytes: array of Byte);
  var
    K: SizeInt;
  begin
    for K := 0 to High(Bytes) do Code[At + K] := Bytes[K];
  end;

begin
  Result := '';
  Count := AdmitCount(CountPhysical);

  { Той самий цикл, що й у C/Rust/FPC-близнюків:
    s=0; for(i=N;i>0;i--) s+=i;
    mov eax,0                  B8 00000000
    mov ecx,N                  B9 NNNNNNNN
    L: add eax,ecx             01 C8
       dec ecx                 FF C9
       jnz L                   75 FA      (ціль — зсув 10 від 16)
    mov edi,eax                89 C7
    and edi,255                83 E7 FF
    mov eax,60                 B8 3C000000
    syscall                    0F 05 }
  Emit(0, [$B8, $00, $00, $00, $00]);
  Emit(5, [$B9, Byte(Count), Byte(Count shr 8),
    Byte(Count shr 16), Byte(Count shr 24)]);
  Emit(10, [$01, $C8]);
  Emit(12, [$FF, $C9]);
  Emit(14, [$75, $FA]);
  Emit(16, [$89, $C7]);
  Emit(18, [$83, $E7, $FF]);
  Emit(21, [$B8, $3C, $00, $00, $00]);
  Emit(26, [$0F, $05]);

  SetLength(Result, SumFileSize);
  for I := 1 to Length(Result) do Result[I] := #0;

  Put(0, $464C457F, 4);
  Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
  Put(16, 2, 2); Put(18, 62, 2); Put(20, 1, 4);
  Put(24, ELFBase + HeaderBytes, 8);
  Put(32, 64, 8);
  Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
  Put(64, 1, 4); Put(68, 5, 4);
  Put(80, ELFBase, 8); Put(88, ELFBase, 8);
  Put(96, SumFileSize, 8); Put(104, SumFileSize, 8); Put(112, $1000, 8);

  for I := 0 to SumCodeSize - 1 do
    Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
end;

end.
