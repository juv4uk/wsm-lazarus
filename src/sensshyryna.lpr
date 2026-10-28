{ Нативний оглядач фізичних D12+ ширин.
  .lisp — людська українська проєкція, НЕ вхід цього CLI.
  Не обчислюємо числа: тільки T5M та точні позиції. }
program sensshyryna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.widespan;
function Ukr(const S: UnicodeString): RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
function Run: Integer;
var F:TFileStream; Physical, Report:RawByteString;
    Wide:TWideWords; Path:String;
begin
  Result:=64;
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>Ukr('--широкі-слова')) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') then begin
    WriteLn(StdErr,Ukr('Використання: sensshyryna --широкі-слова файл.sens'));
    Exit;
  end;
  Result:=2;
  try
    Path:=ParamStr(2);
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise EWideSpanError.Create('порожній або завеликий фізичний файл');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    CollectWideWords(Physical,Wide);
    Report:=WideTSV(Wide);
    { Жодного stdout, доки всі слова і всі TSV рядки не допущено. }
    Write(Report);
    Result:=0;
  except on E:Exception do
    WriteLn(StdErr,Ukr('ШИРОКІ-СЛОВА-ПОМИЛКА: '),E.Message);
  end;
end;
begin
  ExitCode:=Run;
end.
