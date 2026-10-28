{ G5.21: незалежний механічний свідок канонічних фізичних
  відповідей startup. Жодних нових семантичних значень чи законів. }
program TestCore4SessionCapture;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m;

var Words,Recovered:TExactWords;Physical:RawByteString;OutputPath:String;
    Stream:TFileStream;I:SizeInt;
begin
  if ParamCount<>1 then
    raise Exception.Create('потрібен шлях очікуваного фізичного .sens');
  OutputPath:=ParamStr(1);
  SetLength(Words,5);
  Words[0]:='1';
  Words[1]:='1';
  Words[2]:='0';
  Words[3]:='000000000000000000000000';
  Words[4]:='0';
  Physical:=EncodeT5M(Words);
  DecodeT5M(Physical,Recovered);
  if Length(Recovered)<>Length(Words) then
    raise Exception.Create('кількість exact слів не збереглась');
  for I:=0 to High(Words) do
    if Recovered[I]<>Words[I] then
      raise Exception.Create('порушено точну ширину/біти');
  Stream:=TFileStream.Create(OutputPath,fmCreate);
  try
    Stream.WriteBuffer(Physical[1],Length(Physical));
  finally Stream.Free end;
  WriteLn('CORE4-ОЧІКУВАНІ-БАЙТИ-ГАРАЗД слів=5 W1=4 W24=1');
end.
