{ Українська людська проєкція фізичних кадрів нативного налагоджувача.
  Точні двійкові слова та ширини залишаються незмінними.
  Цей модуль НЕ визначає викличність, значення чи закони SENS. }
unit wsm.uktrace;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses SysUtils, wsm.debugtrace;

type
  EProiektsiiaError = class(Exception);

function UkrainskyiStek(const Kadry: TDebugFrames): RawByteString;

implementation
uses wsm.domain;

function UkrainskyiStek(const Kadry: TDebugFrames): RawByteString;
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
    Result := Result + 'кадр ' + IntToStr(High(Kadry)-I) +
      ': домен D' + IntToStr(Kadr.Key.Width) +
      ', слово ' + Slovo +
      ', байт ' + IntToStr(Kadr.ByteOffset) +
      ', рядок ' + IntToStr(Kadr.Line) +
      ', стовпець ' + IntToStr(Kadr.ByteColumn) + #10;
  end;
end;
end.
