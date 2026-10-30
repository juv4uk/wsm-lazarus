{ Точний host-binder ратифікованих шести людських проєкцій.
  Джерело даних: тільки вже перевірений pinned TProektsiiCatalog.
  Результат — доменний ключ, а НЕ закон, викличність або виконання.
  D7 є даними; D12+ не належать цьому табличному API. }
unit wsm.bindproektsii;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.domain, wsm.proektsii;

type
  EProjectedBindError = class(Exception);

{ Колонки: 0=ук, 1=укр, 2=san, 3=en, 4=LISP, 5=sym.
  Domain=0 шукає у D1..D10; Domain=1..10 обмежує пошук.
  Навіть за успіху ключ НЕ є дозволом використовувати його в голові виклику.
  Key стає (0,0) до будь-якої відмови; немає часткового результату. }
procedure BindProjected(const Catalog: TProektsiiCatalog;
  Column, Domain: Byte; const Spelling: RawByteString;
  out Key: TDomainKey);

implementation

procedure ValidateCatalog(const Catalog: TProektsiiCatalog);
var D, I: SizeInt;
begin
  { Каталог є mutable record/array: кожне звернення захищене від
    пошкодження після першого pinned admission; це не реєстр законів. }
  for D := 1 to 10 do begin
    if Length(Catalog[D]) <> (SizeInt(1) shl D) then
      raise EProjectedBindError.CreateFmt(
        'неповна таблиця pinned D%d', [D]);
    for I := 0 to High(Catalog[D]) do
      if (Catalog[D][I].Key.Width <> D) or
         (Catalog[D][I].Key.Bits <> I) then
        raise EProjectedBindError.CreateFmt(
          'пошкоджена exact-координата D%d, рядок %d', [D,I]);
  end;
end;

procedure BindProjected(const Catalog: TProektsiiCatalog;
  Column, Domain: Byte; const Spelling: RawByteString;
  out Key: TDomainKey);
var D, I, FirstD, LastD: SizeInt;
    Candidate: TDomainKey;
    Found: Boolean;
begin
  Key.Width := 0;
  Key.Bits := 0;
  if Column > 5 then
    raise EProjectedBindError.Create('невідома колонка проєкції');
  if Domain > 10 then
    raise EProjectedBindError.Create('домен поза D1–D10');
  if Spelling = '' then
    raise EProjectedBindError.Create('відсутня людська проєкція');
  ValidateCatalog(Catalog);
  FirstD := 1;
  LastD := 10;
  if Domain <> 0 then begin
    FirstD := Domain;
    LastD := Domain;
  end;
  Found := False;
  Candidate.Width := 0;
  Candidate.Bits := 0;
  for D := FirstD to LastD do
    for I := 0 to High(Catalog[D]) do
      if Catalog[D][I].Surface[Column] = Spelling then begin
        if Found then
          raise EProjectedBindError.Create(
            'неоднозначна проєкція: потрібна точна координата');
        Candidate := Catalog[D][I].Key;
        Found := True;
      end;
  if not Found then
    raise EProjectedBindError.Create('невідома pinned проєкція');
  Key := Candidate;
end;

{ Питання до механізму:
  1. Чому один напис без домену може бути неоднозначним?
  2. Чому повернення TDomainKey не доводить викличність?
  3. Чому D7/LISP=() не може утворити ключ із порожнього напису?
  4. Чому пошкоджену таблицю перевіряємо перед публікацією Key? }
end.
