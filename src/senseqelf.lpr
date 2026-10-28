{ G6.13 — українська оболонка для одного фізичного D3:101→ELF64. }
program senseqelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfeq,wsm.t5m;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S));end;
procedure Run;
var
  F:TFileStream;
  InputPath,OutputPath,TempPath:String;
  Physical,Machine:RawByteString;
begin
  TempPath:='';
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>UA('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: senseqelf --породити вхід.sens вихід.elf'));
    ExitCode:=64;Exit;
  end;
  InputPath:=ParamStr(2);OutputPath:=ParamStr(3);
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EElfEqError.Create(UA('Заборонено перезаписувати існуючий ELF'));
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EElfEqError.Create(UA('Недопустимий розмір фізичного .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free;end;
    Machine:=BuildEqELF(Physical,'external/sens');
    TempPath:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'eqb');
    if TempPath='' then
      raise EElfEqError.Create(UA('Не вдалося створити тимчасовий ELF'));
    F:=TFileStream.Create(TempPath,fmCreate);
    try F.WriteBuffer(Machine[1],Length(Machine));
    finally F.Free;end;
    if fpChmod(PChar(TempPath),$1ED)<>0 then
      raise EElfEqError.Create(UA('Не вдалося дозволити виконання ELF'));
    if FileExists(OutputPath) then
      raise EElfEqError.Create(UA('Вихідний файл уже існує'));
    if not RenameFile(TempPath,OutputPath) then
      raise EElfEqError.Create(UA('Помилка публікації ELF'));
    TempPath:='';
    WriteLn(UA('НАТИВНИЙ-EQ-ГОТОВО ELF64=x86-64 байтів='),Length(Machine));
    ExitCode:=0;
  except
    on E:Exception do begin
      if (TempPath<>'') and FileExists(TempPath) then DeleteFile(TempPath);
      WriteLn(StdErr,UA('НАТИВНИЙ-EQ-ПОМИЛКА: '),E.Message);
      ExitCode:=2;
    end;
  end;
end;
begin Run;end.
