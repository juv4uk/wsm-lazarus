{ G1.12: потокове широке фізичне D2, без числових законів. }
program test_t5m_wide_stream;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.t5madmission;

procedure Check(Condition: Boolean; const Why: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'ШИРОКИЙ-ПОТІК-ПОМИЛКА: ', Why);
    Halt(1);
  end;
end;

function Pack(const Values: array of RawByteString): RawByteString;
var W: TExactWords; I: SizeInt;
begin
  SetLength(W, Length(Values));
  for I := 0 to High(Values) do W[I] := Values[I];
  Result := EncodeT5M(W);
end;

function StreamRead(const Physical: RawByteString; Wide: Boolean): TD2Document;
var S: TMemoryStream;
begin
  S := TMemoryStream.Create;
  try
    if Length(Physical) <> 0 then S.WriteBuffer(Physical[1], Length(Physical));
    S.Position := 0;
    if Wide then Result := ReadCheckedD2WideStream(S)
    else Result := ReadCheckedD2Stream(S);
  finally
    S.Free;
  end;
end;

procedure SameNode(A, B: TD2Node);
var I: SizeInt;
begin
  Check((A <> nil) and (B <> nil), 'відсутній вузол');
  Check((A.Kind = B.Kind) and (A.WordIndex = B.WordIndex)
    and (A.Width = B.Width) and (A.Bits = B.Bits),
    'втрачено exact ширину, біти або індекс');
  Check(Length(A.Children) = Length(B.Children), 'пошкоджено дерево');
  for I := 0 to High(A.Children) do SameNode(A.Children[I], B.Children[I]);
end;

procedure CompareWide(const Physical: RawByteString);
var Reference, Streamed: TD2Document; I: SizeInt;
begin
  Reference := ReadD2T5MWide(Physical);
  try
    Streamed := StreamRead(Physical, True);
    try
      Check(Length(Reference.Roots) = Length(Streamed.Roots),
        'змінена кількість коренів');
      for I := 0 to High(Reference.Roots) do
        SameNode(Reference.Roots[I], Streamed.Roots[I]);
    finally
      Streamed.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure Reject(const Physical: RawByteString; Wide: Boolean;
  const Why: String);
var D: TD2Document; Rejected: Boolean;
begin
  D := nil; Rejected := False;
  try
    D := StreamRead(Physical, Wide);
  except
    on E: ET5MAdmissionError do Rejected := True;
    on E: ET5MError do Rejected := True;
    on E: ED2SourceError do Rejected := True;
  end;
  D.Free;
  Check(Rejected, Why + ' прийнято');
end;

var
  W: TExactWords;
  I: SizeInt;
  Physical: RawByteString;
  Doc: TD2Document;
begin
  { Новий широкій API не змінює вузький W1–W9. }
  Physical := Pack(['10', '101', '0', '000', '01']);
  CompareWide(Physical);
  Doc := StreamRead(Physical, False);
  Doc.Free;

  for I := 12 to 192 do
    if (I = 12) or (I = 13) or (I = 24) or
       (I = 48) or (I = 96) or (I = 192) then begin
      Physical := Pack(['10', StringOfChar('0', I - 1) + '1', '01']);
      CompareWide(Physical);
      Reject(Physical, False, 'старий вузький reader прийняв W' + IntToStr(I));
    end;
  { W13 є лише непрозорим словом, це не нова ратифікація D13. }
  CompareWide(Pack(['10', '1', '11', '0', '01'])); { крапкова пара }

  { Приблизно 6 КіБ: декодування через фізичні межі чанків 4096. }
  SetLength(W, 3600);
  for I := 0 to High(W) do W[I] := '1010101';
  Physical := EncodeT5M(W);
  Check(Length(Physical) > 4096, 'тест не перетнув межі чанка');
  CompareWide(Physical);

  Reject('', True, 'порожній потік');
  Reject(#243, True, 'недопустимий байт');
  Reject(#242, True, 'суцільне заповнення');
  Reject(#72, True, 'повторний роздільник');
  Reject(Pack([StringOfChar('0', 193)]), True, 'W193');
  Reject(Pack(['10', '1']), True, 'відкрита D2-форма');
  Reject(Pack(['10', '11', '1', '01']), True, 'крапка без голови');
  SetLength(W, MaxD2Words + 1);
  for I := 0 to High(W) do W[I] := '1';
  Reject(EncodeT5M(W), True, 'перевищення кількості слів');

  Doc := nil;
  try
    Doc := ReadCheckedD2WideStream(nil);
  except on E: ET5MAdmissionError do begin end; end;
  Check(Doc = nil, 'nil-потік прийнято');
  Doc.Free;

  WriteLn('ШИРОКИЙ-ПОТІК-ГАРАЗД: FPC=T5M W1–W192 D2=структура ',
    'width=точний old-W9=незмінний негативні=відмова ',
    'D12+=не-числова-інтерпретація');
end.
