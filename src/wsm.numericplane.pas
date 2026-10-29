{ G3.7 — точна числова проєкція SENS D12+.
  Власницька влада: pinned Contract 12.0 та
  contracts/numeric-domains-ratification.lisp, D12-first (2026-10-24).
  Людський десятковий запис без width-тегів, машинна тотожність завжди
  з явним доменом і повними бітами. НЕ арифметика/виклик/REPL/Core4.
  Транспортування — тільки вже злитий wsm.t5m. }
unit wsm.numericplane;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m;
type
  ENumericPlaneError = class(Exception);
  TExplicitNumeric = record
    DomainWidth: SizeInt;         { явний D12 / D24 / D48 / D96 / D192 }
    ExactBits: RawByteString;     { у тому числі знаковий біт і провідні 0 }
  end;
function SelectedNumericDomain(const Name: RawByteString): SizeInt;
function EncodeNumericDecimal(const Decimal: RawByteString;
  DomainWidth: SizeInt): RawByteString;
function ReadNumericPhysical(const Physical: RawByteString;
  DomainWidth: SizeInt): TExplicitNumeric;
function RenderNumericDecimal(const Number: TExplicitNumeric): RawByteString;

implementation

procedure CheckWidth(W: SizeInt);
begin
  if not (W in [12,24,48,96,192]) then
    raise ENumericPlaneError.Create(
      #$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$B5#$D0#$BD#$20#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$B1#$D1#$80#$D0#$B0#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$20#$44#$31#$32#$2F#$44#$32#$34#$2F#$44#$34#$38#$2F#$44#$39#$36#$2F#$44#$31#$39#$32);
end;

function SelectedNumericDomain(const Name: RawByteString): SizeInt;
begin
  if Name='D12' then Result:=12
  else if Name='D24' then Result:=24
  else if Name='D48' then Result:=48
  else if Name='D96' then Result:=96
  else if Name='D192' then Result:=192
  else raise ENumericPlaneError.Create(
    #$D0#$BD#$D0#$B5#$D0#$BF#$D1#$96#$D0#$B4#$D1#$82#$D0#$B2#$D0#$B5#$D1#$80#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD);
end;

function DivideDecimalByTwo(const Input: RawByteString;
  out Remainder: Byte): RawByteString;
var I,D,Carry,Q:SizeInt;
begin
  Result:='';
  Carry:=0;
  for I:=1 to Length(Input) do begin
    D:=Ord(Input[I])-Ord('0');
    Q:=Carry*10+D;
    if (Result<>'') or (Q div 2<>0) then
      Result:=Result+AnsiChar(Ord('0')+Q div 2);
    Carry:=Q mod 2;
  end;
  if Result='' then Result:='0';
  Remainder:=Carry;
end;

function MultiplyDecimalByTwo(const Input: RawByteString;
  Bit: Byte): RawByteString;
var I,V,Carry:SizeInt;
begin
  Result:=Input;
  Carry:=Bit;
  for I:=Length(Input) downto 1 do begin
    V:=(Ord(Input[I])-Ord('0'))*2+Carry;
    Result[I]:=AnsiChar(Ord('0')+(V mod 10));
    Carry:=V div 10;
  end;
  if Carry<>0 then Result:=AnsiChar(Ord('0')+Carry)+Result;
end;

function ExactBitsOfDecimal(const Decimal: RawByteString;
  W:SizeInt):RawByteString;
var S:RawByteString; Negative:Boolean; I,Carry:SizeInt; Bit:Byte;
begin
  CheckWidth(W);
  if (Length(Decimal)=0) or (Length(Decimal)>96) then
    raise ENumericPlaneError.Create(#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$8F#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$B0#$20#$D0#$B4#$D0#$B5#$D1#$81#$D1#$8F#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$8F);
  Negative:=Decimal[1]='-';
  S:=Decimal;
  if Negative then Delete(S,1,1);
  if (S='') or ((Length(S)>1) and (S[1]='0')) or
     (Negative and (S='0')) then
    raise ENumericPlaneError.Create(#$D0#$BD#$D0#$B5#$D0#$BA#$D0#$B0#$D0#$BD#$D0#$BE#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$B5#$D1#$81#$D1#$8F#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B5#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$BC#$D1#$96#$D0#$BD#$D1#$83#$D1#$81#$2D#$D0#$BD#$D1#$83#$D0#$BB#$D1#$8C);
  for I:=1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      raise ENumericPlaneError.Create(#$D1#$83#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D1#$96#$D0#$B9#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97#$20#$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$BD#$D1#$96#$20#$D0#$B7#$D0#$B2#$D0#$B8#$D1#$87#$D0#$B0#$D0#$B9#$D0#$BD#$D1#$96#$20#$D0#$B4#$D0#$B5#$D1#$81#$D1#$8F#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D1#$96#$20#$D1#$86#$D0#$B8#$D1#$84#$D1#$80#$D0#$B8);
  SetLength(Result,W);
  for I:=W downto 1 do begin
    S:=DivideDecimalByTwo(S,Bit);
    if Bit=1 then Result[I]:='1' else Result[I]:='0';
  end;
  if S<>'0' then
    raise ENumericPlaneError.Create(#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$20#$D0#$BD#$D0#$B5#$20#$D0#$B2#$D0#$BC#$D1#$96#$D1#$89#$D0#$B0#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F#$20#$D0#$B2#$20#$D0#$BE#$D0#$B1#$D1#$80#$D0#$B0#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD);
  if not Negative then begin
    if Result[1]<>'0' then
      raise ENumericPlaneError.Create(#$D0#$B7#$D0#$BD#$D0#$B0#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$B4#$D0#$B0#$D1#$82#$D0#$BD#$D0#$B5#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$BF#$D0#$BE#$D0#$B2#$D0#$BD#$D1#$8E#$D1#$94#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD);
    Exit;
  end;
  { Magnitude <= 2^(W-1); для мінімуму знак 1 та всі інші 0.
    Жодної неявної зміни D12 на D24. }
  if Result[1]='1' then
    for I:=2 to W do
      if Result[I]<>'0' then
        raise ENumericPlaneError.Create(#$D0#$B2#$D1#$96#$D0#$B4#$27#$D1#$94#$D0#$BC#$D0#$BD#$D0#$B5#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$20#$D0#$BD#$D0#$B8#$D0#$B6#$D1#$87#$D0#$B5#$20#$D0#$BC#$D1#$96#$D0#$BD#$D1#$96#$D0#$BC#$D1#$83#$D0#$BC#$D1#$83#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$D1#$83);
  for I:=1 to W do
    if Result[I]='0' then Result[I]:='1' else Result[I]:='0';
  Carry:=1;
  for I:=W downto 1 do begin
    if Carry=0 then Break;
    if Result[I]='1' then Result[I]:='0'
    else begin Result[I]:='1';Carry:=0;end;
  end;
  if Result[1]<>'1' then
    raise ENumericPlaneError.Create(#$D0#$B2#$D1#$82#$D1#$80#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$B7#$D0#$BD#$D0#$B0#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B1#$D1#$96#$D1#$82#$20#$D0#$BF#$D1#$80#$D0#$B8#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
end;

function EncodeNumericDecimal(const Decimal: RawByteString;
  DomainWidth: SizeInt): RawByteString;
var Words:TExactWords; Bits:RawByteString;
begin
  Bits:=ExactBitsOfDecimal(Decimal,DomainWidth);
  SetLength(Words,1);
  Words[0]:=Bits;
  Result:=EncodeT5M(Words);
end;

function ReadNumericPhysical(const Physical: RawByteString;
  DomainWidth: SizeInt): TExplicitNumeric;
var Words:TExactWords; I:SizeInt;
begin
  CheckWidth(DomainWidth);
  { Фізичний читач не визначає самостійно ані домен, ані число. }
  DecodeT5M(Physical,Words);
  if Length(Words)<>1 then
    raise ENumericPlaneError.Create(#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$84#$D1#$96#$D0#$BB#$D1#$8C#$20#$D0#$BF#$D1#$80#$D0#$B8#$D0#$B9#$D0#$BC#$D0#$B0#$D1#$94#$20#$D1#$80#$D1#$96#$D0#$B2#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$B4#$D0#$BD#$D0#$B5#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B5#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE);
  if Length(Words[0])<>DomainWidth then
    raise ENumericPlaneError.Create(#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B0#$20#$D0#$BD#$D0#$B5#$20#$D0#$B7#$D0#$B1#$D1#$96#$D0#$B3#$D0#$B0#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F#$20#$D0#$B7#$20#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$B1#$D1#$80#$D0#$B0#$D0#$BD#$D0#$B8#$D0#$BC#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$D0#$BE#$D0#$BC);
  for I:=1 to Length(Words[0]) do
    if not (Words[0][I] in ['0','1']) then
      raise ENumericPlaneError.Create(#$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B5#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE);
  if EncodeT5M(Words)<>Physical then
    raise ENumericPlaneError.Create(#$D0#$BD#$D0#$B5#$D0#$BA#$D0#$B0#$D0#$BD#$D0#$BE#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$B5#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B5#$20#$D0#$BF#$D0#$B0#$D0#$BA#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$20#$54#$35#$4D);
  Result.DomainWidth:=DomainWidth;
  Result.ExactBits:=Words[0];
end;

function RenderNumericDecimal(const Number:TExplicitNumeric):RawByteString;
var B,Digits:RawByteString; Negative:Boolean; I,Carry:SizeInt;
begin
  CheckWidth(Number.DomainWidth);
  B:=Number.ExactBits;
  if Length(B)<>Number.DomainWidth then
    raise ENumericPlaneError.Create(#$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BF#$D0#$BE#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D1#$96#$D1#$81#$D1#$82#$D1#$8C#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B8#$20#$D1#$96#$20#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B0);
  for I:=1 to Length(B) do
    if not (B[I] in ['0','1']) then
      raise ENumericPlaneError.Create(#$D0#$BD#$D0#$B5#$D0#$B1#$D1#$96#$D0#$BD#$D0#$B0#$D1#$80#$D0#$BD#$D0#$B5#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B5#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE);
  Negative:=B[1]='1';
  if Negative then begin
    for I:=1 to Length(B) do
      if B[I]='1' then B[I]:='0' else B[I]:='1';
    Carry:=1;
    for I:=Length(B) downto 1 do begin
      if Carry=0 then Break;
      if B[I]='1' then B[I]:='0'
      else begin B[I]:='1';Carry:=0;end;
    end;
  end;
  Digits:='0';
  for I:=1 to Length(B) do
    Digits:=MultiplyDecimalByTwo(Digits,Ord(B[I])-Ord('0'));
  if Negative then Result:='-'+Digits else Result:=Digits;
end;
end.
