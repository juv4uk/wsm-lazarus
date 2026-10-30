{ G6.93 — нативний РЕКУРСИВНИЙ `fib` для енергобенчмарків.
  Один точно допущений фізичний D24 `.sens` стає нативною програмою
  x86-64: fib(n) обчислюється рекурсивно на СПРАВЖНЬОМУ стеку, тому
  межа інтерпретатора (глибина 32) тут не діє.

  Що тут НАЛЕЖИТЬ SENS: сама D24-константа n, допущена чинним
  ReadNumericPhysical — той самий шлях, що й у злитих numeric-механізмах.
  Що тут НЕ належить SENS: спосіб обчислення (рекурсія на стеку) і
  вихід через exit(low8) — це ЯВНО оголошений host-механізм навантаження.
  Результат НЕ оголошується SENS-значенням: він звіряється з незалежним
  оракулом як число.

  Це НЕ повний компілятор: немає регістрового розподілу, IR-lowering
  довільних форм, GC чи REPL. Тіло fib тут — host-код навантаження,
  а не трансляція довільного тіла SENS. }
unit wsm.elffib;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  EELFFibError = class(Exception);

const
  { Межа host-навантаження: n = 0..35. Це ресурс стеку й часу, не закон.
    fib(35) = 9227465, а exit(low8) дає 9227465 and 255 = 201. }
  MinFibCount = 0;
  MaxFibCount = 35;

{ CountPhysical — позичені packed T5M байти одного D24-атома (драбина
  доменів: D24 тримає до 8388607). n приходить ІЗ `.sens`, а не з
  host-аргументу — це дає artifact provenance для бенчмарків.
  Результат — новий ELF64 ET_EXEC; на відмові жодного часткового образу. }
function BuildD24FibELF(const CountPhysical: RawByteString): RawByteString;

{ Той самий оракул, що й у тесті: fib(n) для n ≥ 0 (QWord-точний). }
function FibOracle(N: LongWord): QWord;

implementation
uses wsm.numericplane;

const
  ELFBase = $400000;
  HeaderBytes = 64 + 56;      { ELF64 заголовок + один PT_LOAD }
  D24Width = 24;

  { Код: 61 байт. Зсуви пораховані вручну й перевірені тестом:
    _start (0) викликає fib, кладе результат у exit(low8);
    fib (22) — рекурсивне обчислення на стеку. }
  CodeSize = 61;
  FileSize = HeaderBytes + CodeSize;

  FibOffset = 22;             { початок fib }
  BaseOffset = 58;            { база рекурсії }
  StartCallAt = 5;            { зсув байта E8 у _start }
  StartCallEnd = 10;          { зсув після call у _start }
  Recurse1At = 31;            { зсув байта E8 першого самовиклику }
  Recurse1End = 36;
  Recurse2At = 45;            { зсув байта E8 другого самовиклику }
  Recurse2End = 50;
  JlAt = 25;                  { зсув байта 7C }
  JlEnd = 27;

function UkrBytes(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Need(Ok: Boolean; const Why: UnicodeString);
begin
  if not Ok then raise EELFFibError.Create(UkrBytes(Why));
end;

function FibOracle(N: LongWord): QWord;
var
  A, B, T: QWord;
  I: LongWord;
begin
  A := 0; B := 1;
  for I := 1 to N do begin
    T := A + B;
    A := B;
    B := T;
  end;
  Result := A;
end;

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
      raise EELFFibError.Create(
        UkrBytes('фізичний D24-аргумент не допущено: ') + E.Message);
  end;
  Need(Number.DomainWidth = D24Width,
    'аргумент fib має бути двадцять четвертого домену');
  Bits := Number.ExactBits;
  Need(Length(Bits) = D24Width, 'точний D24 мусить мати рівно 24 біти');
  Unsigned := 0;
  for I := 1 to D24Width do begin
    Need((Bits[I] = '0') or (Bits[I] = '1'), 'D24 містить не двійковий знак');
    Unsigned := (Unsigned shl 1) or LongWord(Ord(Bits[I]) - Ord('0'));
  end;
  Negative := (Unsigned and (LongWord(1) shl (D24Width - 1))) <> 0;
  Need(not Negative, 'аргумент fib не може бути відʼємним');
  Need(Unsigned >= MinFibCount, 'аргумент fib поза host-межею знизу');
  Need(Unsigned <= MaxFibCount, 'аргумент fib поза host-межею зверху');
  Result := Unsigned;
end;

function BuildD24FibELF(const CountPhysical: RawByteString): RawByteString;
var
  Count: LongWord;
  Code: array[0..CodeSize - 1] of Byte;
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

  procedure EmitRel32(At: SizeInt; Target, AfterAt: SizeInt);
  var
    Delta: LongInt;
  begin
    Delta := LongInt(Target - AfterAt);
    Emit(At, [Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
      Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
  end;

begin
  Result := '';
  Count := AdmitCount(CountPhysical);
  for I := 0 to CodeSize - 1 do Code[I] := $90; { NOP: жодного нуля-пастки }

  { _start: exit(low8(fib(n))) — 22 байти. }
  Emit(0, [$BF, Byte(Count), Byte(Count shr 8),
    Byte(Count shr 16), Byte(Count shr 24)]);        { mov edi, n        }
  Emit(StartCallAt, [$E8]);                          { call fib         }
  EmitRel32(StartCallAt + 1, FibOffset, StartCallEnd);
  Emit(10, [$89, $C7]);                              { mov edi, eax     }
  { MOVZX EDI,AL — справжнє занулення всіх бітів вище молодших 8.
    83 E7 FF НЕ підходить: imm8 sign-extends до -1; AND нічого не маскує.
    Рівно три байти зберігають усі offsets call/jl і ELF64 геометрію.
    Це host Linux exit ABI, а не числовий закон чи opcode SENS. }
  Emit(12, [$0F, $B6, $F8]);                         { movzx edi, al    }
  Emit(15, [$B8, $3C, $00, $00, $00]);               { mov eax, 60      }
  Emit(20, [$0F, $05]);                              { syscall          }

  { fib: рекурсія на справжньому стеку. }
  Emit(FibOffset, [$83, $FF, $02]);                  { cmp edi, 2       }
  Emit(JlAt, [$7C, Byte(BaseOffset - JlEnd)]);       { jl base          }
  Emit(27, [$57]);                                   { push rdi         }
  Emit(28, [$48, $FF, $CF]);                         { dec rdi          }
  Emit(Recurse1At, [$E8]);                           { call fib         }
  EmitRel32(Recurse1At + 1, FibOffset, Recurse1End);
  Emit(36, [$50]);                                   { push rax         }
  Emit(37, [$48, $8B, $7C, $24, $08]);               { mov rdi,[rsp+8]  }
  Emit(42, [$83, $EF, $02]);                         { sub edi, 2       }
  Emit(Recurse2At, [$E8]);                           { call fib         }
  EmitRel32(Recurse2At + 1, FibOffset, Recurse2End);
  Emit(50, [$59]);                                   { pop rcx          }
  Emit(51, [$01, $C8]);                              { add eax, ecx     }
  Emit(53, [$48, $83, $C4, $08]);                    { add rsp, 8       }
  Emit(57, [$C3]);                                   { ret              }
  Emit(BaseOffset, [$89, $F8]);                      { mov eax, edi     }
  Emit(60, [$C3]);                                   { ret              }

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

  for I := 0 to CodeSize - 1 do
    Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
end;

end.
