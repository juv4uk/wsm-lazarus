{ Візуальне подання фізичних слів SENS: жодної власної семантики.
  Декодування й координати — виключно чинні wsm.t5m та wsm.physloc.
  Текст «ук» читається з pinned таблиць, не визначає тотожності. }
unit wsm.inspectorview;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.physloc, wsm.domain, wsm.bind;

const MaxVisualWords = 4096; { лише межа UI, не закон мови }

type
  EVisualInspect = class(Exception);
  TVisualWord = record
    Index: SizeInt;
    Key: TDomainKey;
    Bits: RawByteString;
    Position: TPhysicalWordSpan;
    Ukrainian: RawByteString;
  end;
  TVisualWords = array of TVisualWord;

procedure BuildVisualWords(const Physical: RawByteString;
  const Tables: TDomainSet; out ResultWords: TVisualWords);

implementation

procedure BuildVisualWords(const Physical: RawByteString;
  const Tables: TDomainSet; out ResultWords: TVisualWords);
var
  Words: TExactWords;
  Positions: TPhysicalWordSpans;
  Candidate: TVisualWords;
  I, Width: SizeInt;
  Row: TDomainRow;
begin
  SetLength(ResultWords, 0);
  DecodeT5MWithLocations(Physical, Words, Positions);
  if (Length(Words) > MaxVisualWords) or (Length(Words) <> Length(Positions)) then
    raise EVisualInspect.Create('забагато фізичних слів для візуального огляду');
  SetLength(Candidate, Length(Words));
  for I := 0 to High(Words) do begin
    Width := Length(Words[I]);
    { Сучасний фізичний огляд приймає D1..D9; D10 не ратифікуємо тут. }
    if (Width < 1) or (Width > 9) then
      raise EVisualInspect.Create('непідтримувана фізична ширина слова');
    if Length(Tables[Width]) <> (SizeInt(1) shl Width) then
      raise EVisualInspect.Create('неповна таблиця pinned домену');
    Candidate[I].Key := ExactKey(Words[I]);
    Candidate[I].Bits := Words[I];
    Candidate[I].Index := I + 1;
    Candidate[I].Position := Positions[I];
    if not DomainRowByKey(Tables[Width], Candidate[I].Key, Row) then
      raise EVisualInspect.Create('немає точних координат у pinned таблиці');
    Candidate[I].Ukrainian := Row.Ukrainian;
  end;
  ResultWords := Candidate; { один commit після повного успіху }
end;

end.
