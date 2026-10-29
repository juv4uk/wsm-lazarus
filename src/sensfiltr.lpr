{ G3.38 — канонічний фізичний stdin -> stdout для вже чинного D3 evaluator.
  Тільки один цілісний T5M/D2-корінь; ні REPL, ні Core4, ні текстова проєкція.
  Доменний допуск, закони та виконання — тільки TBinaryExecutor. }
program sensfiltr;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.binaryexec, wsm.t5m;

const ChunkBytes = 16384;
type EFilterError = class(Exception);

function UA(const Text: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(Text));
end;

{ Буфер — власний RawByteString із фізичними байтами (не UTF-8 і не
  числовими значеннями). Used — точна кількість прочитаних байтів,
  Capacity — обсяг алокації. Подвоєння обмежене pinned T5M-лімітом;
  до повернення зайві байти алокації відкидаємо. EOF завершує ОДИН
  фізичний запит; жодного раннього виклику evaluator.
  Питання: чому EOF не є тритом? Навіщо запас місткості?
  Як відкидається завеликий потік? Хто володіє результатом?
  Чому не можна розбирати текстову проєкцію замість цих байтів? }
function ReadPhysicalInput: RawByteString;
var
  Buffer: array[0..ChunkBytes-1] of Byte;
  Used, Capacity, NextCapacity: SizeInt;
  Got: LongInt;
begin
  Result := '';
  Used := 0;
  Capacity := 0;
  repeat
    Got := FileRead(TextRec(Input).Handle, Buffer, SizeOf(Buffer));
    if Got < 0 then
      raise EFilterError.Create(UA('не вдалося прочитати фізичний stdin'));
    if Got = 0 then Break;
    if Used > MAX_T5M_FILE_BYTES - Got then
      raise EFilterError.Create(UA('фізичний stdin перевищує межу T5M'));
    if Used + Got > Capacity then begin
      NextCapacity := Capacity;
      if NextCapacity = 0 then NextCapacity := ChunkBytes;
      while NextCapacity < Used + Got do begin
        if NextCapacity > MAX_T5M_FILE_BYTES div 2 then
          NextCapacity := MAX_T5M_FILE_BYTES
        else
          NextCapacity := NextCapacity * 2;
      end;
      Capacity := NextCapacity;
      SetLength(Result, Capacity);
    end;
    Move(Buffer[0], Result[Used+1], Got);
    Inc(Used, Got);
  until False;
  if Used = 0 then
    raise EFilterError.Create(UA('порожній фізичний stdin'));
  SetLength(Result, Used);
end;

{ Bytes — позичений незмінний T5M результат evaluator; Offset/Sent
  позначають байти файлового дескриптора ОС, не координати SENS.
  Відповідь повністю обчислена ДО першого FileWrite. Втрата каналу
  stdout не відкочується (це host I/O, а не мовна транзакція).
  Питання: коли результат стає доступним? Чому не WriteLn?
  Як обробляється частковий запис? Хто зберігає фізичні нулі?
  Чи дозволяє це обійти exact-domain binder? }
procedure WritePhysicalOutput(const Bytes: RawByteString);
var Offset, Sent: SizeInt;
begin
  if Length(Bytes) = 0 then
    raise EFilterError.Create(UA('порожня фізична відповідь'));
  Offset := 0;
  while Offset < Length(Bytes) do begin
    Sent := FileWrite(TextRec(Output).Handle, Bytes[Offset+1],
      Length(Bytes)-Offset);
    if Sent <= 0 then
      raise EFilterError.Create(UA('помилка фізичного stdout'));
    Inc(Offset, Sent);
  end;
end;

var
  Physical, Answer: RawByteString;
  Engine: TBinaryExecutor;
begin
  if (ParamCount <> 1) or
     (RawByteString(ParamStr(1)) <> UA('--виконати-сенс')) then begin
    WriteLn(StdErr, UA('Використання: sensfiltr --виконати-сенс < програма.sens > відповідь.sens'));
    ExitCode := 64;
  end else begin
    Engine := nil;
    try
      Physical := ReadPhysicalInput;
      Engine := TBinaryExecutor.Create('external/sens');
      { Ніякої власної семантики: точний фізичний допуск і D3 виконання. }
      Answer := Engine.ExecutePhysicalT5M(Physical);
      WritePhysicalOutput(Answer);
    except
      on E: EBinaryExecutionError do begin
        WriteLn(StdErr, UA('ФІЛЬТР-ПОМИЛКА: '), E.Message,
          UA(' слово='), E.WordIndex);
        ExitCode := 2;
      end;
      on E: Exception do begin
        WriteLn(StdErr, UA('ФІЛЬТР-ПОМИЛКА: '), E.Message);
        ExitCode := 2;
      end;
    end;
    Engine.Free;
  end;
end.
