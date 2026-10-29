{ G6.107: повторно використовуваний механізм локального CALL/RET x86-64.
  Мовних доменів, законів та українських проєкцій тут немає.
  Вхід і вихід: TX64Code з власним RawByteString; фізичні зміщення
  0-based у байтах host machine, не в тритах або словах SENS.
  Відмова не змінює буфер і не публікує часткового ELF.

  Питання: 1) Чому CALL rel32 відлічує адресу від КІНЦЯ команди?
  2) Чому fixup не можна застосувати двічі?
  3) Навіщо окремо перевіряються opcode та порожні чотири байти?
  4) Чому стек/ABI caller-а не визначаються цією одиницею?
  5) Хто володіє Code.Bytes після повернення процедури? }
unit wsm.x64call;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64EmitLocalCall(var Code:TX64Code;out DispOffset:SizeInt);
procedure X64PatchLocalCall(var Code:TX64Code;DispOffset,TargetOffset:SizeInt);
procedure X64Return(var Code:TX64Code);
implementation
const MaxMachineBytes=256;

procedure Require(Good:Boolean;const Why:String);
begin
  if not Good then raise EX64CodeError.Create(Why);
end;

{ Параметр Code — managed buffer caller; DispOffset після успіху є
  0-based адресою ПЕРШОГО байта 32-бітного зміщення. Помилки перед
  дописуванням зберігають Code.Bytes і DispOffset=-1. }
procedure X64EmitLocalCall(var Code:TX64Code;out DispOffset:SizeInt);
var Existing:SizeInt;
begin
  DispOffset:=-1;
  Existing:=Length(Code.Bytes);
  Require(Existing<=MaxMachineBytes-5,
    'CALL: перевищено машинну квоту 256 байтів');
  Code.Bytes:=Code.Bytes+#$E8#0#0#0#0;
  DispOffset:=Existing+1;
end;

{ Адреса цілі є 0-based позицією в тому самому вже випущеному Code.
  Підстановка відбувається у копії; тільки повністю перевірений
  кандидат повертається caller. rel32 має signed little-endian вигляд.
  Нульове зміщення заборонене, щоб не замаскувати незв'язану ціль. }
procedure X64PatchLocalCall(var Code:TX64Code;DispOffset,TargetOffset:SizeInt);
var N,I:SizeInt;Delta:Int64;Encoded:QWord;Candidate:RawByteString;
begin
  N:=Length(Code.Bytes);
  Require((N>=5) and (N<=MaxMachineBytes) and
          (DispOffset>=1) and (DispOffset<=N-4),
    'CALL: адреса підстановки за межами коду');
  Require(Copy(Code.Bytes,DispOffset,1)=#$E8,
    'CALL: відсутній відповідний opcode E8');
  Require(Copy(Code.Bytes,DispOffset+1,4)=#0#0#0#0,
    'CALL: підстановка вже виконана або пошкоджений заповнювач');
  Require((TargetOffset>=0) and (TargetOffset<N),
    'CALL: ціль поза випущеним машинним кодом');
  Delta:=Int64(TargetOffset)-Int64(DispOffset+4);
  Require((Delta<>0) and (Delta>=Low(LongInt)) and
          (Delta<=High(LongInt)),
    'CALL: недопустиме signed rel32 зміщення');
  Encoded:=QWord(Delta) and $FFFFFFFF;
  Candidate:=Copy(Code.Bytes,1,N);
  for I:=0 to 3 do begin
    Candidate[DispOffset+I+1]:=AnsiChar(Byte(Encoded and $FF));
    Encoded:=Encoded shr 8;
  end;
  Code.Bytes:=Candidate;
end;

{ Лише host x86-64 RET near, один байт C3. Correct stack layout
  забезпечує caller, а не цей emitter. За квотою — атомарна відмова. }
procedure X64Return(var Code:TX64Code);
begin
  Require(Length(Code.Bytes)<MaxMachineBytes,
    'RET: перевищено машинну квоту 256 байтів');
  Code.Bytes:=Code.Bytes+#$C3;
end;
end.
