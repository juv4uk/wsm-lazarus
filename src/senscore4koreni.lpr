{ G4.34 — opt-in CLI багатокореневого фізичного Core4.
  Пакети зі списковими результатами не змінюють старий однослівний CLI. }
program senscore4koreni;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes{$IFDEF UNIX}, cwstring{$ENDIF},
  wsm.core4runtime, wsm.core4multiroot, wsm.t5m
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('джерело .sens поза межею 1..4 МіБ');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Data — власні фізичні байти. Видаємо новий файл без перезапису:
  приватний temp у тій самій директорії + атомарний hard link.
  У разі відмови знищуємо тільки власний temp; навіть dangling
  symlink цілі не замінюємо. Непідтримана платформа — відмова. }
procedure SaveNew(const Path:String;const Data:RawByteString);
var Temp:String; F:TFileStream;
begin
  Temp:='';
  if (Length(Data)<1) or (Length(Data)>MAX_T5M_FILE_BYTES) then
    raise Exception.Create('неприпустимий розмір фізичної відповіді');
  try
    Temp:=GetTempFileName(ExtractFilePath(ExpandFileName(Path)),'c4k');
    if Temp='' then raise Exception.Create('не створено тимчасовий файл');
    F:=TFileStream.Create(Temp,fmCreate);
    try F.WriteBuffer(Data[1],Length(Data))
    finally F.Free end;
    {$IFDEF UNIX}
    if fpLink(RawByteString(Temp),RawByteString(Path))<>0 then
      raise Exception.Create('ціль уже існує або її не можна створити');
    {$ELSE}
    raise Exception.Create('для цієї платформи немає безпечної публікації');
    {$ENDIF}
  finally
    if Temp<>'' then DeleteFile(Temp);
  end;
end;

var Runtime:TCore4Runtime; Source,Answer:RawByteString;
begin
  if (ParamCount<>4) or (ParamStr(1)<>'--виконати-корені') or
     (LowerCase(ExtractFileExt(ParamStr(3)))<>'.sens') or
     (LowerCase(ExtractFileExt(ParamStr(4)))<>'.sens') then begin
    WriteLn(StdErr,'CORE4-КОРЕНІ-ПОМИЛКА: --виконати-корені КОРІНЬ ВХІД.sens НОВИЙ-ВИХІД.sens');
    Halt(64);
  end;
  Runtime:=nil;
  try
    Source:=ReadPhysical(ParamStr(3));
    Runtime:=TCore4Runtime.Create(ParamStr(2));
    Answer:=ExecuteCore4Roots(Runtime,Source);
    SaveNew(ParamStr(4),Answer);
    WriteLn('CORE4-КОРЕНІ-ГАРАЗД');
  except
    on E:Exception do begin
      WriteLn(StdErr,'CORE4-КОРЕНІ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
  Runtime.Free;
end.
