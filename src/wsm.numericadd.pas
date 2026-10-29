{ G3.38 — точне фізичне додавання однакових D12+ атомів.
  Закон: pinned SENS 12.0, numeric-d12-start-extension-1.
  Цей механізм не створює викличного коду D5, законів чи Core4. }
unit wsm.numericadd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ENumericAddError=class(Exception);
function AddNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane;

{ L/R: exact-width перевірені бітові буфери. Результат: новий
  керований рядок; FPC керує часом життя. Жодного Int64/decimal.
  Питання: чому carry йде справа наліво? Чи рівні домени?
  Чому арифметичну помилку не можна замінити на D1:0? }
function AddBits(const L,R:RawByteString):RawByteString;
var I,S,Carry:SizeInt;
begin
  if (Length(L)=0) or (Length(L)<>Length(R)) then
    raise ENumericAddError.Create('неоднакова фізична ширина доданків');
  SetLength(Result,Length(L));
  Carry:=0;
  for I:=Length(L) downto 1 do begin
    if not (L[I] in ['0','1']) or not (R[I] in ['0','1']) then
      raise ENumericAddError.Create('недвійковий біт');
    S:=Ord(L[I])-48+Ord(R[I])-48+Carry;
    Result[I]:=AnsiChar(48+(S and 1));
    Carry:=S shr 1;
  end;
end;

{ Повертає власне точне двійкове знакове розширення.
  Питання: чому -1 розширюється одиницями, а не нулями?
  Який дім відповідає за визволення Result? Чому не змінено input? }
function ExtendSigned(const Bits:RawByteString; W:SizeInt):RawByteString;
begin
  if (Length(Bits)=0) or (W<Length(Bits)) then
    raise ENumericAddError.Create('неможливе знакове розширення');
  Result:=RawByteString(StringOfChar(Bits[1],W-Length(Bits)))+Bits;
end;

{ Обидва фізичні входи — позичені T5M-байти, ExplicitWidth — явний
  D12/D24/D48/D96/D192, не виведений з байтової довжини. Вихід —
  канонічні власні T5M-байти ОДНОГО атома; без публікації в stdout.
  Питання: навіщо двічі ReadNumericPhysical? Чому змішані Dn не
  додаються? Що доводить знак результату? Чому D192 overflow —
  відмова? Як зберігаються всі провідні біти? }
function AddNumericPhysical(const LeftPhysical,RightPhysical:RawByteString;
  ExplicitWidth:SizeInt):RawByteString;
var L,R,Verify:TExplicitNumeric; Bits:RawByteString;
  NewWidth:SizeInt; Words:TExactWords;
begin
  L:=ReadNumericPhysical(LeftPhysical,ExplicitWidth);
  R:=ReadNumericPhysical(RightPhysical,ExplicitWidth);
  Bits:=AddBits(L.ExactBits,R.ExactBits);
  NewWidth:=ExplicitWidth;
  if (L.ExactBits[1]=R.ExactBits[1]) and
     (Bits[1]<>L.ExactBits[1]) then begin
    if ExplicitWidth>=192 then
      raise ENumericAddError.Create('немає допущеного наступника після D192');
    NewWidth:=ExplicitWidth*2;
    Bits:=AddBits(ExtendSigned(L.ExactBits,NewWidth),
                  ExtendSigned(R.ExactBits,NewWidth));
  end;
  SetLength(Words,1);
  Words[0]:=Bits;
  Result:=EncodeT5M(Words);
  Verify:=ReadNumericPhysical(Result,NewWidth);
  if Verify.ExactBits<>Bits then
    raise ENumericAddError.Create('порушено точне фізичне кодування суми');
end;
end.
