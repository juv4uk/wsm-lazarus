{ G6.13 — тести фізичного D3:101 і машинного CMP/SETE.
  Окремий сценарій реально виконає ELF64 через ядро Linux. }
program test_elfeq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfeq;
var Good,Bad:SizeInt;Machine:RawByteString;
procedure Check(B:Boolean;const Why:String);
begin
  if not B then begin
    WriteLn(StdErr,'НАТИВНИЙ-EQ-ТЕСТ-ПОМИЛКА: ',Why);Halt(1);
  end;
end;
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
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free;end;
end;
procedure Positive(const LabelText,Expected,Left,Right:RawByteString);
var Physical,Again:RawByteString;
begin
  Physical:=EncodeT5M(W(['10','101',Left,Right,'01']));
  Save('build/m0.2/elfeq/'+String(LabelText)+'.sens',Physical);
  Machine:=BuildEqELF(Physical,'external/sens');
  Again:=BuildEqELF(Physical,'external/sens');
  Check((Machine=Again) and (Length(Machine)>160) and
    (Length(Machine)<300),'ELF не є детермінованим');
  Check((Copy(Machine,1,4)=#$7F'ELF') and
    (Ord(Machine[5])=2) and (Ord(Machine[6])=1) and
    (Ord(Machine[17])=2) and (Ord(Machine[19])=62),
    'неправильний ELF64 ET_EXEC x86-64');
  Check(Pos(#$39#$C8#$0F#$94#$C0,Machine)>0,
    'немає реального CMP/SETE у машинному коді');
  Check(Copy(Machine,Length(Machine)-3,4)=#$31#$FF#$0F#$05,
    'немає машинного sys_exit наприкінці');
  Save('build/m0.2/elfeq/'+String(LabelText)+'.expected.elf',Machine);
  Save('build/m0.2/elfeq/'+String(LabelText)+'.expected.out',Expected+#10);
  Inc(Good);
end;
procedure Negative(const A:array of RawByteString;const Why:String);
var Physical,OutBytes:RawByteString;Rejected:Boolean;
begin
  Physical:=EncodeT5M(W(A));OutBytes:='';Rejected:=False;
  try OutBytes:=BuildEqELF(Physical,'external/sens');
  except on E:EElfEqError do Rejected:=True;end;
  Check(Rejected and (OutBytes=''),Why);
  Inc(Bad);
end;
procedure BadPhysical(const Physical:RawByteString;const Why:String);
var OutBytes:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;OutBytes:='';
  try OutBytes:=BuildEqELF(Physical,'external/sens');
  except on E:EElfEqError do Rejected:=True;end;
  Check(Rejected and (OutBytes=''),Why);Inc(Bad);
end;
begin
  ForceDirectories('build/m0.2/elfeq');Good:=0;Bad:=0;
  Positive('рівні-0-0','1','0','0');
  Positive('різні-0-1','0','0','1');
  Positive('різні-1-0','0','1','0');
  Positive('рівні-1-1','1','1','1');
  Negative(['0'],'D1 поза викликом EQ');
  Negative(['10','010','0','1','01'],'інша голова D3 ATOM');
  Negative(['10','111','0','1','01'],'інша голова D3 CONS');
  Negative(['10','101','0','01'],'замало аргументів');
  Negative(['10','101','0','1','0','01'],'забагато аргументів');
  Negative(['10','101','000','0','01'],'D3:000 не D1');
  Negative(['10','101','10','01','0','01'],'порожній D2 не D1');
  Negative(['10','101','10','111','0','1','01','0','01'],'CONS-пара не D1');
  Negative(['10','101','0','1','01','1'],'два корені');
  Negative(['10','101','000000000001','1','01'],'фізична ширина D12 не D1');
  Negative(['10','101','0','1','11','01'],'крапкова пара');
  BadPhysical(#243,'неприпустимий байт T5M');
  BadPhysical('','порожній T5M');
  Check((Good=4) and (Bad=13),'кількість свідків');
  WriteLn('НАТИВНИЙ-EQ-ДОПУСК-ГАРАЗД D3:101=машинний позитивні=',Good,
    ' негативні=',Bad,' CMP-SETE=код-згенеровано pinned=так');
end.
