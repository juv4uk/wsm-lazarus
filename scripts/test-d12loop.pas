{ G6.73: живий доказ нативного циклу навантаження.
  Фізичні D12-фікстури й очікувані коди виходу рахує НЕЗАЛЕЖНИЙ оракул —
  ланцюжок чинного wsm.numericadd (AddNumericPhysical), а не мій емітер.
  Саме тому цей файл пише фікстури, будує ELF і друкує EXPECT. }
program TestD12Loop;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, BaseUnix, wsm.t5m, wsm.elfd12loop, wsm.numericadd;

var
  Passed: SizeInt;
  Root, OutDir: String;

procedure Check(Condition: Boolean; const Why: String);
begin
  Inc(Passed);
  if not Condition then raise Exception.Create('ПРОВАЛ: ' + Why);
end;

{ Прямі POSIX-виклики: у цій збірці FPC TFileStream(fmCreate)
  лишає 4 блоки heaptrc, і це не властивість SENS. Тут потрібен
  лише точний запис байтів фікстури. }
procedure WriteBytes(const Filename: String; const Data: RawByteString);
var
  FD: cint;
  Written, Chunk: SizeInt;
begin
  FD := fpOpen(Filename, O_WRONLY or O_CREAT or O_TRUNC, &644);
  if FD < 0 then raise Exception.Create('не створено ' + Filename);
  try
    Written := 0;
    while Written < Length(Data) do begin
      Chunk := fpWrite(FD, Data[Written + 1], Length(Data) - Written);
      if Chunk <= 0 then raise Exception.Create('не записано ' + Filename);
      Inc(Written, Chunk);
    end;
  finally
    fpClose(FD);
  end;
end;

{ Точний D12-атом із дванадцяти двійкових знаків. Це host-побудовник
  фікстури через ЄДИНИЙ наявний кодек T5M, не другий кодувальник. }
function D12(const Bits: String): RawByteString;
var
  Words: TExactWords;
begin
  if Length(Bits) <> 12 then raise Exception.Create('не D12');
  SetLength(Words, 1);
  Words[0] := RawByteString(Bits);
  Result := EncodeT5M(Words);
end;

{ Оракул: K додається N-1 разів ЧИННИМ SENS-механізмом; результат —
  дванадцятибітний доповняльний код. Повертаємо молодші 8 біт як код виходу.
  Питання: чому саме AddNumericPhysical, а не арифметика мови Pascal?
  Чому для великих N цей оракул не застосовується? }
function ExpectedExit(const K: RawByteString; Count: SizeInt): Integer;
var
  Acc: RawByteString;
  Bits: TExactWords;
  I, Unsigned: SizeInt;
begin
  Acc := K;
  for I := 2 to Count do
    Acc := AddNumericPhysical(Acc, K, 12);
  DecodeT5M(Acc, Bits);
  if (Length(Bits) <> 1) or (Length(Bits[0]) <> 12) then
    raise Exception.Create('оракул дав не D12');
  Unsigned := 0;
  for I := 1 to 12 do
    Unsigned := (Unsigned shl 1) or (Ord(Bits[0][I]) - Ord('0'));
  Result := Unsigned and 255;
end;

procedure ExpectRefusal(const Physical: RawByteString; Count: LongWord;
  const Why: String);
var
  Image: RawByteString;
begin
  Image := '';
  try
    Image := BuildD12LoopELF(Physical, Count);
  except
    on E: Exception do begin
      Check(Image = '', Why + ': відмова не має лишати часткового образу');
      Exit;
    end;
  end;
  Check(False, Why + ': очікувалася відмова');
end;

var
  K5, KMinus1: RawByteString;
  Image, Again: RawByteString;
  Counts: array[0..2] of LongWord = (1, 7, 64);
  I: SizeInt;
  Bad: RawByteString;
begin
  Passed := 0;
  Root := ParamStr(1);
  OutDir := ParamStr(2);
  if (Root = '') or (OutDir = '') then
    raise Exception.Create('потрібні корінь і каталог виводу');
  K5 := D12('000000000101');
  KMinus1 := D12('111111111111');
  WriteBytes(IncludeTrailingPathDelimiter(OutDir) + 'k5.sens', K5);
  WriteBytes(IncludeTrailingPathDelimiter(OutDir) + 'kminus1.sens', KMinus1);

  { 1. Позитиви: ELF будується, образ має точну геометрію ELF64 ET_EXEC. }
  for I := 0 to High(Counts) do begin
    Image := BuildD12LoopELF(K5, Counts[I]);
    Check(Length(Image) = 151, 'образ має 151 байт, є ' + IntToStr(Length(Image)));
    Check(Copy(Image, 1, 4) = #$7F'ELF', 'немає магії ELF');
    Check(Image[5] = #2, 'не ELFCLASS64');
    Check(Image[17] = #2, 'не ET_EXEC');
    Check(Image[19] = #62, 'не EM_X86_64');
    WriteBytes(IncludeTrailingPathDelimiter(OutDir) + 'loop-' +
      IntToStr(Counts[I]) + '.elf', Image);
    Writeln('EXPECT ', Counts[I], ' ', ExpectedExit(K5, Counts[I]));
  end;

  { 2. Детермінованість: дві незалежні збірки дають ті самі байти. }
  Image := BuildD12LoopELF(K5, 7);
  Again := BuildD12LoopELF(K5, 7);
  Check(Image = Again, 'дві збірки розійшлися побайтово');

  { 3. Знакова константа: -1 не стає 4095. }
  Image := BuildD12LoopELF(KMinus1, 1);
  Check(Length(Image) = 151, 'відʼємна D12 дала інший образ');
  WriteBytes(IncludeTrailingPathDelimiter(OutDir) + 'loop-minus1.elf', Image);
  Writeln('EXPECT -1 ', ExpectedExit(KMinus1, 1));

  { 4. Негативи: жодного часткового образу. }
  ExpectRefusal('', 1, 'порожній вхід');
  Bad := Copy(K5, 1, Length(K5) - 1) + #$FF;
  ExpectRefusal(Bad, 1, 'пошкоджений T5M');
  ExpectRefusal(D12('000000000000'), 0, 'нуль ітерацій');
  ExpectRefusal(D12('000000000000'), 1000000001, 'ітерації поза межею');
  SetLength(Bad, 1);
  Bad[1] := '0';
  ExpectRefusal(Bad, 1, 'D1-атом замість D12');

  Writeln('SENS-D12LOOP-PASS checks=', Passed);
end.
