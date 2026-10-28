{ Об'єднаний FPC-тест реального native D3, не synthetic callback.
  Для семантичного baseline використано окремо засвідчений G3.2
  фізичний SENS/T5M corpus; цей тест не замінює нового oracle. }
program test_sensd3;
{$mode objfpc}{$H+}{$codepage UTF8}
uses SysUtils, Classes, wsm.nativeadapter, wsm.nativeeval,
     wsm.source, wsm.session, wsm.lineinput;

procedure Pereviryty(Umova:Boolean;const Chomu:String);
begin
  if not Umova then begin
    WriteLn(StdErr,'D3-СЕСІЯ-ПОМИЛКА ',Chomu);
    Halt(1);
  end;
end;

function B(const Dzherelo:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Dzherelo)); end;

procedure Uspikh(const R:TSessionReplies;Indeks:SizeInt;
  const Ochikuvannia:RawByteString);
begin
  Pereviryty(Indeks<Length(R),'немає відповіді');
  Pereviryty(R[Indeks].Ok,'несподівана помилка: '+String(R[Indeks].Diagnostic));
  Pereviryty(R[Indeks].Output=Ochikuvannia,
    'очікували '+String(Ochikuvannia)+' отримали '+String(R[Indeks].Output));
end;

procedure Vidmova(const R:TSessionReplies;const Frahment:String);
begin
  Pereviryty((Length(R)=1) and (not R[0].Ok),'відсутня відмова');
  Pereviryty(R[0].Output='','помилка повернула значення');
  Pereviryty(Pos(Frahment,String(R[0].Diagnostic))>0,
    'неправильна діагностика: '+String(R[0].Diagnostic));
end;

var
  Vykonavets:IFormExecutor;
  Sesiia:TNativeSession;
  Riadky:TLineInput;
  Forma:TSourceDocument;
  Native:TNativeEvaluator;
  R:TSessionReplies;
  Tekst:RawByteString;
  F:TFileStream;
  Fail:String;
  Perekhopleno:Boolean;
  Kilkist:SizeInt;
begin
  Vykonavets:=NovyiVykonavetsD3('external/sens');
  Sesiia:=TNativeSession.Create(Vykonavets);
  Native:=TNativeEvaluator.Create('external/sens');
  Riadky:=TLineInput.Create(Sesiia);
  try
    R:=Sesiia.Submit(B('так ні ()'));
    Pereviryty(Length(R)=3,'багатоформове виконання');
    Uspikh(R,0,'1'); Uspikh(R,1,'0'); Uspikh(R,2,'()');
    Pereviryty(R[0].FormNumber=1,'нумерація перших форм');
    Pereviryty((R[0].Output<>R[2].Output) and
      (R[1].Output<>R[2].Output),'D1 відмінний від D3:000');

    R:=Sesiia.Submit(B('(сполучити так ні) (перше (сполучити ні ()))'));
    Pereviryty(Length(R)=2,'неповна кількість D3-викликів');
    Uspikh(R,0,'(1 . 0)'); Uspikh(R,1,'0');
    R:=Sesiia.Submit(B('(решта (як-є (кіт пес)))'));
    Uspikh(R,0,'((1100111 1110100 1100011))');
    R:=Sesiia.Submit(B('(атом? (сполучити так ()))'));
    Uspikh(R,0,'0');

    R:=Sesiia.Submit(B('(перше ())'));
    Vidmova(R,'native selector requires nonempty pair');
    Pereviryty(Pos('рядок=',String(R[0].Diagnostic))>0,
      'втрачено точну позицію в помилці виконання');
    R:=Sesiia.Submit(B('(сполучити так)'));
    Vidmova(R,'native arity error');
    R:=Sesiia.Submit(B('(car ())'));
    Vidmova(R,'unknown native call head');
    R:=Sesiia.Submit(B('(за-умовою (так так))'));
    Vidmova(R,'native mechanism not implemented');
    R:=Sesiia.Submit(B('невідома'));
    Vidmova(R,'unknown native binding');
    R:=Sesiia.Submit(B('ні'));
    Uspikh(R,0,'0');

    R:=Riadky.FeedLine(B('(сполучити так'));
    Pereviryty((Length(R)=0) and (Riadky.PendingBytes>0),
      'незавершену форму виконано');
    R:=Riadky.FeedLine(B('ні)'));
    Pereviryty(Length(R)=1,'не надіслано завершений список');
    Uspikh(R,0,'(1 . 0)');
    R:=Riadky.FeedLine(B('(атом? (як-є (кіт)))'));
    Uspikh(R,0,'0');

    R:=Sesiia.Submit(#$C0);
    Vidmova(R,'UTF-8');
    R:=Sesiia.Submit(B('(перше'));
    Vidmova(R,'unclosed list');
    R:=Sesiia.Submit(B('так'));
    Uspikh(R,0,'1');

    { Прямий вузловий API не повторює текстову обробку, а виконує
      той самий точнодоменний Eval/Render та очищає arena після помилки. }
    Tekst:=B('(перше (сполучити ні ()))');
    Forma:=ReadUkrainianSource(Tekst);
    try
      Pereviryty(Length(Forma.Forms)=1,'одна форма для вузлового API');
      Pereviryty(Native.EvaluateNode(Forma.Forms[0])=
        Native.EvaluateSource(Tekst),'API AST / upstream G3.2 різняться');
    finally Forma.Free; end;
    Perekhopleno:=False;
    try Native.EvaluateNode(nil);
    except on E:ENativeEvalError do Perekhopleno:=True; end;
    Pereviryty(Perekhopleno,'nil AST допущено');
    Pereviryty(Native.EvaluateSource('ні')='0',
      'помилка AST зіпсувала наступне обчислення');

    Fail:=GetTempFileName(GetTempDir(False),'sensd3-');
    try
      F:=TFileStream.Create(Fail,fmCreate);
      try
        Tekst:=B('(атом? ())');
        F.WriteBuffer(Tekst[1],Length(Tekst));
      finally F.Free; end;
      R:=Sesiia.LoadFile(Fail);
      Uspikh(R,0,'1');
    finally
      if FileExists(Fail) then DeleteFile(Fail);
    end;
    Pereviryty(Sesiia.FormsSeen=17,'кількість виконаних форм');
    Kilkist:=Sesiia.FormsSeen;
    WriteLn('D3-СЕСІЯ-OK форм=',Kilkist,
      ' фпк=3.2.2 дійсне-виконання=5-D3 ',
      ' негативні=відхилено T5M-оракул=раніше-перевірено ',
      ' повний-REPL=НІ Core4=НЕ-ВИКОНУЄТЬСЯ');
  finally
    Riadky.Free;
    Native.Free;
    Sesiia.Free;
    Vykonavets:=nil;
  end;
end.
