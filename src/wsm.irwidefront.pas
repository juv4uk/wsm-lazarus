{ G6.97 — СПІЛЬНИЙ ВХІД для ТРИНАДЦЯТИ уже доведених flat physical D2 форм
  Тепер також композиція перевірених лівих 1..100 і правих 1..16
  вкладених D5 ADD/SUB — без нових мовних законів чи ISA backend..
  НЕ новий evaluator, НЕ реєстр мовних законів і НЕ новий x86 emitter.
  Pinned SENS визначає значення/identity; це тільки whitelist наявних
  *машинних профілів* за exact domain-qualified bit key.
  Кожен старий backend самостійно повторно перевіряє повну структуру. }
unit wsm.irwidefront;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideFrontError=class(Exception);
function BuildVerifiedWideELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.irwidezero,wsm.irwideless,wsm.irwidegreater,wsm.irwideabs,
     wsm.irwideaddreg,wsm.irwidemul,wsm.irwidesub,wsm.irwidensd,
     wsm.irwidequot,wsm.irarithchain,wsm.irarithpravy,wsm.irarithderevo,
     wsm.irwideneg,
     wsm.irwideleqgeq,
     wsm.irmixedstep,
     wsm.irwiderest,wsm.irwideminmax,
     wsm.elfgeometry;

procedure Demand(Allowed:Boolean;const Why:String);
begin if not Allowed then raise EIRWideFrontError.Create(Why) end;

{ ProgramPhysical: borrowed canonical packed T5M bytes for a single D2
  program, NOT text. AuthorityRoot: borrowed pinned external/sens dir.
  Result: owned byte-exact ELF64 PIE, only after final machine geometry.
  No SENS function names are dispatched; a small set of compiled
  machine profiles is selected by a proven pinned (width,bits) head.
  Every existing Build*Wide*ELF independently rechecks all children,
  numeric admission, D12/D24, and output geometry; thus this entrypoint
  cannot silently broaden the domain of any compiler backend.

  1) Чому HasPinnedKey потрібен окрім самих бітів голови?
  2) Чому для D5 та D6 перевіряється ще й Width?
  3) Чому opaque W12 не є автоматично числовим D12?
  4) Чому підлеглий backend знову повністю звіряє IR та числовий допуск?
  5) Хто володіє керованими масивами IR та байтами поверненого ELF? }
{ Лише структурний маршрут вкладеного D2, НЕ новий SENS закон.
  Кожну точну D5 голову, D12 листок та проміжний результат повторно
  перевіряє чинний BuildIRMixedTreeELF. Фізичні RawByteString/IR
  керуються FPC, вузли не копіюються; Boolean — лише host-маршрут.
  1) Чому обидва напрями, а не перше wkList?
  2) Хто відхиляє D6 підміну всередині D5 дерева?
  3) Чому ліві 100 кроків не обмежуються до 31?
  4) Чому Boolean цього helper не є D1 предикатом? }
function HasMixedD5Children(const IR:TWideIR):Boolean;
var I,Parent:SizeInt;LeftNested,RightNested:Boolean;
begin
  LeftNested:=False;RightNested:=False;
  for I:=1 to High(IR.Nodes) do
    if IR.Nodes[I].Kind=wkList then begin
      Parent:=IR.Nodes[I].ParentIndex;
      if (Parent>=0) and (Parent<Length(IR.Nodes)) and
         (IR.Nodes[Parent].Kind=wkList) then begin
        if IR.Nodes[I].ChildIndex=1 then LeftNested:=True
        else if IR.Nodes[I].ChildIndex=2 then RightNested:=True;
      end;
    end;
  Result:=LeftNested and RightNested;
end;

function BuildVerifiedWideELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Head:TWideIRNode;Geom:TELFGeometry;
begin
  Result:='';
  Demand((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'фізична .sens програма порожня або завелика');
  DecodeT5M(ProgramPhysical,Words);
  Demand(EncodeT5M(Words)=ProgramPhysical,
    'джерело не є канонічним T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Demand((Stats.Roots=1) and (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Stats.Nodes>=3) and (Length(IR.Nodes)>=3) and
    (IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].Depth=0),
    'потрібен лише один canonical D2 список');
  Head:=IR.Nodes[1];
  Demand((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1) and
    SameKey(Head.NarrowKey,ExactKey(Head.Bits)),
    'виклична голова не підтверджена pinned D5/D6');
  { Вибираємо лише НАЯВНІ ратифіковані механічні профілі; жодного
    закону не реалізуємо вдруге. Width позначає точний домен,
    не машинний opcode або людську функціональну назву. }
  if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('01000')) then
    Result:=BuildIRWideZeroELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('11010')) then
    Result:=BuildIRWideLessELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('11011')) then
    Result:=BuildPhysicalGreaterELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('01010')) then begin
    { Уже ратифікована pinned голова D5. Дочірня структура обирає
      лише наявний машинний профіль, не значення або закон мови.
      Лівий вкладений список → 100-кроковий чинний backend;
      правий вкладений список → 16-кроковий чинний backend.
      Обидва повторно перевіряють усе WideIR та exact D12.
      1) Чому wkList — лише маршрутизація, а не SENS opcode?
      2) Хто відхиляє мішану або зіпсовану вкладеність?
      3) Чому порядок SUB не можна змінити?
      4) Кому належить ELF після виклику чинного backend? }
    if HasMixedD5Children(IR) then
      Result:=BuildIRMixedTreeELF(ProgramPhysical,AuthorityRoot)
    else if (Length(IR.Nodes)>4) and (IR.Nodes[2].Kind=wkList) then
      Result:=BuildIRArithChainELF(ProgramPhysical,AuthorityRoot)
    else if (Length(IR.Nodes)>4) and
            (IR.Nodes[2].Kind=wkAtom) and
            (IR.Nodes[3].Kind=wkList) then
      Result:=BuildIRArithPravyELF(ProgramPhysical,AuthorityRoot)
    else
      Result:=BuildIRWideAddRegisterELF(ProgramPhysical,AuthorityRoot);
  end
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('10110')) then
    Result:=BuildIRWideMulELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('01011')) then begin
    if HasMixedD5Children(IR) then
      Result:=BuildIRMixedTreeELF(ProgramPhysical,AuthorityRoot)
    else if (Length(IR.Nodes)>4) and (IR.Nodes[2].Kind=wkList) then
      Result:=BuildIRArithChainELF(ProgramPhysical,AuthorityRoot)
    else if (Length(IR.Nodes)>4) and
            (IR.Nodes[2].Kind=wkAtom) and
            (IR.Nodes[3].Kind=wkList) then
      Result:=BuildIRArithPravyELF(ProgramPhysical,AuthorityRoot)
    else
      Result:=BuildIRWideSubELF(ProgramPhysical,AuthorityRoot);
  end
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('10111')) then
    Result:=BuildIRWideQuotELF(ProgramPhysical,AuthorityRoot)
  { Два pinned D6 точні W6-кроки, включно з вкладеними 1..5:
    тільки механічне делегування до вже чинного BuildIRMixedStepELF,
    який повторно перевіряє весь IR, exact D12 і машинний профіль.
    Фізичні байти входу borrowed, ELF64 Result — FPC-managed owned.
    1) Чому недостатньо D7 імені операції?
    2) Хто відхиляє шостий вкладений крок?
    3) Чому D24 не можна мовчки звужувати?
    4) Де незалежний семантичний oracle? }
  else if (Head.Width=6) and
    (SameKey(Head.NarrowKey,ExactKey('001110')) or
     SameKey(Head.NarrowKey,ExactKey('001111'))) then
    Result:=BuildIRMixedStepELF(ProgramPhysical,AuthorityRoot)
  { Лише D4:0100 ХИБНЕ? як ратифікована виклична голова;
    всередині — сувора D5:11010/11011 над двома signed D12.
    D6 LEQ/GEQ тут НЕ викличні, навіть якщо каталогові записи є.
    1) Чому D4 NOT є окремою координатою?
    2) Чому нижній backend повторює весь exact D2 admission?
    3) Чому машинний SETLE/SETGE не створює законів D6? }
  else if (Head.Width=4) and SameKey(Head.NarrowKey,ExactKey('0100')) then
    Result:=BuildIRWideBoundsELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and SameKey(Head.NarrowKey,ExactKey('010101')) then
    Result:=BuildIRWideNsdELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and SameKey(Head.NarrowKey,ExactKey('010100')) then
    Result:=BuildIRWideRestELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and SameKey(Head.NarrowKey,ExactKey('010010')) then
    Result:=BuildIRWideNegELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and SameKey(Head.NarrowKey,ExactKey('010011')) then
    Result:=BuildIRWideAbsELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and
    (SameKey(Head.NarrowKey,ExactKey('110101')) or
     SameKey(Head.NarrowKey,ExactKey('110111'))) then
    Result:=BuildIRWideMinMaxELF(ProgramPhysical,AuthorityRoot)
  else
    raise EIRWideFrontError.Create(
      'вузький нативний профіль цієї pinned координати ще не реалізовано');
  VerifySENSELF64(Result,Geom);
  Demand((Geom.Kind=3) and (Geom.Entry=120) and
    (Geom.FileBytes=Length(Result)),
    'некоректний ELF64 PIE від перевіреного backend');
end;
end.
