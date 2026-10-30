{ Український CLI компіляції вузької фізичної D3:010 форми у ELF64. }
program sensatomelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfatom,wsm.t5m;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
var
  F:TFileStream;
  InputPath,OutputPath,TempPath:String;
  Physical,Machine:RawByteString;
begin
  TempPath:='';
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>UA('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: sensatomelf --породити вхід.sens вихід.elf'));
    Halt(64);
  end;
  InputPath:=ParamStr(2);OutputPath:=ParamStr(3);
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EElfAtomError.Create(UA('Вихідний файл уже існує: перезапис заборонено'));
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EElfAtomError.Create(UA('Недопустимий розмір фізичного .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    Machine:=BuildCheckedAtomELF(Physical,'external/sens');
    { Тільки після допуску створюємо тимчасовий файл.
      Всі буфери управляються FPC; на винятку тимчасовий файл зникає.
      Це захист від звичайного перезапису, НЕ від конкурентного TOCTOU. }
    TempPath:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'atm');
    F:=TFileStream.Create(TempPath,fmCreate);
    try F.WriteBuffer(Machine[1],Length(Machine));
    finally F.Free; end;
    if fpChmod(PChar(TempPath),$1ED)<>0 then
      raise EElfAtomError.Create(UA('Неможливо встановити дозвіл виконання'));
    if FileExists(OutputPath) then
      raise EElfAtomError.Create(UA('Вихідний файл уже існує'));
    if not RenameFile(TempPath,OutputPath) then
      raise EElfAtomError.Create(UA('Помилка атомарного перейменування ELF'));
    TempPath:='';
    WriteLn(UA('НАТИВНИЙ-АТОМ-ГОТОВО ELF64=x86-64-Linux байтів='),Length(Machine));
  except
    on E:Exception do begin
      if (TempPath<>'') and FileExists(TempPath) then DeleteFile(TempPath);
      WriteLn(StdErr,UA('НАТИВНИЙ-АТОМ-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
