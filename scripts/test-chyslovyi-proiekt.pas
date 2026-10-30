{ G3.32 / #149 — явна числова проєкція: домен обирає ЛЮДИНА, не значення.
  Перевіряємо механізм wsm.numericplane без GUI й без файлового I/O:
  те саме десяткове слово під різними явними доменами мусить дати
  різні фізичні слова, а кожне фізичне слово — зворотно те саме слово. }
program test_chyslovyi_proiekt;
{$mode objfpc}{$H+}
uses SysUtils, wsm.numericplane;

var
  Checks: Integer = 0;

procedure Check(Ok: Boolean; const Title: String);
begin
  Inc(Checks);
  if Ok then WriteLn('CHYSLOVIY-OK   ', Title)
  else begin
    WriteLn('CHYSLOVIY-ЗБІЙ ', Title);
    Halt(1);
  end;
end;

procedure ExpectError(const Title: String; const Body: TProcedure);
var
  Refused: Boolean;
begin
  Refused := False;
  try
    Body();
  except
    on E: ENumericPlaneError do Refused := True;
  end;
  Check(Refused, 'відмова: ' + Title);
end;

var
  Widths: array[0..4] of SizeInt = (12, 24, 48, 96, 192);
  Names: array[0..4] of String = ('D12', 'D24', 'D48', 'D96', 'D192');
  I, J: Integer;
  Bytes: array[0..4] of RawByteString;
  Number: TExplicitNumeric;
  DistinctWidths: Integer;

  procedure DoUnknownDomain;
  begin
    SelectedNumericDomain('D13');
  end;

  procedure DoOutOfRange;
  begin
    EncodeNumericDecimal('99999', 12);
  end;

  procedure DoWrongWidth;
  begin
    ReadNumericPhysical(Bytes[4], 12);   { D192-слово читаємо як D12 }
  end;

  procedure DoNotInSet;
  begin
    EncodeNumericDecimal('1', 13);
  end;

begin
  { 1-2. Пʼять доменів: round-trip і РІЗНІ фізичні ширини. }
  for I := 0 to 4 do begin
    Bytes[I] := EncodeNumericDecimal('-7', Widths[I]);
    Check(Length(Bytes[I]) > 0, Names[I] + ': фізичне слово не порожнє');
    Number := ReadNumericPhysical(Bytes[I], Widths[I]);
    Check(RenderNumericDecimal(Number) = '-7',
      Names[I] + ': round-trip -7 -> ' + RenderNumericDecimal(Number));
    WriteLn('CHYSLOVIY     ', Names[I], ' байтів=', Length(Bytes[I]));
  end;

  { Головне твердження #149: домен не виводиться зі значення.
    Якби виводився, усі пʼять дали б однакову ширину. }
  DistinctWidths := 0;
  for I := 0 to 4 do begin
    J := 0;
    while (J < I) and (Length(Bytes[J]) <> Length(Bytes[I])) do Inc(J);
    if J = I then Inc(DistinctWidths);
  end;
  Check(DistinctWidths = 5, 'пʼять доменів дають пʼять різних ширин');

  for I := 0 to 3 do
    Check(Bytes[I] <> Bytes[I + 1],
      Names[I] + ' і ' + Names[I + 1] + ': різні байти для того самого слова');

  { 3-5. Негативні випадки — відмова, а не тихе прийняття. }
  ExpectError('невідомий домен D13', @DoUnknownDomain);
  ExpectError('99999 у D12', @DoOutOfRange);
  ExpectError('D192-слово прочитане як D12', @DoWrongWidth);
  ExpectError('ширина 13 поза набором', @DoNotInSet);

  WriteLn('CHYSLOVIY-PROIEKT-PASS checks=', Checks);
end.
