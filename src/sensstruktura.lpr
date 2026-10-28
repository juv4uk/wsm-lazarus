{ G1.10 — фізичний широкий D2-огляд без семантичного тлумачення.
  W24 ≠ числове значення за самою довжиною; ніхто тут не викликає закон. }
program sensstruktura;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source;
const MaxReportBytes=1024*1024;
var
  F:TFileStream;
  Physical,Report:RawByteString;
  Doc:TD2Document;
  I:SizeInt;

procedure Put(const Item:RawByteString);
begin
  if Length(Item)>MaxReportBytes-Length(Report) then
    raise Exception.Create(#$D0#$9F#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BA#$D0#$B2#$D0#$BE#$D1#$82#$D0#$B0#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D0#$B8#$D0#$B2#$D0#$BE#$D0#$B4#$D1#$83);
  Report:=Report+Item;
end;

procedure Visit(N:TD2Node; Depth:SizeInt);
var J:SizeInt; Tag:RawByteString;
begin
  if N=nil then raise Exception.Create(#$D0#$92#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$44#$32#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB);
  if Depth>MaxD2SyntaxDepth then
    raise Exception.Create(#$D0#$9D#$D0#$B0#$D0#$B4#$D0#$BC#$D1#$96#$D1#$80#$D0#$BD#$D0#$B0#$20#$D0#$B3#$D0#$BB#$D0#$B8#$D0#$B1#$D0#$B8#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$44#$32#$20#$D0#$B4#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B0);
  case N.Kind of
    dkList: Tag:=#$44#$32#$3A#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BA#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8;
    dkPair: Tag:=#$D0#$BF#$D0#$BE#$D1#$85#$D1#$96#$D0#$B4#$D0#$BD#$D0#$B0#$2D#$D0#$BF#$D0#$B0#$D1#$80#$D0#$B0;
    dkEmpty: Tag:='W3:000';
    dkIdentity: Tag:='W'+IntToStr(N.Width)+':'+N.Bits;
  else raise Exception.Create(#$D0#$9D#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$B4#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$44#$32);
  end;
  Put(IntToStr(N.WordIndex)+#9+IntToStr(Depth)+#9+Tag+#10);
  for J:=0 to High(N.Children) do Visit(N.Children[J],Depth+1);
end;

begin
  if (ParamCount<>2) or (ParamStr(1)<>#$2D#$2D#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B0) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$73#$74#$72#$75#$6B#$74#$75#$72#$61#$20#$2D#$2D#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B0#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73);
    Halt(64);
  end;
  Doc:=nil;
  try
    F:=TFileStream.Create(ParamStr(2),fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<=0) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create(#$D0#$9F#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$2E#$73#$65#$6E#$73);
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    Doc:=ReadD2T5MWide(Physical);
    Report:=#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#9#$D0#$B3#$D0#$BB#$D0#$B8#$D0#$B1#$D0#$B8#$D0#$BD#$D0#$B0#9#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$BE#$D0#$B7#$D0#$BE#$D1#$80#$D0#$B0#$2D#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B0#10;
    for I:=0 to High(Doc.Roots) do Visit(Doc.Roots[I],0);
    Write(Report); { атомарно лише після повної фізичної перевірки }
  except
    on E:ED2SourceError do begin
      WriteLn(StdErr,#$D0#$A1#$D0#$A2#$D0#$A0#$D0#$A3#$D0#$9A#$D0#$A2#$D0#$A3#$D0#$A0#$D0#$90#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D,E.WordIndex,' ',E.Message);
      ExitCode:=2;
    end;
    on E:Exception do begin
      WriteLn(StdErr,#$D0#$A1#$D0#$A2#$D0#$A0#$D0#$A3#$D0#$9A#$D0#$A2#$D0#$A3#$D0#$A0#$D0#$90#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$20,E.Message);
      ExitCode:=2;
    end;
  end;
  Doc.Free;
end.
