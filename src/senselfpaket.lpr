{ G6.9 — атомарний CLI породження ELF64 із кількох фізичних D1.
  Не є новим виконавцем чи компілятором для загального SENS. }
program senselfpaket;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.t5m, wsm.elfd1batch;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

var
  InputPath, OutputPath, Temporary: String;
  Source, Executable: RawByteString;
  F: TFileStream;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UkrBytes('--породити-пакет')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UkrBytes('Використання: senselfpaket --породити-пакет вхід.sens вихід.elf'));
    Halt(64);
  end;

  InputPath:=ParamStr(2);
  OutputPath:=ParamStr(3);
  Temporary:='';
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EELFD1BatchError.Create(UkrBytes('перезапис готового файла заборонено'));
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EELFD1BatchError.Create(UkrBytes('неприпустимий розмір фізичного .sens'));
      SetLength(Source, SizeInt(F.Size));
      F.ReadBuffer(Source[1], Length(Source));
    finally F.Free; end;
    Executable:=BuildD1BatchELF(Source,'external/sens');
    { Файл створюється тільки після повного допуску. }
    Temporary:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'elf');
    F:=TFileStream.Create(Temporary,fmCreate);
    try F.WriteBuffer(Executable[1],Length(Executable));
    finally F.Free; end;
    if fpChmod(PChar(Temporary),$1ED)<>0 then
      raise EELFD1BatchError.Create(UkrBytes('не вдалося встановити права виконання'));
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EELFD1BatchError.Create(UkrBytes('файл виходу вже існує'));
    if not RenameFile(Temporary,OutputPath) then
      raise EELFD1BatchError.Create(UkrBytes('не вдалося опублікувати машинний ELF'));
    Temporary:='';
    WriteLn(UkrBytes('НАТИВНИЙ-D1-ПАКЕТ-ГОТОВО ELF64=x86-64 байти='),
      Length(Executable));
  except
    on E:Exception do begin
      if (Temporary<>'') and FileExists(Temporary) then
        DeleteFile(Temporary);
      WriteLn(StdErr,UkrBytes('НАТИВНИЙ-D1-ПАКЕТ-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
