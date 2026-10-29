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
  TCore1Mechanism = (cmQuote, cmCons, cmRest, cmFirst, cmSecond, cmThird);

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
    FTexts: array of String;        { тіло в pinned координатах, для звіту }
    procedure Admit(const Root: TD2Node);
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
    function FindAdmitted(const Key: RawByteString): SizeInt;
    function ExecutePhysicalCall(const Physical: RawByteString): RawByteString;
  end;

implementation
uses Classes;

const
  { Ті самі межі, що вже чинні в цьому репозиторії для одного виклику. }
  MaxCore1CallBytes = 65536;
  MaxCore1CallWords = 4096;
  MaxCore1Elements = 64;
  MaxCore1Parameters = 4;
  MaxCore1BodyDepth = 6;

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
  { Посилання на параметр: рівно його точний D7-ключ. }
  if IsD7Sequence(Body) then begin
    Index := ParamIndex(Params, Body);
    if Index < 0 then
      raise EUnsupportedCore1Body.Create('імʼя поза лексичним середовищем');
    Exit('arg' + IntToStr(Index));
  end;
  if (Body.Kind <> dkList) or (Length(Body.Children) = 0) then
    raise EUnsupportedCore1Body.Create('тіло не є фізичним списком');
  Mechanism := MechanismOf(Body.Children[0], Arity);
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
procedure TCore1Selektor.Admit(const Root: TD2Node);
var
  Lambda, Args, Body: TD2Node;
  Params: TCore1KeyArray;
  Key: RawByteString;
  Text: String;
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
  Text := CheckBody(Body, Params, 0);
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
  FTexts[High(FTexts)] := Text;
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
    for I := 0 to High(FDocument.Roots) do
      try
        Admit(FDocument.Roots[I]);
      except
        on E: EUnsupportedCore1Body do ; { явно недопущене визначення }
      end;
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
  { Посилання на параметр: точний D7-ключ, не текст. }
  if IsD7Sequence(Node) then begin
    Index := ParamIndex(Params, Node);
    Need(Index >= 0, 'імʼя поза лексичним середовищем Core1');
    Exit(Values[Index]);
  end;
  Need((Node.Kind = dkList) and (Length(Node.Children) > 0),
    'тіло Core1 не є фізичним списком');
  Mechanism := MechanismOf(Node.Children[0], Arity);
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
