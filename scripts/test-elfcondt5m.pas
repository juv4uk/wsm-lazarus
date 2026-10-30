{ G6.28 — дійсні x86-64 ELF stdout witnesses, не source echo. }
program test_elfcondt5m;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfcond,wsm.elfcondt5m;
var Positives,Negatives:SizeInt; OutDir:String;

function W(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

procedure Require(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('УМОВА-T5M-ПОМИЛКА '+Why) end;

procedure Save(const Filename:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Filename,fmCreate);
  try if Bytes<>'' then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Positive(const Name,ResultBits,AsciiResult:RawByteString;
  const Items:array of RawByteString;MachineEQ:Boolean=False);
var Expected:TExactWords;
    Physical,NewBytes,OldBytes,Answer:RawByteString;
begin
  Physical:=EncodeT5M(W(Items));
  OldBytes:=BuildCondELF(Physical,'external/sens');
  NewBytes:=BuildCondT5MELF(Physical,'external/sens');
  SetLength(Expected,1);Expected[0]:=ResultBits;
  Answer:=EncodeT5M(Expected);
  Require((Length(NewBytes)=Length(OldBytes)) and
    (Length(NewBytes)>160) and (Length(NewBytes)<5000),
    String(Name)+' byte-identical instruction geometry');
  Require((Copy(NewBytes,1,120)=Copy(OldBytes,1,120)) and
    (Copy(NewBytes,Length(NewBytes)-6,7)=
      #$BF#$02#0#0#0+#$0F#$05),
    String(Name)+' ELF ABI + checked host exit');
  { Машинний суфікс кожного результату: syscall write(1,1) →
    CMP RAX,1 → JNE exit(2), при повному записі exit(0).
    Зіставлення виконується тільки для фізичного T5M stdout.
    1) Чому D3:000 не тотожне D1:0?
    2) Чому 64-бітний RAX перевіряється після write?
    3) Чому старий CMP RAX,2 або 3 був хибним?
    4) Чи перевірка байтів сама доводить SENS семантику? }
  Require(Pos(#$0F#$05#$48#$83#$F8#$01#$75#$09,NewBytes)>0,
    String(Name)+' фізичний D1 T5M CMP/JNE');
  Require((Pos(#$83#$F8#$01#$75,NewBytes)>0) or
    (Positives=0),String(Name)+' real CMP/JNE');
  if MachineEQ then
    Require(Pos(#$0F#$94#$C0#$6B#$C0,NewBytes)>0,
      String(Name)+' real SETE/IMUL computed byte');
  Require(BuildCondT5MELF(Physical,'external/sens')=NewBytes,
    String(Name)+' deterministic codegen');
  Save(OutDir+'/'+String(Name)+'.sens',Physical);
  Save(OutDir+'/'+String(Name)+'.elf',NewBytes);
  Save(OutDir+'/'+String(Name)+'.expected.sens',Answer);
  Save(OutDir+'/'+String(Name)+'.legacy.elf',OldBytes);
  Save(OutDir+'/'+String(Name)+'.expected.ascii',AsciiResult+#10);
  Inc(Positives);
end;

procedure NegativeRaw(const Physical:RawByteString;const Why:String);
var OutBytes:RawByteString;Rejected:Boolean;
begin
  OutBytes:='';Rejected:=False;
  try OutBytes:=BuildCondT5MELF(Physical,'external/sens');
  except on E:EElfCondT5MError do Rejected:=True end;
  Require(Rejected and (OutBytes=''),Why);
  Inc(Negatives);
end;

procedure Negative(const Items:array of RawByteString;const Why:String);
begin NegativeRaw(EncodeT5M(W(Items)),Why) end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Потрібна тека для фізичних свідків'); Halt(64);
  end;
  OutDir:=ParamStr(1);
  Require(ForceDirectories(OutDir),'не вдалось створити теку');
  Positives:=0;Negatives:=0;
  Positive('вичерпання','000','()',['10','110','01']);
  Positive('істинна-одиниця','1','1',
    ['10','110','10','1','1','01','01']);
  Positive('істинний-нуль','0','0',
    ['10','110','10','1','0','01','01']);
  Positive('хибна-умова','000','()',
    ['10','110','10','0','1','01','01']);
  Positive('друга-гілка','1','1',
    ['10','110','10','0','0','01','10','1','1','01','01']);
  Positive('рівність-істина','1','1',
    ['10','110','10','1','10','101','1','1','01','01','01'],True);
  Positive('рівність-хиба','0','0',
    ['10','110','10','1','10','101','0','1','01','01','01'],True);
  Positive('рівність-у-тесті','0','0',
    ['10','110','10','10','101','1','1','01','0','01','01']);
  Positive('рівність-не-обрана','000','()',
    ['10','110','10','0','10','101','1','1','01','01','01'],True);
  Negative(['0'],'D1 не D3:110');
  Negative(['10','110','10','000','1','01','01'],
    'D3:000 не D1 предикат');
  Negative(['10','110','10','1','000','01','01'],
    'D3:000 не D1 результат');
  Negative(['10','110','10','000000000000','1','01','01'],
    'D12 не числова підстановка предиката');
  Negative(['10','110','10','1','01','01'],'порожній вираз');
  Negative(['10','110','10','1','0','1','01','01'],'зайва арність');
  Negative(['10','110','10','1','0','01','01','1'],'два корені');
  NegativeRaw(#$F3,'неканонічний T5M');
  NegativeRaw('','порожній T5M');
  Require((Positives=9) and (Negatives=9),'лічильники');
  WriteLn('УМОВА-МАШИННИЙ-T5M-ГАРАЗД позитивних=',Positives,
    ' негативних=',Negatives,
    ' D1=0/1 D3:000=окремо машинне-EQ=так stdout=канонічний');
  { ASCII-ідентифікатор CI тільки після контрольних Positives=9,
    Negatives=9: за неправильної локалі FPC кирилиця може стати '?'. }
  WriteLn('COND-T5M-ADMISSION-PASS positives=',Positives,
    ' negatives=',Negatives);
end.
