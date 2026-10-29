{ G5.63 — файловий клієнт для вже наявного фізичного FPC-сеансу.
  Кожен файл — канонічні packed T5M байти .sens, НЕ текстова .lisp.
  Вивід — ПРИВАТНІ host-кадри status:u8 + word:u32le +
  length:u32le + payload (T5M при успіху, UTF-8 при відмові).
  Один дочірній виконавець між файлами. ЦЕ НЕ загальний SENS REPL. }
program sensfizfaily;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, Process;

const
  MaxFiles = 16;
  MaxInputBytes = 65536;
  MaxReplyBytes = 65536;
  MaxBufferedBytes = 16 * (MaxReplyBytes + 9);
type
  EPhysicalFilesError = class(Exception);
  TPhysicalFiles = array of RawByteString;

function UA(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

function Little32(const Bytes: array of Byte; Offset: SizeInt): QWord;
begin
  Result := QWord(Bytes[Offset]) or
    (QWord(Bytes[Offset+1]) shl 8) or
    (QWord(Bytes[Offset+2]) shl 16) or
    (QWord(Bytes[Offset+3]) shl 24);
end;

procedure PutLE32(var Bytes: array of Byte; N: QWord);
var I: SizeInt;
begin
  if N > High(LongWord) then
    raise EPhysicalFilesError.Create('неприпустима довжина host-кадру');
  for I := 0 to 3 do
    Bytes[I] := Byte((N shr (8 * I)) and $FF);
end;

procedure ReadExactly(S: TStream; var Dest; Count: SizeInt);
var P: PByte; Used, Got: SizeInt;
begin
  P := @Dest;
  Used := 0;
  while Used < Count do begin
    Got := S.Read(P[Used], Count - Used);
    if Got <= 0 then
      raise EPhysicalFilesError.Create(
        'дочірній сеанс обірвав фізичну host-відповідь');
    Inc(Used, Got);
  end;
end;

{ Повний попередній допуск усіх файлів ДО запуску процесу і stdout.
  Files: власні reference-counted фізичні RawByteString, кожен <=65536.
  Ніякого D7/іменного dispatch, числової інтерпретації D12+ або
  конвертації .sens у .lisp тут немає.
  Питання: чому суфікс .sens сам не доводить канонічність?
  Чому читати всі файли до першого stdout?
  Хто володіє байтами після звільнення файлового потоку?
  Чому T5M перевіряє дочірній exact-domain виконавець? }
procedure Preflight(out Files: TPhysicalFiles);
var I: SizeInt; S: TFileStream; Path: String;
begin
  if (ParamCount < 3) or (ParamCount > MaxFiles + 2) or
     (RawByteString(ParamStr(1)) <> UA('--файли')) or
     (ParamStr(2) = '') then
    raise EPhysicalFilesError.Create(
      'використання: sensfizfaily --файли ./sensfizseans один.sens [інші.sens ...]');

  SetLength(Files, ParamCount - 2);
  for I := 0 to High(Files) do begin
    Path := ParamStr(I + 3);
    if (Path = '') or (LowerCase(ExtractFileExt(Path)) <> '.sens') then
      raise EPhysicalFilesError.Create('потрібен фізичний файл .sens');
    S := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (S.Size < 1) or (S.Size > MaxInputBytes) then
        raise EPhysicalFilesError.Create(
          'довжина фізичного файла поза межами 1..65536');
      SetLength(Files[I], SizeInt(S.Size));
      S.ReadBuffer(Files[I][1], Length(Files[I]));
    finally
      S.Free;
    end;
  end;
end;

{ Process — один власний дочірній FPC PID; Input/Output — його
  позичені pipe-потоки. Кожна фізична відповідь цілком буферизується
  перед публікацією; весь stdout віддаємо лише після чистого EOF.
  Status та WordIndex — host-поля, а НЕ значення/закони D1.
  Питання: чому u32le не є SENS словом?
  Чому прочитати відповідь потрібно до відправки наступного кадру?
  Як зберігається початковий T5M payload без UTF-8 перекодування?
  Чому навіть status=1 не знищує PID? }
procedure Run(const Files: TPhysicalFiles; out Rejected: Boolean);
var
  Child: TProcess;
  Header: array[0..3] of Byte;
  ReplyHeader: array[0..8] of Byte;
  Answer: RawByteString;
  AnswerSize: QWord;
  I: SizeInt;
  Extra: Byte;
  Buffer: TMemoryStream;
  Sink: THandleStream;
  Started: Boolean;
begin
  Rejected := False;
  Child := TProcess.Create(nil);
  Buffer := TMemoryStream.Create;
  Started := False;
  try
    Child.Executable := ParamStr(2);
    Child.Parameters.Add(UA('--сеанс'));
    Child.Options := [poUsePipes];
    Child.Execute;
    Started := True;
    for I := 0 to High(Files) do begin
      PutLE32(Header, Length(Files[I]));
      Child.Input.WriteBuffer(Header[0], SizeOf(Header));
      Child.Input.WriteBuffer(Files[I][1], Length(Files[I]));
      ReadExactly(Child.Output, ReplyHeader[0], SizeOf(ReplyHeader));
      if ReplyHeader[0] > 1 then
        raise EPhysicalFilesError.Create('невідомий статус host-відповіді');
      AnswerSize := Little32(ReplyHeader, 5);
      if (AnswerSize < 1) or (AnswerSize > MaxReplyBytes) then
        raise EPhysicalFilesError.Create('невірна довжина host-відповіді');
      if Buffer.Size > MaxBufferedBytes - 9 - AnswerSize then
        raise EPhysicalFilesError.Create('переповнено бюджет відповідей');
      SetLength(Answer, SizeInt(AnswerSize));
      ReadExactly(Child.Output, Answer[1], SizeInt(AnswerSize));
      if ReplyHeader[0] = 1 then Rejected := True
      else if Little32(ReplyHeader, 1) <> 0 then
        raise EPhysicalFilesError.Create(
          'успішна відповідь має ненульовий індекс помилки');
      Buffer.WriteBuffer(ReplyHeader[0], SizeOf(ReplyHeader));
      Buffer.WriteBuffer(Answer[1], Length(Answer));
      Answer := '';
    end;
    Child.CloseInput;
    Child.WaitOnExit;
    if Child.ExitStatus <> 0 then
      raise EPhysicalFilesError.Create('фізичний дочірній сеанс завершився з помилкою');
    if Child.Output.Read(Extra, 1) <> 0 then
      raise EPhysicalFilesError.Create('зайві байти дочірнього stdout');
    if Child.Stderr.Read(Extra, 1) <> 0 then
      raise EPhysicalFilesError.Create('зайва діагностика дочірнього stderr');
    Sink := THandleStream.Create(TextRec(Output).Handle);
    try
      Buffer.Position := 0;
      Sink.CopyFrom(Buffer, Buffer.Size);
    finally
      Sink.Free;
    end;
  finally
    if Started and Child.Running then begin
      Child.Terminate(2);
      Child.WaitOnExit;
    end;
    Child.Free;
    Buffer.Free;
  end;
end;

var Files: TPhysicalFiles; Rejected: Boolean;
begin
  { Помилка використання не породжує ані фальшивого .sens, ані
    часткового host-кадру. Немає власної семантичної таблиці. }
  if (ParamCount < 3) or (ParamCount > MaxFiles + 2) or
     (RawByteString(ParamStr(1)) <> UA('--файли')) then begin
    WriteLn(StdErr, UA('Використання: sensfizfaily --файли ./sensfizseans один.sens [інші.sens ...]'));
    ExitCode := 64;
  end else
    try
      Preflight(Files);
      Run(Files, Rejected);
      if Rejected then ExitCode := 2;
    except
      on E: Exception do begin
        WriteLn(StdErr, UA('ПОМИЛКА-ФІЗИЧНІ-ФАЙЛИ: '), E.Message);
        ExitCode := 2;
      end;
    end;
end.
