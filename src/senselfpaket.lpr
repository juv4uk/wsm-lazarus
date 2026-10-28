{ G6.9 — CLI породження машинного ELF64 для кількох незалежних D1.
  .sens — canonical physical input; .elf — окремий executable, НЕ SENS. }
program senselfpaket;
{$mode objfpc}{$H+}{$codepage utf8}

uses SysUtils, Classes, BaseUnix, wsm.elfbatch, wsm.t5m;

function UkrBytes(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

function Run:LongInt;
var
  F:TFileStream;
  InputPath, OutputPath, Temporary:String;
  Physical, Executable:RawByteString;
begin
  Result:=64;
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UkrBytes('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UkrBytes('Використання: senselfpaket --породити вхід.sens вихід.elf'));
    Exit;
  end;
  Result:=2;
  InputPath:=ParamStr(2);
  OutputPath:=ParamStr(3);
  Temporary:='';
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EELFBatchError.Create(UkrBytes('Вихідний файл уже існує, перезапис заборонено'));
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EELFBatchError.Create(UkrBytes('Порожній чи надмірний фізичний .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally
      F.Free;
    end;

    Executable:=BuildD1BatchELF(Physical,'external/sens');
    { GetTempFileName створює файл у ТІЙ САМІЙ теці.
      fpLink — атомарне створення нового імені без overwrite race;
      тільки після повного admission/запису/chmod і перевірок. }
    Temporary:=GetTempFileName(
      ExtractFilePath(ExpandFileName(OutputPath)),'seb');
    F:=TFileStream.Create(Temporary,fmCreate);
    try
      F.WriteBuffer(Executable[1],Length(Executable));
    finally
      F.Free;
    end;
    if fpChmod(PChar(Temporary),$1ED)<>0 then
      raise EELFBatchError.Create(UkrBytes('Не вдалося встановити права виконання ELF'));
    if fpLink(PChar(Temporary),PChar(OutputPath))<>0 then
      raise EELFBatchError.Create(UkrBytes('Не вдалося атомарно створити новий ELF без перезапису'));
    DeleteFile(Temporary);
    Temporary:='';
    WriteLn(UkrBytes('НАТИВНИЙ-ELF-ПАКЕТ-ГОТОВО D1=фізичний ELF64=x86-64-Linux байти='),Length(Executable));
    Result:=0;
  except
    on E:Exception do
      WriteLn(StdErr,UkrBytes('НАТИВНИЙ-ELF-ПАКЕТ-ПОМИЛКА: '),E.Message);
  end;
  if (Temporary<>'') and FileExists(Temporary) then DeleteFile(Temporary);
end;

begin
  ExitCode:=Run;
end.
