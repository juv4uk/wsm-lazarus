{ G6.29 — реальний IR->ELF: exact provenance, позитиви та негативи.
  Oracle тут НЕ підмінюється: порівнюємо лише з уже перевіреним
  фізичним D3 executor і запускаємо створений ELF під Linux CI. }
program test_exactirtoelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.domain,wsm.exactir,
  wsm.exactirguard,wsm.elfquotet5m,wsm.exactirtoelf;
var
  AuthorityRoot,OutputDir:String;
  Tables:TDomainSet;
  IR:TExactIR;
  Physical:RawByteString;
  Positives,Negatives,Mutations:SizeInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('IR-ЕЛФ-ПОМІЛКА: '+Why);
end;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Prepare(const Source:RawByteString);
begin
  Physical:=Source;
  BuildExactIR(Physical,Tables,IR);
end;

procedure ExpectRejected(const Why:String);
var Got:RawByteString; Rejected:Boolean;
begin
  Got:=''; Rejected:=False;
  try Got:=BuildVerifiedQuoteIR(Physical,RawByteString(AuthorityRoot),IR);
  except on E:EVerifiedIRELFError do Rejected:=True end;
  Check(Rejected and (Got=''),Why+' має відхилитися без результату');
  Inc(Negatives);
end;

procedure CheckGuardValid(const Why:String);
var Stats:TExactIRGuardStats;
begin
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=1) and (Stats.Nodes>=3),Why);
end;

procedure Positive(const Name:RawByteString;
  const FormWords,ValueWords:array of RawByteString);
var Image,Baseline,Expected:RawByteString;
begin
  Prepare(EncodeT5M(Words(FormWords)));
  Image:=BuildVerifiedQuoteIR(Physical,RawByteString(AuthorityRoot),IR);
  Baseline:=BuildQuoteT5MELF(Physical,RawByteString(AuthorityRoot));
  Expected:=EncodeT5M(Words(ValueWords));
  Check((Image=Baseline) and (Length(Image)=153+Length(Expected)),
    'відтворений точний ELF для '+String(Name));
  Check(Copy(Image,154,Length(Expected))=Expected,
    'оригінальні бінарні байти літерала '+String(Name));
  Check(BuildVerifiedQuoteIR(Physical,RawByteString(AuthorityRoot),IR)=Image,
    'нестабільний ELF з перевіреного IR');
  Save(OutputDir+'/'+String(Name)+'.elf',Image);
  Save(OutputDir+'/'+String(Name)+'.expected.sens',Expected);
  Inc(Positives);
end;

procedure NegativeForm(const BadWords:array of RawByteString;const Why:String);
var Source:RawByteString;
begin
  Source:=EncodeT5M(Words(BadWords));
  { Для неприпустимого W12 BuildExactIR може відмовити ще під час
    фізичного допуску. Тоді даємо wrapper-у коректний, але ЧУЖИЙ
    IR, аби довести відсутність обходу перевірки джерела. }
  try
    Prepare(Source);
  except
    on E:Exception do begin
      Prepare(EncodeT5M(Words(['10','001','0','01'])));
      Physical:=Source;
    end;
  end;
  ExpectRejected(Why);
end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Аргументи: pinned-root каталог-виходу'); Halt(64);
  end;
  AuthorityRoot:=ParamStr(1);OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'каталог ELF свідків');
  LoadPinnedDomains(RawByteString(AuthorityRoot),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;

  Positive('д1-нуль',['10','001','0','01'],['0']);
  Positive('д1-один',['10','001','1','01'],['1']);
  Positive('д3-порожньо',['10','001','000','01'],['000']);
  Positive('д7-син',['10','001','0010110','01'],['0010110']);
  Positive('д9-нулі',['10','001','000000001','01'],['000000001']);
  Positive('список',['10','001','10','0','1','01','01'],
                    ['10','0','1','01']);
  Positive('вкладений',['10','001','10','1','10','0','01','01','01'],
                      ['10','1','10','0','01','01']);

  { Головний негатив: зовнішній IR СТРУКТУРНО допустимий,
    але його фізичні біти відрізняються від T5M. }
  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  IR.Nodes[2].Key:=ExactKey('1');
  CheckGuardValid('структурно валідний підмінений біт D1');
  ExpectRejected('підмінений D1:0 на D1:1');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Inc(IR.Nodes[2].WordIndex);
  Inc(IR.Nodes[2].Physical.WordIndex);
  CheckGuardValid('структурно валідний підмінений індекс');
  ExpectRejected('підроблений WordIndex без зміни тритів');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0010110','01'])));
  IR.Nodes[2].Key:=ExactKey('0010111');
  CheckGuardValid('структурно валідна підміна D7');
  ExpectRejected('D7 текстовий код замінено іншим словом');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Physical:=EncodeT5M(Words(['10','001','1','01']));
  CheckGuardValid('оригінальний IR не змінився');
  ExpectRejected('інше фізичне джерело з тим самим контуром');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  IR.Nodes[2].Physical.TritStart:=0;
  ExpectRejected('фальшива фізична тритова позиція');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  IR.Nodes[2].ParentIndex:=99;
  ExpectRejected('підмінене дерево батьків');
  Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Inc(IR.BoundLeaves);
  ExpectRejected('підмінено кількість доменних листків');
  Inc(Mutations);

  { Закон виклику береться лише з чинного backend.
    Навіть правильний фізичний IR для іншої голови — BLOCKED. }
  NegativeForm(['10','111','0','01'],'D3:111 не цитата');
  NegativeForm(['10','001','01'],'D3:001 без аргументу');
  NegativeForm(['10','001','0','1','01'],'D3:001 зайва арність');
  NegativeForm(['0'],'фізичний D1 не є формою цитування');
  NegativeForm(['10','001','000000000001','01'],'числовий D12 не D1');
  NegativeForm(['10','001','10','0','11','1','01'],
    'D2 крапкова цитата не підтримана');

  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Physical:=#243;ExpectRejected('неприпустимий T5M');
  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Physical:='';ExpectRejected('порожній вхід');
  Prepare(EncodeT5M(Words(['10','001','0','01'])));
  Physical:=EncodeT5M(Words(['10','001','0']));
  ExpectRejected('незакритий D2');

  Check((Positives=7) and (Negatives=16) and (Mutations=7),
    'кількість позитивів, негативів і підмін');
  WriteLn('ДОВІРЕНИЙ-IR-ЕЛФ-ГАРАЗД ELF=',Positives,
    ' негативні=',Negatives,' підміни=',Mutations,
    ' exact-provenance=так byte-exact-T5M=так');
end.
