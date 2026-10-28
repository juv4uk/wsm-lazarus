{ G1.10: фізична атомарність T5M — бітовий транспорт, не закони SENS.
  Числова ширина D12/D24 сама не створює числа або викличності. }
program test_t5m_atomic;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m;
const LargePhysicalBytes = 512 * 1024;
      ManyShortWords = 100000;
var
  Words, Source: TExactWords;
  Physical, LongPhysical: RawByteString;
  I: SizeInt;
  Rejected: Boolean;

procedure Check(Yes: Boolean; const Why: String);
begin
  if not Yes then begin
    WriteLn(StdErr, 'Т5М-АТОМАРНІСТЬ-ПОМИЛКА: ', Why);
    Halt(1);
  end;
end;

procedure ExpectReject(const Bad: RawByteString; const Why: String);
begin
  { До помилки — непорожній result попереднього виклику. }
  SetLength(Words, 1);
  Words[0] := '110011';
  Rejected := False;
  try
    DecodeT5M(Bad, Words);
  except
    on E: ET5MError do Rejected := True;
  end;
  Check(Rejected, 'не відхилено: ' + Why);
  Check(Length(Words) = 0,
    'після відмови залишено попередні або часткові слова: ' + Why);
end;

begin
  { Реальний великий однословний фізичний T5M — понад 2.6 млн біт.
    Кожний нульовий фізичний байт містить П'ЯТЬ окремих бітових цифр. }
  LongPhysical := StringOfChar(#0, LargePhysicalBytes);
  DecodeT5M(LongPhysical, Words);
  Check(Length(Words) = 1, 'загублено велике двійкове слово');
  Check(Length(Words[0]) = LargePhysicalBytes * 5, 'втрачена точна ширина');
  Check((Words[0][1]='0') and
        (Words[0][Length(Words[0])]='0'), 'пошкоджено біти довгого слова');
  Check(EncodeT5M(Words) = LongPhysical, 'втрата великих фізичних байтів');

  { Пізній дефект: раніше parser уже публікував першу валідну форму. }
  ExpectReject(LongPhysical + #243, '243 після довгого слова');
  ExpectReject(LongPhysical + #242, 'понад чотири pad-трити після довгого слова');
  ExpectReject('', 'порожній фізичний потік');
  ExpectReject(#162, 'провідний фізичний роздільник');

  SetLength(Source, ManyShortWords);
  for I:=0 to High(Source) do
    if (I and 1)=0 then Source[I]:='00'
    else Source[I]:='1';
  Physical := EncodeT5M(Source);
  DecodeT5M(Physical, Words);
  Check(Length(Words) = ManyShortWords, 'втрачено короткі слова');
  for I:=0 to High(Words) do
    Check(Words[I] = Source[I], 'незбіг точних коротких слів');
  Check(EncodeT5M(Words) = Physical, 'необоротні фізичні короткі слова');

  ExpectReject(Physical + #243, 'пізній 243 після ста тисяч слів');
  ExpectReject(Physical + #242, 'пізній некоректний pad');

  { Після помилки той самий out має успішно відновлюватися. }
  DecodeT5M(Physical, Words);
  Check((Length(Words) = ManyShortWords) and
    (Words[0] = '00') and (Words[1] = '1'),
    'невдале повторне читання після помилки');

  { Точні довгі слова майбутньої D12+ площини не трактуються
    тут як операнди, навіть за збігу фізичної ширини. }
  SetLength(Source, 2);
  Source[0] := '000000000001'; { 12 біт }
  Source[1] := '000000000000000000000001'; { 24 біти }
  Physical := EncodeT5M(Source);
  DecodeT5M(Physical, Words);
  Check((Length(Words)=2) and (Words[0]=Source[0]) and
     (Words[1]=Source[1]), 'втрата бітів D12/D24 фізичного T5M');
  Check(EncodeT5M(Words)=Physical, 'необоротний широкий T5M');

  WriteLn('Т5М-АТОМАРНІСТЬ-ГАРАЗД: FPC=так довге-слово=', LargePhysicalBytes*5,
    ' коротких-слів=', ManyShortWords, ' пізні-відмови=порожній-вихід',
    ' D12-D24=лише-фізичні-біти');
end.
