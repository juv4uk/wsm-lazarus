{ G6.55: фізичний ExactIR → прямі машинні байти для D3:100/011. }
program test_ir_lowered_selector;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,
  wsm.exactirguard,wsm.irlowerselector;

var
  Root,InDir,OutDir:String;
  Tables:TDomainSet;
  IR:TExactIR;
  Physical:RawByteString;
  Positives,Negatives,Mutations:SizeInt;

function UA(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Check(OK:Boolean;const Why:UnicodeString);
begin
  if not OK then raise Exception.Create(UA(
    UnicodeString('ПРЯМЕ-ЗНИЖЕННЯ-СЕЛЕКТОРА-ПОМИЛКА: ')+Why));
end;

function W(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  Result:=nil;
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

function ReadBytes(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Check((F.Size>=1) and (F.Size<=65536),
      UnicodeString('розмір фізичного файла: ')+UnicodeString(Path));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  Check(Bytes<>'','не можна зберегти порожній ELF');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Prepare(const Source:RawByteString);
begin
  Physical:=Source;
  BuildExactIR(Physical,Tables,IR);
end;

procedure Reject(const Why:UnicodeString);
var Image:RawByteString; Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=LowerVerifiedSelectorELF(Physical,RawByteString(Root),IR)
  except on E:EIRLowerSelectorError do Rejected:=True end;
  Check(Rejected and (Image=''),'не відхилено або повернуто частковий ELF: '+Why);
  Inc(Negatives);
end;

procedure BadWords(const Items:array of RawByteString;const Why:UnicodeString);
var Bad:RawByteString;
begin
  Bad:=EncodeT5M(W(Items));
  try Prepare(Bad)
  except
    on E:Exception do begin
      Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
      Physical:=Bad;
    end;
  end;
  Reject(Why);
end;

procedure Positive(const Title:String);
var
  Source,Image,OracleText:RawByteString;
  Geometry:TExactIRGuardStats;
  Values:TExactWords;
  Bits:RawByteString;
  F:TFileStream;
begin
  Source:=ReadBytes(InDir+'/'+Title+'.sens');
  Prepare(Source);
  VerifyExactIRStructure(IR,Geometry);
  Check((Geometry.Roots=1) and (Geometry.Nodes=6),
    UnicodeString('неочікувана геометрія ExactIR: ')+UnicodeString(Title));
  Image:=LowerVerifiedSelectorELF(Physical,RawByteString(Root),IR);
  Check(Length(Image)=193,
    UnicodeString('неочікуваний ELF розмір: ')+UnicodeString(Title));
  DecodeT5M(ReadBytes(InDir+'/'+Title+'.expected.sens'),Values);
  Check((Length(Values)=1) and (Length(Values[0])=1) and
    ((Values[0]='0') or (Values[0]='1')),
    UnicodeString('oracle очікування не є одним точним D1: ')+UnicodeString(Title));
  Bits:=Values[0]+#10;
  OracleText:=Bits;
  SaveBytes(OutDir+'/'+Title+'.elf',Image);
  F:=TFileStream.Create(OutDir+'/'+Title+'.expected.oracle',fmCreate);
  try F.WriteBuffer(OracleText[1],Length(OracleText));
  finally F.Free end;
  Inc(Positives);
end;

var
  Source:RawByteString;
begin
  if ParamCount<>3 then begin
    WriteLn(StdErr,'Аргументи: pinned SENS, вхідні фізичні свідки, каталог ELF');
    Halt(64);
  end;
  Root:=ParamStr(1);InDir:=ParamStr(2);OutDir:=ParamStr(3);
  Check(ForceDirectories(OutDir),'немає каталогу результатів');
  LoadPinnedDomains(RawByteString(Root),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;
  Positive('перше-00');Positive('перше-01');
  Positive('перше-10');Positive('перше-11');
  Positive('решта-00');Positive('решта-01');
  Positive('решта-10');Positive('решта-11');

  Source:=EncodeT5M(W(['10','100','10','111','0','1','01','01']));
  Prepare(Source);IR.Nodes[4].Key:=ExactKey('1');Reject('підміна D1');Inc(Mutations);
  Prepare(Source);IR.Nodes[1].Key:=ExactKey('011');Reject('підміна селектора');Inc(Mutations);
  Prepare(Source);IR.Nodes[3].Key:=ExactKey('101');Reject('підміна CONS');Inc(Mutations);
  Prepare(Source);IR.Nodes[5].Physical.ByteStart:=0;Reject('підміна адреси');Inc(Mutations);
  Prepare(Source);IR.Nodes[2].SubtreeEndExclusive:=3;
  Reject('підміна межі піддерева');Inc(Mutations);
  Prepare(Source);IR.Roots[0]:=2;Reject('підміна кореня');Inc(Mutations);
  Prepare(Source);Physical:=EncodeT5M(W(['10','011','10','111','0','1','01','01']));
  Reject('ExactIR від іншої фізичної програми');Inc(Mutations);

  BadWords(['10','101','10','111','0','1','01','01'],'непідтримана D3:101');
  BadWords(['10','100','10','101','0','1','01','01'],'D3:101 не є CONS');
  BadWords(['10','100','10','111','000','1','01','01'],'D3:000 не є D1');
  BadWords(['10','100','10','111','000000000000','1','01','01'],'D12 не є D1');
  BadWords(['10','100','10','111','0010110','1','01','01'],'D7 лише дані');
  BadWords(['10','100','10','111','0','01','01'],'неповний CONS');
  BadWords(['10','100','10','111','0','1','0','01','01'],'зайвий аргумент');
  BadWords(['10','100','10','111','0','1','01'],'незакритий список');
  BadWords(['10','100','10','111','0','1','01','01','0'],'два корені');
  Prepare(Source);Physical:=#$F3;Reject('пошкоджений T5M');
  Prepare(Source);Physical:='';Reject('порожній T5M');
  Check((Positives=8) and (Negatives=18) and (Mutations=7),
    'лічильники позитивів, відмов і мутацій');
  WriteLn('ПРЯМЕ-ЗНИЖЕННЯ-СЕЛЕКТОРА-ГАРАЗД ELF=',Positives,
    ' відмови=',Negatives,' мутації=',Mutations,' ExactIR→x86-64→T5M');

{ Physical/Root — borrowed байти; IR — borrowed host-граф із точними
  доменними та фізичними полями; ELF — owned RawByteString, не .sens.
  Процедури тесту звільняють усі TFileStream через finally.
  Питання: 1) Навіщо звіряти кожне поле IR із фізичним source?
  2) Чому ключ D3:000 не приймається як D1:0?
  3) Який код ELF читає обидві клітинки CONS?
  4) Чим байт T5M відрізняється від ASCII 0/1?
  5) Що саме доводить порівняння з pinned SENS CLI? }
end.
