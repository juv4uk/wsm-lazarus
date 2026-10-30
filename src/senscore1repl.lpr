{ G5.70 — REPL Core1: читання української проєкції, виконання у СТАЛОМУ
  середовищі pinned Core1, друк результату тією ж проєкцією.

  Що це: справжній read–eval–print. Кожен рядок розбирається на точні
  біти, виклик іде в TCore1Selektor (104 із 129 pinned визначень), відповідь
  друкується назад у проєкцію.

  Чого це НЕ робить: не додає користувацьких визначень у світ, не є
  оракулом SENS, не виконує довільних форм. Середовище стале — це саме
  завантажений один раз pinned Core1, а не таблиця підстановок.

  Числовий літерал у цьому вході — десяткове ціле, яке стає точним
  D24-атомом (світ Core4 дає саме D24). Двійковий літерал довільної
  ширини (3..192 біти) приймається як є.

  Питання: чому імʼя розв'язується ДО координати, а не навпаки?
  Чому помилка рядка не завершує сеанс? Чому друк іде проєкцією, а
  не бітами? }
program senscore1repl;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d7text, wsm.core1selektor,
     wsm.proektsii,wsm.domain;

const
  MaxLineBytes = 4096;
  MaxTokens = 256;

type
  EReplError = class(Exception);
{ G6.131 — ЖОДНИХ локальних Name→Bits пар.
  Catalog — owned managed масив pinned D1–D10, шість ратифікованих
  поверхонь кожного слова; lifetime = цілий REPL-сеанс.
  Український текст — лише borrowed UTF-8 людська проєкція.
  Exact identity => Key.Width + KeyBits(Key) з pinned, не з імені.
  Невідоме ім'я залишається D7-ідентифікатором, а викличність
  і виконання залишаються ТІЛЬКИ у TCore1Selektor.
  1) Чому тут немає таблиці доступних операцій?
  2) Хто відхиляє ратифіковану, але непідтриману голову?
  3) Чому дві українські проєкції того самого ключа не колізія?
  4) Чому рівність назви без width/bit не є мовним законом?
  5) Чому pinned завантажуємо до першого рядка сеансу? }

var
  Map: TD7Map;
  Catalog: TProektsiiCatalog; { owned pinned six-column D1–D10 }
  Selector: TCore1Selektor;
  NameBits: array of RawByteString;   { точні біти імені → для розв'язання }
  NameText: array of RawByteString;

{ Один точний бік — у T5M. Обгортка, бо кодек приймає масив слів. }
function EncodeOne(const Word: RawByteString): RawByteString;
var
  Single: TExactWords;
begin
  SetLength(Single, 1);
  Single[0] := Word;
  Result := EncodeT5M(Single);
end;

{ Уся проєкція в цьому вході — UTF-8 байти. Ніяких перекодувань:
  подвійне кодування псує і порівняння команд, і текст помилок. }
procedure Say(const Text: RawByteString);
begin
  Writeln(Text);
  Flush(Output); { потрібен негайний stdout для довготривалого host pipe }
end;

procedure SayError(const Text: RawByteString);
begin
  Writeln(StdErr, Text);
  Flush(StdErr); { відмова не повинна чекати завершення REPL-сеансу }
end;

{ Рядок зі stdin як СИРІ байти: ReadLn перекодовує за системною
  кодовою сторінкою і псує українські токени. }
{ Рядок зі stdin як СИРІ байти. ReadLn на RawByteString з'їдає весь
  потік за один виклик, тому читаємо по байту з дескриптора. }
function ReadLineRaw(out Line: RawByteString): Boolean;
var
  Stream: THandleStream;
  Byte1: AnsiChar;
begin
  Line := '';
  Stream := THandleStream.Create(TextRec(Input).Handle);
  try
    while True do begin
      if Stream.Read(Byte1, 1) <= 0 then Break;
      if Byte1 = #10 then Exit(True);
      if Byte1 <> #13 then Line := Line + Byte1;
    end;
    Result := Line <> '';
  finally
    Stream.Free;
  end;
end;

function Bits24(Value: Int64): RawByteString;
var
  Bits: String;
  I: SizeInt;
  Unsigned: QWord;
begin
  if (Value < -8388608) or (Value > 8388607) then
    raise EReplError.Create('число поза доменом D24');
  { Додаємо в Int64 і аж потім переводимо в QWord: приведення
    від'ємного Int64 до QWord падає на перевірці діапазону. }
  if Value < 0 then Unsigned := QWord(16777216 + Value)
  else Unsigned := QWord(Value);
  SetLength(Bits, 24);
  for I := 1 to 24 do
    if (Unsigned and (QWord(1) shl (24 - I))) <> 0 then Bits[I] := '1'
    else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

function BitsToInt24(const Bits: RawByteString): Int64;
var
  I: SizeInt;
  Value: QWord;
begin
  Value := 0;
  for I := 1 to Length(Bits) do begin
    Value := Value shl 1;
    if Bits[I] = '1' then Value := Value or 1;
  end;
  if (Length(Bits) = 24) and ((Value and $800000) <> 0) then
    Result := Int64(Value) - 16777216
  else
    Result := Int64(Value);
end;





function IsBinaryLiteral(const Token: RawByteString): Boolean;
var
  I: SizeInt;
begin
  Result := Length(Token) > 0;
  for I := 1 to Length(Token) do
    if not (Token[I] in ['0', '1']) then Exit(False);
end;

function IsDecimalLiteral(const Token: RawByteString; out Value: Int64): Boolean;
var
  Text: RawByteString;
  I: SizeInt;
begin
  Result := False;
  Value := 0;
  if Length(Token) = 0 then Exit;
  Text := Token;
  if Text[1] = '-' then Delete(Text, 1, 1);
  if Length(Text) = 0 then Exit;
  for I := 1 to Length(Text) do
    if not (Text[I] in ['0'..'9']) then Exit;
  Value := StrToInt64(Token);
  Result := True;
end;

{ Точні біти імені: спершу координата механізму, далі — pinned визначення,
  далі — стала світу. Невідоме імʼя — відмова, без здогадів. }
{ Скануємо ЛИШЕ pinned «ук» та «укр» у вже перевіреному
  Catalog. Стан: Found=неоднозначність не допускаємо; ті ж exact
  Width/Bits у двох колонках = один і той самий SENS ключ. Немає
  словника, локальних кодів, нових проєкцій чи мовного dispatch. }
function ResolvePinnedCoordinate(const Token:RawByteString;
  out Bits:RawByteString):Boolean;
var D,I,Column:SizeInt;Key,Previous:TDomainKey;Found:Boolean;
begin
  Result:=False;Bits:='';Found:=False;
  if Token='' then Exit;
  for D:=1 to 10 do begin
    { D7 — тільки фонеми текстової площини: «а» є гліфом
      параметра, НЕ callable D7 механізмом! }
    if D=7 then Continue;
    for I:=0 to High(Catalog[D]) do
      for Column:=0 to 1 do begin
        if (Catalog[D][I].Surface[Column]='') or
           (Catalog[D][I].Surface[Column]<>Token) then Continue;
        Key:=Catalog[D][I].Key;
        if Found and (not SameKey(Key,Previous)) then
          raise EReplError.Create('неоднозначна pinned українська проєкція: '+
            String(Token));
        Found:=True;Previous:=Key;
      end;
  end;
  if Found then begin
    Bits:=KeyBits(Previous);
    Result:=True;
  end;
end;

function IsMechanismToken(const Token:RawByteString):Boolean;
var Bits:RawByteString;I:SizeInt;
begin
  { Лексичне ім’я вже допущено з pinned або user Core1 DEFINE:
    воно не стає ратифікованим opcode через збіг тексту. }
  for I:=0 to High(NameText) do
    if NameText[I]=Token then Exit(False);
  Result:=ResolvePinnedCoordinate(Token,Bits);
end;

function ResolveName(const Token: RawByteString): RawByteString;
var I:SizeInt;Glyphs:TExactWords;
begin
  { Після DEFINE локальне лексичне ім'я завжди має перевагу
    над омонімічною pinned людиною проєкцією, але саме Core1
    вирішує допустимість його виконання. }
  for I:=0 to High(NameText) do
    if NameText[I]=Token then Exit(NameBits[I]);
  if ResolvePinnedCoordinate(Token,Result) then Exit;
  { Інші назви — exact D7-послідовності; відхилення/викличність
    оцінює pinned Core1, не каталог проєкцій. }
  try
    DecodeT5M(EncodeD7Text(Token,Map,dsUk),Glyphs);
  except on E:Exception do
    raise EReplError.Create('невідоме ім’я у проєкції: '+String(Token));
  end;
  Result:='';
  for I:=0 to High(Glyphs) do Result:=Result+Glyphs[I];
  if Result='' then raise EReplError.Create('порожнє ім’я у проєкції: '+
    String(Token));
end;

procedure BuildNameIndex;
var
  I, J, Count: SizeInt;
  Text: RawByteString;
begin
  SetLength(NameBits, Selector.AdmittedCount);
  SetLength(NameText, Selector.AdmittedCount);
  for I := 0 to Selector.AdmittedCount - 1 do begin
    NameBits[I] := Selector.AdmittedName(I);
    Text := '';
    Count := Length(NameBits[I]) div 7;
    try
      for J := 1 to Count do
        Text := Text + DecodeD7Text(
          EncodeOne(Copy(NameBits[I], (J - 1) * 7 + 1, 7)), Map, dsUk);
    except
      on E: Exception do Text := '';
    end;
    NameText[I] := Text;
  end;
end;

{ Розбір одного рядка проєкції у точні слова. Дужки — структура,
  решта — атоми. Жодного прихованого dispatch: усе через ResolveName. }
function ParseLine(const Line: RawByteString; out Words: TExactWords): Boolean;
var
  Tokens: array of RawByteString;
  Stack: array of SizeInt;   { індекси відкритих списків у Words }
  IsQuote: array of Boolean; { чи цей список — (як-є …) }
  First: array of Boolean;   { чи наступний токен — голова списку }
  ExpectName: array of Boolean; { другий дочірній вузол D4 DEFINE — D7 ім'я }
  ExpectParams: array of Boolean; { наступний список D4 LAMBDA — параметри }
  Formal: array of Boolean; { параметри є власні D7 імена, не pinned Dn }
  IsLambda:array of Boolean;
  LocalNames:array of RawByteString; { D7 лексичні імена в поточному scope }
  LocalDepth:array of SizeInt; { lambda frame depth кожного імені }
  I, Depth, Count, P: SizeInt;
  Token: RawByteString;
  Value: Int64;
  Bits: RawByteString;
  Literal: RawByteString;
  ForcedD7: Boolean;
  Glyphs: TExactWords;
  G:SizeInt;

  function IsLocal(const Name:RawByteString):Boolean;
  var L:SizeInt;
  begin
    Result:=False;
    for L:=High(LocalNames) downto 0 do
      if LocalNames[L]=Name then Exit(True);
  end;

  procedure Push(const Word: RawByteString);
  begin
    if Count > MaxTokens * 8 then raise EReplError.Create('рядок задовгий');
    SetLength(Words, Count + 1);
    Words[Count] := Word;
    Inc(Count);
  end;

begin
  Result := False;
  Words := nil; Count := 0; Depth := 0;
  SetLength(Stack, 32);
  SetLength(IsQuote, 32);
  SetLength(First, 32);
  SetLength(ExpectName,32);
  SetLength(ExpectParams,32);
  SetLength(Formal,32);
  SetLength(IsLambda,32);
  SetLength(LocalNames,0);SetLength(LocalDepth,0);
  SetLength(Tokens, 0);
  Token := '';
  for I := 1 to Length(Line) do begin
    if Line[I] in [' ', #9, #13] then begin
      if Token <> '' then begin
        SetLength(Tokens, Length(Tokens) + 1);
        Tokens[High(Tokens)] := Token;
        Token := '';
      end;
    end else if Line[I] = '(' then begin
      if Token <> '' then begin
        SetLength(Tokens, Length(Tokens) + 1);
        Tokens[High(Tokens)] := Token;
        Token := '';
      end;
      SetLength(Tokens, Length(Tokens) + 1);
      Tokens[High(Tokens)] := '(';
    end else if Line[I] = ')' then begin
      if Token <> '' then begin
        SetLength(Tokens, Length(Tokens) + 1);
        Tokens[High(Tokens)] := Token;
        Token := '';
      end;
      SetLength(Tokens, Length(Tokens) + 1);
      Tokens[High(Tokens)] := ')';
    end else
      Token := Token + Line[I];
  end;
  if Token <> '' then begin
    SetLength(Tokens, Length(Tokens) + 1);
    Tokens[High(Tokens)] := Token;
  end;
  if Length(Tokens) = 0 then Exit;

  for P := 0 to High(Tokens) do begin
    if Tokens[P] = '(' then begin
      if Depth >= Length(Stack) then begin
        SetLength(Stack, Depth * 2);
        SetLength(IsQuote, Depth * 2);
        SetLength(First, Depth * 2);
        SetLength(ExpectName,Depth * 2);
        SetLength(ExpectParams,Depth * 2);
        SetLength(Formal,Depth * 2);
        SetLength(IsLambda,Depth * 2);
      end;
      Push('10');
      Stack[Depth] := Count - 1;
      IsQuote[Depth] := False;
      First[Depth] := True;
      ExpectName[Depth] := False;
      ExpectParams[Depth] := False;
      IsLambda[Depth]:=False;
      Formal[Depth] := (Depth>0) and ExpectParams[Depth-1];
      if Formal[Depth] then ExpectParams[Depth-1]:=False;
      Inc(Depth);
    end else if Tokens[P] = ')' then begin
      if Depth = 0 then raise EReplError.Create('зайва закривна дужка');
      Push('01');
      Dec(Depth);
      if IsLambda[Depth] then
        while (Length(LocalDepth)>0) and
              (LocalDepth[High(LocalDepth)]>=Depth) do begin
          SetLength(LocalDepth,Length(LocalDepth)-1);
          SetLength(LocalNames,Length(LocalNames)-1);
        end;
    end else if IsBinaryLiteral(Tokens[P]) and (Length(Tokens[P]) >= 3) then begin
      Literal := RawByteString(Tokens[P]);
      if (Depth > 0) and IsQuote[Depth - 1] then Push(Literal)
      else begin Push('10'); Push('001'); Push(Literal); Push('01'); end;
      if Depth > 0 then First[Depth - 1] := False;
    end else if IsDecimalLiteral(Tokens[P], Value) then begin
      Literal := Bits24(Value);
      if (Depth > 0) and IsQuote[Depth - 1] then Push(Literal)
      else begin Push('10'); Push('001'); Push(Literal); Push('01'); end;
      if Depth > 0 then First[Depth - 1] := False;
    end else begin
      ForcedD7:=((Depth>0) and
        (ExpectName[Depth-1] or Formal[Depth-1])) or
        IsLocal(Tokens[P]);
      if ForcedD7 then begin
        { За D4:0011 наступна назва — ЛЕКСИЧНЕ D7 ім'я
          визначення. Навіть «модуль» — pinned D6:010011 —
          не перетворюється на opcode під час оголошення. }
        DecodeT5M(EncodeD7Text(Tokens[P],Map,dsUk),Glyphs);
        Bits:='';
        for G:=0 to High(Glyphs) do Bits:=Bits+Glyphs[G];
        if (Depth>0) and Formal[Depth-1] then begin
          SetLength(LocalNames,Length(LocalNames)+1);
          SetLength(LocalDepth,Length(LocalDepth)+1);
          LocalNames[High(LocalNames)]:=Tokens[P];
          LocalDepth[High(LocalDepth)]:=Depth-2;
        end;
        if Depth>0 then ExpectName[Depth-1]:=False;
      end else
        Bits:=ResolveName(Tokens[P]);
      { Ознака цитати/визначення — за точними pinned координатами. }
      if (Depth > 0) and First[Depth - 1] then begin
        First[Depth - 1] := False;
        if Bits = '001' then IsQuote[Depth - 1] := True;
        if Bits = '0011' then ExpectName[Depth-1]:=True;
        if Bits = '0010' then begin
          ExpectParams[Depth-1]:=True;
          IsLambda[Depth-1]:=True;
        end;
      end;
      { Лексичне ім'я — D7 список, opcode — exact голий Wn. }
      if (ForcedD7 or (not IsMechanismToken(Tokens[P]))) and
         (Length(Bits) mod 7 = 0) and (Length(Bits) > 0) then begin
        Push('10');
        I := 1;
        while I + 6 <= Length(Bits) do begin
          Push(Copy(Bits, I, 7));
          Inc(I, 7);
        end;
        Push('01');
      end else
        Push(Bits);
    end;
  end;
  if Depth <> 0 then raise EReplError.Create('незакритий список');
  Result := True;
end;

{ Друк відповіді проєкцією: списки — дужками, 7-бітові слова — гліфами,
  числові домени — десятковим числом, решта — точними бітами. }
function RenderWords(const Words: TExactWords): RawByteString;
var
  I, J, Count: SizeInt;
  Part: RawByteString;
  Numeric: Boolean;
  Value: Int64;

  function RenderAtom(const Word: RawByteString): RawByteString;
  var
    K: SizeInt;
    Text: RawByteString;
  begin
    if Word = '000' then Exit('()');
    Numeric := (Length(Word) in [12, 24, 48, 96, 192]);
    if Numeric then begin
      if Length(Word) = 24 then Exit(RawByteString(IntToStr(BitsToInt24(Word))));
      Exit(Word);
    end;
    if (Length(Word) > 0) and (Length(Word) mod 7 = 0) then begin
      Text := '';
      try
        for K := 1 to Length(Word) div 7 do
          Text := Text + DecodeD7Text(
            EncodeOne(Copy(Word, (K - 1) * 7 + 1, 7)), Map, dsUk);
        Exit(Text);
      except
        on E: Exception do ;
      end;
    end;
    Result := Word;
  end;

begin
  Result := '';
  I := 0;
  Count := 0;
  while I <= High(Words) do begin
    if Words[I] = '10' then begin
      Result := Result + '(';
      Inc(Count);
      Inc(I);
    end else if Words[I] = '01' then begin
      Result := Result + ')';
      Dec(Count);
      Inc(I);
    end else begin
      if (Count > 0) and (Result <> '') and (Result[Length(Result)] <> '(') then
        Result := Result + ' ';
      Result := Result + RenderAtom(Words[I]);
      Inc(I);
    end;
  end;
end;

function Evaluate(const Line: RawByteString): RawByteString;
var
  Words: TExactWords;

  Answer: RawByteString;
  Back: TExactWords;
begin
  if not ParseLine(Line, Words) then Exit('');
  { Голова-механізм у цьому вході ще не виконується: точка входу
    обчислювача приймає виклик ВИЗНАЧЕННЯ Core1. Відмовляємо явно,
    а не мовчазною помилкою розбору. }
  { Голова-визначення Core1 іде перевіреним шляхом виклику: він звіряє
    арність із точними параметрами. Голова-механізм — шляхом виразу. }
  { (визначити …) не обчислюється, а ДОДАЄТЬСЯ у світ сеансу — тіло
    проходить ту саму перевірку допуску, що й pinned визначення. }
  if (Length(Words) >= 2) and (Words[1] = '0011') then begin
    Selector.AdmitUserDefinition(EncodeT5M(Words));
    { Після допуску нове D7 ім’я доступне наступному рядку й має
      пріоритет над омонімом pinned Dn у лексичному світі. }
    BuildNameIndex;
    Exit(RawByteString('визначено; усього ') +
      RawByteString(IntToStr(Selector.AdmittedCount)));
  end;
  Answer := Selector.EvaluateExpression(EncodeT5M(Words));
  DecodeT5M(Answer, Back);
  Result := RenderWords(Back);
end;

procedure Run;
var
  Line: RawByteString;
  Command: RawByteString;
  CountText: RawByteString;
begin
  Say('SENS Core1 REPL — українська проєкція, стале середовище pinned Core1.');
  CountText := RawByteString(IntToStr(Selector.AdmittedCount));
  { Друге число — заявлена поверхня pinned core1.sens, порахована самим
    відбірником із фізичного файла, а не вписана в текст. }
  Say(RawByteString('Допущених визначень: ') + CountText +
    RawByteString(' із ') + RawByteString(IntToStr(Selector.DeclaredCount)) +
    RawByteString('.'));
  Say('Двійковий літерал — точні біти (3..192); десяткове ціле — D24.');
  Say('Команди: :help, :quit.');
  while ReadLineRaw(Line) do begin
    Write(StdErr, 'сенс> ');
    Flush(StdErr);
    Line := Trim(Line);
    if Line = '' then Continue;
    Command := LowerCase(Line);
    { Команди латинські — з тієї самої причини, що й прапорці CLI:
      порівняння українських літералів залежить від кодової сторінки. }
    if (Command = ':quit') or (Command = ':q') then Break;
    if (Command = ':help') then begin
      Say('Форми: (додати 2 3), (менше? 2 3), (сполучити (як-є 5) (як-є ())),');
      Say('        (назви-рівні? (як-є a) (як-є a)).');
      Say('Помилка рядка не завершує сеанс — середовище лишається сталим.');
      Continue;
    end;
    try
      Say(Evaluate(Line));
    except
      on E: Exception do
        SayError(RawByteString('; помилка: ') + RawByteString(E.Message));
    end;
  end;
  SayError('; сеанс завершено');
end;

begin
  LoadPinnedD7Map(ParamStr(1), Map);
  LoadPinnedProjections(IncludeTrailingPathDelimiter(ParamStr(1))+
    'external'+PathDelim+'sens',Catalog);
  Selector := TCore1Selektor.Create(ParamStr(1));
  try
    BuildNameIndex;
    Run;
  finally
    Selector.Free;
  end;
end.
