{ Об'єднаний FPC-тест реального native D3, не synthetic callback.
  Для семантичного baseline використано окремо засвідчений G3.2
  фізичний SENS/T5M corpus; цей тест не замінює нового oracle. }
program test_sensd3;
{$mode objfpc}{$H+}{$codepage UTF8}
uses SysUtils, Classes, wsm.nativeadapter, wsm.nativeeval,
     wsm.source, wsm.session, wsm.lineinput;

procedure Перевірити(Умова:Boolean;const Чому:String);
begin
  if not Умова then begin
    WriteLn(StdErr,'D3-СЕСІЯ-ПОМИЛКА ',Чому);
    Halt(1);
  end;
end;

function Б(const Джерело:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Джерело)); end;

procedure Успіх(const Р:TSessionReplies;Індекс:SizeInt;
  const Очікування:RawByteString);
begin
  Перевірити(Індекс<Length(Р),'немає відповіді');
  Перевірити(Р[Індекс].Ok,'несподівана помилка: '+String(Р[Індекс].Diagnostic));
  Перевірити(Р[Індекс].Output=Очікування,
    'очікували '+String(Очікування)+' отримали '+String(Р[Індекс].Output));
end;

procedure Відмова(const Р:TSessionReplies;const Фрагмент:String);
begin
  Перевірити((Length(Р)=1) and (not Р[0].Ok),'відсутня відмова');
  Перевірити(Р[0].Output='','помилка повернула значення');
  Перевірити(Pos(Фрагмент,String(Р[0].Diagnostic))>0,
    'неправильна діагностика: '+String(Р[0].Diagnostic));
end;

var
  Виконавець:IFormExecutor;
  Сесія:TNativeSession;
  Рядки:TLineInput;
  Форма:TSourceDocument;
  Native:TNativeEvaluator;
  Р:TSessionReplies;
  Текст:RawByteString;
  F:TFileStream;
  Файл:String;
  Перехоплено:Boolean;
  Кількість:SizeInt;
begin
  Виконавець:=НовийВиконавецьD3('external/sens');
  Сесія:=TNativeSession.Create(Виконавець);
  Native:=TNativeEvaluator.Create('external/sens');
  Рядки:=TLineInput.Create(Сесія);
  try
    Р:=Сесія.Submit(Б('так ні ()'));
    Перевірити(Length(Р)=3,'багатоформове виконання');
    Успіх(Р,0,'1'); Успіх(Р,1,'0'); Успіх(Р,2,'()');
    Перевірити(Р[0].FormNumber=1,'нумерація перших форм');
    Перевірити((Р[0].Output<>Р[2].Output) and
      (Р[1].Output<>Р[2].Output),'D1 відмінний від D3:000');

    Р:=Сесія.Submit(Б('(сполучити так ні) (перше (сполучити ні ()))'));
    Перевірити(Length(Р)=2,'неповна кількість D3-викликів');
    Успіх(Р,0,'(1 . 0)'); Успіх(Р,1,'0');
    Р:=Сесія.Submit(Б('(решта (як-є (кіт пес)))'));
    Успіх(Р,0,'((1100111 1110100 1100011))');
    Р:=Сесія.Submit(Б('(атом? (сполучити так ()))'));
    Успіх(Р,0,'0');

    Р:=Сесія.Submit(Б('(перше ())'));
    Відмова(Р,'native selector requires nonempty pair');
    Перевірити(Pos('рядок=',String(Р[0].Diagnostic))>0,
      'втрачено точну позицію в помилці виконання');
    Р:=Сесія.Submit(Б('(сполучити так)'));
    Відмова(Р,'native arity error');
    Р:=Сесія.Submit(Б('(car ())'));
    Відмова(Р,'unknown native call head');
    Р:=Сесія.Submit(Б('(за-умовою (так так))'));
    Відмова(Р,'native mechanism not implemented');
    Р:=Сесія.Submit(Б('невідома'));
    Відмова(Р,'unknown native binding');
    Р:=Сесія.Submit(Б('ні'));
    Успіх(Р,0,'0');

    Р:=Рядки.FeedLine(Б('(сполучити так'));
    Перевірити((Length(Р)=0) and (Рядки.PendingBytes>0),
      'незавершену форму виконано');
    Р:=Рядки.FeedLine(Б('ні)'));
    Перевірити(Length(Р)=1,'не надіслано завершений список');
    Успіх(Р,0,'(1 . 0)');
    Р:=Рядки.FeedLine(Б('(атом? (як-є (кіт)))'));
    Успіх(Р,0,'0');

    Р:=Сесія.Submit(#$C0);
    Відмова(Р,'UTF-8');
    Р:=Сесія.Submit(Б('(перше'));
    Відмова(Р,'unclosed list');
    Р:=Сесія.Submit(Б('так'));
    Успіх(Р,0,'1');

    { Прямий вузловий API не повторює текстову обробку, а виконує
      той самий точнодоменний Eval/Render та очищає arena після помилки. }
    Текст:=Б('(перше (сполучити ні ()))');
    Форма:=ReadUkrainianSource(Текст);
    try
      Перевірити(Length(Форма.Forms)=1,'одна форма для вузлового API');
      Перевірити(Native.EvaluateNode(Форма.Forms[0])=
        Native.EvaluateSource(Текст),'API AST / upstream G3.2 різняться');
    finally Форма.Free; end;
    Перехоплено:=False;
    try Native.EvaluateNode(nil);
    except on E:ENativeEvalError do Перехоплено:=True; end;
    Перевірити(Перехоплено,'nil AST допущено');
    Перевірити(Native.EvaluateSource('ні')='0',
      'помилка AST зіпсувала наступне обчислення');

    Файл:=GetTempFileName(GetTempDir(False),'sensd3-');
    try
      F:=TFileStream.Create(Файл,fmCreate);
      try
        Текст:=Б('(атом? ())');
        F.WriteBuffer(Текст[1],Length(Текст));
      finally F.Free; end;
      Р:=Сесія.LoadFile(Файл);
      Успіх(Р,0,'1');
    finally
      if FileExists(Файл) then DeleteFile(Файл);
    end;
    Перевірити(Сесія.FormsSeen=17,'кількість виконаних форм');
    Кількість:=Сесія.FormsSeen;
    WriteLn('D3-СЕСІЯ-OK форм=',Кількість,
      ' фпк=3.2.2 дійсне-виконання=5-D3 ',
      ' негативні=відхилено T5M-оракул=раніше-перевірено ',
      ' повний-REPL=НІ Core4=НЕ-ВИКОНУЄТЬСЯ');
  finally
    Рядки.Free;
    Native.Free;
    Сесія.Free;
    Виконавець:=nil;
  end;
end.
