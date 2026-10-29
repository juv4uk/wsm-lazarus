{ G6.127 — фізичні свідки pinned D5:01011 і host 2×3-byte кадри.
  TExactWords та TExplicitNumeric зберігають exact D12 бітові рисунки.
  У тесті очікування A-B — лише перевірюване fixture; справжній
  мовний oracle: незалежний pinned SENS CLI над кожним .sens файлом.
  Output .sens — canonical packed exact W12, overflow випадки
  позитивні для upstream D24, але МУСЯТЬ бути відхилені D12 ELF.
  Файли створюються owned TFileStream у finally.
  1) Чому два окремих W12 — не SENS програма?
  2) Чому D24 не можна мовчки обернути на D12?
  3) Що зберігає 12 провідних бітів разом із sign?
  4) Чому oracle має отримувати фізичний .sens, не decimal .lisp? }
program test_elfd12subpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Valid,Overflows:TStringList;Good,Overflow,Bad:SizeInt;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('D5-SUB-ПОТІК-СВІДОК: '+Why) end;

procedure ReportUTF8(const Message:UnicodeString);
var Data:RawByteString;S:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Data[1],Length(Data))
  finally S.Free end;
end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Physical12(Value:LongInt):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(IntToStr(Value),12);
  N:=ReadNumericPhysical(Result,12);
  Need((N.DomainWidth=12) and (Length(Result)=3) and
    (Length(N.ExactBits)=12),'числовий атом не є exact D12');
end;

function Bits24(Value:LongInt):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(Value),24),24);
  Result:=N.ExactBits;
end;

function Bits12(Value:LongInt):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(Physical12(Value),12);
  Result:=N.ExactBits;
end;

function Pack(const Values:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Values));
  for I:=0 to High(Values) do W[I]:=Values[I];
  Result:=EncodeT5M(W);
end;

function ProgramOf(A,B:LongInt):RawByteString;
begin Result:=Pack(['10','01011',Bits12(A),Bits12(B),'01']) end;

procedure CaseOf(const LabelText:RawByteString;A,B:LongInt);
var Frame,Expression,Expected:RawByteString;E:LongInt;Name:String;
begin
  Name:=String(LabelText);
  Frame:=Physical12(A)+Physical12(B);
  Expression:=ProgramOf(A,B);
  E:=A-B;
  Save(Name+'.frame',Frame);
  Save(Name+'.sens',Expression);
  if (E>=-2048) and (E<=2047) then begin
    Expected:=Physical12(E);
    Save(Name+'.expected.sens',Expected);
    Valid.Add(Name+#9+IntToStr(A)+#9+IntToStr(B)+#9+IntToStr(E));
    Inc(Good);
  end else begin
    Save(Name+'.expected-d24.sens',EncodeNumericDecimal(IntToStr(E),24));
    Overflows.Add(Name+#9+IntToStr(A)+#9+IntToStr(B)+#9+IntToStr(E));
    Inc(Overflow);
  end;
end;

procedure RejectFrame(const Name:String;const Frame:RawByteString);
begin Save(Name+'.frame',Frame);Inc(Bad) end;

var A,B,Frame:RawByteString;W:TExactWords;
begin
  Need(ParamCount=1,'потрібен каталог');
  Dir:=ParamStr(1);Need(ForceDirectories(Dir),'каталог недоступний');
  Valid:=TStringList.Create;Overflows:=TStringList.Create;
  try
    Good:=0;Overflow:=0;Bad:=0;
    CaseOf('01',0,0);
    CaseOf('02',1,1);
    CaseOf('03',7,3);
    CaseOf('04',3,7);
    CaseOf('05',-7,3);
    CaseOf('06',7,-3);
    CaseOf('07',-7,-3);
    CaseOf('08',-1,1);
    CaseOf('09',1,-1);
    CaseOf('10',-1,-1);
    CaseOf('11',2047,0);
    CaseOf('12',-2048,0);
    CaseOf('13',0,2047);
    CaseOf('14',2047,2047);
    CaseOf('15',-2048,-2048);
    CaseOf('16',2046,-1);
    CaseOf('17',-2047,1);
    CaseOf('18',1024,1023);
    CaseOf('19',-1024,-1023);
    CaseOf('20',2047,1);
    CaseOf('21',-2048,-1);
    CaseOf('22',1999,1000);
    CaseOf('23',0,-1);
    CaseOf('24',-2,-1);
    CaseOf('25',1234,-567);
    CaseOf('26',-1234,567);
    CaseOf('overflow1',2047,-1);
    CaseOf('overflow2',1,-2048);
    CaseOf('overflow3',-2048,1);
    CaseOf('overflow4',-2048,2047);
    CaseOf('overflow5',2047,-2048);
    CaseOf('overflow6',1024,-2048);
    Need((Good=26) and (Overflow=6),'невірна повнота signed/D24 матриці');
    Valid.SaveToFile(Dir+'/cases.tsv');
    Overflows.SaveToFile(Dir+'/overflows.tsv');
    A:=Physical12(1);B:=Physical12(-1);Frame:=A+B;
    RejectFrame('empty','');
    RejectFrame('short1',Copy(Frame,1,1));
    RejectFrame('short5',Copy(Frame,1,5));
    RejectFrame('extra',Frame+#0);
    RejectFrame('newline',Frame+#10);
    RejectFrame('invalid243',#$FF+Copy(Frame,2,5));
    RejectFrame('badfirst',#$02+Copy(Frame,2,5));
    RejectFrame('badsecond',Copy(Frame,1,3)+#$02+Copy(Frame,5,2));
    RejectFrame('badthird',Copy(Frame,1,2)+#0+Copy(Frame,4,3));
    RejectFrame('badlast',Copy(Frame,1,5)+#0);
    RejectFrame('projection',RawByteString(
      UTF8Encode(UnicodeString('(відняти 1 -1)')))+#10);
    SetLength(W,1);W[0]:='1';
    RejectFrame('d1',EncodeT5M(W)+EncodeT5M(W));
    Need(Bad=12,'неповна матриця negative frame');
    Save('wrong-d5.sens',Pack(['10','01010',Bits12(7),Bits12(3),'01']));
    Save('wrong-d6.sens',Pack(['10','010100',Bits12(7),Bits12(3),'01']));
    Save('d24-operand.sens',Pack(['10','01011',Bits12(7),
      Bits24(3),'01']));
    Save('missing-arg.sens',Pack(['10','01011',Bits12(7),'01']));
    Save('extra-arg.sens',Pack(['10','01011',Bits12(7),
      Bits12(3),Bits12(1),'01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    ReportUTF8('Д5-SUB-ПОТІК-СВІДКИ-ГОТОВО позитивів=26 D24=6 кадрів-негативів=12');
  finally Valid.Free;Overflows.Free end;
end.
