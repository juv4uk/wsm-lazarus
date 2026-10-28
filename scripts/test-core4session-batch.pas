{ G5.19 — фізичні багатоформові свідки лише з чинних pinned Core4 fixtures.
  Конкатенація байтів T5M НЕ є конкатенацією форм; декодуємо exact words. }
program test_core4session_batch;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m;

procedure Check(B:Boolean;const Msg:String);
begin if not B then raise Exception.Create('СВІДОК: '+Msg) end;

function ReadBytes(const Path:String):RawByteString;
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmOpenRead);
  try
    Check((S.Size>0) and (S.Size<MAX_T5M_FILE_BYTES),'розмір '+Path);
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

procedure Save(const Path:String;const Bytes:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;

function Batch(const Paths:array of String):RawByteString;
var
  OutWords,InputWords:TExactWords;
  I,J,N:SizeInt;
begin
  OutWords:=nil;
  for I:=0 to High(Paths) do begin
    DecodeT5M(ReadBytes(Paths[I]),InputWords);
    N:=Length(OutWords);
    SetLength(OutWords,N+Length(InputWords));
    for J:=0 to High(InputWords) do OutWords[N+J]:=InputWords[J];
  end;
  Result:=EncodeT5M(OutWords);
end;

var Dir:String;P:array of String;I:SizeInt;
begin
  Check(ParamCount=1,'потрібна тека чинних Core4-фікстур');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  SetLength(P,3);
  P[0]:=Dir+'01-tak.sens';
  P[1]:=Dir+'03-ni.sens';
  P[2]:=Dir+'05-global-d24-0.sens';
  Save(Dir+'paket3.sens',Batch(P));
  P[2]:=Dir+'02-nevidome.sens';
  Save(Dir+'paket-pomylka.sens',Batch(P));
  SetLength(P,64);
  for I:=0 to High(P) do P[I]:=Dir+'01-tak.sens';
  Save(Dir+'paket64.sens',Batch(P));
  SetLength(P,65);
  P[64]:=Dir+'01-tak.sens';
  Save(Dir+'paket65.sens',Batch(P));
  Save(Dir+'paket-porozhnie.sens','');
  Save(Dir+'paket-nekorektne.sens',AnsiChar(243));
  WriteLn('CORE4-PAKET-SVIDKY-OK forms=3,64,65 late-failure=3');
end.
