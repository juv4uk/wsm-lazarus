{ G6.125 — 14 реальних nested D5(D5:mul)(D5:mul) свідків.
  Тестовий fixture — не oracle. Signed arith admission приймає pinned
  шари; реальний ELF і pinned SENS CLI звіряються окремо.
  1) Чому проміжний добуток D24 відхиляємо до emission?
  2) Чому D24 може бути точним кінцевим результатом?
  3) Що доводить повторне byte-exact складання ELF?
  4) Чому всі 4 числа мають canonical 12 фізичних бітів? }
program test_irtwomuladd;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericmul,
  wsm.numericadd,wsm.irtwomuladd,wsm.elfgeometry;
var Dir:String;M:TStringList;Positives,Negatives,Wide:SizeInt;
    Zero,One,D24:RawByteString;

procedure Need(OK:Boolean;const Reason:String);
begin if not OK then raise Exception.Create('ДВА-ДОБУТКИ-ТЕСТ-ПРОВАЛ: '+Reason) end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

function Pack(const A:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(A));
  for I:=0 to High(A) do W[I]:=A[I];
  Result:=EncodeT5M(W);
end;

function NumBits(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
    'хибна ширина фізичного D12');
  Result:=N.ExactBits;
end;

function Physical(const ABits,BBits,CBits,DBits:RawByteString):RawByteString;
begin
  Result:=Pack(['10','01010',
    '10','10110',ABits,BBits,'01',
    '10','10110',CBits,DBits,'01','01']);
end;

{ A/B/C/D borrowed decimal тестові fixtures, НЕ функціональні SENS
  символи. Result — збережені packed .sens, очікувані T5M та ELF.
  Повний compiler ніколи не покладається на fixture text.
  1) Яким законом встановлено точність продуктів?
  2) Чому elf proof не є pinned oracle?
  3) Хто закриває потоки Save? }
procedure Positive(const LabelText,A,B,C,D,Answer:RawByteString;
  ExpectedWidth:SizeInt);
var PA,PB,PC,PD,P1,P2,S,PhysicalInput,ELFImage:RawByteString;
    N:TExplicitNumeric;G:TELFGeometry; Width:SizeInt;
begin
  PA:=EncodeNumericDecimal(A,12);PB:=EncodeNumericDecimal(B,12);
  PC:=EncodeNumericDecimal(C,12);PD:=EncodeNumericDecimal(D,12);
  P1:=MultiplyNumericPhysical(PA,PB,12);
  P2:=MultiplyNumericPhysical(PC,PD,12);
  N:=ReadNumericPhysical(P1,12);Need(N.DomainWidth=12,'перший продукт потребує D24');
  N:=ReadNumericPhysical(P2,12);Need(N.DomainWidth=12,'другий продукт потребує D24');
  S:=AddNumericPhysical(P1,P2,12);
  try N:=ReadNumericPhysical(S,12);Width:=12
  except on E:ENumericPlaneError do begin
    N:=ReadNumericPhysical(S,24);Width:=24;
  end end;
  Need((Width=ExpectedWidth) and
    (S=EncodeNumericDecimal(Answer,ExpectedWidth)),
    'непогоджений canonical numeric result');
  PhysicalInput:=Physical(NumBits(A),NumBits(B),NumBits(C),NumBits(D));
  ELFImage:=BuildIRTwoMulAddELF(PhysicalInput,'external/sens');
  VerifySENSELF64(ELFImage,G);
  Need((G.Kind=3) and (G.Entry=120),'непідтверджений машинний ELF');
  Need(BuildIRTwoMulAddELF(PhysicalInput,'external/sens')=ELFImage,
    'компіляція не детермінована на тих самих фізичних бітах');
  Save(String(LabelText)+'.sens',PhysicalInput);
  Save(String(LabelText)+'.expected.sens',S);
  Save(String(LabelText)+'.elf',ELFImage);
  M.Add(String(LabelText)+#9+IntToStr(ExpectedWidth));
  Inc(Positives);
  if ExpectedWidth=24 then Inc(Wide);
end;

procedure Refuse(const LabelText:String;const Input:RawByteString);
var Image:RawByteString;Failed:Boolean;
begin
  Image:='';Failed:=False;
  try Image:=BuildIRTwoMulAddELF(Input,'external/sens')
  except on E:Exception do Failed:=True end;
  Need(Failed and (Image=''),'не відхилено '+LabelText);
  Save('bad-'+LabelText+'.sens',Input);
  Inc(Negatives);
end;
begin
  Need(ParamCount=1,'потрібна тека для фізичних свідків');
  Dir:=ParamStr(1);
  Need(ForceDirectories(Dir),'не вдалося створити фізичну теку');
  M:=TStringList.Create;
  try
    Positives:=0;Negatives:=0;Wide:=0;
    Positive('01','3','4','5','6','42',12);
    Positive('02','0','2047','3','-7','-21',12);
    Positive('03','-1','-1','0','0','1',12);
    Positive('04','7','7','2','9','67',12);
    Positive('05','20','30','-3','20','540',12);
    Positive('06','-2','3','4','5','14',12);
    Positive('07','-3','-3','-4','-4','25',12);
    Positive('08','1','2047','-1','2047','0',12);
    Positive('09','-2048','0','2047','1','2047',12);
    Positive('10','1','-2048','0','0','-2048',12);
    Positive('11','100','10','100','11','2100',24);
    Positive('12','-100','10','-110','11','-2210',24);
    Positive('13','2047','1','1','1','2048',24);
    Positive('14','-2048','1','-1','1','-2049',24);
    Zero:=NumBits('0');One:=NumBits('1');
    D24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
    Refuse('чужа-зовнішня-голова',Pack(['10','01011','10','10110',Zero,One,'01','10','10110',One,One,'01','01']));
    Refuse('чужа-ліва-голова',Pack(['10','01010','10','01010',Zero,One,'01','10','10110',One,One,'01','01']));
    Refuse('чужа-права-голова',Pack(['10','01010','10','10110',Zero,One,'01','10','01011',One,One,'01','01']));
    Refuse('D6-голова',Pack(['10','01010','10','10110',Zero,One,'01','10','010100',One,One,'01','01']));
    Refuse('D7-голова',Pack(['10','01010','10','10110',Zero,One,'01','10','0010110',One,One,'01','01']));
    Refuse('лівий-D1',Physical('1',One,Zero,One));
    Refuse('правий-D1',Physical(Zero,One,'0',One));
    Refuse('лівий-D24',Physical(D24,One,Zero,One));
    Refuse('правий-D24',Physical(Zero,One,One,D24));
    Refuse('ліве-вкладене-недостатня-арність',Pack(['10','01010','10','10110',Zero,'01','10','10110',One,One,'01','01']));
    Refuse('праве-вкладене-зайва-арність',Pack(['10','01010','10','10110',Zero,One,'01','10','10110',One,One,Zero,'01','01']));
    Refuse('відсутня-права-гілка',Pack(['10','01010','10','10110',Zero,One,'01','01']));
    Refuse('плоска-форма',Pack(['10','01010',Zero,One,Zero,One,'01']));
    Refuse('крапкова-права-гілка',Pack(['10','01010','10','10110',Zero,One,'01','11','10110',One,One,'01','01']));
    Refuse('два-корені',Pack(['10','01010','10','10110',Zero,One,'01','10','10110',One,One,'01','01','0']));
    Refuse('незакрито',Pack(['10','01010','10','10110',Zero,One,'01','10','10110',One,One,'01']));
    Refuse('голий-атом',Pack([One]));
    Refuse('неканонічний-T5M',#$FF);
    Refuse('проміжний-D24-ліворуч',Physical(NumBits('200'),NumBits('20'),Zero,One));
    Refuse('проміжний-D24-праворуч',Physical(Zero,One,NumBits('-2048'),NumBits('-2')));
    Need((Positives=14) and (Negatives=20) and (Wide=4),
      'неповна матриця або хибне D24 розширення');
    M.SaveToFile(Dir+'/cases.tsv');
    WriteLn('ДВА-ДОБУТКИ-СВІДКИ-ГАРАЗД positives=14 negatives=20 widened=4');
  finally M.Free end;
end.
