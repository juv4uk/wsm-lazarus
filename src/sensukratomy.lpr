{ G2.50. Доказове читання української повної проєкції укр.
  Результат — тільки host-перелік атомів та exact keys. Це НЕ evaluator. }
program sensukratomy;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii, wsm.bindindex,
  wsm.bindatoms, wsm.ukratoms, wsm.source;
const MaxSource = 4 * 1024 * 1024;
var
  Catalog: TProektsiiCatalog;
  Atoms: TAtomRecords;
  Path: String;
  Source: RawByteString;
  F: TFileStream;
  I, Known, Unknown: SizeInt;

function Uk(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Check(OK: Boolean; const Problem: String);
begin
  if not OK then raise EUkrAtomsError.Create(Problem);
end;

procedure SelfCheck;
var
  Mutant: TProektsiiCatalog;
  Index: TBindIndex;
  A: TAtomRecords;
  S, Letter: RawByteString;
  D, J, K: SizeInt;
  Rejected, Found: Boolean;
begin
  LoadPinnedProjections('external/sens',Catalog);
  S := Uk('порожній? (як-є "і" ()) невідоме-ім''я');
  CollectFullUkrAtoms(S,Catalog,A);
  Check(Length(A)=3,'Потрібні рівно три синтаксичні атоми');
  Check((A[0].Resolution=arDomainProjection) and
    SameKey(A[0].Key,ExactKey('0101')) and
    (A[0].Position=apTopLevel) and (A[0].ByteOffset=1),
    'Втрачено повний укр D4:0101 або фізичне походження');
  Check((A[1].Resolution=arDomainProjection) and
    SameKey(A[1].Key,ExactKey('001')) and
    (A[1].Position=apFirstChild) and
    (A[1].ByteOffset=Pos(Uk('як-є'),S)),
    'Втрачено точний pinned укр D3:001');
  Check((A[2].Resolution=arUnresolved) and
    (A[2].Key.Width=0) and (A[2].Key.Bits=0) and
    (A[2].ByteOffset=Pos(Uk('невідоме-ім'),S)),
    'Лексична змінна не може отримати вигаданий ключ');
  CollectFullUkrAtoms(Uk('порожнє?'),Catalog,A);
  Check((Length(A)=1) and (A[0].Resolution=arUnresolved),
    'Коротке ук не можна підміняти повним укр');

  { Д7 не є викличним навіть коли стоїть першою дитиною списку:
    тут лише синтаксична позиція, жодного виклику не виконуємо. }
  Found := False;
  for J:=0 to High(Catalog[7]) do begin
    Letter:=Catalog[7][J].Surface[1];
    if (Letter='') or (Letter[1]='"') then Continue;
    CollectFullUkrAtoms('('+Letter+')',Catalog,A);
    Check((Length(A)=1) and (A[0].Position=apFirstChild) and
      SameKey(A[0].Key,Catalog[7][J].Key),
      'D7 — рівно один точний текстовий атом');
    Found:=True;
    Break;
  end;
  Check(Found,'Потрібний pinned друкований D7 атом');
  CollectFullUkrAtoms(Uk('("і" ())'),Catalog,A);
  Check(Length(A)=0,'D7-рядок і () не стають атомами');

  { Відхиляємо зіпсований останній D10, з обнуленням старого індексу. }
  Mutant:=Catalog;
  for D:=1 to 10 do begin
    SetLength(Mutant[D],Length(Catalog[D]));
    for K:=0 to High(Catalog[D]) do Mutant[D][K]:=Catalog[D][K];
  end;
  Mutant[10][1023].Key.Bits:=0;
  SetLength(Index.Slots,5);
  Index.Count:=5;
  Rejected:=False;
  try BuildFullUkrIndex(Mutant,Index);
  except on E:EUkrAtomsError do Rejected:=True end;
  Check(Rejected and (Length(Index.Slots)=0) and (Index.Count=0),
    'Пізній D10 збій опублікував індекс');
  Mutant[10][1023]:=Catalog[10][1023];
  Mutant[3][1].Surface[1]:=Catalog[4][5].Surface[1];
  Rejected:=False;
  try BuildFullUkrIndex(Mutant,Index);
  except on E:EUkrAtomsError do Rejected:=True end;
  Check(Rejected and (Length(Index.Slots)=0) and (Index.Count=0),
    'Міждоменна колізія укр не відхилена');
  CollectFullUkrAtoms(Uk('так'),Catalog,A);
  Check((Length(A)=1) and SameKey(A[0].Key,ExactKey('1')),
    'Відновлення D1 після відмови');

  CollectFullUkrAtoms(Uk('так'),Catalog,A);
  Rejected:=False;
  try CollectFullUkrAtoms(RawByteString(#$C0#$AF),Catalog,A);
  except on E:ESourceError do Rejected:=True end;
  Check(Rejected and (Length(A)=0),
    'Некоректний UTF-8 опублікував часткові атоми');
  WriteLn(Uk('УКР-АТОМИ-САМОПЕРЕВІРКА-ГАРАЗД '),
    Uk('D4=0101 D3=001 D7=дані D10=відмова колізія=відмова UTF8=відмова'));
end;

begin
  try
    if (ParamCount=1) and
       (RawByteString(ParamStr(1))=Uk('--самоперевірка')) then begin
      SelfCheck;
      Halt(0);
    end;
    if ParamCount<>1 then begin
      WriteLn(StdErr,Uk('Використання: sensukratomy файл.lisp або --самоперевірка'));
      Halt(64);
    end;
    Path:=ParamStr(1);
    if LowerCase(ExtractFileExt(Path))<>'.lisp' then
      raise EUkrAtomsError.Create('Очікується лише людська проєкція .lisp, не .sens');
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<=0) or (F.Size>MaxSource) then
        raise EUkrAtomsError.Create('Порожня або надмірна укр проєкція');
      SetLength(Source,SizeInt(F.Size));
      F.ReadBuffer(Source[1],Length(Source));
    finally F.Free end;
    LoadPinnedProjections('external/sens',Catalog);
    CollectFullUkrAtoms(Source,Catalog,Atoms);
    Known:=0; Unknown:=0;
    { stdout — ТІЛЬКИ після повного читання, pinned і зв'язування. }
    for I:=0 to High(Atoms) do begin
      if Atoms[I].Resolution=arDomainProjection then begin
        Inc(Known);
        WriteLn(Uk('атом='),I+1,Uk(' байт='),Atoms[I].ByteOffset,
          Uk(' рядок='),Atoms[I].Line,Uk(' стовпець='),Atoms[I].ByteColumn,
          Uk(' координата=D'),Atoms[I].Key.Width,':',KeyBits(Atoms[I].Key),
          Uk(' напис='),Atoms[I].Name);
      end else begin
        Inc(Unknown);
        WriteLn(Uk('атом='),I+1,Uk(' байт='),Atoms[I].ByteOffset,
          Uk(' незв’язаний='),Atoms[I].Name);
      end;
    end;
    WriteLn(Uk('УКР-АТОМИ-ГАРАЗД зв’язаних='),Known,
      Uk(' незв’язаних='),Unknown,
      Uk(' викличність=не-перевірено D7=дані D12+=не-зв’язуємо'));
  except
    on E:Exception do begin
      WriteLn(StdErr,Uk('УКР-АТОМИ-ПОМИЛКА: '),
        RawByteString(E.Message));
      Halt(2);
    end;
  end;
end.
