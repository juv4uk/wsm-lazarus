program test_bindindex;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.bind, wsm.bindindex;
var Tables: TDomainSet; Index: TBindIndex; K, K2: TDomainKey;
    D, I, Count: Integer; Raised: Boolean;
procedure Check(Ok: Boolean; const MessageText: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'BINDINDEX-FAIL ', MessageText);
    Halt(1);
  end;
end;
begin
  LoadPinnedDomains('external/sens', Tables);
  BuildBindIndex(Tables, Index);
  Count := 0;
  for D := FirstDomain to LastDomain do
    for I := 0 to High(Tables[D]) do begin
      if Tables[D][I].Ukrainian = '' then Continue;
      K := IndexedUkrainian(Index, Tables[D][I].Ukrainian);
      K2 := BindUkrainian(Tables, Tables[D][I].Ukrainian);
      Check(SameKey(K, K2), 'indexed and linear binders disagree');
      Check(SameKey(K, Tables[D][I].Key), 'indexed coordinate mismatch');
      K2 := IndexedUkrainianInDomain(Index, Tables[D][I].Ukrainian, D);
      Check(SameKey(K, K2), 'scoped index coordinate mismatch');
      Inc(Count);
    end;
  Check(Index.Count = Count, 'index lost or duplicated a surface');
  Check(Count > 1000, 'pinned source unexpectedly empty');
  Raised := False;
  try K := IndexedUkrainian(Index, 'quote');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'unrecognized English spelling accepted');
  Raised := False;
  try K := IndexedUkrainian(Index, '');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'empty name accepted');
  Raised := False;
  try K := IndexedUkrainian(Index, 'ТаК');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'byte-exact case check missing');
  Raised := False;
  try K := IndexedUkrainianInDomain(Index, 'так', 3);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'wrong-domain lookup accepted');
  Raised := False;
  try K := IndexedUkrainianInDomain(Index, 'так', 0);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'invalid domain accepted');
  { A built index must remain stable if a caller later edits the source tables. }
  Tables[1][0].Ukrainian := 'за-умовою';
  K := IndexedUkrainian(Index, 'за-умовою');
  Check(SameKey(K, ExactKey('110')), 'snapshot changed after input mutation');
  Raised := False;
  try BuildBindIndex(Tables, Index);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'duplicate Ukrainian surface did not fail closed');
  { Пізній дубль не має залишати вже вставлених координат зовні.
    Старий код у цей момент лишав часткову таблицю — RED регресія. }
  Check((Index.Count=0) and (Length(Index.Slots)=0),
    'partial bind index escaped after duplicate rejection');
  Raised:=False;
  try K:=IndexedUkrainian(Index,'ні');
  except on E:EBindError do Raised:=True; end;
  Check(Raised,'untrusted partial index still admits Ukrainian coordinate');

  { Повторний допуск після відмови не повинен вимагати нового процесу. }
  Tables[1][0].Ukrainian:='ні';
  BuildBindIndex(Tables,Index);
  Check(Index.Count=Count,'valid pinned index did not recover');
  K:=IndexedUkrainian(Index,'так');
  Check(SameKey(K,ExactKey('1')),'recovered exact D1 coordinate lost');

  { Другий дубль припадає на останній слот D10; попередні D1–D9
    не можуть витекти назовні навіть після майже повного сканування. }
  Tables[10][1023].Ukrainian:='так';
  Raised:=False;
  try BuildBindIndex(Tables,Index);
  except on E:EBindError do Raised:=True; end;
  Check(Raised,'late D10 duplicate accepted');
  Check((Index.Count=0) and (Length(Index.Slots)=0),
    'late D10 failure leaked partial table');

  { Перед наступною перевіркою відновлюємо таблиці з pinned файлів,
    щоб не вгадувати початковий Unicode token останнього рядка D10. }
  LoadPinnedDomains('external/sens',Tables);
  BuildBindIndex(Tables,Index);
  Check(Index.Count=Count,'pinned index did not rebuild after late failure');

  { Пошкоджений порядок exact D10 перевіряється перед першою публікацією. }
  Tables[10][1023].Key.Bits:=0;
  Raised:=False;
  try BuildBindIndex(Tables,Index);
  except on E:EBindError do Raised:=True; end;
  Check(Raised,'corrupt D10 key order admitted');
  Check((Index.Count=0) and (Length(Index.Slots)=0),
    'corrupt D10 order retained previous index');
  LoadPinnedDomains('external/sens',Tables);
  BuildBindIndex(Tables,Index);
  Check(Index.Count=Count,'failed to recover pinned index');
  WriteLn('BINDINDEX-ATOMIC-OK domains=10 checked=',Count,
    ' duplicates=reject partial=none rebuild=pass');
end.
