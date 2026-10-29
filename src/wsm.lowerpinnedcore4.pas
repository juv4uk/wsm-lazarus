{ G6.130 — перша нативна компіляція СПРАВЖНЬОГО pinned тіла Core4.
  Жодного Pascal-літерала з тілом, SENS закону або текстового dispatch.
  Донор — саме external/sens/lib/core4.sens, Contract 12.0.
  Нижчий кодогенератор — уже злитий wsm.lowerd24. }
unit wsm.lowerpinnedcore4;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ELowerPinnedCore4Error=class(Exception);
function BuildPinnedCore4ELF(const RepoRoot:String;
  const ArgPhysical:RawByteString):RawByteString;
function PinnedCore4PhysicalCall(const RepoRoot:String;
  const ArgPhysical:RawByteString):RawByteString;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.core4runtime,
     wsm.lowerd24,wsm.numericplane,wsm.elfgeometry;

const MaxCore4Bytes=4*1024*1024;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ELowerPinnedCore4Error.Create(Why) end;

{ Borrowed Path, managed owned binary bytes. Файл не читається як UTF-8:
  він мусить бути canonical packed .sens T5M; all exact word widths kept.
  F owns FD, ends at finally. Питання: чому не .lisp? Чому 4 MiB — host
  quota, а не закон? Чому повторно кодуємо T5M? Хто закриває F? }
function ReadCore4(const RepoRoot:String):RawByteString;
var F:TFileStream;Path:String;
begin
  Need(RepoRoot<>'','порожній шлях до pinned Core4');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
        'external/sens/lib/core4.sens';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MaxCore4Bytes),
      'pinned Core4 виходить за фізичну квоту');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ N borrowed TD2Node, а його managed D7-біти принадні Doc.
  Result — послідовність ТОЧНИХ фізичних 7-bit слів, не рядок «укр».
  Питання: чому 7 замість UTF-8? Де перевірено рівно D7?
  Чому невідомий D7 символ не створює новий SENS закон? }
function NameBits(const N:TD2Node):RawByteString;
var I:SizeInt;
begin
  Need((N<>nil) and (N.Kind=dkList) and
    (Length(N.Children)>0) and (Length(N.Children)<=256),
    'очікується обмежений фізичний D7 список імені');
  Result:='';
  for I:=0 to High(N.Children) do begin
    Need((N.Children[I]<>nil) and
      (N.Children[I].Kind=dkIdentity) and
      (N.Children[I].Width=7) and
      (Length(N.Children[I].Bits)=7),
      'ім’я містить не точний D7 glyph');
    Result:=Result+N.Children[I].Bits;
  end;
end;

{ W borrowed original exact source words, N borrowed AST source span.
  Result owned re-encoded T5M section, preserving EVERY bit and width.
  Питання: чому EndWordIndexExclusive напіввідкритий?
  Як виявляється вихід за SourceWords? Чому не друкуємо UTF-8?
  Хто володіє Result після виходу? }
function ExactSpan(const W:TExactWords;const N:TD2Node):RawByteString;
var Part:TExactWords;I,Count:SizeInt;
begin
  Need((N<>nil) and (N.WordIndex>=1) and
    (N.EndWordIndexExclusive>N.WordIndex) and
    (N.EndWordIndexExclusive<=Length(W)+1),
    'AST span виходить за фізичні Core4 слова');
  Count:=N.EndWordIndexExclusive-N.WordIndex;
  SetLength(Part,Count);
  for I:=0 to Count-1 do Part[I]:=W[N.WordIndex-1+I];
  Result:=EncodeT5M(Part);
end;

{ Source: borrowed full canonical packed Core4; Doc owns parsed first
  function's nodes and releases at finally. Форма витягується, НЕ
  переписується: DEFINE/LAMBDA з pinned exact 4-bit heads.
  Body/Param/Name are owned precise physical T5M slices.
  Host runtime independently verifies same binding from same physical pin.
  Питання: де один справжній DEFINE? Чому перевіряємо точний D4?
  Чому BodyName=ParamName — proof для цього профілю, а не SENS registry?
  Де гарантія, що тіло компілюється без модифікації? }
procedure ExtractFirst(const RepoRoot:String;
  out Name,Param,Body:RawByteString);
var Source:RawByteString;W,Prefix:TExactWords;
    Doc:TD2Document;RT:TCore4Runtime;
    Root,Lambda,Params:TD2Node;
    Depth,EndAt,I:SizeInt;N,P,B:RawByteString;
begin
  Name:='';Param:='';Body:='';
  Source:=ReadCore4(RepoRoot);
  DecodeT5M(Source,W);
  Need(EncodeT5M(W)=Source,'pinned Core4 містить неканонічний T5M');
  Need((Length(W)>0) and (W[0]='10'),
    'Core4 не починається D2 викличною формою');
  Depth:=0;EndAt:=-1;
  for I:=0 to High(W) do begin
    if I>=16384 then raise ELowerPinnedCore4Error.Create(
      'перше бібліотечне визначення перевищило квоту');
    if W[I]='10' then Inc(Depth)
    else if W[I]='01' then begin
      Dec(Depth);Need(Depth>=0,'зайве D2 закриття');
      if Depth=0 then begin EndAt:=I;Break end;
    end;
  end;
  Need(EndAt>=0,'незавершений фізичний DEFINE');
  SetLength(Prefix,EndAt+1);
  for I:=0 to EndAt do Prefix[I]:=W[I];
  Doc:=ParseD2WordsWide(Prefix);
  try
    Need(Length(Doc.Roots)=1,'Core4 має не одну першу форму');
    Root:=Doc.Roots[0];
    Need((Root.Kind=dkList) and (Length(Root.Children)=3) and
      (Root.Children[0].Kind=dkIdentity) and
      (Root.Children[0].Width=4) and
      (Root.Children[0].Bits='0011'),
      'перше визначення не є pinned D4 DEFINE');
    Lambda:=Root.Children[2];
    Need((Lambda.Kind=dkList) and (Length(Lambda.Children)=3) and
      (Lambda.Children[0].Kind=dkIdentity) and
      (Lambda.Children[0].Width=4) and
      (Lambda.Children[0].Bits='0010'),
      'бібліотечне визначення не є pinned D4 LAMBDA');
    Params:=Lambda.Children[1];
    Need((Params.Kind=dkList) and (Length(Params.Children)=1),
      'бібліотечне замикання має не один параметр');
    N:=NameBits(Root.Children[1]);
    P:=NameBits(Params.Children[0]);
    B:=NameBits(Lambda.Children[2]);
    Need(P=B,'тіло першого Core4 замикання не збігається з параметром');
    RT:=TCore4Runtime.Create(RepoRoot);
    try
      Need((RT.BindingCount>=1) and RT.BindingIsFunction(0) and
        (RT.FirstDefinitionIdentifier=N),
        'незалежний pinned Core4 runtime не підтвердив визначення');
    finally RT.Free end;
    Name:=ExactSpan(Prefix,Root.Children[1]);
    Param:=ExactSpan(Prefix,Params.Children[0]);
    Body:=ExactSpan(Prefix,Lambda.Children[2]);
  finally Doc.Free end;
end;

{ ArgPhysical borrowed canonical one-word D24. Return owns real ET_EXEC
  machine bytes assembled by EXISTING source-body lowerer, not here.
  Pinned Core4 supplies *both* binding and exact body.
  Питання: чому низький байт exit-code — лише host ABI?
  Де скасовані сторонні widths? Як перевірено ELF?
  Чому це ще не загальний бібліотечний компілятор? }
function BuildPinnedCore4ELF(const RepoRoot:String;
  const ArgPhysical:RawByteString):RawByteString;
var Name,Param,Body:RawByteString;W:TExactWords;
    Num:TExplicitNumeric;G:TELFGeometry;
begin
  DecodeT5M(ArgPhysical,W);
  Need((Length(W)=1) and (Length(W[0])=24) and
       (EncodeT5M(W)=ArgPhysical),
       'потрібен рівно один canonical D24 .sens атом');
  Num:=ReadNumericPhysical(ArgPhysical,24);
  Need((Num.DomainWidth=24) and (Num.ExactBits=W[0]),
       'числовий D24 фізично не допущено');
  ExtractFirst(RepoRoot,Name,Param,Body);
  Result:=LowerBodyELF(Body,Param,ArgPhysical);
  VerifySENSELF64(Result,G);
  Need((G.Kind=2) and (G.Entry=$400000+120) and
       (G.FileBytes=Length(Result)),
       'нижчий компілятор не породив перевірений ELF64 ET_EXEC');
end;

{ Build exact physical (pinned D7 name, D24 atom) D2 call for a separate
  Core4 evaluator; not a precomputed result. Returns owned packed T5M.
  Питання: чому результат виклику перевіряє інший runtime?
  Чому D7 name береться тільки з pinned Core4? Як зберегти width 24? }
function PinnedCore4PhysicalCall(const RepoRoot:String;
  const ArgPhysical:RawByteString):RawByteString;
var Name,Param,Body:RawByteString;N,A,R:TExactWords;
    I,Count:SizeInt;
begin
  DecodeT5M(ArgPhysical,A);
  Need((Length(A)=1) and (Length(A[0])=24) and
       (EncodeT5M(A)=ArgPhysical),'очікується один точний D24 аргумент');
  ExtractFirst(RepoRoot,Name,Param,Body);
  DecodeT5M(Name,N);
  Count:=Length(N);
  SetLength(R,Count+3);
  R[0]:='10';
  for I:=0 to Count-1 do R[I+1]:=N[I];
  R[Count+1]:=A[0];
  R[Count+2]:='01';
  Result:=EncodeT5M(R);
end;
end.
