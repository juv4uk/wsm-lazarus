{ G6.69: точне віднімання двох однойменних D12+ цілих.
  Єдине джерело правил — pinned SENS Contract 12.
  Модуль реалізує двійкову механіку, не новий закон чи registry. }
unit wsm.numericsub;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ENumericSubError=class(Exception);
function SubtractNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane;

function SubtractBits(const L,R:RawByteString):RawByteString;
var I,V,Borrow:SizeInt;
begin
  if (Length(L)=0) or (Length(L)<>Length(R)) then
    raise ENumericSubError.Create('неоднакова двійкова ширина від'+'німання');
  SetLength(Result,Length(L)); Borrow:=0;
  for I:=Length(L) downto 1 do begin
    if not (L[I] in ['0','1']) or not (R[I] in ['0','1']) then
      raise ENumericSubError.Create('недвійковий біт');
    V:=Ord(L[I])-Ord(R[I])-Borrow;
    if V<0 then begin V:=V+2; Borrow:=1 end else Borrow:=0;
    Result[I]:=AnsiChar(Ord('0')+V);
  end;
end;

function ExtendSigned(const Bits:RawByteString; Width:SizeInt):RawByteString;
begin
  if (Length(Bits)=0) or (Width<Length(Bits)) then
    raise ENumericSubError.Create('неможливе знакове розширення');
  Result:=RawByteString(StringOfChar(Bits[1],Width-Length(Bits)))+Bits;
end;

function SubtractNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
var L,R,Verify:TExplicitNumeric; Bits:RawByteString;
    NewWidth,I:SizeInt; Words:TExactWords;
begin
  L:=ReadNumericPhysical(LeftPhysical,ExplicitWidth);
  R:=ReadNumericPhysical(RightPhysical,ExplicitWidth);
  Bits:=SubtractBits(L.ExactBits,R.ExactBits);
  NewWidth:=ExplicitWidth;
  { signed subtraction переповнюється, коли знаки операндів різні
    і знак різниці відрізняється від знака лівого операнда. }
  if (L.ExactBits[1]<>R.ExactBits[1]) and (Bits[1]<>L.ExactBits[1]) then begin
    if ExplicitWidth>=192 then
      raise ENumericSubError.Create('немає ратифікованого наступника після D192');
    NewWidth:=ExplicitWidth*2;
    Bits:=SubtractBits(ExtendSigned(L.ExactBits,NewWidth),
                       ExtendSigned(R.ExactBits,NewWidth));
  end;
  for I:=1 to Length(Bits) do
    if not (Bits[I] in ['0','1']) then raise ENumericSubError.Create('недвійковий результат');
  SetLength(Words,1); Words[0]:=Bits; Result:=EncodeT5M(Words);
  Verify:=ReadNumericPhysical(Result,NewWidth);
  if (Verify.DomainWidth<>NewWidth) or (Verify.ExactBits<>Bits) then
    raise ENumericSubError.Create('не відтворено точну двійкову різницю');
end;
end.
