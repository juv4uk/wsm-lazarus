{ G6.19 — фізичний .sens -> перевірений D3 CAR/CDR -> машинний ELF64.
  Один вхід, новий вихід; жодного прихованого текстового dispatch. }
program sensvybirelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfselector,wsm.t5m;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

var
  F:TFileStream;
  InputPath,OutputPath,Temporary:String;
  Physical,Machine:RawByteString;
begin
  Temporary:='';
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>UA('--породити')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: sensvybirelf --породити вхід.sens вихід.elf'));
    Halt(64);
  end;
  InputPath:=ParamStr(2);
  OutputPath:=ParamStr(3);
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EElfSelectorError.Create(UA('Не дозволено перезаписувати вихідний ELF'));
    F:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EElfSelectorError.Create(UA('Недопустима фізична довжина .sens'));
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    Machine:=BuildSelectorELF(Physical,'external/sens');
    { Жоден вихідний файл не створюється до повної перевірки pinned SENS.
      Тимчасова публікація захищає від часткового запису, не від TOCTOU. }
    Temporary:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'vbr');
    F:=TFileStream.Create(Temporary,fmCreate);
    try F.WriteBuffer(Machine[1],Length(Machine));
    finally F.Free; end;
    if fpChmod(PChar(Temporary),$1ED)<>0 then
      raise EElfSelectorError.Create(UA('Не вдалося встановити ELF як виконуваний'));
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EElfSelectorError.Create(UA('Вихідний ELF уже зайнятий'));
    if not RenameFile(Temporary,OutputPath) then
      raise EElfSelectorError.Create(UA('Не вдалося опублікувати машинний ELF'));
    Temporary:='';
    WriteLn(UA('МАШИННИЙ-ВИБІР-ГОТОВО D3:100/011 ELF64-x86-64 байтів='),Length(Machine));
  except
    on E:Exception do begin
      if (Temporary<>'') and FileExists(Temporary) then DeleteFile(Temporary);
      WriteLn(StdErr,UA('МАШИННИЙ-ВИБІР-ПОМИЛКА: '),E.Message);
      ExitCode:=2;
    end;
  end;
end.
