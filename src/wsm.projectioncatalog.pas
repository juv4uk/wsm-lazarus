{ G2.26: шість pinned поверхонь для кожної ТОЧНОЇ координати D1-D10.
  Дані, а не dispatch. Ніяких власних законів, функцій чи чисел D12+.
  Структура читається перевіреним wsm.source, зокрема quote-aware D7. }
unit wsm.projectioncatalog;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
const ProjectionColumns=6;
type
  EProjectionCatalogError=class(Exception);
  TProjectionSurface=(psUk,psUkr,psSan,psEn,psLisp,psSym);
  TProjectionRow=record
    Bits:RawByteString; { точна ширина Дn, не host integer }
    Names:array[TProjectionSurface] of RawByteString;
  end;
  TProjectionRows=array of TProjectionRow;
  TProjectionCatalog=array[1..10] of TProjectionRows;
function ParseProjectionTable(const Source:RawByteString;Width:Byte):TProjectionRows;
function LoadProjectionTable(const RepoRoot:String;Width:Byte):TProjectionRows;
procedure LoadProjectionCatalog(const RepoRoot:String;out Catalog:TProjectionCatalog);
function ProjectionColumnName(Column:TProjectionSurface):RawByteString;
implementation
uses Classes,wsm.source;
const NameOrder:array[TProjectionSurface] of RawByteString=
  ('ук','укр','san','en','LISP','sym');

procedure Reject(const Why:String);
begin raise EProjectionCatalogError.Create('відхилено pinned-проєкції: '+Why) end;

function ProjectionColumnName(Column:TProjectionSurface):RawByteString;
begin Result:=NameOrder[Column] end;

{ Відсутність поверхні = структурне (), не рядок "()" і не D3:000.
  У quoted рядках підтримуємо тільки два реально необхідні escapes:
  \" та \\, жодної прихованої нормалізації Unicode. }
function ProjectionText(Node:TSourceNode):RawByteString;
var I:SizeInt;C:AnsiChar;
begin
  Result:='';
  if Node=nil then Reject('відсутнє значення колонки');
  case Node.Kind of
    skList: begin
      if Length(Node.Children)<>0 then Reject('складена чужа проєкція');
    end;
    skAtom: begin
      Result:=Node.Text;
      if Result='' then Reject('порожній атом проєкції');
    end;
    skString: begin
      if (Length(Node.Text)<2) or (Node.Text[1]<>'"') or
         (Node.Text[Length(Node.Text)]<>'"') then
        Reject('відсутні лапки текстової проєкції');
      I:=2;
      while I<Length(Node.Text) do begin
        C:=Node.Text[I];
        if C='\' then begin
          Inc(I);
          if I>=Length(Node.Text) then Reject('обірваний escape');
          C:=Node.Text[I];
          if not (C in ['\','"']) then Reject('недопущений escape');
        end;
        Result:=Result+C;Inc(I);
      end;
    end;
  else Reject('невідомий тип поверхні');
  end;
end;

function ParseProjectionTable(const Source:RawByteString;Width:Byte):TProjectionRows;
var Doc:TSourceDocument;TableNode,Row,Cell:TSourceNode;
    Candidate:TProjectionRows; I,J,V:SizeInt; Surface:TProjectionSurface;
    Binary:RawByteString;
begin
  Result:=nil;Doc:=nil;
  if (Width<1) or (Width>10) then Reject('підтримано лише D1..D10');
  try
    try
      Doc:=ReadUkrainianSource(Source);
      if (Length(Doc.Forms)<>1) or (Doc.Forms[0]=nil) then
        Reject('потрібна одна pinned таблиця');
      TableNode:=Doc.Forms[0];
      if (TableNode.Kind<>skList) or
         (Length(TableNode.Children)<>(SizeInt(1) shl Width)+1) or
         (TableNode.Children[0]=nil) or
         (TableNode.Children[0].Kind<>skAtom) or
         (TableNode.Children[0].Text<>'domain-table-1') then
        Reject('помилкова кількість точних координат');
      SetLength(Candidate,(SizeInt(1) shl Width));
      for I:=0 to High(Candidate) do begin
        Row:=TableNode.Children[I+1];
        if (Row=nil) or (Row.Kind<>skList) or
           (Length(Row.Children)<>ProjectionColumns+1) or
           (Row.Children[0]=nil) or (Row.Children[0].Kind<>skAtom) then
          Reject('неправильна форма доменного рядка');
        Binary:=Row.Children[0].Text;
        if Length(Binary)<>Width then Reject('втрачено точну ширину');
        V:=0;
        for J:=1 to Length(Binary) do begin
          V:=V*2;
          if Binary[J]='1' then Inc(V)
          else if Binary[J]<>'0' then Reject('небінарна координата');
        end;
        if V<>I then Reject('відсутня, повторна чи переставлена координата');
        Candidate[I].Bits:=Binary;
        for Surface:=Low(TProjectionSurface) to High(TProjectionSurface) do begin
          Cell:=Row.Children[Ord(Surface)+1];
          if (Cell=nil) or (Cell.Kind<>skList) or
             (Length(Cell.Children)<>2) or
             (Cell.Children[0]=nil) or
             (Cell.Children[0].Kind<>skAtom) or
             (Cell.Children[0].Text<>NameOrder[Surface]) then
            Reject('змінено шість pinned колонок');
          Candidate[I].Names[Surface]:=ProjectionText(Cell.Children[1]);
        end;
        if Width=7 then begin
          { D7 LISP завжди не-викличний, а не таємний dispatch. }
          if Candidate[I].Names[psLisp]<>'' then
            Reject('D7 не визначає LISP-голів');
          if (I<32) or (I=127) then begin
            if (Candidate[I].Names[psUk]<>'') or
               (Candidate[I].Names[psUkr]<>'') then
              Reject('керувальна координата D7 не має друкованої поверхні');
          end;
        end;
      end;
      Result:=Candidate; { публікація лише після повної перевірки }
    except
      on E:EProjectionCatalogError do raise;
      on E:Exception do Reject('синтаксис pinned-проєкції: '+E.Message);
    end;
  finally Doc.Free end;
end;

function LoadProjectionTable(const RepoRoot:String;Width:Byte):TProjectionRows;
var Path:String; F:TFileStream;Data:RawByteString;
begin
  Result:=nil;
  if (Width<1) or (Width>10) then Reject('поза D1..D10');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim+
    'domains'+PathDelim+'d'+IntToStr(Width)+'.lisp';
  try
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<25) or (F.Size>1024*1024) then
        Reject('pinned таблиця поза межею');
      SetLength(Data,SizeInt(F.Size));
      F.ReadBuffer(Data[1],Length(Data));
    finally F.Free end;
    Result:=ParseProjectionTable(Data,Width);
  except
    on E:EProjectionCatalogError do raise;
    on E:Exception do Reject('читання pinned D'+IntToStr(Width)+': '+E.Message);
  end;
end;

procedure LoadProjectionCatalog(const RepoRoot:String;out Catalog:TProjectionCatalog);
var Candidate:TProjectionCatalog; D:Byte;
begin
  for D:=1 to 10 do begin
    Catalog[D]:=nil;Candidate[D]:=nil;
  end;
  for D:=1 to 10 do Candidate[D]:=LoadProjectionTable(RepoRoot,D);
  for D:=1 to 10 do Catalog[D]:=Candidate[D];
  { При відмові старий/частковий каталог не публікується; усі managed
    Pascal-рядки Candidate звільняються автоматично. }
end;

{ Питання: 1) Чому san є дійсною колонкою замість історичного sa?
  2) Чому LISP показуємо, але не виконуємо?
  3) Чому D7:0110000 має 7 біт попри текстове "0"?
  4) Чому немає reverse lookup за en, якщо назви можуть повторюватися?
  5) Чому публікація 2046 рядків тільки після всіх десяти файлів? }
end.
