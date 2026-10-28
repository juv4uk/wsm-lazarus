{ Український CLI фізичного виконання вже допущеного початкового Core4.
  Обидва файли — канонічні бінарні T5M .sens, не текстова проєкція.
  Усі мовні операції виконує чинний wsm.core4runtime, не цей адаптер. }
program senscore4vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m;

function Укр(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

function ПравильнаКоманда: Boolean;
begin
  Result := (ParamCount = 4) and
    (RawByteString(ParamStr(1)) = Укр('--виконати')) and
    (LowerCase(ExtractFileExt(ParamStr(3))) = '.sens') and
    (LowerCase(ExtractFileExt(ParamStr(4))) = '.sens');
end;

procedure Виконати;
var
  Джерело, Призначення: String;
  Потік: TFileStream;
  Машина: TCore4Runtime;
  Вхід, Вихід: RawByteString;
  Слова: TExactWords;
  Тимчасовий: String;
begin
  Джерело := ParamStr(3);
  Призначення := ParamStr(4);
  Тимчасовий := '';
  if FileExists(Призначення) or DirectoryExists(Призначення) then
    raise Exception.Create(Укр('вихідний файл уже існує'));
  Потік := TFileStream.Create(Джерело, fmOpenRead or fmShareDenyWrite);
  try
    if (Потік.Size < 1) or (Потік.Size > MAX_T5M_FILE_BYTES) then
      raise Exception.Create(Укр('недопустимий розмір двійкового входу'));
    SetLength(Вхід, SizeInt(Потік.Size));
    Потік.ReadBuffer(Вхід[1], Length(Вхід));
  finally
    Потік.Free;
  end;

  Машина := TCore4Runtime.Create(ParamStr(2));
  try
    Вихід := Машина.ExecutePhysicalCall(Вхід);
  finally
    Машина.Free;
  end;
  { Фізичну структуру кінцевого слова перевіряє існуючий декодер.
    Жодної інтерпретації D1/D24, арифметики чи dispatch за spelling. }
  DecodeT5M(Вихід, Слова);
  if Length(Слова) <> 1 then
    raise Exception.Create(Укр('неоднозначна кількість вихідних слів'));

  try
    Тимчасовий := GetTempFileName(
      ExtractFilePath(ExpandFileName(Призначення)), 'cr4');
    if Тимчасовий = '' then
      raise Exception.Create(Укр('не вдалося створити тимчасовий файл'));
    Потік := TFileStream.Create(Тимчасовий, fmCreate);
    try
      Потік.WriteBuffer(Вихід[1], Length(Вихід));
    finally
      Потік.Free;
    end;
    if FileExists(Призначення) or DirectoryExists(Призначення) then
      raise Exception.Create(Укр('вихідний шлях зайнято під час запису'));
    if not RenameFile(Тимчасовий, Призначення) then
      raise Exception.Create(Укр('атомарне завершення запису не вдалося'));
    Тимчасовий := '';
  finally
    if (Тимчасовий <> '') and FileExists(Тимчасовий) then
      DeleteFile(Тимчасовий);
  end;
  WriteLn(Укр('CORE4-ВИКОНАНО двійкові-байти='), Length(Вихід),
    Укр(' закони=pinned-SENS результат=.sens'));
end;

begin
  ExitCode := 0;
  if not ПравильнаКоманда then
  begin
    WriteLn(StdErr, Укр(
      'Використання: senscore4vykon --виконати КОРІНЬ виклик.sens результат.sens'));
    ExitCode := 64;
  end
  else
    try
      Виконати;
    except
      on E: Exception do
      begin
        WriteLn(StdErr, Укр('CORE4-ПОМИЛКА: '), E.Message);
        ExitCode := 2;
      end;
    end;
end.
