{ G6.134 — фізичні pinned T5M/D12 множення для незалежного ELF+oracle.
  Canonical D2 root з exact D5:10110, input operands signed D12.
  Host A*B — лише очікуваний test fixture, не семантика компілятора.
  Після independent pinned SENS oracle доводиться значення.
  Output: owned файли TFileStream, TExactWords managed FPC array.
  1) Чому числа не визначає довжина W12?
  2) Чому за D24 output потрібен окремий доказ?
  3) Чому input кадр 6 байтів не є повною .sens програмою?
  4) Чому це незалежні позитиви й негативи?
  5) Де зберігаються провідні нулі фізичних слів? }
program test_elfd12mulpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;Valid,Overflow:TStringList;Good,Widen,Bad:SizeInt;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('Д5-IMUL-СВІДОК: '+Why) end;

{ Human diagnostic — owned UTF-8 bytes, host stdout handle borrowed.
  1) Чому WriteLn залежить від host codepage?
  2) Чому повідомлення не є мовною поверхнею SENS?
  3) Хто звільняє тимчасовий потік? }
procedure ReportUTF8(const Message:UnicodeString);
var B:RawByteString;S:THandleStream;
begin
  B:=RawByteString(UTF8Encode(Message))+#10;
  S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(B[1],Length(B)) finally S.Free end;
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

function Atom(Value:LongInt;Width:SizeInt):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(IntToStr(Value),Width);
  N:=ReadNumericPhysical(Result,Width);
  Need((N.DomainWidth=Width) and
    (Length(N.ExactBits)=Width) and
    (Length(Result)=(Width+4) div 5),
    'втрачено ширину фізичного числового свідка');
end;

function Bits12(Value:LongInt):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(Atom(Value,12),12);
  Result:=N.ExactBits;
end;

function Pack(const Items:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Items));
  for I:=0 to High(Items) do W[I]:=Items[I];
  Result:=EncodeT5M(W);
end;

procedure CaseOf(const LabelText:String;A,B:LongInt);
var Product:LongInt;Frame,Physical:RawByteString;
begin
  Need((A>=-2048) and (A<=2047) and
    (B>=-2048) and (B<=2047),'не точні вхідні D12');
  Product:=A*B;
  Frame:=Atom(A,12)+Atom(B,12);
  Physical:=Pack(['10','10110',Bits12(A),Bits12(B),'01']);
  Save(LabelText+'.frame',Frame);
  Save(LabelText+'.sens',Physical);
  if (Product>=-2048) and (Product<=2047) then begin
    Save(LabelText+'.expected.sens',Atom(Product,12));
    Valid.Add(LabelText+#9+IntToStr(A)+#9+IntToStr(B)+#9+
      IntToStr(Product));
    Inc(Good);
  end else begin
    Save(LabelText+'.expected-d24.sens',Atom(Product,24));
    Overflow.Add(LabelText+#9+IntToStr(A)+#9+IntToStr(B)+#9+
      IntToStr(Product));
    Inc(Widen);
  end;
end;

procedure BadFrame(const Name:String;const B:RawByteString);
begin Save(Name+'.frame',B);Inc(Bad) end;

var A,B,F:RawByteString;
begin
  Need(ParamCount=1,'потрібен каталог');
  Dir:=ParamStr(1);
  Need(ForceDirectories(Dir),'не створено каталог свідків');
  Valid:=TStringList.Create;Overflow:=TStringList.Create;
  try
    Good:=0;Widen:=0;Bad:=0;
    CaseOf('01',0,0);CaseOf('02',1,1);
    CaseOf('03',7,3);CaseOf('04',3,7);
    CaseOf('05',-7,3);CaseOf('06',7,-3);
    CaseOf('07',-7,-3);CaseOf('08',-1,1);
    CaseOf('09',1,-1);CaseOf('10',-1,-1);
    CaseOf('11',2047,1);CaseOf('12',-2047,1);
    CaseOf('13',0,2047);CaseOf('14',2047,0);
    CaseOf('15',2,-1023);CaseOf('16',-2,-1023);
    CaseOf('17',31,31);CaseOf('18',-31,-31);
    CaseOf('19',1023,2);CaseOf('20',-1023,2);
    CaseOf('21',17,-17);CaseOf('22',-42,42);
    CaseOf('23',-42,-42);CaseOf('24',100,20);
    CaseOf('25',-100,20);CaseOf('26',13,-13);
    CaseOf('overflow1',2047,2);
    CaseOf('overflow2',-2047,2);
    CaseOf('overflow3',1024,2);
    CaseOf('overflow4',-1024,3);
    CaseOf('overflow5',50,50);
    CaseOf('overflow6',-51,51);
    CaseOf('overflow7',2047,-2);
    CaseOf('overflow8',2047,2047);
    Need((Good=26) and (Widen=8),'невірний census positive/overflow');
    Valid.SaveToFile(Dir+'/cases.tsv');
    Overflow.SaveToFile(Dir+'/overflows.tsv');
    A:=Atom(1,12); B:=Atom(-1,12); F:=A+B;
    BadFrame('empty','');
    BadFrame('short1',Copy(F,1,1));
    BadFrame('short5',Copy(F,1,5));
    BadFrame('extra',F+#0);
    BadFrame('newline',F+#10);
    BadFrame('invalid243',#$FF+Copy(F,2,5));
    BadFrame('badfirst',#$02+Copy(F,2,5));
    BadFrame('badsecond',Copy(F,1,3)+#$02+Copy(F,5,2));
    BadFrame('badthird',Copy(F,1,2)+#0+Copy(F,4,3));
    BadFrame('badlast',Copy(F,1,5)+#0);
    BadFrame('projection',RawByteString(
      UTF8Encode(UnicodeString('(помножити 1 -1)')))+#10);
    BadFrame('d1',Pack(['1','0']));
    Need(Bad=12,'невірний census негативних host-кадрів');
    Save('wrong-d5.sens',Pack(['10','01010',Bits12(7),Bits12(3),'01']));
    Save('wrong-d6.sens',Pack(['10','010100',Bits12(7),Bits12(3),'01']));
    Save('d24-operand.sens',Pack(['10','10110',Bits12(7),
      '000000000000000000000011','01']));
    Save('missing-arg.sens',Pack(['10','10110',Bits12(7),'01']));
    Save('extra-arg.sens',Pack(['10','10110',Bits12(7),
      Bits12(3),Bits12(1),'01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    ReportUTF8('Д5-IMUL-СВІДКИ-ГОТОВО positive=26 d24=8 negatives=12');
  finally Valid.Free;Overflow.Free end;
end.
