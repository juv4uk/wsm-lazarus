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
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.numericplane,wsm.irwidefront,
     wsm.elfgeometry,wsm.core1selektor;
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
procedure ExtractPinnedAddition(const RepoRoot:String;
  out NameBits,HeadBits:RawByteString);
var Physical:RawByteString;Words:TExactWords;Document:TD2Document;
    Runtime:TCore1Selektor;Root,Lambda,Params,Body:TD2Node;
    I,Found,Ordinal:SizeInt;Candidate,ParamLeft,ParamRight:RawByteString;
begin
  NameBits:='';HeadBits:='';
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
         (Body.Children[0].Bits<>'01010') then Continue;
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

function BuildPinnedCore1AddELF(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var Head,Name,L,R,ProgramPhysical:RawByteString;
    W:TExactWords;Geometry:TELFGeometry;
begin
  Result:='';
  L:=NumericBits(LeftPhysical);R:=NumericBits(RightPhysical);
  ExtractPinnedAddition(RepoRoot,Name,Head);
  SetLength(W,5);
  W[0]:='10';W[1]:=Head;W[2]:=L;W[3]:=R;W[4]:='01';
  ProgramPhysical:=EncodeT5M(W);
  { ТУТ відбувається єдина фактична нативна компіляція. }
  Result:=BuildVerifiedWideELF(ProgramPhysical,
    RawByteString(IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
      'external/sens'));
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Result)),
       'не отримано перевірений виконуваний ELF64 PIE');
end;

{ Незалежна від codegen інтерпретація САМЕ цього pinned Core1
  бібліотечного DEFINE за фізичним D7 ім’ям, а не рядком укр.
  Повертає фізичний T5M результат, не припущення про його ширину. }
function PinnedCore1AddCall(const RepoRoot:String;
  const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var Name,Head,L,R:RawByteString;Names,T:TExactWords;
    I,N:SizeInt;Runtime:TCore1Selektor;
begin
  L:=NumericBits(LeftPhysical);R:=NumericBits(RightPhysical);
  ExtractPinnedAddition(RepoRoot,Name,Head);
  Need((Length(Name)>0) and (Length(Name) mod 7=0),
       'pinned Core1 назва не є D7');
  N:=Length(Name) div 7;
  SetLength(T,N+4);
  T[0]:='10';
  for I:=0 to N-1 do T[I+1]:=Copy(Name,I*7+1,7);
  T[N+1]:=L;T[N+2]:=R;T[N+3]:='01';
  Runtime:=TCore1Selektor.Create(RepoRoot);
  try Result:=Runtime.ExecutePhysicalCall(EncodeT5M(T));
  finally Runtime.Free end;
end;
end.
