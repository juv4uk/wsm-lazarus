program test_uktrace;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.debugtrace, wsm.uktrace, wsm.faulttrace;

procedure Perevir(Uzmova: Boolean; const Prychyna: String);
begin
  if not Uzmova then
  begin
    WriteLn(StdErr, 'ПОМИЛКА-ПРОЄКЦІЇ: ', Prychyna);
    Halt(1);
  end;
end;

const
  UkKadr = #$D0#$BA#$D0#$B0#$D0#$B4#$D1#$80;
  UkDomen = #$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD;
  UkSlovo = #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE;
  UkBajt = #$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82;
  UkRiadok = #$D1#$80#$D1#$8F#$D0#$B4#$D0#$BE#$D0#$BA;
  UkStovpets = #$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$BF#$D0#$B5#$D1#$86#$D1#$8C;
  UkHarazd = #$D0#$A3#$D0#$9A#$D0#$A0#$2D#$D0#$A1#$D0#$A2#$D0#$95#$D0#$9A#$2D#$D0#$93#$D0#$90#$D0#$A0#$D0#$90#$D0#$97#$D0#$94;

var
  Stek: TDebugTrace;
  Zovnishnii, Vnutrishnii: TDebugToken;
  Kadry: TDebugFrames;
  Podannia, Ochekuvane: RawByteString;
  Vidmovleno: Boolean;
begin
  Stek := TDebugTrace.Create;
  try
    Zovnishnii := Stek.Push(ExactKey('0'), 10, 2, 3);
    Vnutrishnii := Stek.Push(ExactKey('000'), 29, 3, 8);
    Kadry := Stek.Snapshot;
    Podannia := PodanniaSteka(Kadry);
    { Незалежна байтова фікстура UTF-8: ці мітки є літералами
      байтів, а не можливим транслітеруванням SENS-доменів. }
    Ochekuvane :=
      UkKadr + ' 0: ' + UkDomen + ' D3, ' + UkSlovo + ' 000, ' +
      UkBajt + ' 29, ' + UkRiadok + ' 3, ' + UkStovpets + ' 8' + #10 +
      UkKadr + ' 1: ' + UkDomen + ' D1, ' + UkSlovo + ' 0, ' +
      UkBajt + ' 10, ' + UkRiadok + ' 2, ' + UkStovpets + ' 3' + #10;
    Perevir(Podannia = Ochekuvane,
      'точне українське подання та незмінні двійкові слова');
    Perevir(Pos('D3, ' + UkSlovo + ' 000', Podannia) > 0,
      'D3:000 не можна змішувати з D1:0');
    Perevir(Pos('D1, ' + UkSlovo + ' 0', Podannia) > 0, 'D1:0 збережено');
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

  WriteLn(UkHarazd, ' двійкові-координати=точні ',
    'виняток=збережено негативні=відхилено ',
    'закони-SENS=не-визначає');
end.
