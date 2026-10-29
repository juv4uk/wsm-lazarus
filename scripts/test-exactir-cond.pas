{ G6.37 — дев'ять вже ратифікованих фізичних D3:110 свідків,
  запозичених із незміненої test-elfcondt5m. Пряме машинне виконання
  відбувається в оболонці; тут перевірка фізичного IR та ELF байтів. }
program test_exactir_cond;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,
  wsm.exactirguard,wsm.exactirtoelf,wsm.elfcondt5m,
  wsm.elfgeometry,wsm.binaryexec;
var
  Root,InDir,OutDir:String;
  Tables:TDomainSet;
  IR:TExactIR;
  Physical:RawByteString;
  Positives,Negatives,Mutations:SizeInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create(
    RawByteString('ДОВІРЕНА-УМОВА-IR-ПОМИЛКА: ')+Why);
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
    Check((F.Size>0) and (F.Size<=65536),'неприпустима довжина файла');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  Check(Bytes<>'','не можна записувати порожній ELF');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Prepare(const Input:RawByteString);
begin
  Physical:=Input;
  BuildExactIR(Physical,Tables,IR);
end;

procedure Reject(const Why:String);
var Image:RawByteString;Failed:Boolean;
begin
  Image:='';Failed:=False;
  try Image:=BuildVerifiedCondIR(Physical,RawByteString(Root),IR);
  except on E:EVerifiedIRELFError do Failed:=True end;
  Check(Failed and (Image=''),'помилковий допуск/частковий ELF: '+Why);
  Inc(Negatives);
end;

procedure BadWords(const Items:array of RawByteString;const Why:String);
var Wrong:RawByteString;
begin
  Wrong:=EncodeT5M(W(Items));
  try Prepare(Wrong);
  except
    on E:Exception do begin
      Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
      Physical:=Wrong;
    end;
  end;
  Reject(Why);
end;

procedure Positive(const Filename:String);
var
  Image,Baseline,Expected,Answer:RawByteString;
  Geometry:TELFGeometry;
  Executor:TBinaryExecutor;
  Stats:TExactIRGuardStats;
  Stem:String;
begin
  Prepare(ReadBytes(InDir+'/'+Filename));
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=1) and (Stats.Nodes>=2),
    'неповний IR дев’яти pinned фізичних свідків: '+Filename+
    ' roots='+IntToStr(Stats.Roots)+' nodes='+IntToStr(Stats.Nodes));
  Image:=BuildVerifiedCondIR(Physical,RawByteString(Root),IR);
  Baseline:=BuildCondT5MELF(Physical,RawByteString(Root));
  Check((Image=Baseline) and (Length(Image)>160),
    'порушено byte-exact нативний emitter');
  VerifySENSELF64(Image,Geometry);
  Check((Geometry.Kind=2) and (Geometry.MachineBytes>40),
    'машинний ELF64 ET_EXEC без виконуваного коду');
  Executor:=TBinaryExecutor.Create(RawByteString(Root));
  try Answer:=Executor.ExecutePhysicalT5M(Physical);
  finally Executor.Free end;
  Stem:=Copy(Filename,1,Length(Filename)-5);
  Expected:=ReadBytes(InDir+'/'+Stem+'.expected.sens');
  Check(Answer=Expected,
    'обчислений точний D3:110 відрізняється від фізичного свідка');
  Check(BuildVerifiedCondIR(Physical,RawByteString(Root),IR)=Image,
    'машинна компіляція недетермінована');
  SaveBytes(OutDir+'/'+Stem+'.elf',Image);
  Inc(Positives);
end;

var
  Find:TSearchRec;RC:LongInt;
  Stats:TExactIRGuardStats;
begin
  if ParamCount<>3 then begin
    WriteLn(StdErr,RawByteString('Аргументи: pinned SENS, свідки, вихід ELF'));
    Halt(64);
  end;
  Root:=ParamStr(1); InDir:=ParamStr(2); OutDir:=ParamStr(3);
  Check(ForceDirectories(OutDir),'каталог для машинних ELF');
  LoadPinnedDomains(RawByteString(Root),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;

  RC:=FindFirst(InDir+'/*.sens',faAnyFile,Find);
  Check(RC=0,'немає фізичних .sens свідків');
  try
    repeat
      if ((Find.Attr and faDirectory)=0) and
        (Pos('.expected.sens',Find.Name)=0) then
        Positive(Find.Name);
      RC:=FindNext(Find);
    until RC<>0;
  finally FindClose(Find) end;
  Check(Positives=9,'очікувалося рівно дев’ять фізичних D3:110 ELF');

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  IR.Nodes[3].Key:=ExactKey('0');
  VerifyExactIRStructure(IR,Stats);
  Reject('чужий structurally-valid біт предиката');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  IR.Nodes[1].Key:=ExactKey('101');
  VerifyExactIRStructure(IR,Stats);
  Reject('підміна D3:110 на D3:101');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  IR.Nodes[3].Physical.TritStart:=0;
  Reject('підмінено фізичне місце трита');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  IR.Roots[0]:=1;
  Reject('підмінено корінь ExactIR');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  Physical:=EncodeT5M(W(['10','110','10','0','0','01','01']));
  Reject('незмінний IR, інші фізичні байти');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  Inc(IR.BoundLeaves);
  Reject('неправильний підрахунок точних листків');Inc(Mutations);

  BadWords(['0'],'голий D1 замість D3:110');
  BadWords(['10','001','0','01'],'чужа голова D3:001');
  BadWords(['10','110','10','000','1','01','01'],
    'D3:000 у позиції D1 predicate');
  BadWords(['10','110','10','1','000','01','01'],
    'D3:000 у позиції D1 expression');
  BadWords(['10','110','10','000000000000','1','01','01'],
    'D12 не приймається за предикат');
  BadWords(['10','110','10','0010110','1','01','01'],
    'D7 SYN лишається текстовими даними');
  BadWords(['10','110','10','1','01','01'],'пропущений expression');
  BadWords(['10','110','10','1','0','1','01','01'],
    'зайва третя частина умови');
  BadWords(['10','110','10','1','0','01','01','1'],
    'дві фізичні кореневі форми');
  BadWords(['10','110','10','1','0'],'незакритий фізичний D2');
  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  Physical:=#$F3;Reject('неканонічний T5M');
  Prepare(EncodeT5M(W(['10','110','10','1','0','01','01'])));
  Physical:='';Reject('порожнє фізичне джерело');

  Check((Positives=9) and (Negatives=18) and (Mutations=6),
    'втрачено позитивні або негативні перевірки');
  WriteLn(RawByteString('ДОВІРЕНА-УМОВА-IR-ГАРАЗД ELF='),Positives,
    RawByteString(' негативних='),Negatives,
    RawByteString(' підміни='),Mutations,
    RawByteString(' T5M=побайтовий provenance=доведено'));

{ Контракт: фізичні .sens та CandidateIR borrowed. Дані ELF
  виділяє BuildVerifiedCondIR як новий managed RawByteString.
  Тест пише тільки нові файли в окремій CI теці, вхід не змінюється.
  Запитання:
  1) Чому три слова у фізичному D2 мають адреси, а не імена?
  2) Чому ми окремо запускаємо ELF в Linux після FPC guard?
  3) Чому зміна одного біта при незмінному IR мусить відхилятися?
  4) Чому D12 не конвертується неявно в D1?
  5) Чому «зелений ELF» не доводить повний SENS REPL? }
end.
