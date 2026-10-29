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

procedure Check(Ok: Boolean; const Why: String);
begin
  Inc(Checks);
  if Ok then Writeln('LOWER24-OK   ', Why)
  else begin Writeln('LOWER24-ЗБІЙ ', Why); Inc(Failures); end;
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

function Clause(const Test, Body: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), Test, Body, One('01')]);
end;

function Call1(const NameNode, Arg: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg, One('01')]);
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
  SelfNode: TExactWords;
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

  { РЕКУРСІЯ: тіло фібоначі з самовикликом, зібране з точних слів. }
  SelfBits := NameBits('фіб-сенс');
  SelfNode := NameNode(SelfBits);
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

  Selector.Free;
  if Failures > 0 then begin
    Writeln('LOWER24-FAIL');
    Halt(1);
  end;
  Writeln('LOWER24-PASS checks=', Checks);
  Writeln('LOWER24-LIMIT=subset-one-param-add-sub-less-cond-selfcall-no-lists-no-GC');
end.
