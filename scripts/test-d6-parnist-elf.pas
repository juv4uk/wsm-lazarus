{ G6.85 — фізичні signed D12 входи і canonical D1 відповіді.
  Генератор НЕ є оракулом семантики: очікувані біти зіставляємо
  з незалежним pinned SENS REPL. Усі .sens фізично пакує чинний codec. }
program test_d6_parnist_elf;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String; Count:SizeInt;
procedure Save(const Name:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B))
  finally F.Free end;
end;
function D1Physical(Bit:AnsiChar):RawByteString;
var Words:TExactWords;
begin
  if not (Bit in ['0','1']) then raise Exception.Create('D1 bit');
  SetLength(Words,1);Words[0]:=Bit;
  Result:=EncodeT5M(Words);
end;
{ Один numeric D12 атом — власна packed T5M копія;
  два expected D1 — лише тестові фізичні свідки, не host закон.
  1) Чому не можна прочитати .sens через Unicode?
  2) Чому .lisp використовується лише як oracle projection?
  3) Чому D1:0 не є D12:0?
  4) Хто володіє Bytes після збереження? }
procedure CaseOne(const Name,Value:RawByteString;IsEven:Boolean);
var EvenBit,OddBit:AnsiChar;
begin
  if IsEven then begin EvenBit:='1';OddBit:='0' end
  else begin EvenBit:='0';OddBit:='1' end;
  Save(String(Name)+'.sens',EncodeNumericDecimal(Value,12));
  Save(String(Name)+'.even.sens',D1Physical(EvenBit));
  Save(String(Name)+'.odd.sens',D1Physical(OddBit));
  Inc(Count);
end;
var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Count:=0;
  CaseOne('d6-01','-2048',True);
  CaseOne('d6-02','-2047',False);
  CaseOne('d6-03','-1024',True);
  CaseOne('d6-04','-3',False);
  CaseOne('d6-05','-2',True);
  CaseOne('d6-06','-1',False);
  CaseOne('d6-07','0',True);
  CaseOne('d6-08','1',False);
  CaseOne('d6-09','2046',True);
  CaseOne('d6-10','2047',False);
  if Count<>10 then Halt(2);
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  SetLength(Words,1);Words[0]:='1';Save('bad1.sens',EncodeT5M(Words));
  Words[0]:='0010110';Save('bad7.sens',EncodeT5M(Words));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  WriteLn('D6-PARNIST-ATOMS=10 EXPECTED-D1=20 NEGATIVES=5');
end.
