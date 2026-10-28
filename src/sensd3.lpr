{ Обмежена інтерактивна D3-оболонка. ВИКОНУЄ підтримані форми,
  проте НЕ є повним REPL SENS: немає визначень, Core4, D4+ або образів.
  Коди D3 беруться лише з pinned SENS через wsm.nativeeval. }
program sensd3;
{$mode objfpc}{$H+}{$codepage UTF8}
uses SysUtils, wsm.session, wsm.lineinput, wsm.nativeadapter;
var
  Виконавець:IFormExecutor;
  Сесія:TNativeSession;
  Рядки:TLineInput;
  Рядок:RawByteString;
  Відповіді:TSessionReplies;
  Помилки:Boolean;
  I:SizeInt;

procedure Показати(const Список:TSessionReplies);
var J:SizeInt;
begin
  for J:=0 to High(Список) do begin
    if Список[J].Ok then
      WriteLn(String(Список[J].Output))
    else begin
      Помилки:=True;
      WriteLn(StdErr,'ПОМИЛКА D3 форма=',Список[J].FormNumber,
        ' рядок=',Список[J].Line,' байт=',Список[J].ByteOffset,
        ' стовпчик=',Список[J].ByteColumn,': ',
        String(Список[J].Diagnostic));
    end;
  end;
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Використання: sensd3 шлях-до-pinned-sens');
    WriteLn(StdErr,'Обмеження: D1/D3 і вузькі D7-форми; Core4 НЕ виконується.');
    Halt(64);
  end;
  Помилки:=False;
  try
    Виконавець:=НовийВиконавецьD3(RawByteString(ParamStr(1)));
    Сесія:=TNativeSession.Create(Виконавець);
    try
      Рядки:=TLineInput.Create(Сесія);
      try
        while not Eof(Input) do begin
          ReadLn(Input,Рядок);
          try
            Відповіді:=Рядки.FeedLine(Рядок);
            Показати(Відповіді);
          except
            on E:ELineInputError do begin
              Помилки:=True;
              WriteLn(StdErr,'ПОМИЛКА вводу: ',E.Message);
            end;
          end;
        end;
        Відповіді:=Рядки.Finish;
        Показати(Відповіді);
      finally Рядки.Free; end;
    finally Сесія.Free; end;
    Виконавець:=nil;
  except
    on E:Exception do begin
      WriteLn(StdErr,'ПОМИЛКА ініціалізації D3: ',E.Message);
      Halt(2);
    end;
  end;
  if Помилки then Halt(2);
end.
