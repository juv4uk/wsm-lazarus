{ G6.241 — перевірка реального SUB→TEST/SETE ELF64 на фізичних D12.
  Очікування — механічні свідки, не незалежний SENS oracle.
  Дані входу borrowed; ELF і фізичний D1 вихід — managed FPC.
  Запитання: чому D12-нуль не D1:0? Чому відхиляємо D24?
  Чому знаковість D12 важлива? Хто звільняє потоки? }
program test_verified_subzero;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12subzero,wsm.numericplane,wsm.t5m;
var Directory:String;Pass,Rejected:SizeInt;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Positive(const LabelText,A,B,Truth:RawByteString);
var L,R,ELF,Expected:RawByteString;W:TExactWords;
begin
  L:=EncodeNumericDecimal(A,12);
  R:=EncodeNumericDecimal(B,12);
  ELF:=BuildD12SubZeroELF(L,R);
  SetLength(W,1);W[0]:=Truth;Expected:=EncodeT5M(W);
  if Length(Expected)<>1 then Halt(52);
  Save(String(LabelText)+'.elf',ELF);
  Save(String(LabelText)+'.want.sens',Expected);
  WriteLn(String(LabelText),#9,String(A),#9,String(B),#9,String(Truth));
  Inc(Pass);
end;

procedure Reject(const L,R:RawByteString);
var Image:RawByteString;
begin
  try
    Image:=BuildD12SubZeroELF(L,R);
    WriteLn(StdErr,'SUBZERO-НЕПРАВИЛЬНИЙ-ДОПУСК довжина=',Length(Image));
    Halt(53);
  except
    on E:Exception do begin
      if E.Message='' then Halt(54);
      Inc(Rejected);
    end;
  end;
end;

var W:TExactWords;D1,D7,D24:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);
  if not ForceDirectories(Directory) then Halt(2);
  Pass:=0;Rejected:=0;
  Positive('01','0','0','1');
  Positive('02','1','1','1');
  Positive('03','-1','-1','1');
  Positive('04','2047','2047','1');
  Positive('05','-2048','-2048','1');
  Positive('06','17','18','0');
  Positive('07','18','17','0');
  Positive('08','-17','-18','0');
  Positive('09','-18','-17','0');
  Positive('10','1','-1','0');
  Positive('11','-1','1','0');
  Positive('12','2047','0','0');
  Positive('13','-2048','0','0');
  Positive('14','0','2047','0');
  Positive('15','-1000','1000','0');
  Positive('16','1000','-1000','0');
  SetLength(W,1);
  W[0]:='1';D1:=EncodeT5M(W);
  W[0]:='0010110';D7:=EncodeT5M(W);
  D24:=EncodeNumericDecimal('1',24);
  Reject(EncodeNumericDecimal('-2048',12),EncodeNumericDecimal('2047',12));
  Reject(EncodeNumericDecimal('2047',12),EncodeNumericDecimal('-2048',12));
  Reject(EncodeNumericDecimal('0',12),EncodeNumericDecimal('-2048',12));
  Reject(EncodeNumericDecimal('-2048',12),EncodeNumericDecimal('1',12));
  Reject(D1,EncodeNumericDecimal('1',12));
  Reject(EncodeNumericDecimal('1',12),D24);
  Reject(D7,EncodeNumericDecimal('0',12));
  Reject(#$FF,'');
  if (Pass<>16) or (Rejected<>8) then Halt(55);
  WriteLn(StdErr,'SUBZERO-FPC-PASS positive=',Pass,' negative=',Rejected);
end.
