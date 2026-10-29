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
function SurfaceForDisplay(const Value: RawByteString): String;
implementation
uses Classes;
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
procedure LoadProjectionTable(const Source: RawByteString; Width: Byte;
  out Rows: TProektsiiRows);
var P,E,Count,Limit:SizeInt; Line:RawByteString; Candidate:TProektsiiRows;
  R:TProektsiiaRow;
begin
  SetLength(Rows,0);
  Demand((Width>=1) and (Width<=10),'Таблиця поза D1–D10');
  Limit:=SizeInt(1) shl Width;
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
    ParseRow(Line,Width,R);
    Demand(R.Key.Bits=Count,'Дубль або порушення порядку exact-координат');
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
      Demand(Candidate[D][I].Surface[0]=Base[I].Ukrainian,
        'Не збіглася pinned ук-проєкція');
    end;
  end;
  Catalog:=Candidate;
end;
function SurfaceForDisplay(const Value: RawByteString): String;
begin
  if Value='' then Result:='(відсутня)'
  else Result:=String(Value);
end;
end.
