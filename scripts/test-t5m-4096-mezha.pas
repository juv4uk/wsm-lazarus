{ G1.57 — фізична межа читання 4096 байтів, не новий закон SENS.
  W24 є opaque exact word; лише pinned T5M/D2 визначають форму.
  Потік позичений reader-ом, TD2Document належить викликачеві. }
program test_t5m_4096_mezha;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.t5madmission;

type
  TPortionedStream = class(TMemoryStream)
  private
    FPortion: Longint;
    FCalls: SizeInt;
  public
    constructor Create(const Physical: RawByteString; Portion: Longint);
    function Read(var Buffer; Count: Longint): Longint; override;
    property Calls: SizeInt read FCalls;
  end;

constructor TPortionedStream.Create(const Physical: RawByteString;
  Portion: Longint);
begin
  inherited Create;
  if Portion < 1 then raise Exception.Create('нульова порція');
  FPortion := Portion;
  FCalls := 0;
  if Length(Physical) > 0 then WriteBuffer(Physical[1], Length(Physical));
  Position := 0;
end;

function TPortionedStream.Read(var Buffer; Count: Longint): Longint;
begin
  Inc(FCalls);
  if Count > FPortion then Count := FPortion;
  Result := inherited Read(Buffer, Count);
end;

procedure Check(Ok: Boolean; const Reason: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'T5M-4096-FAIL: ', Reason);
    Halt(1);
  end;
end;

procedure CheckSpans(const Actual, Reference: TPhysicalWordSpans);
var I: SizeInt;
begin
  Check(Length(Actual) = Length(Reference), 'кількість exact координат');
  for I := 0 to High(Reference) do
    Check((Actual[I].WordIndex = Reference[I].WordIndex) and
      (Actual[I].TritStart = Reference[I].TritStart) and
      (Actual[I].TritEnd = Reference[I].TritEnd) and
      (Actual[I].ByteStart = Reference[I].ByteStart) and
      (Actual[I].ByteEnd = Reference[I].ByteEnd) and
      (Actual[I].IsEOF = Reference[I].IsEOF),
      'не збігається фізичний span ' + IntToStr(I + 1));
end;

procedure CheckGood(const Physical: RawByteString; Portion: Longint;
  Reference: TD2Document; const RefSpans: TPhysicalWordSpans);
var Input: TPortionedStream;
    D: TD2Document;
    Spans: TPhysicalWordSpans;
    I: SizeInt;
begin
  Input := TPortionedStream.Create(Physical, Portion);
  D := nil;
  try
    D := ReadCheckedD2WideLocatedStream(Input, Spans);
    Check((Length(D.Roots) = 1000) and
      (Length(D.Roots) = Length(Reference.Roots)),
      'не збережено тисячу фізичних D2 коренів');
    CheckSpans(Spans, RefSpans);
    for I := 0 to High(D.Roots) do
      Check((D.Roots[I].Width = 24) and
        (D.Roots[I].WordIndex = I + 1) and
        (D.Roots[I].Bits = Reference.Roots[I].Bits) and
        (D.Roots[I].Kind = Reference.Roots[I].Kind),
        'не збережено точний W24 атом ' + IntToStr(I + 1));
    Check(Input.Calls >= 2, 'не перевірено межу порцій TStream');
  finally
    D.Free;
    Input.Free;
  end;
end;

procedure CheckBad(const Physical: RawByteString; Portion: Longint;
  const RefSpans: TPhysicalWordSpans);
var Input: TPortionedStream;
    D: TD2Document;
    Spans: TPhysicalWordSpans;
    Rejected: Boolean;
begin
  Input := TPortionedStream.Create(Physical, Portion);
  D := nil;
  Rejected := False;
  SetLength(Spans, 1);
  Spans[0] := RefSpans[0];
  try
    try
      D := ReadCheckedD2WideLocatedStream(Input, Spans);
    except
      on E: ET5MAdmissionError do begin
        Rejected := True;
        Check((E.ByteOffset = 4096) and (E.TritOffset = 20480) and
          (E.WordIndex = 820),
          'неправильна адреса зіпсованого байта на межі 4096');
        Check(E.Message <> '', 'втрачено діагностику');
      end;
    end;
    Check(Rejected and (D = nil), 'зіпсоване T5M джерело прийнято');
    Check(Length(Spans) = 0, 'після помилки залишено старі адреси');
  finally
    D.Free;
    Input.Free;
  end;
end;

var
  Words: TExactWords;
  Good, Bad: RawByteString;
  Reference: TD2Document;
  RefSpans: TPhysicalWordSpans;
  I: SizeInt;
begin
  SetLength(Words, 1000);
  for I := 0 to High(Words) do
    Words[I] := RawByteString(StringOfChar('0', 24));
  Good := EncodeT5M(Words);
  { 1000*24 бітів, 999 роздільників та 1 кінцевий трит: 5000 байтів. }
  Check(Length(Good) = 5000, 'неправильна довжина pinned T5M');
  Reference := ReadD2WideWithPhysicalLocations(Good, RefSpans);
  try
    Check(Length(RefSpans) = 1000, 'неповне фізичне еталонне читання');
    CheckGood(Good, 1, Reference, RefSpans);
    CheckGood(Good, 4095, Reference, RefSpans);
    CheckGood(Good, 4096, Reference, RefSpans);
    CheckGood(Good, 4097, Reference, RefSpans);

    Bad := Good;
    Bad[4097] := Chr(243);
    CheckBad(Bad, 4095, RefSpans);
    CheckBad(Bad, 4096, RefSpans);
    CheckBad(Bad, 4097, RefSpans);
    CheckGood(Good, 4096, Reference, RefSpans);
  finally
    Reference.Free;
  end;
  WriteLn('VERIFIED-T5M-4096-PASS positive=4 negative=3 ',
    'byte=4096 trit=20480 word=820 recovery=1 energy=NOT-MEASURED');
end.

{ Типи/час життя: TPortionedStream — owned у тесті, reader тільки
  позичає TStream; TD2Document — owned і Free у finally; Spans — owned
  динамічний масив координат; фізичний результат не стає значенням D24.
  Питання: 1) Чому W24 не означає D24?
  2) Чому 4097-байтова порція обмежена внутрішнім 4096-byte Chunk?
  3) Чому фізична адреса містить і байт, і трит, і індекс слова?
  4) Чому старий out Spans не може пережити фізичну відмову?
  5) Хто звільняє потік та результати AST? }
