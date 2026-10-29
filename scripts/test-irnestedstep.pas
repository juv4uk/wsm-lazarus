{ G6.93 — 20 фізичних Golden ELF fixtures і 14 негативів.
  Всі очікувані числа виникають через чинний AddNumericPhysical. }
program test_irnestedstep;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.irnestedstep;
const Values:array[0..3] of Integer=(-2048,-1,0,2040);
var Folder:String;Negatives:SizeInt;
function Bits12(V:Integer):RawByteString;
var I:Integer;
begin
  Result:=StringOfChar('0',12);
  if V<0 then V:=V+4096;
  for I:=12 downto 1 do begin
    if (V and 1)<>0 then Result[I]:='1';
    V:=V shr 1;
  end;
end;
function Form(Depth:Integer;const HeadBits,AtomBits:RawByteString):RawByteString;
var W:TExactWords;I,K:Integer;
begin
  SetLength(W,3*Depth+1);
  K:=0;
  for I:=1 to Depth do begin
    W[K]:='10';Inc(K);W[K]:=HeadBits;Inc(K);
  end;
  W[K]:=AtomBits;Inc(K);
  for I:=1 to Depth do begin W[K]:='01';Inc(K) end;
  Result:=EncodeT5M(W);
end;
function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;
procedure Save(const Path:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free end;
end;
procedure Reject(const Reason:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try
    Image:=BuildNestedStepELF(Physical,'external/sens');
  except on E:Exception do begin Inc(Negatives);Exit end end;
  raise Exception.Create('помилково прийнято '+Reason+
    ' ELFbytes='+IntToStr(Length(Image)));
end;
procedure Run;
var Depth,I,J,K:Integer;W:TExactWords;
    Source,Image,Expected,One:RawByteString;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог доказів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then
    raise Exception.Create('не створено каталог');
  Negatives:=0;
  One:=EncodeNumericDecimal('1',12);
  for Depth:=1 to 5 do
    for I:=Low(Values) to High(Values) do begin
      Source:=Form(Depth,'001110',Bits12(Values[I]));
      Image:=BuildNestedStepELF(Source,'external/sens');
      Expected:=Atom(Bits12(Values[I]));
      for J:=1 to Depth do
        Expected:=AddNumericPhysical(Expected,One,12);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.sens',Source);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.elf',Image);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.expected.sens',Expected);
    end;
  Reject('інша D6 голова',Form(2,'001111',Bits12(1)));
  Reject('D5 голова',Form(1,'01010',Bits12(1)));
  Reject('D7 голова',Form(1,'0000001',Bits12(1)));
  Reject('D1 аргумент',Form(2,'001110','1'));
  Reject('D7 аргумент',Form(2,'001110','0000001'));
  Reject('D24 аргумент',Form(2,'001110',StringOfChar('0',23)+'1'));
  Reject('вихід D24 на першому кроці',Form(1,'001110',Bits12(2047)));
  Reject('вихід D24 на другому кроці',Form(2,'001110',Bits12(2046)));
  Reject('вихід D24 у п'ятому кроці',Form(5,'001110',Bits12(2043)));
  Reject('перевищена глибина 6',Form(6,'001110',Bits12(1)));
  Reject('пошкоджений T5M',#$FF);
  Reject('порожній вхід','');
  DecodeT5M(Form(2,'001110',Bits12(1)),W);
  SetLength(W,Length(W)-1);
  Reject('немає D2 кінця',EncodeT5M(W));
  DecodeT5M(Form(2,'001110',Bits12(1)),W);
  K:=Length(W);SetLength(W,K+1);W[K]:='0';
  Reject('зайвий другий корінь',EncodeT5M(W));
  if Negatives<>14 then
    raise Exception.Create('не всі негативи '+IntToStr(Negatives));
  WriteLn('D6-NESTED-UNIT-OK positive=20 negative=14');
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'D6-NESTED-UNIT-FAIL: ',E.Message);Halt(1)
  end end;
end.
