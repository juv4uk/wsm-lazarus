{ G3.17. Файловий host-вхід до вже перевіреного D3 batch.
  Фізична відповідь лише T5M, не текстова проєкція і не REPL. }
program senspaketd3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.t5m, wsm.d3batch;

function Ua(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Run;
var
  Root, InputPath, OutputPath, TempPath:String;
  Physical, Answer:RawByteString;
  F:TFileStream;
  Count:SizeInt;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>Ua('--пакет')) then begin
    WriteLn(StdErr,Ua('ПОМИЛКА-ПАКЕТ-D3: Використання: senspaketd3 --пакет корінь-sens вхід.sens новий-результат.sens'));
    ExitCode:=64;
    Exit;
  end;
  Root:=ParamStr(2);
  InputPath:=ParamStr(3);
  OutputPath:=ParamStr(4);
  if (Root='') or (LowerCase(ExtractFileExt(InputPath))<>'.sens') or
     (LowerCase(ExtractFileExt(OutputPath))<>'.sens') then begin
    WriteLn(StdErr,Ua('ПОМИЛКА-ПАКЕТ-D3: потрібен корінь і фізичні файли .sens'));
    ExitCode:=64;
    Exit;
  end;

  TempPath:='';
  try
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надмірний фізичний .sens');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally
      F.Free;
    end;

    { ЖОДНОЇ публікації до завершення всіх реальних D3 форм. }
    ExecutePhysicalD3Batch(Physical,RawByteString(Root),Answer,Count);
    if (Length(Answer)<1) or (Length(Answer)>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('фізична відповідь поза межею T5M');

    { Temp у тій самій директорії. fpLink атомарно відмовляє за
      зайнятого імені, включно з symlink; не чіпає попередній файл. }
    TempPath:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'d3p');
    if TempPath='' then raise Exception.Create('не створено тимчасовий файл');
    F:=TFileStream.Create(TempPath,fmCreate);
    try
      F.WriteBuffer(Answer[1],Length(Answer));
    finally
      F.Free;
    end;
    if fpLink(RawByteString(TempPath),RawByteString(OutputPath))<>0 then
      raise Exception.Create('фізичний результат уже існує або недоступний');
    DeleteFile(TempPath);
    TempPath:='';
    WriteLn(Ua('ПАКЕТ-D3-ГОТОВО форм='),Count,
      Ua(' байтів='),Length(Answer),Ua(' результат=фізичний-T5M'));
  except
    on E:ED3BatchError do begin
      WriteLn(StdErr,Ua('ПОМИЛКА-ПАКЕТ-D3 форма='),E.FormIndex,
        Ua(' слово='),E.WordIndex,': ',E.Message);
      ExitCode:=2;
    end;
    on E:Exception do begin
      WriteLn(StdErr,Ua('ПОМИЛКА-ПАКЕТ-D3: '),E.Message);
      ExitCode:=2;
    end;
  end;
  if TempPath<>'' then DeleteFile(TempPath);
end;

begin
  Run;
end.
