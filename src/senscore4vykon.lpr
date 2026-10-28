{ Ukrаїнський CLI фізичного виконання вже допущеного початкового Core4.
  Обидва файли — канонічні бінарні T5M .sens, не текстова проєкція.
  Усі мовні операції виконує чинний wsm.core4runtime, не цей адаптер. }
program senscore4vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m, wsm.d2source,
  wsm.physloc
  {$IFDEF UNIX}, BaseUnix{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

function Ukr(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

function ValidCommand: Boolean;
begin
  Result := (ParamCount = 4) and
    ((RawByteString(ParamStr(1)) = Ukr('--виконати')) or
     (RawByteString(ParamStr(1)) = Ukr('--пакет'))) and
    (LowerCase(ExtractFileExt(ParamStr(3))) = '.sens') and
    (LowerCase(ExtractFileExt(ParamStr(4))) = '.sens');
end;

{ Кожен top-level вираз уже структурно розібрано чинним D2 reader.
  Послідовність має один persistent Core4 runtime і атомарний загальний
  вихід: помилка будь-якої форми не публікує попередні результати. }
const MaxCore4BatchCalls = 64;

function ExecuteBatch(const Physical:RawByteString;
  Runtime:TCore4Runtime):RawByteString;
var
  Words, Part, ResponseWords, Answers:TExactWords;
  Spans:TPhysicalWordSpans;
  At:TPhysicalWordSpan;
  Doc:TD2Document;
  I,J,FirstWord,AfterLast:SizeInt;
  ResponsePhysical:RawByteString;
begin
  { Той самий T5M reader + фізичні трит-/байт-координати з
    чинного wsm.physloc. Відкинути неканонічний фізичний потік. }
  DecodeT5MWithLocations(Physical,Words,Spans);
  Doc:=ParseD2WordsWide(Words);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxCore4BatchCalls) then
      raise Exception.Create(Ukr('неприпустима кількість фізичних форм у пакеті'));
    SetLength(Answers,Length(Doc.Roots));
    for I:=0 to High(Doc.Roots) do begin
      FirstWord:=Doc.Roots[I].WordIndex-1;
      if I<High(Doc.Roots) then
        AfterLast:=Doc.Roots[I+1].WordIndex-1
      else
        AfterLast:=Length(Words);
      if (FirstWord<0) or (AfterLast<=FirstWord) then
        raise Exception.Create(Ukr('пошкоджено фізичні межі пакета'));
      SetLength(Part,AfterLast-FirstWord);
      for J:=0 to High(Part) do Part[J]:=Words[FirstWord+J];
      { Єдина семантика — вже злитий exact Core4 evaluator. }
      try
        ResponsePhysical:=Runtime.ExecutePhysicalCall(EncodeT5M(Part));
      except
        on E:Exception do begin
          { Це ТОЧНИЙ початок top-level форми, не вигадана позиція
            внутрішньої семантичної помилки виконавця. }
          At:=LocatePhysicalWord(Physical,Spans,Doc.Roots[I].WordIndex);
          raise Exception.Create(
            Ukr('помилка фізичної форми: форма=')+IntToStr(I+1)+
            Ukr(' початок-слово=')+IntToStr(At.WordIndex)+
            Ukr(' трити=[')+IntToStr(At.TritStart)+','+
              IntToStr(At.TritEnd)+')'+
            Ukr(' байти=[')+IntToStr(At.ByteStart)+','+
              IntToStr(At.ByteEnd)+') '+E.Message);
        end;
      end;
      DecodeT5M(ResponsePhysical,ResponseWords);
      if Length(ResponseWords)<>1 then
        raise Exception.Create(Ukr('пакетна форма не дала одного exact слова'));
      Answers[I]:=ResponseWords[0];
    end;
    Result:=EncodeT5M(Answers);
  finally Doc.Free end;
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
    if RawByteString(ParamStr(1)) = Ukr('--пакет') then
      ResultPhysical := ExecuteBatch(Physical, Runtime)
    else
      ResultPhysical := Runtime.ExecutePhysicalCall(Physical);
  finally
    Runtime.Free;
  end;
  { Фізичну структуру кінцевого слова перевіряє існуючий декодер.
    Жодної інтерпретації D1/D24, арифметики чи dispatch за spelling. }
  DecodeT5M(ResultPhysical, Words);
  if (Length(Words)<1) or
     ((RawByteString(ParamStr(1))=Ukr('--виконати')) and
      (Length(Words)<>1)) or
     (Length(Words)>MaxCore4BatchCalls) then
    raise Exception.Create(Ukr('неприпустима кількість вихідних exact слів'));

  try
    TempPath := GetTempFileName(
      ExtractFilePath(ExpandFileName(OutputPath)), 'cr4');
    if TempPath = '' then
      raise Exception.Create(Ukr('не вдалося створити тимчасовий файл'));
    { Канонічні байти вже отримано через pinned Core4; тимчасовий
      файл створюється у каталозі цілі для same-filesystem publish. }
    Stream := TFileStream.Create(TempPath, fmCreate);
    try
      Stream.Size := 0;
      Stream.WriteBuffer(ResultPhysical[1], Length(ResultPhysical));
    finally
      Stream.Free;
    end;
    { FileExists + RenameFile має TOCTOU-вікно. Unix rename може
      перезаписати наявний файл або висяче символьне посилання.
      Публікуємо НОВЕ ім'я без заміни: fpLink / MoveFileW.
      Непідтримана платформа — відмова, не небезпечний fallback. }
    {$IFDEF UNIX}
    if fpLink(RawByteString(TempPath), RawByteString(OutputPath)) <> 0 then
      raise Exception.Create(Ukr('цільовий шлях вже зайнятий або атомарна публікація неможлива'));
    {$ELSE}
      {$IFDEF WINDOWS}
      if not Windows.MoveFileW(PWideChar(UTF8Decode(TempPath)),
                               PWideChar(UTF8Decode(OutputPath))) then
        raise Exception.Create(Ukr('цільовий шлях вже зайнятий або атомарна публікація неможлива'));
      {$ELSE}
      raise Exception.Create(Ukr('платформа не підтримує захищений запис .sens'));
      {$ENDIF}
    {$ENDIF}
  finally
    if (TempPath <> '') and FileExists(TempPath) then
      DeleteFile(TempPath);
  end;
  WriteLn(Ukr('CORE4-ВИКОНАНО двійкові-байти='), Length(ResultPhysical),
    Ukr(' закони=pinned-SENS результат=.sens форм='), Length(Words));
end;

begin
  ExitCode := 0;
  if not ValidCommand then
  begin
    WriteLn(StdErr, Ukr(
      'Використання: senscore4vykon --виконати|--пакет КОРІНЬ виклик.sens результат.sens'));
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
