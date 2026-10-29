{ G6.25 — фізичний вихід справжнього Linux ELF64 EQ.
  Підготовка свідків через діючий T5M, негативи — fail closed. }
program test_elfeqt5m;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfeqt5m;
const HeaderLimit=120;
var Positives,Negatives:SizeInt;
    AuthorityRoot,OutputDir:String;
function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
procedure Check(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create('ПЕРЕВІРКА-T5M-ПРОВАЛ: '+Why) end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
procedure Positive(const Name,First,Second,Expected:RawByteString);
var Physical,Image,Answer:RawByteString;
begin
  Physical:=EncodeT5M(Words(['10','101',First,Second,'01']));
  Image:=BuildEqT5MELF(Physical,RawByteString(AuthorityRoot));
  Answer:=EncodeT5M(Words([Expected]));
  Check((Length(Image)>HeaderLimit) and (Length(Image)<400),
    'довжина ELF: '+String(Name));
  Check((Copy(Image,1,4)=#$7F'ELF') and
    (Ord(Image[5])=2) and (Ord(Image[17])=3) and
    (Ord(Image[19])=62),'ET_DYN x86-64: '+String(Name));
  Check(Pos(#$39#$C8#$0F#$94#$C0#$0F#$B6#$C0,Image)>0,
    'машинний CMP/SETE/MOVZX');
  Check(Pos(#$6B#$C0,Image)>0,'машинна упаковка T5M');
  Check(BuildEqT5MELF(Physical,RawByteString(AuthorityRoot))=Image,
    'детермінізм ELF');
  Save(OutputDir+'/'+String(Name)+'.sens',Physical);
  Save(OutputDir+'/'+String(Name)+'.elf',Image);
  Save(OutputDir+'/'+String(Name)+'.expected.sens',Answer);
  Inc(Positives);
end;
procedure NegativeRaw(const Physical:RawByteString;const Why:String);
var Image:RawByteString; Rejected:Boolean;
begin
  Rejected:=False; Image:='';
  try Image:=BuildEqT5MELF(Physical,RawByteString(AuthorityRoot));
  except on E:EElfEqT5MError do Rejected:=True end;
  Check(Rejected and (Image=''),Why);
  Inc(Negatives);
end;
procedure Negative(const Items:array of RawByteString;const Why:String);
begin NegativeRaw(EncodeT5M(Words(Items)),Why) end;
begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні: pinned-sens-корінь і тека свідків');Halt(64)
  end;
  AuthorityRoot:=ParamStr(1);
  OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'створення каталогу для свідків');
  Positives:=0;Negatives:=0;
  Positive('нуль-нуль','0','0','1');
  Positive('нуль-один','0','1','0');
  Positive('один-нуль','1','0','0');
  Positive('один-один','1','1','1');
  Negative(['0'],'голий D1 не є викликом D3:101');
  Negative(['10','111','0','1','01'],'D3:111 не є тотожністю');
  Negative(['10','101','0','01'],'недостатня арність');
  Negative(['10','101','0','1','0','01'],'зайва арність');
  Negative(['10','101','000','1','01'],'D3:000 не є D1:0');
  Negative(['10','101','000000000000','1','01'],'D12 не D1');
  Negative(['10','101','0','1'],'незакрита фізична форма');
  NegativeRaw(#$F3,'неканонічний фізичний T5M');
  NegativeRaw('','порожня фізична програма');
  Check((Positives=4) and (Negatives=9),'лічильник механічних свідків');
  WriteLn('ЕЛФ-T5M-ГАРАЗД позитивні=',Positives,
    ' негативні=',Negatives,' CMP/SETE=машинний D1=точний вихід=бінарний');
end.
