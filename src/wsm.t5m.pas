{ G1.2: physical T5M .sens transport, strictly from juv4uk/sens
  scripts/sens_t5_t5m_codec.py::encode_t5m_projection/decode_t5m_bytes.
  It returns exact words as bytes "0"/"1" and does NOT infer domain,
  SENS semantics, callable status or D2 syntax from their widths. }
unit wsm.t5m;
{$mode objfpc}{$H+}
interface
uses SysUtils;
const MAX_T5M_FILE_BYTES = 4 * 1024 * 1024;
type
  ET5MError = class(Exception);
  TExactWords = array of RawByteString;

function EncodeT5M(const Words: TExactWords): RawByteString;
procedure DecodeT5M(const Physical: RawByteString; out Words: TExactWords);

implementation

{ Прямий канонічний T5M: спершу ПОВНА перевірка exact-слів і
  фізичного бюджету, потім один Result; немає проміжного Trits.
  П'ять тритів у порядку pinned SENS на кожен байт base 3. }
function EncodeT5M(const Words: TExactWords): RawByteString;
var
  I, J, N, Padded, Total, NextByte, DigitCount, Accumulator: SizeInt;

  procedure EmitTrit(Digit: SizeInt);
  begin
    Accumulator := Accumulator * 3 + Digit;
    Inc(DigitCount);
    if DigitCount = 5 then begin
      Result[NextByte] := AnsiChar(Accumulator);
      Inc(NextByte);
      DigitCount := 0;
      Accumulator := 0;
    end;
  end;

begin
  if Length(Words) = 0 then raise ET5MError.Create('empty T5M word list');
  Total := 0;
  for I := 0 to High(Words) do begin
    N := Length(Words[I]);
    if (N = 0) or (N > MAX_T5M_FILE_BYTES * 5) then
      raise ET5MError.Create('empty/oversized exact word');
    for J := 1 to N do
      if not (Words[I][J] in ['0','1']) then
        raise ET5MError.Create('nonbinary exact word');
    if Total > MAX_T5M_FILE_BYTES * 5 - N then
      raise ET5MError.Create('T5M exceeds file boundary');
    Inc(Total, N);
    if I <> High(Words) then begin
      if Total >= MAX_T5M_FILE_BYTES * 5 then
        raise ET5MError.Create('T5M exceeds file boundary');
      Inc(Total);
    end;
  end;
  Padded := ((Total + 4) div 5) * 5;
  if Padded div 5 > MAX_T5M_FILE_BYTES then
    raise ET5MError.Create('T5M exceeds file boundary');

  { Єдина алокація вихідних фізичних байтів після всіх відмов preflight.
    П'ятірка тритів завжди завершується до наступного байта. }
  SetLength(Result, Padded div 5);
  NextByte := 1;
  DigitCount := 0;
  Accumulator := 0;
  for I := 0 to High(Words) do begin
    for J := 1 to Length(Words[I]) do
      EmitTrit(Ord(Words[I][J]) - Ord('0'));
    if I <> High(Words) then EmitTrit(2);
  end;
  while DigitCount <> 0 do EmitTrit(2);
  if NextByte <> Length(Result) + 1 then
    raise ET5MError.Create('T5M physical byte count mismatch');
end;

{ Транзакційний фізичний декодер: помилковий T5M не повертає
  навіть раніше прочитаних слів. Жодної семантичної класифікації Dn.
  Тимчасовий бітовий буфер росте геометрично, аби не копіювати
  всі попередні біти під час читання кожного наступного трита. }
procedure DecodeT5M(const Physical: RawByteString; out Words: TExactWords);
const Divisors: array[0..4] of Integer = (81,27,9,3,1);
var
  I, K, B, Digit, N, Capacity, Padding: SizeInt;
  Current, Exact: RawByteString;
  CurrentLen, CurrentCap, NewCap: SizeInt;
  Candidate: TExactWords;

  procedure AppendBit(Bit: AnsiChar);
  begin
    if CurrentLen >= MAX_T5M_FILE_BYTES * 5 then
      raise ET5MError.Create('word too large');
    if CurrentLen = CurrentCap then begin
      if CurrentCap = 0 then
        NewCap := 32
      else if CurrentCap > (MAX_T5M_FILE_BYTES * 5) div 2 then
        NewCap := MAX_T5M_FILE_BYTES * 5
      else
        NewCap := CurrentCap * 2;
      SetLength(Current, NewCap);
      CurrentCap := NewCap;
    end;
    Inc(CurrentLen);
    Current[CurrentLen] := Bit;
  end;

  procedure AddWord;
  begin
    if CurrentLen = 0 then raise ET5MError.Create('empty exact word');
    if N = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity * 2;
      SetLength(Candidate, Capacity);
    end;
    { Зберегти рівно поточні біти, не випадкову місткість буфера. }
    Exact := Copy(Current, 1, CurrentLen);
    Candidate[N] := Exact;
    Inc(N);
    CurrentLen := 0;
  end;

begin
  SetLength(Words, 0);
  if (Length(Physical) = 0) or
     (Length(Physical) > MAX_T5M_FILE_BYTES) then
    raise ET5MError.Create('empty/oversized physical T5M file');
  N := 0; Capacity := 0; CurrentLen := 0; CurrentCap := 0;
  Padding := 0;
  SetLength(Candidate, 0);
  Current := '';
  for I := 1 to Length(Physical) do begin
    B := Ord(Physical[I]);
    if B >= 243 then raise ET5MError.Create('invalid T5M byte 243..255');
    for K := 0 to 4 do begin
      Digit := (B div Divisors[K]) mod 3;
      if Digit = 2 then begin
        if CurrentLen > 0 then begin
          AddWord;
          Padding := 1;
        end else Inc(Padding);
        if Padding >= 5 then
          raise ET5MError.Create('too many terminal padding trits');
      end else begin
        if Padding > 1 then
          raise ET5MError.Create('noncanonical repeated separator');
        if (Padding > 0) and (N = 0) then
          raise ET5MError.Create('noncanonical leading separator');
        Padding := 0;
        if Digit = 1 then AppendBit('1')
        else AppendBit('0');
      end;
    end;
  end;
  if CurrentLen > 0 then AddWord;
  if N = 0 then raise ET5MError.Create('empty T5M word stream');
  SetLength(Candidate, N);
  { Єдина точка публікації вже повністю перевіреного документа. }
  Words := Candidate;
end;

end.
