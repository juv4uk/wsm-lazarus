{ Оракул SENS на Pascal — без Rust і без Zig.

  Навіщо: семантику мови перевіряє SENS. Досі для цього тягнули раст
  (`sens --t5m-files`) і зіг. Тут той самий механізм, але власним
  компілятором.

  Що це НЕ таке: не другий evaluator і не друга семантика. Уся робота
  йде через наявний TNativeEvaluator із wsm.nativeeval — того самого,
  що й у sens_uk_d3. Різниця лише в обгортці: sens_uk_d3 бере один
  вираз або файл з аргументів, а тут — ЦИКЛ по stdin, по формі на
  рядок. Це і є те, чого бракувало протоколові compare/.

  Протокол (той самий, що в equal.c):
    READY              — надруковано один раз, буфер скинуто
    <форма>            — по рядку зі stdin
    OK\t<результат>    — відповідь на кожну форму
    ERR\t<причина>     — відмова; вихід 2

  Межа названа прямо: оракул виконує те, що ДОПУСКАЄ наявний
  evaluator (шість D3-операцій). Чого він не допускає — те й тут
  буде ERR, а не тиха підміна. Це навмисно: оракул мусить відмовляти
  там, де мова відмовляє. }
program sens_oracle;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.nativeeval, wsm.source;

const
  MaxFormBytes = 1024 * 1024;

var
  ExitCode2: Integer;

procedure NapisatyStderr(const Tekst: UnicodeString);
var
  Bytes: UTF8String;
  Potik: THandleStream;
begin
  Bytes := UTF8Encode(Tekst + #10);
  Potik := THandleStream.Create(TextRec(StdErr).Handle);
  try
    if Length(Bytes) > 0 then Potik.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    Potik.Free;
  end;
end;

procedure SlightlyFlush;
begin
  Flush(Output);
end;

function Vykonaty(Vikonavets: TNativeEvaluator;
  const Form: RawByteString): RawByteString;
begin
  Result := Vikonavets.EvaluateSource(Form);
end;

procedure Zapustyty;
var
  Vikonavets: TNativeEvaluator;
  Liniya, Vidpovid: RawByteString;
  Nomery: Integer;
begin
  Nomery := 0;
  { Корінь pinned доменів — той самий, що в sens_uk_d3. Не вигадуємо
    іншого шляху й не шукаємо його по файловій системі. }
  Vikonavets := TNativeEvaluator.Create('external/sens');
  try
    WriteLn('READY');
    SlightlyFlush;
    while not EOF(Input) do begin
      ReadLn(Liniya);
      Inc(Nomery);
      { Порожні рядки пропускаємо: це не форма, а роздільник. }
      if Length(Trim(Liniya)) = 0 then Continue;
      if Length(Liniya) > MaxFormBytes then begin
        WriteLn('ERR', #9, 'форма перевищила 1 МіБ');
        SlightlyFlush;
        ExitCode2 := 2;
        Exit;
      end;
      try
        Vidpovid := Vykonaty(Vikonavets, Liniya);
        WriteLn('OK', #9, Vidpovid);
      except
        on E: ESourceError do begin
          WriteLn('ERR', #9, 'рядок=', E.Line, ' колонка=', E.ByteColumn,
            ' ', UTF8Decode(RawByteString(E.Message)));
          SlightlyFlush;
          ExitCode2 := 2;
          Exit;
        end;
        on E: Exception do begin
          WriteLn('ERR', #9, UTF8Decode(RawByteString(E.Message)));
          SlightlyFlush;
          ExitCode2 := 2;
          Exit;
        end;
      end;
      SlightlyFlush;
    end;
  finally
    Vikonavets.Free;
  end;
end;

begin
  ExitCode2 := 0;
  try
    Zapustyty;
  except
    on E: Exception do begin
      NapisatyStderr('ОРАКУЛ_ЗБІЙ причина=' +
        UTF8Decode(RawByteString(E.Message)));
      ExitCode2 := 3;
    end;
  end;
  Halt(ExitCode2);
end.
