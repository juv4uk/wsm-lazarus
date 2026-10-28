{ G3.9: D3:110 COND виконується за pinned SENS Contract 12 K12.3.
  Власний host evaluator НЕ є оракулом: окремо звірити SENS REPL.
  Числова драбина D12+ лишається окремою, тест не приписує їй викличності. }
program test_native_cond;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.nativeeval, wsm.binaryexec, wsm.t5m, wsm.source;
var Engine:TBinaryExecutor; Text:TNativeEvaluator; Checks:SizeInt;

procedure Demand(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('УМОВА-ПРОВАЛ: '+Why);
end;

function Packed(const Source:array of RawByteString):RawByteString;
var Words:TExactWords; I:SizeInt;
begin
  SetLength(Words,Length(Source));
  for I:=0 to High(Source) do Words[I]:=Source[I];
  Result:=EncodeT5M(Words);
end;

procedure ExpectPhysical(const Source:array of RawByteString;
  const Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=Engine.ExecutePhysical(Packed(Source));
  Demand(Actual=Expected,'фізичне D3:110 очікувалось '+Expected+
    ', фактично '+Actual);
end;

procedure RejectPhysical(const Source:array of RawByteString;
  AtWord:SizeInt);
var Failed:Boolean;
begin
  Failed:=False;
  try Engine.ExecutePhysical(Packed(Source));
  except on E:EBinaryExecutionError do
    begin
      Failed:=True;
      Demand(E.WordIndex=AtWord,'точна фізична позиція помилки');
    end;
  end;
  Demand(Failed,'фізично прийнята заборонена гілка');
end;

procedure ExpectText(const Source,Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=Text.EvaluateSource(Source);
  Demand(Actual=Expected,'українська проєкція '+Source);
end;

procedure RejectText(const Source:RawByteString);
var Failed:Boolean;
begin
  Failed:=False;
  try Text.EvaluateSource(Source);
  except on E:ESourceError do begin
    Failed:=True;
    Demand((E.ByteOffset>0) and (E.Line>0) and (E.ByteColumn>0),
      'відсутня точна позиція помилки української проєкції');
  end; end;
  Demand(Failed,'прийнято хибну українську форму '+Source);
end;

procedure Save(const Name:String; const Source:array of RawByteString);
var Raw:RawByteString; F:TFileStream;
begin
  Raw:=Packed(Source);
  F:=TFileStream.Create(Name,fmCreate);
  try F.WriteBuffer(Raw[1],Length(Raw));
  finally F.Free; end;
end;

begin
  Checks:=0;
  Engine:=TBinaryExecutor.Create('external/sens');
  Text:=TNativeEvaluator.Create('external/sens');
  try
    { Справжній фізичний T5M → D2 → pinned binder → evaluator. }
    ExpectPhysical(['10','110','10','1','1','01','01'],'1');
    ExpectPhysical(['10','110','10','1','0','01','01'],'0');
    ExpectPhysical(['10','110','10','0','0','01','10','1','1','01','01'],'1');
    ExpectPhysical(['10','110','10','0','1','01','01'],'()');
    ExpectPhysical(['10','110','01'],'()');

    { Істинна перша гілка не виконує аварійну другу;
      хибна гілка теж не виконує своє аварійне тіло. }
    ExpectPhysical(['10','110','10','1','0','01',
      '10','0','10','100','000','01','01','01'],'0');
    ExpectPhysical(['10','110','10','0','10','100','000','01','01',
      '10','1','1','01','01'],'1');

    { D3:000 не D1:0; поля клаузи рівно два; branch is a list. }
    RejectPhysical(['10','110','10','000','1','01','01'],4);
    RejectPhysical(['10','110','10','1','0','1','01','01'],3);
    RejectPhysical(['10','110','1','01'],3);
    RejectPhysical(['10','110','10','1','10','100','000','01','01','01'],5);

    { Українська проєкція є лише вхідним поданням; механізм той самий.
      Перший свідок із реального pinned examples/migrated/smoke-cond.lisp. }
    ExpectText('(за-умовою (ні ні) ((атом? (як-є ())) так))','1');
    ExpectText('(за-умовою (так ні))','0');
    ExpectText('(за-умовою (ні так))','()');
    ExpectText('(за-умовою)','()');
    ExpectText('(за-умовою (так так) (ні (перше ())))','1');
    ExpectText('(за-умовою (ні (перше ())) (так ні))','0');
    RejectText('(за-умовою (() так))');
    RejectText('(за-умовою ((як-є ()) так))');
    RejectText('(за-умовою (так))');
    RejectText('(за-умовою (так ні так))');
    RejectText('(за-умовою так)');
    RejectText('(за-умовою (так (перше ())))');
    RejectText('(за-умовою ((сполучити так ()) ні))');

    { Виконавець має залишатися придатним після всіх відмов. }
    ExpectPhysical(['10','110','10','1','0','01','01'],'0');
    ExpectText('(за-умовою (так так))','1');

    Save('build/m0.2/native-cond-positive.sens',
      ['10','110','10','0','0','01','10','1','1','01','01']);
    Save('build/m0.2/native-cond-negative.sens',
      ['10','110','10','000','1','01','01']);
    WriteLn('УМОВА-ВИКОНАННЯ-ГАРАЗД перевірок=',Checks,
      ' T5M=так D2=так pinned=так D1=точний D3:000=після-вичерпання',
      ' лінивість=так негативні=відхилені oracle=окремо');
  finally
    Text.Free;
    Engine.Free;
  end;
end.
