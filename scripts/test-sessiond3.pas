{ G5.4 — фізичний сеанс із СПРАВЖНІМ обмеженим D3 оцінювачем.
  «ук» є лише проєкцією входу; вихід — точні двійкові слова. }
program test_sessiond3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.session, wsm.sessiond3;
function Bytes(const U:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(U)); end;
procedure Check(B:Boolean; const Why:String);
begin
  if not B then begin WriteLn(StdErr,'SESSIOND3-FAIL ',Why); Halt(1); end;
end;
var
  S:TNativeSession;
  R:TSessionReplies;
  P:RawByteString;
  F:TFileStream;
  Filename:String;
begin
  S:=TNativeSession.Create(NewNativeD3Executor('external/sens'));
  try
    R:=S.Submit(Bytes('так ні (сполучити так ())'));
    Check(Length(R)=3,'кількість форм');
    Check(R[0].Ok and (R[0].Output='1'),'точне D1:1');
    Check(R[1].Ok and (R[1].Output='0'),'точне D1:0');
    Check(R[2].Ok and (R[2].Output='(1)'),'дійсне сполучення');
    Check((R[0].FormNumber=1) and (R[2].FormNumber=3),
      'номери форм');

    R:=S.Submit(Bytes('(перше (сполучити ні ())) (атом? ())'));
    Check(Length(R)=2,'дві форми D3');
    Check(R[0].Ok and (R[0].Output='0'),'дійсний селектор');
    Check(R[1].Ok and (R[1].Output='1'),'порожня структура не є D1:0');
    R:=S.Submit(Bytes('(як-є кіт)'));
    Check((Length(R)=1) and R[0].Ok and
      (R[0].Output='(1110010 1110011 1101110)'),
      'цитування D7 як структури точних бітів');

    R:=S.Submit(Bytes('(невідома ()) ні'));
    Check((Length(R)=2) and not R[0].Ok and R[1].Ok,
      'невідомий виклик має блокуватися без втрати наступної форми');
    Check((R[0].ByteOffset=2) and (R[0].Line=1) and
      (R[0].ByteColumn=2),'точна позиція вкладеної помилки');
    Check(R[1].Output='0','відновлення після помилки');
    R:=S.Submit(Bytes('(за-умовою (так так)) так'));
    Check((Length(R)=2) and not R[0].Ok and R[1].Ok,
      'нереалізований D3 не має виконуватися');
    Check(R[0].Diagnostic<>'','негативний випадок без діагностики');
    R:=S.Submit(Bytes('(перше ()) так'));
    Check((Length(R)=2) and not R[0].Ok and R[1].Ok,
      'помилка типу та подальше виконання');
    R:=S.Submit(Bytes('(перше'));
    Check((Length(R)=1) and not R[0].Ok,
      'незакрита форма не відхилена');
    R:=S.Submit(Bytes('()'));
    Check((Length(R)=1) and R[0].Ok and (R[0].Output='()'),
      'сеанс не відновився після синтаксичної помилки');

    Filename:=GetTempFileName(GetTempDir(False),'sens-d3-');
    try
      F:=TFileStream.Create(Filename,fmCreate);
      try
        P:=Bytes('(сполучити так ні)')+#10+Bytes('(атом? ())');
        F.WriteBuffer(P[1],Length(P));
      finally F.Free; end;
      R:=S.LoadFile(Filename);
      Check((Length(R)=2) and R[0].Ok and R[1].Ok,
        'файлове виконання');
      Check((R[0].Output='(1 . 0)') and (R[1].Output='1'),
        'точні двійкові значення з файлу');
    finally
      if FileExists(Filename) then DeleteFile(Filename);
    end;
    R:=S.LoadFile(Filename);
    Check((Length(R)=1) and not R[0].Ok,'відсутній файл прийнято');
    Check(S.FormsSeen=14,'помилки читання змінили лічильник форм');
    WriteLn('SESSIOND3-OK domain=D1,D3,D7 binary-results=1 ',
      'forms=14 positional=1 file=1 recovery=1 ',
      'core4=NOT_EXECUTED full-repl=NOT_IMPLEMENTED');
  finally S.Free; end;
end.
