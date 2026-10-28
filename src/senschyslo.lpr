{ Одне знакове число як звичайний український людський token .lisp.
  Файл .sens — канонічні T5M байти; D12+ задано явно зовні,
  жодного змішування із D1:0 або D3:000. Це НЕ SENS evaluator. }
program senschyslo;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.numericplane;
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

procedure SaveNewPhysical(const Path:String; const Data:RawByteString);
var Temp:String; Stream:TFileStream;
begin
  if FileExists(Path) then
    raise Exception.Create(#$D1#$86#$D1#$96#$D0#$BB#$D1#$8C#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$20#$D1#$83#$D0#$B6#$D0#$B5#$20#$D1#$96#$D1#$81#$D0#$BD#$D1#$83#$D1#$94);
  Temp:=Path+'.temp-numeric';
  if FileExists(Temp) then
    raise Exception.Create(#$D1#$82#$D0#$B8#$D0#$BC#$D1#$87#$D0#$B0#$D1#$81#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$20#$D1#$83#$D0#$B6#$D0#$B5#$20#$D1#$96#$D1#$81#$D0#$BD#$D1#$83#$D1#$94);
  try
    Stream:=TFileStream.Create(Temp,fmCreate);
    try Stream.WriteBuffer(Data[1],Length(Data));
    finally Stream.Free;end;
    if FileExists(Path) or not RenameFile(Temp,Path) then
      raise Exception.Create(#$D0#$BD#$D0#$B5#$D0#$BC#$D0#$BE#$D0#$B6#$D0#$BB#$D0#$B8#$D0#$B2#$D0#$BE#$20#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC#$D0#$B0#$D1#$80#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$BF#$D1#$83#$D0#$B1#$D0#$BB#$D1#$96#$D0#$BA#$D1#$83#$D0#$B2#$D0#$B0#$D1#$82#$D0#$B8#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB);
  finally
    if FileExists(Temp) then DeleteFile(Temp);
  end;
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
