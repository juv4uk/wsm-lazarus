{ G6.39 — лише генератор точних фізичних T5M свідків для CLI.
  Не виконує мовних законів, а кодує затверджені D3-слова;
  незалежний x86-64 запуск і byte-exact stdout перевіряє shell. }
program test_senselfvykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

procedure Save(const Path:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;

procedure Pair(const Dir,LabelText:String;const Input,Output:array of RawByteString);
begin
  Save(Dir+'/'+LabelText+'.sens',EncodeT5M(W(Input)));
  Save(Dir+'/'+LabelText+'.expected.sens',EncodeT5M(W(Output)));
end;

var Dir:String;Big:RawByteString;
begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Потрібна тека фізичних свідків');Halt(64);
  end;
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);

  { Кожен вхід містить фізичний D2 виклик із ратифікованою D3
    головою. W7 0010110 — SYN, 7-бітні ДАНІ, НЕ виклик. }
  Pair(Dir,'p01',['10','001','0010110','01'],['0010110']);
  Pair(Dir,'p02',['10','001','1','01'],['1']);
  Pair(Dir,'p03',['10','010','10','111','0','1','01','01'],['0']);
  Pair(Dir,'p04',['10','010','000','01'],['1']);
  Pair(Dir,'p05',['10','101','0','1','01'],['0']);
  Pair(Dir,'p06',['10','101','1','1','01'],['1']);
  Pair(Dir,'p07',['10','100','10','111','1','0','01','01'],['1']);
  Pair(Dir,'p08',['10','011','10','111','1','0','01','01'],['0']);
  Pair(Dir,'p09',['10','110','10','1','1','01','01'],['1']);
  Pair(Dir,'p10',['10','110','01'],['000']);

  Save(Dir+'/bad-t5m.sens',#$F3);
  Save(Dir+'/bare-d1.sens',EncodeT5M(W(['0'])));
  Save(Dir+'/d12-atom.sens',EncodeT5M(W([
    '10','010','000000000000','01'])));
  Save(Dir+'/d12-cond.sens',EncodeT5M(W([
    '10','110','10','000000000000','1','01','01'])));
  Save(Dir+'/truncated.sens',EncodeT5M(W([
    '10','110','10','1','1'])));
  Save(Dir+'/empty.sens','');
  Big:=StringOfChar('x',65537);
  Save(Dir+'/huge.sens',Big);
  WriteLn('ФІЗИЧНІ-СВІДКИ-МАШИНИ-ГОТОВІ позитивів=10 негативних-входів=7');
end.

{ Memory: W allocates a transient array of immutable RawByteString words;
  EncodeT5M returns owned packed binary bytes; Save owns only one
  TFileStream, closed even on failure. No REPL, Core4, numeric semantics.
  Питання: (1) Чому W7 SYN має ширину 7? (2) Чому D3:000
  не стає D1:0? (3) Чому випадки D12+ відкладено до emitter admission?
  (4) Чому label p01 — лише host ім'я, не surface?
  (5) Як байти .expected.sens звіряються з реальним x86-64 stdout? }
