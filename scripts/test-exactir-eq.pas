{ G6.30 — справжній ELF після повного доказу provenance зовнішнього IR. }
program test_exactir_eq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.domain,
  wsm.exactir,wsm.exactirguard,wsm.exactirtoelf,wsm.elfeqt5m;
var Root,Dir:String; Tables:TDomainSet; IR:TExactIR;
    Physical:RawByteString; Positives,Negatives,Mutations:SizeInt;
procedure Check(C:Boolean;const Why:String);
begin if not C then raise Exception.Create('ДОВІРЕНИЙ-EQ-IR-ПОМИЛКА: '+Why) end;
function W(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Prepare(const Bytes:RawByteString);
begin
  Physical:=Bytes;BuildExactIR(Physical,Tables,IR);
end;
procedure Reject(const Why:String);
var E:RawByteString;Failed:Boolean;
begin
  Failed:=False;E:='';
  try E:=BuildVerifiedEqIR(Physical,RawByteString(Root),IR);
  except on X:EVerifiedIRELFError do Failed:=True end;
  Check(Failed and (E=''),Why+' — відсутня атомарна відмова');
  Inc(Negatives);
end;
procedure Positive(const LabelName,A,B,Expected:RawByteString);
var Image,Baseline,Answer:RawByteString; Stats:TExactIRGuardStats;
begin
  Prepare(EncodeT5M(W(['10','101',A,B,'01'])));
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=1) and (Stats.Nodes=4),'структура фізичного EQ');
  Image:=BuildVerifiedEqIR(Physical,RawByteString(Root),IR);
  Baseline:=BuildEqT5MELF(Physical,RawByteString(Root));
  Answer:=EncodeT5M(W([Expected]));
  Check((Image=Baseline) and (Length(Image)>120) and
    (Copy(Image,1,4)=#$7F'ELF') and (Ord(Image[5])=2) and
    (Ord(Image[17])=3),'справжня ELF64 збірка '+String(LabelName));
  Check(BuildVerifiedEqIR(Physical,RawByteString(Root),IR)=Image,
    'недетермінізм машинного image');
  Save(Dir+'/'+String(LabelName)+'.elf',Image);
  Save(Dir+'/'+String(LabelName)+'.expected.sens',Answer);
  Inc(Positives);
end;
procedure InvalidWords(const Items:array of RawByteString;const Why:String);
var NewPhysical:RawByteString;
begin
  NewPhysical:=EncodeT5M(W(Items));
  try Prepare(NewPhysical)
  except on E:Exception do begin
    Prepare(EncodeT5M(W(['10','101','0','0','01'])));
    Physical:=NewPhysical;
  end end;
  Reject(Why);
end;
var Stats:TExactIRGuardStats;
begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Аргументи: pinned-корінь і каталог ELF');Halt(64);
  end;
  Root:=ParamStr(1);Dir:=ParamStr(2);
  Check(ForceDirectories(Dir),'каталог фізичних свідків');
  LoadPinnedDomains(RawByteString(Root),Tables);
  Positives:=0;Negatives:=0;Mutations:=0;
  Positive('нуль-нуль','0','0','1');
  Positive('нуль-один','0','1','0');
  Positive('один-нуль','1','0','0');
  Positive('один-один','1','1','1');

  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  IR.Nodes[2].Key:=ExactKey('1');
  VerifyExactIRStructure(IR,Stats);
  Reject('структурно валідний чужий D1');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  Inc(IR.Nodes[2].WordIndex);Inc(IR.Nodes[2].Physical.WordIndex);
  VerifyExactIRStructure(IR,Stats);
  Reject('підмінений фізичний індекс');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  Physical:=EncodeT5M(W(['10','101','1','1','01']));
  Reject('підмінено T5M при незмінному IR');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  IR.Roots[0]:=2;Reject('підмінено корінь');Inc(Mutations);

  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  IR.Nodes[3].Physical.TritStart:=0;
  Reject('змінено фізичний тритовий span');Inc(Mutations);

  InvalidWords(['10','001','0','01'],'цитата не є EQ');
  InvalidWords(['10','101','0','01'],'відсутній другий D1');
  InvalidWords(['10','101','0','1','0','01'],'зайвий D1');
  InvalidWords(['10','101','000','1','01'],'D3:000 не D1');
  InvalidWords(['10','101','000000000000','1','01'],'D12 не D1');
  InvalidWords(['10','101','0010110','1','01'],'D7 SYN не D1');
  InvalidWords(['0'],'голий атом не виклик');
  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  Physical:=#$F3;Reject('неканонічний T5M');
  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  Physical:='';Reject('порожній T5M');
  Prepare(EncodeT5M(W(['10','101','0','1','01'])));
  Physical:=EncodeT5M(W(['10','101','0','1']));
  Reject('незакрита D2 форма');

  Check((Positives=4) and (Negatives=15) and (Mutations=5),
    'лічильники позитивів і негативів');
  WriteLn('ДОВІРЕНИЙ-EQ-IR-ГАРАЗД ELF=',Positives,
    ' негативні=',Negatives,' підміни=',Mutations,
    ' machine=EQ T5M=фізичний provenance=так');
end.
