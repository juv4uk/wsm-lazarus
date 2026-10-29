{ G6.100: один canonical .sens D3:110 -> чинний ExactIR lowering
  -> НОВІ x86-64 rel32 JZ/JMP -> один ET_DYN ELF64.
  Порівнюємо виконуваний результат із попереднім уже перевіреним
  BuildPinnedIRCondELF та окремим pinned SENS REPL.
  Входи і виходи — справжні T5M, не людська ASCII-семантика.
  Готові ELF створюємо в каталозі тесту; allocation та його очистка
  належать bash harness. FPC records локальні до одного свідка.

  Питання: 1) Чому один байт D1 не можна вгадувати за цифрою?
  2) Чому два різні машинні образи можуть повертати той самий SENS?
  3) Як виявити неатомарну відмову по Result?
  4) Чому D3:000 та D1:0 мають різні expected .sens? }
program test_ircondbranch;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.ircond,wsm.ircondbranch,wsm.elfgeometry;
var Passed,Rejected:SizeInt; DirectoryName:String;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;
procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('IR-ПЕРЕХОДИ-ПРОВАЛ: '+Why);
end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(DirectoryName+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Positive(const Name:String;const ExpectedWord:RawByteString;
  const SourceWords:array of RawByteString);
var Physical,Image,OldImage,Expected,OracleText:RawByteString;
    Geom:TELFGeometry; Found:TExactWords; I:SizeInt;
begin
  Physical:=EncodeT5M(W(SourceWords));
  Image:=BuildIRCondBranchELF(Physical,'external/sens');
  OldImage:=BuildPinnedIRCondELF(Physical,'external/sens');
  Check(Image=BuildIRCondBranchELF(Physical,'external/sens'),
    Name+': недетерміновані машинні байти');
  Check(Image<>OldImage,Name+': замість нового JZ/JMP writer старий ELF');
  VerifySENSELF64(Image,Geom);
  Check((Geom.Kind=3) and (Geom.MachineBytes>0) and
        (Geom.MachineBytes<=256),Name+': неправильна ELF64 PIE геометрія');
  Check(Pos(#$0F#$84,Image)>0 orelse (Length(SourceWords)=3),
    Name+': немає host JZ rel32 для фізичної гілки');
  Expected:=EncodeT5M(W([ExpectedWord]));
  DecodeT5M(Expected,Found);
  Check((Length(Found)=1) and (Found[0]=ExpectedWord),
    Name+': неправильний фізичний T5M еталон');
  Save(Name+'.sens',Physical);
  Save(Name+'.branch.elf',Image);
  Save(Name+'.legacy.elf',OldImage);
  Save(Name+'.expected.sens',Expected);
  if ExpectedWord='000' then OracleText:='()'+#10
  else OracleText:=ExpectedWord+#10;
  Save(Name+'.oracle.txt',OracleText);
  Inc(Passed);
end;

function SeriesWords(Clauses,TrueAt:SizeInt):TExactWords;
var I,P:SizeInt;
begin
  Check((Clauses>=0) and (Clauses<=5) and
        (TrueAt>=-1) and (TrueAt<Clauses),'генератор за квотою');
  SetLength(Result,3+4*Clauses);
  Result[0]:='10';Result[1]:='110';
  for I:=0 to Clauses-1 do begin
    P:=2+4*I;
    Result[P]:='10';
    if I=TrueAt then Result[P+1]:='1'
    else Result[P+1]:='0';
    if (I mod 2)=0 then Result[P+2]:='0'
    else Result[P+2]:='1';
    Result[P+3]:='01';
  end;
  Result[High(Result)]:='01';
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Image:RawByteString; Failed:Boolean; MessageText:String;
begin
  Image:=''; Failed:=False;MessageText:='';
  try Image:=BuildIRCondBranchELF(Physical,'external/sens')
  except on E:Exception do begin Failed:=True;MessageText:=E.Message end end;
  Check(Failed and (Image='') and (Length(MessageText)>4),
    Name+': позитив або неповна відмова');
  Inc(Rejected);
end;
procedure Negative(const Name:String;
  const Parts:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(W(Parts))) end;

begin
  Check((ParamCount=1) and DirectoryExists(ParamStr(1)),
    'вкажіть існуючий каталог фізичних свідків');
  DirectoryName:=ParamStr(1);
  Passed:=0;Rejected:=0;

  Positive('порожня','000',['10','110','01']);
  Positive('одна-хибна','000',['10','110','10','0','1','01','01']);
  Positive('одна-істинна-нуль','0',['10','110','10','1','0','01','01']);
  Positive('одна-істинна-один','1',['10','110','10','1','1','01','01']);
  Positive('друга-істинна','1',
    ['10','110','10','0','0','01','10','1','1','01','01']);
  Positive('першу-обрано','1',
    ['10','110','10','1','1','01','10','1','0','01','01']);
  Positive('дві-хибні','000',
    ['10','110','10','0','1','01','10','0','0','01','01']);
  Positive('чотири-остання','1',SeriesWords(4,3));
  Positive('чотири-вичерпано','000',SeriesWords(4,-1));
  Positive('вкладений-тест','0',
    ['10','110','10','10','101','1','1','01','0','01','01']);
  Positive('вкладений-пропуск','000',
    ['10','110','10','10','101','0','1','01','0','01','01']);
  Positive('вкладений-вираз','1',
    ['10','110','10','1','10','101','0','0','01','01','01']);
  Positive('обидва-вкладені','0',
    ['10','110','10','10','101','1','1','01',
       '10','101','1','0','01','01','01']);

  Negative('пʼять-гілок',SeriesWords(5,-1));
  Negative('хибна-голова',['10','101','10','1','0','01','01']);
  Negative('три-поля',['10','110','10','1','0','1','01','01']);
  Negative('D7-тест',['10','110','10','0010110','1','01','01']);
  Negative('D12-тест',['10','110','10','000000000000','1','01','01']);
  Negative('D12-вираз',['10','110','10','1','000000000000','01','01']);
  Negative('D3-порожній-тест',['10','110','10','000','1','01','01']);
  Negative('два-корені',['10','110','01','0']);
  NegativeRaw('битий-T5M',#$F3);
  NegativeRaw('порожній-T5M','');
  Negative('непідтриманий-EQ',
    ['10','110','10','10','101','0','01','1','01','01']);
  Check((Passed=13) and (Rejected=11),
    'неповна матриця перевірених позитивів/негативів');
  WriteLn('IR-ПЕРЕХОДИ-ГАРАЗД elfs=',Passed,
    ' negative=',Rejected,
    ' T5M=physical reference=old-ircond pinned-REPL=external',
    ' machine=JZ-JMP-rel32 energy=NOT-MEASURED');
end.
