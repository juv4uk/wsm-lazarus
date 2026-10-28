{ G1.8: оборотна звичайна українська .lisp-проєкція фізичного .sens.
  Закон і написання беруться ЛИШЕ з pinned SENS таблиць.
  Немає жодних доменних міток у тексті, немає семантичного dispatch.
  Невідновлювані координати (D3:000, явний D2 00, D2 11)
  відхиляються, а не стираються. Це обмежений піднабір, НЕ повний
  канонічний текстовий формат і не SENS REPL. }
unit wsm.ukroundtrip;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.bind;
type
  EUkRoundtripError=class(Exception);
  { Для кожного точного бінарного ключа з pinned table:
    звичайне ПОВНЕ українське поле «укр», а не коротке «ук». }
  TLongProjection=array[1..9] of array of RawByteString;
procedure LoadPinnedLongProjection(const Root:RawByteString;
  const Tables:TDomainSet; out Longs:TLongProjection);
function PhysicalToUkrainian(const Physical:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
function UkrainianToPhysical(const Ukrainian:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
implementation
uses Classes, wsm.t5m, wsm.d2source, wsm.source, wsm.domain,
  wsm.binarybind;

const MaxProjectionBytes=1024*1024;
      MaxProjectionWords=32768;

procedure Require(Condition:Boolean; const Explanation:String);
begin
  if not Condition then raise EUkRoundtripError.Create(Explanation);
end;

function SafeAtom(const Surface:RawByteString):Boolean;
var I:SizeInt; C:AnsiChar;
begin
  Result:=False;
  if Surface='' then Exit;
  { Поверхня повинна бути одним атомом чинного reader, а не
    синтаксисом дужок, рядком, коментарем, пробілом чи крапкою. }
  if Surface='.' then Exit;
  for I:=1 to Length(Surface) do begin
    C:=Surface[I];
    if (C in [#0..#32,'(',')',';','"']) then Exit;
  end;
  Result:=True;
end;

procedure AddWord(var Words:TExactWords; const Bits:RawByteString);
var L:SizeInt;
begin
  L:=Length(Words);
  if L>=MaxProjectionWords then
    raise EUkRoundtripError.Create('Перевищено межу слів української проєкції');
  SetLength(Words,L+1);
  Words[L]:=Bits;
end;

procedure LoadPinnedLongProjection(const Root:RawByteString;
  const Tables:TDomainSet; out Longs:TLongProjection);
var
  D, I, P, E, EndBits, AtUkr, EndUkr, Count:SizeInt;
  Path, Data, Line, Bits, Name:RawByteString;
  Stream:TFileStream;
  Seen:array of Boolean;
  K:TDomainKey;
  Row:TDomainRow;
begin
  for D:=1 to 9 do begin
    Require(Length(Tables[D])=(SizeInt(1) shl D),
      'Потрібна повна pinned таблиця точного домену');
    SetLength(Longs[D],Length(Tables[D]));
    SetLength(Seen,Length(Tables[D]));
    for I:=0 to High(Seen) do Seen[I]:=False;
    Path:=IncludeTrailingPathDelimiter(String(Root))+
      'lib/domains/d'+IntToStr(D)+'.lisp';
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      Require((Stream.Size>0) and (Stream.Size<=1024*1024),
        'Порожня або завелика pinned таблиця проєкцій');
      SetLength(Data,SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[1],Length(Data));
    finally Stream.Free; end;

    Count:=0; P:=1;
    while P<=Length(Data) do begin
      E:=P;
      while (E<=Length(Data)) and (Data[E]<>#10) do Inc(E);
      Line:=Trim(Copy(Data,P,E-P));
      P:=E+1;
      if (Length(Line)<4) or (Line[1]<>'(') or
         not (Line[2] in ['0','1']) then Continue;
      EndBits:=2;
      while (EndBits<=Length(Line)) and
        (Line[EndBits] in ['0','1']) do Inc(EndBits);
      Require((EndBits<=Length(Line)) and (Line[EndBits]=' '),
        'Некоректний pinned рядок із двійковим ключем');
      Bits:=Copy(Line,2,EndBits-2);
      K:=ExactKey(Bits);
      Require(K.Width=D,'Невірна ширина домену у pinned укр');
      Require(DomainRowByKey(Tables[D],K,Row),
        'Доменний ключ укр відсутній у pinned таблиці');
      Require(not Seen[K.Bits],'Повторна адреса у pinned укр');
      { Точні байти UTF-8 з pinned таблиці: у-к-р, без implicit
        UnicodeString/RawByteString codepage перетворення. }
      AtUkr:=Pos(#$28#$D1#$83#$D0#$BA#$D1#$80#$20,Line);
      Require(AtUkr>0,'Відсутнє pinned поле укр у D'+IntToStr(D)+
        ': '+Bits);
      AtUkr:=AtUkr+8;
      { Значення () у pinned джерелі означає відсутню поверхню. }
      if Copy(Line,AtUkr,2)='()' then Name:=''
      else begin
        EndUkr:=AtUkr;
        while (EndUkr<=Length(Line)) and
          (Line[EndUkr]<>')') do Inc(EndUkr);
        Require(EndUkr<=Length(Line),'Незавершене pinned поле укр');
        Name:=Copy(Line,AtUkr,EndUkr-AtUkr);
      end;
      Longs[D][K.Bits]:=Name;
      Seen[K.Bits]:=True;
      Inc(Count);
    end;
    Require(Count=Length(Seen),'Неповна pinned таблиця укр');
  end;
end;

function LongUkrainianKey(const Tables:TDomainSet;
  const Longs:TLongProjection; const Name:RawByteString):TDomainKey;
var D,I:SizeInt; Found:Boolean;
begin
  Require(Name<>'','Порожня українська назва');
  Found:=False;
  for D:=1 to 9 do begin
    Require(Length(Longs[D])=Length(Tables[D]),
      'Неініціалізована pinned проєкція укр');
    for I:=0 to High(Longs[D]) do
      if (Longs[D][I]<>'') and (Longs[D][I]=Name) then begin
        Require(not Found,'Неоднозначна українська укр назва між доменами');
        Result:=Tables[D][I].Key;
        Found:=True;
      end;
  end;
  Require(Found,'Невідома українська укр назва');
end;

function PackCore(const Ukrainian:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
var Source:TSourceDocument; Words:TExactWords; I:SizeInt;
  procedure Visit(const Node:TSourceNode; Depth:SizeInt);
  var K:TDomainKey; J:SizeInt;
  begin
    Require(Node<>nil,'Відсутня текстова форма');
    Require(Depth<=MaxD2SyntaxDepth,'Надмірна вкладеність української проєкції');
    case Node.Kind of
      skList: begin
        AddWord(Words,'10');
        for J:=0 to High(Node.Children) do Visit(Node.Children[J],Depth+1);
        AddWord(Words,'01');
      end;
      skAtom: begin
        Require(SafeAtom(Node.Text),'Неприпустимий атом української проєкції');
        { BindUkrainian гарантує унікальність ТОЧНОЇ назви між доменами.
          Жоден spelling не наділяється викличністю/значенням. }
        K:=LongUkrainianKey(Tables,Longs,Node.Text);
        Require((K.Width<>2) and (K.Width<=9),
          'Структурні двійкові слова не є текстовими атомами');
        Require(not ((K.Width=3) and (KeyBits(K)='000')),
          'D3:000 не має оборотної звичайної текстової назви');
        AddWord(Words,KeyBits(K));
      end;
      skString: raise EUkRoundtripError.Create(
        'Текстові рядки не підтримані точним двійковим пакуванням');
      else raise EUkRoundtripError.Create('Невідома текстова форма');
    end;
  end;
begin
  Result:='';
  Require(Length(Ukrainian)>0,'Порожня українська проєкція');
  Source:=ReadUkrainianSource(Ukrainian);
  try
    Require(Length(Source.Forms)>0,'Український файл не містить форм');
    SetLength(Words,0);
    for I:=0 to High(Source.Forms) do Visit(Source.Forms[I],0);
    { Єдиний наявний фізичний кодер; не створюємо власний T5M. }
    Result:=EncodeT5M(Words);
  finally
    Source.Free;
  end;
end;

function ProjectCore(const Physical:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
var
  Words:TExactWords;
  Document:TD2Document;
  Bound:TBinaryWords;
  Stream:TMemoryStream;
  I, J:SizeInt;

  procedure Put(const S:RawByteString);
  begin
    if Length(S)>MaxProjectionBytes-Stream.Size then
      raise EUkRoundtripError.Create('Перевищено межу байтів української проєкції');
    if Length(S)>0 then Stream.WriteBuffer(S[1],Length(S));
  end;

  procedure Visit(const Node:TD2Node; Depth:SizeInt);
  var
    K:TDomainKey; Row:TDomainRow; Verify:TDomainKey;
    Name:RawByteString; C:SizeInt;
  begin
    Require(Node<>nil,'Відсутній фізичний вузол');
    Require(Depth<=MaxD2SyntaxDepth,'Надмірна фізична вкладеність');
    case Node.Kind of
      dkList: begin
        Put('(');
        for C:=0 to High(Node.Children) do begin
          if C>0 then Put(' ');
          Visit(Node.Children[C],Depth+1);
        end;
        Put(')');
      end;
      dkIdentity: begin
        K:=ExactKey(Node.Bits);
        Require((K.Width=Node.Width) and (K.Width<>2) and
          (K.Width<=9),'Втрачено точну фізичну ширину');
        Require(DomainRowByKey(Tables[K.Width],K,Row),
          'Немає точної координати в закріпленій таблиці');
        Name:=Longs[K.Width][K.Bits];
        Require(SafeAtom(Name),
          'Відсутня або синтаксично неоднозначна повна українська назва');
        { Використовуємо «укр», а не скорочену «ук».
          Її точна однозначність перевірена проти усіх доменів. }
        Verify:=LongUkrainianKey(Tables,Longs,Name);
        Require(SameKey(K,Verify),
          'Неоднозначна українська проєкція фізичного слова');
        Put(Name);
      end;
      dkEmpty: raise EUkRoundtripError.Create(
        'Фізичне D3:000 і порожній D2-список мають неоднозначне ()');
      dkPair: raise EUkRoundtripError.Create(
        'Крапкова D2-пара не підтримана оборотною проєкцією');
      else raise EUkRoundtripError.Create('Невідомий фізичний вузол');
    end;
  end;
begin
  Result:='';
  Require((Length(Physical)>0) and
    (Length(Physical)<=MAX_T5M_FILE_BYTES),'Порожній чи завеликий фізичний .sens');
  DecodeT5M(Physical,Words);
  Require(EncodeT5M(Words)=Physical,
    'Неканонічне фізичне пакування T5M');
  Require(Length(Words)<=MaxProjectionWords,
    'Перевищено межу фізичних слів у проєкції');
  for I:=0 to High(Words) do begin
    Require(Words[I]<>'00',
      'Явний D2 пропуск 00 неможливо оборотно відновити з пробілів');
    Require(Words[I]<>'11',
      'Крапкова пара D2 не підтримана оборотною проєкцією');
  end;
  Document:=ParseD2Words(Words);
  try
    { Чинний pinned exact-domain binder допущено ПЕРЕД виводом. }
    BindD2Binary(Document,Tables,Bound);
    Stream:=TMemoryStream.Create;
    try
      for J:=0 to High(Document.Roots) do begin
        Visit(Document.Roots[J],0);
        Put(#10);
      end;
      Require(Stream.Size>0,'Немає фізичних форм для проєкції');
      SetLength(Result,SizeInt(Stream.Size));
      Stream.Position:=0;
      Stream.ReadBuffer(Result[1],Length(Result));
    finally Stream.Free; end;
  finally Document.Free; end;
end;

function PhysicalToUkrainian(const Physical:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
var Repacked:RawByteString;
begin
  Result:='';
  try
    Result:=ProjectCore(Physical,Tables,Longs);
    Repacked:=PackCore(Result,Tables,Longs);
    Require(Repacked=Physical,'Втрачено фізичні байти під час round-trip');
  except
    on E:EUkRoundtripError do raise;
    on E:Exception do raise EUkRoundtripError.Create(E.Message);
  end;
end;

function UkrainianToPhysical(const Ukrainian:RawByteString;
  const Tables:TDomainSet; const Longs:TLongProjection):RawByteString;
var Projected:RawByteString;
begin
  Result:='';
  try
    Result:=PackCore(Ukrainian,Tables,Longs);
    Projected:=ProjectCore(Result,Tables,Longs);
    Require(PackCore(Projected,Tables,Longs)=Result,
      'Українська проєкція не відтворила точні фізичні байти');
  except
    on E:EUkRoundtripError do raise;
    on E:Exception do raise EUkRoundtripError.Create(E.Message);
  end;
end;

end.
