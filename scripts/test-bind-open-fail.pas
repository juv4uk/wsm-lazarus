{ G2.58 — checked FPC перевірка адресної відмови при відсутності
  фізичної pinned таблиці. Жодних власних координат/законів SENS.
  Параметри: (1) пошкоджена копія authority; (2) справжній pin;
  (3) номер відсутнього домену. Результат — ASCII машинний маркер.
  Масив TDomainSet належить одному процесу; його керовані рядки та
  таблиці звільняє FPC, після винятку не можна лишати старий snapshot.
  Питання:
  1) Чому D7 в діагностиці є доменом, а не Unicode-кодуванням?
  2) Чому перевіряємо всі десять масивів після пізньої помилки?
  3) Чому спершу завантажуємо чинний authority у той самий out?
  4) Чому recovery після відмови не є дозволом на нову семантику? }
program test_bind_open_fail;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.bind;

procedure Demand(Condition: Boolean; const Problem: String);
begin
  if not Condition then
    raise Exception.Create('G2-58-ПРОВАЛ: '+Problem);
end;

var
  Tables: TDomainSet;
  D, Missing: Integer;
  Caught: Boolean;
  BrokenRoot, PinnedRoot, Expected: RawByteString;
begin
  Demand(ParamCount=3,'потрібні копія, pin, номер Dn');
  BrokenRoot:=RawByteString(ParamStr(1));
  PinnedRoot:=RawByteString(ParamStr(2));
  Missing:=StrToInt(ParamStr(3));
  Demand((Missing>=FirstDomain) and (Missing<=LastDomain),
    'неприпустимий номер домену');
  Demand(not FileExists(String(BrokenRoot)+'/lib/domains/d'+
    IntToStr(Missing)+'.lisp'),'негативна таблиця досі існує');

  { Спочатку справжній набір: перевіряємо, що негатив очистить
    раніше опубліковані дані, а не лише порожній первісний стан. }
  LoadPinnedDomains(PinnedRoot,Tables);
  for D:=FirstDomain to LastDomain do
    Demand(Length(Tables[D])=(SizeInt(1) shl D),
      'пошкоджений початковий pinned набір');

  Caught:=False;
  Expected:='pinned D'+RawByteString(IntToStr(Missing))+':';
  try
    LoadPinnedDomains(BrokenRoot,Tables);
  except
    on E:EBindError do begin
      Caught:=True;
      Demand(Pos(String(Expected),E.Message)=1,
        'втрачені тип EBindError або адреса потрібного Dn');
      Demand(Pos('не вдалося відкрити таблицю:',E.Message)>0,
        'втрачена I/O причина');
    end;
  end;
  Demand(Caught,'відсутню таблицю було допущено');
  for D:=FirstDomain to LastDomain do
    Demand(Length(Tables[D])=0,
      'після відмови опубліковано старий або частковий домен');

  LoadPinnedDomains(PinnedRoot,Tables);
  for D:=FirstDomain to LastDomain do
    Demand(Length(Tables[D])=(SizeInt(1) shl D),
      'повторний pinned допуск не відновився');
  WriteLn('G2-58-BIND-MISSING-PASS domain=',Missing,
    ' partial=none recovery=all-10');
end.
