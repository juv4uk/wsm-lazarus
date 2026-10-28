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
type EUkRoundtripError=class(Exception);
function PhysicalToUkrainian(const Physical:RawByteString;
  const Tables:TDomainSet):RawByteString;
function UkrainianToPhysical(const Ukrainian:RawByteString;
  const Tables:TDomainSet):RawByteString;
implementation
uses Classes, wsm.t5m, wsm.d2source, wsm.source, wsm.domain;

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
    if (C in [' ',#0..#32,'(',')',';','"']) then Exit;
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

function PackCore(const Ukrainian:RawByteString;
  const Tables:TDomainSet):RawByteString;
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
        K:=BindUkrainian(Tables,Node.Text);
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
  const Tables:TDomainSet):RawByteString;
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
    C:SizeInt;
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
        Require(SafeAtom(Row.Ukrainian),
          'Відсутня або синтаксично неоднозначна українська назва');
        { Перевіряємо, що ця назва НЕ збігається з іншою фізичною
          координатою в pinned таблицях. Інакше жодного round-trip. }
        Verify:=BindUkrainian(Tables,Row.Ukrainian);
        Require(SameKey(K,Verify),
          'Неоднозначна українська проєкція фізичного слова');
        Put(Row.Ukrainian);
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
  const Tables:TDomainSet):RawByteString;
var Repacked:RawByteString;
begin
  Result:='';
  try
    Result:=ProjectCore(Physical,Tables);
    Repacked:=PackCore(Result,Tables);
    Require(Repacked=Physical,'Втрачено фізичні байти під час round-trip');
  except
    on E:EUkRoundtripError do raise;
    on E:Exception do raise EUkRoundtripError.Create(E.Message);
  end;
end;

function UkrainianToPhysical(const Ukrainian:RawByteString;
  const Tables:TDomainSet):RawByteString;
var Projected:RawByteString;
begin
  Result:='';
  try
    Result:=PackCore(Ukrainian,Tables);
    Projected:=ProjectCore(Result,Tables);
    Require(PackCore(Projected,Tables)=Result,
      'Українська проєкція не відтворила точні фізичні байти');
  except
    on E:EUkRoundtripError do raise;
    on E:Exception do raise EUkRoundtripError.Create(E.Message);
  end;
end;

end.
