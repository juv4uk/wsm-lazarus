{ G2.53. Незалежна механічна перевірка шести pinned проєкцій.
  Це НЕ SENS evaluator, не oracle семантики й не реєстр законів. }
program test_bindproektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.proektsii, wsm.bindproektsii;

var
  Catalog, Bad: TProektsiiCatalog;
  Key: TDomainKey;
  Col, D, I, Checks: SizeInt;

procedure Check(OK: Boolean; const Description: String);
begin
  if not OK then
    raise Exception.Create('ПЕРЕВІРКА-ПРОВАЛ: ' + Description);
  Inc(Checks);
end;

procedure CloneCatalog(const Source: TProektsiiCatalog;
  out Target: TProektsiiCatalog);
var Domain, Row: SizeInt;
begin
  for Domain := 1 to 10 do begin
    SetLength(Target[Domain], Length(Source[Domain]));
    for Row := 0 to High(Source[Domain]) do
      Target[Domain][Row] := Source[Domain][Row];
  end;
end;

procedure ExpectRejected(const Data: TProektsiiCatalog;
  Column, Domain: Byte; const Spelling: RawByteString);
var
  Actual: TDomainKey;
  Rejected: Boolean;
begin
  Actual.Width := 99;
  Actual.Bits := 99;
  Rejected := False;
  try
    BindProjected(Data, Column, Domain, Spelling, Actual);
  except
    on E: EProjectedBindError do Rejected := True;
  end;
  Check(Rejected, 'потрібна явна відмова');
  Check((Actual.Width = 0) and (Actual.Bits = 0),
    'після відмови не можна публікувати ключ');
end;

begin
  Checks := 0;
  try
    Check(ParamCount = 1, 'очікується корінь pinned SENS');
    LoadPinnedProjections(ParamStr(1), Catalog);
    { Шість окремих колонок того самого ратифікованого D3:001.
      Значення тексту не використовується як dispatch або закон. }
    for Col := 0 to 5 do begin
      Check(Catalog[3][1].Surface[Col] <> '',
        'D3:001 повинен мати всі шість людських проєкцій');
      BindProjected(Catalog, Col, 3, Catalog[3][1].Surface[Col], Key);
      Check((Key.Width = 3) and (Key.Bits = 1),
        'потрібен exact D3:001 для кожної колонки');
    end;
    { Друкована D7-координата є лише текстовими даними. }
    Check(Catalog[7][65].Surface[1] <> '', 'потрібна укр D7 літера');
    BindProjected(Catalog, 1, 7, Catalog[7][65].Surface[1], Key);
    Check((Key.Width = 7) and (Key.Bits = 65),
      'D7 має залишитися W7, не D12 і не D3');
    ExpectRejected(Catalog, 4, 7, 'QUOTE');
    ExpectRejected(Catalog, 1, 7, '');
    ExpectRejected(Catalog, 1, 12, 'число');
    ExpectRejected(Catalog, 6, 3, 'як-є');
    ExpectRejected(Catalog, 1, 3, 'ніколи-не-існує-такої-проєкції');

    { Колізія двох рядків ОДНОГО домену мусить відмовляти. }
    CloneCatalog(Catalog, Bad);
    Bad[3][2].Surface[1] := Bad[3][1].Surface[1];
    ExpectRejected(Bad, 1, 3, Bad[3][1].Surface[1]);

    { Колізія МІЖ доменами: без домену відмова, із ним — два
      РІЗНІ exact-ключі. Їхня викличність ніде не припускається. }
    CloneCatalog(Catalog, Bad);
    Bad[4][0].Surface[1] := Bad[3][1].Surface[1];
    ExpectRejected(Bad, 1, 0, Bad[3][1].Surface[1]);
    BindProjected(Bad, 1, 3, Bad[3][1].Surface[1], Key);
    Check((Key.Width = 3) and (Key.Bits = 1), 'домен D3 збережено');
    BindProjected(Bad, 1, 4, Bad[3][1].Surface[1], Key);
    Check((Key.Width = 4) and (Key.Bits = 0), 'домен D4 збережено');

    { Пізнє пошкодження таблиці, не просто відсутня поверхня. }
    CloneCatalog(Catalog, Bad);
    Bad[10][1023].Key.Width := 7;
    ExpectRejected(Bad, 1, 3, Catalog[3][1].Surface[1]);
    CloneCatalog(Catalog, Bad);
    SetLength(Bad[10], 0);
    ExpectRejected(Bad, 1, 3, Catalog[3][1].Surface[1]);

    WriteLn('ПРОЄКЦІЇ-ПРИВ’ЯЗКА-PASS перевірок=',Checks);
  except
    on E: Exception do begin
      WriteLn(ErrOutput, 'ПРОЄКЦІЇ-ПРИВ’ЯЗКА-FAIL: ',E.Message);
      Halt(2);
    end;
  end;
end.
