{ G2.52 — перевірна людська проєкція ФІЗИЧНИХ Core1 D7-ідентифікаторів.
  Закони і шість проєкцій — тільки pinned external/sens.
  Ця утиліта НЕ виконує DEFINE і не тлумачить текст як dispatch. }
program senscore1imena;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii, wsm.core1index;

type ECore1NamesError = class(Exception);

procedure Need(Condition:Boolean; const Reason:String);
begin
  if not Condition then raise ECore1NamesError.Create(Reason);
end;

{ Surface: borrowed UTF-8 клітинка вже допущеного D7-каталогу.
  Повертає власний RawByteString символу; лапки в таблиці — лише
  синтаксис проєкції. Дозволено тільки ратифіковані escape " і \.
  Пам'ять managed, без прив'язки до lifetime індексу Core1. }
function ProjectGlyph(const Surface:RawByteString):RawByteString;
var P:SizeInt; C:Char;
begin
  Need(Surface<>'','фізичний D7-ключ містить недруковану координату');
  if Surface[1]<>'"' then
    Result:=Surface
  else begin
    Need((Length(Surface)>=2) and (Surface[Length(Surface)]='"'),
      'некоректний quoted D7-символ');
    Result:='';
    P:=2;
    while P<Length(Surface) do begin
      C:=Surface[P];
      if C='\' then begin
        Inc(P);
        Need(P<Length(Surface),'обірвана escape-послідовність D7');
        C:=Surface[P];
        Need((C='"') or (C='\'),'невідома escape-послідовність D7');
      end;
      Result:=Result+C;
      Inc(P);
    end;
  end;
  Need((Result<>'') and (Pos(#10,Result)=0) and
       (Pos(#13,Result)=0) and (Pos(#9,Result)=0) and
       (Result<>' '),'D7-символ не придатний для імені');
end;

{ NameBits: власна послідовність рівно 7-бітних D7-слів з
  TCore1Index.Definition, НЕ десятковий індекс та НЕ текстовий ключ.
  Catalog: borrowed ратифіковані шість колонок, тут тільки укр.
  Результат: новий UTF-8 RawByteString, без зміни канонічних бітів.
  Невідомий/недрукований ключ відхиляється до stdout. }
function FullName(const NameBits:RawByteString;
  const Catalog:TProektsiiCatalog):RawByteString;
var P:SizeInt; K:TDomainKey; R:TProektsiiaRow;
begin
  Need((Length(NameBits)>0) and (Length(NameBits) mod 7=0),
    'некоректна довжина фізичного D7-ідентифікатора');
  Result:='';
  P:=1;
  while P<=Length(NameBits) do begin
    K:=ExactKey(Copy(NameBits,P,7));
    Need((K.Width=7) and (K.Bits<QWord(Length(Catalog[7]))),
      'фізична координата не належить D7');
    R:=Catalog[7][K.Bits];
    Need(SameKey(K,R.Key),'не збігся exact ключ pinned D7');
    Result:=Result+ProjectGlyph(R.Surface[1]);
    Inc(P,7);
  end;
end;

{ Index володіє розпакованим T5M/D2 та exact D7-бітами; Names і Seen
  володіють лише host-рядками до кінця Run. Спочатку перевіряємо
  ВСІ імена і колізії, тоді атомарно публікуємо stdout. }
procedure Run;
var Index:TCore1Index; Catalog:TProektsiiCatalog;
    Names,Seen:TStringList; I:SizeInt; Name:RawByteString;
    Root:String;
begin
  Need(ParamCount=1,'використання: senscore1imena КОРІНЬ-РЕПОЗИТОРІЮ');
  Root:=ParamStr(1);
  Index:=TCore1Index.Create(Root);
  try
    LoadPinnedProjections(
      IncludeTrailingPathDelimiter(Root)+'external/sens',Catalog);
    Names:=TStringList.Create;
    Seen:=TStringList.Create;
    try
      Seen.CaseSensitive:=True;
      for I:=1 to Index.Count do begin
        Name:=FullName(Index.Definition(I).NameBits,Catalog);
        Need(Seen.IndexOf(String(Name))<0,
          'колізія повного імені у pinned укр-проєкції');
        Seen.Add(String(Name));
        Names.Add(String(Name));
      end;
      Need((Names.Count=Index.Count) and (Names.Count>0),
        'пошкоджений список фізичних імен');
      for I:=0 to Names.Count-1 do WriteLn(Names[I]);
    finally
      Seen.Free;
      Names.Free;
    end;
  finally
    Index.Free;
  end;
end;

begin
  try
    Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'CORE1-ФІЗИЧНІ-ІМЕНА-ВІДМОВА: ',E.Message);
      Halt(2);
    end;
  end;
end.
