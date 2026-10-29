{ CLI: два двійкові файли .sens, не порівняння людської проєкції. }
program sensriznytsia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.t5mdiff;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('очікується файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('невірний розмір фізичного .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
function AsWord(const S:RawByteString;Present:Boolean):String;
begin
  if Present then Result:='W'+IntToStr(Length(S))+':'+String(S)
  else Result:='КІНЕЦЬ-ФАЙЛУ';
end;
var L,R:RawByteString; D:TPhysicalDifference;
begin
  if (ParamCount<>3) or (ParamStr(1)<>'--порівняти') then begin
    WriteLn(StdErr,'Виклик: sensriznytsia --порівняти перший.sens другий.sens');
    Halt(64);
  end;
  try
    L:=ReadPhysical(ParamStr(2));
    R:=ReadPhysical(ParamStr(3));
    ComparePhysical(L,R,D);
    if D.Equal then WriteLn('СЕНС-ФІЗИЧНО-РІВНІ')
    else WriteLn('СЕНС-ФІЗИЧНА-ВІДМІННІСТЬ слово=',D.WordIndex,
      ' ліворуч=',AsWord(D.LeftBits,D.LeftPresent),
      ' трити=[',D.LeftSpan.TritStart,',',D.LeftSpan.TritEnd,')',
      ' байти=[',D.LeftSpan.ByteStart,',',D.LeftSpan.ByteEnd,')',
      ' праворуч=',AsWord(D.RightBits,D.RightPresent),
      ' трити=[',D.RightSpan.TritStart,',',D.RightSpan.TritEnd,')',
      ' байти=[',D.RightSpan.ByteStart,',',D.RightSpan.ByteEnd,')');
  except on E:Exception do begin
    WriteLn(StdErr,'СЕНС-ПОРІВНЯННЯ-ПОМИЛКА: ',E.Message);
    Halt(65);
  end end;
end.
