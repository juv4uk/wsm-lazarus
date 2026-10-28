program test_core4_nested;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.core4runtime,wsm.t5m;
var Runtime:TCore4Runtime;Name,Global0,Global1,Bad:RawByteString;
    W:TExactWords;I,Negative:SizeInt;

procedure Check(B:Boolean;const Why:String);
begin if not B then raise Exception.Create('ВІДМОВА: '+Why); end;

function Seq(const Items:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(Items));
  for J:=0 to High(Items) do Result[J]:=Items[J];
end;

function Identifier(const Id:RawByteString):TExactWords;
var J,N:SizeInt;
begin
  Check((Length(Id)>0) and (Length(Id) mod 7=0),'невалідна D7');
  N:=Length(Id) div 7;
  SetLength(Result,N+2);
  Result[0]:='10';
  for J:=0 to N-1 do Result[J+1]:=Copy(Id,J*7+1,7);
  Result[N+1]:='01';
end;

function Apply(const Id:RawByteString;const Arg:TExactWords):TExactWords;
var Head:TExactWords;J,K:SizeInt;
begin
  Head:=Identifier(Id);
  SetLength(Result,Length(Head)+Length(Arg)+2);
  K:=0;Result[K]:='10';Inc(K);
  for J:=0 to High(Head) do begin Result[K]:=Head[J];Inc(K);end;
  for J:=0 to High(Arg) do begin Result[K]:=Arg[J];Inc(K);end;
  Result[K]:='01';
end;

procedure Equals(const Form:TExactWords;const Bits:RawByteString;const Why:String);
var Actual:RawByteString;Decoded:TExactWords;
begin
  Actual:=Runtime.ExecutePhysicalCall(EncodeT5M(Form));
  DecodeT5M(Actual,Decoded);
  Check((Length(Decoded)=1) and (Decoded[0]=Bits),Why);
  Check(Actual=EncodeT5M(Seq([Bits])),Why+' byte-exact');
end;

procedure Reject(const Form:TExactWords;const Why:String);
var Failed:Boolean;
begin
  Failed:=False;
  try Runtime.ExecutePhysicalCall(EncodeT5M(Form));
  except on E:ECore4RuntimeError do Failed:=True;end;
  Check(Failed,Why+' прийнято');
  Inc(Negative);
end;

begin
  Check(ParamCount=1,'корінь pinned SENS потрібний');
  Negative:=0;
  Runtime:=TCore4Runtime.Create(ParamStr(1));
  try
    Check(Runtime.BindingCount=3,'три справжні визначення');
    Name:=Runtime.FirstDefinitionIdentifier;
    Global0:=Runtime.BindingIdentifier(1);
    Global1:=Runtime.BindingIdentifier(2);
    Bad:=Copy(Name,1,Length(Name));
    if Bad[1]='0' then Bad[1]:='1' else Bad[1]:='0';

    Equals(Apply(Name,Seq(['1'])),'1','атом D1:1');
    Equals(Apply(Name,Apply(Name,Seq(['0']))),'0','два вкладення');
    Equals(Apply(Name,Apply(Name,Apply(Name,Seq(['1'])))),
      '1','три вкладення');
    Equals(Apply(Name,Identifier(Global0)),
      '000000000000000000000000','pinned D24:0');
    Equals(Apply(Name,Apply(Name,Identifier(Global1))),
      '000000000000000000000001','pinned D24:1');
    Equals(Identifier(Global0),
      '000000000000000000000000','збережене читання глобала');

    Reject(Apply(Name,Seq(['000'])),'D3:000 не D1:0');
    Reject(Apply(Bad,Seq(['1'])),'невідома exact D7 голова');
    Reject(Apply(Global0,Seq(['1'])),'глобал невикличний');
    Reject(Identifier(Name),'замикання без застосування');
    Reject(Apply(Name,Seq(['10','01'])),'порожній аргумент');
    Reject(Apply(Name,Seq(['1','0'])),'неправильна арність');
    Reject(Seq(['10','0011','1','01']),'raw D4 голова');

    W:=Seq(['1']);
    for I:=1 to 66 do W:=Apply(Name,W);
    Reject(W,'перевищено вкладеність 64');
    Check(Runtime.BindingCount=3,'стійке середовище після помилок');
    Equals(Apply(Name,Identifier(Global1)),
      '000000000000000000000001','повторний успіх');
    WriteLn('CORE4-NESTED-OK cases=7 negatives=',Negative,
      ' pinned=core4.sens physical=T5M byte-exact=yes');
  finally Runtime.Free; end;
end.
