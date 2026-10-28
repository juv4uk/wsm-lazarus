program test_binaryexec;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.binaryexec;
var E:TBinaryExecutor; Checks:SizeInt;
procedure Require(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then begin WriteLn(StdErr,#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$98#$D0#$99#$2D#$D0#$A2#$D0#$95#$D0#$A1#$D0#$A2#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$20,Why); Halt(1); end;
end;
function WordsOf(const Data:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Data));
  for I:=0 to High(Data) do Result[I]:=Data[I];
end;
procedure Expect(const Data:array of RawByteString;
  const Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=E.ExecutePhysical(EncodeT5M(WordsOf(Data)));
  Require(Actual=Expected,#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B0#$D0#$B2#$D0#$B8#$D0#$BB#$D1#$8C#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82#$20+String(Actual));
end;
procedure Reject(const Data:array of RawByteString;
  ExpectedIndex:SizeInt);
var Failed:Boolean;
begin
  Failed:=False;
  try E.ExecutePhysical(EncodeT5M(WordsOf(Data)));
  except on X:EBinaryExecutionError do begin
    Failed:=True;
    if ExpectedIndex>=0 then
      Require(X.WordIndex=ExpectedIndex,#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B0#$D0#$B2#$D0#$B8#$D0#$BB#$D1#$8C#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$96#$D0#$BD#$D0#$B4#$D0#$B5#$D0#$BA#$D1#$81#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B0);
  end; end;
  Require(Failed,#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$96#$D0#$B4#$D1#$82#$D0#$B2#$D0#$B5#$D1#$80#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0#$20#$D0#$BD#$D0#$B5#$20#$D0#$B1#$D1#$83#$D0#$BB#$D0#$B0#$20#$D0#$B2#$D1#$96#$D0#$B4#$D1#$85#$D0#$B8#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$B0);
end;
procedure WriteBinary(const Name:String;
  const Data:array of RawByteString);
var F:TFileStream; B:RawByteString;
begin
  B:=EncodeT5M(WordsOf(Data));
  F:=TFileStream.Create(Name,fmCreate);
  try F.WriteBuffer(B[1],Length(B));
  finally F.Free; end;
end;
var Failed:Boolean;
begin
  Checks:=0;
  if ParamCount=1 then begin
    { Механічний тест: pinned двійкові рядки незмінні, але проєкції
      «ук» D1/D3 навмисно стерто в копії таблиць ТІЛЬКИ для тесту.
      Пряме виконання НЕ може залежати від українського spelling. }
    E:=TBinaryExecutor.Create(ParamStr(1));
    try
      Expect(['1'],'1');
      Expect(['0'],'0');
      Expect(['000'],'()');
      Expect(['10','111','1','000','01'],'(1)');
      Expect(['10','010','000','01'],'1');
      Expect(['10','100','10','111','0','000','01','01'],'0');
      Expect(['10','001','1','01'],'1');
      Expect(['10','111','0','000','01'],'(0)');
    finally E.Free; end;
    WriteLn(#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$98#$D0#$99#$2D#$D0#$9F#$D0#$A0#$D0#$AF#$D0#$9C#$D0#$98#$D0#$99#$2D#$D0#$93#$D0#$90#$D0#$A0#$D0#$90#$D0#$97#$D0#$94#$20#$D1#$83#$D0#$BA#$5F#$44#$31#$5F#$44#$33#$3D#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$20,
      #$65#$78#$61#$63#$74#$5F#$64#$69#$73#$70#$61#$74#$63#$68#$3D#$D1#$82#$D0#$B0#$D0#$BA#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$BE#$D0#$BA#$3D,Checks);
    Halt(0);
  end;
  E:=TBinaryExecutor.Create('external/sens');
  try
    Expect(['1'],'1');
    Expect(['0'],'0');
    Expect(['000'],'()');
    Expect(['10','01'],'()');
    Expect(['10','111','1','000','01'],'(1)');
    Expect(['10','111','1','0','01'],'(1 . 0)');
    Expect(['10','100','10','111','0','000','01','01'],'0');
    Expect(['10','011','10','111','1','000','01','01'],'()');
    Expect(['10','010','10','111','1','000','01','01'],'0');
    Expect(['10','010','000','01'],'1');
    Expect(['10','001','000','01'],'()'); { pinned D3:001 }
    Reject(['10','111','1','11','0','01'],1); { dotted }
    Reject(['10','110','1','01'],3); { невалідна гілка: атом замість двопольового списку }
    { Чотири негативні фізичні регресії з уже MERGED #118.
      Без перетворення в UTF-8: NativeEval.ByteOffset = D2 WordIndex. }
    Reject(['10','111','1','10','100','000','01','01'],4);
    Reject(['10','111','1','10','110','1','01','01'],6); { помилка тепер на хибній гілці }
    Reject(['10','111','1','10','111','1','01','01'],4);
    Reject(['10','111','1','010','01'],4); { відсутній native D3 cond }
    Reject(['1111111'],1); { D7 без непідтвердженого dispatch }
    Reject(['111111111'],1); { D9 }
    Reject(['1','0'],2); { дві форми }
    Reject(['00'],1); { немає форм }
    Reject(['01'],1); { D2 close }
    Reject(['10','1'],3); { D2 не закрито }
    Reject(['10','111','1','01'],1); { arity }
    Expect(['10','111',
      '10','100','10','111','0','000','01','01',
      '10','111','1','000','01','01'],'(0 1)');
    Reject(['10','100','000','01'],1); { селектор потребує pair }
    Expect(['1'],'1'); { після fail arena очищено }
    Failed:=False;
    try E.ExecutePhysical(#243);
    except on X:EBinaryExecutionError do begin
      Failed:=True; Require(X.WordIndex=0,#$D0#$B7#$D1#$96#$D0#$BF#$D1#$81#$D0#$BE#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$B8#$D0#$B9#$20#$54#$35#$4D#$20#$D0#$BC#$D0#$B0#$D1#$94#$20#$69#$6E#$64#$65#$78#$3D#$30);
    end; end;
    Require(Failed,#$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$20#$54#$35#$4D#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE);
    Failed:=False;
    try E.ExecutePhysical(#242);
    except on X:EBinaryExecutionError do Failed:=True; end;
    Require(Failed,#$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$70#$61#$64#$64#$69#$6E#$67#$20#$54#$35#$4D#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE);
    WriteBinary('build/m0.2/binaryexec-valid.sens',
      ['10','111','1','000','01']);
    WriteBinary('build/m0.2/binaryexec-invalid.sens',
      ['10','000','000','01']); { D3:000 як голова невикличне }
  finally E.Free; end;
  WriteLn(#$D0#$94#$D0#$92#$D0#$86#$D0#$99#$D0#$9A#$D0#$9E#$D0#$92#$D0#$95#$2D#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$2D#$D0#$9E#$D0#$9A#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$BE#$D0#$BA#$3D,Checks,
    #$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$3D#$54#$35#$4D#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B0#$3D#$44#$32#$20#$D0#$BF#$D1#$96#$D0#$B4#$D0#$BC#$D0#$BD#$D0#$BE#$D0#$B6#$D0#$B8#$D0#$BD#$D0#$B0#$3D#$44#$31#$2F#$44#$33#$20#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$3D#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$B0#$2D#$D0#$BF#$D1#$96#$D0#$B4#$D0#$BC#$D0#$BD#$D0#$BE#$D0#$B6#$D0#$B8#$D0#$BD#$D0#$B0,
    #$20#$43#$6F#$72#$65#$34#$3D#$D0#$9D#$D0#$95#$5F#$D0#$92#$D0#$98#$D0#$9A#$D0#$9E#$D0#$9D#$D0#$A3#$D0#$84#$D0#$A2#$D0#$AC#$D0#$A1#$D0#$AF);
end.
