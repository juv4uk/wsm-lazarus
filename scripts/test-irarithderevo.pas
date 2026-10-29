{ G6.146 — справжні mixed фізичні D5 дерева: ліві/праві/збалансовані/
  нерегулярні. Цілочисельне очікування тут лише TEST witness;
  мовний авторитет підтверджує окремий pinned SENS REPL у CI. }
program test_irarithderevo;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.irarithderevo;
const Sizes:array[0..7] of Integer=(1,2,3,5,8,12,20,31);
type
  TTree=record
    Words:TExactWords;
    Human:RawByteString;
    Expected:Integer;
  end;
var Folder:String;Positive,Negative:Integer;

function Bits12(V:Integer):RawByteString;
var I:Integer;
begin
  if (V< -2048) or (V>2047) then
    raise Exception.Create('тест поза D12');
  if V<0 then V:=V+4096;
  SetLength(Result,12);
  for I:=12 downto 1 do begin
    if (V and 1)<>0 then Result[I]:='1' else Result[I]:='0';
    V:=V shr 1;
  end;
end;
function PhysicalAtom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;

{ Кожна внутрішня форма: D2:10, pinned D5 W5, рівно два незалежні
  дочірні піддерева, D2:01. Text є тільки українською проєкцією для
  НЕЗАЛЕЖНОГО oracle; не використовується у Pascal компіляторі.
  Питання: чому віднімання з лівого піддерева не можна переставити?
  Чому тестовий signed Integer не є SENS canonical?
  Чому слова з'єднуються як TExactWords, а не текстові біти? }
function BuildTree(Ops,Shape,Seed:Integer):TTree;
var Left,Right:TTree;I,LeftOps,RightOps,Val:Integer;
    Head,Title:RawByteString;
begin
  if Ops=0 then begin
    Val:=(Seed*7+Shape*3) mod 15-7;
    SetLength(Result.Words,1);Result.Words[0]:=Bits12(Val);
    Result.Human:=RawByteString(IntToStr(Val));
    Result.Expected:=Val;
    Exit;
  end;
  case Shape of
    0:LeftOps:=Ops-1;
    1:LeftOps:=0;
    2:LeftOps:=(Ops-1) div 2;
    else LeftOps:=(Ops*3+Seed) mod Ops;
  end;
  RightOps:=Ops-1-LeftOps;
  Left:=BuildTree(LeftOps,Shape,(Seed*3+5) mod 97);
  Right:=BuildTree(RightOps,Shape,(Seed*5+7) mod 97);
  if ((Seed+Ops+Shape) mod 3)=0 then begin
    Head:='01011';Title:='відняти';
    Result.Expected:=Left.Expected-Right.Expected;
  end else begin
    Head:='01010';Title:='додати';
    Result.Expected:=Left.Expected+Right.Expected;
  end;
  if (Result.Expected< -2048) or (Result.Expected>2047) then
    raise Exception.Create('позитивне дерево вийшло за D12');
  SetLength(Result.Words,Length(Left.Words)+Length(Right.Words)+3);
  Result.Words[0]:='10';Result.Words[1]:=Head;
  for I:=0 to High(Left.Words) do Result.Words[2+I]:=Left.Words[I];
  for I:=0 to High(Right.Words) do
    Result.Words[2+Length(Left.Words)+I]:=Right.Words[I];
  Result.Words[High(Result.Words)]:='01';
  Result.Human:='('+Title+' '+Left.Human+' '+Right.Human+')';
end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const Tag:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try Image:=BuildIRMixedTreeELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Negative);Exit end end;
  raise Exception.Create('прийнято недопустиму форму '+Tag+
    ' ELF='+IntToStr(Length(Image)));
end;
procedure Run;
var Shape,Pos,Ops,I:Integer;T:TTree;W,Wrong:TExactWords;
    Image,Physical,LabelName:RawByteString;
    Manifest:TStringList;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог доказів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then
    raise Exception.Create('не створено каталог');
  Positive:=0;Negative:=0;
  Manifest:=TStringList.Create;
  try
    for Shape:=0 to 3 do
      for Pos:=0 to High(Sizes) do begin
        Ops:=Sizes[Pos];
        T:=BuildTree(Ops,Shape,Shape+2);
        Physical:=EncodeT5M(T.Words);
        Image:=BuildIRMixedTreeELF(Physical,'external/sens');
        LabelName:=IntToStr(Shape)+'-'+IntToStr(Ops);
        Save(Folder+String(LabelName)+'.sens',Physical);
        Save(Folder+String(LabelName)+'.elf',Image);
        Save(Folder+String(LabelName)+'.expected.sens',
          PhysicalAtom(Bits12(T.Expected)));
        Save(Folder+String(LabelName)+'.oracle.lisp',T.Human+#10);
        Manifest.Add(String(LabelName)+#9+IntToStr(Ops));
        Inc(Positive);
      end;
    Manifest.SaveToFile(Folder+'cases.tsv');
  finally Manifest.Free end;

  T:=BuildTree(1,0,2);
  Reject('порожній фізичний файл','');
  Reject('пошкоджений T5M',#$FF);
  Reject('лише атом',PhysicalAtom(Bits12(3)));
  DecodeT5M(EncodeT5M(T.Words),W);
  W[1]:='10110';Reject('D5 множення',EncodeT5M(W));
  W[1]:='001110';Reject('D6 замість D5',EncodeT5M(W));
  W[1]:='0000001';Reject('D7 замість D5',EncodeT5M(W));
  W[1]:='01010';
  W[2]:='1';Reject('D1 лівий',EncodeT5M(W));
  W[2]:=Bits12(3);W[3]:=StringOfChar('0',24);
  Reject('D24 правий',EncodeT5M(W));
  W[3]:=Bits12(3);W[2]:='000';
  Reject('D3 порожній замість D12',EncodeT5M(W));
  W[2]:=Bits12(3);
  W[0]:='11';Reject('D2 dotted root',EncodeT5M(W));
  W[0]:='10';W[4]:='11';
  Reject('помилкове закриття',EncodeT5M(W));
  SetLength(W,4);Reject('незакритий список',EncodeT5M(W));
  DecodeT5M(EncodeT5M(T.Words),W);
  SetLength(W,6);W[5]:='1';
  Reject('другий корінь',EncodeT5M(W));
  SetLength(W,5);
  SetLength(Wrong,6);
  for I:=0 to 3 do Wrong[I]:=W[I];
  Wrong[4]:=Bits12(1);Wrong[5]:=W[4];
  Reject('третій аргумент',EncodeT5M(Wrong));
  W[1]:='01010';W[2]:=Bits12(2047);W[3]:=Bits12(7);
  Reject('додатне D12 переповнення',EncodeT5M(W));
  W[1]:='01011';W[2]:=Bits12(-2048);W[3]:=Bits12(7);
  Reject('відємне D12 переповнення',EncodeT5M(W));
  T:=BuildTree(32,2,7);
  Reject('понад 31 D5 вузол',EncodeT5M(T.Words));
  if (Positive<>32) or (Negative<>17) then
    raise Exception.Create('помилка кількості свідків: '+IntToStr(Positive)+
      ' / '+IntToStr(Negative));
  WriteLn('ДЕРЕВО-D5-ФІЗИКА-ГАРАЗД: positive=32 negative=17');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'ДЕРЕВО-D5-ТЕСТ-ВІДМОВА: ',E.Message);
    Halt(1);
  end end;
end.
