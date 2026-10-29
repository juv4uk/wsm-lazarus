{ G5.70 — REPL Core1: читання української проєкції, виконання у СТАЛОМУ
  середовищі pinned Core1, друк результату тією ж проєкцією.

  Що це: справжній read–eval–print. Кожен рядок розбирається на точні
  біти, виклик іде в TCore1Selektor (92 із 96 pinned визначень), відповідь
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
uses SysUtils, Classes, wsm.t5m, wsm.d7text, wsm.core1selektor;

const
  MaxLineBytes = 4096;
  MaxTokens = 256;

type
  EReplError = class(Exception);
  TMechanism = record
    Name: RawByteString;
    Bits: RawByteString;
  end;

const
  { Точні координати вже підтриманих механізмів — ті самі, що їх
    розв'язує обчислювач; тут лише людська проєкція назви. }
  Mechanisms: array[0..18] of TMechanism = (
    (Name: 'за-умовою';    Bits: '110'),
    (Name: 'як-є';         Bits: '001'),
    (Name: 'атом?';        Bits: '010'),
    (Name: 'тотожне?';     Bits: '101'),
    (Name: 'сполучити';    Bits: '111'),
    (Name: 'перше';        Bits: '100'),
    (Name: 'решта';        Bits: '011'),
    (Name: 'порожнє?';     Bits: '0101'),
    (Name: 'порожній?';    Bits: '0101'),
    (Name: 'друге';        Bits: '1001'),
    (Name: 'третє';        Bits: '10011'),
    (Name: 'додати';       Bits: '01010'),
    (Name: 'відняти';      Bits: '01011'),
    (Name: 'помножити';    Bits: '10110'),
    (Name: 'менше?';       Bits: '11010'),
    (Name: 'більше?';      Bits: '11011'),
    (Name: 'частка';       Bits: '10111'),
    (Name: 'остача';       Bits: '010100'),
    (Name: 'змінити-знак'; Bits: '010010'));

var
  Map: TD7Map;
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
end;

procedure SayError(const Text: RawByteString);
begin
  Writeln(StdErr, Text);
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
  if Value < 0 then Unsigned := QWord(16777216) + QWord(Value)
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

function IsMechanismBits(const Bits: RawByteString): Boolean;
var
  I: SizeInt;
begin
  for I := 0 to High(Mechanisms) do
    if Mechanisms[I].Bits = Bits then Exit(True);
  Result := False;
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
function ResolveName(const Token: RawByteString): RawByteString;
var
  I: SizeInt;
begin
  for I := 0 to High(Mechanisms) do
    if Mechanisms[I].Name = Token then Exit(Mechanisms[I].Bits);
  for I := 0 to High(NameText) do
    if NameText[I] = Token then Exit(NameBits[I]);
  raise EReplError.Create('невідоме імʼя у проєкції: ' + Token);
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
  I, Depth, Count, P: SizeInt;
  Token: RawByteString;
  Value: Int64;
  Bits: RawByteString;

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
      if Depth >= Length(Stack) then SetLength(Stack, Depth * 2);
      Push('10');
      Stack[Depth] := Count - 1;
      Inc(Depth);
    end else if Tokens[P] = ')' then begin
      if Depth = 0 then raise EReplError.Create('зайва закривна дужка');
      Push('01');
      Dec(Depth);
    end else if IsBinaryLiteral(Tokens[P]) and (Length(Tokens[P]) >= 3) then begin
      Push(RawByteString(Tokens[P]));
    end else if IsDecimalLiteral(Tokens[P], Value) then begin
      Push(Bits24(Value));
    end else begin
      Bits := ResolveName(Tokens[P]);
      { Імʼя — це ТОЧНА D7-послідовність гліфів. У фізичній формі вона
        є власним вузлом `10 <гліф> … 01`, а не одним довгим словом;
        саме так імʼя звʼязується з координатою. }
      if (Length(Bits) > 7) and (Length(Bits) mod 7 = 0) then begin
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
  if (Length(Words) >= 2) and IsMechanismBits(Words[1]) then
    raise EReplError.Create(
      'голова-механізм: виклич відповідне визначення Core1, напр. ' +
      '(ядро1-додати 2 3)');
  Answer := Selector.ExecutePhysicalCall(EncodeT5M(Words));
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
  Say(RawByteString('Допущених визначень: ') + CountText +
    RawByteString(' із 96.'));
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
      Say('        (ядро1-назви-рівні? (як-є a) (як-є a)).');
      Say('Помилка рядка не завершує сеанс — середовище лишається сталим.');
      Continue;
    end;
    try
      Say(Evaluate(Line));
    except
      on E: Exception do SayError('; помилка: ' + E.Message);
    end;
  end;
  SayError('; сеанс завершено');
end;

begin
  LoadPinnedD7Map(ParamStr(1), Map);
  Selector := TCore1Selektor.Create(ParamStr(1));
  try
    BuildNameIndex;
    Run;
  finally
    Selector.Free;
  end;
end.
