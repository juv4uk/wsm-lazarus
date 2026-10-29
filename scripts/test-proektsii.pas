program test_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii;
var All:TProektsiiCatalog; Rows:TProektsiiRows;
    F:TFileStream; S,Bad:RawByteString; I,Total,Rejected:Integer;
procedure Check(OK:Boolean;const MessageText:String);
begin
  if not OK then begin
    WriteLn(StdErr,'ПРОЄКЦІЇ-ПОМИЛКА: ',MessageText);
    Halt(1);
  end;
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
  LoadProjectionTable(S,3,Rows);
  Check(Length(Rows)=8,'Не відновлено D3 після відмови');
  WriteLn('ПРОЄКЦІЇ-ГАРАЗД рядків=',Total,
    ' колонок=6 негативних=',Rejected,' D7=128 D10=1024');
end.
