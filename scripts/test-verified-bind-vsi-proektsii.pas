{ G2.55 — повний byte-exact механічний свідок шести pinned проєкцій.
  D1–D10 тут є точними координатами, а не правилами виклику.
  Вхід — immutable на час тесту TProektsiiCatalog із pinned SENS;
  вихід — лічильники host-тесту, не значення SENS і не D12. }
program test_verified_bind_vsi_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}

uses SysUtils, wsm.domain, wsm.proektsii, wsm.bindproektsii;

var
  Catalog: TProektsiiCatalog;
  Key: TDomainKey;
  Domain, Column, Row, Other, Duplicates: SizeInt;
  TotalRows, NonEmpty, UniqueNames, Collisions, EmptyNames: SizeInt;
  ColumnCount: array[0..5] of SizeInt;
  Spelling: RawByteString;
  Rejected: Boolean;

procedure Demand(Condition: Boolean; const Problem: String);
begin
  if not Condition then
    raise Exception.Create('G2.55: ' + Problem);
end;

procedure CheckBlank(const Data: TProektsiiCatalog;
  ColumnIndex, DomainIndex: Byte);
var
  Candidate: TDomainKey;
  Failed: Boolean;
begin
  Candidate.Width := 99;
  Candidate.Bits := 999;
  Failed := False;
  try
    BindProjected(Data, ColumnIndex, DomainIndex, '', Candidate);
  except
    on E: EProjectedBindError do Failed := True;
  end;
  Demand(Failed, 'порожня проєкція отримала координату');
  Demand((Candidate.Width = 0) and (Candidate.Bits = 0),
    'відмова залишила попередній ключ');
end;

begin
  TotalRows := 0;
  NonEmpty := 0;
  UniqueNames := 0;
  Collisions := 0;
  EmptyNames := 0;
  for Column := 0 to 5 do ColumnCount[Column] := 0;
  try
    Demand(ParamCount = 1, 'потрібний шлях до pinned SENS');
    LoadPinnedProjections(ParamStr(1), Catalog);
    for Domain := 1 to 10 do begin
      Demand(Length(Catalog[Domain]) = (SizeInt(1) shl Domain),
        'неповна таблиця D' + IntToStr(Domain));
      for Row := 0 to High(Catalog[Domain]) do begin
        Inc(TotalRows);
        Demand((Catalog[Domain][Row].Key.Width = Domain) and
          (Catalog[Domain][Row].Key.Bits = Row),
          'втрата ширини чи провідних нулів D' + IntToStr(Domain) +
          ' рядок ' + IntToStr(Row));
        for Column := 0 to 5 do begin
          Spelling := Catalog[Domain][Row].Surface[Column];
          if Spelling = '' then begin
            Inc(EmptyNames);
            Continue;
          end;
          Inc(NonEmpty);
          Inc(ColumnCount[Column]);
          { Підрахунок byte-exact збігів тільки в тому самому домені.
            Не прирівнюємо Unicode-нормалізацію до ідентичності SENS. }
          Duplicates := 0;
          for Other := 0 to High(Catalog[Domain]) do
            if Catalog[Domain][Other].Surface[Column] = Spelling then
              Inc(Duplicates);
          Demand(Duplicates > 0, 'відсутній власний рядок');
          Key.Width := 99;
          Key.Bits := 999;
          Rejected := False;
          try
            BindProjected(Catalog, Byte(Column), Byte(Domain),
              Spelling, Key);
          except
            on E: EProjectedBindError do Rejected := True;
          end;
          if Duplicates = 1 then begin
            Demand(not Rejected, 'унікальну pinned проєкцію відхилено');
            Demand((Key.Width = Domain) and (Key.Bits = Row),
              'спотворено домен або exact біти pinned проєкції');
            Inc(UniqueNames);
          end else begin
            Demand(Rejected, 'неоднозначній проєкції надано координату');
            Demand((Key.Width = 0) and (Key.Bits = 0),
              'відмова лишила частковий exact ключ');
            Inc(Collisions);
          end;
        end;
      end;
      { Навіть у домені з непорожніми іменами немає неявної
        координати для () / відсутньої проєкції. }
      for Column := 0 to 5 do
        CheckBlank(Catalog, Byte(Column), Byte(Domain));
    end;
    Demand(TotalRows = 2046, 'очікувалося 2046 pinned координат D1–D10');
    Demand(NonEmpty + EmptyNames = TotalRows * 6,
      'утрачено колонку або рядок pinned каталогу');
    Demand((NonEmpty > 0) and (UniqueNames > 0),
      'не виконано жодної позитивної exact прив’язки');
    for Column := 0 to 5 do
      Demand(ColumnCount[Column] > 0, 'порожня ціла колонка №' +
        IntToStr(Column));

    WriteLn('G2-55-BIND-PASS rows=',TotalRows,
      ' columns=6 nonempty=',NonEmpty,
      ' unique=',UniqueNames,' ambiguous=',Collisions,
      ' empty=',EmptyNames,' blank-rejections=60');
  except
    on E: Exception do begin
      WriteLn(ErrOutput,'ПРОЄКЦІЇ-ВСІ-ПОМИЛКА: ',E.Message);
      Halt(1);
    end;
  end;
end.

{ Життєвий цикл: Catalog має owned масиви RawByteString, які автоматично
  звільняє runtime; Key — локальне значення без алокації. Лічильники —
  тільки host-результат. Це не semantic oracle і не виконання D12+.
  Питання: 1) Чому збіги шукаються в межах одного D?
  2) Чому два однакові байтові написи не мають отримати перший ключ?
  3) Чому порожній рядок не є координатою D1:0?
  4) Чому успішний BindProjected не дозволяє виклик функції? }
