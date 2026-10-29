{ G2.26: Шість зовнішніх проєкцій ОДНІЄЇ точної двійкової координати.
  Ні LISP-донор, ні D7-текст не є семантичним dispatch SENS.
  Джерело — pinned external/sens/lib/domains/dN.lisp, без власних законів. }
unit wsm.projections;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.domain;

type
  EProjectionError = class(Exception);
  TProjectionSet = array[0..5] of RawByteString;

function ReadDomainProjections(const Source, Bits: RawByteString): TProjectionSet;
function LoadPinnedProjections(const Root: String; const Bits: RawByteString): TProjectionSet;

implementation
uses Classes, wsm.source;

const
  { Колонки схеми, не реєстр законів або викличності. }
  Columns: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
  MaxTableBytes = 1024 * 1024;

procedure Fail(const Reason: String);
begin
  raise EProjectionError.Create('проєкцію відхилено: ' + Reason);
end;

function ViewValue(const Source: RawByteString; Value: TSourceNode): RawByteString;
begin
  if (Value = nil) or
     (Value.EndByteExclusive <= Value.ByteOffset) or
     (Value.ByteOffset < 1) or
     (Value.EndByteExclusive > Length(Source) + 1) then
    Fail('неправильні межі значення');
  { Буквальні байти UTF-8, із лапками та escape, а не чужа семантика. }
  Result := Copy(Source, Value.ByteOffset,
    Value.EndByteExclusive - Value.ByteOffset);
end;

function ReadDomainProjections(const Source, Bits: RawByteString): TProjectionSet;
var
  Key, RowKey: TDomainKey;
  Doc: TSourceDocument;
  Root, Row, Cell: TSourceNode;
  RowNo, ColNo, ExpectedCount: SizeInt;
  Candidate: TProjectionSet;
  Found: Boolean;
begin
  Key := ExactKey(Bits);
  ExpectedCount := SizeInt(1) shl Key.Width;
  for ColNo := 0 to 5 do Candidate[ColNo] := '';
  Found := False;
  Doc := ReadUkrainianSource(Source);
  try
    if Length(Doc.Forms) <> 1 then Fail('таблиця повинна мати одну форму');
    Root := Doc.Forms[0];
    if (Root.Kind <> skList) or (Length(Root.Children) <> ExpectedCount + 1) then
      Fail('неповна або надлишкова таблиця');
    if (Root.Children[0].Kind <> skAtom) or
       (Root.Children[0].Text <> 'domain-table-1') then
      Fail('непідтримана схема таблиці');
    for RowNo := 1 to ExpectedCount do begin
      Row := Root.Children[RowNo];
      if (Row.Kind <> skList) or (Length(Row.Children) <> 7) then
        Fail('неправильний рядок таблиці');
      if Row.Children[0].Kind <> skAtom then
        Fail('відсутня двійкова координата');
      RowKey := ExactKey(Row.Children[0].Text);
      if (RowKey.Width <> Key.Width) or (RowKey.Bits <> RowNo - 1) then
        Fail('порушено ширину, порядок або унікальність координат');
      for ColNo := 0 to 5 do begin
        Cell := Row.Children[ColNo + 1];
        if (Cell.Kind <> skList) or (Length(Cell.Children) <> 2) or
           (Cell.Children[0].Kind <> skAtom) or
           (Cell.Children[0].Text <> Columns[ColNo]) then
          Fail('колонки проєкцій не відповідають pinned схемі');
        if SameKey(RowKey, Key) then
          Candidate[ColNo] := ViewValue(Source, Cell.Children[1]);
      end;
      if SameKey(RowKey, Key) then Found := True;
    end;
    if not Found then Fail('координату не знайдено');
    { Публікуємо лише після перевірки ВСІЄЇ таблиці. }
    Result := Candidate;
  finally
    Doc.Free;
  end;
end;

function LoadPinnedProjections(const Root: String; const Bits: RawByteString): TProjectionSet;
var
  Key: TDomainKey;
  FileName: String;
  Stream: TFileStream;
  Source: RawByteString;
begin
  Key := ExactKey(Bits);
  FileName := IncludeTrailingPathDelimiter(Root) + 'lib/domains/d' +
    IntToStr(Key.Width) + '.lisp';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size <= 0) or (Stream.Size > MaxTableBytes) then
      Fail('розмір pinned таблиці поза межею');
    SetLength(Source, SizeInt(Stream.Size));
    Stream.ReadBuffer(Source[1], Length(Source));
  finally
    Stream.Free;
  end;
  Result := ReadDomainProjections(Source, Bits);
end;
end.
