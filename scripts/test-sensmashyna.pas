{ G6.31: джерело очікуваних результатів — існуючий D3 evaluator.
  Це sanity witness, НЕ незалежний SENS REPL oracle. }
program test_sensmashyna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.binaryexec;
var Root,Dir:String; Count:SizeInt;
function Exact(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
procedure Save(const Path:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if B<>'' then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;
procedure Fixture(const Name:RawByteString;
  const Form:array of RawByteString);
var Source,Answer:RawByteString; Engine:TBinaryExecutor;
begin
  Source:=EncodeT5M(Exact(Form));
  Engine:=TBinaryExecutor.Create(RawByteString(Root));
  try Answer:=Engine.ExecutePhysicalT5M(Source);
  finally Engine.Free end;
  if (Answer='') or (Length(Answer)>4096) then
    raise Exception.Create('Порожня або завелика фізична відповідь');
  Save(Dir+'/'+String(Name)+'.sens',Source);
  Save(Dir+'/'+String(Name)+'.expected.sens',Answer);
  Inc(Count);
end;
begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні: pinned SENS і каталог свідків');
    Halt(64);
  end;
  Root:=ParamStr(1);Dir:=ParamStr(2);
  if not ForceDirectories(Dir) then
    raise Exception.Create('Неможливо створити каталог свідків');
  Count:=0;
  Fixture('цитата-д7',['10','001','0010110','01']);
  Fixture('цитата-список',['10','001','10','0','1','01','01']);
  Fixture('атом-один',['10','010','1','01']);
  Fixture('атом-пара',['10','010','10','111','0','1','01','01']);
  Fixture('тотожні-00',['10','101','0','0','01']);
  Fixture('тотожні-01',['10','101','0','1','01']);
  Fixture('тотожні-10',['10','101','1','0','01']);
  Fixture('тотожні-11',['10','101','1','1','01']);
  Save(Dir+'/помилковий-байт.sens',#$F3);
  Save(Dir+'/незакрита-форма.sens',EncodeT5M(Exact(['10','101','0','1'])));
  Save(Dir+'/хибний-д12.sens',EncodeT5M(Exact(['10','101',
    '000000000000','1','01'])));
  Save(Dir+'/порожній.sens','');
  if Count<>8 then raise Exception.Create('Неповна вибірка');
  WriteLn('МАШИНА-СВІДКИ-ГАРАЗД фізичних=8 режимів=3');
end.
