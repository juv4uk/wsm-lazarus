{ Українська людська проєкція фізичних кадрів нативного налагоджувача.
  Точні двійкові слова та ширини залишаються незмінними.
  Цей модуль НЕ визначає викличність, значення чи закони SENS. }
unit wsm.uktrace;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.debugtrace;

type
  EProiektsiiaError = class(Exception);

function PodanniaSteka(const Kadry: TDebugFrames): RawByteString;

implementation
uses wsm.domain;
const
  MitkaKadr = #$D0#$BA#$D0#$B0#$D0#$B4#$D1#$80;
  MitkaDomen = #$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD;
  MitkaSlovo = #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE;
  MitkaBajt = #$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82;
  MitkaRiadok = #$D1#$80#$D1#$8F#$D0#$B4#$D0#$BE#$D0#$BA;
  MitkaStovpets = #$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$BF#$D0#$B5#$D1#$86#$D1#$8C;


function PodanniaSteka(const Kadry: TDebugFrames): RawByteString;
var
  I: SizeInt;
  Slovo: RawByteString;
  Kadr: TDebugFrame;
begin
  if Length(Kadry) > MaxTraceDepth then
    raise EProiektsiiaError.Create('перевищено межу кількості кадрів');
  Result := '';
  { Внутрішній масив містить кадри від зовнішнього до внутрішнього.
    Людині показуємо найглибший кадр першим; облік із нуля. }
  for I := High(Kadry) downto 0 do
  begin
    Kadr := Kadry[I];
    try
      Slovo := KeyBits(Kadr.Key);
    except
      on E: EDomainError do
        raise EProiektsiiaError.Create('некоректна фізична координата кадру');
    end;
    if (Length(Slovo) = 0) or (Kadr.ByteOffset < 1) or
       (Kadr.Line < 1) or (Kadr.ByteColumn < 1) then
      raise EProiektsiiaError.Create('некоректні координати або позиція кадру');
    Result := Result + MitkaKadr + ' ' + IntToStr(High(Kadry)-I) +
      ': ' + MitkaDomen + ' D' + IntToStr(Kadr.Key.Width) +
      ', ' + MitkaSlovo + ' ' + Slovo +
      ', ' + MitkaBajt + ' ' + IntToStr(Kadr.ByteOffset) +
      ', ' + MitkaRiadok + ' ' + IntToStr(Kadr.Line) +
      ', ' + MitkaStovpets + ' ' + IntToStr(Kadr.ByteColumn) + #10;
  end;
end;
end.
