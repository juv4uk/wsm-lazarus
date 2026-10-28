{ Ukrаїнський CLI фізичного виконання вже допущеного початкового Core4.
  Обидва файли — канонічні бінарні T5M .sens, не текстова проєкція.
  Усі мовні операції виконує чинний wsm.core4runtime, не цей адаптер. }
program senscore4vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m;

function Ukr(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

function ValidCommand: Boolean;
begin
  Result := (ParamCount = 4) and
    (RawByteString(ParamStr(1)) = Ukr('--виконати')) and
    (LowerCase(ExtractFileExt(ParamStr(3))) = '.sens') and
    (LowerCase(ExtractFileExt(ParamStr(4))) = '.sens');
end;

procedure Execute;
var
  InputPath, OutputPath: String;
  Stream: TFileStream;
  Runtime: TCore4Runtime;
  Physical, ResultPhysical: RawByteString;
  Words: TExactWords;
  TempPath: String;
begin
  InputPath := ParamStr(3);
  OutputPath := ParamStr(4);
  TempPath := '';
  if FileExists(OutputPath) or DirectoryExists(OutputPath) then
    raise Exception.Create(Ukr('вихідний файл уже існує'));
  Stream := TFileStream.Create(InputPath, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 1) or (Stream.Size > MAX_T5M_FILE_BYTES) then
      raise Exception.Create(Ukr('недопустимий розмір двійкового входу'));
    SetLength(Physical, SizeInt(Stream.Size));
    Stream.ReadBuffer(Physical[1], Length(Physical));
  finally
    Stream.Free;
  end;

  Runtime := TCore4Runtime.Create(ParamStr(2));
  try
    ResultPhysical := Runtime.ExecutePhysicalCall(Physical);
  finally
    Runtime.Free;
  end;
  { Фізичну структуру кінцевого слова перевіряє існуючий декодер.
    Жодної інтерпретації D1/D24, арифметики чи dispatch за spelling. }
  DecodeT5M(ResultPhysical, Words);
  if Length(Words) <> 1 then
    raise Exception.Create(Ukr('неоднозначна кількість вихідних слів'));

  try
    TempPath := GetTempFileName(
      ExtractFilePath(ExpandFileName(OutputPath)), 'cr4');
    if TempPath = '' then
      raise Exception.Create(Ukr('не вдалося створити тимчасовий файл'));
    Stream := TFileStream.Create(TempPath, fmCreate);
    try
      Stream.WriteBuffer(ResultPhysical[1], Length(ResultPhysical));
    finally
      Stream.Free;
    end;
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise Exception.Create(Ukr('вихідний шлях зайнято під час запису'));
    if not RenameFile(TempPath, OutputPath) then
      raise Exception.Create(Ukr('атомарне завершення запису не вдалося'));
    TempPath := '';
  finally
    if (TempPath <> '') and FileExists(TempPath) then
      DeleteFile(TempPath);
  end;
  WriteLn(Ukr('CORE4-ВИКОНАНО двійкові-байти='), Length(ResultPhysical),
    Ukr(' закони=pinned-SENS результат=.sens'));
end;

begin
  ExitCode := 0;
  if not ValidCommand then
  begin
    WriteLn(StdErr, Ukr(
      'Використання: senscore4vykon --виконати КОРІНЬ виклик.sens результат.sens'));
    ExitCode := 64;
  end
  else
    try
      Execute;
    except
      on E: Exception do
      begin
        WriteLn(StdErr, Ukr('CORE4-ПОМИЛКА: '), E.Message);
        ExitCode := 2;
      end;
    end;
end.
