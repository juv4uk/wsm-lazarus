{ G6.29 — перевірений IR -> справжній машинний ELF64.
  Канонічний .sens лишається джерелом правди: довільний зовнішній IR
  не може підмінити біти, фізичне походження або викличну голову.
  Ні семантики Common Lisp, ні місцевого реєстру законів тут немає. }
unit wsm.exactirtoelf;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.exactir;
type
  EVerifiedIRELFError=class(Exception);
function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactirguard,wsm.elfquotet5m;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EVerifiedIRELFError.Create(Why);
end;

function SameNode(const A,B:TExactIRNode):Boolean;
begin
  { Не порівнювати raw record/FillChar: explicit fields не включають
    padding чи випадковий вміст. Фізичне походження — до трита. }
  Result:=
    (A.Kind=B.Kind) and
    (A.RootIndex=B.RootIndex) and
    (A.ParentIndex=B.ParentIndex) and
    (A.ChildIndex=B.ChildIndex) and
    (A.Depth=B.Depth) and
    (A.WordIndex=B.WordIndex) and
    (A.HasKey=B.HasKey) and
    (A.Key.Width=B.Key.Width) and
    (A.Key.Bits=B.Key.Bits) and
    (A.Physical.WordIndex=B.Physical.WordIndex) and
    (A.Physical.TritStart=B.Physical.TritStart) and
    (A.Physical.TritEnd=B.Physical.TritEnd) and
    (A.Physical.ByteStart=B.Physical.ByteStart) and
    (A.Physical.ByteEnd=B.Physical.ByteEnd) and
    (A.Physical.IsEOF=B.Physical.IsEOF);
end;

function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var
  Tables:TDomainSet;
  ActualIR:TExactIR;
  CandidateStats,ActualStats:TExactIRGuardStats;
  I:SizeInt;
begin
  Result:='';
  try
    Require((Length(Physical)>=1) and (Length(Physical)<=65536),
      'Фізичне джерело поза host-межею');
    { Крок 1 — перевірка структурної валідності зовнішнього IR:
      кількість коренів, DFS, фізичні межі, точні ключі.
      CandidateIR є borrowed, ніколи не змінюється. }
    VerifyExactIRStructure(CandidateIR,CandidateStats);

    { Крок 2 — ВІДТВОРИТИ provenance із вихідних T5M байтів.
      BuildExactIR вже використовує канонічний T5M/D2 і pinned binder;
      не виводимо імен/законів із projections. }
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,ActualIR);
    VerifyExactIRStructure(ActualIR,ActualStats);
    Require((Length(CandidateIR.Roots)=Length(ActualIR.Roots)) and
      (Length(CandidateIR.Nodes)=Length(ActualIR.Nodes)) and
      (CandidateIR.BoundLeaves=ActualIR.BoundLeaves),
      'Зовнішній IR не відповідає фізичному джерелу');
    Require((CandidateStats.Nodes=ActualStats.Nodes) and
      (CandidateStats.Roots=ActualStats.Roots) and
      (CandidateStats.BoundLeaves=ActualStats.BoundLeaves) and
      (CandidateStats.StructuralNodes=ActualStats.StructuralNodes) and
      (CandidateStats.MaxDepth=ActualStats.MaxDepth),
      'Статистика IR відрізняється від фізичного джерела');
    for I:=0 to High(ActualIR.Roots) do
      Require(CandidateIR.Roots[I]=ActualIR.Roots[I],
        'Підмінено фізичний покажчик кореня');
    for I:=0 to High(ActualIR.Nodes) do
      Require(SameNode(CandidateIR.Nodes[I],ActualIR.Nodes[I]),
        'Підмінено точне слово або фізичну адресу IR вузла '+
          IntToStr(I));

    { Крок 3 — вузьке входження до backend: ТІЛЬКИ
      кореневий D2-список із точною головою D3:001 «як-є».
      Це не дозвіл виклику для інших доменів: кінцеве семантичне
      підтвердження й CodeGen залишається в BuildQuoteT5MELF. }
    Require((Length(ActualIR.Roots)=1) and
      (Length(ActualIR.Nodes)>=3),'Очікується одна форма цитування');
    Require((ActualIR.Roots[0]=0) and
      (ActualIR.Nodes[0].Kind=ikList) and
      (ActualIR.Nodes[1].Kind=ikIdentity) and
      ActualIR.Nodes[1].HasKey and
      (ActualIR.Nodes[1].ParentIndex=0) and
      (ActualIR.Nodes[1].ChildIndex=0) and
      (ActualIR.Nodes[1].Key.Width=3) and
      (KeyBits(ActualIR.Nodes[1].Key)='001') and
      (ActualIR.Nodes[2].ParentIndex=0) and
      (ActualIR.Nodes[2].ChildIndex=1),
      'Це не допущена pinned D3:001 фізична голова');

    { Наявний emitter робить повну арність, keyed runtime admission,
      ELF64 ET_DYN і реальний x86-64 write фізичних T5M даних.
      ЖОДНИХ нового instruction dispatch чи повторення законів. }
    Result:=BuildQuoteT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:=''; raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

{ Фізичні ресурси: CandidateIR borrowed на тривалість виклику,
  ActualIR/Tables — локальні FPC-managed dynamic arrays, звільняються
  після виходу. ELF — новий owned RawByteString. Межа 65536 байтів
  джерела — host квота, не закон SENS.
  Питання: (1) Чому структурний сторож не є доказом provenance?
  (2) Чому звіряємо тритові адреси, а не лише байти?
  (3) Чому D7 text-data не перетворюється на callable?
  (4) Хто виконує реальний D3 механізм перед ELF?
  (5) Чому це не загальний compiler чи Core4 REPL? }
end.
