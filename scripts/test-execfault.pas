{ Позитивні та негативні фізичні координати, не семантичний oracle. }
program test_execfault;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.binaryexec, wsm.execfault;
var Engine:TBinaryExecutor; Checks:SizeInt;
procedure Check(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,'EXECFAULT-FAIL ',Why);
    Halt(1);
  end;
end;
function Physical(const Items:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Items));
  for I:=0 to High(Items) do W[I]:=Items[I];
  Result:=EncodeT5M(W);
end;
procedure SaveFile(const Path:String; const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free; end;
end;
procedure ExpectBad(const Data:RawByteString; Word:SizeInt;
  Located, IsEOF:Boolean; TStart,TEnd,BStart,BEnd:SizeInt;
  const Name:String);
var Failed:Boolean;
begin
  Failed:=False;
  try ExecuteWithPhysicalLocation(Data,Engine);
  except on E:ELocatedExecutionFault do begin
    Failed:=True;
    Check(E.WordIndex=Word,Name+' word index');
    Check(E.HasPhysicalSpan=Located,Name+' false physical certainty');
    if Located then begin
      Check(E.Span.WordIndex=Word,Name+' span word');
      Check(E.Span.IsEOF=IsEOF,Name+' EOF flag');
      Check((E.Span.TritStart=TStart) and (E.Span.TritEnd=TEnd),
        Name+' trit half-open range');
      Check((E.Span.ByteStart=BStart) and (E.Span.ByteEnd=BEnd),
        Name+' byte half-open range');
    end else
      Check((E.Span.WordIndex=0) and (E.Span.TritStart=0) and
        (E.Span.ByteStart=0),Name+' missing span must be zero');
  end; end;
  Check(Failed,Name+' invalid program accepted');
end;
begin
  Checks:=0;
  Engine:=TBinaryExecutor.Create('external/sens');
  try
    Check(ExecuteWithPhysicalLocation(
      Physical(['10','111','1','000','01']),Engine)='(1)',
      'D3 real execution unchanged');
    Check(ExecuteWithPhysicalLocation(Physical(['1']),Engine)='1',
      'D1 exact value unchanged');
    { D3:001 physical word 2 spans trits 3..6, shared physical
      byte 0 and 1. NO invented byte=word offset. }
    ExpectBad(Physical(['10','001','000','01']),2,True,False,
      3,6,0,2,'D3 quote blocked');
    { Nested unknown D3 call head at physical word 5:
      10 | 111 | 1 | 10 | 110 | 1 | 01 | 01 }
    ExpectBad(Physical(['10','111','1','10','110','1','01','01']),
      5,True,False,12,15,2,3,'nested D3 head');
    ExpectBad(Physical(['10','100','000','01']),
      1,True,False,0,2,0,1,'selector on empty');
    { D2 parser signals expected word count+1 at EOF.
      Last meaningful trit=4 but byte cursor includes padding. }
    ExpectBad(Physical(['10','1']),3,True,True,
      4,4,1,1,'unclosed D2 EOF');
    ExpectBad(Physical(['01']),1,True,False,
      0,2,0,1,'stray D2 close');
    ExpectBad(Physical(['1','0']),2,True,False,
      2,3,0,1,'two roots');
    ExpectBad(#243,0,False,False,0,0,0,0,'forbidden T5M byte');
    ExpectBad(#242,0,False,False,0,0,0,0,'bad T5M padding');
    Check(ExecuteWithPhysicalLocation(Physical(['0']),Engine)='0',
      'recover after several failures');
    { Fixtures for real CLI: negative stdout must stay empty. }
    SaveFile('build/m0.2/execfault-valid.sens',
      Physical(['10','111','1','000','01']));
    SaveFile('build/m0.2/execfault-quote.sens',
      Physical(['10','001','000','01']));
    SaveFile('build/m0.2/execfault-nested.sens',
      Physical(['10','111','1','10','110','1','01','01']));
    SaveFile('build/m0.2/execfault-eof.sens',
      Physical(['10','1']));
    SaveFile('build/m0.2/execfault-corrupt.sens',#243);
  finally Engine.Free; end;
  WriteLn('EXECFAULT-OK fpc exact-word=так trits=half-open ',
    'bytes=half-open eof=distinct invalid-carrier=unknown ',
    'native-evaluator=shared checks=',Checks);
end.
