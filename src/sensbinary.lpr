{ G2.8: фізична діагностика двійкового зв'язування без надання викличності.
  Єдина семантична влада — pinned SENS, а не цей Pascal CLI. }
program sensbinary;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.domain,
  wsm.bind, wsm.binarybind;

type
  EBinaryCLIError = class(Exception);

function ReadPhysical(const FileName: String): RawByteString;
var F: TFileStream;
begin
  if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
    raise EBinaryCLIError.Create('очікується фізичний файл .sens, не проєкція .lisp');
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
      raise EBinaryCLIError.Create('порожній або завеликий фізичний файл');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

procedure Analyze(const FileName: String);
var
  Physical: RawByteString;
  Tables: TDomainSet;
  Bound: TBinaryWords;
  I: SizeInt;
  EmptyLabel, Surface: RawByteString;
begin
  Physical := ReadPhysical(FileName);
  { Ні українське написання, ні історичний SID8 не визначають координату. }
  LoadPinnedDomains('external/sens', Tables);
  BindT5MBinary(Physical, Tables, Bound);
  { Весь T5M, D2 та доменний ввід перевірено до першого байта stdout. }
  for I := 0 to High(Bound) do begin
    if Bound[I].IsEmpty then EmptyLabel := 'так' else EmptyLabel := 'ні';
    Surface := Bound[I].Ukrainian;
    if Surface = '' then Surface := 'немає';
    WriteLn('ДВІЙКОВЕ-СЛОВО індекс=', Bound[I].WordIndex,
      ' форма=', Bound[I].RootIndex, ' домен=', Bound[I].Key.Width,
      ' біти=', KeyBits(Bound[I].Key), ' порожнє=', EmptyLabel,
      ' ук=', Surface);
  end;
  WriteLn('ДВІЙКОВЕ-ПІДСУМОК слів=', Length(Bound),
    ' викличність=не-перевірено виконання=не-перевірено');
end;

begin
  if (ParamCount <> 2) or (ParamStr(1) <> '--аналіз') then begin
    WriteLn(StdErr, 'ВИКОРИСТАННЯ: sensbinary --аналіз файл.sens');
    Halt(64);
  end;
  try
    Analyze(ParamStr(2));
  except
    on E: ED2SourceError do begin
      WriteLn(StdErr, 'ДВІЙКОВЕ-ПОМИЛКА слово=', E.WordIndex, ': ', E.Message);
      Halt(1);
    end;
    on E: Exception do begin
      WriteLn(StdErr, 'ДВІЙКОВЕ-ПОМИЛКА ', E.Message);
      Halt(1);
    end;
  end;
end.
