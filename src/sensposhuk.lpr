{ G2.42: зворотний пошук ТІЛЬКИ за шістьма pinned проєкціями.
  Точна машинна ідентичність лишається (домен, ширина, біти, закон).
  Знайдене написання не надає викличності; D7 — тільки текстові дані. }
program sensposhuk;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii;

const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
var
  Catalog: TProektsiiCatalog;
  Lines: TStringList;
  Name, Surface, DomainArg: RawByteString;
  Column, D, FirstDomain, LastDomain, I, J: Integer;
  FoundColumn: Boolean;

{ D1..D10 — лише явний host-фільтр. D12+ належать окремій числовій
  площині й не можуть потрапити сюди за збігом бітів або написання. }
function ReadDomainFilter(const S: RawByteString): Integer;
var P: SizeInt;
begin
  if (Length(S)<2) or (Length(S)>3) or (S[1]<>'D') or
     (S[2]='0') then
    raise EProektsiiError.Create('потрібен точний домен D1..D10');
  for P:=2 to Length(S) do
    if not (S[P] in ['0'..'9']) then
      raise EProektsiiError.Create('домен не є канонічним D1..D10');
  Result:=StrToInt(Copy(S,2,Length(S)-1));
  if (Result<1) or (Result>10) then
    raise EProektsiiError.Create('D12+ не є функційною проєкцією D1..D10');
end;

begin
  Lines:=nil;
  try
    if (ParamCount<>3) and (ParamCount<>4) then
      raise EProektsiiError.Create(
        'використання: sensposhuk PINNED_ROOT ук|укр|san|en|LISP|sym ТОЧНИЙ_ТЕКСТ [D1..D10]');
    Surface:=RawByteString(ParamStr(2));
    Name:=RawByteString(ParamStr(3));
    if (Name='') or (Name='()') then
      raise EProektsiiError.Create('порожня проєкція () не є написанням');
    FoundColumn:=False;
    Column:=-1;
    for I:=0 to High(Labels) do
      if Labels[I]=Surface then begin
        FoundColumn:=True;
        Column:=I;
        Break;
      end;
    if not FoundColumn then
      raise EProektsiiError.Create('невідома проєкція');
    FirstDomain:=1;
    LastDomain:=10;
    if ParamCount=4 then begin
      DomainArg:=RawByteString(ParamStr(4));
      FirstDomain:=ReadDomainFilter(DomainArg);
      LastDomain:=FirstDomain;
    end;

    { Атомарний pinned допуск усіх 2046 координат до першого stdout.
      Catalog — FPC-managed масиви шести UTF-8 поверхонь; немає
      додаткового текстового reader, інтерпретатора чи реєстру законів. }
    LoadPinnedProjections(ParamStr(1),Catalog);
    Lines:=TStringList.Create;
    for D:=FirstDomain to LastDomain do
      for J:=0 to High(Catalog[D]) do
        if Catalog[D][J].Surface[Column]=Name then
          Lines.Add('координата: D'+IntToStr(D)+':'+
            String(KeyBits(Catalog[D][J].Key)));
    if Lines.Count=0 then
      raise EProektsiiError.Create(
        'точне написання відсутнє у вибраній pinned проєкції');
    { Лише після повного пошуку оприлюднюємо ВСІ збіги, у
      фізичному порядку доменів та точних бітових слів.
      Жодна неоднозначність не є приводом обрати перший збіг. }
    for I:=0 to Lines.Count-1 do WriteLn(Lines[I]);
    WriteLn('збігів=',Lines.Count,' викличність=не-перевірено');
  except
    on E:Exception do begin
      WriteLn(ErrOutput, 'ПОШУК-ПРОЄКЦІЙ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
  Lines.Free;
end.
