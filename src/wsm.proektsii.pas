{ Механічний огляд pinned поверхонь SENS. Жодної нової семантики.
  Ключ — тільки точний домен і бітове слово; шість назв — лише проєкції.
  Усе читання атомарне: не оприлюднювати напівперевірену таблицю. }
unit wsm.proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.domain;
type
  EProektsiiError = class(Exception);
  TProektsiiaRow = record
    Key: TDomainKey;
    Surface: array[0..5] of RawByteString; { ук, укр, san, en, LISP, sym }
  end;
  TProektsiiRows = array of TProektsiiaRow;
  TProektsiiCatalog = array[1..10] of TProektsiiRows;
procedure LoadProjectionTable(const Source: RawByteString; Width: Byte;
  out Rows: TProektsiiRows);
procedure LoadPinnedProjections(const Root: String; out Catalog: TProektsiiCatalog);
function SameProjectedText(const Data: RawByteString; const Text: UnicodeString): Boolean;
function SurfaceForDisplay(const Value: RawByteString): String;
implementation
uses Classes,wsm.source;
const
  ColumnNames: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
procedure Demand(OK: Boolean; const Problem: String);
begin
  if not OK then raise EProektsiiError.Create(Problem);
end;
procedure Spaces(const S: RawByteString; var P: SizeInt);
begin
  while (P<=Length(S)) and (S[P] in [#9,' ']) do Inc(P);
end;
function ValueAt(const S: RawByteString; var P: SizeInt): RawByteString;
var Start: SizeInt; Closed: Boolean;
begin
  Demand(P<=Length(S),'Порожня колонка проєкції');
  if S[P]='(' then begin
    Demand(Copy(S,P,2)='()','Невірне порожнє значення');
    Inc(P,2);
    Exit('');
  end;
  Start:=P;
  if S[P]='"' then begin
    Inc(P);
    Closed:=False;
    while P<=Length(S) do begin
      if S[P]='\' then begin
        Inc(P);
        Demand(P<=Length(S),'Обрізана escape-послідовність');
        Demand((S[P]='"') or (S[P]='\'),
          'Невідоме екранування pinned поверхні');
        Inc(P);
      end else if S[P]='"' then begin
        Inc(P);
        Closed:=True;
        Break;
      end else Inc(P);
    end;
    Demand(Closed,'Незакрита лапка проєкції');
  end else begin
    while (P<=Length(S)) and not (S[P] in [')',' ',#9]) do Inc(P);
    Demand(P>Start,'Відсутнє значення проєкції');
  end;
  Result:=Copy(S,Start,P-Start); { лапки залишаються ознакою текстових даних }
end;
function ReadColumn(const S: RawByteString; var P: SizeInt;
  const Name: RawByteString): RawByteString;
begin
  Spaces(S,P);
  Demand((P<=Length(S)) and (S[P]='('),'Відсутня колонка '+String(Name));
  Inc(P);
  Demand(Copy(S,P,Length(Name))=Name,'Неправильний порядок колонок '+String(Name));
  Inc(P,Length(Name));
  Demand((P<=Length(S)) and (S[P]=' '),'Немає межі колонки '+String(Name));
  Spaces(S,P);
  Result:=ValueAt(S,P);
  Demand((P<=Length(S)) and (S[P]=')'),'Колонку не закрито '+String(Name));
  Inc(P);
end;
procedure ParseRow(const Line: RawByteString; Width: Byte;
  out Row: TProektsiiaRow);
var P, Start, I: SizeInt; Bits: RawByteString;
begin
  P:=1;
  Demand((P<=Length(Line)) and (Line[P]='('),'Немає початку рядка');
  Inc(P);
  Start:=P;
  while (P<=Length(Line)) and (Line[P] in ['0','1']) do Inc(P);
  Bits:=Copy(Line,Start,P-Start);
  Demand(Length(Bits)=Width,'Невірна ширина двійкової адреси');
  Demand((P<=Length(Line)) and (Line[P]=' '),'Немає межі двійкового слова');
  Row.Key:=ExactKey(Bits);
  for I:=0 to 5 do Row.Surface[I]:=ReadColumn(Line,P,ColumnNames[I]);
  Spaces(Line,P);
  Demand((P=Length(Line)) and (Line[P]=')'),
    'Зайві або відсутні дужки доменного рядка');
end;
{ Рядковий fast-path не має ігнорувати сторонні зовнішні S-expressions.
  Чинний wsm.source перевіряє ВСЮ UTF-8 структуру, включно з лапками.
  Це структурний host gate, а не місцевий мовний закон чи evaluator. }
procedure ValidateProjectionSyntax(const Source:RawByteString;Width:Byte);
var Doc:TSourceDocument;TableNode,Row:TSourceNode;
    I,Expected:SizeInt;
begin
  Doc:=nil;
  try
    try
      Doc:=ReadUkrainianSource(Source);
    except on E:Exception do
      raise EProektsiiError.Create('Невірний UTF-8 або синтаксис pinned таблиці: '+E.Message);
    end;
    Demand((Doc<>nil) and (Length(Doc.Forms)=1),
      'Рівно одна pinned таблиця, без сторонніх top-level форм');
    TableNode:=Doc.Forms[0];
    Demand((TableNode<>nil) and (TableNode.Kind=skList) and
      (Length(TableNode.Children)>0),
      'Невірна структура pinned таблиці');
    Demand((TableNode.Children[0]<>nil) and
      (TableNode.Children[0].Kind=skAtom) and
      (TableNode.Children[0].Text='domain-table-1'),
      'Невірна назва pinned таблиці');
    Expected:=SizeInt(1) shl Width;
    Demand(Length(TableNode.Children)=Expected+1,
      'Неповний або зайвий рядок pinned таблиці');
    for I:=1 to Expected do begin
      Row:=TableNode.Children[I];
      Demand((Row<>nil) and (Row.Kind=skList) and
        (Length(Row.Children)=7),
        'Пошкоджений рядок або шість колонок pinned таблиці');
    end;
  finally Doc.Free end;
end;

{ Лише host-адреса ОЧІКУВАНОГО рядка у діагностиці.
  Число Count не є SENS значенням, функцією чи номером закону. }
function RowIndexBits(Index: SizeInt; Width: Byte): RawByteString;
var I: SizeInt;
begin
  SetLength(Result,Width);
  for I:=Width downto 1 do begin
    if (Index and 1) <> 0 then Result[I]:='1'
    else Result[I]:='0';
    Index:=Index shr 1;
  end;
end;

procedure LoadProjectionTable(const Source: RawByteString; Width: Byte;
  out Rows: TProektsiiRows);
var P,E,Count,Limit:SizeInt; Line:RawByteString; Candidate:TProektsiiRows;
  R:TProektsiiaRow;
begin
  SetLength(Rows,0);
  Demand((Width>=1) and (Width<=10),'Таблиця поза D1–D10');
  Limit:=SizeInt(1) shl Width;
  ValidateProjectionSyntax(Source,Width);
  SetLength(Candidate,Limit);
  Count:=0;
  P:=1;
  while P<=Length(Source) do begin
    E:=P;
    while (E<=Length(Source)) and (Source[E]<>#10) do Inc(E);
    Line:=Trim(Copy(Source,P,E-P));
    P:=E+1;
    if (Length(Line)<2) or (Line[1]<>'(') or
       not (Line[2] in ['0','1']) then Continue;
    Demand(Count<Limit,'Зайвий рядок у доменній таблиці');
    { Діагностика збережена для всіх викликачів спільного pinned
      reader: позиція Count — це ОЧІКУВАНА exact-координата рядка,
      а не семантичне число чи припущення про зіпсований ключ.
      Глибина/колонки/UTF-8 як і раніше перевіряються ParseRow. }
    try
      ParseRow(Line,Width,R);
      Demand(R.Key.Bits=Count,
        'Дубль або порушення порядку exact-координат');
    except
      on E:EProektsiiError do
        raise EProektsiiError.Create('D'+IntToStr(Width)+': '+
          RowIndexBits(Count,Width)+' (очікуваний рядок): '+E.Message);
    end;
    if Width=7 then begin
      Demand(R.Surface[4]='','D7 LISP — лише (), не виклична голова');
      if (Count<32) or (Count=127) then
        Demand((R.Surface[0]='') and (R.Surface[1]=''),
          'Керувальна D7 координата не має ук/укр тексту')
      else
        Demand((R.Surface[0]<>'') and (R.Surface[1]<>''),
          'Друкована D7 координата без ук/укр проєкції');
    end;
    Candidate[Count]:=R;
    Inc(Count);
  end;
  Demand(Count=Limit,'Неповна pinned таблиця домену');
  Rows:=Candidate;
end;
procedure LoadPinnedProjections(const Root: String; out Catalog: TProektsiiCatalog);
var D,I:SizeInt; F:TFileStream; Data,Path:RawByteString;
  Candidate:TProektsiiCatalog; Base:TDomainTable;
begin
  for D:=1 to 10 do SetLength(Catalog[D],0);
  for D:=1 to 10 do begin
    Path:=RawByteString(IncludeTrailingPathDelimiter(Root)+
      'lib/domains/d'+IntToStr(D)+'.lisp');
    F:=TFileStream.Create(String(Path),fmOpenRead or fmShareDenyWrite);
    try
      Demand((F.Size>0) and (F.Size<=1024*1024),
        'Некоректний розмір pinned таблиці D'+IntToStr(D));
      SetLength(Data,SizeInt(F.Size));
      F.ReadBuffer(Data[1],Length(Data));
    finally F.Free end;
    LoadProjectionTable(Data,D,Candidate[D]);
    { Незалежний уже наявний exact-domain механізм перевіряє ключ та ук.
      Новий оглядач не створює власного реєстру викличності чи законів. }
    LoadDomainTable(Data,D,Base);
    Demand(Length(Candidate[D])=Length(Base),'Не збіглася кількість координат');
    for I:=0 to High(Base) do begin
      Demand(SameKey(Candidate[D][I].Key,Base[I].Key),
        'Не збіглася exact-координата');
      { Цитовані символи Д7, зокрема ")", тепер повністю читає
        чинний wsm.domain. Жодних винятків з незалежної звірки:
        кожна точна D1–D10 координата має збігатися побайтово. }
      Demand(Candidate[D][I].Surface[0]=Base[I].Ukrainian,
        'Не збіглася pinned ук-проєкція');
    end;
  end;
  Catalog:=Candidate;
end;
{ UTF-8 потрібен тільки на host-межі проєкції. Машинний D7 не стає Unicode. }
function SameProjectedText(const Data: RawByteString; const Text: UnicodeString): Boolean;
var Encoded: UTF8String;
begin
  Encoded:=UTF8Encode(Text);
  Result:=Data=RawByteString(Encoded);
end;
function SurfaceForDisplay(const Value: RawByteString): String;
begin
  if Value='' then Result:='(відсутня)'
  else Result:=String(Value);
end;
end.
