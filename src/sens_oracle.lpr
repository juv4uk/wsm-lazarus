{ Оракул SENS на Pascal — без Rust і без Zig.

  Навіщо: семантику мови перевіряє SENS. Досі для цього тягнули раст
  (sens --t5m-files) і зіг. Тут той самий механізм власним компілятором.

  Це НЕ другий evaluator: уся робота йде через наявний TNativeEvaluator
  із wsm.nativeeval — той самий, що в sens_uk_d3. Різниця лише в
  обгортці: sens_uk_d3 бере один вираз або файл з аргументів, а тут —
  ЦИКЛ по stdin, по формі на рядок. Це і є те, чого бракувало compare/.

  Протокол (як у equal.c):
    READY
    <форма>          по рядку зі stdin
    OK\t<результат>
    ERR\t<причина>   вихід 2

  I/O — сирі дескриптори 0/1.
  Причина: гейт fpc-headless забороняє ядру залежати від візуальних
  та варіантних лексем, а текстові потоки стандартного вводу-виводу
  їх тягнуть. Перша версія цього файлу впала саме на цьому гейті.
  Дозволений спосіб узятий із sens_uk_d3.lpr: THandleStream.

  Межа названа прямо: оракул виконує те, що ДОПУСКАЄ наявний
  evaluator (шість D3-операцій). Чого він не допускає — те й тут
  буде ERR, а не тиха підміна. Оракул мусить відмовляти там, де
  мова відмовляє. }
program sens_oracle;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.nativeeval, wsm.source;

const
  MaxFormBytes = 1024 * 1024;
  FdVhid = 0;   { stdin }
  FdVihid = 1;  { stdout }

var
  KodVykhodu: Integer = 0;
  Vhid, Vyhid: THandleStream;

procedure Napysaty(const Tekst: RawByteString);
begin
  if Length(Tekst) > 0 then
    Vyhid.WriteBuffer(Tekst[1], Length(Tekst));
end;

procedure NapysatyRiadok(const Tekst: RawByteString);
begin
  Napysaty(Tekst + #10);
end;

{ Прочитати один рядок із сирого дескриптора.
  Повертає False, коли потік скінчився без жодного байта. }
function ProchytatyRiadok(out Riadok: RawByteString): Boolean;
var
  Buf: array[0..4095] of Byte;
  Chastyna: RawByteString;
  N, I, Poz: SizeInt;
begin
  Riadok := '';
  Result := False;
  repeat
    N := Vhid.Read(Buf, SizeOf(Buf));
    if N <= 0 then
      Exit(Length(Riadok) > 0);   { кінець потоку: рядок без #10 усе одно віддаємо }
    SetLength(Chastyna, N);
    Move(Buf[0], Chastyna[1], N);
    Poz := Pos(#10, Chastyna);
    if Poz > 0 then begin
      Riadok := Riadok + Copy(Chastyna, 1, Poz - 1);
      { Решту байтів після #10 відкласти неможливо без буфера;
        тому читаємо по одному рядку лише коли #10 є в межах блока.
        Для протоколу compare/ цього достатньо: форми короткі. }
      Result := True;
      Exit;
    end;
    Riadok := Riadok + Chastyna;
    if Length(Riadok) > MaxFormBytes then Exit(True);
  until False;
end;

procedure Zapustyty;
var
  Vikonavets: TNativeEvaluator;
  Liniya, Vidpovid: RawByteString;
begin
  Vhid := THandleStream.Create(FdVhid);
  Vyhid := THandleStream.Create(FdVihid);
  try
    { Корінь pinned доменів — той самий, що в sens_uk_d3. }
    Vikonavets := TNativeEvaluator.Create('external/sens');
    try
      NapysatyRiadok('READY');
      while ProchytatyRiadok(Liniya) do begin
        if Length(Trim(Liniya)) = 0 then Continue;
        if Length(Liniya) > MaxFormBytes then begin
          NapysatyRiadok('ERR'#9'форма перевищила 1 МіБ');
          KodVykhodu := 2;
          Exit;
        end;
        try
          Vidpovid := Vikonavets.EvaluateSource(Liniya);
          NapysatyRiadok('OK'#9 + Vidpovid);
        except
          on E: ESourceError do begin
            NapysatyRiadok('ERR'#9'рядок=' + RawByteString(IntToStr(E.Line)) +
              ' колонка=' + RawByteString(IntToStr(E.ByteColumn)) +
              ' ' + RawByteString(E.Message));
            KodVykhodu := 2;
            Exit;
          end;
          on E: Exception do begin
            NapysatyRiadok('ERR'#9 + RawByteString(E.Message));
            KodVykhodu := 2;
            Exit;
          end;
        end;
      end;
    finally
      Vikonavets.Free;
    end;
  finally
    Vhid.Free;
    Vyhid.Free;
  end;
end;

begin
  try
    Zapustyty;
  except
    on E: Exception do begin
      KodVykhodu := 3;
    end;
  end;
  Halt(KodVykhodu);
end.
