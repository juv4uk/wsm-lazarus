{ Обмежена інтерактивна D3-оболонка. ВИКОНУЄ підтримані форми,
  проте НЕ є повним REPL SENS: немає визначень, Core4, D4+ або образів.
  Коди D3 беруться лише з pinned SENS через wsm.nativeeval. }
program sensd3;
{$mode objfpc}{$H+}{$codepage UTF8}
uses SysUtils, wsm.session, wsm.lineinput, wsm.nativeadapter;
var
  Vykonavets:IFormExecutor;
  Sesiia:TNativeSession;
  Riadky:TLineInput;
  Riadok:RawByteString;
  Vidpovidi:TSessionReplies;
  Pomylky:Boolean;
  I:SizeInt;

procedure Pokazaty(const Spysok:TSessionReplies);
var J:SizeInt;
begin
  for J:=0 to High(Spysok) do begin
    if Spysok[J].Ok then
      WriteLn(String(Spysok[J].Output))
    else begin
      Pomylky:=True;
      WriteLn(StdErr,'ПОМИЛКА D3 форма=',Spysok[J].FormNumber,
        ' рядок=',Spysok[J].Line,' байт=',Spysok[J].ByteOffset,
        ' стовпчик=',Spysok[J].ByteColumn,': ',
        String(Spysok[J].Diagnostic));
    end;
  end;
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Використання: sensd3 шлях-до-pinned-sens');
    WriteLn(StdErr,'Обмеження: D1/D3 і вузькі D7-форми; Core4 НЕ виконується.');
    Halt(64);
  end;
  Pomylky:=False;
  try
    Vykonavets:=NovyiVykonavetsD3(RawByteString(ParamStr(1)));
    Sesiia:=TNativeSession.Create(Vykonavets);
    try
      Riadky:=TLineInput.Create(Sesiia);
      try
        while not Eof(Input) do begin
          ReadLn(Input,Riadok);
          try
            Vidpovidi:=Riadky.FeedLine(Riadok);
            Pokazaty(Vidpovidi);
          except
            on E:ELineInputError do begin
              Pomylky:=True;
              WriteLn(StdErr,'ПОМИЛКА вводу: ',E.Message);
            end;
          end;
        end;
        Vidpovidi:=Riadky.Finish;
        Pokazaty(Vidpovidi);
      finally Riadky.Free; end;
    finally Sesiia.Free; end;
    Vykonavets:=nil;
  except
    on E:Exception do begin
      WriteLn(StdErr,'ПОМИЛКА ініціалізації D3: ',E.Message);
      Halt(2);
    end;
  end;
  if Pomylky then Halt(2);
end.
