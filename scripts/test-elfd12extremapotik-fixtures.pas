{ G6.114 — 18 signed pairs, canonical W12 T5M stdin frames.
  Expected values computed by host test comparator ONLY; authoritative
  result additionally compared with independent pinned SENS REPL. }
program test_elfd12extremapotik_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,Math,wsm.numericplane,wsm.t5m;
var Folder:String;Count:Integer;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin F:=TFileStream.Create(Path,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end end;
{ Host Signed pair; output managed T5M of two DISTINCT W12 atoms.
  Why one .frame is not one .sens? Who enforces exact width?
  What is independently proven by pinned oracle? }
procedure Pair(const Name,L,R:RawByteString);
var A,B:RawByteString;X,Y:Integer;
begin
  A:=EncodeNumericDecimal(L,12);
  B:=EncodeNumericDecimal(R,12);
  if (Length(A)<>3) or (Length(B)<>3) then
    raise Exception.Create('очікується рівно 3 байти W12');
  X:=StrToInt(String(L));Y:=StrToInt(String(R));
  Save(Folder+'/'+String(Name)+'.frame',A+B);
  Save(Folder+'/'+String(Name)+'-min.sens',
    EncodeNumericDecimal(IntToStr(Min(X,Y)),12));
  Save(Folder+'/'+String(Name)+'-max.sens',
    EncodeNumericDecimal(IntToStr(Max(X,Y)),12));
  WriteLn(Name,#9,L,#9,R);
  Inc(Count);
end;
var One:TExactWords;Frame:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);ForceDirectories(Folder);Count:=0;
  Pair('00','0','0');Pair('01','1','0');Pair('02','0','1');
  Pair('03','-1','0');Pair('04','0','-1');Pair('05','-7','-3');
  Pair('06','-3','-7');Pair('07','2047','-2048');
  Pair('08','-2048','2047');Pair('09','-2048','-2048');
  Pair('10','2047','2047');Pair('11','2046','2047');
  Pair('12','-2047','-2048');Pair('13','1024','-1024');
  Pair('14','-999','1000');Pair('15','111','-22');
  Pair('16','2037','-2036');Pair('17','-128','127');
  Frame:=EncodeNumericDecimal('1',12)+EncodeNumericDecimal('1',12);
  Save(Folder+'/bad-empty.frame','');
  Save(Folder+'/bad-short1.frame',Copy(Frame,1,1));
  Save(Folder+'/bad-short5.frame',Copy(Frame,1,5));
  Save(Folder+'/bad-extra.frame',Frame+#0);
  Save(Folder+'/bad-newline.frame',Frame+#10);
  Save(Folder+'/bad-first.frame',#$FF+Copy(Frame,2,5));
  Save(Folder+'/bad-second.frame',Copy(Frame,1,3)+#$FF+Copy(Frame,5,2));
  Save(Folder+'/bad-third.frame',Copy(Frame,1,2)+#0+Copy(Frame,4,3));
  Save(Folder+'/bad-last.frame',Copy(Frame,1,5)+#0);
  Save(Folder+'/bad-projection.frame','(найменше 1 1)'+#10);
  SetLength(One,1);One[0]:='1';
  Save(Folder+'/bad-d1.frame',EncodeT5M(One)+EncodeT5M(One));
  One[0]:=StringOfChar('0',23)+'1';
  Save(Folder+'/bad-d24.frame',EncodeT5M(One)+EncodeT5M(One));
  if Count<>18 then Halt(2);
  WriteLn(StdErr,'G6.114-FIXTURES-OK pairs=18 negatives=12');
end.
