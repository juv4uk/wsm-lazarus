{ Core1.6 CLI: фізичний перелік допущених визначень Core1 і виконання
  одного канонічного .sens виклику. Це не REPL і не повний Core1.
  Режими (латинські, щоб розбір argv не залежав від локалі):
    --list КОРІНЬ          перелік допущених DEFINE з точними D7-бітами
    --run  КОРІНЬ ФАЙЛ     виконати один фізичний виклик із файла
  На відмові stdout порожній, діагностика йде в stderr, код 2. }
program senscore1selektor;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1selektor;

const
  MaxCallFileBytes = 65536;

procedure Fail(const MessageText: UnicodeString);
begin
  Writeln(StdErr, 'CORE1-SELEKTOR-ВІДМОВА: ', MessageText);
  Writeln(StdErr, 'CORE1-SELEKTOR-REFUSED');
  Halt(2);
end;

function ReadCall(const Filename: String): RawByteString;
var
  Stream: TFileStream;
begin
  Result := '';
  try
    Stream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do Fail('не відкрито фізичний виклик: ' + E.Message);
  end;
  try
    if (Stream.Size <= 0) or (Stream.Size > MaxCallFileBytes) then
      Fail('фізичний виклик порожній або завеликий');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

{ Точні біти без розділювачів: один D7-ключ — один рядок.
  Це координата, не назва і не opcode. }
function BitsOf(const Physical: RawByteString): String;
var
  Words: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(Physical, Words);
  Result := '';
  for I := 0 to High(Words) do begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + String(Words[I]);
  end;
end;

var
  Mode, Root, Filename: String;
  Selektor: TCore1Selektor;
  I: SizeInt;
  Answer: RawByteString;
  Done: Boolean;
begin
  Done := False;
  if ParamCount < 2 then begin
    Writeln(StdErr, 'вжиток: senscore1selektor --list КОРІНЬ');
    Writeln(StdErr, '        senscore1selektor --run КОРІНЬ ФАЙЛ');
    Halt(64);
  end;
  Mode := ParamStr(1);
  Root := ParamStr(2);
  Selektor := nil;
  try
    try
      Selektor := TCore1Selektor.Create(Root);
    except
      on E: Exception do Fail('pinned Core1 не допущено: ' + E.Message);
    end;
    if Mode = '--list' then begin
      Writeln('CORE1-SELEKTOR-ДОПУЩЕНО ', Selektor.AdmittedCount);
      Writeln('CORE1-SELEKTOR-ADMITTED ', Selektor.AdmittedCount);
      for I := 0 to Selektor.AdmittedCount - 1 do
        Writeln('CORE1-SELEKTOR-DEF ', I, ' D7=',
          String(Selektor.AdmittedName(I)), ' body=',
          Selektor.AdmittedBodyText(I), ' mech=',
          Selektor.AdmittedMechanismText(I));
      Done := True;
    end;
    if Done then begin
      Selektor.Free;
      Selektor := nil;
      Halt(0);
    end;
    if Mode <> '--run' then Fail('невідомий режим: ' + Mode);
    if ParamCount < 3 then Fail('потрібен шлях фізичного виклику');
    Filename := ParamStr(3);
    try
      Answer := Selektor.ExecutePhysicalCall(ReadCall(Filename));
    except
      on E: Exception do Fail('виклик відхилено: ' + E.Message);
    end;
    Writeln('CORE1-SELEKTOR-РЕЗУЛЬТАТ ', BitsOf(Answer));
    Writeln('CORE1-SELEKTOR-RESULT ', BitsOf(Answer));
  finally
    Selektor.Free;
  end;
end.
