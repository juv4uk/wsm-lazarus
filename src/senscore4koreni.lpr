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

{ G4.37: POSIX mkstemp атомарно створює один новий файл з mode=0600
  та залишає дескриптор відкритим. fmCreate поверх готового tempfile
  ПОМИЛКОВО відновлює mode=0644: це вже доведено незалежним CI.
  Лише host-байти canonical .sens, не проєкція .lisp і не закон SENS. }
{$IFDEF UNIX}
function CreatePrivateTemp(Template:PChar):cint; cdecl; external 'c' name 'mkstemp';
{$ENDIF}

{ Data: owned RawByteString фізичних T5M байтів, Path: host-ціль;
  не копіюємо й не міняємо Data. Один FD живе лише в межах SaveNew.
  fpWrite допускає часткове виконання; fpLink публікує цілий результат
  лише після успішного закриття, не замінюючи зайняту ціль.
  Питання для перевірки механізму:
  1. Чому перевідкриття tempfile через fmCreate губить mode=0600?
  2. Чому fd потрібно отримати одночасно з атомарним створенням?
  3. Чому fpLink має відбутися лише після останнього fpWrite/fpClose?
  4. Що станеться з temp, коли ціль — dangling symlink? }
procedure SaveNew(const Path:String;const Data:RawByteString);
{$IFDEF UNIX}
var Temp:RawByteString; FD:cint; Offset,Written:SizeInt;
    Created:Boolean;
{$ENDIF}
begin
  if (Length(Data)<1) or (Length(Data)>MAX_T5M_FILE_BYTES) then
    raise Exception.Create('неприпустимий розмір фізичної відповіді');
  {$IFDEF UNIX}
  Temp:='';FD:=-1;Created:=False;
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path)))+'c4kXXXXXX');
    { mkstemp змінює шість X безпосередньо в унікальному буфері. }
    UniqueString(Temp);
    FD:=CreatePrivateTemp(PChar(Temp));
    if FD<0 then
      raise Exception.Create('не створено приватний тимчасовий файл');
    Created:=True;
    Offset:=0;
    while Offset<Length(Data) do
    begin
      Written:=fpWrite(FD,Data[Offset+1],Length(Data)-Offset);
      if Written<=0 then
        raise Exception.Create('не записано повну фізичну відповідь');
      Inc(Offset,Written);
    end;
    if fpClose(FD)<>0 then
    begin
      FD:=-1;
      raise Exception.Create('не закрито фізичну відповідь');
    end;
    FD:=-1;
    if fpLink(Temp,RawByteString(Path))<>0 then
      raise Exception.Create('ціль уже існує або її не можна створити');
  finally
    if FD>=0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise Exception.Create('для цієї платформи немає безпечної публікації');
  {$ENDIF}
end;

{ Host індекс є десятковою позицією кореня у фізичній ВІДПОВІДІ,
  не числовим SENS доменом D12+ й не частиною програмного dispatch. }
function ReadRootIndex(const Text:String):SizeInt;
var I:LongInt; { TryStrToInt у FPC 3.2.x має параметр var LongInt }
begin
  if (not TryStrToInt(Text,I)) or (I<1) or (I>64) or
     (IntToStr(I)<>Text) then
    raise Exception.Create('індекс відповіді має бути канонічним десятковим 1..64');
  Result:=I;
end;

var Runtime:TCore4Runtime; Source,Answer:RawByteString;
    Pick:Boolean; InputPath,OutputPath:String; Index:SizeInt;
begin
  Pick:=(ParamCount=5) and (ParamStr(1)='--виконати-й-вибрати');
  if not Pick then begin
    if (ParamCount<>4) or (ParamStr(1)<>'--виконати-корені') then begin
      WriteLn(StdErr,'CORE4-КОРЕНІ-ПОМИЛКА: --виконати-корені КОРІНЬ ВХІД.sens НОВИЙ-ВИХІД.sens або --виконати-й-вибрати КОРІНЬ ІНДЕКС ВХІД.sens НОВИЙ-ВИХІД.sens');
      Halt(64);
    end;
    InputPath:=ParamStr(3);OutputPath:=ParamStr(4);
  end else begin
    InputPath:=ParamStr(4);OutputPath:=ParamStr(5);
  end;
  if (LowerCase(ExtractFileExt(InputPath))<>'.sens') or
     (LowerCase(ExtractFileExt(OutputPath))<>'.sens') then begin
    WriteLn(StdErr,'CORE4-КОРЕНІ-ПОМИЛКА: потрібні фізичні .sens шляхи');
    Halt(64);
  end;
  Runtime:=nil;
  try
    if Pick then Index:=ReadRootIndex(ParamStr(3))
    else Index:=0;
    Source:=ReadPhysical(InputPath);
    Runtime:=TCore4Runtime.Create(ParamStr(2));
    { Спершу РЕАЛЬНО виконуємо весь пакет: непідтримана пізня
      форма не дозволяє вибрати ранню відповідь як успішну. }
    Answer:=ExecuteCore4Roots(Runtime,Source);
    if Pick then Answer:=SelectCore4Result(Answer,Index);
    SaveNew(OutputPath,Answer);
    if Pick then WriteLn('CORE4-ВИБІР-ГАРАЗД корінь=',Index)
    else WriteLn('CORE4-КОРЕНІ-ГАРАЗД');
  except
    on E:Exception do begin
      WriteLn(StdErr,'CORE4-КОРЕНІ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
  Runtime.Free;
end.
