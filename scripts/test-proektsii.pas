program test_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii;
var All:TProektsiiCatalog; Rows:TProektsiiRows; Base:TDomainTable;
    F:TFileStream; S,S7,Bad:RawByteString; I,Total,Rejected:Integer;
procedure Check(OK:Boolean;const MessageText:String);
begin
  if not OK then begin
    WriteLn(StdErr,'ПРОЄКЦІЇ-ПОМИЛКА: ',MessageText);
    Halt(1);
  end;
end;
procedure MustRejectD7(const Candidate:RawByteString;const Name:String);
var Failed:Boolean;
begin
  LoadProjectionTable(S7,7,Rows);
  Failed:=False;
  try LoadProjectionTable(Candidate,7,Rows);
  except on E:EProektsiiError do Failed:=True end;
  Check(Failed,'Не відхилено D7 '+Name);
  Check(Length(Rows)=0,'Залишився частковий D7 після відмови: '+Name);
  Inc(Rejected);
end;
procedure MustReject(const Candidate:RawByteString;const Name:String);
var Failed:Boolean;
begin
  LoadProjectionTable(S,3,Rows);
  Failed:=False;
  try LoadProjectionTable(Candidate,3,Rows);
  except on E:EProektsiiError do Failed:=True end;
  Check(Failed,'Не відхилено '+Name);
  Check(Length(Rows)=0,'Після помилки залишився старий результат: '+Name);
  Inc(Rejected);
end;
begin
  LoadPinnedProjections('external/sens',All);
  Total:=0;
  for I:=1 to 10 do begin
    Check(Length(All[I])=(1 shl I),'Неповна pinned таблиця D'+IntToStr(I));
    Inc(Total,Length(All[I]));
    Check(KeyBits(All[I][0].Key)=StringOfChar('0',I),
      'Втрачено провідні нулі D'+IntToStr(I));
  end;
  Check(Total=2046,'Неправильна кількість pinned рядків');
  Check(SameProjectedText(All[1][0].Surface[0],'ні') and
        SameProjectedText(All[1][1].Surface[0],'так'),'D1 0/1 назви');
  Check(SameProjectedText(All[2][2].Surface[0],'відкрити'),'D2 рамка');
  Check(SameProjectedText(All[3][1].Surface[2],'svarūpa'),'D3 san');
  Check(All[3][1].Surface[3]='quote','D3 en');
  Check(All[3][1].Surface[4]='QUOTE','D3 LISP дані');
  Check(SameProjectedText(All[4][5].Surface[0],'порожнє?'),'D4 ук');
  Check(SameProjectedText(All[4][5].Surface[1],'порожній?'),'D4 укр');
  Check(All[7][22].Surface[0]='','D7 SYN має бути без ук');
  Check(All[7][22].Surface[4]='','D7 не можна вигадати функцію');
  Check(All[7][32].Surface[0]='" "','D7 пробіл є quoted data');
  Check(All[10][1023].Key.Bits=1023,'D10 останній exact біт');
  Check(SameProjectedText(RawByteString(SurfaceForDisplay('')),'(відсутня)'),
    'Неправильний показ порожньої проєкції');
  F:=TFileStream.Create('external/sens/lib/domains/d3.lisp',fmOpenRead);
  try
    SetLength(S,SizeInt(F.Size));
    F.ReadBuffer(S[1],Length(S));
  finally F.Free end;
  Rejected:=0;
  MustReject('', 'порожнє джерело');
  MustReject(Copy(S,1,Pos('(111 (',S)-1),'відсутній кінець');
  Bad:=StringReplace(S,'(111 (', '(110 (',[]);
  MustReject(Bad,'дубльоване двійкове слово');
  Bad:=StringReplace(S,'(san ', '(sx ',[]);
  MustReject(Bad,'помилкова назва колонки san');
  { Оригінальний D3:111 має нецитовану sym-поверхню +:.
    Перевіряємо, що мутант справді змінює байти pinned рядка. }
  Bad:=StringReplace(S,'(sym +:))', '(sym +:)',[]);
  Check(Bad<>S,'Мутант незакритої колонки не створено');
  MustReject(Bad,'незакрита колонка');
  { Рядковий fast-path раніше ігнорував чужу верхню форму, попри
    нібито повне pinned джерело. Відтепер AST gate це відхиляє. }
  MustReject(S+#10+'(стороння-форма)','зайва top-level форма');
  Bad:=StringReplace(S,'(sym "''")','(sym "\q")',[]);
  Check(Bad<>S,'Не створено mutant D3 quoted sym');
  MustReject(Bad,'невідоме quoted escape');
  LoadProjectionTable(S,3,Rows);
  Check(Length(Rows)=8,'Не відновлено D3 після відмови');

  F:=TFileStream.Create('external/sens/lib/domains/d7.lisp',fmOpenRead);
  try
    SetLength(S7,SizeInt(F.Size));
    F.ReadBuffer(S7[1],Length(S7));
  finally F.Free end;
  Bad:=StringReplace(S7,'(LISP ())','(LISP ATOM)',[]);
  Check(Bad<>S7,'Не створено mutant D7 LISP');
  MustRejectD7(Bad,'заборонена виклична LISP-голова у D7');
  Bad:=StringReplace(S7,'(0010110 (ук ())','(0010110 (ук "x")',[]);
  Check(Bad<>S7,'Не створено mutant D7 SYN');
  MustRejectD7(Bad,'SYN не має друкованого символу');
  Bad:=StringReplace(S7,'(0110000 (ук "0")','(0110000 (ук ())',[]);
  Check(Bad<>S7,'Не створено mutant D7 цифри');
  MustRejectD7(Bad,'друкована W7 цифра з пустою українською');
  LoadProjectionTable(S7,7,Rows);
  Check((Length(Rows)=128) and (Rows[22].Surface[0]='') and
    (Rows[48].Surface[0]='"0"'),
    'Відновлено pinned D7 керувальну/цифрову поверхню');

  { G2.37: старий host reader обрізав ")" і незалежний
    LoadPinnedProjections вимикав перевірку цієї координати.
    Тепер ВСІ 128 pinned D7 ук мають збігатися побайтово. }
  LoadDomainTable(S7,7,Base);
  Check((Length(Base)=128) and (Rows[41].Surface[0]='")"') and
    (Base[41].Ukrainian='")"') and (Rows[40].Surface[0]='"("'),
    'втрачені точні quoted дужки D7');
  for I:=0 to 127 do
    Check(SameKey(Rows[I].Key,Base[I].Key) and
      (Rows[I].Surface[0]=Base[I].Ukrainian) and
      (All[7][I].Surface[0]=Base[I].Ukrainian),
      'невідповідність pinned D7 двох незалежних reader: '+IntToStr(I));
  WriteLn('ПРОЄКЦІЇ-Д7-ПАРИТЕТ-ГАРАЗД рядків=128 ',
    'quoted-дужки=точно без-пропущених-координат=так');
  WriteLn('ПРОЄКЦІЇ-ГАРАЗД рядків=',Total,
    ' колонок=6 негативних=',Rejected,' D7=128 D10=1024');
end.
