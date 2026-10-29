{ Core1.6: живий FPC доказ другого й третього визначення сучасного Core1.
  Кожен виклик іде фізичним T5M; жодного текстового dispatch.
  Диференційний оракул для ПЕРШОГО визначення — уже злитий
  TCore1FirstRuntime: два незалежні шляхи мають дати ті самі байти. }
program TestCore1Selektor;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1selektor, wsm.core1first,
  wsm.core1index, wsm.core4runtime, wsm.binaryexec, wsm.d7text;

var
  Passed: SizeInt;
  Root: String;

procedure Check(Condition: Boolean; const Why: String);
begin
  Inc(Passed);
  if not Condition then raise Exception.Create('ПРОВАЛ: ' + Why);
end;

procedure WritePhysical(const Filename: String; const Physical: RawByteString);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(Filename, fmCreate);
  try
    if Length(Physical) > 0 then Stream.WriteBuffer(Physical[1], Length(Physical));
  finally
    Stream.Free;
  end;
end;

function D12(const Bits: String): RawByteString; forward;

function D12(const Bits: String): RawByteString;
var
  Words: TExactWords;
begin
  if Length(Bits) <> 12 then raise Exception.Create('не D12');
  SetLength(Words, 1);
  Words[0] := RawByteString(Bits);
  Result := EncodeT5M(Words);
end;

function D12Of(Value: SizeInt): RawByteString; forward;
function Bits24(Value: SizeInt): RawByteString; forward;
function Bits12(Value: SizeInt): RawByteString; forward;

function Bits12(Value: SizeInt): RawByteString;
var
  Bits: String;
  I: SizeInt;
begin
  if (Value < 0) or (Value > 2047) then raise Exception.Create('не D12');
  SetLength(Bits, 12);
  for I := 1 to 12 do
    if (Value and (1 shl (12 - I))) <> 0 then Bits[I] := '1' else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

function D12Of(Value: SizeInt): RawByteString;
begin
  Result := D12(Bits12(Value));
end;

{ Точний D24-атом: 24 біти доповняльного коду, зі знаком. }
function Bits24(Value: SizeInt): RawByteString;
var
  Bits: String;
  I: SizeInt;
  Unsigned: LongInt;
begin
  if (Value < -8388608) or (Value > 8388607) then raise Exception.Create('не D24');
  if Value < 0 then Unsigned := LongInt(16777216) + LongInt(Value)
  else Unsigned := LongInt(Value);
  SetLength(Bits, 24);
  for I := 1 to 24 do
    if (Unsigned and (1 shl (24 - I))) <> 0 then Bits[I] := '1' else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

function El(const Bits: String): RawByteString;
begin
  Result := RawByteString(Bits);
end;

{ (10 (10 <D7 ім'я> 01) (10 1110 <елементи> 01) 01) — та сама фізична
  форма, яку вже використовує перший Core1-зріз. Це host-побудовник
  тестового входу, не reader і не interpreter. }
function MakeCall(const NameBits: RawByteString;
  const Elements: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I, P, Count: SizeInt;
begin
  Count := Length(NameBits) div 7;
  if (Count = 0) or (Count * 7 <> Length(NameBits)) then
    raise Exception.Create('недопустима довжина D7');
  SetLength(Words, Count + Length(Elements) + 9);
  P := 0;
  Words[P] := '10'; Inc(P);
  Words[P] := '10'; Inc(P);
  for I := 0 to Count - 1 do begin
    Words[P] := Copy(NameBits, I * 7 + 1, 7); Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := '10'; Inc(P);
  Words[P] := '1110'; Inc(P);
  for I := 0 to High(Elements) do begin
    Words[P] := Elements[I]; Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := '01'; Inc(P);
  SetLength(Words, P);
  Result := EncodeT5M(Words);
end;

{ Незалежний оракул: D3:011 «решта» через TBinaryExecutor і
  D4:1001 «друге» через TCore4Runtime. Це ІНШИЙ шлях, ніж механізми юніта:
  ратифікована LISP-проєкція CADDR (lib/domains/d5.lisp) розкладає
  третій елемент саме як CADR(CDR x).
  Питання: чому це перевірка, а не другий закон? Чому аргумент цитовано?
  Хто звільняє тимчасові масиви слів? }
function CdrOnce(Bin: TBinaryExecutor;
  const Elements: array of RawByteString): TExactWords;
var
  Call, Quoted, List: TExactWords;
  Middle: RawByteString;
  I, N: SizeInt;
begin
  N := Length(Elements);
  { (10 011 (10 001 (10 <елементи> 01) 01) 01) }
  SetLength(List, N + 2);
  List[0] := '10';
  for I := 0 to N - 1 do List[I + 1] := Elements[I];
  List[High(List)] := '01';
  SetLength(Quoted, Length(List) + 3);
  Quoted[0] := '10'; Quoted[1] := '001';
  for I := 0 to High(List) do Quoted[I + 2] := List[I];
  Quoted[Length(List) + 2] := '01';
  SetLength(Call, Length(Quoted) + 3);
  Call[0] := '10'; Call[1] := '011';
  for I := 0 to High(Quoted) do Call[I + 2] := Quoted[I];
  Call[Length(Quoted) + 2] := '01';
  Middle := Bin.ExecutePhysicalT5M(EncodeT5M(Call));
  DecodeT5M(Middle, List);
  if (Length(List) < 2) or (List[0] <> '10') or
     (List[High(List)] <> '01') then
    raise Exception.Create('оракул D3:011 не повернув список');
  SetLength(Result, Length(List) - 2);
  for I := 1 to Length(List) - 2 do Result[I - 1] := List[I];
end;

function CadrOf(Exec: TCore4Runtime;
  const Elements: TExactWords): RawByteString;
var
  Call: TExactWords;
  I, N: SizeInt;
begin
  N := Length(Elements);
  { (10 1001 (10 1110 <елементи> 01) 01) }
  SetLength(Call, N + 6);
  Call[0] := '10'; Call[1] := '1001'; Call[2] := '10'; Call[3] := '1110';
  for I := 0 to N - 1 do Call[I + 4] := Elements[I];
  Call[N + 4] := '01'; Call[N + 5] := '01';
  Result := Exec.ExecutePhysicalCall(EncodeT5M(Call));
end;

function ComposedThird(Bin: TBinaryExecutor; Exec: TCore4Runtime;
  const Elements: array of RawByteString): RawByteString;
begin
  Result := CadrOf(Exec, CdrOnce(Bin, Elements));
end;

function ComposedCdrThird(Bin: TBinaryExecutor; Exec: TCore4Runtime;
  const Elements: array of RawByteString): RawByteString;
var
  Once: TExactWords;
begin
  Once := CdrOnce(Bin, Elements);
  Result := CadrOf(Exec, CdrOnce(Bin, Once));
end;

{ Незалежний оракул: вкладені D3:111/D3:001 збираються вручну,
  без обчислювача юніта. }
function QuoteRaw(const Datum: TExactWords): TExactWords;
var
  I: SizeInt;
begin
  SetLength(Result, Length(Datum) + 3);
  Result[0] := '10'; Result[1] := '001';
  for I := 0 to High(Datum) do Result[I + 2] := Datum[I];
  Result[High(Result)] := '01';
end;

{ (10 111 <цитоване A> <B як форма> 01): перший операнд — дане,
  другий — уже побудована форма, яку обчислювач обчислить сам. }
function ConsForm(const A, B: TExactWords): TExactWords;
var
  Left: TExactWords;
  I, P: SizeInt;
begin
  Left := QuoteRaw(A);
  SetLength(Result, Length(Left) + Length(B) + 3);
  P := 0;
  Result[P] := '10'; Inc(P);
  Result[P] := '111'; Inc(P);
  for I := 0 to High(Left) do begin Result[P] := Left[I]; Inc(P); end;
  for I := 0 to High(B) do begin Result[P] := B[I]; Inc(P); end;
  Result[P] := '01';
  SetLength(Result, P + 1);
end;

{ (111 (001 <маркер>) (111 (001 <a>) (111 (001 <b>) (001 ())))) }
function NestedCons(const Mark: TExactWords; const A, B: RawByteString): TExactWords;
var
  Empty, Inner, MarkList, Mid: TExactWords;
  I: SizeInt;
begin
  { Маркер — це СПИСОК D7-знаків, а не плоске слово: цитуємо його як список. }
  SetLength(MarkList, Length(Mark) + 2);
  MarkList[0] := '10';
  for I := 0 to High(Mark) do MarkList[I + 1] := Mark[I];
  MarkList[High(MarkList)] := '01';
  SetLength(Empty, 2); Empty[0] := '10'; Empty[1] := '01';
  SetLength(Inner, 1); Inner[0] := B;
  Mid := ConsForm(Inner, QuoteRaw(Empty));
  SetLength(Inner, 1); Inner[0] := A;
  Mid := ConsForm(Inner, Mid);
  Result := ConsForm(MarkList, Mid);
end;

{ (10 (10 <D7 ім'я> 01) <аргумент> <аргумент> 01) — виклик із N аргументів,
  кожен з яких є самостійним фізичним даним. }
function MakeCallArgs(const NameBits: RawByteString;
  const Elements: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I, P, Count: SizeInt;
begin
  Count := Length(NameBits) div 7;
  if (Count = 0) or (Count * 7 <> Length(NameBits)) then
    raise Exception.Create('недопустима довжина D7');
  SetLength(Words, Count + Length(Elements) + 5);
  P := 0;
  Words[P] := '10'; Inc(P);
  Words[P] := '10'; Inc(P);
  for I := 0 to Count - 1 do begin
    Words[P] := Copy(NameBits, I * 7 + 1, 7); Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  for I := 0 to High(Elements) do begin
    Words[P] := Elements[I]; Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  SetLength(Words, P);
  Result := EncodeT5M(Words);
end;

{ Знайти номер допущеного визначення за ЙОГО ТІЛОМ, а не за індексом:
  порядок і кількість допущених змінюються разом із механізмами. }
function ByBody(S: TCore1Selektor; const Body: String): SizeInt;
var
  I: SizeInt;
begin
  for I := 0 to S.AdmittedCount - 1 do
    if S.AdmittedBodyText(I) = Body then Exit(I);
  raise Exception.Create('немає допущеного тіла ' + Body);
end;

{ Виклик із ДВОМА списками-аргументами:
  (10 (10 <ім'я> 01) (10 1110 <a1> 01) (10 1110 <a2> 01) 01). }
{ Виклик з атомом D1 та списком-значенням. Аргументи тут передаються
  безпосередньо як фізичні дані; D4:1110 позначає саме список, а вкладені
  D2-дужки зберігають його елемент-список. }
function MakeCallAtomList(const NameBits: RawByteString;
  const AtomWord: RawByteString;
  const ListWords: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I, P, Count: SizeInt;
begin
  Count := Length(NameBits) div 7;
  SetLength(Words, Count + Length(ListWords) + 8);
  P := 0;
  Words[P] := '10'; Inc(P);
  { Голова виклику — ВЛАСНИЙ вузол-імʼя `10 <гліфи> 01`, а не окремі
    слова: саме так імʼя звʼязується з exact D7-послідовністю. }
  Words[P] := '10'; Inc(P);
  for I := 1 to Count do begin
    Words[P] := Copy(NameBits, (I - 1) * 7 + 1, 7); Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := AtomWord; Inc(P);
  Words[P] := '10'; Inc(P); Words[P] := '1110'; Inc(P);
  for I := 0 to High(ListWords) do begin
    Words[P] := ListWords[I]; Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := '01'; Inc(P);
  SetLength(Words, P);
  Result := EncodeT5M(Words);
end;

function MakeCallTwoLists(const NameBits: RawByteString;
  const First, Second: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I, P, Count: SizeInt;
  procedure PutList(const Items: array of RawByteString);
  var
    K: SizeInt;
  begin
    Words[P] := '10'; Inc(P);
    Words[P] := '1110'; Inc(P);
    for K := 0 to High(Items) do begin
      Words[P] := Items[K]; Inc(P);
    end;
    Words[P] := '01'; Inc(P);
  end;
begin
  Count := Length(NameBits) div 7;
  SetLength(Words, Count + Length(First) + Length(Second) + 10);
  P := 0;
  Words[P] := '10'; Inc(P);
  Words[P] := '10'; Inc(P);
  for I := 0 to Count - 1 do begin
    Words[P] := Copy(NameBits, I * 7 + 1, 7); Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  PutList(First);
  PutList(Second);
  Words[P] := '01'; Inc(P);
  SetLength(Words, P);
  Result := EncodeT5M(Words);
end;

function ExpectRefusal(S: TCore1Selektor; const Physical: RawByteString;
  const Why: String): Boolean;
var
  Answer: RawByteString;
begin
  Answer := '';
  try
    Answer := S.ExecutePhysicalCall(Physical);
  except
    on E: Exception do begin
      Check(Answer = '', Why + ': відмова не має лишати часткової відповіді');
      Exit(True);
    end;
  end;
  Check(False, Why + ': очікувалася відмова, отримано ' + IntToStr(Length(Answer)) + ' байт');
  Result := False;
end;

var
  S: TCore1Selektor;
  First: TCore1FirstRuntime;
  Index: TCore1Index;
  A, B, C, D, Oracle: RawByteString;
  Mark: RawByteString;
  MarkWords, Built: TExactWords;
  Map: TD7Map;
  Upstream: String;
  Bin: TBinaryExecutor;
  Exec: TCore4Runtime;
  Answer, ViaFirst: RawByteString;
  Bad, Name: RawByteString;
  OutDir: String;
  Idx: array[0..9] of SizeInt;
  FoundIdx, DefIdx, NameEqIdx, PlusIdx, MinusIdx, TimesIdx,
  OneIdx, TwoIdx, ZeroIdx, IncIdx, NegIdx, QuotIdx, RemIdx: SizeInt;
  ZeroDiv: Boolean;
  MarkIdx, NamesEq: SizeInt;
  Words: TExactWords;
  Glyphs, I: SizeInt;
begin
  Passed := 0;
  Root := ParamStr(1);
  if Root = '' then raise Exception.Create('потрібен корінь робочого дерева');
  A := El('0000001'); B := El('0000010'); C := El('0000100'); D := El('0001000');
  S := TCore1Selektor.Create(Root);
  First := nil;
  Index := nil;
  Upstream := IncludeTrailingPathDelimiter(ExpandFileName(Root)) +
    'external' + PathDelim + 'sens';
  Bin := TBinaryExecutor.Create(
    RawByteString(IncludeTrailingPathDelimiter(ExpandFileName(Root)) +
      'external' + PathDelim + 'sens'));
  Exec := TCore4Runtime.Create(Root);
  try
    { 0. Номери допущених визначень шукаємо за тілом, не за індексом. }
  Idx[0] := ByBody(S, 'D4:1001(arg0)');
  Idx[1] := ByBody(S, 'D5:10011(arg0)');
  Idx[2] := ByBody(S, 'D5:10011(D3:011(arg0))');
  Idx[3] := ByBody(S, 'D3:111(D3:001(datum),D3:111(arg0,D3:111(arg1,D3:001(datum))))');
  Idx[4] := ByBody(S, 'D3:111(arg0,D3:001(datum))');
  Idx[5] := ByBody(S, 'D3:100(arg0)');

  { 1. Допущено щонайменше три визначення; порядок = порядок pinned коренів. }
    Check(S.AdmittedCount >= 3, 'допущено менше трьох визначень Core1');

    { 2. Тіла в точних pinned координатах — жодного вигаданого закону. }
    Check(S.AdmittedBodyText(Idx[0]) = 'D4:1001(arg0)', 'тіло D4:1001(arg0) не знайдено');
    Check(S.AdmittedBodyText(Idx[1]) = 'D5:10011(arg0)', 'тіло D5:10011(arg0) не знайдено');
    Check(S.AdmittedBodyText(Idx[2]) = 'D5:10011(D3:011(arg0))', 'тіло D5:10011(D3:011(arg0)) не знайдено');
    Check(S.AdmittedBodyText(Idx[3]) =
      'D3:111(D3:001(datum),D3:111(arg0,D3:111(arg1,D3:001(datum))))',
      'вкладене D3:111-тіло не знайдено');
    Check(S.AdmittedParamCount(Idx[0]) = 1, 'у D4:1001 має бути один параметр');
    Check(S.AdmittedParamCount(Idx[3]) = 2, 'у вкладеного D3:111 має бути два параметри');

    { 4. Точні D7-ключі збігаються з незалежним чинним індексом Core1. }
    Index := TCore1Index.Create(Root);
    Check(Index.Count = 96, 'pinned Core1 має 96 визначень, є ' + IntToStr(Index.Count));
    Check(Index.Definition(1).NameBits = S.AdmittedName(Idx[0]), 'D7-ключ 0 розійшовся з індексом');
    Check(Index.Definition(2).NameBits = S.AdmittedName(Idx[1]), 'D7-ключ 1 розійшовся з індексом');
    Check(Index.Definition(3).NameBits = S.AdmittedName(Idx[2]), 'D7-ключ 2 розійшовся з індексом');

    { 5. ДРУГЕ визначення: друге з трьох. }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[0]), [A, B, C]));
    Check(Answer = EncodeT5M([B]), 'друге з (a b c) має бути b');

    { 6. Диференційний оракул: той самий виклик через уже злитий
         TCore1FirstRuntime дає ті самі байти. }
    First := TCore1FirstRuntime.Create(
      IncludeTrailingPathDelimiter(ExpandFileName(Root)) + 'external' + PathDelim + 'sens',
      Root);
    ViaFirst := First.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[0]), [A, B, C]));
    Check(ViaFirst = Answer, 'перший зріз і новий зріз розійшлися на D4:1001');

    { 7. ДРУГЕ pinned визначення: третє з трьох (D5:10011). }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[1]), [A, B, C]));
    Check(Answer = EncodeT5M([C]), 'третє з (a b c) має бути c');
    Check(Answer <> EncodeT5M([B]), 'третє не має дорівнювати другому');

    { 7b. Незалежний оракул: та сама координата через D3:011 + D4:1001
         дає ті самі байти, що й нативний D5:10011. }
    Oracle := ComposedThird(Bin, Exec, [A, B, C]);
    Check(Oracle = Answer, 'D5:10011 розійшовся з композицією CADR(CDR x)');

    { 8. ТРЕТЄ pinned визначення: третє від решти, тобто четверте. }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[2]), [A, B, C, D]));
    Check(Answer = EncodeT5M([D]), 'третє від решти (a b c d) має бути d');
    Oracle := ComposedCdrThird(Bin, Exec, [A, B, C, D]);
    Check(Oracle = EncodeT5M([D]), 'композиція не дала четвертого елемента');

    { 9. Відповідь є канонічним T5M: повторне кодування не змінює байтів. }
    DecodeT5M(Answer, Words);
    Check(EncodeT5M(Words) = Answer, 'відповідь не є канонічним T5M');

    { 9b. ПЕРШЕ визначення з ДВОМА параметрами: ядро1-створити-помилку.
         Незалежний оракул маркера: беремо його НЕ з фізичного core1.sens,
         а з pinned ук-проєкції через наявний D7-кодек wsm.d7text. }
    LoadPinnedD7Map(Root, Map);
    Mark := EncodeD7Text(RawByteString('ядро1-запис-помилки'), Map, dsUk);
    DecodeT5M(Mark, MarkWords);
    Check(Length(MarkWords) = 19, 'маркер запису має 19 D7-знаків, є ' +
      IntToStr(Length(MarkWords)));
    Answer := S.ExecutePhysicalCall(MakeCallArgs(S.AdmittedName(Idx[3]), [A, B]));

    { Той самий результат через ЧИСТИЙ TBinaryExecutor без обчислювача:
         вкладені D3:111/D3:001, зібрані вручну. }
    Oracle := Bin.ExecutePhysicalT5M(EncodeT5M(NestedCons(MarkWords, A, B)));
    Check(Answer = Oracle, 'створити-помилку розійшлося з чистим D3:111');

    { Структурна звірка самої відповіді: (маркер вид подробиці), де маркер —
         це список D7-знаків, а не плоске ім'я. }
    DecodeT5M(Answer, Built);
    Check((Length(Built) = Length(MarkWords) + 6) and (Built[0] = '10') and
      (Built[1] = '10') and (Built[Length(MarkWords) + 2] = '01'),
      'відповідь має бути списком із вкладеним маркером');
    for I := 0 to High(MarkWords) do
      Check(Built[I + 2] = MarkWords[I], 'знак маркера ' + IntToStr(I));
    Check(Built[Length(MarkWords) + 3] = A, 'перший аргумент не збережено');
    Check(Built[Length(MarkWords) + 4] = B, 'другий аргумент не збережено');
    Check(Built[High(Built)] = '01', 'список не закрито');

    { 9d. Ще два допущені визначення з тим самим обчислювачем:
         сполучити значення з порожнім списком і перше з аргументу. }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[4]), [A, B, C]));
    Check(Answer = EncodeT5M(['10', '10', A, B, C, '01', '01']),
      'сполучити значення з (як-є ()) має дати ((a b c))');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(Idx[5]), [A, B, C]));
    Check(Answer = EncodeT5M([A]), 'перше з (a b c) має бути a');

    { 9e. Перший ПРЕДИКАТ Core1: ядро1-знайдено? = хибне?(атом?(x)).
         Тіло D4:0100(D3:010(arg0)) — два ратифіковані предикати.
         Атом → D1:0, список → D1:1; жодного host-boolean. }
    FoundIdx := ByBody(S, 'D4:0100(D3:010(arg0))');
    Answer := S.ExecutePhysicalCall(MakeCallArgs(S.AdmittedName(FoundIdx), [A]));
    Check(Answer = EncodeT5M(['0']), 'знайдено?(атом) має бути D1:0');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(FoundIdx), [A, B]));
    Check(Answer = EncodeT5M(['1']), 'знайдено?(список) має бути D1:1');

    { 9f. ПЕРШЕ визначення, яке ВИКЛИКАЄ ІНШЕ: ядро1-визначення?
         тіло = D3:110(атом?->D1:0; тотожне?(перше, як-є визначити)->D1:1; D1:1->D1:0)
         і воно кличе ядро1-назва-визначення? — тобто два рівні викликів. }
    DefIdx := ByBody(S,
      'D3:110(D3:010(arg0)->D1:0;call(D3:100(arg0))->D1:1;D1:1->D1:0)');
    Answer := S.ExecutePhysicalCall(MakeCallArgs(S.AdmittedName(DefIdx), [A]));
    Check(Answer = EncodeT5M(['0']), 'визначення?(атом) має бути D1:0');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(DefIdx), [El('0011'), A]));
    Check(Answer = EncodeT5M(['1']), 'визначення?((визначити ...)) має бути D1:1');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(DefIdx), [A, B]));
    Check(Answer = EncodeT5M(['0']), 'визначення?((a b)) має бути D1:0');

    { 9g. ПЕРШЕ РЕКУРСИВНЕ визначення Core1: ядро1-назви-рівні?
         тіло кличе СЕБЕ: тотожне?(перше a, перше b) → рекурсія на решті.
         Мітка D5:00100 більше не блокує: самопосилання йде звичайним
         точним D7-шляхом, а глибину тримає межа обчислення. }
    NameEqIdx := ByBody(S,
      'D3:110(D3:010(arg0)->D3:110(D3:010(arg1)->D3:101(arg0,arg1);D1:1->D1:0);' +
      'D3:010(arg1)->D1:0;call(D3:100(arg0),D3:100(arg1))->call(D3:011(arg0),D3:011(arg1));' +
      'D1:1->D1:0)');
    Answer := S.ExecutePhysicalCall(
      MakeCallTwoLists(S.AdmittedName(NameEqIdx), [A, B], [A, B]));
    Check(Answer = EncodeT5M(['1']), 'назви-рівні?((a b),(a b)) має бути D1:1');
    Answer := S.ExecutePhysicalCall(
      MakeCallTwoLists(S.AdmittedName(NameEqIdx), [A, B], [A, C]));
    Check(Answer = EncodeT5M(['0']), 'назви-рівні?((a b),(a c)) має бути D1:0');

    { 9h. ПЕРША АРИФМЕТИКА в обчислювачі Core1: D5:01010/01011/10110
         через наявні wsm.numericadd/numericsub/numericmul. Оракул —
         просте точне D12-значення, обчислене в тесті. }
    PlusIdx := ByBody(S, 'D5:01010(arg0,arg1)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(PlusIdx), [Bits12(5), Bits12(3)]));
    Check(Answer = D12Of(8), 'додати 5 і 3 має бути 8');
    MinusIdx := ByBody(S, 'D5:01011(arg0,arg1)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(MinusIdx), [Bits12(5), Bits12(3)]));
    Check(Answer = D12Of(2), 'відняти 5 і 3 має бути 2');
    TimesIdx := ByBody(S, 'D5:10110(arg0,arg1)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(TimesIdx), [Bits12(5), Bits12(3)]));
    Check(Answer = D12Of(15), 'помножити 5 і 3 має бути 15');

    { 9i. D4:0101 (порожнє?) і D4:0111 (решта-решти): предикати довжини.
         одна-величина? = атом?→0; порожнє?(решта x)→1; інакше 0. }
    OneIdx := ByBody(S,
      'D3:110(D3:010(arg0)->D1:0;D4:0101(D3:011(arg0))->D1:1;D1:1->D1:0)');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(OneIdx), [A]));
    Check(Answer = EncodeT5M(['1']), 'одна-величина?((a)) має бути D1:1');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(OneIdx), [A, B]));
    Check(Answer = EncodeT5M(['0']), 'одна-величина?((a b)) має бути D1:0');
    TwoIdx := ByBody(S,
      'D3:110(D3:010(arg0)->D1:0;D3:010(D3:011(arg0))->D1:0;' +
      'D4:0101(D3:011(D3:011(arg0)))->D1:1;D1:1->D1:0)');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(TwoIdx), [A, B]));
    Check(Answer = EncodeT5M(['1']), 'дві-величини?((a b)) має бути D1:1');
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(TwoIdx), [A]));
    Check(Answer = EncodeT5M(['0']), 'дві-величини?((a)) має бути D1:0');

    { 9j. СТАЛІ СВІТУ з pinned core4.sens (D24:0 і D24:1) + числові
         порівняння D5:11010/11011. Умова виходу з рекурсії. }
    Check(S.ConstantCount = 2, 'світ має рівно дві атомні сталі Core4, є ' +
      IntToStr(S.ConstantCount));
    ZeroIdx := ByBody(S,
      'D3:110(D5:11010(arg0,const)->D3:010(D3:111(D3:001(datum),D3:001(datum)));' +
      'D5:11011(arg0,const)->D3:010(D3:111(D3:001(datum),D3:001(datum)));' +
      'D1:1->D3:010(D3:001(datum)))');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(ZeroIdx), [Bits24(0)]));
    Check(Answer = EncodeT5M(['1']), 'нуль?(0) має бути D1:1');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(ZeroIdx), [Bits24(5)]));
    Check(Answer = EncodeT5M(['0']), 'нуль?(5) має бути D1:0');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(ZeroIdx), [Bits24(-5)]));
    Check(Answer = EncodeT5M(['0']), 'нуль?(-5) має бути D1:0');
    IncIdx := ByBody(S, 'D5:01010(arg0,const)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(IncIdx), [Bits24(5)]));
    Check(Answer = EncodeT5M([Bits24(6)]), 'збільшити-на-один(5) має бути 6');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(IncIdx), [Bits24(-1)]));
    Check(Answer = EncodeT5M([Bits24(0)]), 'збільшити-на-один(-1) має бути 0');

    { 9k. D6:010010 «змінити-знак»: доповняльне заперечення точного D24. }
    NegIdx := ByBody(S, 'D6:010010(arg0)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(NegIdx), [Bits24(5)]));
    Check(Answer = EncodeT5M([Bits24(-5)]), 'обернути-знак(5) має бути -5');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(NegIdx), [Bits24(-5)]));
    Check(Answer = EncodeT5M([Bits24(5)]), 'обернути-знак(-5) має бути 5');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(NegIdx), [Bits24(0)]));
    Check(Answer = EncodeT5M([Bits24(0)]), 'обернути-знак(0) має бути 0');

    { 9l. Ділення й остача точних D24: частка відсікає до нуля,
         остача має знак діленого. }
    QuotIdx := ByBody(S, 'D5:10111(arg0,arg1)');
    RemIdx := ByBody(S, 'D6:010100(arg0,arg1)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(QuotIdx), [Bits24(7), Bits24(2)]));
    Check(Answer = EncodeT5M([Bits24(3)]), 'частка(7,2) має бути 3');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(RemIdx), [Bits24(7), Bits24(2)]));
    Check(Answer = EncodeT5M([Bits24(1)]), 'остача(7,2) має бути 1');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(QuotIdx), [Bits24(-7), Bits24(2)]));
    Check(Answer = EncodeT5M([Bits24(-3)]), 'частка(-7,2) має бути -3');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(RemIdx), [Bits24(-7), Bits24(2)]));
    Check(Answer = EncodeT5M([Bits24(-1)]), 'остача(-7,2) має бути -1');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(RemIdx), [Bits24(7), Bits24(-2)]));
    Check(Answer = EncodeT5M([Bits24(1)]), 'остача(7,-2) має бути 1');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(QuotIdx), [Bits24(-7), Bits24(-2)]));
    Check(Answer = EncodeT5M([Bits24(3)]), 'частка(-7,-2) має бути 3');

    { 9m. Негатив: ділення на нуль — явна відмова, не вигадане число. }
    ZeroDiv := False;
    try
      S.ExecutePhysicalCall(
        MakeCallArgs(S.AdmittedName(QuotIdx), [Bits24(7), Bits24(0)]));
    except
      on E: Exception do ZeroDiv := True;
    end;
    Check(ZeroDiv, 'частка(7,0) має бути відмовою');

    { 9n. D4:1110 оживляє GC-визначення Core1: вони будують пару
         (сірі чорні) списком, без host-масиву.
         (позначити-комірку a ()) → памʼять порожня → порожнеча. }
    MarkIdx := ByBody(S,
      'D3:110(D4:0101(call(arg0,arg1))->D3:001(datum);D1:1->D4:1110(arg0))');
    Answer := S.ExecutePhysicalCall(
      MakeCallTwoLists(S.AdmittedName(MarkIdx), [A], []));
    Check((Answer = EncodeT5M(['10', '01'])) or (Answer = EncodeT5M(['000'])),
      'позначити-комірку у порожній памʼяті має дати порожнечу');
    { 9o. Закон порівняння назв: атоми, списки й порожнеча.
         Саме ця перевірка пояснює, чому пошук комірки не знаходив пару. }
    NamesEq := ByBody(S,
      'D3:110(D3:010(arg0)->D3:110(D3:010(arg1)->D3:101(arg0,arg1);D1:1->D1:0);' +
      'D3:010(arg1)->D1:0;call(D3:100(arg0),D3:100(arg1))->call(D3:011(arg0),D3:011(arg1));' +
      'D1:1->D1:0)');
    Answer := S.ExecutePhysicalCall(
      MakeCallArgs(S.AdmittedName(NamesEq), [A, A]));
    Check(Answer = EncodeT5M(['1']), 'назви-рівні?(a,a) має бути D1:1');
    Answer := S.ExecutePhysicalCall(
      MakeCallTwoLists(S.AdmittedName(NamesEq), [A], [A]));
    Check(Answer = EncodeT5M(['1']), 'назви-рівні?((a),(a)) має бути D1:1');
    Answer := S.ExecutePhysicalCall(
      MakeCallTwoLists(S.AdmittedName(NamesEq), [], []));
    Check(Answer = EncodeT5M(['1']), 'назви-рівні?((),()) має бути D1:1');

    { 9p. ПОЗИТИВНА гілка GC-пошуку: посилання — D1-атом a, памʼять —
         ((a)). D4:1110 задає список памʼяті, а вкладена D2-форма — його
         єдину комірку. Результат бібліотечного визначення має бути (a). }
    Answer := S.ExecutePhysicalCall(
      MakeCallAtomList(S.AdmittedName(MarkIdx), A,
        ['10', A, '01']));
    Check(Answer = EncodeT5M(['10', A, '01']),
      'позначити-комірку має знайти наявну комірку й повернути (a)');
    { Та сама фізична форма з іншим точним атомом не збігається. }
    Answer := S.ExecutePhysicalCall(
      MakeCallAtomList(S.AdmittedName(MarkIdx), B,
        ['10', A, '01']));
    Check((Answer = EncodeT5M(['10', '01'])) or
      (Answer = EncodeT5M(['000'])),
      'позначити-комірку має повернути порожнечу для чужого посилання');

    { 10. Негативні: закороткий список — явна відмова, не порожнеча. }
    ExpectRefusal(S, MakeCall(S.AdmittedName(Idx[1]), [A, B]), 'третє з двох елементів');
    ExpectRefusal(S, MakeCall(S.AdmittedName(Idx[1]), [A]), 'третє з одного елемента');
    ExpectRefusal(S, MakeCall(S.AdmittedName(Idx[2]), [A, B, C]), 'третє від решти трьох');
    ExpectRefusal(S, MakeCallArgs(S.AdmittedName(Idx[3]), [A]), 'створити-помилку з одним аргументом');
    ExpectRefusal(S, MakeCallArgs(S.AdmittedName(Idx[3]), [A, B, C]), 'створити-помилку з трьома аргументами');

    { 11. Негатив: чужий D7-ключ не переадресовується на перше замикання. }
    ExpectRefusal(S, MakeCall(StringOfChar('1', 14), [A, B, C]), 'чужий D7-ключ');

    { 12. Негатив: аргумент не є D4:1110 списком (точний атом замість списку). }
    Name := S.AdmittedName(Idx[1]);
    Glyphs := Length(Name) div 7;
    SetLength(Words, Glyphs + 5);
    Words[0] := '10';
    Words[1] := '10';
    for I := 0 to Glyphs - 1 do
      Words[I + 2] := Copy(Name, I * 7 + 1, 7);
    Words[Glyphs + 2] := '01';
    Words[Glyphs + 3] := '0000001';
    Words[Glyphs + 4] := '01';
    ExpectRefusal(S, EncodeT5M(Words), 'атомарний аргумент');

    { 13. Негатив: пошкоджений T5M не дає часткової відповіді. }
    Bad := MakeCall(S.AdmittedName(Idx[1]), [A, B, C]);
    Bad := Copy(Bad, 1, Length(Bad) - 1) + #$FF;
    ExpectRefusal(S, Bad, 'пошкоджений T5M');

    { 14. Негатив: порожній вхід. }
    ExpectRefusal(S, '', 'порожній виклик');

    { Фізичні входи для CLI пишуться ТИМ САМИМ EncodeT5M: жодного
      другого кодера в тестовій обв'язці. }
    OutDir := ParamStr(2);
    if OutDir <> '' then begin
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-0.sens',
        MakeCall(S.AdmittedName(Idx[0]), [A, B, C]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-1.sens',
        MakeCall(S.AdmittedName(Idx[1]), [A, B, C]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-2.sens',
        MakeCall(S.AdmittedName(Idx[2]), [A, B, C, D]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-short.sens',
        MakeCall(S.AdmittedName(Idx[1]), [A, B]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-3.sens',
        MakeCallArgs(S.AdmittedName(Idx[3]), [A, B]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-3-short.sens',
        MakeCallArgs(S.AdmittedName(Idx[3]), [A]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-alien.sens',
        MakeCall(StringOfChar('1', 14), [A, B, C]));
      Bad := MakeCall(S.AdmittedName(Idx[1]), [A, B, C]);
      Bad := Copy(Bad, 1, Length(Bad) - 1) + #$FF;
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-bad.sens', Bad);
    end;

    Writeln('CORE1-SELEKTOR-ГАРАЗД перевірок=', Passed);
    { Машинні маркери навмисно ASCII: їх звіряє shell незалежно від локалі. }
    Writeln('CORE1-SELEKTOR-PASS checks=', Passed);
    Writeln('CORE1-SELEKTOR-LIMIT=not-full-Core1-no-GC-no-REPL-no-native-backend');
  finally
    Exec.Free;
    Bin.Free;
    Index.Free;
    First.Free;
    S.Free;
  end;
end.
