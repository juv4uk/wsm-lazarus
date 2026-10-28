{ Нативне породження ELF64, лише фізичний D1 після pinned допуску.
  Вихід — новий машинний файл, не канонічний .sens. }
program senself;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.elfd1, wsm.t5m;
function Українською(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
var F:TFileStream; Input,OutputPath,Tmp:String;
    Physical,Executable:RawByteString;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>Українською('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,Українською('Використання: senself --породити вхід.sens вихід.elf'));
    Halt(64);
  end;
  Input:=ParamStr(2); OutputPath:=ParamStr(3);
  Tmp:='';
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EELFD1Error.Create('Файл виходу вже існує, перезапис заборонено');
    F:=TFileStream.Create(Input,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EELFD1Error.Create('Порожній чи надмірний фізичний .sens');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    Executable:=BuildD1ELF(Physical,'external/sens');
    { Атомарна публікація лише після повного pinned і native допуску.
      Тимчасовий файл у тій самій теці; раніше наявний не чіпаємо. }
    Tmp:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'sen');
    F:=TFileStream.Create(Tmp,fmCreate);
    try F.WriteBuffer(Executable[1],Length(Executable));
    finally F.Free; end;
    if fpChmod(PChar(Tmp),$1ED)<>0 then
      raise EELFD1Error.Create('Не вдалося встановити права виконання ELF');
    if FileExists(OutputPath) then
      raise EELFD1Error.Create('Файл виходу вже існує');
    if not RenameFile(Tmp,OutputPath) then
      raise EELFD1Error.Create('Не вдалося атомарно опублікувати ELF');
    Tmp:='';
    WriteLn(Українською('НАТИВНИЙ-ELF-ГОТОВО D1 ELF64=x86-64-Linux байти='),Length(Executable));
  except
    on E:Exception do begin
      if (Tmp<>'') and FileExists(Tmp) then DeleteFile(Tmp);
      WriteLn(StdErr,Українською('НАТИВНИЙ-ELF-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
