{ Фізичний огляд .sens: лише механізм T5M/D2, жодного виконання SENS.
  Усі слова, трити та байти одержано з наявного reader juv4uk/sens. }
unit wsm.oglyadmodel;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.d2source;

const
  MaxOghliadBytes = 1024*1024;
  MaxOghliadWords = 5000;

type
  EOghliadError = class(Exception);
  TOghliadWord = record
    Index, Width: SizeInt;
    Bits, Kind: RawByteString;
    TritStart, TritEnd, ByteStart, ByteEnd: SizeInt;
  end;
  TOghliadWords = array of TOghliadWord;

  TOghliadModel = class
  private
    FPhysical: RawByteString;
    FWords: TOghliadWords;
    FRoots: SizeInt;
  public
    procedure LoadBytes(const Physical: RawByteString);
    procedure LoadFile(const Path: String);
    function WordAt(Index: SizeInt): TOghliadWord; { 0-based UI row }
    function HexAt(Index: SizeInt): RawByteString;
    function WordCount: SizeInt;
    function RootCount: SizeInt;
    function ByteCount: SizeInt;
  end;

implementation

procedure TOghliadModel.LoadBytes(const Physical: RawByteString);
var
  Doc: TD2Document;
  Spans: TPhysicalWordSpans;
  Words: TExactWords;
  Next: TOghliadWords;
  I: SizeInt;
begin
  if (Length(Physical)=0) or (Length(Physical)>MaxOghliadBytes) then
    raise EOghliadError.Create('Фізичний файл порожній або перевищує 1 МіБ');
  { Усі збої залишають попередню модель недоторканою. }
  Doc := nil;
  try
    Doc := ReadD2WithPhysicalLocations(Physical,Spans);
    DecodeT5M(Physical,Words);
    if (Length(Words)>MaxOghliadWords) then
      raise EOghliadError.Create('Для візуалізації дозволено до 5000 слів');
    if Length(Words)<>Length(Spans) then
      raise EOghliadError.Create('Порушено відповідність фізичних позицій');
    SetLength(Next,Length(Words));
    for I:=0 to High(Words) do begin
      Next[I].Index := I+1;
      Next[I].Width := Length(Words[I]);
      Next[I].Bits := Words[I];
      Next[I].TritStart := Spans[I].TritStart;
      Next[I].TritEnd := Spans[I].TritEnd;
      Next[I].ByteStart := Spans[I].ByteStart;
      Next[I].ByteEnd := Spans[I].ByteEnd;
      if Next[I].Width=2 then begin
        if Words[I]='10' then Next[I].Kind:='D2: відкрити'
        else if Words[I]='01' then Next[I].Kind:='D2: закрити'
        else if Words[I]='00' then Next[I].Kind:='D2: розділити'
        else Next[I].Kind:='D2: крапка';
      end else if Words[I]='000' then
        Next[I].Kind:='D3: порожня структура'
      else
        Next[I].Kind:='Двійкове слово (без тлумачення)';
    end;
    { Публікувати лише після всіх перевірок і цілого D2 AST. }
    FPhysical:=Physical;
    FWords:=Next;
    FRoots:=Length(Doc.Roots);
  finally
    Doc.Free;
  end;
end;

procedure TOghliadModel.LoadFile(const Path:String);
var F:TFileStream; Physical:RawByteString;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxOghliadBytes) then
      raise EOghliadError.Create('Фізичний файл порожній або перевищує 1 МіБ');
    SetLength(Physical,SizeInt(F.Size));
    F.ReadBuffer(Physical[1],Length(Physical));
  finally
    F.Free;
  end;
  LoadBytes(Physical);
end;

function TOghliadModel.WordAt(Index:SizeInt):TOghliadWord;
begin
  if (Index<0) or (Index>=Length(FWords)) then
    raise EOghliadError.Create('Індекс слова поза межами документа');
  Result:=FWords[Index];
end;

function TOghliadModel.HexAt(Index:SizeInt):RawByteString;
var R:TOghliadWord; I:SizeInt;
begin
  R:=WordAt(Index);
  Result:='';
  for I:=R.ByteStart to R.ByteEnd-1 do begin
    if Result<>'' then Result:=Result+' ';
    Result:=Result+RawByteString(IntToHex(Ord(FPhysical[I+1]),2));
  end;
end;

function TOghliadModel.WordCount:SizeInt;
begin Result:=Length(FWords); end;
function TOghliadModel.RootCount:SizeInt;
begin Result:=FRoots; end;
function TOghliadModel.ByteCount:SizeInt;
begin Result:=Length(FPhysical); end;
end.
