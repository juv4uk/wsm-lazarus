{ G6.93 — нативний рекурсивний fib: збірка ELF із точного D24 `.sens`
  і звірка виходу з НЕЗАЛЕЖНИМ оракулом. Негативні випадки: відʼємний,
  завеликий і не-D24 аргумент — явна відмова, без часткового образу. }
program test_elffib;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.elffib;

var
  Failures: SizeInt = 0;
  Checks: SizeInt = 0;

procedure Check(Ok: Boolean; const Why: String);
begin
  Inc(Checks);
  if Ok then Writeln('ELFFIB-OK   ', Why)
  else begin Writeln('ELFFIB-ЗБІЙ ', Why); Inc(Failures); end;
end;

function D24(Value: LongWord): RawByteString;
var
  Bits: String;
  I: SizeInt;
begin
  SetLength(Bits, 24);
  for I := 1 to 24 do
    if (Value and (LongWord(1) shl (24 - I))) <> 0 then Bits[I] := '1'
    else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

{ Image — позичені байти вже зібраного ELF64; ExitCode — код Linux exit,
  а НЕ логічне значення D1. Для fib коректні коди включають ненульові.
  GetTempFileName атомарно створює окремий host-файл; try/finally
  прибирає його навіть при збої запису, chmod або запуску.
  1) Чому тут не можна вимагати exit=0?
  2) Чому випадкове ім'я з fmCreate може перезаписати чужий файл?
  3) Хто володіє Image і коли звільняється Stream?
  4) Чому файл видаляємо також після винятку?
  5) Чому exit(low8) не є фізичним T5M результатом SENS? }
function RunELF(const Image: RawByteString; out ExitCode: SizeInt): Boolean;
var
  Path: String;
  Stream: TFileStream;
  Status: LongInt;
begin
  Result := False;
  ExitCode := -1;
  { Справжній Linux runner; /tmp — контрольований шлях без shell-метасимволів. }
  Path := GetTempFileName('/tmp/', 'sfb');
  if Path = '' then Exit;
  try
    Stream := TFileStream.Create(Path, fmCreate);
    try
      if Length(Image) > 0 then
        Stream.WriteBuffer(Image[1], Length(Image));
    finally
      Stream.Free;
    end;
    if fpChmod(Path, &755) <> 0 then Exit;
    Status := fpSystem(PChar(Path));
    if WIFEXITED(Status) then begin
      ExitCode := WEXITSTATUS(Status);
      Result := True;
    end;
  finally
    DeleteFile(Path);
  end;
end;

procedure Positive(const N: LongWord);
var
  Image: RawByteString;
  Words: TExactWords;
  Code: SizeInt;
  Expected: QWord;
  Ok: Boolean;
begin
  SetLength(Words, 1);
  Words[0] := D24(N);
  Image := BuildD24FibELF(EncodeT5M(Words));
  Expected := FibOracle(N) and 255;
  { G6.204: незалежний свідок конкретних машинних байтів _start.
    Емуляція Linux status=low8 сама не виявить хибного AND imm8=-1.
    ELF header=120 байтів; інструкція починається на code offset=12.
    Тут перевіряємо лише host ABI, не ратифікуємо новий закон SENS.
    1) Чому exit=201 не доводить правильність AND?
    2) Як x86-64 sign-extends imm8 в opcode 83?
    3) Чому movzx edi,al занулює вищі 24 біти?
    4) Чому три байти зберігають relative call/jl offsets? }
  if N = 35 then begin
    Ok := Length(Image) >= 135;
    if Ok then
      Ok := (Image[133] = #$0F) and
            (Image[134] = #$B6) and (Image[135] = #$F8);
    Check(Ok, 'ELF _start: MOVZX EDI, AL реально маскує low8');
  end;
  Ok := RunELF(Image, Code);
  Check(Ok and (QWord(Code) = Expected),
    'fib(' + IntToStr(N) + ') native=' + IntToStr(Code) +
    ' oracle=' + IntToStr(Expected));
end;

procedure Negative(const Value: LongWord; const Why: String);
var
  Words: TExactWords;
  Refused: Boolean;
begin
  SetLength(Words, 1);
  Words[0] := D24(Value);
  Refused := False;
  try
    BuildD24FibELF(EncodeT5M(Words));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, Why);
end;

{ Запозичені фізичні байти мають пройти саме pinned D24/T5M admission;
  не-Д24, зайві слова й обірвані кадри не стають host fib-функціями.
  1) Чому довжина слова визначає домен?
  2) Чому два слова не можна тихо прийняти як одне?
  3) Чому T5M — фізичне джерело, а не текстова проєкція?
  4) Хто гарантує відсутність часткового ELF після винятку? }
procedure NegativePhysical(const Physical: RawByteString; const Why: String);
var
  Refused: Boolean;
begin
  Refused := False;
  try
    BuildD24FibELF(Physical);
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, Why);
end;

var
  Words: TExactWords;
  Refused: Boolean;
begin
  { Незалежні host-константи не дозволяють непомітно зіпсувати
    використаний у всіх десяти виконаннях математичний оракул. }
  Check(FibOracle(30) = 832040, 'host fib(30) = 832040');
  Check(FibOracle(35) = 9227465, 'host fib(35) = 9227465');
  Positive(0);
  Positive(1);
  Positive(2);
  Positive(3);
  Positive(10);
  Positive(15);
  Positive(20);
  Positive(25);
  Positive(30);
  Positive(35);

  Negative($800000, 'negative D24 refused');
  Negative(36, 'n beyond host limit refused');

  NegativePhysical('', 'порожній фізичний T5M відхилено');
  NegativePhysical(#0, 'обірваний фізичний T5M відхилено');
  SetLength(Words, 1);
  Words[0] := D24(1);
  NegativePhysical(EncodeT5M(Words) + #0,
    'зайвий фізичний хвіст T5M відхилено');
  SetLength(Words, 2);
  Words[0] := D24(1);
  Words[1] := D24(2);
  NegativePhysical(EncodeT5M(Words), 'два D24-атоми замість одного відхилено');

  SetLength(Words, 1);
  Words[0] := '000000000001';
  Refused := False;
  try
    BuildD24FibELF(EncodeT5M(Words));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, 'non-D24 argument refused');

  if Failures > 0 then begin
    Writeln('ELFFIB-FAIL');
    Halt(1);
  end;
  Writeln('ELFFIB-PASS checks=', Checks);
  Writeln('ELFFIB-LIMIT=host-fib-body-not-sens-lowering-no-GC-no-REPL');
end.
