{ Core1.6: фізичне виконання ДРУГОГО й ТРЕТЬОГО pinned визначення Core1.
  Тіло замикання допускається лише як композиція вже ратифікованих
  селекторів над єдиним лексичним параметром. Жодного власного реєстру
  законів, жодного текстового dispatch за назвою, жодної копії
  бібліотечних DEFINE у Pascal.

  Механізми не вигадані: D3:011 «решта» виконує наявний TBinaryExecutor,
  D4:1001 «друге» і D5:10011 «третє» — наявний TCore4Runtime.
  Композиція CADR(CDR x) тут НЕ є механізмом: вона лишається незалежним
  оракулом у тесті, щоб два різні шляхи давали той самий результат.

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
  TCore1Mechanism = (cmRest, cmSecond, cmThird);
  TCore1Steps = array of TCore1Mechanism;

  { Значення під час одного виконання.
    Words — точні слова БЕЗ маркера D4:1110: або елементи списку,
    або одне/кілька вибраних слів. IsList — структурна ознака того,
    що Words є елементами списку, а не самим значенням. }
  TCore1Value = record
    Words: TExactWords;
    IsList: Boolean;
  end;

  TCore1Selektor = class
  private
    FDocument: TD2Document;         { власний: розібраний pinned core1.sens }
    FWords: TExactWords;            { власний: точні слова того ж файла }
    FExecutor: TCore4Runtime;       { власний: наявний механізм D4 }
    FBinary: TBinaryExecutor;       { власний: наявний механізм D3 }
    FNames: array of RawByteString; { точні D7-ключі допущених DEFINE }
    FBodyText: array of String;     { тіло в pinned координатах, для звіту }
    FSteps: array of TCore1Steps;   { розкриті кроки виконання }
    procedure Admit(const Root: TD2Node);
    function NameKey(const Node: TD2Node): RawByteString;
    function IsD7Sequence(const Node: TD2Node): Boolean;
    function MechanismOf(const Head: TD2Node): TCore1Mechanism;
    function ExpandPlan(const Steps: TCore1Steps): TCore1Steps;
    function PlanOf(const Body: TD2Node; const Parameter: RawByteString;
      Depth: SizeInt; out BodyText: String;
      out IsIdentity: Boolean): TCore1Steps;
    function FindPlan(const Key: RawByteString): SizeInt;
    function Apply(const Mechanism: TCore1Mechanism;
      const Value: TCore1Value): TCore1Value;
    function ApplyRest(const Value: TCore1Value): TCore1Value;
    function ApplySecond(const Value: TCore1Value): TCore1Value;
    function ApplyThird(const Value: TCore1Value): TCore1Value;
  public
    constructor Create(const WorkspaceRoot: String);
    destructor Destroy; override;
    function AdmittedCount: SizeInt;
    function AdmittedName(Ordinal: SizeInt): RawByteString;
    function AdmittedBodyText(Ordinal: SizeInt): String;
    function AdmittedMechanismText(Ordinal: SizeInt): String;
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
  MaxCore1PlanDepth = 6;
  MaxCore1PlanSteps = 8;

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
    cmRest:   Result := 'D3:011';
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

{ Вузол належить FDocument і живе до Destroy.
  Ключ копіюється (RawByteString): це точні біти, не текст і не opcode.
  Питання: чому D7-послідовність не є назвою? Хто звільняє вузол?
  Чому не можна вивести викличність із самої лише ширини? }
{ Структурна перевірка БЕЗ винятку: чи є вузол непорожньою
  послідовністю рівно семибітних точних слів. Потрібна для того,
  щоб невідоме тіло давало саме EUnsupportedCore1Body, а не
  помилку формату під час admission.
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

function TCore1Selektor.NameKey(const Node: TD2Node): RawByteString;
var
  I: SizeInt;
begin
  Need((Node <> nil) and (Node.Kind = dkList) and
    (Length(Node.Children) > 0) and (Length(Node.Children) <= 256),
    'очікувана непорожня точна D7-послідовність');
  Result := '';
  for I := 0 to High(Node.Children) do begin
    Need((Node.Children[I] <> nil) and
      (Node.Children[I].Kind = dkIdentity) and
      (Node.Children[I].Width = 7),
      'недійсна фізична D7-координата ідентифікатора');
    Result := Result + Node.Children[I].Bits;
  end;
end;

{ Тільки три ратифіковані координати мають механізм у цьому зрізі.
  Ширина перевіряється РАЗОМ із бітами: 3-бітне 011 і 4-бітне 0011
  не є однією координатою лише тому, що їхні біти схожі. }
function TCore1Selektor.MechanismOf(const Head: TD2Node): TCore1Mechanism;
begin
  if (Head = nil) or (Head.Kind <> dkIdentity) then
    raise EUnsupportedCore1Body.Create('тіло не є викликом селектора');
  if (Head.Width = 3) and (Head.Bits = '011') then Exit(cmRest);
  if (Head.Width = 4) and (Head.Bits = '1001') then Exit(cmSecond);
  if (Head.Width = 5) and (Head.Bits = '10011') then Exit(cmThird);
  raise EUnsupportedCore1Body.Create('невідома координата тіла Core1');
end;

{ Кожен крок плану — це рівно одна ратифікована координата з власним
  наявним механізмом. Розкриття не потрібне: D5:10011 виконує сам
  TCore4Runtime, тому тут немає ні композиції, ні нового закону.
  Питання: чому крок не може об'єднувати дві координати?
  Чому межа кроків тримається до admission? }
function TCore1Selektor.ExpandPlan(const Steps: TCore1Steps): TCore1Steps;
begin
  if Length(Steps) > MaxCore1PlanSteps then
    raise EUnsupportedCore1Body.Create('задовгий план виконання');
  Result := Copy(Steps, 0, Length(Steps));
end;

{ План будується ЛИШЕ з фізичного AST pinned core1.sens.
  Дозволено рівно дві форми тіла: сам параметр (тотожність) і
  виклик одного ратифікованого селектора над підпланом.
  Невідомі форми дають EUnsupportedCore1Body, а не припущення.
  Питання: чому тіло не можна підмінити текстом? Чому глибина обмежена?
  Чому порожній план означає тотожність, а не хибу? }
function TCore1Selektor.PlanOf(const Body: TD2Node;
  const Parameter: RawByteString; Depth: SizeInt;
  out BodyText: String; out IsIdentity: Boolean): TCore1Steps;
var
  Inner: TCore1Steps;
  InnerText: String;
  InnerIdentity: Boolean;
  Mechanism: TCore1Mechanism;
  I: SizeInt;
begin
  IsIdentity := False;
  if Depth > MaxCore1PlanDepth then
    raise EUnsupportedCore1Body.Create('занадто глибока композиція тіла');
  if (Body = nil) or (Body.Kind <> dkList) or (Length(Body.Children) = 0) then
    raise EUnsupportedCore1Body.Create('тіло не є фізичним списком');
  { Тотожність: тіло — рівно сам лексичний параметр. }
  if IsD7Sequence(Body) and (NameKey(Body) = Parameter) then begin
    BodyText := 'тотожність';
    IsIdentity := True;
    Exit(nil);
  end;
  if Length(Body.Children) <> 2 then
    raise EUnsupportedCore1Body.Create('тіло не є викликом одного селектора');
  Mechanism := MechanismOf(Body.Children[0]);
  Inner := PlanOf(Body.Children[1], Parameter, Depth + 1, InnerText,
    InnerIdentity);
  if Length(Inner) + 1 > MaxCore1PlanSteps then
    raise EUnsupportedCore1Body.Create('задовгий план виконання');
  SetLength(Result, Length(Inner) + 1);
  for I := 0 to High(Inner) do Result[I] := Inner[I];
  Result[High(Result)] := Mechanism;
  if InnerIdentity then
    BodyText := MechanismText(Mechanism)
  else
    BodyText := MechanismText(Mechanism) + '(' + InnerText + ')';
end;

{ Приймається лише (D4:0011 name (D4:0010 (param) body)).
  Рівно один лексичний параметр: інші визначення цього зрізу не
  підтримані й лишаються явно недопущеними.
  Питання: чому рівно один параметр? Чому D4:0011/D4:0010 точні?
  Хто володіє Lambda/Args/Body? Чому невідоме тіло не стає NIL? }
procedure TCore1Selektor.Admit(const Root: TD2Node);
var
  Lambda, Args, Body: TD2Node;
  Parameter, Key: RawByteString;
  Steps: TCore1Steps;
  BodyText: String;
  Identity: Boolean;
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
     (Length(Args.Children) <> 1) then
    raise EUnsupportedCore1Body.Create('потрібен рівно один параметр');
  Parameter := NameKey(Args.Children[0]);
  Body := Lambda.Children[2];
  Steps := PlanOf(Body, Parameter, 0, BodyText, Identity);
  if Length(Steps) = 0 then
    raise EUnsupportedCore1Body.Create('тотожність не є селектором Core1');
  Key := NameKey(Root.Children[1]);
  for I := 0 to High(FNames) do
    if FNames[I] = Key then
      raise EUnsupportedCore1Body.Create('повторний точний D7-ключ Core1');
  SetLength(FNames, Length(FNames) + 1);
  SetLength(FBodyText, Length(FBodyText) + 1);
  SetLength(FSteps, Length(FSteps) + 1);
  FNames[High(FNames)] := Key;
  FBodyText[High(FBodyText)] := BodyText;
  FSteps[High(FSteps)] := ExpandPlan(Steps);
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

function TCore1Selektor.AdmittedBodyText(Ordinal: SizeInt): String;
begin
  Need((Ordinal >= 0) and (Ordinal < Length(FBodyText)),
    'неприпустимий номер допущеного визначення Core1');
  Result := FBodyText[Ordinal];
end;

function TCore1Selektor.AdmittedMechanismText(Ordinal: SizeInt): String;
var
  I: SizeInt;
begin
  Need((Ordinal >= 0) and (Ordinal < Length(FSteps)),
    'неприпустимий номер допущеного визначення Core1');
  Result := '';
  for I := 0 to High(FSteps[Ordinal]) do begin
    if Result <> '' then Result := Result + ',';
    Result := Result + MechanismText(FSteps[Ordinal][I]);
  end;
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

{ D3:011 «решта» виконує наявний TBinaryExecutor над цитованим
  фізичним списком; він повертає фізичний список без маркера D4:1110,
  тому маркер не вигадується, а просто відсутній у D3-значенні.
  Питання: чому аргумент цитовано? Чому результат — елементи, не значення?
  Хто звільняє тимчасові масиви слів? }
function TCore1Selektor.ApplyRest(const Value: TCore1Value): TCore1Value;
var
  Call, Quoted: TExactWords;
  Answer: RawByteString;
  Back: TExactWords;
  I, N: SizeInt;
begin
  Need(Value.IsList, 'D3:011 потребує фізичного списку, не атома');
  N := Length(Value.Words);
  Need((N > 0) and (N <= MaxCore1Elements),
    'неприпустима кількість елементів для D3:011');
  { (10 011 (10 001 (10 <елементи> 01) 01) 01): три відкриті 10 і три 01. }
  SetLength(Quoted, N + 5);
  Quoted[0] := '10'; Quoted[1] := '001'; Quoted[2] := '10';
  for I := 0 to N - 1 do Quoted[I + 3] := Value.Words[I];
  Quoted[N + 3] := '01';
  Quoted[N + 4] := '01';
  SetLength(Call, N + 8);
  Call[0] := '10'; Call[1] := '011';
  for I := 0 to High(Quoted) do Call[I + 2] := Quoted[I];
  Call[Length(Quoted) + 2] := '01';
  Answer := FBinary.ExecutePhysicalT5M(EncodeT5M(Call));
  DecodeT5M(Answer, Back);
  Need((Length(Back) >= 2) and (Back[0] = '10') and
    (Back[High(Back)] = '01'),
    'D3:011 повернув не фізичний список');
  SetLength(Result.Words, Length(Back) - 2);
  for I := 1 to Length(Back) - 2 do Result.Words[I - 1] := Back[I];
  Result.IsList := True;
end;

{ D4:1001 «друге» виконує наявний TCore4Runtime; цей механізм уже
  доведений першим замиканням Core1, тому тут немає другої семантики.
  Аргумент подається як фізичний D4:1110 список — саме та форма,
  яку цей механізм приймає.
  Питання: чому маркер D4:1110 додається тут? Чому результат може бути
  списком? Чому відсутній елемент — відмова, а не порожнеча? }
function TCore1Selektor.ApplySecond(const Value: TCore1Value): TCore1Value;
var
  Call: TExactWords;
  Answer: RawByteString;
  Back: TExactWords;
  I, N: SizeInt;
begin
  Need(Value.IsList, 'D4:1001 потребує фізичного списку, не атома');
  N := Length(Value.Words);
  Need((N > 0) and (N <= MaxCore1Elements),
    'неприпустима кількість елементів для D4:1001');
  { (10 1001 (10 1110 <елементи> 01) 01) }
  SetLength(Call, N + 6);
  Call[0] := '10'; Call[1] := '1001'; Call[2] := '10'; Call[3] := '1110';
  for I := 0 to N - 1 do Call[I + 4] := Value.Words[I];
  Call[N + 4] := '01'; Call[N + 5] := '01';
  Answer := FExecutor.ExecutePhysicalCall(EncodeT5M(Call));
  DecodeT5M(Answer, Back);
  Need(Length(Back) > 0, 'D4:1001 повернув порожню фізичну відповідь');
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

{ D5:10011 «третє» виконує наявний TCore4Runtime, який уже приймає
  цей ратифікований селектор над фізичним D4:1110 списком.
  Аргумент подається тією самою формою, що й для D4:1001.
  Питання: чому ширина 5 є частиною тотожності? Чому тут немає
  власного обходу списку? Хто звільняє тимчасовий Call? }
function TCore1Selektor.ApplyThird(const Value: TCore1Value): TCore1Value;
var
  Call: TExactWords;
  Answer: RawByteString;
  Back: TExactWords;
  I, N: SizeInt;
begin
  Need(Value.IsList, 'D5:10011 потребує фізичного списку, не атома');
  N := Length(Value.Words);
  Need((N > 0) and (N <= MaxCore1Elements),
    'неприпустима кількість елементів для D5:10011');
  { (10 10011 (10 1110 <елементи> 01) 01) }
  SetLength(Call, N + 6);
  Call[0] := '10'; Call[1] := '10011'; Call[2] := '10'; Call[3] := '1110';
  for I := 0 to N - 1 do Call[I + 4] := Value.Words[I];
  Call[N + 4] := '01'; Call[N + 5] := '01';
  Answer := FExecutor.ExecutePhysicalCall(EncodeT5M(Call));
  DecodeT5M(Answer, Back);
  Need(Length(Back) > 0, 'D5:10011 повернув порожню фізичну відповідь');
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

function TCore1Selektor.Apply(const Mechanism: TCore1Mechanism;
  const Value: TCore1Value): TCore1Value;
begin
  case Mechanism of
    cmRest: Result := ApplyRest(Value);
    cmSecond: Result := ApplySecond(Value);
    cmThird: Result := ApplyThird(Value);
  else
    raise ECore1SelektorError.Create(Ukr('невідомий механізм Core1'));
  end;
end;

{ Physical: позичені канонічні packed T5M байти одного виклику.
  Слова/Doc/Value — власні тимчасові; на помилці відповіді немає
  взагалі (жодного часткового stdout).
  Питання: чому рівно один корінь? Чому аргумент має бути D4:1110?
  Чому невідомий D7 не переадресовується на перше замикання? }
function TCore1Selektor.ExecutePhysicalCall(
  const Physical: RawByteString): RawByteString;
var
  Words: TExactWords;
  Doc: TD2Document;
  Call, Argument: TD2Node;
  Key: RawByteString;
  Plan: TCore1Steps;
  Value: TCore1Value;
  Ordinal, StartAt, AfterAt, I, N: SizeInt;
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
      (Length(Call.Children) = 2),
      'Core1 очікує виклик замикання з одним аргументом');
    Need(IsD7Sequence(Call.Children[0]),
      'голова виклику Core1 має бути точною D7-послідовністю');
    Key := NameKey(Call.Children[0]);
    Ordinal := FindPlan(Key);
    Plan := FSteps[Ordinal];
    Argument := Call.Children[1];
    Need((Argument <> nil) and (Argument.Kind = dkList) and
      (Length(Argument.Children) >= 1),
      'потрібен фізичний список-аргумент');
    Need((Argument.Children[0] <> nil) and
      (Argument.Children[0].Kind = dkIdentity) and
      (Argument.Children[0].Width = 4) and
      (Argument.Children[0].Bits = '1110'),
      'цей зріз приймає лише точний D4:1110 список');
    StartAt := Argument.WordIndex - 1;
    AfterAt := Argument.EndWordIndexExclusive - 1;
    Need((StartAt >= 0) and (AfterAt >= StartAt + 3) and
      (AfterAt <= Length(Words)), 'пошкоджений фізичний інтервал аргумента');
    { Відкидаємо '10', '1110' і фінальний '01': лишаються елементи. }
    N := AfterAt - StartAt - 3;
    Need((N >= 0) and (N <= MaxCore1Elements),
      'неприпустима кількість елементів аргумента');
    SetLength(Value.Words, N);
    for I := 0 to N - 1 do Value.Words[I] := Words[StartAt + 2 + I];
    Value.IsList := True;
    for I := 0 to High(Plan) do
      Value := Apply(Plan[I], Value);
    if Value.IsList then begin
      SetLength(Words, Length(Value.Words) + 3);
      Words[0] := '10'; Words[1] := '1110';
      for I := 0 to High(Value.Words) do Words[I + 2] := Value.Words[I];
      Words[High(Words)] := '01';
      Result := EncodeT5M(Words);
    end else
      Result := EncodeT5M(Value.Words);
  finally
    Doc.Free;
  end;
end;

end.
