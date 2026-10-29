{ G6.101 — 20 фізичних nested D6 fixtures і 17 незалежних негативів.
  Не заміняємо незалежний pinned SENS oracle: його запускає shell. }
program test_irmixedstep;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.numericsub,wsm.irmixedstep;
const Bases:array[0..3] of Integer=(5,17,512,2040);
var Folder:String;Rejected:Integer;
function Bits12(V:Integer):RawByteString;
var I:Integer;
begin
  Result:=StringOfChar('0',12);
  if V<0 then V:=4096+V;
  for I:=12 downto 1 do begin
    if (V and 1)<>0 then Result[I]:='1';
    V:=V shr 1;
  end;
end;
{ Pattern є тестовою перестановкою фізичних D6 голів, не законом.
  0:-+ 1:+- 2:-- 3:++. Бітова ідентичність береться лише з W6.
  Questions: чому два різні W6 не взаємозамінні?
  Що гарантує фізичний D2:10/01?
  Як перевіряється порядок від inner до outer? }
function HeadAt(Step,Pattern:Integer):RawByteString;
begin
  if (Pattern=2) or
     ((Pattern=0) and ((Step mod 2)=0)) or
     ((Pattern=1) and ((Step mod 2)=1)) then Result:='001111'
  else Result:='001110';
end;
function Form(Depth,Base,Pattern,BadStep:Integer;
  const BadHead,Leaf:RawByteString):RawByteString;
var W:TExactWords;I,K:Integer;
begin
  SetLength(W,3*Depth+1);K:=0;
  for I:=0 to Depth-1 do begin
    W[K]:='10';Inc(K);
    if (Depth-1-I)=BadStep then W[K]:=BadHead
    else W[K]:=HeadAt(Depth-1-I,Pattern);
    Inc(K);
  end;
  if Leaf<>'' then W[K]:=Leaf else W[K]:=Bits12(Base);
  Inc(K);
  for I:=1 to Depth do begin W[K]:='01';Inc(K) end;
  Result:=EncodeT5M(W);
end;
function Good(Depth,Base,Pattern:Integer):RawByteString;
begin Result:=Form(Depth,Base,Pattern,-1,'','') end;
function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const What:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try Image:=BuildIRMixedStepELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Rejected);Exit end end;
  raise Exception.Create('помилково прийнято '+What+
    ' ELFbytes='+IntToStr(Length(Image)));
end;
procedure Run;
var Depth,I,J,K:Integer;W,T:TExactWords;
    Source,Image,Expected,One:RawByteString;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог доказів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then
    raise Exception.Create('не створено каталог');
  One:=EncodeNumericDecimal('1',12);
  Rejected:=0;
  for Depth:=1 to 5 do
    for I:=0 to 3 do begin
      Source:=Good(Depth,Bases[I],I);
      Image:=BuildIRMixedStepELF(Source,'external/sens');
      Expected:=Atom(Bits12(Bases[I]));
      for J:=0 to Depth-1 do
        if HeadAt(J,I)='001111' then
          Expected:=SubtractNumericPhysical(Expected,One,12)
        else Expected:=AddNumericPhysical(Expected,One,12);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.sens',Source);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.elf',Image);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.expected.sens',Expected);
    end;
  Reject('чужий D6 код',Form(2,12,0,0,'001100',''));
  Reject('інший зовнішній D6',Form(3,12,0,2,'001100',''));
  Reject('підміна голови D5',Form(2,12,0,0,'01010',''));
  Reject('підміна голови D7',Form(2,12,0,0,'0000001',''));
  Reject('D1 листок',Form(2,12,0,-1,'','1'));
  Reject('D7 листок',Form(2,12,0,-1,'','0000001'));
  Reject('D24 листок',Form(2,12,0,-1,'',StringOfChar('0',23)+'1'));
  Reject('зайва глибина',Good(6,12,0));
  Reject('порожній потік','');
  Reject('неприпустимий T5M',#$FF);
  Reject('CPU SUB від нуля',Good(1,0,0));
  Reject('CPU SUB від відємного',Good(1,-1,0));
  Reject('другий SUB від нуля',Good(2,1,2));
  Reject('D12 overflow додавання',Good(1,2047,1));
  Reject('D12 overflow у кроці 3',Good(5,2044,3));
  DecodeT5M(Good(2,5,0),W);
  SetLength(W,Length(W)-1);
  Reject('відсутня D2 закривна дужка',EncodeT5M(W));
  DecodeT5M(Good(1,5,0),W);
  K:=Length(W);SetLength(T,K+1);
  for J:=0 to K-2 do T[J]:=W[J];
  T[K-1]:=Bits12(1);T[K]:=W[K-1];
  Reject('зайвий унарний аргумент',EncodeT5M(T));
  if Rejected<>17 then raise Exception.Create(
    'не пройшли всі негативи '+IntToStr(Rejected));
  WriteLn('D6-MIXED-UNIT-OK positive=20 negative=17');
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'D6-MIXED-UNIT-FAIL: ',E.Message);Halt(1)
  end end;
end.
