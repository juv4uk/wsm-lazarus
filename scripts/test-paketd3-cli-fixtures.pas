{ G3.17. Позитивні/негативні ФІЗИЧНІ T5M fixture, не SENS закони. }
program test_paketd3_cli_fixtures;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m;

procedure Store(const Dir, Name:String; const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally
    F.Free;
  end;
end;

function Pack(const B:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(B));
  for I:=0 to High(B) do W[I]:=B[I];
  Result:=EncodeT5M(W);
end;

function Many(N:SizeInt):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,N);
  for I:=0 to N-1 do
    if (I and 1)=0 then W[I]:='0' else W[I]:='1';
  Result:=EncodeT5M(W);
end;

var Dir:String;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  Store(Dir,'one.sens',Pack(['0']));
  Store(Dir,'one-answer.sens',Pack(['0']));
  Store(Dir,'four.sens',Pack(['0','00','10','001','000','01','00',
    '10','111','1','0','01','10','001','111111111','01']));
  Store(Dir,'four-answer.sens',
    Pack(['0','000','10','1','11','0','01','111111111']));
  Store(Dir,'64.sens',Many(64));
  Store(Dir,'64-answer.sens',Many(64));
  Store(Dir,'65.sens',Many(65));
  Store(Dir,'late-bad.sens',Pack(['0','10','001','1','0','01']));
  Store(Dir,'bad-t5m.sens',#$F3);
  Store(Dir,'d12.sens',Pack(['0','10','001','000000000000','01']));
  Store(Dir,'not-program.lisp',Pack(['0']));
  WriteLn('СВІДКИ-ПАКЕТ-D3-ГОТОВО');
end.
