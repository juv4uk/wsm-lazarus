{ Фізичний командний інтерфейс допуску закріпленого Core4.
  SIR1 залишається приватним структурним форматом, не канонічним .sens.
  Мовні закони, виконання та допустимість викликів тут не визначаються. }
program senscore4;
{$mode objfpc}{$H+}

uses SysUtils, Classes, wsm.core4source, wsm.compiler;

procedure Відмова(const Текст: String);
begin
  raise Exception.Create(Текст);
end;

procedure ЗаписатиБезПсування(const Шлях: String; Джерело: TMemoryStream);
var
  Тимчасовий: String;
  Вихід: TFileStream;
  Створено: Boolean;
begin
  if Шлях = '' then Відмова('не вказано вихідний шлях');
  if FileExists(Шлях) then Відмова('вихідний файл уже існує');
  Тимчасовий := Шлях + '.tmp';
  if FileExists(Тимчасовий) then Відмова('тимчасовий файл уже існує');
  Створено := False;
  try
    Вихід := TFileStream.Create(Тимчасовий, fmCreate);
    Створено := True;
    try
      Джерело.Position := 0;
      Вихід.CopyFrom(Джерело, Джерело.Size);
    finally
      Вихід.Free;
    end;
    if FileExists(Шлях) then Відмова('вихідний шлях зайнято під час запису');
    if not RenameFile(Тимчасовий, Шлях) then
      Відмова('не вдалось завершити запис вихідного файлу');
    Створено := False;
  finally
    if Створено then DeleteFile(Тимчасовий);
  end;
end;

procedure Виконати;
var
  Дія, Корінь: String;
  Буфер: TMemoryStream;
  Статистика: TSIR1Stats;
  Сирий: RawByteString;
begin
  if (ParamCount <> 2) and (ParamCount <> 3) then
    Відмова('використання: senscore4 --check КОРІНЬ або --emit-ir КОРІНЬ ФАЙЛ');
  Дія := ParamStr(1);
  Корінь := ParamStr(2);
  if Корінь = '' then Відмова('порожній корінь репозиторію');
  if (Дія = '--check') and (ParamCount <> 2) then
    Відмова('для перевірки потрібні рівно два аргументи');
  if (Дія = '--emit-ir') and (ParamCount <> 3) then
    Відмова('для виводу потрібні рівно три аргументи');
  if (Дія <> '--check') and (Дія <> '--emit-ir') then
    Відмова('невідома дія');
  { Наявний перевірений завантажувач сам обмежує байти, валідує
    UTF-8/структуру, а також відкидає некоректний SIR1 до видачі. }
  Сирий := ReadPinnedCore4(Корінь);
  Буфер := TMemoryStream.Create;
  try
    CompilePinnedCore4Structure(Корінь, Буфер);
    Буфер.Position := 0;
    InspectSIR1(Буфер, Статистика);
    if Дія = '--emit-ir' then
      ЗаписатиБезПсування(ParamStr(3), Буфер);
    WriteLn('CORE4-ДОПУСК-ГАРАЗД байти=', Length(Сирий),
      ' структура=', Буфер.Size,
      ' форми-списки=', Статистика.ListOpens,
      ' атоми=', Статистика.Atoms,
      ' рядки=', Статистика.Strings,
      ' виконання=ні');
  finally
    Буфер.Free;
  end;
end;

begin
  try
    Виконати;
  except
    on E: ECore4SourceError do begin
      WriteLn(StdErr, 'CORE4-ДОПУСК-ПОМИЛКА ', E.Message,
        ' байт=', E.ByteOffset, ' рядок=', E.Line,
        ' стовпець=', E.ByteColumn);
      Halt(2);
    end;
    on E: Exception do begin
      WriteLn(StdErr, 'CORE4-ДОПУСК-ПОМИЛКА ', E.Message);
      Halt(2);
    end;
  end;
end.
