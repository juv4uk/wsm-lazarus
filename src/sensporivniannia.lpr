{ G1.37 — механічне порівняння ДВОХ канонічних фізичних T5M-файлів.
  Не визначає домен за шириною Wn, не виконує SENS та не проєктує .lisp.
  Всі слова декодує тільки наявний wsm.t5m, без другого читача. }
program sensporivniannia;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m;

type EPhysicalCompare = class(Exception);

function ReadPhysical(const FileName: String): RawByteString;
var F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
      raise EPhysicalCompare.Create('порожній або завеликий фізичний файл');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

function ViewWord(const WordBits: RawByteString): String;
const MaxVisibleBits = 64;
begin
  if Length(WordBits) <= MaxVisibleBits then
    Result := String(WordBits)
  else
    Result := String(Copy(WordBits, 1, MaxVisibleBits)) +
      '…[показано лише перші 64 біти]';
end;

function WordInfo(const Words: TExactWords; Index: SizeInt): String;
begin
  if Index >= Length(Words) then
    Exit('відсутнє');
  Result := 'W' + IntToStr(Length(Words[Index])) +
    ': ' + ViewWord(Words[Index]);
end;

function FirstDifferentByte(const First, Second: RawByteString): SizeInt;
var I, Common: SizeInt;
begin
  Common := Length(First);
  if Length(Second) < Common then Common := Length(Second);
  I := 1;
  while (I <= Common) and (First[I] = Second[I]) do Inc(I);
  Result := I - 1; { 0-based, також коректний EOF-зсув }
end;

function ComparePhysical(const A, B: RawByteString;
  const WA, WB: TExactWords): Integer;
var I, N, ByteOffset: SizeInt;
begin
  { На момент виклику ОБИДВА фізичні входи вже повністю допущені T5M. }
  if A = B then begin
    WriteLn('ТОТОЖНІ фізичні-файли; слів=', Length(WA),
      '; байтів=', Length(A));
    Exit(0);
  end;

  ByteOffset := FirstDifferentByte(A, B);
  N := Length(WA);
  if Length(WB) < N then N := Length(WB);
  I := 0;
  while (I < N) and (WA[I] = WB[I]) do Inc(I);
  WriteLn('ВІДМІННІ фізичні-файли; перший-байт=', ByteOffset,
    '; слів-ліворуч=', Length(WA), '; слів-праворуч=', Length(WB));
  if (I < N) or (Length(WA) <> Length(WB)) then begin
    WriteLn('перше-відмінне-слово=', I + 1);
    WriteLn('ліворуч=', WordInfo(WA, I));
    WriteLn('праворуч=', WordInfo(WB, I));
  end else
    WriteLn('точні-слова-однакові; відрізняються фізичні байти');
  WriteLn('Домен не встановлюється за Wn; мовний паритет не перевірявся.');
  Result := 1;
end;

var
  PA, PB: RawByteString;
  WA, WB: TExactWords;
  Verdict: Integer;
begin
  if ParamCount <> 2 then begin
    WriteLn(StdErr, 'Використання: sensporivniannia перший.sens другий.sens');
    Halt(64);
  end;
  try
    { Два bounded фізичні буфери (кожен <= 4 МіБ); Words — owned
      динамічні масиви exact RawByteString, без запозичених посилань.
      Жодний stdout не з'являється до успішного допуску обох входів. }
    PA := ReadPhysical(ParamStr(1));
    PB := ReadPhysical(ParamStr(2));
    DecodeT5M(PA, WA);
    DecodeT5M(PB, WB);
    Verdict := ComparePhysical(PA, PB, WA, WB);
    Halt(Verdict);
  except
    on E: Exception do begin
      WriteLn(StdErr, 'ФІЗИЧНЕ-ПОРІВНЯННЯ-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.

{ Перевірте розуміння:
  1. Чому рівні біти різних Dn не доводять тотожність законів?
  2. Чому порівнюються саме канонічні фізичні байти?
  3. Навіщо спочатку декодувати ОБИДВА документи до першого stdout?
  4. Коли перший різний байт може бути EOF-зсувом?
  5. Чому D7 та числові D12+ не визначаються цим інструментом? }
