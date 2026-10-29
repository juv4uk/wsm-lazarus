{ G6.39 — справжній фізичний ExactIR → машинні D3:100/011.
  Вхідні вісім .sens створює незмінений upstream-pinned emitter-test.
  Це механічне підтвердження ELF64, а не незалежний SENS REPL oracle. }
program test_exactir_selector;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,
  wsm.exactirguard,wsm.exactirtoelf,wsm.elfselectort5m,
  wsm.elfgeometry,wsm.binaryexec;
var
  Root,InDir,OutDir:String; Tables:TDomainSet; IR:TExactIR;
  Physical:RawByteString; Positives,Negatives,Mutations:SizeInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ДОВІРЕНИЙ-СЕЛЕКТОР-IR-ПОМИЛКА: '+Why);
end;

function W(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

function ReadBytes(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Check((F.Size>=1) and (F.Size<=65536),
      'недопустимий фізичний розмір: '+Path);
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  Check(Bytes<>'','порожній перевірений машинний результат');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Prepare(const Source:RawByteString);
begin
  Physical:=Source;
  BuildExactIR(Physical,Tables,IR);
end;

procedure Reject(const Why:String);
var
  Image:RawByteString;
  Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try
    Image:=BuildVerifiedSelectorIR(Physical,RawByteString(Root),IR);
  except
    on E:EVerifiedIRELFError do Rejected:=True;
  end;
  Check(Rejected and (Image=''),
    'відмова або нульовий результат відсутні: '+Why);
  Inc(Negatives);
end;

procedure BadWords(const Items:array of RawByteString;const Why:String);
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
  Image,Baseline,Answer,Expected,Source:RawByteString;
  Geometry:TELFGeometry;
  Engine:TBinaryExecutor;
  Stats:TExactIRGuardStats;
begin
  Source:=ReadBytes(InDir+'/'+Title+'.sens');
  Prepare(Source);
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=1) and (Stats.Nodes>=6),
    'неповний фізичний ExactIR селектора: '+Title);
  Image:=BuildVerifiedSelectorIR(Physical,RawByteString(Root),IR);
  Baseline:=BuildSelectorT5MELF(Physical,RawByteString(Root));
  Check((Image=Baseline) and (Length(Image)=193),
    'машинний ELF не збігається із чинним генератором: '+Title);
  VerifySENSELF64(Image,Geometry);
  Check((Geometry.Kind=3) and (Geometry.MachineBytes=73),
    'очікується реальний ELF64 ET_DYN із машинним CONS');
  Expected:=ReadBytes(InDir+'/'+Title+'.expected.sens');
  Engine:=TBinaryExecutor.Create(RawByteString(Root));
  try Answer:=Engine.ExecutePhysicalT5M(Physical);
  finally Engine.Free end;
  Check((Length(Answer)=1) and (Answer=Expected),
    'фізичний native witness відрізняється: '+Title);
  Check(Answer=ReadBytes(InDir+'/'+Title+'.native.sens'),
    'втрачено попередню перевірку байтів: '+Title);
  Check(BuildVerifiedSelectorIR(Physical,RawByteString(Root),IR)=Image,
    'недетермінований native ELF');
  SaveBytes(OutDir+'/'+Title+'.elf',Image);
  Inc(Positives);
end;

var Stats:TExactIRGuardStats;
begin
  if ParamCount<>3 then begin
    WriteLn(StdErr,RawByteString('Аргументи: pinned SENS, свідки, вихід'));
    Halt(64);
  end;
  Root:=ParamStr(1);InDir:=ParamStr(2);OutDir:=ParamStr(3);
  Check(ForceDirectories(OutDir),'немає каталогу для ELF');
  LoadPinnedDomains(RawByteString(Root),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;

  Positive('перше-00');Positive('перше-01');
  Positive('перше-10');Positive('перше-11');
  Positive('решта-00');Positive('решта-01');
  Positive('решта-10');Positive('решта-11');

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  IR.Nodes[4].Key:=ExactKey('1');
  VerifyExactIRStructure(IR,Stats);
  Reject('структурно коректна підміна D1:0 на D1:1');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  IR.Nodes[1].Key:=ExactKey('011');
  VerifyExactIRStructure(IR,Stats);
  Reject('структурно коректна заміна CAR на CDR');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  IR.Nodes[3].Key:=ExactKey('101');
  VerifyExactIRStructure(IR,Stats);
  Reject('структурно коректна підміна CONS на EQ');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  IR.Nodes[4].Physical.TritStart:=0;
  Reject('підмінене фізичне місце D1');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  IR.Roots[0]:=2;
  Reject('підмінене дерево коренів');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  Physical:=EncodeT5M(W(['10','100','10','111','1','1','01','01']));
  Reject('ті самі IR вузли з іншими canonical T5M');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  Inc(IR.BoundLeaves);
  Reject('підмінений підрахунок exact листків');Inc(Mutations);

  BadWords(['0'],'голий D1 не є селектором');
  BadWords(['10','101','10','111','0','1','01','01'],
    'D3:101 — інша голова');
  BadWords(['10','100','0','01'],'немає CONS');
  BadWords(['10','100','10','111','01','01'],
    'CONS без аргументів');
  BadWords(['10','100','10','111','0','01','01'],
    'CONS лише з одним аргументом');
  BadWords(['10','011','10','111','0','1','0','01','01'],
    'CONS із трьома аргументами');
  BadWords(['10','100','10','111','000','1','01','01'],
    'D3:000 не тотожний D1:0');
  BadWords(['10','011','10','111','000000000000','1','01','01'],
    'D12 не підмінює D1');
  BadWords(['10','100','10','111','0010110','1','01','01'],
    'D7 SYN — лише текстові дані');
  BadWords(['10','100','10','111','10','111','0','1','01','0','01','01'],
    'вкладений CONS замість D1');
  BadWords(['10','100','10','111','0','11','1','01','01'],
    'дотована D2 пара');
  BadWords(['10','100','10','111','0','1','01','01','0'],
    'два корені замість одного');
  BadWords(['10','100','10','111','0','1','01'],
    'незакритий D2');
  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  Physical:=#$F3; Reject('неправильний packed T5M');
  Prepare(EncodeT5M(W(['10','100','10','111','0','1','01','01'])));
  Physical:=''; Reject('порожній фізичний вхід');

  Check((Positives=8) and (Negatives=22) and (Mutations=7),
    'не виконані всі фізичні позитивні/негативні перевірки');
  WriteLn(RawByteString('ДОВІРЕНИЙ-СЕЛЕКТОР-IR-ГАРАЗД ELF='),Positives,
    RawByteString(' негативні='),Negatives,
    RawByteString(' підміни='),Mutations,
    RawByteString(' CONS=машинний T5M=побайтово'));

{ Контракт/життя: Source позичений canonical T5M, IR — приватний FPC
  managed граф, ELF — нові байти з verified builder; тест пише лише
  файл у власний output каталог. D7-рядки не є call admission.
  Запитання:
  1) Чому обидва QWord мають окремі машинні адреси?
  2) Чому підміна лише одного D1 біта у валідному IR не дозволена?
  3) Чому ми порівнюємо із вже злитим emitter?
  4) Чому D12 numeric не стає умовою чи аргументом D1?
  5) Чому цей результат ще не означає загальний Core4? }
end.
