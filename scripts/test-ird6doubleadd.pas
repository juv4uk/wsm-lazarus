{ G6.90 — згенерувати фізичні golden inputs, expected output
  і 12 реальних машинних ELF; 12 fail-closed випадків. }
program test_ird6doubleadd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
     wsm.ird6doubleadd;
const Values:array[0..11] of Integer=
  (-2048,-2000,-5,-2,-1,0,1,2,127,512,1024,2045);
var Directory:String;Rejected:SizeInt;

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
function Form(const OuterBits,InnerBits,AtomBits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,7);
  W[0]:='10';W[1]:=OuterBits;W[2]:='10';
  W[3]:=InnerBits;W[4]:=AtomBits;W[5]:='01';W[6]:='01';
  Result:=EncodeT5M(W);
end;
function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W);
end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const Name:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try
    Image:=BuildIRDoubleAddELF(Physical,'external/sens');
  except
    on E:Exception do begin Inc(Rejected);Exit end;
  end;
  raise Exception.Create('прийнято негатив '+Name+
    ' ELF='+IntToStr(Length(Image)));
end;
procedure Run;
var I,V:Integer;Source,Image,Expected,One:RawByteString;W:TExactWords;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог доказів');
  Directory:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Directory) then
    raise Exception.Create('не створено каталог');
  Rejected:=0;
  One:=EncodeNumericDecimal('1',12);
  for I:=Low(Values) to High(Values) do begin
    V:=Values[I];
    Source:=Form('001110','001110',Bits12(V));
    Image:=BuildIRDoubleAddELF(Source,'external/sens');
    Expected:=AddNumericPhysical(Atom(Bits12(V)),One,12);
    Expected:=AddNumericPhysical(Expected,One,12);
    Save(Directory+IntToStr(I)+'.sens',Source);
    Save(Directory+IntToStr(I)+'.elf',Image);
    Save(Directory+IntToStr(I)+'.expected.sens',Expected);
  end;
  Reject('інша зовнішня функція',
    Form('001111','001110',Bits12(1)));
  Reject('інша внутрішня функція',
    Form('001110','001111',Bits12(1)));
  Reject('голова D5',
    Form('01010','001110',Bits12(1)));
  Reject('атом D1',
    Form('001110','001110','1'));
  Reject('атом D7',
    Form('001110','001110','0000001'));
  Reject('атом D24',
    Form('001110','001110',StringOfChar('0',23)+'1'));
  Reject('переповнення друге',Form('001110','001110',Bits12(2046)));
  Reject('переповнення перше',Form('001110','001110',Bits12(2047)));
  Reject('пошкоджений T5M',#$FF);
  SetLength(W,6);
  W[0]:='10';W[1]:='001110';W[2]:='10';W[3]:='001110';
  W[4]:=Bits12(1);W[5]:='01';
  Reject('незакритий зовнішній список',EncodeT5M(W));
  SetLength(W,8);
  W[0]:='10';W[1]:='001110';W[2]:='10';W[3]:='001110';
  W[4]:=Bits12(1);W[5]:='01';W[6]:='01';W[7]:='1';
  Reject('другий корінь',EncodeT5M(W));
  W[6]:=Bits12(1);W[7]:='01';
  Reject('другий аргумент',EncodeT5M(W));
  if Rejected<>12 then
    raise Exception.Create('не всі негативи перевірено');
  WriteLn('D6-DOUBLE-UNIT-OK positive=12 negative=',Rejected);
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'D6-DOUBLE-UNIT-FAIL: ',E.Message);
    Halt(1)
  end end;
end.
