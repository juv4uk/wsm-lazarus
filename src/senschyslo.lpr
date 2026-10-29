{ Одне знакове число як звичайний український людський token .lisp.
  Файл .sens — канонічні T5M байти; D12+ задано явно зовні,
  жодного змішування із D1:0 або D3:000. Це НЕ SENS evaluator. }
program senschyslo;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.numericplane{$IFDEF UNIX}, BaseUnix{$ENDIF};
{$IFDEF UNIX}
function CreatePrivateTemp(Template:PChar):cint; cdecl; external 'c' name 'mkstemp';
{$ENDIF}
function ReadLimited(const Path: String; MaxBytes:SizeInt):RawByteString;
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<=0) or (Stream.Size>MaxBytes) then
      raise Exception.Create(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free;end;
end;

{ Ці host-файлові байти — canonical T5M з перевіреного явного D12+ домену.
  Path: запозичений шлях ОС; Data: керований RawByteString, власник caller.
  mkstemp створює приватний файл mode=0600; fpWrite перевіряє короткі записи;
  fpLink атомарно публікує ТІЛЬКИ відсутню ціль, включно із symlink-гонками.
  Навіть dangling symlink не перезаписуємо. Жодного SENS законодавства тут немає.
  Питання: 1) Чому RenameFile не є no-clobber? 2) Чому не можна повторно
  відкривати mkstemp через fmCreate? 3) Що робимо при fpWrite<Length?
  4) Яке фізичне представлення містить Data? }
procedure SaveNewPhysical(const Path:String; const Data:RawByteString);
{$IFDEF UNIX}
var Temp:RawByteString; FD:cint; Offset,Written:SizeInt;
    Created:Boolean;
{$ENDIF}
begin
  if (Length(Data)<1) or (Length(Data)>64) then
    raise Exception.Create('неприпустима довжина фізичного числа');
  {$IFDEF UNIX}
  Temp:=''; FD:=-1; Created:=False;
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path)))+'numXXXXXX');
    UniqueString(Temp);
    FD:=CreatePrivateTemp(PChar(Temp));
    if FD<0 then
      raise Exception.Create('не створено приватний числовий файл');
    Created:=True;
    Offset:=0;
    while Offset<Length(Data) do begin
      Written:=fpWrite(FD,Data[Offset+1],Length(Data)-Offset);
      if Written<=0 then
        raise Exception.Create('не записано повний фізичний T5M');
      Inc(Offset,Written);
    end;
    if fpClose(FD)<>0 then begin
      FD:=-1;
      raise Exception.Create('не закрито фізичний числовий файл');
    end;
    FD:=-1;
    if fpLink(Temp,RawByteString(Path))<>0 then
      raise Exception.Create('ціль уже існує або захищена від запису');
  finally
    if FD>=0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise Exception.Create('безпечна атомарна публікація на цій ОС недоступна');
  {$ENDIF}
end;

function ProcessCommand:Integer;
var Width:SizeInt; Bytes,Decimal:RawByteString;
    N:TExplicitNumeric;
begin
  Result:=64;
  if not (((ParamCount=3) and (ParamStr(1)='--'+#$D0#$B2#$2D#$D1#$83#$D0#$BA#$D1#$80)) or
     ((ParamCount=4) and (ParamStr(1)='--'+#$D0#$B7#$2D#$D1#$83#$D0#$BA#$D1#$80))) then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$63#$68#$79#$73#$6C#$6F#$20#$2D#$2D#$D0#$B2#$2D#$D1#$83#$D0#$BA#$D1#$80#$20#$44#$31#$32#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73#$20#$7C#$20#$2D#$2D#$D0#$B7#$2D#$D1#$83#$D0#$BA#$D1#$80#$20#$44#$31#$32#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$6C#$69#$73#$70#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73);
    Exit;
  end;
  try
    Width:=SelectedNumericDomain(ParamStr(2));
    if ParamCount=3 then begin
      if LowerCase(ExtractFileExt(ParamStr(3)))<>'.sens' then
        raise Exception.Create(#$D0#$B4#$D0#$BB#$D1#$8F#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D1#$85#$D0#$BE#$D0#$B4#$D1#$83#$20#$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$B5#$D0#$BD#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$20#$2E#$73#$65#$6E#$73);
      Bytes:=ReadLimited(ParamStr(3),64);
      N:=ReadNumericPhysical(Bytes,Width);
      Decimal:=RenderNumericDecimal(N);
      WriteLn(Decimal); { лише людська проєкція, не SENS value }
    end else begin
      if LowerCase(ExtractFileExt(ParamStr(3)))<>'.lisp' then
        raise Exception.Create(#$D0#$B4#$D0#$BB#$D1#$8F#$20#$D0#$BB#$D1#$8E#$D0#$B4#$D1#$81#$D1#$8C#$D0#$BA#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B4#$D0#$B6#$D0#$B5#$D1#$80#$D0#$B5#$D0#$BB#$D0#$B0#$20#$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$BD#$D0#$B0#$20#$2E#$6C#$69#$73#$70);
      if LowerCase(ExtractFileExt(ParamStr(4)))<>'.sens' then
        raise Exception.Create(#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D1#$85#$D1#$96#$D0#$B4#$20#$D0#$BC#$D1#$83#$D1#$81#$D0#$B8#$D1#$82#$D1#$8C#$20#$D0#$BC#$D0#$B0#$D1#$82#$D0#$B8#$20#$2E#$73#$65#$6E#$73);
      Decimal:=ReadLimited(ParamStr(3),96);
      if (Length(Decimal)>0) and (Decimal[Length(Decimal)]=#10) then begin
        Delete(Decimal,Length(Decimal),1);
        if (Length(Decimal)>0) and (Decimal[Length(Decimal)]=#13) then
          Delete(Decimal,Length(Decimal),1);
      end;
      Bytes:=EncodeNumericDecimal(Decimal,Width);
      SaveNewPhysical(ParamStr(4),Bytes);
    end;
    Result:=0;
  except
    on E:Exception do begin
      WriteLn(StdErr,#$D0#$A7#$D0#$98#$D0#$A1#$D0#$9B#$D0#$9E#$D0#$92#$D0#$90#$2D#$D0#$9F#$D0#$A0#$D0#$9E#$D0#$84#$D0#$9A#$D0#$A6#$D0#$86#$D0#$AF#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20,E.Message);
      Result:=2;
    end;
  end;
end;

begin
  { Halt лише після повернення з процедури — локальні FPC managed
    рядки й файли до цього часу вже звільнені. }
  Halt(ProcessCommand);
end.
