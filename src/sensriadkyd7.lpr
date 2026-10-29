{ G1.46 — лінійний обмін pinned D7 surface-токенів і фізичного T5M.
  Вхідні рядки .txt — ДАНІ, а НЕ виконуване джерело .lisp.
  Домен визначений явно як D7; кожний токен шукається лише у
  завантажених шести колонках juv4uk/sens, без англійського dispatch. }
program sensriadkyd7;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.domain, wsm.proektsii;

const
  MaxInputBytes = 65536;
  MaxD7Words = 8192;
  Projections: array[0..5] of RawByteString =
    ('ук','укр','san','en','LISP','sym');
  { ParamStr повертає host-байти, а Pascal String може мати system
    codepage. Порівнюємо ЛИШЕ точний UTF-8 байтовий запис параметра. }
  ModePack:RawByteString='--'+#$D0+#$BF+#$D0+#$B0+#$D0+#$BA+#$D1+#$83+
    #$D0+#$B2+#$D0+#$B0+#$D1+#$82+#$D0+#$B8;
  ModeExpand:RawByteString='--'+#$D1+#$80+#$D0+#$BE+#$D0+#$B7+#$D0+#$B3+
    #$D0+#$BE+#$D1+#$80+#$D0+#$BD+#$D1+#$83+#$D1+#$82+#$D0+#$B8;
type
  ED7LinesError = class(Exception);

{ Path — позичена host-адреса; Result — власний managed byte buffer.
  Перевірка межі до виділення пам'яті. Жодних мовних чисел D12+. }
function ReadBounded(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxInputBytes) then
      raise ED7LinesError.Create('Файл порожній або більший за 65536 байтів');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Лише 6 затверджених назв колонок pinned каталогу.
  Номер колонки — host-індекс, не SENS opcode. }
function ColumnOf(const S:RawByteString):Integer;
var I:Integer;
begin
  for I:=0 to 5 do
    if Projections[I]=S then Exit(I);
  raise ED7LinesError.Create('Невідома колонка проєкції');
end;

{ Один surface-токен може мати кілька Unicode scalar і може бути
  цитованим, тому НІЯКОГО split за символами, trim або нормалізації.
  Колізія написання ніколи не вибирає довільний код D7. }
function ExactD7(const Token:RawByteString;Column:Integer;
  const Catalog:TProektsiiCatalog):RawByteString;
var I,Found:SizeInt;
begin
  if (Token='') or (Token='()') then
    raise ED7LinesError.Create('Порожній surface-токен заборонений');
  Found:=-1;
  for I:=0 to High(Catalog[7]) do
    if (Catalog[7][I].Surface[Column]<>'') and
       (Catalog[7][I].Surface[Column]=Token) then begin
      if Found>=0 then
        raise ED7LinesError.Create('Неоднозначна pinned D7 проєкція');
      Found:=I;
    end;
  if Found<0 then
    raise ED7LinesError.Create('Немає точного pinned D7 написання');
  Result:=KeyBits(Catalog[7][Found].Key);
  if Length(Result)<>7 then
    raise ED7LinesError.Create('Зіпсована ширина pinned D7');
end;

{ Source — повний UTF-8 byte stream з одним pinned surface-токеном
  у рядку й обов'язковим LF. Words — managed масив точних W7, який
  публікується лише після цілого розбору. Не створює .lisp програму. }
function PackLines(const Source:RawByteString;Column:Integer;
  const Catalog:TProektsiiCatalog):RawByteString;
var Words:TExactWords; I,Start,N:SizeInt;Token:RawByteString;
begin
  if (Source='') or (Source[Length(Source)]<>#10) then
    raise ED7LinesError.Create('Потрібен завершальний LF');
  SetLength(Words,0);
  Start:=1;
  N:=0;
  for I:=1 to Length(Source) do begin
    if (Source[I]=#0) or (Source[I]=#13) then
      raise ED7LinesError.Create('NUL та CR заборонені в токенах D7');
    if Source[I]=#10 then begin
      if (I=Start) then
        raise ED7LinesError.Create('Порожній рядок D7 заборонений');
      if N>=MaxD7Words then
        raise ED7LinesError.Create('Понад 8192 D7 токенів');
      Token:=Copy(Source,Start,I-Start);
      SetLength(Words,N+1);
      Words[N]:=ExactD7(Token,Column,Catalog);
      Inc(N);
      Start:=I+1;
    end;
  end;
  if (N=0) then raise ED7LinesError.Create('Немає жодного D7 слова');
  Result:=EncodeT5M(Words); { чинний канонічний фізичний кодек }
end;

{ Фізичний canonical stream декодується ПОВНІСТЮ до повернення даних.
  Вихід — лише UTF-8 pinned токени з LF, без викличності й D12+.
  Навіть один пізній недрукований D7 не публікує часткового stdout. }
function UnpackLines(const Physical:RawByteString;Column:Integer;
  const Catalog:TProektsiiCatalog):RawByteString;
var Words:TExactWords;I,J,Index:SizeInt;Token:RawByteString;
begin
  Result:='';
  DecodeT5M(Physical,Words);
  if (Length(Words)<1) or (Length(Words)>MaxD7Words) then
    raise ED7LinesError.Create('Кількість фізичних D7 слів поза межею');
  if EncodeT5M(Words)<>Physical then
    raise ED7LinesError.Create('Неканонічний фізичний T5M');
  for I:=0 to High(Words) do begin
    if Length(Words[I])<>7 then
      raise ED7LinesError.Create('Фізичне слово не належить D7');
    Index:=0;
    for J:=1 to 7 do begin
      if not (Words[I][J] in ['0','1']) then
        raise ED7LinesError.Create('Недвійковий D7 ключ');
      Index:=(Index shl 1)+Ord(Words[I][J])-Ord('0');
    end;
    if not SameKey(Catalog[7][Index].Key,ExactKey(Words[I])) then
      raise ED7LinesError.Create('Невідповідність exact D7 координати');
    Token:=Catalog[7][Index].Surface[Column];
    if Token='' then
      raise ED7LinesError.Create('Ця D7 координата не має проєкції');
    { Для round-trip неможна експортувати неоднозначні назви.
      Повторний пошук перевіряє усі 128 pinned D7 рядків. }
    if ExactD7(Token,Column,Catalog)<>Words[I] then
      raise ED7LinesError.Create('Втрата точної D7 тотожності');
    if Length(Result)+Length(Token)+1>MaxInputBytes then
      raise ED7LinesError.Create('Текстова проєкція завелика');
    Result:=Result+Token+#10;
  end;
end;

{ Ніякого stdout до повної перевірки pinned каталогу, файла та
  фізичної або текстової цілісності. Потік — owned bytes, Writer
  звільняється тут, не залишається стану чи напіврезультату. }
procedure WriteBytes(const Bytes:RawByteString);
var W:THandleStream;
begin
  if Bytes='' then Exit;
  W:=THandleStream.Create(TextRec(Output).Handle);
  try W.WriteBuffer(Bytes[1],Length(Bytes));
  finally W.Free end;
end;

{ Діагностика, як і фізичний stdout, не повинна міняти UTF-8 через
  system Ansi codepage Free Pascal у CI. ErrOutput — окремий borrowed fd.
  Власний RawByteString звільняється після повного запису. }
procedure WriteError(const MessageText:String);
var W:THandleStream;Utf8:RawByteString;
begin
  Utf8:=RawByteString(UTF8Encode(UnicodeString('РЯДКИ-Д7-ВІДМОВА: ')))+
    RawByteString(UTF8Encode(UnicodeString(MessageText)))+#10;
  W:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try W.WriteBuffer(Utf8[1],Length(Utf8));
  finally W.Free end;
end;

var
  Mode,ColumnName:RawByteString;
  Path:String;
  Column:Integer;
  Catalog:TProektsiiCatalog;
  Data,Answer:RawByteString;
begin
  try
    if ParamCount<>4 then
      raise ED7LinesError.Create(
        'Використання: sensriadkyd7 PINNED_ROOT --пакувати|--розгорнути ук|укр|san|en|LISP|sym файл.txt|файл.sens');
    Mode:=RawByteString(ParamStr(2));
    ColumnName:=RawByteString(ParamStr(3));Path:=ParamStr(4);
    if (Mode<>ModePack) and (Mode<>ModeExpand) then
      raise ED7LinesError.Create('Невідома операція D7');
    Column:=ColumnOf(ColumnName);
    if (Mode=ModePack) and (LowerCase(ExtractFileExt(Path))<>'.txt') then
      raise ED7LinesError.Create('Токени проєкції треба подавати як .txt, не .lisp');
    if (Mode=ModeExpand) and (LowerCase(ExtractFileExt(Path))<>'.sens') then
      raise ED7LinesError.Create('Тільки фізичний .sens у зворотному напрямі');
    LoadPinnedProjections(ParamStr(1),Catalog);
    Data:=ReadBounded(Path);
    if Mode=ModePack then Answer:=PackLines(Data,Column,Catalog)
    else Answer:=UnpackLines(Data,Column,Catalog);
    WriteBytes(Answer);
  except
    on E:Exception do begin
      WriteError(E.Message);
      ExitCode:=2;
    end;
  end;
end.
