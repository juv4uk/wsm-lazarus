{ G6.135 — AOT спеціалізація СПРАВЖНЬОГО двоаргументного визначення
  pinned lib/core1.sens. Pascal НЕ містить його бібліотечного тіла:
  фізичний D4 DEFINE/LAMBDA/D5 body читається з upstream T5M.
  Тільки перевірена підстановка двох exact W12 даних у вихідну D5
  форму, далі — спільний BuildVerifiedWideELF, без власного emitter.

  RepoRoot/LeftPhysical/RightPhysical позичені; Result — окремі owned
  ELF64 або T5M байти. Всі TFileStream, TD2Document та Core1 runtime
  звільняються в finally. Жодного текстового dispatch за проєкцією.
  1) Чому тільки pinned фізичне DEFINE/LAMBDA, а не .lisp текст?
  2) Як доведено відповідність порядку двох D7 параметрів?
  3) Хто допустить D5 та numeric overflow після спеціалізації?
  4) Чим runtime Core1 відрізняється від незалежного SENS REPL oracle?
  5) Чому це не загальний компілятор всіх 96 визначень? }
unit wsm.lowerpinnedcore1add;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ELowerPinnedCore1AddError=class(Exception);
function BuildPinnedCore1AddELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
function PinnedCore1AddCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
function BuildPinnedCore1SubELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
function PinnedCore1SubCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.numericplane,wsm.numericadd,
     wsm.numericsub,
     wsm.irwidefront,wsm.elfd12promote,wsm.elfgeometry,wsm.core1selektor,
     wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard;
const MaxCore1Bytes=4*1024*1024;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise ELowerPinnedCore1AddError.Create(Why);
end;

{ Стежимо за джерелом: тільки бінарний pinned Core1, без читання
  .lisp проєкції та без припущення, що байтова довжина = домен. }
function ReadPinnedCore1(const RepoRoot:String):RawByteString;
var F:TFileStream;Path:String;
begin
  Need((RepoRoot<>'') and (Length(RepoRoot)<4096),
    'потрібен корінь робочого дерева pinned SENS');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external/sens/lib/core1.sens';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MaxCore1Bytes),
      'порожній або надмірний pinned Core1');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Назва — список фізичних семибітних D7 знаків.
  Не декодуємо їх у текст — одна ідентичність не може стати opcode
  від spelling або від номеру визначення у файлі. }
function ExactD7Name(const Node:TD2Node):RawByteString;
var I:SizeInt;Child:TD2Node;
begin
  Need((Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=256),
    'очікується непорожній обмежений фізичний список D7');
  Result:='';
  for I:=0 to High(Node.Children) do begin
    Child:=Node.Children[I];
    Need((Child<>nil) and (Child.Kind=dkIdentity) and
      (Child.Width=7) and (Length(Child.Bits)=7),
      'параметр або ім’я має не точний D7 гліф');
    Result:=Result+Child.Bits;
  end;
end;

{ Повертає лише ОДНЕ exact DEFINE, у якого оригінальне фізичне
  тіло має форму D5:01010(параметр_1,параметр_2). Це вузький
  профіль спеціалізації, НЕ авторитетний реєстр законів.
  Витягнутий AST і повний T5M перевіряються до емісії; незалежний
  TCore1Selektor мусить допустити саме цей source-backed D7 ключ. }
procedure ExtractPinnedBinary(const RepoRoot:String;
  const ExpectedHead:RawByteString;out NameBits,HeadBits:RawByteString);
var Physical:RawByteString;Words:TExactWords;Document:TD2Document;
    Runtime:TCore1Selektor;Root,Lambda,Params,Body:TD2Node;
    I,Found,Ordinal:SizeInt;Candidate,ParamLeft,ParamRight:RawByteString;
begin
  NameBits:='';HeadBits:='';
  { Це два раніше допущені машинні профілі, не нові закони:
    сама координата і повне DEFINE повинні бути у pinned Core1. }
  Need((ExpectedHead='01010') or (ExpectedHead='01011'),
    'непідтриманий фізичний D5 профіль Core1');
  Physical:=ReadPinnedCore1(RepoRoot);
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'pinned Core1 має неканонічний T5M');
  Document:=ParseD2WordsWide(Words);
  try
    Need(Length(Document.Roots)=96,
      'pinned Core1 census змінився — не можна вгадувати визначення');
    Found:=0;
    for I:=0 to High(Document.Roots) do begin
      Root:=Document.Roots[I];
      if (Root=nil) or (Root.Kind<>dkList) or
         (Length(Root.Children)<>3) then Continue;
      if (Root.Children[0].Kind<>dkIdentity) or
         (Root.Children[0].Width<>4) or
         (Root.Children[0].Bits<>'0011') then Continue;
      Lambda:=Root.Children[2];
      if (Lambda=nil) or (Lambda.Kind<>dkList) or
         (Length(Lambda.Children)<>3) then Continue;
      if (Lambda.Children[0].Kind<>dkIdentity) or
         (Lambda.Children[0].Width<>4) or
         (Lambda.Children[0].Bits<>'0010') then Continue;
      Params:=Lambda.Children[1];Body:=Lambda.Children[2];
      if (Params=nil) or (Params.Kind<>dkList) or
         (Length(Params.Children)<>2) or
         (Body=nil) or (Body.Kind<>dkList) or
         (Length(Body.Children)<>3) then Continue;
      if (Body.Children[0].Kind<>dkIdentity) or
         (Body.Children[0].Width<>5) or
         (Body.Children[0].Bits<>ExpectedHead) then Continue;
      { Точна позиційна підстановка допускається лише для повного
        тіла, у якому обидва аргументи — відповідні D7 параметри. }
      ParamLeft:=ExactD7Name(Params.Children[0]);
      ParamRight:=ExactD7Name(Params.Children[1]);
      Need(ParamLeft<>ParamRight,'два параметри pinned Core1 збігаються');
      Need((ExactD7Name(Body.Children[1])=ParamLeft) and
           (ExactD7Name(Body.Children[2])=ParamRight),
        'тіло Core1 не зберігає порядок точних D7 параметрів');
      Need((Body.WordIndex>=1) and
           (Body.EndWordIndexExclusive>Body.WordIndex) and
           (Body.EndWordIndexExclusive<=Length(Words)+1) and
           (Words[Body.WordIndex-1]='10') and
           (Words[Body.EndWordIndexExclusive-2]='01'),
        'пошкоджені фізичні межі оригінального D5 тіла');
      Candidate:=ExactD7Name(Root.Children[1]);
      Inc(Found);
      Need(Found=1,'більш ніж одне спеціалізоване визначення Core1');
      NameBits:=Candidate;
      HeadBits:=Body.Children[0].Bits;
    end;
    Need(Found=1,'немає одного точного D5 тіла у pinned Core1');
  finally Document.Free end;
  Runtime:=TCore1Selektor.Create(RepoRoot);
  try
    Ordinal:=Runtime.FindAdmitted(NameBits);
    Need((Ordinal>=0) and (Runtime.AdmittedParamCount(Ordinal)=2) and
      (Runtime.AdmittedName(Ordinal)=NameBits),
      'незалежний Core1 runtime не допускає pinned DEFINE');
  finally Runtime.Free end;
end;

{ Обидва операнди — лише канонічні одноатомні D12; wider результати
  вирішує вже злитий WideIR numeric backend за pinned законом. }
function NumericBits(const Physical:RawByteString):RawByteString;
var Words:TExactWords;Numeric:TExplicitNumeric;
begin
  Need(Length(Physical)>0,'порожній D12 аргумент');
  DecodeT5M(Physical,Words);
  Need((Length(Words)=1) and (Length(Words[0])=12) and
       (EncodeT5M(Words)=Physical),'потрібен один canonical D12 атом');
  Numeric:=ReadNumericPhysical(Physical,12);
  Need((Numeric.DomainWidth=12) and
       (Numeric.ExactBits=Words[0]),'порушено точну D12 ідентичність');
  Result:=Words[0];
end;

function BuildPinnedCore1BinaryELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical,ExpectedHead:RawByteString):RawByteString;
var Head,Name,L,R,ProgramPhysical,Sum,Authority:RawByteString;
    W,SumWords:TExactWords;Geometry:TELFGeometry;
    Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
begin
  Result:='';
  L:=NumericBits(LeftPhysical);R:=NumericBits(RightPhysical);
  ExtractPinnedBinary(RepoRoot,ExpectedHead,Name,Head);
  SetLength(W,5);
  W[0]:='10';W[1]:=Head;W[2]:=L;W[3]:=R;W[4]:='01';
  ProgramPhysical:=EncodeT5M(W);
  Authority:=RawByteString(IncludeTrailingPathDelimiter(
    ExpandFileName(RepoRoot))+'external/sens');

  { Точно той самий pinned wide-IR admission ОБОВ'ЯЗКОВИЙ для ОБОХ
    профілів: він не виводить закон із довжини числа чи D7 назви. }
  LoadPinnedDomains(String(Authority),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Stats.Nodes=4) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'спеціалізований Core1 не є повною D5 WideIR формою');
  Need((IR.Nodes[1].HasPinnedKey) and (IR.Nodes[1].Width=5) and
       (IR.Nodes[1].Bits=Head) and
       (IR.Nodes[2].Width=12) and (IR.Nodes[3].Width=12) and
       (IR.Nodes[2].Bits=L) and (IR.Nodes[3].Bits=R),
       'exact pinned D5/D12 вузли спеціалізації не збіглися');

  { Ширину РЕЗУЛЬТАТУ визначає лише уже чинний AddNumericPhysical.
    Її не вгадують із D12 входів; жодного truncation із D24 у D12.
    Обидва native emitters існували до цього зрізу. }
  if ExpectedHead='01010' then
    Sum:=AddNumericPhysical(LeftPhysical,RightPhysical,12)
  else Sum:=SubtractNumericPhysical(LeftPhysical,RightPhysical,12);
  DecodeT5M(Sum,SumWords);
  Need(Length(SumWords)=1,'результат D5 має бути одним точним атомом');
  if Length(SumWords[0])=12 then
    Result:=BuildVerifiedWideELF(ProgramPhysical,Authority)
  else if (Length(SumWords[0])=24) and (ExpectedHead='01010') then
    Result:=BuildD12PromotedAddELF(LeftPhysical,RightPhysical)
  else if (Length(SumWords[0])=24) and (ExpectedHead='01011') then
    Result:=BuildVerifiedWideELF(ProgramPhysical,Authority)
  else raise ELowerPinnedCore1AddError.Create(
    'числова драбина потребує ще не підтриманого native backend');

  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Result)),
       'не отримано перевірений виконуваний ELF64 PIE');
end;

{ Незалежна від codegen інтерпретація САМЕ цього pinned Core1
  бібліотечного DEFINE за фізичним D7 ім’ям, а не рядком укр.
  Повертає фізичний T5M результат, не припущення про його ширину. }
function PinnedCore1BinaryCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical,ExpectedHead:RawByteString):RawByteString;
var Name,Head,L,R:RawByteString;T:TExactWords;
    I,N:SizeInt;Runtime:TCore1Selektor;
begin
  L:=NumericBits(LeftPhysical);R:=NumericBits(RightPhysical);
  ExtractPinnedBinary(RepoRoot,ExpectedHead,Name,Head);
  Need((Length(Name)>0) and (Length(Name) mod 7=0),
       'pinned Core1 назва не є D7');
  N:=Length(Name) div 7;
  { Голова — ОКРЕМИЙ вкладений D2 список точних D7 гліфів.
    Плоскі W7 у зовнішньому виклику НЕ утворюють одну назву. }
  SetLength(T,N+6);
  T[0]:='10';T[1]:='10';
  for I:=0 to N-1 do T[I+2]:=Copy(Name,I*7+1,7);
  T[N+2]:='01';
  T[N+3]:=L;T[N+4]:=R;T[N+5]:='01';
  Runtime:=TCore1Selektor.Create(RepoRoot);
  try Result:=Runtime.ExecutePhysicalCall(EncodeT5M(T));
  finally Runtime.Free end;
end;

{ Позичені параметри — canonical паковані D12 T5M; повернені bytes ELF
  або T5M є owned managed RawByteString. Відбувається тільки фізична
  спеціалізація вже ратифікованих DEFINE, без Pascal-копії функцій.
  1) Як знайти точне тіло DEFINE без його текстової назви?
  2) Чому не можна звузити D24 до D12?
  3) Хто перевіряє фактичний x86-64 ELF?
  4) Чому результат Core1 runtime не замінює pinned SENS REPL? }
function BuildPinnedCore1AddELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=BuildPinnedCore1BinaryELF(RepoRoot,LeftPhysical,RightPhysical,'01010');
end;

function BuildPinnedCore1SubELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=BuildPinnedCore1BinaryELF(RepoRoot,LeftPhysical,RightPhysical,'01011');
end;

function PinnedCore1AddCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=PinnedCore1BinaryCall(RepoRoot,LeftPhysical,RightPhysical,'01010');
end;

function PinnedCore1SubCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=PinnedCore1BinaryCall(RepoRoot,LeftPhysical,RightPhysical,'01011');
end;
end.
