{ Core1.7: фізичний обчислювач сучасного Core1 з лексичним середовищем.
  Тіло замикання обчислюється рекурсивно ЛИШЕ з ратифікованих координат:
  D3:001 (як-є), D3:011 (решта), D3:100 (перше), D3:111 (сполучити),
  D4:1001 (друге), D5:10011 (третє). Жодного власного реєстру законів,
  жодної копії бібліотечних DEFINE, жодного текстового dispatch.

  Механізми не вигадані: D3-форми виконує наявний TBinaryExecutor,
  D4/D5-селектори — наявний TCore4Runtime. Тут лише середовище,
  позиційне зв'язування параметрів і рекурсія по фізичному AST.

  Виконуються Roots[0..3] pinned lib/core1.sens:
  ядро1-другий-елемент, ядро1-третій-елемент, ядро1-четвертий-елемент,
  ядро1-створити-помилку (перше визначення з ДВОМА параметрами).

  Це НЕ повний Core1 (96 визначень), не арифметика D12+, не GC, не REPL. }
unit wsm.core1selektor;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.core4runtime, wsm.binaryexec;

type
  ECore1SelektorError = class(Exception);

  { Приватний сигнал admission: тіло не є підтриманою композицією.
    Він не є станом SENS і не виходить за межі конструктора. }
  EUnsupportedCore1Body = class(Exception);

  { Точний механізм, а не назва функції: кожен член відповідає
    одній ратифікованій координаті домену. }
  TCore1Mechanism = (cmQuote, cmCons, cmRest, cmFirst, cmSecond, cmThird,
    cmAtom, cmNot, cmEq, cmCond, cmPlus, cmMinus, cmTimes,
    cmNull, cmCdar, cmCddr, cmLess, cmGreater, cmNeg, cmQuot, cmRem, cmList);

  { Значення під час одного обчислення.
    Words — точні слова БЕЗ маркера D4:1110: або елементи списку,
    або одне/кілька вибраних слів. IsList — структурна ознака того,
    що Words є елементами списку, а не самим значенням. }
  TCore1Value = record
    Words: TExactWords;
    IsList: Boolean;
  end;

  TCore1KeyArray = array of RawByteString;
  TCore1ValueArray = array of TCore1Value;

  TCore1Selektor = class
  private
    FDocument: TD2Document;         { власний: розібраний pinned core1.sens }
    FWords: TExactWords;            { власний: точні слова того ж файла }
    FExecutor: TCore4Runtime;       { власний: наявний механізм D4/D5 }
    FBinary: TBinaryExecutor;       { власний: наявний механізм D3 }
    FNames: array of RawByteString; { точні D7-ключі допущених DEFINE }
    FParams: array of TCore1KeyArray; { точні D7-ключі параметрів }
    FBodies: array of TD2Node;      { позичені з FDocument }
    FTexts: array of String;
    { Сталі світу з pinned core4.sens: DEFINE зі значенням-атомом,
      наприклад (визначити число-нуль 0). Це не викличні визначення. }
    FConstKeys: array of RawByteString;
    FConstBits: array of RawByteString;
    FLibRoot: String;        { тіло в pinned координатах, для звіту }
    procedure LoadConstants;
    procedure Collect(const Root: TD2Node);
    procedure AdmitBody(Ordinal: SizeInt);
    procedure SettleCalls;
    function NameKey(const Node: TD2Node): RawByteString;
    function IsD7Sequence(const Node: TD2Node): Boolean;
    function MechanismOf(const Head: TD2Node; out Arity: SizeInt): TCore1Mechanism;
    function CheckBody(const Body: TD2Node; const Params: TCore1KeyArray;
      Depth: SizeInt): String;
    function ParamIndex(const Params: TCore1KeyArray; const Node: TD2Node): SizeInt;
    function SliceOf(const Source: TExactWords; const Node: TD2Node): TCore1Value;
    function ValueFromPhysical(const Physical: RawByteString): TCore1Value;
    function AsDatum(const Value: TCore1Value): TExactWords;
    function CallD3(const Head: RawByteString; const A: TCore1Value): TCore1Value;
    function CallCons(const A, B: TCore1Value): TCore1Value;
    function ApplyNot(const A: TCore1Value): TCore1Value;
    function ApplyEq(const A, B: TCore1Value): TCore1Value;
    function ApplyNull(const A: TCore1Value): TCore1Value;
    function ApplyNeg(const A: TCore1Value): TCore1Value;
    function ApplyList(const Node: TD2Node; const Params: TCore1KeyArray;
      const Values: TCore1ValueArray; Depth: SizeInt): TCore1Value;
    function ApplyDivide(const A, B: TCore1Value;
      const Mechanism: TCore1Mechanism): TCore1Value;
    function ApplyCompare(const A, B: TCore1Value;
      const Mechanism: TCore1Mechanism): TCore1Value;
    function ApplyNumeric(const A, B: TCore1Value;
      const Mechanism: TCore1Mechanism): TCore1Value;
    function ApplyCond(const Node: TD2Node; const Params: TCore1KeyArray;
      const Values: TCore1ValueArray; Depth: SizeInt): TCore1Value;
    function ApplyCall(const Node: TD2Node; const Params: TCore1KeyArray;
      const Values: TCore1ValueArray; Depth: SizeInt): TCore1Value;
    function CalleeParams(const Key: RawByteString): SizeInt;
    function IsConstant(const Key: RawByteString): Boolean;
    function ConstantValue(const Key: RawByteString): TCore1Value;
    function CallCore4(const Head: RawByteString; const A: TCore1Value): TCore1Value;
    function EvalNode(const Node: TD2Node; const Params: TCore1KeyArray;
      const Values: TCore1ValueArray; Depth: SizeInt): TCore1Value;
    function FindPlan(const Key: RawByteString): SizeInt;
  public
    constructor Create(const WorkspaceRoot: String);
    destructor Destroy; override;
    function AdmittedCount: SizeInt;
    function AdmittedName(Ordinal: SizeInt): RawByteString;
    function AdmittedParamCount(Ordinal: SizeInt): SizeInt;
    function AdmittedBodyText(Ordinal: SizeInt): String;
    function ConstantCount: SizeInt;
    function ConstantBits(Ordinal: SizeInt): RawByteString;
    function FindAdmitted(const Key: RawByteString): SizeInt;
    function ExecutePhysicalCall(const Physical: RawByteString): RawByteString;
  end;

implementation
uses Classes, wsm.numericplane, wsm.numericadd, wsm.numericsub, wsm.numericmul;

{ Бітові операції над точними рядками однакової ширини — механізм, не
  закон: жодного Int64, лише біти. }
function BitsNegate(const Bits: RawByteString): RawByteString;
var
  I: SizeInt;
  Carry: Boolean;
begin
  SetLength(Result, Length(Bits));
  for I := 1 to Length(Bits) do
    if Bits[I] = '0' then Result[I] := '1' else Result[I] := '0';
  Carry := True;
  I := Length(Bits);
  while Carry and (I >= 1) do
    if Result[I] = '0' then begin Result[I] := '1'; Carry := False; end
    else begin Result[I] := '0'; Dec(I); end;
end;

function BitsUnsignedLess(const L, R: RawByteString): Boolean;
var
  I: SizeInt;
begin
  for I := 1 to Length(L) do
    if L[I] <> R[I] then Exit(L[I] < R[I]);
  Result := False;
end;

function BitsUnsignedSub(const L, R: RawByteString): RawByteString;
var
  I, D, Borrow: SizeInt;
begin
  SetLength(Result, Length(L));
  Borrow := 0;
  for I := Length(L) downto 1 do begin
    D := (Ord(L[I]) - Ord('0')) - (Ord(R[I]) - Ord('0')) - Borrow;
    if D < 0 then begin D := D + 2; Borrow := 1; end else Borrow := 0;
    if D = 1 then Result[I] := '1' else Result[I] := '0';
  end;
end;

{ Ділення точних рядків із знаком: частка відсікає до нуля, остача має
  знак діленого (як QUOTIENT/REMAINDER у Lisp 1.5). Ділення на нуль —
  явна відмова, не D1:0 і не вигадане число.
  Питання: чому остача бере знак діленого? Чому нуль — відмова?
  Чому ширина результату та сама? Чому без Int64? }
procedure DivideExact(const A, B: RawByteString;
  out Quotient, Remainder: RawByteString);
var
  MagA, MagB, Rem, Q: RawByteString;
  I, K: SizeInt;
  NegativeA, NegativeB, DivisorNonZero: Boolean;
begin
  NegativeA := A[1] = '1';
  NegativeB := B[1] = '1';
  if NegativeA then MagA := BitsNegate(A) else MagA := A;
  if NegativeB then MagB := BitsNegate(B) else MagB := B;
  DivisorNonZero := False;
  for K := 1 to Length(MagB) do
    if MagB[K] = '1' then DivisorNonZero := True;
  if not DivisorNonZero then
    raise ECore1SelektorError.Create(
      'ділення на нуль у числовому примітиві');
  Rem := StringOfChar('0', Length(MagA));
  Q := StringOfChar('0', Length(MagA));
  for I := 1 to Length(MagA) do begin
    Rem := Copy(Rem, 2, Length(Rem) - 1) + MagA[I];
    if not BitsUnsignedLess(Rem, MagB) then begin
      Rem := BitsUnsignedSub(Rem, MagB);
      Q[I] := '1';
    end;
  end;
  if NegativeA xor NegativeB then Quotient := BitsNegate(Q) else Quotient := Q;
  if NegativeA then Remainder := BitsNegate(Rem) else Remainder := Rem;
end;


const
  { Ті самі межі, що вже чинні в цьому репозиторії для одного виклику. }
  MaxCore1CallBytes = 65536;
  MaxCore1CallWords = 4096;
  MaxCore1Elements = 64;
  MaxCore1Parameters = 4;
  MaxCore1EvalDepth = 32;
  { Глибина структури тіла й глибина ВИКЛИКІВ — різні межі.
    Тіло може бути глибоко вкладеним; рекурсію тримає MaxCore1EvalDepth. }
  MaxCore1BodyDepth = 256;

function Ukr(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Need(Condition: Boolean; const MessageText: UnicodeString);
begin
  if not Condition then
    raise ECore1SelektorError.Create(Ukr(MessageText));
end;

function MechanismText(M: TCore1Mechanism): String;
begin
  case M of
    cmQuote:  Result := 'D3:001';
    cmCons:   Result := 'D3:111';
    cmRest:   Result := 'D3:011';
    cmFirst:  Result := 'D3:100';
    cmSecond: Result := 'D4:1001';
    cmThird:  Result := 'D5:10011';
    cmAtom:   Result := 'D3:010';
    cmNot:    Result := 'D4:0100';
    cmEq:     Result := 'D3:101';
    cmCond:   Result := 'D3:110';
    cmPlus:   Result := 'D5:01010';
    cmMinus:  Result := 'D5:01011';
    cmTimes:  Result := 'D5:10110';
    cmNull:   Result := 'D4:0101';
    cmCdar:   Result := 'D4:0110';
    cmCddr:   Result := 'D4:0111';
    cmLess:   Result := 'D5:11010';
    cmGreater: Result := 'D5:11011';
    cmNeg:    Result := 'D6:010010';
    cmQuot:   Result := 'D5:10111';
    cmRem:    Result := 'D6:010100';
    cmList:   Result := 'D4:1110';
  else
    Result := '?';
  end;
end;

function ReadPinnedCore1(const WorkspaceRoot: String): RawByteString;
var
  Stream: TFileStream;
  Filename: String;
begin
  Need(WorkspaceRoot <> '', 'порожній корінь робочого дерева');
  Filename := IncludeTrailingPathDelimiter(ExpandFileName(WorkspaceRoot)) +
    'external' + PathDelim + 'sens' + PathDelim + 'lib' + PathDelim +
    'core1.sens';
  try
    Stream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do
      raise ECore1SelektorError.Create(
        Ukr('відсутній фізичний pinned core1.sens: ') + E.Message);
  end;
  try
    Need((Stream.Size > 0) and (Stream.Size <= MAX_T5M_FILE_BYTES),
      'фізичний Core1 поза межами розміру');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

{ Структурна перевірка БЕЗ винятку: чи є вузол непорожньою
  послідовністю рівно семибітних точних слів.
  Питання: чому тут немає винятку? Чому ширина 7 обов'язкова? }
function TCore1Selektor.IsD7Sequence(const Node: TD2Node): Boolean;
var
  I: SizeInt;
begin
  Result := (Node <> nil) and (Node.Kind = dkList) and
    (Length(Node.Children) > 0) and (Length(Node.Children) <= 256);
  if not Result then Exit;
  for I := 0 to High(Node.Children) do
    if (Node.Children[I] = nil) or
       (Node.Children[I].Kind <> dkIdentity) or
       (Node.Children[I].Width <> 7) then
      Exit(False);
end;

{ Вузол належить FDocument і живе до Destroy.
  Ключ копіюється (RawByteString): це точні біти, не текст і не opcode.
  Питання: чому D7-послідовність не є назвою? Хто звільняє вузол? }
function TCore1Selektor.NameKey(const Node: TD2Node): RawByteString;
var
  I: SizeInt;
begin
  Need(IsD7Sequence(Node), 'очікувана непорожня точна D7-послідовність');
  Result := '';
  for I := 0 to High(Node.Children) do
    Result := Result + Node.Children[I].Bits;
end;

{ Тільки шість ратифікованих координат мають механізм у цьому зрізі.
  Ширина перевіряється РАЗОМ із бітами: 3-бітне 011 і 4-бітне 0011
  не є однією координатою лише тому, що їхні біти схожі. }
function TCore1Selektor.MechanismOf(const Head: TD2Node;
  out Arity: SizeInt): TCore1Mechanism;
begin
  Arity := 0;
  if (Head = nil) or (Head.Kind <> dkIdentity) then
    raise EUnsupportedCore1Body.Create('тіло не є викликом селектора');
  if (Head.Width = 3) and (Head.Bits = '001') then begin
    Arity := 1; Exit(cmQuote);
  end;
  if (Head.Width = 3) and (Head.Bits = '111') then begin
    Arity := 2; Exit(cmCons);
  end;
  if (Head.Width = 3) and (Head.Bits = '011') then begin
    Arity := 1; Exit(cmRest);
  end;
  if (Head.Width = 3) and (Head.Bits = '100') then begin
    Arity := 1; Exit(cmFirst);
  end;
  if (Head.Width = 4) and (Head.Bits = '1001') then begin
    Arity := 1; Exit(cmSecond);
  end;
  if (Head.Width = 5) and (Head.Bits = '10011') then begin
    Arity := 1; Exit(cmThird);
  end;
  { D3:010 «атом?» — ратифікований предикат; виконує наявний TBinaryExecutor. }
  if (Head.Width = 3) and (Head.Bits = '010') then begin
    Arity := 1; Exit(cmAtom);
  end;
  { D4:0100 «хибне?» — ратифікований D1-предикат; механізм заперечення
    точного D1-слова, не новий закон. }
  if (Head.Width = 4) and (Head.Bits = '0100') then begin
    Arity := 1; Exit(cmNot);
  end;
  { D3:101 «тотожне?» — точна рівність двох атомів; виконує наявний
    TBinaryExecutor. Арність 2, жодного host-порівняння рядків. }
  if (Head.Width = 3) and (Head.Bits = '101') then begin
    Arity := 2; Exit(cmEq);
  end;
  { D3:110 «за-умовою» — лінива послідовність двопольових гілок;
    арність перевіряється окремо, бо гілок може бути від 0 до N. }
  if (Head.Width = 3) and (Head.Bits = '110') then begin
    Arity := -1; Exit(cmCond);
  end;
  { D5:01010/01011/10110 — ратифіковані числові примітиви драбини доменів.
    Їх виконують наявні wsm.numericadd/numericsub/numericmul над точними
    фізичними атомами; тут лише міст від значення до фізичного атому. }
  if (Head.Width = 5) and (Head.Bits = '01010') then begin
    Arity := 2; Exit(cmPlus);
  end;
  if (Head.Width = 5) and (Head.Bits = '01011') then begin
    Arity := 2; Exit(cmMinus);
  end;
  if (Head.Width = 5) and (Head.Bits = '10110') then begin
    Arity := 2; Exit(cmTimes);
  end;
  { D4:0101 «порожнє?» — структурна перевірка порожнечі, не числовий нуль. }
  if (Head.Width = 4) and (Head.Bits = '0101') then begin
    Arity := 1; Exit(cmNull);
  end;
  { D4:0110 «решта-першого» і D4:0111 «решта-решти» — наявний TCore4Runtime. }
  if (Head.Width = 4) and (Head.Bits = '0110') then begin
    Arity := 1; Exit(cmCdar);
  end;
  if (Head.Width = 4) and (Head.Bits = '0111') then begin
    Arity := 1; Exit(cmCddr);
  end;
  { D5:11010 «менше?» і D5:11011 «більше?» — числові порівняння драбини. }
  if (Head.Width = 5) and (Head.Bits = '11010') then begin
    Arity := 2; Exit(cmLess);
  end;
  if (Head.Width = 5) and (Head.Bits = '11011') then begin
    Arity := 2; Exit(cmGreater);
  end;
  { D6:010010 «змінити-знак» — шостий домен, один числовий атом. }
  if (Head.Width = 6) and (Head.Bits = '010010') then begin
    Arity := 1; Exit(cmNeg);
  end;
  if (Head.Width = 5) and (Head.Bits = '10111') then begin
    Arity := 2; Exit(cmQuot);
  end;
  if (Head.Width = 6) and (Head.Bits = '010100') then begin
    Arity := 2; Exit(cmRem);
  end;
  { D4:1110 «список» — побудова списку з N обчислених величин.
    Саме нею GC-визначення Core1 будують пару (сірі чорні). }
  if (Head.Width = 4) and (Head.Bits = '1110') then begin
    Arity := -2; Exit(cmList);
  end;
  raise EUnsupportedCore1Body.Create('невідома координата тіла Core1');
end;

{ Тіло описується ЛИШЕ з фізичного AST pinned core1.sens.
  Дозволено рівно дві форми вузла: посилання на параметр і виклик
  однієї ратифікованої координати з точною арністю.
  Невідомі форми дають EUnsupportedCore1Body, а не припущення.
  Питання: чому тіло не можна підмінити текстом? Чому глибина обмежена?
  Чому посилання на параметр не є викликом? }
function TCore1Selektor.CheckBody(const Body: TD2Node;
  const Params: TCore1KeyArray; Depth: SizeInt): String;
var
  Mechanism: TCore1Mechanism;
  Arity, Index, I: SizeInt;
begin
  if Depth > MaxCore1BodyDepth then
    raise EUnsupportedCore1Body.Create('занадто глибоке тіло Core1');
  if (Body = nil) then
    raise EUnsupportedCore1Body.Create('порожнє тіло Core1');
  { D1-літерал самозначущий: одновітне слово є значенням, не іменем. }
  if (Body.Kind = dkIdentity) and (Body.Width = 1) and
     ((Body.Bits = '0') or (Body.Bits = '1')) then
    Exit('D1:' + Body.Bits);
  { Посилання на параметр: рівно його точний D7-ключ. }
  if IsD7Sequence(Body) then begin
    if IsConstant(NameKey(Body)) then Exit('const');
    Index := ParamIndex(Params, Body);
    if Index < 0 then
      raise EUnsupportedCore1Body.Create('імʼя поза лексичним середовищем');
    Exit('arg' + IntToStr(Index));
  end;
  if (Body.Kind <> dkList) or (Length(Body.Children) = 0) then
    raise EUnsupportedCore1Body.Create('тіло не є фізичним списком');
  { Виклик ІНШОГО визначення Core1: голова — точний D7-ключ, не оператор.
    Це єдина форма, яка робить тіло композиційним і відкриває рекурсію. }
  if IsD7Sequence(Body.Children[0]) then begin
    Arity := CalleeParams(NameKey(Body.Children[0]));
    if Arity < 0 then
      raise EUnsupportedCore1Body.Create('виклик невідомого визначення Core1');
    if Length(Body.Children) - 1 <> Arity then
      raise EUnsupportedCore1Body.Create('невірна арність виклику Core1');
    Result := 'call(';
    for I := 1 to Arity do begin
      if I > 1 then Result := Result + ',';
      Result := Result + CheckBody(Body.Children[I], Params, Depth + 1);
    end;
    Exit(Result + ')');
  end;
  Mechanism := MechanismOf(Body.Children[0], Arity);
  if (Mechanism = cmCond) or (Mechanism = cmList) then begin
    if Mechanism = cmList then begin
      { D4:1110 «список»: вільна арність, кожен елемент — окреме тіло. }
      Result := 'D4:1110(';
      for I := 1 to High(Body.Children) do begin
        if I > 1 then Result := Result + ',';
        Result := Result + CheckBody(Body.Children[I], Params, Depth + 1);
      end;
      Exit(Result + ')');
    end;
    { Кожна гілка — рівно два поля; перевіряємо ВСІ, навіть недосяжні. }
    Result := 'D3:110(';
    for I := 1 to High(Body.Children) do begin
      if I > 1 then Result := Result + ';';
      if (Body.Children[I] = nil) or (Body.Children[I].Kind <> dkList) or
         (Length(Body.Children[I].Children) <> 2) then
        raise EUnsupportedCore1Body.Create('гілка D3:110 має бути двопольовою');
      Result := Result + CheckBody(Body.Children[I].Children[0], Params, Depth + 1) +
        '->' + CheckBody(Body.Children[I].Children[1], Params, Depth + 1);
    end;
    Exit(Result + ')');
  end;
  if Length(Body.Children) <> Arity + 1 then
    raise EUnsupportedCore1Body.Create('невірна арність координати тіла');
  if Mechanism = cmQuote then
    { Дані під цитуванням не обчислюються: перевіряти нема чого. }
    Exit(MechanismText(Mechanism) + '(datum)');
  Result := MechanismText(Mechanism) + '(';
  for I := 1 to Arity do begin
    if I > 1 then Result := Result + ',';
    Result := Result + CheckBody(Body.Children[I], Params, Depth + 1);
  end;
  Result := Result + ')';
end;

{ Порівняння саме точних бітів D7, а не тексту.
  Питання: чому -1 є явною відмовою, а не «першим»? }
function TCore1Selektor.ParamIndex(const Params: TCore1KeyArray;
  const Node: TD2Node): SizeInt;
var
  Key: RawByteString;
  I: SizeInt;
begin
  Result := -1;
  if not IsD7Sequence(Node) then Exit;
  Key := NameKey(Node);
  for I := 0 to High(Params) do
    if Params[I] = Key then Exit(I);
end;

{ Приймається лише (D4:0011 name (D4:0010 (params...) body)).
  Від одного до чотирьох лексичних параметрів; інші визначення цього
  зрізу не підтримані й лишаються явно недопущеними.
  Питання: чому параметри позиційні? Чому D4:0011/D4:0010 точні?
  Хто володіє Lambda/Args/Body? Чому невідоме тіло не стає NIL? }
{ Сталі світу з pinned core4.sens.
  Файл БІЛЬШИЙ за межу D2-читача (278857 слів проти MaxD2Words=100000),
  і має власний профіль з розділювачами 00. Тому розбираємо не весь AST,
  а ВІКНО навколо кожного фізичного рисунку 10 0011: чинний
  ParseD2WordsWide бачить лише вікно, як TCore4Runtime бачить префікс.
  Приймаємо рівно корінь (0011 <D7-ключ> <атом>).
  Питання: чому вікно, а не підняття межі? Чому лише атом як значення?
  Чому ім'я береться з точних бітів, а не з тексту? }
{ Сталі світу беруться з ТОГО САМОГО TCore4Runtime, який уже завантажує
  pinned core4.sens: він сам розбирає початкові форми (файл більший за
  межу D2-читача, тому повний AST неможливий) і тримає атомні глобали як
  точні біти. Жодного другого розбору профілю і жодного другого реєстру.
  Питання: чому не читаємо core4.sens самі? Чому лише не-замикання? }
procedure TCore1Selektor.LoadConstants;
var
  I: SizeInt;
begin
  if FExecutor = nil then Exit;
  for I := 0 to FExecutor.BindingCount - 1 do begin
    if FExecutor.BindingIsFunction(I) then Continue;
    SetLength(FConstKeys, Length(FConstKeys) + 1);
    SetLength(FConstBits, Length(FConstBits) + 1);
    FConstKeys[High(FConstKeys)] := FExecutor.BindingIdentifier(I);
    FConstBits[High(FConstBits)] := FExecutor.BindingValueBits(I);
  end;
end;

function TCore1Selektor.ConstantCount: SizeInt;
begin
  Result := Length(FConstKeys);
end;

function TCore1Selektor.ConstantBits(Ordinal: SizeInt): RawByteString;
begin
  Need((Ordinal >= 0) and (Ordinal <= High(FConstBits)), 'немає такої сталої');
  Result := FConstBits[Ordinal];
end;

{ Ім'я сталої світу: значення підставляється як ТОЧНЕ слово. }
function TCore1Selektor.IsConstant(const Key: RawByteString): Boolean;
var
  I: SizeInt;
begin
  for I := 0 to High(FConstKeys) do
    if FConstKeys[I] = Key then Exit(True);
  Result := False;
end;

function TCore1Selektor.ConstantValue(const Key: RawByteString): TCore1Value;
var
  I: SizeInt;
begin
  for I := 0 to High(FConstKeys) do
    if FConstKeys[I] = Key then begin
      SetLength(Result.Words, 1);
      Result.Words[0] := FConstBits[I];
      Result.IsList := False;
      Exit;
    end;
  raise EUnsupportedCore1Body.Create('невідоме імʼя сталої світу');
end;

{ Перший прохід: ЛИШЕ структурна форма DEFINE/LAMBDA і точні ключі.
  Тіла ще не перевіряються — виклик може посилатися на визначення,
  яке стоїть далі у файлі.
  Питання: чому параметри збираються до перевірки тіл? Чому повторний
  точний D7-ключ — відмова, а не перезапис? }
procedure TCore1Selektor.Collect(const Root: TD2Node);
var
  Lambda, Args, Body: TD2Node;
  Params: TCore1KeyArray;
  Key: RawByteString;
  I: SizeInt;
begin
  if (Root = nil) or (Root.Kind <> dkList) or
     (Length(Root.Children) <> 3) then
    raise EUnsupportedCore1Body.Create('корінь Core1 не є DEFINE');
  if (Root.Children[0] = nil) or
     (Root.Children[0].Kind <> dkIdentity) or
     (Root.Children[0].Width <> 4) or
     (Root.Children[0].Bits <> '0011') then
    raise EUnsupportedCore1Body.Create('корінь Core1 потребує D4:0011');
  Lambda := Root.Children[2];
  { D5:00100 «мітка»: (мітка <ім'я> (функція ...)). Самопосилання в Core1
    підписане саме так; мітка мусить називати СВОЄ ж визначення, інакше
    рекурсія вказувала б на чужий ключ. Саме тіло лишається незмінним,
    тому окремого механізму виклику не треба: виклик іде звичайним
    точним D7-шляхом, а глибину тримає межа обчислення.
    Питання: чому мітка не створює нового замикання? Чому ім'я мусить
    збігатися з DEFINE? Що буде, якщо мітка назве інше визначення? }
  if (Lambda <> nil) and (Lambda.Kind = dkList) and
     (Length(Lambda.Children) = 3) and (Lambda.Children[0] <> nil) and
     (Lambda.Children[0].Kind = dkIdentity) and
     (Lambda.Children[0].Width = 5) and
     (Lambda.Children[0].Bits = '00100') then begin
    if NameKey(Lambda.Children[1]) <> NameKey(Root.Children[1]) then
      raise EUnsupportedCore1Body.Create(
        'мітка називає інше визначення, а не своє');
    Lambda := Lambda.Children[2];
  end;
  if (Lambda = nil) or (Lambda.Kind <> dkList) or
     (Length(Lambda.Children) <> 3) then
    raise EUnsupportedCore1Body.Create('значення Core1 не є LAMBDA');
  if (Lambda.Children[0] = nil) or
     (Lambda.Children[0].Kind <> dkIdentity) or
     (Lambda.Children[0].Width <> 4) or
     (Lambda.Children[0].Bits <> '0010') then
    raise EUnsupportedCore1Body.Create('значення Core1 потребує D4:0010');
  Args := Lambda.Children[1];
  if (Args = nil) or (Args.Kind <> dkList) or
     (Length(Args.Children) < 1) or
     (Length(Args.Children) > MaxCore1Parameters) then
    raise EUnsupportedCore1Body.Create('неприпустима кількість параметрів');
  SetLength(Params, Length(Args.Children));
  for I := 0 to High(Args.Children) do
    Params[I] := NameKey(Args.Children[I]);
  Body := Lambda.Children[2];
  Key := NameKey(Root.Children[1]);
  for I := 0 to High(FNames) do
    if FNames[I] = Key then
      raise EUnsupportedCore1Body.Create('повторний точний D7-ключ Core1');
  SetLength(FNames, Length(FNames) + 1);
  SetLength(FParams, Length(FParams) + 1);
  SetLength(FBodies, Length(FBodies) + 1);
  SetLength(FTexts, Length(FTexts) + 1);
  FNames[High(FNames)] := Key;
  FParams[High(FParams)] := Params;
  FBodies[High(FBodies)] := Body;
  FTexts[High(FTexts)] := '';
end;

{ Другий прохід: перевірка тіла вже з ПОВНОЮ таблицею точних ключів. }
procedure TCore1Selektor.AdmitBody(Ordinal: SizeInt);
begin
  FTexts[Ordinal] := CheckBody(FBodies[Ordinal], FParams[Ordinal], 0);
end;

{ Третій прохід: виклик недопущеного визначення робить недопущеним і
  того, хто кличе. Повторюємо до нерухомої точки (не більше N кроків).
  Питання: чому це потрібно саме тут? Чому одного проходу замало? }
procedure TCore1Selektor.SettleCalls;
var
  Accepted: array of Boolean;
  Changed: Boolean;
  I, J, Round: SizeInt;
  Key: RawByteString;
begin
  SetLength(Accepted, Length(FNames));
  for I := 0 to High(Accepted) do Accepted[I] := FTexts[I] <> '';
  Round := 0;
  repeat
    Changed := False;
    Inc(Round);
    for I := 0 to High(Accepted) do begin
      if not Accepted[I] then Continue;
      for J := 0 to High(FNames) do begin
        if Accepted[J] then Continue;
        Key := FNames[J];
        if Pos(Key, FTexts[I]) = 0 then Continue;
        Accepted[I] := False;
        Changed := True;
        Break;
      end;
    end;
  until (not Changed) or (Round > Length(FNames));
  { Компакція: лишаємо тільки прийняті, зберігаючи порядок файла. }
  J := 0;
  for I := 0 to High(Accepted) do
    if Accepted[I] then begin
      if I <> J then begin
        FNames[J] := FNames[I];
        FParams[J] := FParams[I];
        FBodies[J] := FBodies[I];
        FTexts[J] := FTexts[I];
      end;
      Inc(J);
    end;
  SetLength(FNames, J);
  SetLength(FParams, J);
  SetLength(FBodies, J);
  SetLength(FTexts, J);
end;

{ Обидва чинні механізми живуть рівно один раз і не переживають Destroy.
  Недопущене тіло не робить конструктор хибним: Core1 має 96 визначень,
  більшість із них цим зрізом не підтримані, і це явний, а не мовчазний факт.
  Питання: що лишається живим після відмови admission? Чому відсутність
  external/sens — це помилка, а недопущене тіло — ні? }
constructor TCore1Selektor.Create(const WorkspaceRoot: String);
var
  Physical: RawByteString;
  Upstream: String;
  I: SizeInt;
begin
  inherited Create;
  FDocument := nil; FExecutor := nil; FBinary := nil;
  try
    Physical := ReadPinnedCore1(WorkspaceRoot);
    try
      DecodeT5M(Physical, FWords);
    except
      on E: Exception do
        raise ECore1SelektorError.Create(
          Ukr('хибний pinned Core1 T5M: ') + E.Message);
    end;
    Need(EncodeT5M(FWords) = Physical, 'core1.sens не є канонічним T5M');
    FDocument := ParseD2WordsWide(FWords);
    Need(Length(FDocument.Roots) > 0, 'фізичний Core1 без визначень');
    Upstream := IncludeTrailingPathDelimiter(ExpandFileName(WorkspaceRoot)) +
      'external' + PathDelim + 'sens';
    FExecutor := TCore4Runtime.Create(WorkspaceRoot);
    FBinary := TBinaryExecutor.Create(RawByteString(Upstream));
    FLibRoot := IncludeTrailingPathDelimiter(ExpandFileName(WorkspaceRoot)) +
      'external' + PathDelim + 'sens' + PathDelim + 'lib';
    LoadConstants;
    { Прохід 1: зібрати всі точні ключі та параметри. }
    for I := 0 to High(FDocument.Roots) do
      try
        Collect(FDocument.Roots[I]);
      except
        on E: EUnsupportedCore1Body do ;
      end;
    Need(Length(FNames) > 0, 'жодне визначення Core1 не зібрано');
    { Прохід 2: перевірити тіла вже з повною таблицею. }
    for I := 0 to High(FNames) do
      try
        AdmitBody(I);
      except
        on E: EUnsupportedCore1Body do FTexts[I] := '';
      end;
    { Прохід 3: виклик недопущеного визначення забороняє і викликача. }
    SettleCalls;
    Need(Length(FNames) > 0, 'жодне визначення Core1 не підтримано');
  except
    FreeAndNil(FBinary); FreeAndNil(FExecutor); FreeAndNil(FDocument);
    raise;
  end;
end;

destructor TCore1Selektor.Destroy;
begin
  FBinary.Free;
  FExecutor.Free;
  FDocument.Free;
  inherited Destroy;
end;

function TCore1Selektor.AdmittedCount: SizeInt;
begin
  Result := Length(FNames);
end;

function TCore1Selektor.AdmittedName(Ordinal: SizeInt): RawByteString;
begin
  Need((Ordinal >= 0) and (Ordinal < Length(FNames)),
    'неприпустимий номер допущеного визначення Core1');
  Result := FNames[Ordinal];
end;

function TCore1Selektor.AdmittedParamCount(Ordinal: SizeInt): SizeInt;
begin
  Need((Ordinal >= 0) and (Ordinal < Length(FParams)),
    'неприпустимий номер допущеного визначення Core1');
  Result := Length(FParams[Ordinal]);
end;

function TCore1Selektor.AdmittedBodyText(Ordinal: SizeInt): String;
begin
  Need((Ordinal >= 0) and (Ordinal < Length(FTexts)),
    'неприпустимий номер допущеного визначення Core1');
  Result := FTexts[Ordinal];
end;

{ Кількість параметрів ЗІБРАНОГО визначення за точним ключем; -1 — немає.
  Це не дозвіл виклику: дозвіл дає лише SettleCalls. }
function TCore1Selektor.CalleeParams(const Key: RawByteString): SizeInt;
var
  I: SizeInt;
begin
  for I := 0 to High(FNames) do
    if FNames[I] = Key then Exit(Length(FParams[I]));
  Result := -1;
end;

function TCore1Selektor.FindAdmitted(const Key: RawByteString): SizeInt;
var
  I: SizeInt;
begin
  for I := 0 to High(FNames) do
    if FNames[I] = Key then Exit(I);
  Result := -1;
end;

function TCore1Selektor.FindPlan(const Key: RawByteString): SizeInt;
begin
  Result := FindAdmitted(Key);
  Need(Result >= 0, 'це визначення Core1 не підтримане цим зрізом');
end;

{ Фізичний зріз вузла як значення. Source — ТІ слова, з яких вузол
  реально розібрано: для тіла це pinned core1.sens, для аргументів — файл
  виклику. Змішувати їх не можна, бо індекси слів різні. Список віддається елементами,
  атом — своїми точними словами. Маркер D4:1110 тут не вигадується:
  він належить конструкторові списку, а не значенню.
  Питання: хто володіє FWords? Чому порожній список має нуль елементів? }
function TCore1Selektor.SliceOf(const Source: TExactWords;
  const Node: TD2Node): TCore1Value;
var
  StartAt, AfterAt, I: SizeInt;
begin
  Need(Node <> nil, 'порожній вузол тіла Core1');
  StartAt := Node.WordIndex - 1;
  AfterAt := Node.EndWordIndexExclusive - 1;
  Need((StartAt >= 0) and (AfterAt > StartAt) and
    (AfterAt <= Length(Source)), 'пошкоджений фізичний інтервал вузла');
  if (AfterAt - StartAt >= 2) and (Source[StartAt] = '10') and
     (Source[AfterAt - 1] = '01') then begin
    SetLength(Result.Words, AfterAt - StartAt - 2);
    for I := 1 to AfterAt - StartAt - 2 do
      Result.Words[I - 1] := Source[StartAt + I];
    Result.IsList := True;
  end else begin
    SetLength(Result.Words, AfterAt - StartAt);
    for I := 0 to AfterAt - StartAt - 1 do
      Result.Words[I] := Source[StartAt + I];
    Result.IsList := False;
  end;
end;

function TCore1Selektor.ValueFromPhysical(
  const Physical: RawByteString): TCore1Value;
var
  Back: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(Physical, Back);
  Need(Length(Back) > 0, 'порожня фізична відповідь механізму');
  { D3:000 — це структурна порожнеча, а не трибітний атом: механізми
    віддають її одним словом 000, і для обчислювача це порожній список. }
  if (Length(Back) = 1) and (Back[0] = '000') then begin
    SetLength(Result.Words, 0);
    Result.IsList := True;
    Exit;
  end;
  if (Length(Back) >= 2) and (Back[0] = '10') and
     (Back[High(Back)] = '01') then begin
    SetLength(Result.Words, Length(Back) - 2);
    for I := 1 to Length(Back) - 2 do Result.Words[I - 1] := Back[I];
    Result.IsList := True;
  end else begin
    Result.Words := Copy(Back, 0, Length(Back));
    Result.IsList := False;
  end;
end;

{ Значення подається як ФІЗИЧНЕ дане (без обчислення): список —
  як (10 <елементи> 01), атом — своїми словами.
  Питання: чому дані не обчислюються вдруге? }
function TCore1Selektor.AsDatum(const Value: TCore1Value): TExactWords;
var
  I: SizeInt;
begin
  if Value.IsList then begin
    SetLength(Result, Length(Value.Words) + 2);
    Result[0] := '10';
    for I := 0 to High(Value.Words) do Result[I + 1] := Value.Words[I];
    Result[High(Result)] := '01';
  end else
    Result := Copy(Value.Words, 0, Length(Value.Words));
end;

{ D3-форма з одним аргументом-даним: (10 <голова> (10 001 <дане> 01) 01).
  Виконує наявний TBinaryExecutor; тут немає другої семантики D3.
  Питання: чому аргумент цитовано? Чому голова — точні біти? }
function TCore1Selektor.CallD3(const Head: RawByteString;
  const A: TCore1Value): TCore1Value;
var
  Call: TExactWords;
  Datum: TExactWords;
  I: SizeInt;
begin
  Datum := AsDatum(A);
  SetLength(Call, Length(Datum) + 6);
  Call[0] := '10'; Call[1] := Head; Call[2] := '10'; Call[3] := '001';
  for I := 0 to High(Datum) do Call[I + 4] := Datum[I];
  Call[Length(Datum) + 4] := '01';
  Call[Length(Datum) + 5] := '01';
  Result := ValueFromPhysical(FBinary.ExecutePhysicalT5M(EncodeT5M(Call)));
end;

{ D3:111 «сполучити» з двома даними:
  (10 111 (10 001 <a> 01) (10 001 <b> 01) 01).
  Результат може бути як списком, так і крапковою парою — це вирішує
  наявний механізм, а не цей юніт.
  Питання: чому тут два цитування? Чому результат не переписується? }
function TCore1Selektor.CallCons(const A, B: TCore1Value): TCore1Value;
var
  Call, Left, Right: TExactWords;
  I, P: SizeInt;
begin
  Left := AsDatum(A);
  Right := AsDatum(B);
  SetLength(Call, Length(Left) + Length(Right) + 9);
  P := 0;
  Call[P] := '10'; Inc(P);
  Call[P] := '111'; Inc(P);
  Call[P] := '10'; Inc(P); Call[P] := '001'; Inc(P);
  for I := 0 to High(Left) do begin Call[P] := Left[I]; Inc(P); end;
  Call[P] := '01'; Inc(P);
  Call[P] := '10'; Inc(P); Call[P] := '001'; Inc(P);
  for I := 0 to High(Right) do begin Call[P] := Right[I]; Inc(P); end;
  Call[P] := '01'; Inc(P);
  Call[P] := '01'; Inc(P);
  SetLength(Call, P);
  Result := ValueFromPhysical(FBinary.ExecutePhysicalT5M(EncodeT5M(Call)));
end;

{ D4:0100 «хибне?» над точним D1-словом: 0 → 1, 1 → 0.
  Це механізм ратифікованої координати, а не новий закон: жодного
  host-boolean, лише точні біти. Будь-яке не-D1 значення — відмова.
  Питання: чому не Pascal Boolean? Чому ширина 1 обовʼязкова?
  Чому порожній список не є хибне? }
function TCore1Selektor.ApplyNot(const A: TCore1Value): TCore1Value;
begin
  Need(not A.IsList, 'D4:0100 потребує точного D1-слова, не списку');
  Need(Length(A.Words) = 1, 'D4:0100 потребує рівно одного слова');
  Need((A.Words[0] = '0') or (A.Words[0] = '1'),
    'D4:0100 приймає лише D1:0 або D1:1');
  SetLength(Result.Words, 1);
  if A.Words[0] = '0' then Result.Words[0] := '1' else Result.Words[0] := '0';
  Result.IsList := False;
end;

{ D3:101 «тотожне?» над двома точними атомами: виконує наявний
  TBinaryExecutor, аргументи подаються як дані.
  Питання: чому список не є атомом для тотожне? Чому результат — D1? }
function TCore1Selektor.ApplyEq(const A, B: TCore1Value): TCore1Value;
begin
  { D3:101 — тотожність АТОМІВ. Список ніколи не тотожний атому, тому
    така пара дає D1:0 (структурний факт, не оцінка). Два списки
    тотожне? не порівнює: для складених імен є окреме ядро1-назви-рівні?.
    Механізм: порівняння точного слова РАЗОМ із його шириною (довжина
    рядка бітів і є шириною), тому 011 (D3) ніколи не дорівнює 0011 (D4).
    Це ширше за наявний nativeeval D3:101 (той бере лише D1 або
    цитований D7); розширення механічне й не додає жодного нового закону. }
  if A.IsList or B.IsList then begin
    SetLength(Result.Words, 1);
    Result.IsList := False;
    { Два ПОРОЖНІ списки — це одне структурне D3:000, тому тотожні.
      Будь-які інші списки тотожне? не порівнює: для складених імен
      є окреме ядро1-назви-рівні?, і саме воно кличе тотожне? по знаках. }
    if A.IsList and B.IsList and (Length(A.Words) = 0) and
       (Length(B.Words) = 0) then begin
      Result.Words[0] := '1';
      Exit;
    end;
    Need(not (A.IsList and B.IsList),
      'D3:101 не порівнює два списки: для складених імен є ядро1-назви-рівні?');
    Result.Words[0] := '0';
    Exit;
  end;
  Need((Length(A.Words) = 1) and (Length(B.Words) = 1),
    'D3:101 приймає рівно по одному точному слову');
  SetLength(Result.Words, 1);
  if (Length(A.Words[0]) = Length(B.Words[0])) and (A.Words[0] = B.Words[0]) then
    Result.Words[0] := '1'
  else
    Result.Words[0] := '0';
  Result.IsList := False;
end;

{ D6:010010 «змінити-знак»: доповняльне заперечення точного числового
  атома. Інверсія всіх бітів плюс одиниця — жодного Int64, жодного
  віднімання в хості. Ширина лишається тією самою.
  Питання: чому 0 переходить у 0? Чому ширина не міняється?
  Чому список — відмова? }
{ D4:1110 «список»: будує ПОСЛІДОВНІСТЬ з уже обчислених величин.
  Це структурна побудова, не виклик обчислювача і не новий закон.
  Питання: чому жоден елемент не обчислюється вдруге? Чому вкладені
  списки лишаються списками? Чому порожній виклик дає порожній список? }
function TCore1Selektor.ApplyList(const Node: TD2Node;
  const Params: TCore1KeyArray; const Values: TCore1ValueArray;
  Depth: SizeInt): TCore1Value;
var
  Item: TCore1Value;
  I, P, Total, K: SizeInt;
  Parts: array of TExactWords;
begin
  SetLength(Parts, Length(Node.Children) - 1);
  Total := 0;
  for I := 1 to High(Node.Children) do begin
    Item := EvalNode(Node.Children[I], Params, Values, Depth + 1);
    Parts[I - 1] := AsDatum(Item);
    Inc(Total, Length(Parts[I - 1]));
  end;
  SetLength(Result.Words, Total);
  P := 0;
  for I := 0 to High(Parts) do
    for K := 0 to High(Parts[I]) do begin
      Result.Words[P] := Parts[I][K];
      Inc(P);
    end;
  Result.IsList := True;
end;

function TCore1Selektor.ApplyDivide(const A, B: TCore1Value;
  const Mechanism: TCore1Mechanism): TCore1Value;
var
  Left, Right, Quotient, Remainder: RawByteString;
  Width: SizeInt;
begin
  Need(not A.IsList, 'ділення потребує точного атома зліва');
  Need(not B.IsList, 'ділення потребує точного атома справа');
  Need((Length(A.Words) = 1) and (Length(B.Words) = 1),
    'ділення приймає рівно по одному слову');
  Left := A.Words[0];
  Right := B.Words[0];
  Width := Length(Left);
  Need(Width = Length(Right), 'ділення потребує однакової ширини');
  Need((Width = 12) or (Width = 24) or (Width = 48) or
    (Width = 96) or (Width = 192), 'ширина не є числовим доменом драбини');
  DivideExact(Left, Right, Quotient, Remainder);
  SetLength(Result.Words, 1);
  Result.IsList := False;
  if Mechanism = cmQuot then Result.Words[0] := Quotient
  else Result.Words[0] := Remainder;
end;

function TCore1Selektor.ApplyNeg(const A: TCore1Value): TCore1Value;
var
  Bits: RawByteString;
  I, Width: SizeInt;
  Carry: Boolean;
begin
  Need(not A.IsList, 'змінити-знак потребує точного атома');
  Need(Length(A.Words) = 1, 'змінити-знак приймає рівно одне слово');
  Bits := A.Words[0];
  Width := Length(Bits);
  Need((Width = 12) or (Width = 24) or (Width = 48) or
    (Width = 96) or (Width = 192), 'ширина не є числовим доменом драбини');
  SetLength(Result.Words, 1);
  Result.IsList := False;
  Result.Words[0] := Bits;
  for I := 1 to Width do
    if Bits[I] = '0' then Result.Words[0][I] := '1'
    else Result.Words[0][I] := '0';
  Carry := True;
  I := Width;
  while Carry and (I >= 1) do begin
    if Result.Words[0][I] = '0' then begin
      Result.Words[0][I] := '1';
      Carry := False;
    end else begin
      Result.Words[0][I] := '0';
      Dec(I);
    end;
  end;
end;

{ Числове порівняння драбини доменів: обидва операнди — точні атоми
  ОДНАКОВОЇ ширини з числового домену. Порівнюємо доповняльний код:
  різні знакові біти — менший той, у кого знак 1; однакові — звичайне
  лексикографічне порівняння бітів. Результат — точний D1.
  Жодного Int64 і жодного host-boolean: лише біти.
  Питання: чому ширина мусить збігатися? Чому знак — найстарший біт?
  Чому результат не «так/ні», а D1? }
function TCore1Selektor.ApplyCompare(const A, B: TCore1Value;
  const Mechanism: TCore1Mechanism): TCore1Value;
var
  Left, Right: RawByteString;
  I, Width: SizeInt;
  LeftSign, RightSign: Char;
  Less, Greater: Boolean;
begin
  Need(not A.IsList, 'порівняння потребує точного атома зліва');
  Need(not B.IsList, 'порівняння потребує точного атома справа');
  Need((Length(A.Words) = 1) and (Length(B.Words) = 1),
    'порівняння приймає рівно по одному слову');
  Left := A.Words[0];
  Right := B.Words[0];
  Width := Length(Left);
  Need(Width = Length(Right), 'порівняння потребує однакової ширини');
  Need((Width = 12) or (Width = 24) or (Width = 48) or
    (Width = 96) or (Width = 192), 'ширина не є числовим доменом драбини');
  LeftSign := Left[1];
  RightSign := Right[1];
  if LeftSign <> RightSign then begin
    Less := LeftSign = '1';
    Greater := RightSign = '1';
  end else begin
    Less := False; Greater := False;
    for I := 1 to Width do
      if Left[I] <> Right[I] then begin
        Less := Left[I] < Right[I];
        Greater := Left[I] > Right[I];
        Break;
      end;
  end;
  SetLength(Result.Words, 1);
  Result.IsList := False;
  if Mechanism = cmLess then begin
    if Less then Result.Words[0] := '1' else Result.Words[0] := '0';
  end else begin
    if Greater then Result.Words[0] := '1' else Result.Words[0] := '0';
  end;
end;

{ D4:0101 «порожнє?»: істина лише для СТРУКТУРНОЇ порожнечі (список без
  елементів). Це не числовий нуль і не D1:0 — саме тому перевірка
  структурна, а не арифметична.
  Питання: чому D1:0 не є порожнім? Чому атом — не порожній? }
function TCore1Selektor.ApplyNull(const A: TCore1Value): TCore1Value;
begin
  SetLength(Result.Words, 1);
  Result.IsList := False;
  if A.IsList and (Length(A.Words) = 0) then
    Result.Words[0] := '1'
  else
    Result.Words[0] := '0';
end;

{ Числовий примітив драбини доменів над ДВОМА точними атомами.
  Обидва операнди мусять бути атомами однакової ширини з відомого
  числового домену (D12/D24/D48/D96/D192); саму арифметику й закон
  виконує наявний механізм, цей юніт не додає жодного правила.
  Питання: чому ширина береться з самих слів? Чому список — відмова?
  Чому результат — знову точний атом тієї самої ширини? }
function TCore1Selektor.ApplyNumeric(const A, B: TCore1Value;
  const Mechanism: TCore1Mechanism): TCore1Value;
var
  LeftPhysical, RightPhysical, Answer: RawByteString;
  Width: SizeInt;
begin
  Need(not A.IsList, 'числовий примітив потребує точного атома зліва');
  Need(not B.IsList, 'числовий примітив потребує точного атома справа');
  Need((Length(A.Words) = 1) and (Length(B.Words) = 1),
    'числовий примітив приймає рівно по одному слову');
  Width := Length(A.Words[0]);
  Need(Width = Length(B.Words[0]), 'операнди мусять мати однакову ширину');
  Need((Width = 12) or (Width = 24) or (Width = 48) or
    (Width = 96) or (Width = 192), 'ширина не є числовим доменом драбини');
  LeftPhysical := EncodeT5M(Copy(A.Words, 0, 1));
  RightPhysical := EncodeT5M(Copy(B.Words, 0, 1));
  case Mechanism of
    cmPlus:  Answer := AddNumericPhysical(LeftPhysical, RightPhysical, Width);
    cmMinus: Answer := SubtractNumericPhysical(LeftPhysical, RightPhysical, Width);
    cmTimes: Answer := MultiplyNumericPhysical(LeftPhysical, RightPhysical, Width);
  else
    raise ECore1SelektorError.Create(Ukr('невідомий числовий примітив'));
  end;
  Result := ValueFromPhysical(Answer);
end;

{ D3:110 «за-умовою»: гілки перевіряються ЛІНИВО, зверху вниз.
  Тест мусить дати точний D1; D1:1 вибирає вираз, D1:0 іде далі.
  Вичерпання гілок повертає структурну порожнечу, не D1:0.
  Питання: чому вираз не обчислюється для хибного тесту?
  Чому не-D1 тест — відмова, а не «хибно»? }
function TCore1Selektor.ApplyCond(const Node: TD2Node;
  const Params: TCore1KeyArray; const Values: TCore1ValueArray;
  Depth: SizeInt): TCore1Value;
var
  Clause, Test: TCore1Value;
  I: SizeInt;
begin
  for I := 1 to High(Node.Children) do begin
    Need((Node.Children[I] <> nil) and (Node.Children[I].Kind = dkList) and
      (Length(Node.Children[I].Children) = 2),
      'гілка D3:110 має бути двопольовою');
    Test := EvalNode(Node.Children[I].Children[0], Params, Values, Depth + 1);
    Need((not Test.IsList) and (Length(Test.Words) = 1) and
      ((Test.Words[0] = '0') or (Test.Words[0] = '1')),
      'D3:110 потребує точного D1 у тесті');
    if Test.Words[0] = '1' then
      Exit(EvalNode(Node.Children[I].Children[1], Params, Values, Depth + 1));
  end;
  { Структурне () — не хибне значення D1:0. }
  SetLength(Result.Words, 0);
  Result.IsList := True;
  Clause.Words := nil;
end;

{ Виклик іншого визначення Core1 за ТОЧНИМ D7-ключем.
  Аргументи обчислюються в середовищі викликача, потім зв'язуються
  позиційно з параметрами викликаного. Глибина обмежена, щоб
  рекурсія без умови виходу була відмовою, а не зависанням.
  Питання: чому немає замикань? Чому глибина є host-межею? }
function TCore1Selektor.ApplyCall(const Node: TD2Node;
  const Params: TCore1KeyArray; const Values: TCore1ValueArray;
  Depth: SizeInt): TCore1Value;
var
  Callee: TCore1ValueArray;
  Ordinal, I: SizeInt;
begin
  Need(Depth < MaxCore1EvalDepth, 'перевищено глибину викликів Core1');
  Ordinal := FindPlan(NameKey(Node.Children[0]));
  Need(Length(Node.Children) - 1 = Length(FParams[Ordinal]),
    'арність виклику не дорівнює кількості параметрів');
  SetLength(Callee, Length(FParams[Ordinal]));
  for I := 0 to High(Callee) do
    Callee[I] := EvalNode(Node.Children[I + 1], Params, Values, Depth + 1);
  Result := EvalNode(FBodies[Ordinal], FParams[Ordinal], Callee, Depth + 1);
end;

{ D4/D5-селектор над фізичним D4:1110 списком:
  (10 <голова> (10 1110 <елементи> 01) 01).
  Питання: чому маркер D4:1110 додається тут? Чому атом не приймається? }
function TCore1Selektor.CallCore4(const Head: RawByteString;
  const A: TCore1Value): TCore1Value;
var
  Call: TExactWords;
  I: SizeInt;
begin
  Need(A.IsList, 'цей селектор потребує фізичного списку, не атома');
  Need(Length(A.Words) <= MaxCore1Elements,
    'неприпустима кількість елементів для селектора');
  SetLength(Call, Length(A.Words) + 6);
  Call[0] := '10'; Call[1] := Head; Call[2] := '10'; Call[3] := '1110';
  for I := 0 to High(A.Words) do Call[I + 4] := A.Words[I];
  Call[Length(A.Words) + 4] := '01';
  Call[Length(A.Words) + 5] := '01';
  Result := ValueFromPhysical(FExecutor.ExecutePhysicalCall(EncodeT5M(Call)));
end;

{ Рекурсивне обчислення тіла в лексичному середовищі.
  Значення параметрів позичені з одного виклику і не змінюються.
  Питання: чому параметр не обчислюється? Чому цитування не обчислює
  свій аргумент? Чому невідомий вузол — відмова, а не порожнеча? }
function TCore1Selektor.EvalNode(const Node: TD2Node;
  const Params: TCore1KeyArray; const Values: TCore1ValueArray;
  Depth: SizeInt): TCore1Value;
var
  Mechanism: TCore1Mechanism;
  Arity, Index: SizeInt;
begin
  if Depth > MaxCore1BodyDepth then
    raise ECore1SelektorError.Create(Ukr('занадто глибоке обчислення тіла'));
  Need(Node <> nil, 'порожній вузол тіла Core1');
  { D1-літерал самозначущий: одновітне слово є значенням. }
  if (Node.Kind = dkIdentity) and (Node.Width = 1) and
     ((Node.Bits = '0') or (Node.Bits = '1')) then begin
    SetLength(Result.Words, 1);
    Result.Words[0] := Node.Bits;
    Result.IsList := False;
    Exit;
  end;
  { Посилання на параметр: точний D7-ключ, не текст. }
  if IsD7Sequence(Node) then begin
    if IsConstant(NameKey(Node)) then Exit(ConstantValue(NameKey(Node)));
    Index := ParamIndex(Params, Node);
    Need(Index >= 0, 'імʼя поза лексичним середовищем Core1');
    Exit(Values[Index]);
  end;
  Need((Node.Kind = dkList) and (Length(Node.Children) > 0),
    'тіло Core1 не є фізичним списком');
  { Виклик іншого визначення: голова — точний D7-ключ. }
  if IsD7Sequence(Node.Children[0]) then
    Exit(ApplyCall(Node, Params, Values, Depth));
  Mechanism := MechanismOf(Node.Children[0], Arity);
  if Mechanism = cmCond then
    Exit(ApplyCond(Node, Params, Values, Depth));
  { D4:1110 «список» має вільну арність: кожен елемент — окремий вираз. }
  if Mechanism = cmList then
    Exit(ApplyList(Node, Params, Values, Depth));
  Need(Length(Node.Children) = Arity + 1,
    'невірна арність координати тіла Core1');
  if Mechanism = cmQuote then
    { Цитування — тотожність фізичного даного: аргумент НЕ обчислюється. }
    Exit(SliceOf(FWords, Node.Children[1]));
  if Mechanism = cmCons then
    Exit(CallCons(EvalNode(Node.Children[1], Params, Values, Depth + 1),
      EvalNode(Node.Children[2], Params, Values, Depth + 1)));
  case Mechanism of
    cmRest:   Result := CallD3('011', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmFirst:  Result := CallD3('100', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmSecond: Result := CallCore4('1001', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmThird:  Result := CallCore4('10011', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmAtom:   Result := CallD3('010', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmNot:    Result := ApplyNot(EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmEq:     Result := ApplyEq(EvalNode(Node.Children[1], Params, Values, Depth + 1),
      EvalNode(Node.Children[2], Params, Values, Depth + 1));
    cmNull:   Result := ApplyNull(EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmNeg:    Result := ApplyNeg(EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmList:   Result := ApplyList(Node, Params, Values, Depth);
    cmQuot, cmRem:
      Result := ApplyDivide(EvalNode(Node.Children[1], Params, Values, Depth + 1),
        EvalNode(Node.Children[2], Params, Values, Depth + 1), Mechanism);
    cmLess, cmGreater:
      Result := ApplyCompare(EvalNode(Node.Children[1], Params, Values, Depth + 1),
        EvalNode(Node.Children[2], Params, Values, Depth + 1), Mechanism);
    cmCdar:   Result := CallCore4('0110', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmCddr:   Result := CallCore4('0111', EvalNode(Node.Children[1], Params, Values, Depth + 1));
    cmPlus, cmMinus, cmTimes:
      Result := ApplyNumeric(EvalNode(Node.Children[1], Params, Values, Depth + 1),
        EvalNode(Node.Children[2], Params, Values, Depth + 1), Mechanism);
  else
    raise ECore1SelektorError.Create(Ukr('невідомий механізм Core1'));
  end;
end;

{ Physical: позичені канонічні packed T5M байти одного виклику.
  Слова/Doc/значення — власні тимчасові; на помилці відповіді немає
  взагалі (жодного часткового stdout).
  Питання: чому кількість аргументів мусить дорівнювати кількості
  параметрів? Чому невідомий D7 не переадресовується на перше замикання? }
function TCore1Selektor.ExecutePhysicalCall(
  const Physical: RawByteString): RawByteString;
var
  Words: TExactWords;
  Doc: TD2Document;
  Call, Item: TD2Node;
  Key: RawByteString;
  Params: TCore1KeyArray;
  Values: TCore1ValueArray;
  Value: TCore1Value;
  Ordinal, I, J: SizeInt;
begin
  Result := '';
  Doc := nil;
  Need((Length(Physical) > 0) and (Length(Physical) <= MaxCore1CallBytes),
    'порожній або завеликий фізичний виклик Core1');
  try
    DecodeT5M(Physical, Words);
  except
    on E: Exception do
      raise ECore1SelektorError.Create(Ukr('хибний T5M виклику: ') + E.Message);
  end;
  Need((Length(Words) > 0) and (Length(Words) <= MaxCore1CallWords),
    'перевищена фізична межа виклику Core1');
  Need(EncodeT5M(Words) = Physical, 'виклик не є канонічним T5M');
  try
    Doc := ParseD2WordsWide(Words);
    Need(Length(Doc.Roots) = 1, 'Core1 очікує рівно один фізичний корінь');
    Call := Doc.Roots[0];
    Need((Call <> nil) and (Call.Kind = dkList) and
      (Length(Call.Children) >= 2),
      'Core1 очікує виклик замикання з аргументами');
    Need(IsD7Sequence(Call.Children[0]),
      'голова виклику Core1 має бути точною D7-послідовністю');
    Key := NameKey(Call.Children[0]);
    Ordinal := FindPlan(Key);
    Params := FParams[Ordinal];
    Need(Length(Call.Children) - 1 = Length(Params),
      'кількість аргументів не дорівнює кількості параметрів Core1');
    SetLength(Values, Length(Params));
    for I := 0 to High(Params) do begin
      Item := Call.Children[I + 1];
      Need(Item <> nil, 'порожній аргумент Core1');
      Values[I] := SliceOf(Words, Item);
      { Фізичний D4:1110 у позиції аргументу позначає список-значення:
        його голова є конструктором списку, а не елементом. }
      if Values[I].IsList and (Length(Values[I].Words) > 0) and
         (Values[I].Words[0] = '1110') then begin
        for J := 0 to High(Values[I].Words) - 1 do
          Values[I].Words[J] := Values[I].Words[J + 1];
        SetLength(Values[I].Words, Length(Values[I].Words) - 1);
      end;
    end;
    Value := EvalNode(FBodies[Ordinal], Params, Values, 0);
    if Value.IsList then begin
      SetLength(Words, Length(Value.Words) + 2);
      Words[0] := '10';
      for I := 0 to High(Value.Words) do Words[I + 1] := Value.Words[I];
      Words[High(Words)] := '01';
      Result := EncodeT5M(Words);
    end else
      Result := EncodeT5M(Value.Words);
  finally
    Doc.Free;
  end;
end;

end.
