{ G6.57 — машинний COND із перевіреного фізичного ExactIR, не parser.
  Канонічний вихід лише T5M; oracle — окремий pinned SENS, не FPC. }
program test_ircond;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.ircond,wsm.elfgeometry;
var Passed,Rejected:SizeInt;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then
    raise Exception.Create('ТОЧНА-УМОВА-IR-ПРОВАЛ: '+Why);
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Positive(const Name,ExpectedWord:RawByteString;
  const SourceWords:array of RawByteString;
  const ExpectedClauses:SizeInt);
var
  Physical,Image,Expected:RawByteString;
  Lowered:TLoweredIRCond;
  Geom:TELFGeometry;
  OracleText:RawByteString;
begin
  Physical:=EncodeT5M(W(SourceWords));
  LowerPinnedIRCond(Physical,'external/sens',Lowered);
  Check((Lowered.Count=ExpectedClauses) and (Lowered.HeadWord=2),
    String(Name)+': втрачено голову або порядок умов');
  Image:=BuildPinnedIRCondELF(Physical,'external/sens');
  Check(Image=BuildPinnedIRCondELF(Physical,'external/sens'),
    String(Name)+': недетермінований образ');
  VerifySENSELF64(Image,Geom);
  { Не часовий benchmark: статична метрика компактного ELF64 коду.
    17 байтів/гілку + 38 байтів спільного машинного виходу. }
  Check((Geom.Kind=3) and
        (Geom.MachineBytes=38+17*ExpectedClauses),
    String(Name)+': ELF64 PIE не має одного спільного машинного виходу');
  if ExpectedClauses>0 then begin
    Check(Pos(#$83#$F8#$01#$75,Image)>0,
      String(Name)+': немає справжньої x86-64 умови CMP/JNE');
    Check(Pos(#$75#$07#$B3,Image)>0,
      String(Name)+': неправильно обчислено пропуск машинної гілки');
  end;
  Expected:=EncodeT5M(W([ExpectedWord]));
  Save('build/m0.2/ircond/'+String(Name)+'.sens',Physical);
  Save('build/m0.2/ircond/'+String(Name)+'.elf',Image);
  Save('build/m0.2/ircond/'+String(Name)+'.expected.sens',Expected);
  if ExpectedWord='000' then OracleText:='()'+#10
  else OracleText:=ExpectedWord+#10;
  Save('build/m0.2/ircond/'+String(Name)+'.oracle.txt',OracleText);
  Inc(Passed);
end;

{ Генератор структурних свідків; жодного людського диспетчера.
  D2:10/01 обрамлює списки, D3:110 і D1:0/1 — pinned exact слова.
  Фізичні байти утворюються ВИКЛЮЧНО чинним EncodeT5M. }
function SeriesWords(Clauses,TrueAt:SizeInt):TExactWords;
var I,P:SizeInt;
begin
  Check((Clauses>=0) and (Clauses<=33) and
        (TrueAt>=-1) and (TrueAt<Clauses),
    'Неприпустима host-геометрія генератора умов');
  SetLength(Result,3+4*Clauses);
  Result[0]:='10';
  Result[1]:='110';
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

procedure PositiveSeries(const Name:RawByteString;
  Clauses,TrueAt:SizeInt);
var Expected:RawByteString;
begin
  if TrueAt=-1 then Expected:='000'
  else if (TrueAt mod 2)=0 then Expected:='0'
  else Expected:='1';
  Positive(Name,Expected,SeriesWords(Clauses,TrueAt),Clauses);
end;

procedure NegativeRaw(const Name,Physical:RawByteString);
var Image:RawByteString;Lowered:TLoweredIRCond;Failed:Boolean;
begin
  Lowered.Count:=255;Failed:=False;
  try LowerPinnedIRCond(Physical,'external/sens',Lowered);
  except on E:Exception do Failed:=True end;
  Check(Failed and (Lowered.Count=0),
    String(Name)+': lowering не відхилив атомарно');
  Failed:=False; Image:='';
  try Image:=BuildPinnedIRCondELF(Physical,'external/sens');
  except on E:Exception do Failed:=True end;
  Check(Failed and (Image=''),
    String(Name)+': видано ELF із непідтриманої форми');
  Inc(Rejected);
end;

procedure Negative(const Name:RawByteString;
  const SourceWords:array of RawByteString);
begin
  NegativeRaw(Name,EncodeT5M(W(SourceWords)));
end;

begin
  ForceDirectories('build/m0.2/ircond');
  Passed:=0;Rejected:=0;
  Positive('порожня','000',['10','110','01'],0);
  Positive('одна-хибна','000',
    ['10','110','10','0','1','01','01'],1);
  Positive('одна-істинна-0','0',
    ['10','110','10','1','0','01','01'],1);
  Positive('одна-істинна-1','1',
    ['10','110','10','1','1','01','01'],1);
  Positive('друга-істинна-0','0',
    ['10','110','10','0','1','01','10','1','0','01','01'],2);
  Positive('друга-істинна-1','1',
    ['10','110','10','0','0','01','10','1','1','01','01'],2);
  Positive('перша-істинна','1',
    ['10','110','10','1','1','01','10','1','0','01','01'],2);
  Positive('обидві-хибні','000',
    ['10','110','10','0','1','01','10','0','0','01','01'],2);

  Positive('три-перша-істинна','0',
    ['10','110','10','1','0','01','10','0','1','01',
      '10','0','1','01','01'],3);
  Positive('три-друга-істинна','1',
    ['10','110','10','0','0','01','10','1','1','01',
      '10','1','0','01','01'],3);
  Positive('три-третя-істинна','1',
    ['10','110','10','0','0','01','10','0','0','01',
      '10','1','1','01','01'],3);
  Positive('три-всі-хибні','000',
    ['10','110','10','0','1','01','10','0','1','01',
      '10','0','1','01','01'],3);

  PositiveSeries('чотири-остання',4,3);
  PositiveSeries('вісім-остання',8,7);
  PositiveSeries('шістнадцять-середня',16,8);
  PositiveSeries('тридцятьдві-перша',32,0);
  PositiveSeries('тридцятьдві-середня',32,15);
  PositiveSeries('тридцятьдві-остання',32,31);
  PositiveSeries('тридцятьдві-вичерпано',32,-1);

  Negative('самотній-D1',['1']);
  Negative('інша-D3-голова',['10','101','10','1','0','01','01']);
  Negative('три-поля',['10','110','10','1','0','1','01','01']);
  Negative('одне-поле',['10','110','10','1','01','01']);
  Negative('порожній-тест',['10','110','10','000','1','01','01']);
  Negative('D7-тест',['10','110','10','0010110','1','01','01']);
  Negative('D12-тест',['10','110','10','000000000000','1','01','01']);
  Negative('D2-порожній-тест',['10','110','10','10','01','1','01','01']);
  Negative('D12-вираз',['10','110','10','1','000000000000','01','01']);
  Negative('D7-вираз',['10','110','10','1','0010110','01','01']);
  Negative('порожній-вираз',['10','110','10','1','000','01','01']);
  Negative('тридцятьтри-гілки',SeriesWords(33,-1));
  Negative('вкладена-рівність',
    ['10','110','10','10','101','1','1','01','0','01','01']);
  Negative('два-корені',['10','110','01','0']);
  Negative('не-допарений-D2',['10','110','10','1','1','01']);
  Negative('крапкова-гілка',['10','110','10','1','11','0','01','01']);
  NegativeRaw('пошкоджений-фізичний',#$F3);
  NegativeRaw('порожній-файл','');
  Check((Passed=19) and (Rejected=18),
    'кількість перевірених фізичних свідків');
  WriteLn('ТОЧНА-УМОВА-IR-ГАРАЗД ELF64-PIE=',Passed,
    ' негативи=',Rejected,
    ' T5M=байт-у-байт D3:000=не-D1:0',
    ' один-машинний-вихід=так максимум-гілок=32');
  WriteLn('ТОЧНА-УМОВА-IR-МЕЖА Core4=не-підтримано',
    ' вкладені-EQ=не-підтримано числа-D12+=не-підтримано');
end.
