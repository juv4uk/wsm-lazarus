{ G6.156 — фізичні дві функції/один machine image з pinned W7 та D24.
  Усі .sens тут справжні packed T5M байти; український текст — лише
  вибір exact D7 координат через pinned карту, не dispatch.
  Масиви TExactWords керовані FPC; усі TFileStream звільнено finally.
  Питання: чому NameNode має точні D2 10/01? Чому D24 не дорівнює D1?
  Чому B має фізичне тіло, навіть якщо арифметичний A його не викликає?
  Чому машинний результат перевіряється незалежним числовим кодеком? }
program test_pair_body_stdout;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d7text,wsm.numericplane;
var Map:TD7Map;Dir:String;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create(Why); end;
procedure Save(const FileName:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+FileName,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
function One(const Bits:RawByteString):TExactWords;
begin SetLength(Result,1);Result[0]:=Bits end;
function Join(const Parts:array of TExactWords):TExactWords;
var I,J,N:SizeInt;
begin
  SetLength(Result,0);
  for I:=0 to High(Parts) do for J:=0 to High(Parts[I]) do begin
    N:=Length(Result);SetLength(Result,N+1);Result[N]:=Parts[I][J];
  end;
end;
function NameNode(const Value:RawByteString):TExactWords;
var Raw,Bits:RawByteString;W:TExactWords;I,N:SizeInt;
begin
  Raw:=EncodeD7Text(Value,Map,dsUk);
  DecodeT5M(Raw,W);Bits:='';
  for I:=0 to High(W) do Bits:=Bits+W[I];
  Need((Length(Bits)>0) and (Length(Bits) mod 7=0),
       'ім’я не є pinned D7');
  N:=Length(Bits) div 7;
  SetLength(Result,N+2);Result[0]:='10';Result[N+1]:='01';
  for I:=0 to N-1 do Result[I+1]:=Copy(Bits,I*7+1,7);
end;
function Atom24(N:Integer):TExactWords;
begin
  DecodeT5M(EncodeNumericDecimal(RawByteString(IntToStr(N)),24),Result);
  Need(Length(Result)=1,'немає одного D24');
end;
function Quote24(N:Integer):TExactWords;
begin Result:=Join([One('10'),One('001'),Atom24(N),One('01')]);end;
function Call2(const Head:RawByteString;const A,B:TExactWords):TExactWords;
begin Result:=Join([One('10'),One(Head),A,B,One('01')]);end;
function Call1(const Head,A:TExactWords):TExactWords;
begin Result:=Join([One('10'),Head,A,One('01')]);end;
function Clause(const Test,Body:TExactWords):TExactWords;
begin Result:=Join([One('10'),Test,Body,One('01')]);end;
procedure CasePair(const Tag:String;const A,AN,B,BN,P:TExactWords;
  Input,Wanted:Integer;const OracleTag:String);
begin
  Save(Tag+'.a.sens',EncodeT5M(A));
  Save(Tag+'.an.sens',EncodeT5M(AN));
  Save(Tag+'.b.sens',EncodeT5M(B));
  Save(Tag+'.bn.sens',EncodeT5M(BN));
  Save(Tag+'.p.sens',EncodeT5M(P));
  Save(Tag+'.input.sens',EncodeNumericDecimal(RawByteString(IntToStr(Input)),24));
  WriteLn(Tag,#9,Input,#9,Wanted,#9,OracleTag);
end;
procedure Run;
var P,AN,BN,ArithA,ArithB,EvenA,OddB,Less,MinusOne:TExactWords;
begin
  Need(ParamCount=2,'потрібні pinned корінь та каталог');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(2));
  Need(ForceDirectories(Dir),'немає каталогу');
  LoadPinnedD7Map(ParamStr(1),Map);
  P:=NameNode('величина');AN:=NameNode('парне');BN:=NameNode('непарне');
  ArithA:=Call2('01010',P,Quote24(300));
  ArithB:=Call2('01011',P,Quote24(300));
  CasePair('plus342',ArithA,AN,ArithB,BN,P,42,342,'додати');
  CasePair('plus260',ArithA,AN,ArithB,BN,P,-40,260,'додати');
  CasePair('minus100',ArithA,AN,ArithB,BN,P,-400,-100,'додати');
  Less:=Call2('11010',P,Quote24(1));
  MinusOne:=Call2('01011',P,Quote24(1));
  EvenA:=Join([One('10'),One('110'),
    Clause(Less,Quote24(1)),
    Clause(One('1'),Call1(BN,MinusOne)),One('01')]);
  OddB:=Join([One('10'),One('110'),
    Clause(Less,Quote24(0)),
    Clause(One('1'),Call1(AN,MinusOne)),One('01')]);
  CasePair('even0',EvenA,AN,OddB,BN,P,0,1,'прямий');
  CasePair('odd1',EvenA,AN,OddB,BN,P,1,0,'прямий');
  CasePair('odd5',EvenA,AN,OddB,BN,P,5,0,'прямий');
  CasePair('even8',EvenA,AN,OddB,BN,P,8,1,'прямий');
  Save('overflow.sens',EncodeNumericDecimal('8388607',24));
  Save('wrong-width.sens',EncodeNumericDecimal('1',12));
  Save('bad-body.sens',EncodeT5M(One('101')));
  Save('corrupt.sens',#$FF);
  WriteLn(StdErr,'PAIR-BODY-FIXTURES-OK cases=7');
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'PAIR-BODY-FIXTURES-FAIL: ',E.Message);Halt(2)
  end end;
end.
