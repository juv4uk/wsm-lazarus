{ G6.106 — 16 фізичних міждоменних програм, 22 негативи.
  Очікування обчислює лише чинний pinned numeric gate; незалежний
  SENS REPL та САМ машинний ELF запускаються в shell. }
program test_ird5d6compose;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.numericsub,wsm.ird5d6compose;
const Bases:array[0..3] of Integer=(5,17,127,2030);
      Rights:array[0..3] of Integer=(3,-7,11,-2);
var Folder:String;Rejected:SizeInt;
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
function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;

{ Фізична T5M форма має рівно ВІСІМ слів:
  D2-open, D5, D2-open, D6, opaque W12, D2-close, W12, D2-close.
  Ці слова не є текстом .lisp, навіть якщо їх можна проєктувати.
  Питання: як відрізняються width=5 і width=6?
  Чому правий аргумент D5 стоїть після D2-close?
  Що станеться при зайвому D2-root? }
function Form(const Outer,Inner,BaseBits,RightBits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,8);
  W[0]:='10';W[1]:=Outer;W[2]:='10';W[3]:=Inner;
  W[4]:=BaseBits;W[5]:='01';W[6]:=RightBits;W[7]:='01';
  Result:=EncodeT5M(W);
end;
function Good(Combo,Idx:Integer):RawByteString;
var O,I:RawByteString;
begin
  if Combo>=2 then O:='01011' else O:='01010';
  if (Combo mod 2)=1 then I:='001111' else I:='001110';
  Result:=Form(O,I,Bits12(Bases[Idx]),Bits12(Rights[Idx]));
end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const Name:String;const Physical:RawByteString);
var B:RawByteString;
begin
  try B:=BuildIRComposedD5D6ELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Rejected);Exit end end;
  raise Exception.Create('прийнято негатив '+Name+' ELF='+IntToStr(Length(B)));
end;
procedure Run;
var Combo,Idx,K,J:Integer;W,T:TExactWords;
    Physical,Image,Expected,One,Right:RawByteString;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог тестів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then
    raise Exception.Create('не створено каталог тестів');
  Rejected:=0;
  One:=Atom(Bits12(1));
  for Combo:=0 to 3 do
    for Idx:=0 to 3 do begin
      Physical:=Good(Combo,Idx);
      Image:=BuildIRComposedD5D6ELF(Physical,'external/sens');
      Expected:=Atom(Bits12(Bases[Idx]));
      Right:=Atom(Bits12(Rights[Idx]));
      if (Combo mod 2)=1 then
        Expected:=SubtractNumericPhysical(Expected,One,12)
      else Expected:=AddNumericPhysical(Expected,One,12);
      if Combo>=2 then
        Expected:=SubtractNumericPhysical(Expected,Right,12)
      else Expected:=AddNumericPhysical(Expected,Right,12);
      Save(Folder+IntToStr(Combo)+'-'+IntToStr(Idx)+'.sens',Physical);
      Save(Folder+IntToStr(Combo)+'-'+IntToStr(Idx)+'.elf',Image);
      Save(Folder+IntToStr(Combo)+'-'+IntToStr(Idx)+'.expected.sens',Expected);
    end;
  Reject('чужий D5 ключ',Form('10110','001110',Bits12(5),Bits12(1)));
  Reject('чужий D6 ключ',Form('01010','000000',Bits12(5),Bits12(1)));
  Reject('голова D6 замість D5',Form('001110','001110',Bits12(5),Bits12(1)));
  Reject('голова D5 замість D6',Form('01010','01010',Bits12(5),Bits12(1)));
  Reject('основа D1',Form('01010','001110','1',Bits12(1)));
  Reject('основа D7',Form('01010','001110','0000001',Bits12(1)));
  Reject('основа D24',Form('01010','001110',StringOfChar('0',23)+'1',Bits12(1)));
  Reject('правий D1',Form('01010','001110',Bits12(5),'1'));
  Reject('правий D7',Form('01010','001110',Bits12(5),'0000001'));
  Reject('правий D24',Form('01010','001110',Bits12(5),StringOfChar('0',23)+'1'));
  Reject('порожня програма','');
  Reject('неприпустимий T5M',#$FF);
  DecodeT5M(Good(0,0),W);
  W[0]:='01';
  Reject('неправильний зовнішній D2-маркер',EncodeT5M(W));
  DecodeT5M(Good(0,0),W);
  SetLength(W,7);
  Reject('немає закривної D2 дужки',EncodeT5M(W));
  DecodeT5M(Good(0,0),W);
  W[6]:='01';SetLength(W,7);
  Reject('немає правого D5 аргументу',EncodeT5M(W));
  DecodeT5M(Good(0,0),W);
  K:=Length(W);SetLength(T,K+1);
  for J:=0 to K-2 do T[J]:=W[J];
  T[K-1]:=Bits12(1);T[K]:=W[K-1];
  Reject('зайвий D5 аргумент',EncodeT5M(T));
  DecodeT5M(Good(0,0),W);
  K:=Length(W);SetLength(W,K+1);W[K]:=Bits12(1);
  Reject('другий корінь',EncodeT5M(W));
  Reject('CPU SUB1 від нуля',
    Form('01010','001111',Bits12(0),Bits12(1)));
  Reject('CPU SUB1 від від’ємного',
    Form('01010','001111',Bits12(-1),Bits12(1)));
  Reject('переповнення D6 +1',
    Form('01010','001110',Bits12(2047),Bits12(0)));
  Reject('переповнення D5 +',
    Form('01010','001110',Bits12(2046),Bits12(1)));
  Reject('переповнення D5 -',
    Form('01011','001110',Bits12(-2048),Bits12(2)));
  if Rejected<>22 then raise Exception.Create(
    'очікувалося 22 негативи, відхилено '+IntToStr(Rejected));
  WriteLn('D5-D6-UNIT-OK positive=16 negative=22');
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'D5-D6-UNIT-FAIL: ',E.Message);Halt(1)
  end end;
end.
