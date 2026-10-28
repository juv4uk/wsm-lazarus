{ G6.13 — український CLI машинного D3:101; один точний фізичний .sens. }
program senseqelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfeq,wsm.t5m;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
var
  F:TFileStream;
  InFile,OutFile,Temporary:String;
  Mode:RawByteString;
  Physical,Machine:RawByteString;
begin
  Temporary:='';
  Mode:=RawByteString(ParamStr(1));
  if (ParamCount<>3) or
     ((Mode<>UA('--породити')) and
      (Mode<>UA('--породити-переміщуваний'))) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: senseqelf --породити|--породити-переміщуваний вхід.sens вихід.elf'));
    Halt(64);
  end;
  InFile:=ParamStr(2);OutFile:=ParamStr(3);
  try
    if FileExists(OutFile) or DirectoryExists(OutFile) then
      raise EElfEqError.Create(UA('Вихідний файл уже існує: перезапис заборонено'));
    F:=TFileStream.Create(InFile,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EElfEqError.Create(UA('Недопустима довжина фізичного .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    if Mode=UA('--породити') then
      Machine:=BuildEqELF(Physical,'external/sens')
    else
      Machine:=BuildEqPIE(Physical,'external/sens');
    { Тимчасовий виконуваний файл тільки ПІСЛЯ повного допуску.
      Це звичайна файлово-атомарна публікація, не захист від TOCTOU. }
    Temporary:=GetTempFileName(ExtractFilePath(ExpandFileName(OutFile)),'eqx');
    F:=TFileStream.Create(Temporary,fmCreate);
    try F.WriteBuffer(Machine[1],Length(Machine));
    finally F.Free; end;
    if fpChmod(PChar(Temporary),$1ED)<>0 then
      raise EElfEqError.Create(UA('Неможливо дозволити виконання ELF'));
    if FileExists(OutFile) or DirectoryExists(OutFile) then
      raise EElfEqError.Create(UA('Вихідний файл зайнято іншим процесом'));
    if not RenameFile(Temporary,OutFile) then
      raise EElfEqError.Create(UA('Атомарне перейменування ELF не вдалося'));
    Temporary:='';
    if Mode=UA('--породити-переміщуваний') then
      WriteLn(UA('НАТИВНЕ-ЕКВІВАЛЕНТНЕ-PIE-ГОТОВО D3:101 ELF64-x86-64 байтів='),Length(Machine))
    else
      WriteLn(UA('НАТИВНЕ-ЕКВІВАЛЕНТНЕ-ГОТОВО D3:101 ELF64-x86-64 байтів='),
      Length(Machine));
  except
    on E:Exception do begin
      if (Temporary<>'') and FileExists(Temporary) then DeleteFile(Temporary);
      WriteLn(StdErr,UA('НАТИВНЕ-ЕКВІВАЛЕНТНЕ-ПОМИЛКА: '),E.Message);
      ExitCode:=2;
    end;
  end;
end.
