{ G6.112 — 12 цілих фізичних D5:01011(W12,W12) свідків.
  Виходи порівнюються з канонічними незалежними SENS REPL у CI.
  Генератор НЕ семантичний oracle: фіксовані очікувані числа
  перевіряються чинним SubtractNumericPhysical та фактичним ELF.
  1) Чому два фізичних W12 листки поза D5 контекстом opaque?
  2) Хто відповідає за правильний D24 після machine SUB?
  3) Чому byte-identical ELF сильніший за збіг host return code?
  4) Чому негативні форми не повинні породити жодного ELF? }
program test_irwidesub;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericsub,
     wsm.irwidesub,wsm.elfd12sub,wsm.elfgeometry;
var Dir:String;Cases:TStringList;Good,Bad:SizeInt;
    Zero,One,MaxD12,MinD12,D24:RawByteString;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('D5-ВІДНІМАННЯ-СВІДОК-ПРОВАЛ: '+Why) end;

procedure Save(const Name:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;

function Pack(const A:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(A));
  for I:=0 to High(A) do W[I]:=A[I];
  Result:=EncodeT5M(W);
end;

procedure Positive(const LabelText,LDec,RDec,Wanted:RawByteString;Width:SizeInt);
var L,R,Expected,Actual,Physical,OldELF,NewELF:RawByteString;
    NL,NR,Answer:TExplicitNumeric;G:TELFGeometry;
begin
  L:=EncodeNumericDecimal(LDec,12);
  R:=EncodeNumericDecimal(RDec,12);
  NL:=ReadNumericPhysical(L,12);NR:=ReadNumericPhysical(R,12);
  Physical:=Pack(['10','01011',NL.ExactBits,NR.ExactBits,'01']);
  Expected:=EncodeNumericDecimal(Wanted,Width);
  Actual:=SubtractNumericPhysical(L,R,12);
  Need(Actual=Expected,'канонічні еталонні D12/D24 біти не збіглися');
  Answer:=ReadNumericPhysical(Actual,Width);
  Need((Answer.DomainWidth=Width),'не втримано ширину результату');
  NewELF:=BuildIRWideSubELF(Physical,'external/sens');
  OldELF:=BuildD12SubELF(L,R);
  Need(NewELF=OldELF,'WideIR змінив уже перевірені ELF машинні байти');
  VerifySENSELF64(NewELF,G);
  Need((G.Kind=3) and (G.Entry=120),'не прийнято ELF64 PIE');
  Save(String(LabelText)+'.sens',Physical);
  Save(String(LabelText)+'.expected.sens',Expected);
  Save(String(LabelText)+'.reference.elf',OldELF);
  Cases.Add(String(LabelText)+#9+String(LDec)+#9+String(RDec)+#9+
            String(Wanted)+#9+IntToStr(Width));
  Inc(Good);
end;

procedure Refuse(const Why:String;const Physical:RawByteString);
var Failed:Boolean;Image:RawByteString;
begin
  Image:='';Failed:=False;
  try Image:=BuildIRWideSubELF(Physical,'external/sens')
  except on E:Exception do Failed:=True end;
  Need(Failed and (Image=''),'не відхилено '+Why);
  Inc(Bad);
end;

begin
  Need(ParamCount=1,'потрібна фізична тека');
  Dir:=ParamStr(1);Need(DirectoryExists(Dir),'теку не створено');
  Cases:=TStringList.Create;
  try
    Good:=0;Bad:=0;
    Positive('01','0','2047','-2047',12);
    Positive('02','1','-2048','2049',24);
    Positive('03','7','-7','14',12);
    Positive('04','12','12','0',12);
    Positive('05','-2048','1','-2049',24);
    Positive('06','2047','-2048','4095',24);
    Positive('07','-2048','2047','-4095',24);
    Positive('08','-2048','-2048','0',12);
    Positive('09','-1','-1','0',12);
    Positive('10','-3','0','-3',12);
    Positive('11','23','10','13',12);
    Positive('12','10','-204','214',12);
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    One:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
    MaxD12:=ReadNumericPhysical(EncodeNumericDecimal('2047',12),12).ExactBits;
    MinD12:=ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12).ExactBits;
    D24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
    Refuse('чужа D5 голова',Pack(['10','01010',Zero,One,'01']));
    Refuse('чужа D6 голова',Pack(['10','010100',Zero,One,'01']));
    Refuse('чужа D7 голова',Pack(['10','0001011',Zero,One,'01']));
    Refuse('D1 як перший аргумент',Pack(['10','01011','1',One,'01']));
    Refuse('D24 як другий аргумент',Pack(['10','01011',One,D24,'01']));
    Refuse('бракує аргумента',Pack(['10','01011',One,'01']));
    Refuse('зайвий аргумент',Pack(['10','01011',One,One,One,'01']));
    Refuse('непідтриманий вкладений аргумент',
      Pack(['10','01011','10',One,'01',One,'01']));
    Refuse('два корені',Pack(['10','01011',One,One,'01','0']));
    Refuse('крапкова пара',Pack(['10','01011','11',One,One,'01']));
    Refuse('незакрита D2 форма',Pack(['10','01011',One,One]));
    Refuse('голий W12',Pack([One]));
    Refuse('неканонічний байт T5M',#$FF);
    Refuse('порожнє джерело','');
    Refuse('D3 порожнеча як числовий листок',
      Pack(['10','01011','000',One,'01']));
    Refuse('додатковий D2 хвіст',
      Pack(['10','01011',One,One,'01','01']));
    Need((Good=12) and (Bad=16),'матриця не завершена');
    Cases.SaveToFile(Dir+'/cases.tsv');
    WriteLn('D5-WIDE-SUB-OK positives=12 negatives=16');
  finally Cases.Free end;
end.
