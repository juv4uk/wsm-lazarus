{ G6.85 — фізичний host framing ДВОХ ОКРЕМИХ packed D1 atom files.
  Конкатенація не є одиничним SENS .sens документом.
  Очікувані відповіді зберігаються ОКРЕМО чинним test-sensmashyna
  (ExecutePhysicalT5M), а незалежну семантику звіряє pinned REPL.
  Тут НЕ реалізовано EQ, D1 Boolean чи жодної мовної операції. }
program test_elfd1potik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m;

procedure Save(const Path:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try if Bytes<>'' then Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;

function Atom(const Bit:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);
  Words[0]:=Bit;
  Result:=EncodeT5M(Words);
  if Length(Result)<>1 then
    raise ET5MError.Create('один W1 не упакувався в один байт');
end;

procedure Pair(const Dir,LabelText,LeftBit,RightBit:String);
var L,R:RawByteString;
begin
  L:=Atom(RawByteString(LeftBit));
  R:=Atom(RawByteString(RightBit));
  Save(Dir+'/'+LabelText+'-l.sens',L);
  Save(Dir+'/'+LabelText+'-r.sens',R);
  Save(Dir+'/'+LabelText+'.frame',L+R);
end;

var Dir:String;L,R:RawByteString;W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Pair(Dir,'тотожні-00','0','0');
  Pair(Dir,'тотожні-01','0','1');
  Pair(Dir,'тотожні-10','1','0');
  Pair(Dir,'тотожні-11','1','1');
  L:=Atom('0');R:=Atom('1');
  Save(Dir+'/порожній.frame','');
  Save(Dir+'/короткий.frame',L);
  Save(Dir+'/зайвий.frame',L+R+L);
  Save(Dir+'/небінарний.frame',#$F3+R);
  Save(Dir+'/ASCII.frame','01');
  Save(Dir+'/помилковий-перший.frame',#$00+R);
  Save(Dir+'/помилковий-другий.frame',L+#$00);
  SetLength(W,1);
  W[0]:='0010110';
  Save(Dir+'/д7.frame',EncodeT5M(W));
  Save(Dir+'/розширений.frame',L+R+#0);
  Save(Dir+'/дві-одиниці.frame',R+R);
  if (L=R) or (Length(L)<>1) or (Length(R)<>1) then Halt(2);
  { Тут host-рядок — не SENS проєкція; W1 файли двійкові. }
  WriteLn('D1-POTIK-FRAMES-OK pairs=4 negatives=9');
end.
