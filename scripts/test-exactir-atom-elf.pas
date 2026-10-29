{ G6.30: справжні фізичні D3:010 форми через спільний ExactIR.
  10 запусків Linux ELF перевіряють машинне обчислення «атом?».
  Структурно валідний, але чужий IR мусить відхилятися. }
program test_exactir_atom_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.domain,wsm.exactir,
  wsm.exactirguard,wsm.elfatomt5m,wsm.exactirtoelf,
  wsm.binaryexec;
var
  AuthorityRoot,OutputDir:String;
  Tables:TDomainSet;
  IR:TExactIR;
  Physical:RawByteString;
  Positives,Negatives,Mutations:SizeInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('IR-АТОМ-ЕЛФ-ПОМИЛКА: '+Why);
end;

function Words(const Values:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Values));
  for I:=0 to High(Values) do Result[I]:=Values[I];
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

procedure Rejected(const Why:String);
var Output:RawByteString;DidReject:Boolean;
begin
  Output:='';DidReject:=False;
  try Output:=BuildVerifiedAtomIR(Physical,RawByteString(AuthorityRoot),IR);
  except on E:EVerifiedIRELFError do DidReject:=True end;
  Check(DidReject and (Output=''),'не відхилено: '+Why);
  Inc(Negatives);
end;

procedure CheckStructurallyValid(const Why:String);
var Stats:TExactIRGuardStats;
begin
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=1) and (Stats.Nodes>=3),Why);
end;

procedure Positive(const Name,ExpectedBits:RawByteString;
  const FormWords:array of RawByteString);
var Output,Baseline,Expected,Native:RawByteString;
    Executor:TBinaryExecutor;
begin
  Prepare(EncodeT5M(Words(FormWords)));
  Output:=BuildVerifiedAtomIR(Physical,RawByteString(AuthorityRoot),IR);
  Baseline:=BuildAtomT5MELF(Physical,RawByteString(AuthorityRoot));
  Expected:=EncodeT5M(Words([ExpectedBits]));
  Check((Output=Baseline) and (Length(Output)>150) and
    (Copy(Output,1,4)=#$7F'ELF'),'ELF і чинний emitter: '+String(Name));
  Check((Ord(Output[17])=2) and (Ord(Output[19])=62),
    'ELF64 ET_EXEC AMD64: '+String(Name));
  Check(Pos(#$83#$E0#$03#$83#$F8#$03#$0F#$95#$C0,Output)>0,
    'реальний AND/CMP/SETNE: '+String(Name));
  Check(Pos(#$0F#$B6#$C0,Output)>0,'машинний MOVZX');
  Check(Pos(#$6B#$C0,Output)>0,'машинний IMUL T5M');
  Check(Length(Expected)=1,'результат — рівно один фізичний байт D1');
  Executor:=TBinaryExecutor.Create(RawByteString(AuthorityRoot));
  try Native:=Executor.ExecutePhysicalT5M(Physical);
  finally Executor.Free end;
  Check(Native=Expected,'native runtime D3:010: '+String(Name));
  Check(BuildVerifiedAtomIR(Physical,RawByteString(AuthorityRoot),IR)=Output,
    'ELF не детермінований: '+String(Name));
  Save(OutputDir+'/'+String(Name)+'.elf',Output);
  Save(OutputDir+'/'+String(Name)+'.expected.sens',Expected);
  Inc(Positives);
end;

procedure Negative(const BadWords:array of RawByteString;const Why:String);
var Source:RawByteString;
begin
  Source:=EncodeT5M(Words(BadWords));
  try Prepare(Source);
  except
    on E:Exception do begin
      Prepare(EncodeT5M(Words(['10','010','0','01'])));
      Physical:=Source;
    end;
  end;
  Rejected(Why);
end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні pinned SENS і каталог свідків');Halt(64);
  end;
  AuthorityRoot:=ParamStr(1);OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'каталог свідків');
  LoadPinnedDomains(RawByteString(AuthorityRoot),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;
  Positive('атом-нуль','1',['10','010','0','01']);
  Positive('атом-один','1',['10','010','1','01']);
  Positive('атом-порожній','1',['10','010','10','01','01']);
  Positive('атом-д3-порожній','1',['10','010','000','01']);
  Positive('атом-пара','0',['10','010','10','111','0','1','01','01']);
  Positive('атом-пара-порожній','0',
    ['10','010','10','111','0','000','01','01']);
  Positive('атом-пара-пар','0',
    ['10','010','10','111','10','111','1','000','01','0','01','01']);
  Positive('атом-вкладений-атом-пари','1',
    ['10','010','10','010','10','111','0','000','01','01','01']);
  Positive('атом-атома','1',['10','010','10','010','0','01','01']);
  Positive('атом-вкладена-пара','0',
    ['10','010','10','111','10','010','1','01','0','01','01']);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  IR.Nodes[2].Key:=ExactKey('1');
  CheckStructurallyValid('підміна D1 структурно допустима');
  Rejected('чужий точний D1 біт');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  Inc(IR.Nodes[2].WordIndex);
  Inc(IR.Nodes[2].Physical.WordIndex);
  CheckStructurallyValid('підміна WordIndex структурно допустима');
  Rejected('підроблено індекс листка');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  Physical:=EncodeT5M(Words(['10','010','1','01']));
  CheckStructurallyValid('те саме дерево, інший фізичний байт');
  Rejected('підмінено джерело після IR');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  IR.Nodes[1].Key:=ExactKey('001');
  CheckStructurallyValid('підміна координати D3 структурно допустима');
  Rejected('підмінено голову D3:010');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0010110','01'])));
  IR.Nodes[2].Key:=ExactKey('0010111');
  CheckStructurallyValid('D7 контроль лишився структурно валідним');
  Rejected('підмінений фізичний текст D7');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  IR.Nodes[2].Physical.TritStart:=0;
  Rejected('підмінена адреса трита');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  IR.Nodes[2].ParentIndex:=99;
  Rejected('підмінений батько');Inc(Mutations);

  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  Inc(IR.BoundLeaves);
  Rejected('підмінене число листків');Inc(Mutations);

  Negative(['0'],'голий D1');
  Negative(['10','001','0','01'],'чужа голова D3:001');
  Negative(['10','010','01'],'ATOM без аргументу');
  Negative(['10','010','0','1','01'],'ATOM із двома аргументами');
  Negative(['10','010','000000000000','01'],'D12 число');
  Negative(['10','010','000000000000000000000000','01'],'D24 атом');
  Negative(['10','010','10','100','0','01','01'],'непідтриманий CAR');
  Negative(['10','010','10','001','0','01','01'],'вкладена цитата');
  Negative(['10','010','10','1','11','0','01','01'],'крапкова пара');
  Negative(['10','010','0','01','1'],'два корені');
  Negative(['10','010','0'],'незакрита D2 форма');
  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  Physical:=#243;Rejected('неканонічний T5M');
  Prepare(EncodeT5M(Words(['10','010','0','01'])));
  Physical:='';Rejected('порожнє джерело');

  Check((Positives=10) and (Mutations=8) and (Negatives=21),
    'неточний лічильник свідків');
  WriteLn('СПІЛЬНИЙ-IR-АТОМ-ЕЛФ-ГАРАЗД ELF=',Positives,
    ' негативні=',Negatives,' підміни=',Mutations,
    ' exact-provenance=так D1=T5M machine-ATOM=так');
end.
