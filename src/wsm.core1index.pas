{ Core1.3 — фізичний індекс визначень за точним D7.
  Механізми T5M/D2 взято з чинного FPC; єдиний мовний закон у pinned SENS.
  Індекс зберігає тільки власні біти та координати. Це НЕ evaluator.
  Діагностика host не визначає нової семантики SENS. }
unit wsm.core1index;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m;

type
  ECore1IndexError = class(Exception);

  TCore1Definition = record
    { Точна D7-послідовність, без конвертації в текстову назву. }
    NameBits: RawByteString;
    { 1-based напіввідкрита межа слів у pinned фізичній програмі. }
    StartWord, EndWordExclusive: SizeInt;
  end;

  TCore1Index = class
  private
    FWords: TExactWords;
    FEntries: array of TCore1Definition;
    FSorted: array of SizeInt;
    procedure NeedOrdinal(Ordinal:SizeInt);
    function FindExactBits(const Bits:RawByteString):SizeInt;
  public
    constructor Create(const RepoRoot:String);
    function Count:SizeInt;
    function Definition(Ordinal:SizeInt):TCore1Definition;
    function PhysicalDefinition(Ordinal:SizeInt):RawByteString;
    function PhysicalIdentifier(Ordinal:SizeInt):RawByteString;
    function FindPhysicalDefinition(const NamePhysical:RawByteString):RawByteString;
  end;

implementation
uses Classes, wsm.d2source;

const MaxCore1Definitions=256;
const MaxCore1NameGlyphs=256;

procedure Need(Condition:Boolean; const Reason:String);
begin
  if not Condition then raise ECore1IndexError.Create(Reason);
end;

function ReadPhysical(const RepoRoot:String):RawByteString;
var
  F:TFileStream;
  Filename:String;
begin
  Need(RepoRoot<>'','порожній корінь репозиторію');
  Filename:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim+'core1.sens';
  F:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MAX_T5M_FILE_BYTES),
      'неприпустимий розмір фізичного Core1');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally
    F.Free;
  end;
end;

function ExactNameBits(N:TD2Node):RawByteString;
var I:SizeInt;
begin
  Need((N<>nil) and (N.Kind=dkList) and
       (Length(N.Children)>0) and
       (Length(N.Children)<=MaxCore1NameGlyphs),
       'ідентифікатор Core1 має бути непорожнім D7-списком');
  Result:='';
  for I:=0 to High(N.Children) do begin
    Need((N.Children[I]<>nil) and
      (N.Children[I].Kind=dkIdentity) and
      (N.Children[I].Width=7) and
      (Length(N.Children[I].Bits)=7),
      'точний D7-ідентифікатор пошкоджено');
    Result:=Result+N.Children[I].Bits;
  end;
end;

function ExactDefinition(N:TD2Node):TCore1Definition;
begin
  Need((N<>nil) and (N.Kind=dkList) and
       (Length(N.Children)=3),
       'фізична форма Core1 не є тричленним DEFINE');
  Need((N.Children[0]<>nil) and
       (N.Children[0].Kind=dkIdentity) and
       (N.Children[0].Width=4) and
       (N.Children[0].Bits='0011'),
       'фізичний Core1 має визначення поза D4:0011');
  Need(N.Children[2]<>nil,'відсутнє тіло визначення Core1');
  Result.NameBits:=ExactNameBits(N.Children[1]);
  Result.StartWord:=N.WordIndex;
  Result.EndWordExclusive:=N.EndWordIndexExclusive;
  Need((Result.StartWord>=1) and
       (Result.EndWordExclusive>Result.StartWord),
       'пошкоджена фізична межа визначення');
end;

constructor TCore1Index.Create(const RepoRoot:String);
var
  Physical:RawByteString;
  Doc:TD2Document;
  I,J,Wanted:SizeInt;
begin
  inherited Create;
  Doc:=nil;
  try
    Physical:=ReadPhysical(RepoRoot);
    DecodeT5M(Physical,FWords);
    Need(EncodeT5M(FWords)=Physical,
      'фізичний файл не є канонічним T5M');
    Doc:=ParseD2WordsWide(FWords);
    Need((Length(Doc.Roots)>=1) and
      (Length(Doc.Roots)<=MaxCore1Definitions),
      'кількість визначень Core1 перевищує фізичний бюджет');
    SetLength(FEntries,Length(Doc.Roots));
    SetLength(FSorted,Length(Doc.Roots));
    for I:=0 to High(Doc.Roots) do begin
      FEntries[I]:=ExactDefinition(Doc.Roots[I]);
      Need(FEntries[I].EndWordExclusive-1<=Length(FWords),
        'визначення посилається поза фізичні слова');
      FSorted[I]:=I;
    end;
    { Кількість визначень обмежено 256; insertion-sort лише для
      порівняння бітових ключів. Ні ім'я, ні домен не виводиться з числа. }
    for I:=1 to High(FSorted) do begin
      Wanted:=FSorted[I];
      J:=I;
      while (J>0) and
        (FEntries[FSorted[J-1]].NameBits>FEntries[Wanted].NameBits) do begin
        FSorted[J]:=FSorted[J-1];
        Dec(J);
      end;
      FSorted[J]:=Wanted;
    end;
    for I:=1 to High(FSorted) do
      Need(FEntries[FSorted[I-1]].NameBits<>
        FEntries[FSorted[I]].NameBits,
        'два визначення Core1 мають однакове точне D7-ім’я');
  finally
    Doc.Free;
  end;
end;

function TCore1Index.Count:SizeInt;
begin
  Result:=Length(FEntries);
end;

procedure TCore1Index.NeedOrdinal(Ordinal:SizeInt);
begin
  Need((Ordinal>=1) and (Ordinal<=Count),
    'порядковий номер визначення Core1 поза межею');
end;

function TCore1Index.Definition(Ordinal:SizeInt):TCore1Definition;
begin
  NeedOrdinal(Ordinal);
  Result:=FEntries[Ordinal-1];
end;

function TCore1Index.PhysicalDefinition(Ordinal:SizeInt):RawByteString;
var
  Span:TCore1Definition;
  Part:TExactWords;
  I:SizeInt;
begin
  Span:=Definition(Ordinal);
  SetLength(Part,Span.EndWordExclusive-Span.StartWord);
  for I:=0 to High(Part) do
    Part[I]:=FWords[Span.StartWord-1+I];
  { Перепаковуємо в ОКРЕМУ canonical T5M форму: byte-aligned
    зріз оригіналу тут заборонений, бо межі слів тритові. }
  Result:=EncodeT5M(Part);
end;

function TCore1Index.PhysicalIdentifier(Ordinal:SizeInt):RawByteString;
var
  NameBits:RawByteString;
  Part:TExactWords;
  I,CountGlyphs:SizeInt;
begin
  NameBits:=Definition(Ordinal).NameBits;
  CountGlyphs:=Length(NameBits) div 7;
  SetLength(Part,CountGlyphs+2);
  Part[0]:='10';
  for I:=0 to CountGlyphs-1 do
    Part[I+1]:=Copy(NameBits,I*7+1,7);
  Part[High(Part)]:='01';
  Result:=EncodeT5M(Part);
end;

function TCore1Index.FindExactBits(const Bits:RawByteString):SizeInt;
var Left,Right,Middle,CompareTo:SizeInt;
begin
  Left:=0;
  Right:=Length(FSorted);
  while Left<Right do begin
    Middle:=Left+(Right-Left) div 2;
    CompareTo:=FSorted[Middle];
    if FEntries[CompareTo].NameBits<Bits then
      Left:=Middle+1
    else
      Right:=Middle;
  end;
  if (Left<Length(FSorted)) and
    (FEntries[FSorted[Left]].NameBits=Bits) then
    Exit(FSorted[Left]+1);
  raise ECore1IndexError.Create('невідоме точне D7-ім’я у pinned Core1');
end;

function TCore1Index.FindPhysicalDefinition(
  const NamePhysical:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Exact:RawByteString;
begin
  Need((Length(NamePhysical)>0) and
       (Length(NamePhysical)<=MAX_T5M_FILE_BYTES),
       'недопустимий розмір фізичного D7-ключа');
  Doc:=ReadD2T5MWide(NamePhysical);
  try
    Need(Length(Doc.Roots)=1,'фізичний ключ має рівно один D2-корінь');
    Exact:=ExactNameBits(Doc.Roots[0]);
    Result:=PhysicalDefinition(FindExactBits(Exact));
  finally
    Doc.Free;
  end;
end;

end.
