{ G3.36 — пакетне кодування людських десяткових чисел в явному D12+.
  Джерело закону — pinned SENS Contract 12; наявний numericplane
  обчислює точні двійкові слова, а t5m фізично пакує їх.
  Вхідний .lisp є тільки обмеженою українською числовою проєкцією
  (ОДИН десятковий атом на рядок), НЕ загальним синтаксисом SENS.
  Немає арифметики, REPL, диспетчеризації за англійськими назвами. }
program senschyslopakuvaty;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane;

const
  MaxSourceBytes = 131072;
  MaxPhysicalBytes = 65536;
  MaxNumericWords = 1024;

{ Path: позичений шлях файлу ОС. Повертає власний RawByteString
  з максимум MaxSourceBytes фізичних байтів; його час життя керований FPC.
  Питання: чому читаємо файл повністю до stdout? Чому заборонений
  порожній вхід? Чому перевіряємо розмір до алокації? }
function ReadSource(const Path: String): RawByteString;
var F: TFileStream;
begin
  if LowerCase(ExtractFileExt(Path)) <> '.lisp' then
    raise Exception.Create('очікується людська проєкція .lisp');
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size < 1) or (F.Size > MaxSourceBytes) then
      raise Exception.Create('порожній або надто великий файл проєкції');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

{ S: власний незмінюваний буфер UTF-8/ASCII цифр з LF або CRLF.
  Width: явний домен, наданий викликом, не виведений із цифр.
  Результат: власні канонічні паковані байти T5M; жодних часткових
  байтів stdout під час перевірки. Managed words звільняє FPC.
  Питання: чому цифри не визначають домен? Навіщо ReadNumericPhysical
  після EncodeNumericDecimal? Чому ми не обрізаємо пробіли?
  Як зберігається повна ширина та провідні нулі? }
function EncodeLines(const S: RawByteString; Width: SizeInt): RawByteString;
var
  Words: TExactWords;
  Count, StartAt, I, L: SizeInt;
  N: TExplicitNumeric;

  procedure AddDecimal(const Decimal: RawByteString);
  begin
    if (Decimal = '') or (Count >= MaxNumericWords) then
      raise Exception.Create('порожній атом або понад 1024 числові слова');
    { Єдиний наявний допуск числової проєкції: точне слово + домен. }
    N := ReadNumericPhysical(EncodeNumericDecimal(Decimal, Width), Width);
    if (N.DomainWidth <> Width) or (Length(N.ExactBits) <> Width) then
      raise Exception.Create('порушено фізичну числову ширину');
    Words[Count] := N.ExactBits;
    Inc(Count);
  end;

begin
  SetLength(Words, MaxNumericWords);
  Count := 0;
  StartAt := 1;
  for I := 1 to Length(S) do begin
    if S[I] = #10 then begin
      L := I - StartAt;
      if L > 0 then
        if S[I-1] = #13 then Dec(L);
      AddDecimal(Copy(S, StartAt, L));
      StartAt := I + 1;
    end;
  end;
  if StartAt <= Length(S) then
    AddDecimal(Copy(S, StartAt, Length(S)-StartAt+1));
  if Count = 0 then
    raise Exception.Create('не задано жодного числового слова');
  SetLength(Words, Count);
  Result := EncodeT5M(Words);
  if (Length(Result) < 1) or (Length(Result) > MaxPhysicalBytes) then
    raise Exception.Create('надмірний фізичний T5M-пакет');
end;

{ Physical: власний перевірений RawByteString із точними T5M байтами;
  THandleStream запозичує дескриптор stdout і НЕ володіє ним.
  Публікація відбувається лише після успішного повного admission.
  Питання: чому WriteBuffer, а не WriteLn? Що станеться при помилці
  під час validation? Чи дозволяє це неявно виконувати SENS? }
procedure WritePhysical(const Physical: RawByteString);
var H: THandleStream;
begin
  H := THandleStream.Create(TextRec(Output).Handle);
  try
    H.WriteBuffer(Physical[1], Length(Physical));
  finally
    H.Free;
  end;
end;

function Run: Integer;
var Width: SizeInt; Source, Physical: RawByteString;
begin
  if (ParamCount <> 3) or (ParamStr(1) <> '--'+#$D0#$BF#$D0#$B0#$D0#$BA#$D1#$83#$D0#$B2#$D0#$B0#$D1#$82#$D0#$B8#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82) then begin
    WriteLn(StdErr, 'Використання: senschyslopakuvaty --пакувати-пакет D12|D24|D48|D96|D192 файл.lisp > файл.sens');
    Exit(64);
  end;
  try
    Width := SelectedNumericDomain(RawByteString(ParamStr(2)));
    Source := ReadSource(ParamStr(3));
    Physical := EncodeLines(Source, Width);
    WritePhysical(Physical);
    Result := 0;
  except
    on E: Exception do begin
      WriteLn(StdErr, 'ЧИСЛОВЕ-ПАКУВАННЯ-ПОМИЛКА: ', E.Message);
      Result := 2;
    end;
  end;
end;

begin
  Halt(Run);
end.
