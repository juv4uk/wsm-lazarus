{ Нативні позитивні та негативні pinned-свідки від SENS. }
program testprojections;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.projections;

{ Порівнюємо ТІЛЬКИ фізичні UTF-8 байти: FPC UnicodeString implicit
  conversion не повинне змінити pinned поверхні. }
function SameBytes(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B));
  if Result and (Length(A) > 0) then
    Result := CompareMem(@A[1], @B[1], Length(A));
end;

procedure Check(Condition: Boolean; const Why: String);
begin
  if not Condition then raise Exception.Create('ПОМИЛКА: ' + Why);
end;

function ReadText(const Path: String): RawByteString;
var S: TFileStream;
begin
  S := TFileStream.Create(Path, fmOpenRead);
  try
    SetLength(Result, SizeInt(S.Size));
    if Length(Result) > 0 then S.ReadBuffer(Result[1], Length(Result));
  finally
    S.Free;
  end;
end;

procedure ExpectFailure(const Source, Bits: RawByteString);
var V: TProjectionSet;
begin
  try
    V := ReadDomainProjections(Source, Bits);
    raise Exception.Create('ПОМИЛКА: прийнята невірна таблиця або координата ' +
      String(Bits) + ' / ' + String(V[0]));
  except
    on E: Exception do
      if Pos('ПОМИЛКА:', E.Message) = 1 then raise;
  end;
end;

var Root: String;
    S3, S7, S10, Bad: RawByteString;
    V: TProjectionSet;
begin
  if ParamCount <> 1 then raise Exception.Create('потрібен шлях до pinned SENS');
  Root := IncludeTrailingPathDelimiter(ParamStr(1));
  S3 := ReadText(Root + 'lib/domains/d3.lisp');
  S7 := ReadText(Root + 'lib/domains/d7.lisp');
  S10 := ReadText(Root + 'lib/domains/d10.lisp');

  V := ReadDomainProjections(S3, '001');
  Check((SameBytes(V[0], 'як-є')) and (SameBytes(V[1], 'як-є')) and
    (SameBytes(V[2], 'svarūpa')) and (SameBytes(V[3], 'quote')) and
    (SameBytes(V[4], 'QUOTE')), 'D3:001 pinned поверхні');

  V := ReadDomainProjections(S7, '0101000');
  Check((SameBytes(V[0], '"("')) and (SameBytes(V[1], '"("')) and
    (SameBytes(V[4], '()')), 'D7:0101000 текстова дужка, а не D2');

  V := ReadDomainProjections(S7, '0101001');
  Check((SameBytes(V[0], '")"')) and (SameBytes(V[3], '")"')),
    'D7:0101001 права дужка не є синтаксисом');

  V := ReadDomainProjections(S7, '0010110');
  Check((SameBytes(V[0], '()')) and (SameBytes(V[1], '()')) and
    (SameBytes(V[4], '()')), 'D7:0010110 SYN без друкованої поверхні');

  V := ReadDomainProjections(S10, '0000000110');
  Check((SameBytes(V[0], 'якщо')) and (SameBytes(V[1], 'якщо')) and
    (SameBytes(V[4], 'IF')), 'D10:0000000110 не означає викличність');

  ExpectFailure(S3, '0010');
  ExpectFailure(S3, '0x1');
  ExpectFailure(Copy(S3, 1, Length(S3)-1), '001');
  Bad := RawByteString(StringReplace(String(S3), '(san svarūpa)',
    '(sa svarūpa)', []));
  ExpectFailure(Bad, '001');
  Bad := RawByteString(StringReplace(String(S3), '  (001 ',
    '  (000 ', []));
  ExpectFailure(Bad, '001');
  Bad := S7 + RawByteString(Chr(255));
  ExpectFailure(Bad, '0010110');

  WriteLn('ШІСТЬ-ПРОЄКЦІЙ-ГАРАЗД pinned=D3/D7/D10 повнота=так D7-SYN=порожньо негативні=так');
end.
