{ G6.82 — checked FPC fixture/test generator для машинного D6:001111.
  Порівняння з SENS REPL і реальний запуск ELF виконує shell gate. }
program test_ird6sub1;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.ird6sub1,wsm.numericplane,
     wsm.numericsub;
const Values:array[0..7] of Integer=(1,2,3,7,15,127,1024,2047);
var Directory:String; Counter:SizeInt;

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
function PhysicalForm(const OperatorBits,ValueBits:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,4);
  Words[0]:='10'; Words[1]:=OperatorBits;
  Words[2]:=ValueBits; Words[3]:='01';
  Result:=EncodeT5M(Words);
end;
function SingleAtom(const Bits:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1); Words[0]:=Bits; Result:=EncodeT5M(Words);
end;
procedure Save(const Path:String; const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const LabelText:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try
    Image:=BuildD6Sub1ELF(Physical,'external/sens');
  except
    on E:Exception do begin Inc(Counter); Exit end;
  end;
  raise Exception.Create('неочікуване прийняття: '+LabelText+
    ', ELF байтів='+IntToStr(Length(Image)));
end;
procedure Run;
var I,V:Integer; Source,Image,Expected:RawByteString;
    Words:TExactWords;
begin
  if ParamCount<>1 then raise Exception.Create('потрібна тека доказів');
  Directory:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Directory) then
    raise Exception.Create('не створено каталог доказів');
  Counter:=0;
  for I:=Low(Values) to High(Values) do begin
    V:=Values[I];
    Source:=PhysicalForm('001111',Bits12(V));
    Image:=BuildD6Sub1ELF(Source,'external/sens');
    Expected:=SubtractNumericPhysical(SingleAtom(Bits12(V)),
                                      SingleAtom(Bits12(1)),12);
    Save(Directory+IntToStr(V)+'.sens',Source);
    Save(Directory+IntToStr(V)+'.elf',Image);
    Save(Directory+IntToStr(V)+'.expected.sens',Expected);
    { Усі 8 результатів і машинні ELF перевіряє окремий shell/REPL. }
  end;
  Reject('помилкова D6 адреса',
         PhysicalForm('001110',Bits12(3)));
  Reject('підміна D1',
         PhysicalForm('001111','1'));
  Reject('підміна D7',
         PhysicalForm('001111','0000001'));
  Reject('підміна D24',
         PhysicalForm('001111',StringOfChar('0',23)+'1'));
  Reject('нуль поза CPU профілем',
         PhysicalForm('001111',Bits12(0)));
  Reject('від’ємне поза CPU профілем',
         PhysicalForm('001111',Bits12(-1)));
  Reject('нижня D12 межа',
         PhysicalForm('001111',Bits12(-2048)));
  Reject('пошкоджений T5M',#$FF);
  SetLength(Words,3); Words[0]:='10'; Words[1]:='001111';
  Words[2]:=Bits12(3);
  Reject('відсутня D2 дужка',EncodeT5M(Words));
  SetLength(Words,5); Words[0]:='10'; Words[1]:='001111';
  Words[2]:=Bits12(3);Words[3]:='01';Words[4]:='0';
  Reject('сторонній другий корінь',EncodeT5M(Words));
  if Counter<>10 then raise Exception.Create('не виконано всі негативи');
  WriteLn('D6-ВІДНЯТИ-1-UNIT-ГАРАЗД позитивів=8 негативів=',Counter);
end;
begin
  try Run
  except on E:Exception do begin WriteLn(StdErr,E.Message);Halt(1) end end;
end.
