{ G2.42/G2.44: зворотний пошук і перетин pinned людських проєкцій.
  Машинна ідентичність — (домен, ширина, біти, закон), не написання.
  D7 — текстові дані, а не каталог викличних функцій. }
program sensposhuk;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.proektsii;

const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
type
  THits = array of RawByteString;
  TQuery = record
    Column: Integer;
    Name: RawByteString;
  end;
var
  Catalog: TProektsiiCatalog;
  Hits: THits;
  Queries: array[0..1] of TQuery;
  DomainArg: RawByteString;
  D, FirstDomain, LastDomain, I, J, K, QueryCount: Integer;
  HitCount: SizeInt;
  IntersectMode, Fits: Boolean;

{ Host UTF-8 лише для проєкцій та діагностики; нічого не кодує у D7.
  RawByteString зберігає байти: TStrings/неявна ANSI-конверсія тут
  заборонені, інакше FPC у C locale друкує '?' замість літер. }
function Uk(const S: UnicodeString): RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

{ D1..D10 — явний host-фільтр. Числову площину D12+ він не охоплює. }
function ReadDomainFilter(const S: RawByteString): Integer;
var P: SizeInt;
begin
  if (Length(S)<2) or (Length(S)>3) or (S[1]<>'D') or
     (S[2]='0') then
    raise EProektsiiError.Create(String(Uk('потрібен точний домен D1..D10')));
  for P:=2 to Length(S) do
    if not (S[P] in ['0'..'9']) then
      raise EProektsiiError.Create(String(Uk('домен не є канонічним D1..D10')));
  Result:=StrToInt(Copy(S,2,Length(S)-1));
  if (Result<1) or (Result>10) then
    raise EProektsiiError.Create(
      String(Uk('D12+ не є функційною проєкцією D1..D10')));
end;

{ Шість допустимих колонок походять з pinned SENS. Номер є лише
  host-адресою у вже перевіреному TProektsiiCatalog, не opcode. }
function ReadColumn(const S: RawByteString): Integer;
var N: Integer;
begin
  for N:=0 to High(Labels) do
    if Labels[N]=S then Exit(N);
  raise EProektsiiError.Create(String(Uk('невідома проєкція')));
end;

{ Один запит зберігає колонку та byte-exact UTF-8 назву. Послідовність
  цитованих знаків D7 (напр. "'") не перетворюємо на синтаксис.
  Значення () означає відсутність проєкції, а не текст для пошуку. }
procedure SetQuery(var Q: TQuery; const Surface, Name: RawByteString);
begin
  Q.Column:=ReadColumn(Surface);
  if (Name='') or (Name='()') then
    raise EProektsiiError.Create(String(Uk(
      'порожня проєкція () не є написанням')));
  Q.Name:=Name;
end;

begin
  HitCount:=0;
  SetLength(Hits,0);
  try
    IntersectMode:=(ParamCount>=2) and
      (RawByteString(ParamStr(2))=Uk('--перетин'));
    if IntersectMode then begin
      if (ParamCount<>6) and (ParamCount<>7) then
        raise EProektsiiError.Create(String(Uk(
          'використання: sensposhuk PINNED_ROOT --перетин ПОВЕРХНЯ1 ТЕКСТ1 ПОВЕРХНЯ2 ТЕКСТ2 [D1..D10]')));
      QueryCount:=2;
      SetQuery(Queries[0],RawByteString(ParamStr(3)),
        RawByteString(ParamStr(4)));
      SetQuery(Queries[1],RawByteString(ParamStr(5)),
        RawByteString(ParamStr(6)));
    end else begin
      if (ParamCount<>3) and (ParamCount<>4) then
        raise EProektsiiError.Create(String(Uk(
          'використання: sensposhuk PINNED_ROOT ук|укр|san|en|LISP|sym ТОЧНИЙ_ТЕКСТ [D1..D10]')));
      QueryCount:=1;
      SetQuery(Queries[0],RawByteString(ParamStr(2)),
        RawByteString(ParamStr(3)));
    end;
    FirstDomain:=1;
    LastDomain:=10;
    if (IntersectMode and (ParamCount=7)) or
       ((not IntersectMode) and (ParamCount=4)) then begin
      DomainArg:=RawByteString(ParamStr(ParamCount));
      FirstDomain:=ReadDomainFilter(DomainArg);
      LastDomain:=FirstDomain;
    end;

    { Атомарний pinned допуск до stdout. Catalog — FPC-managed шість
      UTF-8 текстових полів на точну координату. Власних законів немає.
      Перетин двох колонок перевіряємо на ОДНОМУ exact рядку,
      а не за рівністю текстів, нормалізацією чи порядком збігів. }
    LoadPinnedProjections(ParamStr(1),Catalog);
    for D:=FirstDomain to LastDomain do
      for J:=0 to High(Catalog[D]) do begin
        Fits:=True;
        for K:=0 to QueryCount-1 do
          if Catalog[D][J].Surface[Queries[K].Column]<>Queries[K].Name then begin
            Fits:=False;
            Break;
          end;
        if Fits then begin
          SetLength(Hits,HitCount+1);
          Hits[HitCount]:=Uk('координата: D')+RawByteString(IntToStr(D))+
            ':'+KeyBits(Catalog[D][J].Key);
          Inc(HitCount);
        end;
      end;
    if HitCount=0 then
      raise EProektsiiError.Create(String(Uk(
        'точне написання відсутнє у вибраній pinned проєкції або їх перетині')));

    { Тільки після повного проходу показуємо ВСІ збіги. THits є
      локальним FPC-managed масивом UTF-8 байтів, без host ANSI TStrings;
      кожне значення містить точну фізичну ширину й провідні нулі. }
    for I:=0 to HitCount-1 do WriteLn(Hits[I]);
    WriteLn(Uk('збігів='),HitCount,Uk(' викличність=не-перевірено'));
  except
    on E:Exception do begin
      WriteLn(ErrOutput, Uk('ПОШУК-ПРОЄКЦІЙ-ПОМИЛКА: '),
        RawByteString(E.Message));
      ExitCode:=2;
    end;
  end;
end.
