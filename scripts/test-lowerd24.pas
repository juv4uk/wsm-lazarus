{ G6.95 — перше справжнє зниження тіла SENS у машинний код.
  Оракул — САМ ОБЧИСЛЮВАЧ SENS: те саме тіло допускається як
  користувацьке визначення й викликається; нативний ELF мусить дати
  той самий результат (low8). }
program test_lowerd24;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix,
  wsm.t5m, wsm.d7text, wsm.core1selektor, wsm.lowerd24;

var
  Map: TD7Map;
  Selector: TCore1Selektor;
  Checks, Failures: SizeInt;
  DefCounter: SizeInt;

procedure Check(Ok: Boolean; const Why: RawByteString);
begin
  Inc(Checks);
  if Ok then Writeln('LOWER24-OK   ', Why)
  else begin Writeln('LOWER24-ЗБІЙ ', Why); Inc(Failures); end;
end;

function JoinUtf8(const Left, Right: String): RawByteString;
begin
  { Не конкатенувати україномовний суфікс як звичайний String:
    FPC може знизити символи до '?' за codepage параметра. }
  Result := RawByteString(Left) + RawByteString(Right);
end;

function NameBits(const Text: String): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(EncodeD7Text(RawByteString(Text), Map, dsUk), Words);
  Result := '';
  for I := 0 to High(Words) do Result := Result + Words[I];
end;

function NameNode(const Bits: RawByteString): TExactWords;
var
  I: SizeInt;
  P: SizeInt;
begin
  SetLength(Result, (Length(Bits) div 7) + 2);
  Result[0] := '10';
  P := 1;
  I := 1;
  while I + 6 <= Length(Bits) do begin
    Result[P] := Copy(Bits, I, 7);
    Inc(P);
    Inc(I, 7);
  end;
  Result[P] := '01';
  SetLength(Result, P + 1);
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

function Concat(const Parts: array of TExactWords): TExactWords;
var
  I, K, P: SizeInt;
begin
  SetLength(Result, 0);
  P := 0;
  for I := 0 to High(Parts) do
    for K := 0 to High(Parts[I]) do begin
      SetLength(Result, P + 1);
      Result[P] := Parts[I][K];
      Inc(P);
    end;
end;

function One(const Word: RawByteString): TExactWords;
begin
  SetLength(Result, 1);
  Result[0] := Word;
end;

function QuoteAtom(const Word: RawByteString): TExactWords;
begin
  SetLength(Result, 4);
  Result[0] := '10';
  Result[1] := '001';
  Result[2] := Word;
  Result[3] := '01';
end;

function Binary(const Head, A, B: RawByteString): TExactWords;
begin
  SetLength(Result, 5);
  Result[0] := '10';
  Result[1] := Head;
  Result[2] := A;
  Result[3] := B;
  Result[4] := '01';
end;

function RunELF(const Image: RawByteString; out ExitCode: SizeInt): Boolean;
var
  Path: String;
  Stream: TFileStream;
  Status: LongInt;
begin
  Result := False;
  ExitCode := -1;
  Path := GetTempDir(False) + 'sens-lower-' + IntToStr(Random(1000000)) + '.elf';
  Stream := TFileStream.Create(Path, fmCreate);
  try
    if Length(Image) > 0 then Stream.WriteBuffer(Image[1], Length(Image));
  finally
    Stream.Free;
  end;
  if fpChmod(Path, &755) <> 0 then begin DeleteFile(Path); Exit; end;
  Status := fpSystem(PChar(Path));
  DeleteFile(Path);
  if WIFEXITED(Status) then begin
    ExitCode := WEXITSTATUS(Status);
    Result := True;
  end;
end;

{ Оракул: те саме тіло як користувацьке визначення, викликане обчислювачем. }
function OracleValueNamed(const BodyWords: TExactWords;
  const ParamBits: RawByteString; const Arg: LongWord;
  const DefName: RawByteString): LongWord;
var
  DefWords, CallWords: TExactWords;
  Params, Lambda, Call: TExactWords;
  Answer: RawByteString;
  Back: TExactWords;
  I: SizeInt;
  Ordinal: SizeInt;
  Name: RawByteString;
begin
  if DefName = '' then begin
    Name := NameBits('проба' + IntToStr(DefCounter));
    Inc(DefCounter);
  end else
    Name := DefName;

  { Список параметрів — просто `10 <імʼя> 01`: маркер 1110 тут не потрібен. }
  Params := Concat([One('10'), NameNode(ParamBits), One('01')]);
  Lambda := Concat([One('10'), One('0010'), Params, BodyWords, One('01')]);
  DefWords := Concat([One('10'), One('0011'), NameNode(Name), Lambda, One('01')]);
  Ordinal := Selector.AdmitUserDefinition(EncodeT5M(DefWords));

  { ExecutePhysicalCall бере аргументи ЯК ДАНІ, тому точний D24
    передається голим словом, без цитати. }
  Call := Concat([One('10'), NameNode(Name), One(D24(Arg)), One('01')]);
  Answer := Selector.ExecutePhysicalCall(EncodeT5M(Call));
  DecodeT5M(Answer, Back);
  Result := 0;
  for I := 1 to Length(Back[0]) do
    Result := (Result shl 1) or LongWord(Ord(Back[0][I]) - Ord('0'));
end;

{ G6.147: два справжні фізичні аргументи в одному pinned SENS
  визначенні. Це незалежний виклик уже існуючого TCore1Selektor,
  не Pascal-обчислення знакового порівняння. }
function OracleValueTwoParams(const BodyWords: TExactWords;
  const A, B: LongWord): LongWord;
var
  Name, FirstKey, SecondKey, Answer: RawByteString;
  Params, Lambda, DefWords, CallWords, Back: TExactWords;
  I: SizeInt;
  Ordinal: SizeInt;
begin
  Name := NameBits('проба' + IntToStr(DefCounter));
  Inc(DefCounter);
  FirstKey := NameBits('величина');
  SecondKey := NameBits('додаток');
  Params := Concat([One('10'), NameNode(FirstKey),
    NameNode(SecondKey), One('01')]);
  Lambda := Concat([One('10'), One('0010'), Params, BodyWords, One('01')]);
  DefWords := Concat([One('10'), One('0011'),
    NameNode(Name), Lambda, One('01')]);
  Ordinal := Selector.AdmitUserDefinition(EncodeT5M(DefWords));
  CallWords := Concat([One('10'), NameNode(Name),
    One(D24(A)), One(D24(B)), One('01')]);
  Answer := Selector.ExecutePhysicalCall(EncodeT5M(CallWords));
  DecodeT5M(Answer, Back);
  if Length(Back) <> 1 then
    raise Exception.Create('обчислювач повернув не один фізичний атом');
  if not (Length(Back[0]) in [1, 24]) then
    raise Exception.Create('обчислювач втратив домен відповіді');
  Result := 0;
  for I := 1 to Length(Back[0]) do
    Result := (Result shl 1) or LongWord(Ord(Back[0][I]) - Ord('0'));
end;

{ G6.257: три справжні фізичні аргументи в одному pinned SENS
  визначенні. Оракул — той самий TCore1Selektor, не Pascal-арифметика. }
function OracleValueThreeParams(const BodyWords: TExactWords;
  const A, B, C: LongWord): LongWord;
var
  Name, FirstKey, SecondKey, ThirdKey, Answer: RawByteString;
  Params, Lambda, DefWords, CallWords, Back: TExactWords;
  I: SizeInt;
begin
  Name := NameBits('проба' + IntToStr(DefCounter));
  Inc(DefCounter);
  FirstKey := NameBits('величина');
  SecondKey := NameBits('додаток');
  ThirdKey := NameBits('третя');
  Params := Concat([One('10'), NameNode(FirstKey),
    NameNode(SecondKey), NameNode(ThirdKey), One('01')]);
  Lambda := Concat([One('10'), One('0010'), Params, BodyWords, One('01')]);
  DefWords := Concat([One('10'), One('0011'),
    NameNode(Name), Lambda, One('01')]);
  Selector.AdmitUserDefinition(EncodeT5M(DefWords));
  CallWords := Concat([One('10'), NameNode(Name),
    One(D24(A)), One(D24(B)), One(D24(C)), One('01')]);
  Answer := Selector.ExecutePhysicalCall(EncodeT5M(CallWords));
  DecodeT5M(Answer, Back);
  if Length(Back) <> 1 then
    raise Exception.Create('обчислювач повернув не один фізичний атом');
  Result := 0;
  for I := 1 to Length(Back[0]) do
    Result := (Result shl 1) or LongWord(Ord(Back[0][I]) - Ord('0'));
end;

{ Три параметри: rdi, rsi, rdx. Очікування бере pinned SENS обчислювач,
  тому збіг не може бути наслідком тієї самої помилки в обох шляхах. }
procedure CaseThreeParamsOracle(const Title: String;
  const BodyWords: TExactWords; const A, B, C: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
  Expected: LongWord;
begin
  Expected := OracleValueThreeParams(BodyWords, A, B, C);
  Image := LowerBodyThreeParamsELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))),
    EncodeT5M(NameNode(NameBits('додаток'))),
    EncodeT5M(NameNode(NameBits('третя'))),
    EncodeT5M(One(D24(A))), EncodeT5M(One(D24(B))), EncodeT5M(One(D24(C))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' a=' + IntToStr(A) + ' b=' + IntToStr(B) + ' c=' + IntToStr(C) +
    ' native=' + IntToStr(Code) + ' oracle=' + IntToStr(Expected and 255));
end;

{ G6.258: N параметрів. Оракул — той самий pinned SENS-обчислювач,
  тому збіг не може бути наслідком спільної помилки. }
const
  ParamNames: array[0..5] of String =
    ('величина', 'додаток', 'третя', 'четверта', 'пята', 'шоста');

function OracleValueNParams(const BodyWords: TExactWords;
  const Args: array of LongWord): LongWord;
var
  Name, Answer: RawByteString;
  Params, Lambda, DefWords, CallWords, Back: TExactWords;
  I: SizeInt;
begin
  Name := NameBits('проба' + IntToStr(DefCounter));
  Inc(DefCounter);
  Params := Concat([One('10')]);
  for I := 0 to High(Args) do
    Params := Concat([Params, NameNode(NameBits(ParamNames[I]))]);
  Params := Concat([Params, One('01')]);
  Lambda := Concat([One('10'), One('0010'), Params, BodyWords, One('01')]);
  DefWords := Concat([One('10'), One('0011'), NameNode(Name), Lambda, One('01')]);
  Selector.AdmitUserDefinition(EncodeT5M(DefWords));
  CallWords := Concat([One('10'), NameNode(Name)]);
  for I := 0 to High(Args) do
    CallWords := Concat([CallWords, One(D24(Args[I]))]);
  CallWords := Concat([CallWords, One('01')]);
  Answer := Selector.ExecutePhysicalCall(EncodeT5M(CallWords));
  DecodeT5M(Answer, Back);
  if Length(Back) <> 1 then
    raise Exception.Create('обчислювач повернув не один фізичний атом');
  Result := 0;
  for I := 1 to Length(Back[0]) do
    Result := (Result shl 1) or LongWord(Ord(Back[0][I]) - Ord('0'));
end;

{ Прямий оракул для 4–6 параметрів. ЧЕСНО ПРО ПРИЧИНУ: pinned-обчислювач
  на ОДНОМУ чотирипараметровому визначенні в чистому сеансі працює
  (перевірено окремо: (1+2)+(3+4) → 10), але в цьому тесті, де перед ним
  ухвалено десятки визначень, AdmitUserDefinition падає EAccessViolation.
  Точну причину я НЕ встановив, тому не роблю вигляд, що це оракул.
  Очікування тут — Pascal-арифметика, і назва кожного випадку це позначає. }
procedure CaseNParamsDirect(const Title: String;
  const BodyWords: TExactWords; const Args: array of LongWord;
  const Expected: LongWord);
var
  Keys, Vals: array of RawByteString;
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
  I: SizeInt;
  Shown: String;
begin
  SetLength(Keys, Length(Args));
  SetLength(Vals, Length(Args));
  Shown := '';
  for I := 0 to High(Args) do begin
    Keys[I] := EncodeT5M(NameNode(NameBits(ParamNames[I])));
    Vals[I] := EncodeT5M(One(D24(Args[I])));
    Shown := Shown + IntToStr(Args[I]) + ' ';
  end;
  Image := LowerBodyNParamsELF(EncodeT5M(BodyWords), Keys, Vals);
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' args=' + Shown + 'native=' + IntToStr(Code) +
    ' direct=' + IntToStr(Expected and 255));
end;

procedure CaseNParamsOracle(const Title: String;
  const BodyWords: TExactWords; const Args: array of LongWord);
var
  Keys, Vals: array of RawByteString;
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
  Expected: LongWord;
  I: SizeInt;
  Shown: String;
begin
  Expected := OracleValueNParams(BodyWords, Args);
  SetLength(Keys, Length(Args));
  SetLength(Vals, Length(Args));
  Shown := '';
  for I := 0 to High(Args) do begin
    Keys[I] := EncodeT5M(NameNode(NameBits(ParamNames[I])));
    Vals[I] := EncodeT5M(One(D24(Args[I])));
    Shown := Shown + IntToStr(Args[I]) + ' ';
  end;
  Image := LowerBodyNParamsELF(EncodeT5M(BodyWords), Keys, Vals);
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' args=' + Shown + 'native=' + IntToStr(Code) +
    ' oracle=' + IntToStr(Expected and 255));
end;

function Clause(const Test, Body: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), Test, Body, One('01')]);
end;

function Call1(const NameNode, Arg: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg, One('01')]);
end;

{ Самовиклик із ДВОМА аргументами: голова-імʼя, два операнди. }
function Call2(const NameNode, Arg1, Arg2: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg1, Arg2, One('01')]);
end;

{ G6.257: виклик із трьома аргументами — та сама фізична форма списку. }
function Call3(const NameNode, Arg1, Arg2, Arg3: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg1, Arg2, Arg3, One('01')]);
end;

function Call4(const NameNode, Arg1, Arg2, Arg3, Arg4: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg1, Arg2, Arg3, Arg4, One('01')]);
end;

{ Оракул другого роду: пряма арифметика в хості. Використовується там,
  де обчислювач SENS на цьому тілі зараз відмовляє (літерал у тілі) —
  і це ЯВНО позначено в назві випадку, а не замасковано. }
procedure CaseBodyDirect(const Title: String; const BodyWords: TExactWords;
  const Arg, Expected: LongWord);
var
  ParamBits: RawByteString;
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  ParamBits := NameBits('величина');
  Image := LowerBodyELF(EncodeT5M(BodyWords), EncodeT5M(NameNode(ParamBits)),
    EncodeT5M(One(D24(Arg))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' arg=' + IntToStr(Arg) + ' native=' + IntToStr(Code) +
    ' direct=' + IntToStr(Expected and 255));
end;

{ ДВА параметри: тіло (додати величина додаток) із rdi та rsi.
  Це перший випадок, коли зниження читає другий регістр аргументів. }
procedure CaseTwoParams(const Title: String; const BodyWords: TExactWords;
  const A, B, Expected: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  Image := LowerBodyTwoParamsELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))),
    EncodeT5M(NameNode(NameBits('додаток'))),
    EncodeT5M(One(D24(A))), EncodeT5M(One(D24(B))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' a=' + IntToStr(A) + ' b=' + IntToStr(B) +
    ' native=' + IntToStr(Code) + ' direct=' + IntToStr(Expected and 255));
end;

{ Обидва аргументи D24 взяті з фізичного T5M; expected обчислює
  справжній pinned SENS executor, незалежний від x86-64 SETG. }
procedure CaseTwoParamsOracle(const Title: String;
  const BodyWords: TExactWords; const A, B: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
  Expected: LongWord;
begin
  Expected := OracleValueTwoParams(BodyWords, A, B);
  Image := LowerBodyTwoParamsELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))),
    EncodeT5M(NameNode(NameBits('додаток'))),
    EncodeT5M(One(D24(A))), EncodeT5M(One(D24(B))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' a=' + IntToStr(A) + ' b=' + IntToStr(B) +
    ' native=' + IntToStr(Code) + ' SENS=' + IntToStr(Expected and 255));
end;

{ Рекурсія з ДВОМА параметрами: самовиклик передає обидва аргументи.
  Тіло: (за-умовою ((менше? величина додаток) (як-є 0))
                  (так (додати величина (self (відняти величина 1) додаток)))) }
procedure CaseTwoParamRecursive(const Title: String; const BodyWords: TExactWords;
  const SelfBits: RawByteString; const A, B, Expected: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  Image := LowerBodyTwoParamsWithSelfELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))),
    EncodeT5M(NameNode(NameBits('додаток'))),
    EncodeT5M(One(D24(A))), EncodeT5M(One(D24(B))),
    EncodeT5M(NameNode(SelfBits)));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' a=' + IntToStr(A) + ' b=' + IntToStr(B) +
    ' native=' + IntToStr(Code) + ' direct=' + IntToStr(Expected and 255));
end;

{ G6.257: трипараметровий САМОВИКЛИК. Очікування — прямий математичний
  свідок (сума a+(a-1)+...+0, зсунута на c), бо pinned обчислювач не
  приймає цієї форми гілок; це позначено в назві випадку. }
procedure CaseThreeParamRecursive(const Title: String;
  const BodyWords: TExactWords; const SelfBits: RawByteString;
  const A, B, C, Expected: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  Image := LowerBodyThreeParamsWithSelfELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))),
    EncodeT5M(NameNode(NameBits('додаток'))),
    EncodeT5M(NameNode(NameBits('третя'))),
    EncodeT5M(One(D24(A))), EncodeT5M(One(D24(B))), EncodeT5M(One(D24(C))),
    EncodeT5M(NameNode(SelfBits)));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' a=' + IntToStr(A) + ' b=' + IntToStr(B) + ' c=' + IntToStr(C) +
    ' native=' + IntToStr(Code) + ' direct=' + IntToStr(Expected and 255));
end;

{ G6.260: самовиклик із 4..6 аргументами. Очікування — прямий свідок
  (d + b*a), бо pinned-обчислювач у цьому сеансі вже відмовляв. }
procedure CaseSelfN(const Title: String; const BodyWords: TExactWords;
  const SelfBits: RawByteString; const Args: array of LongWord;
  const Expected: LongWord);
var
  Keys, Vals: array of RawByteString;
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
  I: SizeInt;
  Shown: String;
begin
  SetLength(Keys, Length(Args));
  SetLength(Vals, Length(Args));
  Shown := '';
  for I := 0 to High(Args) do begin
    Keys[I] := EncodeT5M(NameNode(NameBits(ParamNames[I])));
    Vals[I] := EncodeT5M(One(D24(Args[I])));
    Shown := Shown + IntToStr(Args[I]) + ' ';
  end;
  Image := LowerBodyNParamsWithSelfELF(EncodeT5M(BodyWords), Keys, Vals,
    EncodeT5M(NameNode(SelfBits)));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' args=' + Shown + 'native=' + IntToStr(Code) +
    ' direct=' + IntToStr(Expected and 255));
end;

{ ВЗАЄМНА РЕКУРСІЯ: дві функції в одному ELF (evenodd).
  парне(n) = 1, якщо n < 1; інакше непарне(n-1)
  непарне(n) = 0, якщо n < 1; інакше парне(n-1) }
procedure CasePair(const Title: String; const BodyA, BodyB: TExactWords;
  const NameA, NameB: RawByteString; const Arg, Expected: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  Image := LowerPairELF(EncodeT5M(BodyA), EncodeT5M(NameNode(NameA)),
    EncodeT5M(BodyB), EncodeT5M(NameNode(NameB)),
    EncodeT5M(NameNode(NameBits('величина'))), EncodeT5M(One(D24(Arg))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' n=' + IntToStr(Arg) + ' native=' + IntToStr(Code) +
    ' direct=' + IntToStr(Expected and 255));
end;

{ Тіло з самовикликом і ЯВНО заданим очікуванням (не оракулом fib). }
procedure CaseSelfExpected(const Title: String; const BodyWords: TExactWords;
  const SelfBits: RawByteString; const Arg, Expected: LongWord);
var
  Image: RawByteString;
  Code: SizeInt;
  Ok: Boolean;
begin
  Image := LowerBodyWithSelfELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(NameBits('величина'))), EncodeT5M(One(D24(Arg))),
    EncodeT5M(NameNode(SelfBits)));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' arg=' + IntToStr(Arg) + ' native=' + IntToStr(Code) +
    ' expected=' + IntToStr(Expected and 255));
end;

{ Відмова перед емісією, якщо цитований атом не є точним D24.
  Тут не ототожнюємо D1/D7/D12 з числом за десятковою проєкцією. }
procedure CaseBadQuoteWidth(const Title: String; const BodyWords: TExactWords);
var
  ParamBits: RawByteString;
  Refused: Boolean;
begin
  ParamBits := NameBits('величина');
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(BodyWords),
      EncodeT5M(NameNode(ParamBits)), EncodeT5M(One(D24(1))));
  except
    on E: ELowerD24Error do Refused := True;
  end;
  Check(Refused, JoinUtf8(Title, ' — ширину відхилено до ELF'));
end;

{ G6.135: несуцільний D3:110 не є D24 результатом.
  Успіх тесту — контрольована відмова саме lowering, не runtime. }
procedure CaseBadCond(const Title: String; const BodyWords: TExactWords);
var
  Refused: Boolean;
  ParamBits: RawByteString;
begin
  ParamBits := NameBits('величина');
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(BodyWords),
      EncodeT5M(NameNode(ParamBits)), EncodeT5M(One(D24(1))));
  except
    on E: ELowerD24Error do Refused := True;
  end;
  Check(Refused, JoinUtf8(Title, ' — відмова до видачі ELF'));
end;

{ Недопустимий операнд EQ не породжує машинного ELF. На відміну
  від числового порівняння host, тут звіряється exact ширина/домен. }
{ Заборонені для scoped D5:11011 випадки мусять відмовити до ELF
  точним ELowerD24Error, а не породити «правдоподібне» машинне D1. }
procedure CaseBadGreater(const Title: String; const BodyWords: TExactWords);
var
  Refused: Boolean;
begin
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(BodyWords),
      EncodeT5M(NameNode(NameBits('величина'))),
      EncodeT5M(One(D24(5))));
  except
    on E: ELowerD24Error do Refused := True;
  end;
  Check(Refused, JoinUtf8(Title, ' — відмова до машинного ELF'));
end;

procedure CaseBadEq(const Title: String; const BodyWords: TExactWords);
var
  Refused: Boolean;
  ParamBits: RawByteString;
begin
  ParamBits := NameBits('величина');
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(BodyWords),
      EncodeT5M(NameNode(ParamBits)), EncodeT5M(One(D24(1))));
  except
    on E: ELowerD24Error do Refused := True;
  end;
  Check(Refused, JoinUtf8(Title, ' — точний домен відхилено до ELF'));
end;

procedure CaseBody(const Title: String; const BodyWords: TExactWords;
  const Arg: LongWord);
var
  ParamBits: RawByteString;
  Image: RawByteString;
  Expected: LongWord;
  Code: SizeInt;
  Ok: Boolean;
begin
  ParamBits := NameBits('величина');
  Expected := OracleValueNamed(BodyWords, ParamBits, Arg, '') and 255;
  Image := LowerBodyELF(EncodeT5M(BodyWords), EncodeT5M(NameNode(ParamBits)),
    EncodeT5M(One(D24(Arg))));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = Expected),
    Title + ' arg=' + IntToStr(Arg) + ' native=' + IntToStr(Code) +
    ' oracle=' + IntToStr(Expected));
end;

{ Фізичні негативи: невалідне D7-ім'я має зупинити lowering
  до будь-якої емісії x86-64. Звіряємо саме тип контрольованої відмови. }
procedure CaseBadPhysicalName(const Title: String;
  const ParamPhysical, SelfPhysical: RawByteString);
var
  Refused: Boolean;
begin
  Refused := False;
  try
    LowerBodyWithSelfELF(
      EncodeT5M(NameNode(NameBits('величина'))),
      ParamPhysical, EncodeT5M(One(D24(1))), SelfPhysical);
  except
    on E: ELowerD24Error do Refused := True;
  end;
  Check(Refused, JoinUtf8(Title, ' — явна відмова без ELF'));
end;

procedure CaseRecursive(const Title: String; const BodyWords: TExactWords;
  const SelfBits: RawByteString; const Arg: LongWord; const UseInterp: Boolean);
var
  ParamBits: RawByteString;
  Image: RawByteString;
  Code: SizeInt;
  Expected: LongWord;
  Ok: Boolean;
  A, B, T: QWord;
  I: LongWord;
begin
  ParamBits := NameBits('величина');
  if UseInterp then
    Expected := OracleValueNamed(BodyWords, ParamBits, Arg, SelfBits)
  else begin
    A := 0; B := 1;
    for I := 1 to Arg do begin T := A + B; A := B; B := T; end;
    Expected := A;
  end;
  Image := LowerBodyWithSelfELF(EncodeT5M(BodyWords),
    EncodeT5M(NameNode(ParamBits)), EncodeT5M(One(D24(Arg))),
    EncodeT5M(NameNode(SelfBits)));
  Ok := RunELF(Image, Code);
  Check(Ok and (LongWord(Code) = (Expected and 255)),
    Title + ' arg=' + IntToStr(Arg) + ' native=' + IntToStr(Code) +
    ' oracle=' + IntToStr(Expected and 255));
end;

var
  Param: RawByteString;
  ParamNode: TExactWords;
  ParamRef: TExactWords;
  Body: TExactWords;
  SelfBits: RawByteString;
  SelfNode, Param2Ref, Param3Ref: TExactWords;
  Param4Ref, Param5Ref, Param6Ref: TExactWords;
  BodyA, BodyB: TExactWords;
  Refused: Boolean;
begin
  Randomize;
  LoadPinnedD7Map(ParamStr(1), Map);
  Selector := TCore1Selektor.Create(ParamStr(1));
  Checks := 0; Failures := 0; DefCounter := 0;

  Param := NameBits('величина');

  ParamNode := NameNode(Param);
  { Посилання на параметр — сам вузол-імʼя, без зайвої обгортки. }
  ParamRef := ParamNode;
  Param2Ref := NameNode(NameBits('додаток'));
  Param3Ref := NameNode(NameBits('третя'));
  Param4Ref := NameNode(NameBits('четверта'));
  Param5Ref := NameNode(NameBits('пята'));
  Param6Ref := NameNode(NameBits('шоста'));

  { 1. (додати величина величина) }
  Body := Concat([One('10'), One('01010'), ParamRef, ParamRef, One('01')]);
  CaseBody('додати параметр параметр', Body, 7);
  CaseBody('додати параметр параметр', Body, 20);

  { 2. (додати (як-є 5) величина) }
  Body := Concat([One('10'), One('01010'), QuoteAtom(D24(5)), ParamRef, One('01')]);
  CaseBodyDirect('додати 5 параметр (прямий оракул)', Body, 7, 12);
  CaseBodyDirect('додати 5 параметр (прямий оракул)', Body, 30, 35);

  { 3. (відняти (як-є 10) величина) }
  Body := Concat([One('10'), One('01011'), QuoteAtom(D24(10)), ParamRef, One('01')]);
  CaseBodyDirect('відняти 10 параметр (прямий оракул)', Body, 3, 7);
  CaseBodyDirect('відняти 10 параметр (прямий оракул)', Body, 9, 1);

  { 4. вкладене: (додати (додати параметр (як-є 3)) (як-є 4)) }
  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), One('01010'), ParamRef, QuoteAtom(D24(3)), One('01')]),
    QuoteAtom(D24(4)), One('01')]);
  CaseBodyDirect('вкладене додавання (прямий оракул)', Body, 1, 8);
  CaseBodyDirect('вкладене додавання (прямий оракул)', Body, 11, 18);

  { Вкладене суто з параметрів — знову ОРАКУЛ SENS. }
  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), One('01010'), ParamRef, ParamRef, One('01')]),
    ParamRef, One('01')]);
  CaseBody('вкладене лише з параметрів', Body, 2);
  CaseBody('вкладене лише з параметрів', Body, 5);

  { G6.132 — signed D24 та порядок CMP, реальні native ELF.
    Ці прямі очікування є математичними контрольними свідками, а
    НЕ незалежним SENS REPL-оракулом; старі SENS-oracle тести вище живі. }
  Body := Concat([One('10'), One('11010'), ParamRef,
    QuoteAtom(D24(10)), One('01')]);
  CaseBodyDirect('верхній CMP: 3 < 10', Body, 3, 1);
  CaseBodyDirect('верхній CMP: 12 < 10 — ні', Body, 12, 0);
  CaseBodyDirect('верхній CMP: -1 < 10', Body, $FFFFFF, 1);
  CaseBodyDirect('верхній CMP: мінімум D24 < 10', Body, $800000, 1);
  CaseBodyDirect('верхній CMP: максимум D24 < 10 — ні', Body, $7FFFFF, 0);

  Body := Concat([One('10'), One('11010'), ParamRef,
    QuoteAtom(D24(0)), One('01')]);
  CaseBodyDirect('параметр -1 < 0', Body, $FFFFFF, 1);
  CaseBodyDirect('параметр -8388608 < 0', Body, $800000, 1);
  CaseBodyDirect('параметр 0 < 0 — ні', Body, 0, 0);
  CaseBodyDirect('параметр 1 < 0 — ні', Body, 1, 0);

  Body := Concat([One('10'), One('11010'), QuoteAtom(D24($FFFFFF)),
    ParamRef, One('01')]);
  CaseBodyDirect('цитата -1 < 0', Body, 0, 1);
  CaseBodyDirect('цитата -1 < -1 — ні', Body, $FFFFFF, 0);
  CaseBodyDirect('цитата -1 < -8388608 — ні', Body, $800000, 0);

  { Кожен не-D24 цитований атом має явно відхилятися,
    а не ставати схожим за 32-бітовим host-значенням. }
  CaseBadQuoteWidth('D1 у числовій цитаті', QuoteAtom('1'));
  CaseBadQuoteWidth('D7 у числовій цитаті', QuoteAtom('0000000'));
  CaseBadQuoteWidth('D12 у числовій цитаті', QuoteAtom('000000000001'));

  { G6.135: фізичні D3:110 з повним завершальним D1:1,
    виконувані ELF перевіряють дійсний порядок упорядкованих гілок.
    Прямі числові очікування тут НЕ є самостійним SENS REPL оракулом. }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(0)), One('01')]), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBodyDirect('COND -1: перша гілка', Body, $FFFFFF, 7);
  CaseBodyDirect('COND 0: остання гілка', Body, 0, 0);
  CaseBodyDirect('COND 12: остання гілка', Body, 12, 12);

  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(0)), One('01')]), QuoteAtom(D24(7))),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(10)), One('01')]), QuoteAtom(D24(4))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBodyDirect('COND три гілки -1', Body, $FFFFFF, 7);
  CaseBodyDirect('COND три гілки 5', Body, 5, 4);
  CaseBodyDirect('COND три гілки 12', Body, 12, 12);

  { Контракт K12.3: за відсутності істинної гілки — D3:000.
    У D24-only exit ABI такий результат не можна видати як 0. }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(0)), One('01')]), ParamRef), One('01')]);
  CaseBadCond('COND без завершального так', Body);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(0)), One('01')]), ParamRef),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(10)), One('01')]), ParamRef),
    One('01')]);
  CaseBadCond('COND дві умовні гілки без так', Body);
  Body := Concat([One('10'), One('110'),
    Clause(One('1'), ParamRef),
    Clause(Concat([One('10'), One('11010'), ParamRef,
      QuoteAtom(D24(10)), One('01')]), ParamRef), One('01')]);
  CaseBadCond('COND рання безумовна гілка', Body);
  Body := Concat([One('10'), One('110'),
    Clause(One('1'), ParamRef),
    Clause(One('1'), QuoteAtom(D24(2))), One('01')]);
  CaseBadCond('COND два безумовні переходи', Body);

  { G6.150: cond-test із pinned Contract 12.0 є саме D1:0/1.
    Точний D1:0 — безумовно хибна НЕ-остання гілка, яка
    знижується до XOR EAX,EAX; не D24 нуль і не truthiness. }
  Body := Concat([One('10'), One('110'),
    Clause(One('0'), QuoteAtom(D24(73))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBody('COND exact D1:0 -> наступна гілка (SENS oracle)', Body, 0);
  CaseBody('COND exact D1:0 -> наступна гілка (SENS oracle)', Body, 7);
  CaseBody('COND exact D1:0 -> наступна гілка (SENS oracle)',
    Body, $FFFFFF);

  { Дійсний pinned D3:101 повертає D1 для умови, не D24 число.
    Семантична звірка тут з реальним TCore1Selektor (не host арифметика). }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('101'), ParamRef, ParamRef,
      One('01')]), ParamRef),
    Clause(One('1'), QuoteAtom(D24(99))), One('01')]);
  CaseBody('COND exact EQ true -> тіло (SENS oracle)', Body, 0);
  CaseBody('COND exact EQ true -> тіло (SENS oracle)', Body, 17);
  CaseBody('COND exact EQ true -> тіло (SENS oracle)',
    Body, $800000);

  { Змішаний тест D5 «менше?» дозволено тільки з доведеним
    D24-операндом; вкладене D24 додавання зберігає його тип.
    Ці вектори мають ПРЯМЕ очікування, не самостійний SENS oracle. }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'),
      Concat([One('10'), One('01010'),
        ParamRef, QuoteAtom(D24(1)), One('01')]),
      QuoteAtom(D24(6)), One('01')]), QuoteAtom(D24(11))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBodyDirect('COND typed D24 додавання в D1 тесті (прямий)', Body, 3, 11);
  CaseBodyDirect('COND typed D24 додавання в D1 тесті (прямий)', Body, 9, 9);

  { Критичний негатив: D24:+1 має ту саму host-числову величину,
    але НЕ той самий домен/закон, що точний D1:1; жодного ELF. }
  Body := Concat([One('10'), One('110'),
    Clause(QuoteAtom(D24(1)), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND тест D24:1 НЕ є D1:1', Body);
  Body := Concat([One('10'), One('110'),
    Clause(QuoteAtom(D24(0)), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND тест D24:0 НЕ є D1:0', Body);
  Body := Concat([One('10'), One('110'),
    Clause(ParamRef, QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND лексичний параметр D24 НЕ є D1', Body);
  Body := Concat([One('10'), One('110'),
    Clause(QuoteAtom('000000000001'), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND цитата D12 НЕ є D1', Body);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('01010'), ParamRef,
      QuoteAtom(D24(1)), One('01')]), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND D5 додавання повертає D24, не D1', Body);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'),
      Concat([One('10'), One('101'), ParamRef, ParamRef, One('01')]),
      ParamRef, One('01')]), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND D5 менше? з D1 арифметичним операндом', Body);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11011'),
      ParamRef, QuoteAtom('000000000001'), One('01')]),
      QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND D5 більше? зі змішаним D12 операндом', Body);
  Body := Concat([One('10'), One('110'),
    Clause(One(D24(1)), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBadCond('COND голий D24:1 НЕ є D1:1', Body);

  { G6.139: D3:101 — фізична тотожність двох exact D24 атомів,
    native CMP/SETE/MOVZX видає точний D1. Повністю реальний
    TCore1Selektor (із pinned SENS) — oracle для параметр/параметр. }
  Body := Concat([One('10'), One('101'), ParamRef, ParamRef, One('01')]);
  CaseBody('тотожне? параметр параметр: 0 (SENS oracle)', Body, 0);
  CaseBody('тотожне? параметр параметр: -1 (SENS oracle)', Body, $FFFFFF);
  CaseBody('тотожне? параметр параметр: мінімум D24 (SENS oracle)',
    Body, $800000);
  CaseBody('тотожне? параметр параметр: максимум D24 (SENS oracle)',
    Body, $7FFFFF);

  { Для цитованих D24, які поточний обчислювач Core1 може не допускати,
    використовуємо ЯВНО окремий прямий oracle, без заяви parity. }
  Body := Concat([One('10'), One('101'), ParamRef,
    QuoteAtom(D24($FFFFFF)), One('01')]);
  CaseBodyDirect('тотожне? -1 == -1 (прямий oracle)', Body, $FFFFFF, 1);
  CaseBodyDirect('тотожне? 0 == -1 — ні (прямий oracle)', Body, 0, 0);
  CaseBodyDirect('тотожне? мінімум == -1 — ні (прямий oracle)',
    Body, $800000, 0);

  Body := Concat([One('10'), One('101'),
    QuoteAtom(D24($800000)), ParamRef, One('01')]);
  CaseBodyDirect('тотожне? мінімум D24 == мінімум (прямий oracle)',
    Body, $800000, 1);
  CaseBodyDirect('тотожне? максимум D24 == мінімум — ні (прямий oracle)',
    Body, $7FFFFF, 0);

  Body := Concat([One('10'), One('101'),
    QuoteAtom(D24(12)), QuoteAtom(D24(12)), One('01')]);
  CaseBodyDirect('тотожне? дві цитати D24 (прямий oracle)', Body, 3, 1);
  Body := Concat([One('10'), One('101'),
    QuoteAtom(D24(12)), QuoteAtom(D24(13)), One('01')]);
  CaseBodyDirect('тотожне? різні цитати D24 (прямий oracle)', Body, 3, 0);

  { Два параметри: перший у rdi, другий у rsi. }
  Body := Concat([One('10'), One('01010'),
    NameNode(NameBits('величина')), NameNode(NameBits('додаток')), One('01')]);
  CaseTwoParams('додати два параметри (прямий oracle)', Body, 3, 4, 7);
  CaseTwoParams('додати два параметри (прямий oracle)', Body, 100, 55, 155);
  { Порядок операндів важливий: перший — rdi, другий — rsi.
    (відняти величина додаток) = 9 - 4 = 5, і саме це відрізняє
    правильну передачу другого аргументу від переплутаної. }
  Body := Concat([One('10'), One('01011'),
    NameNode(NameBits('величина')), NameNode(NameBits('додаток')), One('01')]);
  CaseTwoParams('відняти rdi мінус rsi (прямий oracle)', Body, 9, 4, 5);
  CaseTwoParams('відняти rdi мінус rsi (прямий oracle)', Body, 4, 9, 251);

  { Двопараметрова РЕКУРСІЯ: сума від a вниз до b включно. }
  SelfBits := NameBits('сума-сенс');
  SelfNode := NameNode(SelfBits);
  Param2Ref := NameNode(NameBits('додаток'));
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, Param2Ref, One('01')]),
           QuoteAtom(D24(0))),
    Clause(One('1'),
      Concat([One('10'), One('01010'), ParamRef,
        Call2(SelfNode,
          Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
          Param2Ref),
        One('01')])),
    One('01')]);
  CaseTwoParamRecursive('сума вниз із двома параметрами (прямий oracle)',
    Body, SelfBits, 5, 0, 15);
  CaseTwoParamRecursive('сума вниз із двома параметрами (прямий oracle)',
    Body, SelfBits, 10, 0, 55);
  CaseTwoParamRecursive('сума вниз із двома параметрами (прямий oracle)',
    Body, SelfBits, 10, 7, 34);

  { ACKERMANN — три гілки й ВКЛАДЕНИЙ самовиклик у позиції аргументу.
    ack(m,n) = n+1                якщо m = 0
             = ack(m-1, 1)        якщо n = 0
             = ack(m-1, ack(m,n-1)) інакше
    Обчислювач SENS таке тіло не приймає (інша форма гілок), тому
    звірка з ПРЯМИМ оракулом — і це позначено в назві. }
  SelfBits := NameBits('акерман-сенс');
  SelfNode := NameNode(SelfBits);
  Param2Ref := NameNode(NameBits('додаток'));
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('101'), ParamRef, QuoteAtom(D24(0)), One('01')]),
           Concat([One('10'), One('01010'), Param2Ref, QuoteAtom(D24(1)), One('01')])),
    Clause(Concat([One('10'), One('101'), Param2Ref, QuoteAtom(D24(0)), One('01')]),
           Call2(SelfNode,
             Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
             QuoteAtom(D24(1)))),
    Clause(One('1'),
      Call2(SelfNode,
        Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
        Call2(SelfNode, ParamRef,
          Concat([One('10'), One('01011'), Param2Ref, QuoteAtom(D24(1)), One('01')])))),
    One('01')]);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 0, 3, 4);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 1, 2, 4);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 2, 2, 7);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 3, 3, 61);

  { ВЗАЄМНА РЕКУРСІЯ — четверте навантаження pinned списку. }
  BodyA := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(1))),
    Clause(One('1'), Call1(NameNode(NameBits('непарне')),
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  BodyB := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(0))),
    Clause(One('1'), Call1(NameNode(NameBits('парне')),
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 0, 1);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1, 0);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 2, 1);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 5, 0);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 8, 1);
  { ХВОСТОВА взаємна рекурсія: без TCO глибина n кадрів на кожній
    функції; 1 000 000 гарантовано переповнив би стек. }
  CasePair('парне/непарне хвіст n=1000000', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1000000, 1);
  CasePair('парне/непарне хвіст n=1000001', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1000001, 0);

  { ХВОСТОВА РЕКУРСІЯ. «Сума вниз» хвостовою НЕ є (додавання після
    виклику), тому вона законно впирається в стек. Хвостове тіло — те,
    де самовиклик є результатом гілки. }
  SelfBits := NameBits('хвіст-сенс');
  SelfNode := NameNode(SelfBits);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(7))),
    Clause(One('1'), Call1(SelfNode,
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  CaseSelfExpected('хвіст: n=5', Body, SelfBits, 5, 7);
  CaseSelfExpected('хвіст: n=1000000 — без TCO був би stack overflow',
    Body, SelfBits, 1000000, 7);
  CaseSelfExpected('хвіст: n=5000000 — без TCO був би stack overflow',
    Body, SelfBits, 5000000, 7);

  { ЗАХИСТ ВІД ПРОТІКАННЯ СТАНУ: одразу ПІСЛЯ парного зниження
    робимо звичайне однопараметрове. Якщо стан (пара, виправлення,
    хвостовий контекст) не відновлено — цей випадок зламається. }
  Body := Concat([One('10'), One('01010'), ParamRef, QuoteAtom(D24(5)), One('01')]);
  CaseBodyDirect('після парного зниження: додати 5 (прямий оракул)',
    Body, 10, 15);
  CaseBodyDirect('після парного зниження: додати 5 (прямий оракул)',
    Body, 1, 6);

  { EQ — дійсний предикат D1 всередині вже перевіреної D3:110. }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('101'), ParamRef,
      QuoteAtom(D24(5)), One('01')]), QuoteAtom(D24(7))),
    Clause(One('1'), ParamRef), One('01')]);
  CaseBodyDirect('EQ як умова: обрана гілка (прямий oracle)', Body, 5, 7);
  CaseBodyDirect('EQ як умова: резервна гілка (прямий oracle)', Body, 6, 6);

  { Крос-доменні лексичні аліаси, список та числовий вираз заборонені.
    Ніяка host-конверсія не може зробити їх D24 атомом. }
  CaseBadEq('EQ: цитата D1 проти D24', Concat([One('10'), One('101'),
    QuoteAtom('1'), ParamRef, One('01')]));
  CaseBadEq('EQ: цитата D12 проти D24', Concat([One('10'), One('101'),
    QuoteAtom('000000000001'), ParamRef, One('01')]));
  CaseBadEq('EQ: цитата D7 проти D24', Concat([One('10'), One('101'),
    QuoteAtom('0000000'), ParamRef, One('01')]));
  CaseBadEq('EQ: невідоме D7 імʼя', Concat([One('10'), One('101'),
    NameNode(NameBits('інше')), ParamRef, One('01')]));
  CaseBadEq('EQ: арифметичний вираз не атом', Concat([One('10'), One('101'),
    Concat([One('10'), One('01010'), ParamRef, ParamRef, One('01')]),
    ParamRef, One('01')]));
  CaseBadEq('EQ: надлишковий аргумент', Concat([One('10'), One('101'),
    ParamRef, ParamRef, ParamRef, One('01')]));

  { G6.147: ратифіковане pinned D5:11011 більше?
    ДВА D7 параметри: реальна SENS-функція й x86-64 CMP/SETG.
    Усі ці свідки порівнюються не з host арифметикою, а з executor. }
  Body := Concat([One('10'), One('11011'),
    NameNode(NameBits('величина')), NameNode(NameBits('додаток')),
    One('01')]);
  CaseTwoParamsOracle('більше?: +1 > 0', Body, 1, 0);
  CaseTwoParamsOracle('більше?: 0 > +1', Body, 0, 1);
  CaseTwoParamsOracle('більше?: -1 > 0', Body, $FFFFFF, 0);
  CaseTwoParamsOracle('більше?: 0 > -1', Body, 0, $FFFFFF);
  CaseTwoParamsOracle('більше?: -1 > мінімум', Body, $FFFFFF, $800000);
  CaseTwoParamsOracle('більше?: мінімум > -1', Body, $800000, $FFFFFF);
  CaseTwoParamsOracle('більше?: максимум > мінімум', Body, $7FFFFF, $800000);
  CaseTwoParamsOracle('більше?: мінімум > максимум', Body, $800000, $7FFFFF);
  CaseTwoParamsOracle('більше?: 5 > 5 — рівність', Body, 5, 5);
  CaseTwoParamsOracle('більше?: максимум > передмаксимум',
    Body, $7FFFFF, $7FFFFE);
  CaseTwoParamsOracle('більше?: передмаксимум > максимум',
    Body, $7FFFFE, $7FFFFF);

  { Позиція SETG у вкладеній D3 умові: тестове D1 обирає D24
    параметр без непроголошених конверсій. }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11011'),
      NameNode(NameBits('величина')),
      NameNode(NameBits('додаток')), One('01')]),
      NameNode(NameBits('величина'))),
    Clause(One('1'), NameNode(NameBits('додаток'))),
    One('01')]);
  CaseTwoParamsOracle('більше? як D3 умова: ліва гілка', Body, 17, 3);
  CaseTwoParamsOracle('більше? як D3 умова: права гілка', Body, 3, 17);
  CaseTwoParamsOracle('більше? як D3 умова: знакова межа', Body,
    $800000, $7FFFFF);

  { Фізичні негативи D5:11011, які будь-який host CMP спокусився б
    тихо порівняти як цілі. Жодних D1/D7/D12 як D24. }
  CaseBadGreater('більше?: бракує правого аргументу',
    Concat([One('10'), One('11011'), ParamRef, One('01')]));
  CaseBadGreater('більше?: надлишковий аргумент',
    Concat([One('10'), One('11011'),
      ParamRef, ParamRef, ParamRef, One('01')]));
  CaseBadGreater('більше?: D1 цитата проти D24',
    Concat([One('10'), One('11011'),
      QuoteAtom('1'), ParamRef, One('01')]));
  CaseBadGreater('більше?: D12 цитата проти D24',
    Concat([One('10'), One('11011'),
      QuoteAtom('000000000001'), ParamRef, One('01')]));
  CaseBadGreater('більше?: D7 цитата проти D24',
    Concat([One('10'), One('11011'),
      QuoteAtom('0000000'), ParamRef, One('01')]));
  CaseBadGreater('більше?: невідоме імʼя D7',
    Concat([One('10'), One('11011'),
      NameNode(NameBits('інше')), ParamRef, One('01')]));
  CaseBadGreater('більше?: змішування предиката D1 з числом',
    Concat([One('10'), One('11011'),
      Concat([One('10'), One('101'), ParamRef, ParamRef, One('01')]),
      ParamRef, One('01')]));
  CaseBadGreater('більше?: складений арифметичний операнд поза профілем',
    Concat([One('10'), One('11011'),
      Concat([One('10'), One('01010'), ParamRef, ParamRef, One('01')]),
      ParamRef, One('01')]));

  { Негатив: форма поза підмножиною — явна відмова. }
  Body := Concat([One('10'), One('100'), ParamRef, One('01')]);
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(Body), EncodeT5M(ParamNode), EncodeT5M(One(D24(1))));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, 'форма поза підмножиною відхилена');

  { Негатив: імʼя поза параметрами. }
  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), NameNode(NameBits('інше')), One('01')]), ParamRef, One('01')]);
  Refused := False;
  try
    LowerBodyELF(EncodeT5M(Body), EncodeT5M(ParamNode), EncodeT5M(One(D24(1))));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, 'імʼя поза параметрами відхилене');

  { G6.129: не сприймати сирий D7, недозамкнений список, D12-домішку,
    вкладені D2-межі та порожню назву як той самий фізичний ключ. }
  CaseBadPhysicalName('сирий D7 без меж',
    EncodeT5M(One(Copy(Param, 1, 7))), '');
  CaseBadPhysicalName('відсутня права D2-межа',
    EncodeT5M(Concat([One('10'), One(Copy(Param, 1, 7))])), '');
  CaseBadPhysicalName('D12-домішка до D7',
    EncodeT5M(Concat([One('10'), One(Copy(Param, 1, 7)),
      One(D24(1)), One('01')])), '');
  CaseBadPhysicalName('вкладені D2-межі',
    EncodeT5M(Concat([One('10'), One('10'),
      One(Copy(Param, 1, 7)), One('01'), One('01')])), '');
  CaseBadPhysicalName('порожнє імʼя', EncodeT5M(Concat([
    One('10'), One('01')])), '');

  { РЕКУРСІЯ: тіло фібоначі з самовикликом, зібране з точних слів. }
  SelfBits := NameBits('фіб-сенс');
  SelfNode := NameNode(SelfBits);
  CaseBadPhysicalName('незамкнене D7-імʼя власної функції',
    EncodeT5M(ParamNode), EncodeT5M(One(Copy(SelfBits, 1, 7))));
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(2)), One('01')]),
           ParamRef),
    Clause(One('1'),
      Concat([One('10'), One('01010'),
        Call1(SelfNode, Concat([One('10'), One('01011'), ParamRef,
          QuoteAtom(D24(1)), One('01')])),
        Call1(SelfNode, Concat([One('10'), One('01011'), ParamRef,
          QuoteAtom(D24(2)), One('01')])),
        One('01')])),
    One('01')]);
  { Малі n — оракул SENS; великі — прямий оракул (обчислювач має межу 32). }
  { Обчислювач SENS поки не приймає ЦЕ тіло, зібране вручну (інша форма
    гілок), тому рекурсивні випадки звіряються ПРЯМИМ оракулом, і це
    позначено в назві. Оракул SENS для рекурсії — окремий зріз. }
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 1, False);
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 5, False);
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 10, False);
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 15, False);
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 20, False);
  CaseRecursive('фібоначі (прямий оракул)', Body, SelfBits, 25, False);

  { ACKERMANN — три гілки й ВКЛАДЕНИЙ самовиклик у позиції аргументу.
    ack(m,n) = n+1                якщо m = 0
             = ack(m-1, 1)        якщо n = 0
             = ack(m-1, ack(m,n-1)) інакше
    Обчислювач SENS таке тіло не приймає (інша форма гілок), тому
    звірка з ПРЯМИМ оракулом — і це позначено в назві. }
  SelfBits := NameBits('акерман-сенс');
  SelfNode := NameNode(SelfBits);
  Param2Ref := NameNode(NameBits('додаток'));
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('101'), ParamRef, QuoteAtom(D24(0)), One('01')]),
           Concat([One('10'), One('01010'), Param2Ref, QuoteAtom(D24(1)), One('01')])),
    Clause(Concat([One('10'), One('101'), Param2Ref, QuoteAtom(D24(0)), One('01')]),
           Call2(SelfNode,
             Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
             QuoteAtom(D24(1)))),
    Clause(One('1'),
      Call2(SelfNode,
        Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
        Call2(SelfNode, ParamRef,
          Concat([One('10'), One('01011'), Param2Ref, QuoteAtom(D24(1)), One('01')])))),
    One('01')]);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 0, 3, 4);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 1, 2, 4);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 2, 2, 7);
  CaseTwoParamRecursive('акерман (прямий oracle)', Body, SelfBits, 3, 3, 61);

  { ВЗАЄМНА РЕКУРСІЯ — четверте навантаження pinned списку. }
  BodyA := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(1))),
    Clause(One('1'), Call1(NameNode(NameBits('непарне')),
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  BodyB := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(0))),
    Clause(One('1'), Call1(NameNode(NameBits('парне')),
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 0, 1);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1, 0);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 2, 1);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 5, 0);
  CasePair('парне/непарне (прямий oracle)', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 8, 1);
  { ХВОСТОВА взаємна рекурсія: без TCO глибина n кадрів на кожній
    функції; 1 000 000 гарантовано переповнив би стек. }
  CasePair('парне/непарне хвіст n=1000000', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1000000, 1);
  CasePair('парне/непарне хвіст n=1000001', BodyA, BodyB,
    NameBits('парне'), NameBits('непарне'), 1000001, 0);

  { ХВОСТОВА РЕКУРСІЯ. «Сума вниз» хвостовою НЕ є (додавання після
    виклику), тому вона законно впирається в стек. Хвостове тіло — те,
    де самовиклик є результатом гілки. }
  SelfBits := NameBits('хвіст-сенс');
  SelfNode := NameNode(SelfBits);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           QuoteAtom(D24(7))),
    Clause(One('1'), Call1(SelfNode,
      Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]))),
    One('01')]);
  CaseSelfExpected('хвіст: n=5', Body, SelfBits, 5, 7);
  CaseSelfExpected('хвіст: n=1000000 — без TCO був би stack overflow',
    Body, SelfBits, 1000000, 7);
  CaseSelfExpected('хвіст: n=5000000 — без TCO був би stack overflow',
    Body, SelfBits, 5000000, 7);

  { ЗАХИСТ ВІД ПРОТІКАННЯ СТАНУ: одразу ПІСЛЯ парного зниження
    робимо звичайне однопараметрове. Якщо стан (пара, виправлення,
    хвостовий контекст) не відновлено — цей випадок зламається. }
  Body := Concat([One('10'), One('01010'), ParamRef, QuoteAtom(D24(5)), One('01')]);
  CaseBodyDirect('після парного зниження: додати 5 (прямий оракул)',
    Body, 10, 15);
  CaseBodyDirect('після парного зниження: додати 5 (прямий оракул)',
    Body, 1, 6);

  Selector.Free;
  if Failures > 0 then begin
    Writeln('LOWER24-FAIL');
    Halt(1);
  end;
  { G6.257: ТРИ ПАРАМЕТРИ. Третій аргумент приходить у edx; перевіряємо
    не лише арифметику, а й що він НЕ переплутаний з першими двома:
    порядок (a,b,c) і (c,b,a) дає різні результати при нерівних входах. }
  Body := Concat([One('10'), One('01010'), ParamRef, Param2Ref, One('01')]);
  CaseThreeParamsOracle('три параметри: додати a b, третій не задіяний',
    Body, 3, 4, 100);
  Body := Concat([One('10'), One('01010'), Param2Ref, Param3Ref, One('01')]);
  CaseThreeParamsOracle('три параметри: додати b c (другий і третій)',
    Body, 100, 3, 4);
  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), One('01010'), ParamRef, Param2Ref, One('01')]),
    Param3Ref, One('01')]);
  CaseThreeParamsOracle('три параметри: (a+b)+c', Body, 1, 2, 3);
  CaseThreeParamsOracle('три параметри: (a+b)+c, знакові', Body, $FFFFFF, 2, 3);
  CaseThreeParamsOracle('три параметри: (a+b)+c, межа', Body, $7FFFFF, 0, 0);
  Body := Concat([One('10'), One('01010'), ParamRef,
    Concat([One('10'), One('01010'), Param2Ref, Param3Ref, One('01')]),
    One('01')]);
  CaseThreeParamsOracle('три параметри: a+(b+c) — інший порядок', Body, 1, 2, 3);
  CaseThreeParamsOracle('три параметри: a+(b+c), нерівні входи', Body, 7, 20, 300);
  Body := Concat([One('10'), One('01011'), Param3Ref, ParamRef, One('01')]);
  CaseThreeParamsOracle('три параметри: c−a (третій мінус перший)', Body, 5, 100, 12);
  CaseThreeParamsOracle('три параметри: c−a, від’ємний результат', Body, 9, 0, 4);

  { G6.257: триаргументний САМОВИКЛИК — і звичайний, і хвостовий.
    сума(a,b,c) = c, якщо a < 1; інакше сума(a-1, b, c+b).
    Очікування: c + b*a (для a >= 0) — прямий свідок, не той самий код. }
  SelfBits := NameBits('сума-три-сенс');
  SelfNode := NameNode(SelfBits);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           Param3Ref),
    Clause(One('1'),
      Call3(SelfNode,
        Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
        Param2Ref,
        Concat([One('10'), One('01010'), Param3Ref, Param2Ref, One('01')]))),
    One('01')]);
  CaseThreeParamRecursive('самовиклик трьох: сума a кроків по b від c',
    Body, SelfBits, 5, 2, 0, 10);
  CaseThreeParamRecursive('самовиклик трьох: a=0 — лише c',
    Body, SelfBits, 0, 7, 42, 42);
  CaseThreeParamRecursive('самовиклик трьох: великий a (хвіст)',
    Body, SelfBits, 200, 3, 1, (1 + 200*3) and 255);
  { Без TCO тут був би stack overflow: 200 000 кадрів по 32 байти — це 6 МБ.
    Той самий сенс, що й у двопараметрового випадку з n=5000000. }
  CaseThreeParamRecursive('самовиклик трьох: a=200000 — без TCO був би stack overflow',
    Body, SelfBits, 200000, 1, 0, (200000) and 255);

  { G6.258: чотири, пʼять і шість параметрів — регістри rcx, r8, r9.
    Кожен випадок перевіряє, що саме цей регістр доїхав: беремо суму
    всіх і окремо пари з різними входами. }
  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), One('01010'), ParamRef, Param2Ref, One('01')]),
    Concat([One('10'), One('01010'), Param3Ref, Param4Ref, One('01')]),
    One('01')]);
  CaseNParamsDirect('чотири параметри: (a+b)+(c+d)', Body, [1, 2, 3, 4], 10);
  CaseNParamsDirect('чотири параметри: (a+b)+(c+d), нерівні', Body, [10, 20, 30, 40], 100);
  Body := Concat([One('10'), One('01010'), Param4Ref, ParamRef, One('01')]);
  CaseNParamsDirect('чотири параметри: d+a — саме rcx', Body, [5, 0, 0, 9], 14);

  Body := Concat([One('10'), One('01010'),
    Concat([One('10'), One('01010'), ParamRef, Param2Ref, One('01')]),
    Concat([One('10'), One('01010'), Param3Ref, Param4Ref, One('01')]),
    One('01')]);
  CaseNParamsDirect('пʼять параметрів: (a+b)+(c+d), пʼятий не задіяний',
    Body, [1, 2, 3, 4, 100], 10);
  Body := Concat([One('10'), One('01010'), Param5Ref, ParamRef, One('01')]);
  CaseNParamsDirect('пʼять параметрів: e+a — саме r8', Body, [7, 0, 0, 0, 30], 37);

  Body := Concat([One('10'), One('01010'), Param6Ref, ParamRef, One('01')]);
  CaseNParamsDirect('шість параметрів: f+a — саме r9', Body, [11, 0, 0, 0, 0, 31], 42);
  Body := Concat([One('10'), One('01010'), Param6Ref, Param5Ref, One('01')]);
  CaseNParamsDirect('шість параметрів: f+e — r9 і r8', Body, [0, 0, 0, 0, 40, 2], 42);

  { G6.260: самовиклик із 4, 5 і 6 аргументами — той самий загальний
    шлях, що й для 1..3, тому тут важливо, що він НЕ зламав хвіст. }
  SelfBits := NameBits('сума-чотири-сенс');
  SelfNode := NameNode(SelfBits);
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(1)), One('01')]),
           Param4Ref),
    Clause(One('1'),
      Call4(SelfNode,
        Concat([One('10'), One('01011'), ParamRef, QuoteAtom(D24(1)), One('01')]),
        Param2Ref, Param3Ref,
        Concat([One('10'), One('01010'), Param4Ref, Param2Ref, One('01')]))),
    One('01')]);
  CaseSelfN('самовиклик чотирьох: d + b*a', Body, SelfBits, [5, 2, 0, 0], 10);
  CaseSelfN('самовиклик чотирьох: a=0 — лише d', Body, SelfBits, [0, 7, 9, 42], 42);
  CaseSelfN('самовиклик чотирьох: a=200000 — без TCO stack overflow',
    Body, SelfBits, [200000, 1, 0, 0], 200000 and 255);

  Writeln('LOWER24-PASS checks=', Checks);
  Writeln('LOWER24-LIMIT=subset-1-6-param-add-sub-less-greater-cond-selfcall-1-6-args-no-lists-no-GC');
end.
