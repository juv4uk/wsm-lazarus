{ G3.43: точне двійкове множення двох однаково-доменних D12+ цілих.
  ПРАВО: pinned SENS 12.0, numeric-d12-start-extension-1.
  Алгоритм — лише native механізм. Жодних локальних D5 законів. }
unit wsm.numericmul;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ENumericMulError=class(Exception);
function MultiplyNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane;

{ Borrowed точні двійкові біти Wn; owned Wn magnitude.
  Two's complement інвертуємо лише для від'ємного вхідного числа.
  Жодне '0' не конвертується до D1:0, Int64 або host decimal.
  Питання: чому мінімум -2^(n-1) має позитивний magnitude з MSB=1?
  Чому немає -0? Хто володіє RawByteString? }
function AbsBits(const Bits:RawByteString):RawByteString;
var I,Carry,V:SizeInt;
begin
  if (Length(Bits)=0) or (not (Bits[1] in ['0','1'])) then
    raise ENumericMulError.Create('неприпустимі двійкові біти');
  Result:=Bits;
  if Bits[1]='0' then Exit;
  for I:=1 to Length(Bits) do
    if Bits[I]='0' then Result[I]:='1'
    else if Bits[I]='1' then Result[I]:='0'
    else raise ENumericMulError.Create('недвійкова величина');
  Carry:=1;
  for I:=Length(Result) downto 1 do begin
    V:=Ord(Result[I])-48+Carry;
    Result[I]:=AnsiChar(48+(V and 1));
    Carry:=V shr 1;
  end;
end;

{ Множимо тільки двійкові величини, результат рівно 2n біт.
  P — власний little-endian host-масив проміжних бітів, не SENS.
  Додавання за зсувами O(n²), n <=192, без переповнення машинного int.
  Питання: чому потрібно 2n? Що з carry? Де домен результату?
  Чому модуль і двійковий знак відділені від T5M transport? }
function UnsignedProduct(const A,B:RawByteString):RawByteString;
var P:array of Byte; N,I,J,K,V,Carry:SizeInt;
begin
  N:=Length(A);
  if (N=0) or (N<>Length(B)) then
    raise ENumericMulError.Create('різні ширини множників');
  SetLength(P,2*N);
  for I:=0 to N-1 do begin
    if not (B[N-I] in ['0','1']) then
      raise ENumericMulError.Create('недвійковий множник');
    if B[N-I]='1' then begin
      Carry:=0;
      for J:=0 to N-1 do begin
        if not (A[N-J] in ['0','1']) then
          raise ENumericMulError.Create('недвійковий множник');
        V:=P[I+J]+Ord(A[N-J])-48+Carry;
        P[I+J]:=Byte(V and 1);
        Carry:=V shr 1;
      end;
      K:=I+N;
      while Carry<>0 do begin
        if K>=2*N then raise ENumericMulError.Create('переповнено тимчасовий добуток');
        V:=P[K]+Carry;
        P[K]:=Byte(V and 1);
        Carry:=V shr 1;
        Inc(K);
      end;
    end;
  end;
  SetLength(Result,2*N);
  for I:=0 to 2*N-1 do
    Result[2*N-I]:=AnsiChar(48+P[I]);
end;

{ Owned точне 2n signed слово, інверсія+1 лише для від'ємного добутку.
  Для нульового magnitude знак ніколи не міняє бітів. }
function NegateBits(const Bits:RawByteString):RawByteString;
var I,V,Carry:SizeInt;
begin
  Result:=Bits;
  for I:=1 to Length(Result) do
    if Result[I]='0' then Result[I]:='1'
    else if Result[I]='1' then Result[I]:='0'
    else raise ENumericMulError.Create('недвійковий добуток');
  Carry:=1;
  for I:=Length(Result) downto 1 do begin
    V:=Ord(Result[I])-48+Carry;
    Result[I]:=AnsiChar(48+(V and 1));
    Carry:=V shr 1;
  end;
end;

{ Borrowed T5M payload двох окремих Dn атомів; ExplicitWidth є
  ВИКЛЮЧНО зовнішнім ратифікованим вибором домену, не виводиться із
  ширини, значень, D7 або десяткового тексту.
  Результат: owned canonical packed T5M Wn чи W(2n) атом;
  при переповненні D192 відмова, stdout залишається поза цим unit.
  Питання: чому знакове розширення визначає fits? Чому D192
  не може автоматично видати D384? Як перевірено round-trip?
  Чому змішані Dn не перетворюються неявно? }
function MultiplyNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
var Left,Right,Verify:TExplicitNumeric;
    Bits,Full,MagnitudeL,MagnitudeR:RawByteString;
    I,NewWidth:SizeInt; NegResult,Fits:Boolean; Words:TExactWords;
begin
  Left:=ReadNumericPhysical(LeftPhysical,ExplicitWidth);
  Right:=ReadNumericPhysical(RightPhysical,ExplicitWidth);
  MagnitudeL:=AbsBits(Left.ExactBits);
  MagnitudeR:=AbsBits(Right.ExactBits);
  Full:=UnsignedProduct(MagnitudeL,MagnitudeR);
  NegResult:=(Left.ExactBits[1]<>Right.ExactBits[1]);
  if NegResult then Full:=NegateBits(Full);
  Fits:=True;
  for I:=1 to ExplicitWidth do
    if Full[I]<>Full[ExplicitWidth+1] then begin Fits:=False; Break end;
  if Fits then begin
    NewWidth:=ExplicitWidth;
    Bits:=Copy(Full,ExplicitWidth+1,ExplicitWidth);
  end else begin
    if ExplicitWidth>=192 then
      raise ENumericMulError.Create('добуток виходить за ратифіковану D192');
    NewWidth:=ExplicitWidth*2;
    Bits:=Full;
  end;
  SetLength(Words,1);
  Words[0]:=Bits;
  Result:=EncodeT5M(Words);
  Verify:=ReadNumericPhysical(Result,NewWidth);
  if Verify.ExactBits<>Bits then
    raise ENumericMulError.Create('не відтворено точний фізичний добуток');
end;
end.
