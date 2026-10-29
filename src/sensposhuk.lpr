{ G2.42: зворотний пошук ТІЛЬКИ за шістьма pinned проєкціями.
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
var
  Catalog: TProektsiiCatalog;
  Hits: THits;
  Name, Surface, DomainArg: RawByteString;
  Column, D, FirstDomain, LastDomain, I, J: Integer;
  HitCount: SizeInt;
  FoundColumn: Boolean;

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

begin
  HitCount:=0;
  SetLength(Hits,0);
  try
    if (ParamCount<>3) and (ParamCount<>4) then
      raise EProektsiiError.Create(String(Uk(
        'використання: sensposhuk PINNED_ROOT ук|укр|san|en|LISP|sym ТОЧНИЙ_ТЕКСТ [D1..D10]')));
    Surface:=RawByteString(ParamStr(2));
    Name:=RawByteString(ParamStr(3));
    if (Name='') or (Name='()') then
      raise EProektsiiError.Create(String(Uk(
        'порожня проєкція () не є написанням')));
    FoundColumn:=False;
    Column:=-1;
    for I:=0 to High(Labels) do
      if Labels[I]=Surface then begin
        FoundColumn:=True;
        Column:=I;
        Break;
      end;
    if not FoundColumn then
      raise EProektsiiError.Create(String(Uk('невідома проєкція')));
    FirstDomain:=1;
    LastDomain:=10;
    if ParamCount=4 then begin
      DomainArg:=RawByteString(ParamStr(4));
      FirstDomain:=ReadDomainFilter(DomainArg);
      LastDomain:=FirstDomain;
    end;

    { Атомарний pinned допуск до stdout. Catalog — FPC-managed шість
      UTF-8 текстових полів на точну координату. Власних законів немає. }
    LoadPinnedProjections(ParamStr(1),Catalog);
    for D:=FirstDomain to LastDomain do
      for J:=0 to High(Catalog[D]) do
        if Catalog[D][J].Surface[Column]=Name then begin
          SetLength(Hits,HitCount+1);
          Hits[HitCount]:=Uk('координата: D')+RawByteString(IntToStr(D))+
            ':'+KeyBits(Catalog[D][J].Key);
          Inc(HitCount);
        end;
    if HitCount=0 then
      raise EProektsiiError.Create(String(Uk(
        'точне написання відсутнє у вибраній pinned проєкції')));

    { Тільки після завершення пошуку показуємо ВСІ збіги. THits є
      локальним FPC-managed масивом UTF-8 байтів, без конвертації в
      host ANSI TStrings; час життя — один виклик процесу. }
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
