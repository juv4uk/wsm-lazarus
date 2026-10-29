{ G3.13: реальний результат D3 -> T5M; не розбираємо текст evaluator. }
program test_native_physical_answer;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.binaryexec;

var E:TBinaryExecutor; Checks:SizeInt;

procedure Must(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('ФІЗИЧНА-ВІДПОВІДЬ-ПОМИЛКА: '+Why);
end;

function Pack(const V:array of RawByteString):RawByteString;
var Words:TExactWords; I:SizeInt;
begin
  SetLength(Words,Length(V));
  for I:=0 to High(V) do Words[I]:=V[I];
  Result:=EncodeT5M(Words);
end;

procedure CheckAnswer(const Source,Expected:RawByteString;
  const ExpectedText,Why:String);
var Actual,TextAnswer:RawByteString; Words:TExactWords;
    Tree:TD2Document;
begin
  Actual:=E.ExecutePhysicalT5M(Source);
  Must(Actual=Expected,Why+': фізичні байти не збігаються');
  DecodeT5M(Actual,Words);
  Must(EncodeT5M(Words)=Actual,Why+': неконічний T5M');
  Tree:=ReadD2T5M(Actual);
  try Must(Length(Tree.Roots)=1,Why+': має бути один D2 корінь');
  finally Tree.Free; end;
  TextAnswer:=E.ExecutePhysical(Source);
  Must(TextAnswer=ExpectedText,Why+': текстовий API змінено');
end;

procedure CheckWords(const A,B:array of RawByteString;
  const ExpectedText,Why:String);
begin
  CheckAnswer(Pack(A),Pack(B),ExpectedText,Why);
end;

procedure Reject(const Payload:RawByteString; AtWord:SizeInt;
  const Why:String);
var Failed:Boolean; ResultBytes:RawByteString;
begin
  Failed:=False; ResultBytes:='';
  try ResultBytes:=E.ExecutePhysicalT5M(Payload)
  except on X:EBinaryExecutionError do begin
    Failed:=True;
    Must(X.WordIndex=AtWord,Why+': неточне слово помилки');
  end; end;
  Must(Failed,Why+': заборонений фізичний виклик прийнято');
  Must(ResultBytes='',Why+': оприлюднено часткову відповідь');
end;

function LongQuote(Count:SizeInt):RawByteString;
var Words:TExactWords; I:SizeInt;
begin
  SetLength(Words,Count+5);
  Words[0]:='10'; Words[1]:='001'; Words[2]:='10';
  for I:=0 to Count-1 do Words[I+3]:='1';
  Words[Count+3]:='01'; Words[Count+4]:='01';
  Result:=EncodeT5M(Words);
end;

procedure CheckLong;
var Source,Answer:RawByteString; W:TExactWords; I:SizeInt;
    Tree:TD2Document;
begin
  Source:=LongQuote(2000);
  Answer:=E.ExecutePhysicalT5M(Source);
  DecodeT5M(Answer,W);
  Must(Length(W)=2002,'плоский фізичний D2 список: кількість слів');
  Must((W[0]='10') and (W[High(W)]='01'),
    'плоский фізичний список: обрамлення');
  for I:=1 to High(W)-1 do
    Must(W[I]='1','плоский фізичний список: точний D1 atom');
  Must(EncodeT5M(W)=Answer,'довгий фізичний побайтовий roundtrip');
  Tree:=ReadD2T5M(Answer);
  try
    Must(Length(Tree.Roots)=1,'довгий фізичний список: один корінь');
    Must(Tree.Roots[0].Kind=dkList,'довгий результат: D2 список');
    Must(Length(Tree.Roots[0].Children)=2000,'втрачено елемент списку');
  finally Tree.Free; end;
end;

begin
  Checks:=0;
  E:=TBinaryExecutor.Create('external/sens');
  try
    CheckWords(['0'],['0'],'0','D1:0');
    CheckWords(['1'],['1'],'1','D1:1');
    CheckWords(['000'],['000'],'()','D3:000 не D1:0');
    CheckWords(['10','001','000','01'],['000'],'()',
      'pinned (як-є ()) — empty oracle');
    CheckWords(['10','001','111111111','01'],['111111111'],
      '111111111','точний W9 без скорочення');
    CheckWords(['10','001','10','1','0','01','01'],
      ['10','1','0','01'],'(1 0)','цитований proper list');
    CheckWords(['10','001','10','1','10','0','1','01','01','01'],
      ['10','1','10','0','1','01','01'],'(1 (0 1))',
      'вкладені фізичні D2 списки');
    CheckWords(['10','001','10','000','1','01','01'],
      ['10','000','1','01'],'(() 1)',
      'D3:000 усередині фізичного списку');
    { Обидва масиви — точні фізичні слова; CheckWords пакує їх у T5M,
      передає source evaluator і звіряє T5M-відповідь та її проєкцію.
      Пара є даними після QUOTE; її поля не стають аргументами виклику.
      Буфери живуть до завершення синхронної перевірки.
      Питання: де зберігається крапкова межа? Яка точна форма відповіді?
      Чому попередня негативна перевірка була застарілою? }
    CheckWords(['10','001','10','1','11','0','01','01'],
      ['10','1','11','0','01'],'(1 . 0)',
      'цитована фізична D2 крапкова пара');
    CheckWords(['10','111','1','0','01'],
      ['10','1','11','0','01'],'(1 . 0)',
      'справжній D3:111 з dotted tail');
    CheckWords(['10','111','1','10','111','0','1','01','01'],
      ['10','1','0','11','1','01'],'(1 0 . 1)',
      'вкладений CONS і один точний D2 dot');
    CheckWords(['10','101','1','1','01'],['1'],'1',
      'справжній D3:101 повернув D1');
    CheckWords(['10','110','01'],['000'],'()',
      'вичерпаний D3:110 не false');
    CheckLong;

    Reject(#243,0,'неприпустимий T5M байт');
    Reject(Pack(['10','001','1','0','01']),1,'арність D3:001');
    Reject(Pack(['10','1','11','0','01']),1,
      'виконувана крапкова D2 пара');
    Reject(Pack(['10','001','000000000000','01']),3,'D12+ без допуску');
    CheckWords(['10','001','001','01'],['001'],'001',
      'відновлення після чотирьох відмов');
    WriteLn('ФІЗИЧНА-ВІДПОВІДЬ-ГАРАЗД checks=',Checks,
      ' T5M=канонічний D3:000=не-D1:0 W9=точний',
      ' proper=d2 dotted=d2 long=2000 oracle=незалежно');
  finally E.Free; end;
end.
