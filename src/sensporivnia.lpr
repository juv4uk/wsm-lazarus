{ Український CLI точного фізичного порівняння .sens (не oracle). }
program sensporivnia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.t5mdiff;

{ Явне UTF-8 виведення в байтовий потік, без системної codepage. }
procedure Emit(const MessageText:UnicodeString; ToError:Boolean);
const LF:AnsiChar=#10;
var B:UTF8String; F:THandleStream;
begin
  B:=UTF8Encode(MessageText);
  if ToError then F:=THandleStream.Create(TextRec(StdErr).Handle)
  else F:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
    F.WriteBuffer(LF,1);
  finally F.Free; end;
end;


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
    Emit('Використання: sensporivnia лівий.sens правий.sens',True);
    ExitCode:=64;
  end else try
    ComparePhysicalWords(ReadPhysical(ParamStr(1)),ReadPhysical(ParamStr(2)),C);
    if C.Kind=pdEqual then
      Emit('ФІЗИЧНІ-СВІДКИ-ТОТОЖНІ слів='+IntToStr(C.LeftCount)+
        ' семантика=НЕ-ПЕРЕВІРЕНО',False)
    else begin
      Emit('ФІЗИЧНА-РІЗНИЦЯ вид='+DiffKindName(C.Kind)+
        ' слово='+IntToStr(C.WordIndex)+' біт='+IntToStr(C.BitIndex)+
        ' ліва-ширина='+IntToStr(C.LeftWidth)+
        ' права-ширина='+IntToStr(C.RightWidth)+
        ' ліве='+Address(C.LeftSpan)+' праве='+Address(C.RightSpan)+
        ' семантика=НЕ-ПЕРЕВІРЕНО',False);
      ExitCode:=1;
    end;
  except
    on E:Exception do begin
      Emit('ФІЗИЧНЕ-ПОРІВНЯННЯ-ПОМИЛКА: '+E.Message,True);
      ExitCode:=2;
    end;
  end;
end.
