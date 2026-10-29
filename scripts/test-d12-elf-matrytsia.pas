{ G6.68: тестовий генератор ВЖЕ ратифікованих D12 координат.
  Signed Int64 потрібні лише для тестової матриці, НЕ для SENS dispatch.
  Фізичний .sens карбує чинний codec; semantics звіряє pinned REPL.
  Питання: чому W12 не є самодостатнім D12 законом?
  Чому добуток іноді має W24?
  Чому Int64 тесту не є мовним oracle?
  Чому порівнюємо саме фізичні байти T5M? }
program test_d12_elf_matrytsia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane;

const
  LeftValues: array[0..5] of Int64 = (-2048,-1024,-1,0,1023,2047);
  RightValues: array[0..5] of Int64 = (-2048,-1,0,1,2,2047);
  D12Min = -2048;
  D12Max = 2047;

{ Явне UnicodeString→UTF8 без locale fallback у stderr FPC 3.2.2.
  Результат RawByteString належить caller до завершення WriteLn.
  1) Чому TextRec host не є SENS D7? 2) Чому тільки діагностика UTF8?
  3) Чому canonical числові .sens лишаються незмінними? }
function UA(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Save(const Path:String;const Value:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Value)>0 then F.WriteBuffer(Value[1],Length(Value));
  finally
    F.Free;
  end;
end;

function LabelOf(N:Integer):String;
begin
  Result:=IntToStr(N);
  while Length(Result)<3 do Result:='0'+Result;
end;

var
  Dir,Name:String;
  Left,Right,Sum,Product:Int64;
  I,J,Index,Width,AddCount,OverflowCount,WidenCount:Integer;
  AddAllowed:RawByteString;
begin
  { FPC 3.2.2 без явного CP_UTF8 замінює український stderr на '?'.
    Це host діагностика тесту, не перетворення фізичних слів SENS.
    1) Чому кодова сторінка stderr не є D7 доменом?
    2) Чому не змінюємо canonical .sens через налаштування тексту?
    3) Де лишаються точні бітові слова W12/W24? }
  SetTextCodePage(Output,CP_UTF8);
  SetTextCodePage(StdErr,CP_UTF8);
  if ParamCount<>1 then Halt(64);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Dir) then Halt(2);
  Index:=0;AddCount:=0;OverflowCount:=0;WidenCount:=0;
  for I:=Low(LeftValues) to High(LeftValues) do
    for J:=Low(RightValues) to High(RightValues) do begin
      Inc(Index);
      Name:=LabelOf(Index);
      Left:=LeftValues[I]; Right:=RightValues[J];
      Sum:=Left+Right; Product:=Left*Right;
      Save(Dir+Name+'-l.sens',
        EncodeNumericDecimal(RawByteString(IntToStr(Left)),12));
      Save(Dir+Name+'-r.sens',
        EncodeNumericDecimal(RawByteString(IntToStr(Right)),12));
      if (Sum>=D12Min) and (Sum<=D12Max) then begin
        Save(Dir+Name+'-add.sens',
          EncodeNumericDecimal(RawByteString(IntToStr(Sum)),12));
        AddAllowed:='так';Inc(AddCount);
      end else begin
        AddAllowed:='ні';Inc(OverflowCount);
      end;
      if (Product>=D12Min) and (Product<=D12Max) then
        Width:=12
      else begin Width:=24;Inc(WidenCount) end;
      Save(Dir+Name+'-mul.sens',
        EncodeNumericDecimal(RawByteString(IntToStr(Product)),Width));
      WriteLn(Name,#9,Left,#9,Right,#9,AddAllowed,#9,Width);
    end;
  if (Index<>36) or (AddCount=0) or (OverflowCount=0) or
     (WidenCount=0) or (Index<>AddCount+OverflowCount) then
    raise Exception.Create('тестова матриця D12 неповна');
  WriteLn(StdErr,UA('D12-МАТРИЦЯ-СВІДКИ-ГАРАЗД пар='),Index,
    UA(' сума-допущена='),AddCount,UA(' переповнень='),OverflowCount,
    UA(' широкий-добуток='),WidenCount);
end.
