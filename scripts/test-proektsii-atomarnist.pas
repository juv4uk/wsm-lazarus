{ G2.54 — незалежний механічний свідок атомарного завантаження pinned
  шести проєкцій exact D1–D10. Назви є даними; жодного dispatch,
  числової семантики D12+ чи нового реєстру мовних законів. }
program test_proektsii_atomarnist;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.proektsii;

var
  Catalog: TProektsiiCatalog;
  Root, Mode, CaseName: String;
  D, I, Total: Integer;
  Failed: Boolean;

procedure Require(Condition: Boolean; const Explanation: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'ПРОЄКЦІЇ-АТОМАРНІСТЬ-ПОМИЛКА: ', Explanation);
    Halt(1);
  end;
end;

{ Catalog володіє 10 FPC-managed масивами. Жодна текстова проєкція
  не є машинною ідентичністю; exact-ключ перевіряється самостійно.
  Результат — лише булеві твердження host-тесту й лічильник рядків. }
procedure RequireComplete(const Explanation: String);
begin
  Total:=0;
  for D:=1 to 10 do begin
    Require(Length(Catalog[D])=(1 shl D),
      Explanation+': не всі фізичні адреси D'+IntToStr(D));
    for I:=0 to High(Catalog[D]) do begin
      Require((Catalog[D][I].Key.Width=D) and
              (Catalog[D][I].Key.Bits=I),
        Explanation+': точна координата D'+IntToStr(D)+
        ':'+IntToStr(I)+' втрачена');
      Inc(Total);
    end;
  end;
  Require(Total=2046, Explanation+': неправильна сума координат');
  Require((Catalog[1][1].Surface[0]<>'') and
          (Catalog[1][1].Surface[1]<>'') and
          (Catalog[3][1].Surface[2]='svarūpa') and
          (Catalog[3][1].Surface[3]='quote') and
          (Catalog[3][1].Surface[4]='QUOTE') and
          (Catalog[3][1].Surface[5]<>'') and
          (Catalog[7][22].Surface[4]='') and
          (Catalog[10][1023].Key.Bits=1023),
    Explanation+': шість pinned проєкцій / D7 / D10 не узгоджені');
end;

begin
  Require(ParamCount=3,
    'host protocol: ROOT 1|0 CASE-ID');
  Root:=ParamStr(1);
  Mode:=ParamStr(2);
  CaseName:=ParamStr(3);
  Require((Mode='1') or (Mode='0'),
    'host mode must be 1 or 0');

  { Валідація завжди починається зі справжнього pinned авторитету. }
  LoadPinnedProjections('external/sens',Catalog);
  RequireComplete('початковий pinned каталог');

  if Mode='1' then begin
    LoadPinnedProjections(Root,Catalog);
    RequireComplete('фізична копія pinned каталогу');
  end else begin
    Failed:=False;
    try
      { Значення out має бути атомарно очищене навіть після D1–D9,
        якщо пошкоджений останній D10 або немає файла. }
      LoadPinnedProjections(Root,Catalog);
    except on E:Exception do
      Failed:=True;
    end;
    Require(Failed,CaseName+': пошкоджений каталог прийнято');
    for D:=1 to 10 do
      Require(Length(Catalog[D])=0,
        CaseName+': частковий/старий каталог після відмови D'+IntToStr(D));
    LoadPinnedProjections('external/sens',Catalog);
    RequireComplete(CaseName+': відновлення після відмови');
  end;
  { FPC ParamStr може декодувати argv у host ANSI. Для машинного
    протоколу тільки ASCII case-id; це НЕ двійкова координата SENS. }
  WriteLn('G2-54-HARAZD case=',CaseName,
    ' rows=2046 columns=6 partial=0 recovery=1');
end.
