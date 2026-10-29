{ G6.30 — спільний перевірений ExactIR для двох фізичних D3 backend.
  Тільки pinned SENS вирішує закон; тут — provenance і backend admission.
  D3:001 друкує незмінну цитату, D3:010 ВИКОНУЄ atom? на x86-64.
  Жодних локальних Lisp-законів, назв у dispatch або D12 арифметики. }
unit wsm.exactirtoelf;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.exactir;
type EVerifiedIRELFError=class(Exception);
function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
function BuildVerifiedAtomIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactirguard,
  wsm.elfquotet5m,wsm.elfatomt5m;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EVerifiedIRELFError.Create(Why);
end;

function SameNode(const A,B:TExactIRNode):Boolean;
begin
  { Не порівнюємо сирі record/padding. Точне походження до трита. }
  Result:=(A.Kind=B.Kind) and
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

{ Спільний довірений місток: не інтерпретує SENS і не створює IR
  з тексту. Вхід CandidateIR borrowed, ActualIR — власні FPC-managed
  масиви з незалежно зчитаних фізичних байтів; 64KiB — host-квота. }
procedure VerifyPhysicalExactIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR;out ActualIR:TExactIR);
var
  Tables:TDomainSet;
  CandidateStats,ActualStats:TExactIRGuardStats;
  I:SizeInt;
begin
  SetLength(ActualIR.Nodes,0);SetLength(ActualIR.Roots,0);
  ActualIR.BoundLeaves:=0;
  Require((Length(Physical)>=1) and (Length(Physical)<=65536),
    'Фізичне джерело поза host-межею');
  VerifyExactIRStructure(CandidateIR,CandidateStats);
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
      'Підмінено точне слово або фізичну адресу IR вузла '+IntToStr(I));
end;

{ Перевірка точного машинного входу: виключно один D2-список,
  фізична голова pinned D3 з рівно вказаними бітами. Не замінює
  повну перевірку арності/викличності в кожному чинному emitter. }
procedure RequireD3Head(const ActualIR:TExactIR;const ExactBits:RawByteString);
begin
  Require((Length(ActualIR.Roots)=1) and
    (Length(ActualIR.Nodes)>=3),'Очікується одна фізична D3-форма');
  Require((ActualIR.Roots[0]=0) and
    (ActualIR.Nodes[0].Kind=ikList) and
    (ActualIR.Nodes[1].Kind=ikIdentity) and
    ActualIR.Nodes[1].HasKey and
    (ActualIR.Nodes[1].ParentIndex=0) and
    (ActualIR.Nodes[1].ChildIndex=0) and
    (ActualIR.Nodes[1].Key.Width=3) and
    (KeyBits(ActualIR.Nodes[1].Key)=ExactBits) and
    (ActualIR.Nodes[2].ParentIndex=0) and
    (ActualIR.Nodes[2].ChildIndex=1),
    'Непідтримана точна D3 голова');
end;

function BuildVerifiedQuoteIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'001');
    { Чинний compiler підтверджує pinned D3:001 і фізичний T5M,
      виконує quote native та записує байти через ELF64 syscall. }
    Result:=BuildQuoteT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

function BuildVerifiedAtomIR(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var ActualIR:TExactIR;
begin
  Result:='';
  try
    VerifyPhysicalExactIR(Physical,AuthorityRoot,CandidateIR,ActualIR);
    RequireD3Head(ActualIR,'010');
    { Existing BuildAtomT5MELF -> BuildAtomELF відповідає
      за повну викличність/арність і машинні AND/CMP/SETNE/MOVZX;
      у нас НЕМАЄ host constant-fold значення D1:0/1. }
    Result:=BuildAtomT5MELF(Physical,AuthorityRoot);
    Require(Result<>'','Нативний emitter повернув порожній ELF');
  except
    on E:EVerifiedIRELFError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EVerifiedIRELFError.Create(
        'Перевірений фізичний IR відхилено: '+E.Message);
    end;
  end;
end;

{ Контракт/пам'ять: Physical та CandidateIR borrowed; ActualIR —
  локальна керована FPC пам'ять, ELF — новий owned RawByteString.
  На відмову EVerifiedIRELFError і нульовий результат.
  Питання:
  1) Чому структура IR не доводить його фізичне походження?
  2) Чому для двох backend-ів достатньо одного provenance guard?
  3) Чому машинний ATOM, а не Pascal, визначає вихідний D1?
  4) Чому D7 SYN дані не стають викличними головами?
  5) Чим цей вузький місток відрізняється від загального компілятора? }
end.
