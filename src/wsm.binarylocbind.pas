{ G2.8. Фізичні адреси точних доменних слів SENS.
  Єдині джерела механіки: вже злиті wsm.physloc і wsm.binarybind.
  Тут немає ні нового T5M-декодера, ні семантичних законів, ні викличності.
  Українська проєкція є лише довідковим полем вихідного зв'язування. }
unit wsm.binarylocbind;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind;
type
  EBinaryLocatedError = class(Exception);
  TLocatedBinaryWord = record
    Word: TBinaryWord;        { exact width, bits, root, optional ук }
    Physical: TPhysicalWordSpan; { 0-based half-open trits and bytes }
  end;
  TLocatedBinaryWords = array of TLocatedBinaryWord;

procedure BindLocatedT5M(const Physical: RawByteString;
  const Tables: TDomainSet; out Bound: TLocatedBinaryWords);

implementation
procedure BindLocatedT5M(const Physical: RawByteString;
  const Tables: TDomainSet; out Bound: TLocatedBinaryWords);
var
  Document: TD2Document;
  Spans: TPhysicalWordSpans;
  Words: TBinaryWords;
  I: SizeInt;
  Span: TPhysicalWordSpan;
begin
  SetLength(Bound, 0);
  { Фізичний T5M та синтаксис D2 перевіряють чинні модулі.
    Вони зберігають точну позицію навіть для D2-помилки на EOF. }
  Document := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    { Домен перевіряється тільки після фізичного D2 розбору.
      Жодна українська назва не використовується для dispatch. }
    BindD2Binary(Document, Tables, Words);
    SetLength(Bound, Length(Words));
    for I := 0 to High(Words) do begin
      Span := LocatePhysicalWord(Physical, Spans, Words[I].WordIndex);
      if Span.IsEOF or
         (Span.TritEnd - Span.TritStart <> Words[I].Key.Width) or
         (Span.WordIndex <> Words[I].WordIndex) or
         (Span.ByteStart < 0) or
         (Span.ByteEnd > Length(Physical)) or
         (Span.ByteStart >= Span.ByteEnd) then
        raise EBinaryLocatedError.Create('некоректна фізична позиція доменного слова');
      Bound[I].Word := Words[I];
      Bound[I].Physical := Span;
    end;
  finally
    Document.Free;
  end;
end;
end.
