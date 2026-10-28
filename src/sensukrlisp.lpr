{ G1.8 — тільки звичайна українська .lisp проєкція, не SENS канон.
  Команда не обчислює SENS, не завантажує Core4 і не змінює закони. }
program sensukrlisp;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.t5m, wsm.bind, wsm.ukroundtrip;

const MaxTextBytes=1024*1024;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

function ReadBounded(const Path:String; Maximum:SizeInt):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>Maximum) then
      raise EUkRoundtripError.Create(UkrBytes('Вхід порожній або перевищує межу байтів'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

procedure PublishWithoutOverwrite(const Path:String; const Data:RawByteString);
var Temporary:String; F:TFileStream;
begin
  if FileExists(Path) or DirectoryExists(Path) then
    raise EUkRoundtripError.Create(UkrBytes('Вихідний файл вже існує'));
  if Data='' then
    raise EUkRoundtripError.Create(UkrBytes('Порожній результат заборонено'));
  Temporary:=GetTempFileName(
    ExtractFilePath(ExpandFileName(Path)),'suk');
  try
    F:=TFileStream.Create(Temporary,fmCreate);
    try F.WriteBuffer(Data[1],Length(Data));
    finally F.Free; end;
    { POSIX hard-link створює ціль АТОМАРНО лише якщо її ще немає;
      жодного TOCTOU overwrite між FileExists та RenameFile. }
    if fpLink(PChar(Temporary),PChar(Path))<>0 then
      raise EUkRoundtripError.Create(UkrBytes('Не вдалося атомарно створити вихід без перезапису'));
  finally
    DeleteFile(Temporary);
  end;
end;

function Run:LongInt;
var
  InputPath,OutputPath:String;
  Source,ResultBytes:RawByteString;
  Tables:TDomainSet;
  Longs:TLongProjection;
  ToUkr:Boolean;
begin
  Result:=64;
  if ParamCount<>3 then begin
    WriteLn(StdErr,UkrBytes('Використання: sensukrlisp --вивести-ук вхід.sens вихід.lisp або --пакувати-ук вхід.lisp вихід.sens'));
    Exit;
  end;
  ToUkr:=RawByteString(ParamStr(1))=UkrBytes('--вивести-ук');
  if (not ToUkr) and
     (RawByteString(ParamStr(1))<>UkrBytes('--пакувати-ук')) then begin
    WriteLn(StdErr,UkrBytes('Використання: sensukrlisp --вивести-ук / --пакувати-ук'));
    Exit;
  end;
  InputPath:=ParamStr(2); OutputPath:=ParamStr(3);
  if ToUkr then begin
    if (LowerCase(ExtractFileExt(InputPath))<>'.sens') or
       (LowerCase(ExtractFileExt(OutputPath))<>'.lisp') then begin
      WriteLn(StdErr,UkrBytes('ПОМИЛКА: потрібні вхід.sens та вихід.lisp'));
      Exit;
    end;
  end else begin
    if (LowerCase(ExtractFileExt(InputPath))<>'.lisp') or
       (LowerCase(ExtractFileExt(OutputPath))<>'.sens') then begin
      WriteLn(StdErr,UkrBytes('ПОМИЛКА: потрібні вхід.lisp та вихід.sens'));
      Exit;
    end;
  end;
  Result:=2;
  try
    if FileExists(OutputPath) or DirectoryExists(OutputPath) then
      raise EUkRoundtripError.Create(UkrBytes('Вихідний файл вже існує'));
    if ToUkr then Source:=ReadBounded(InputPath,MAX_T5M_FILE_BYTES)
    else Source:=ReadBounded(InputPath,MaxTextBytes);
    LoadPinnedDomains('external/sens',Tables);
    LoadPinnedLongProjection('external/sens',Tables,Longs);
    if ToUkr then ResultBytes:=PhysicalToUkrainian(Source,Tables,Longs)
    else ResultBytes:=UkrainianToPhysical(Source,Tables,Longs);
    PublishWithoutOverwrite(OutputPath,ResultBytes);
    if ToUkr then
      WriteLn(UkrBytes('УКРАЇНСЬКА-ПРОЄКЦІЯ-ГАРАЗД .sens→.lisp байтів='),Length(ResultBytes))
    else
      WriteLn(UkrBytes('УКРАЇНСЬКЕ-ПАКУВАННЯ-ГАРАЗД .lisp→.sens байтів='),Length(ResultBytes));
    Result:=0;
  except
    on E:Exception do WriteLn(StdErr,UkrBytes('УКРАЇНСЬКА-ПРОЄКЦІЯ-ПОМИЛКА: '),E.Message);
  end;
end;

begin
  ExitCode:=Run;
end.
