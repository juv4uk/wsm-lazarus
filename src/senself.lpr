{ Нативне породження ELF64, лише фізичний D1 після pinned допуску.
  Вихід — новий машинний файл, не канонічний .sens. }
program senself;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.elfd1, wsm.t5m;
function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
var F:TFileStream; Input,OutputPath,Tmp:String;
    Physical,Executable:RawByteString;
    IsPIE:Boolean;
begin
  if (ParamCount<>3) or
     ((RawByteString(ParamStr(1))<>UkrBytes('--породити')) and
      (RawByteString(ParamStr(1))<>UkrBytes('--породити-переміщуваний'))) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UkrBytes('Використання: senself --породити|--породити-переміщуваний вхід.sens вихід.elf'));
    Halt(64);
  end;
  IsPIE:=RawByteString(ParamStr(1))=UkrBytes('--породити-переміщуваний');
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
    if IsPIE then Executable:=BuildD1PIE(Physical,'external/sens')
    else Executable:=BuildExactLiteralELF(Physical,'external/sens');
    { Атомарна публікація лише після повного pinned і native допуску.
      Тимчасовий файл у тій самій теці; раніше наявний не чіпаємо. }
    Tmp:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'sen');
    F:=TFileStream.Create(Tmp,fmCreate);
    try F.WriteBuffer(Executable[1],Length(Executable));
    finally F.Free; end;
    if fpChmod(PChar(Tmp),$1ED)<>0 then
      raise EELFD1Error.Create('Не вдалося встановити права виконання ELF');
    { Важливо: попередній FileExists не є захистом від гонки.
      RenameFile у Linux замінив би чужий файл або навіть dangling
      symlink, створений після перевірки. Атомарний hardlink робить
      публікацію лише якщо імені ще НЕ існує (EEXIST => відмова).
      Тимчасовий ELF лежить у тій самій файловій системі. }
    if fpLink(PChar(Tmp),PChar(OutputPath))<>0 then
      raise EELFD1Error.Create(
        'Не вдалося атомарно створити ELF без перезапису');
    DeleteFile(Tmp);
    Tmp:='';
    if IsPIE then
      WriteLn(UkrBytes('НАТИВНИЙ-ELF-ГОТОВО D1 ELF64=x86-64-Linux ET_DYN байти='),Length(Executable))
    else
      WriteLn(UkrBytes('НАТИВНИЙ-ELF-ГОТОВО D1 ELF64=x86-64-Linux байти='),Length(Executable));
  except
    on E:Exception do begin
      if (Tmp<>'') and FileExists(Tmp) then DeleteFile(Tmp);
      WriteLn(StdErr,UkrBytes('НАТИВНИЙ-ELF-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
