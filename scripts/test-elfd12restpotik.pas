{ G6.120 — фізичні D12 host stdin frames для повторно використовуваного
  D6:010100 нативного ELF. Результат — тільки canonical packed T5M.
  Для незалежного semantic proof кожне позитивне expected додатково
  перевіряється через pinned SENS REPL у hosted CI.
  Вхід: borrowed каталог, owned TFileStream у finally.
  Frame — НЕ багатослівний .sens документ, а два окремі packed атоми.
  1) Чому кадр 6 фізичних байтів? 2) Чому всі числа — D12?
  3) Чому expected не може бути самостійним мовним законом?
  4) Чому негативи мусять завершуватись без stdout? }
program test_elfd12restpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Valid:TStringList;PosCount,NegCount:SizeInt;

procedure Save(const Name:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then Stream.WriteBuffer(Data[1],Length(Data))
  finally Stream.Free end;
end;

function Physical12(const Number:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(Number,12);
  N:=ReadNumericPhysical(Result,12);
  if (Length(Result)<>3) or (N.DomainWidth<>12) then
    raise Exception.Create('неканонічний D12 свідок');
end;

procedure Positive(const LabelText:RawByteString;A,B:LongInt);
var Left,Right:RawByteString;
begin
  if (A<0) or (A>2047) or (B<1) or (B>2047) then Halt(20);
  Left:=Physical12(IntToStr(A));Right:=Physical12(IntToStr(B));
  Save(String(LabelText)+'.frame',Left+Right);
  Save(String(LabelText)+'.expected.sens',Physical12(IntToStr(A mod B)));
  Valid.Add(String(LabelText)+#9+IntToStr(A)+#9+IntToStr(B));
  Inc(PosCount);
end;

procedure Negative(const Name:String;const Data:RawByteString);
begin
  Save(Name+'.frame',Data);
  Inc(NegCount);
end;

var One,Three,Frame:RawByteString;
    Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Valid:=TStringList.Create;
  try
    PosCount:=0;NegCount:=0;
    Positive('01',0,1);
    Positive('02',1,1);
    Positive('03',2,3);
    Positive('04',7,3);
    Positive('05',15,4);
    Positive('06',17,5);
    Positive('07',1024,31);
    Positive('08',2047,2);
    Positive('09',2047,2047);
    Positive('10',2046,2047);
    Positive('11',127,7);
    Positive('12',1234,17);
    Positive('13',1999,100);
    Positive('14',2000,64);
    Valid.SaveToFile(Dir+'/cases.tsv');
    One:=Physical12('1');
    Three:=Physical12('3');
    Frame:=One+Three;
    Negative('zero-divisor',Physical12('7')+Physical12('0'));
    Negative('both-zero',Physical12('0')+Physical12('0'));
    Negative('negative-left',Physical12('-1')+Three);
    Negative('negative-right',Physical12('7')+Physical12('-3'));
    Negative('both-negative',Physical12('-7')+Physical12('-3'));
    Negative('min-left',Physical12('-2048')+Three);
    Negative('min-right',Physical12('7')+Physical12('-2048'));
    Negative('negative-minus-one',Physical12('2047')+Physical12('-1'));
    Negative('empty','');
    Negative('short1',Copy(Frame,1,1));
    Negative('short5',Copy(Frame,1,5));
    Negative('extra',Frame+#0);
    Negative('newline',Frame+#10);
    Negative('invalid243',#$FF+Copy(Frame,2,5));
    Negative('badfirst',#$02+Copy(Frame,2,5));
    Negative('badsecond',Copy(Frame,1,3)+#$02+Copy(Frame,5,2));
    Negative('badthird',Copy(Frame,1,2)+#0+Copy(Frame,4,3));
    Negative('badlast',Copy(Frame,1,5)+#0);
    Negative('projection',RawByteString(UTF8Encode(UnicodeString(
      '(остача 1 3)')))+#10);
    SetLength(Words,1);
    Words[0]:='1';
    Negative('d1',EncodeT5M(Words)+EncodeT5M(Words));
    if (PosCount<>14) or (NegCount<>20) then Halt(3);
    WriteLn('Д6-ОСТАЧА-ПОТІК-СВІДКИ-ГОТОВО позитивів=14 негативів=20');
  finally Valid.Free end;
end.
