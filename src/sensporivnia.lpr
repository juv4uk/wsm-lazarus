{ Український CLI точного фізичного порівняння .sens (не oracle). }
program sensporivnia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.t5mdiff;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('вхід повинен бути фізичним .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або завеликий .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

function Address(const S:TPhysicalWordSpan):String;
begin
  if S.IsEOF then Exit('EOF байт='+IntToStr(S.ByteStart));
  Result:='трити=['+IntToStr(S.TritStart)+','+IntToStr(S.TritEnd)+
    ') байти=['+IntToStr(S.ByteStart)+','+IntToStr(S.ByteEnd)+')';
end;

var C:TPhysicalComparison;
begin
  ExitCode:=0;
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Використання: sensporivnia лівий.sens правий.sens');
    ExitCode:=64;
  end else try
    ComparePhysicalWords(ReadPhysical(ParamStr(1)),ReadPhysical(ParamStr(2)),C);
    if C.Kind=pdEqual then
      WriteLn('ФІЗИЧНІ-СВІДКИ-ТОТОЖНІ слів=',C.LeftCount,
        ' семантика=НЕ-ПЕРЕВІРЕНО')
    else begin
      WriteLn('ФІЗИЧНА-РІЗНИЦЯ вид=',DiffKindName(C.Kind),
        ' слово=',C.WordIndex,' біт=',C.BitIndex,
        ' ліва-ширина=',C.LeftWidth,' права-ширина=',C.RightWidth,
        ' ліве=',Address(C.LeftSpan),' праве=',Address(C.RightSpan),
        ' семантика=НЕ-ПЕРЕВІРЕНО');
      ExitCode:=1;
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'ФІЗИЧНЕ-ПОРІВНЯННЯ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
