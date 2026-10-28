program test_uktrace;
{$mode objfpc}{$H+}
{$codepage utf8}
uses SysUtils, wsm.domain, wsm.debugtrace, wsm.uktrace, wsm.faulttrace;

procedure Perevir(Uzmova: Boolean; const Prychyna: String);
begin
  if not Uzmova then
  begin
    WriteLn(StdErr, 'ПОМИЛКА-ПРОЄКЦІЇ: ', Prychyna);
    Halt(1);
  end;
end;

var
  Stek: TDebugTrace;
  Zovnishnii, Vnutrishnii: TDebugToken;
  Kadry: TDebugFrames;
  Podannia, Ochekuvane: UTF8String;
  Vidmovleno: Boolean;
begin
  Stek := TDebugTrace.Create;
  try
    Zovnishnii := Stek.Push(ExactKey('0'), 10, 2, 3);
    Vnutrishnii := Stek.Push(ExactKey('000'), 29, 3, 8);
    Kadry := Stek.Snapshot;
    Podannia := PodanniaSteka(Kadry);
    Ochekuvane :=
      'кадр 0: домен D3, слово 000, байт 29, рядок 3, стовпець 8' + #10 +
      'кадр 1: домен D1, слово 0, байт 10, рядок 2, стовпець 3' + #10;
    Perevir(Podannia = Ochekuvane,
      'точне українське подання та незмінні двійкові слова');
    Perevir(Pos('D3, слово 000', Podannia) > 0,
      'D3:000 не можна змішувати з D1:0');
    Perevir(Pos('D1, слово 0', Podannia) > 0, 'D1:0 збережено');
    Perevir(Pos('byte=', Podannia) = 0, 'англомовних міток немає');
    Stek.Pop(Vnutrishnii);
    Stek.Pop(Zovnishnii);
    Perevir(PodanniaSteka(Kadry) = Ochekuvane,
      'знімок не змінюється після розмотування кадрів');
    Perevir(PodanniaSteka(Stek.Snapshot) = '',
      'порожній стек має порожнє подання');

    { Реальний виняток захоплює кадри до знищення джерела. }
    Zovnishnii := Stek.Push(ExactKey('0'), 10, 2, 3);
    Vnutrishnii := Stek.Push(ExactKey('000'), 29, 3, 8);
    Vidmovleno := False;
    try
      try
        raise EDebugFault.Capture(Stek, 9, 'фізична помилка');
      finally
        Stek.Pop(Vnutrishnii);
        Stek.Pop(Zovnishnii);
      end;
    except
      on E: EDebugFault do
      begin
        Vidmovleno := True;
        Perevir(Stek.Depth = 0, 'всі кадри зняті через finally');
        Stek.Free;
        Stek := nil;
        Perevir(E.UkrainskyiStek = Ochekuvane,
          'виняток зберігає українське подання після Free');
        Perevir(E.Backtrace <> E.UkrainskyiStek,
          'попередній фізичний формат збережено окремо');
        Perevir(E.FrameCount = 2, 'кількість збережених кадрів');
      end;
    end;
    Perevir(Vidmovleno, 'виняток справді був оброблений');
  finally
    Stek.Free;
  end;

  SetLength(Kadry, 1);
  Kadry[0].Key.Width := 0;
  Kadry[0].Key.Bits := 0;
  Kadry[0].ByteOffset := 1;
  Kadry[0].Line := 1;
  Kadry[0].ByteColumn := 1;
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'нульова ширина заборонена');

  Kadry[0].Key.Width := 2;
  Kadry[0].Key.Bits := 4;
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'біти поза доменом заборонені');

  Kadry[0].Key := ExactKey('01');
  Kadry[0].Line := 0;
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'рядок нуль заборонено');
  Kadry[0].Line := 1;
  Kadry[0].ByteOffset := 0;
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'нульовий байтовий зсув заборонено');
  Kadry[0].ByteOffset := 1;
  Kadry[0].ByteColumn := 0;
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'нульовий стовпець заборонено');

  SetLength(Kadry, MaxTraceDepth+1);
  Vidmovleno := False;
  try Podannia := PodanniaSteka(Kadry);
  except on E: EProiektsiiaError do Vidmovleno := True; end;
  Perevir(Vidmovleno, 'надмірну кількість кадрів відхилено');

  WriteLn('УКР-СТЕК-ГАРАЗД: двійкові-координати=точні ',
    'виняток=збережено негативні=відхилено ',
    'закони-SENS=не-визначає');
end.
