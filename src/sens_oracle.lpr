{ Обмежений D3 stdin-адаптер на Free Pascal.
  Назву sens_oracle збережено для сумісності з наявним compare/протоколом,
  але він НЕ є незалежним оракулом семантики SENS. Закони належать тільки
  pinned juv4uk/sens, а виконання — вже існуючому TNativeEvaluator.
  Цикл по stdin не додає мовної семантики та не підтримує всю Core1/Core4.

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
  { Байтова черга тільки host-протоколу: жодних D7/SENS значень.
    Статична місткість 4096, існує до завершення процесу; невикористані
    після LF байти залишаються для наступного виклику читача. }
  VhidBufer: array[0..4095] of Byte;
  VhidDovzhyna: SizeInt = 0;
  VhidPozytsiia: SizeInt = 0;

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
{ Вхід: один LF-рядок UTF-8 як сирі байти, не канонічна .sens.
  Параметр out Riadok — власний керований RawByteString до 1 МіБ.
  Вихід True: один повний рядок або фінальний фрагмент на EOF;
  False: чистий EOF. Переповнення повертає довжину Max+1 для
  існуючого fail-closed шляху (код 2), без жодного повторного читання.
  Питання: (1) чому LF зберігає наступні байти? (2) чому Move не змінює
  UTF-8? (3) де межа пам'яті? (4) що робиться при EOF без LF?
  (5) чому це не новий SENS reader? }
function ProchytatyRiadok(out Riadok: RawByteString): Boolean;
var
  Pochatok, Dodaty, Bulo: SizeInt;
begin
  Riadok := '';
  Result := False;
  while True do begin
    if VhidPozytsiia = VhidDovzhyna then begin
      VhidDovzhyna := Vhid.Read(VhidBufer, SizeOf(VhidBufer));
      VhidPozytsiia := 0;
      if VhidDovzhyna <= 0 then Exit(Length(Riadok) > 0);
    end;
    Pochatok := VhidPozytsiia;
    while (VhidPozytsiia < VhidDovzhyna) and
          (VhidBufer[VhidPozytsiia] <> 10) do
      Inc(VhidPozytsiia);
    Dodaty := VhidPozytsiia - Pochatok;
    Bulo := Length(Riadok);
    if Dodaty > MaxFormBytes - Bulo then begin
      SetLength(Riadok, MaxFormBytes + 1);
      Exit(True);
    end;
    if Dodaty > 0 then begin
      SetLength(Riadok, Bulo + Dodaty);
      Move(VhidBufer[Pochatok], Riadok[Bulo + 1], Dodaty);
    end;
    if VhidPozytsiia < VhidDovzhyna then begin
      Inc(VhidPozytsiia); { спожити LF; решту поточного блока зберегти }
      Exit(True);
    end;
  end;
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
        { Розмір контролюється ДО відкидання порожніх рядків:
          1 МіБ+ пробілів також є перевищенням host-квоти. }
        if Length(Liniya) > MaxFormBytes then begin
          NapysatyRiadok('ERR'#9'форма перевищила 1 МіБ');
          KodVykhodu := 2;
          Exit;
        end;
        if Length(Trim(Liniya)) = 0 then Continue;
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
