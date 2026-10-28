{ G6.17 — CLI для машинної вузької умовної форми; лише .sens. }
program senscondelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfcond,wsm.t5m;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
var F:TFileStream;
  InFile,OutFile,Temporary:String;
  Physical,Machine:RawByteString;
begin
  Temporary:='';
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>UA('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: senscondelf --породити вхід.sens вихід.elf'));
    Halt(64);
  end;
  InFile:=ParamStr(2); OutFile:=ParamStr(3);
  try
    if FileExists(OutFile) or DirectoryExists(OutFile) then
      raise EElfCondError.Create(UA('Вихідний ELF уже існує: перезапис заборонено'));
    F:=TFileStream.Create(InFile,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EElfCondError.Create(UA('Недопустима довжина .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    Machine:=BuildCondELF(Physical,'external/sens');
    Temporary:=GetTempFileName(ExtractFilePath(ExpandFileName(OutFile)),'cnd');
    F:=TFileStream.Create(Temporary,fmCreate);
    try F.WriteBuffer(Machine[1],Length(Machine));
    finally F.Free; end;
    if fpChmod(PChar(Temporary),$1ED)<>0 then
      raise EElfCondError.Create(UA('Не вдалося встановити права на виконання'));
    if FileExists(OutFile) or DirectoryExists(OutFile) then
      raise EElfCondError.Create(UA('Вихідний ELF уже зайнятий'));
    if not RenameFile(Temporary,OutFile) then
      raise EElfCondError.Create(UA('Не вдалося атомарно опублікувати ELF'));
    Temporary:='';
    WriteLn(UA('МАШИННА-УМОВА-ГОТОВО D3:110 ELF64 байтів='),Length(Machine));
  except
    on E:Exception do begin
      if (Temporary<>'') and FileExists(Temporary) then DeleteFile(Temporary);
      WriteLn(StdErr,UA('МАШИННА-УМОВА-ПОМИЛКА: '),E.Message);
      ExitCode:=2;
    end;
  end;
end.
