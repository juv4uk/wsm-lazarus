{ G5.27 — незалежні фізичні очікування для ОСТАННЬОГО результату
  сеансу. Тільки відомі дійсні результати pinned Core4 свідків,
  а не лексичне декодування надрукованого Wn:bits. }
program TestCore4SessionLiveCapture;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m;

procedure Require(Condition:Boolean;const Message:String);
begin
  if not Condition then raise Exception.Create('ОСТАННІЙ-СВІДОК: '+Message);
end;

procedure SaveWords(const Path:String;const Words:array of RawByteString);
var Exact,Recovered:TExactWords;Physical:RawByteString;
    I:SizeInt;FileOut:TFileStream;
begin
  SetLength(Exact,Length(Words));
  for I:=0 to High(Exact) do Exact[I]:=Words[I];
  Physical:=EncodeT5M(Exact);
  DecodeT5M(Physical,Recovered);
  Require(Length(Recovered)=Length(Exact),'не збіглася кількість слів');
  for I:=0 to High(Exact) do
    Require(Recovered[I]=Exact[I],'порушено точну ширину/біти');
  FileOut:=TFileStream.Create(Path,fmCreate);
  try
    Require(Length(Physical)>0,'немає фізичних байтів');
    FileOut.WriteBuffer(Physical[1],Length(Physical));
  finally FileOut.Free end;
end;

var Dir:String;W:TExactWords;I:SizeInt;
begin
  Require(ParamCount=1,'потрібна тека свідків');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  SaveWords(Dir+'останній-так-очікування.sens',['1']);
  SaveWords(Dir+'останній-ні-очікування.sens',['0']);
  SaveWords(Dir+'останній-пакет3-очікування.sens',
    ['1','0','000000000000000000000000']);
  SaveWords(Dir+'останній-укр2-очікування.sens',['1','0']);
  SetLength(W,64);
  for I:=0 to High(W) do W[I]:='1';
  SaveWords(Dir+'останній-пакет64-очікування.sens',W);
  WriteLn('CORE4-ОСТАННЯ-ВІДПОВІДЬ-СВІДКИ-ГАРАЗД W1 W24 3/64 точні-T5M');
end.
