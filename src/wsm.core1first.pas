{ Core1.2 — виконання ПЕРШОГО pinned Core1 DEFINE через наявний D4 runtime.
  Бібліотечне тіло не переписане на Pascal. Лише фізичне зв'язування
  однієї D7-змінної із аргументом і передача обчислення wsm.core4runtime.
  Це вузький замкнений виклик, НЕ загальні lexical closures, REPL або GC. }
unit wsm.core1first;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  ECore1FirstError=class(Exception);
  TCore1First=class
  private
    FDoc:TObject; { фактично TD2Document; належить цьому об'єкту }
    FRuntime:TObject; { фактично TCore4Runtime; чинний D4 evaluator }
    FName,FParameter,FSelector:RawByteString;
  public
    constructor Create(const AuthorityRoot,PhysicalCore1Path:String);
    destructor Destroy;override;
    function PhysicalName:RawByteString;
    function ExecutePhysical(const FullD7Name,PhysicalArgument:RawByteString):RawByteString;
  end;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.domain,wsm.bind,
  wsm.core4runtime;

function Require(Valid:Boolean;const Reason:String):Boolean;
begin
  if not Valid then raise ECore1FirstError.Create(Reason);
  Result:=True;
end;

{ Вхід — фізичний файл pinned blob, який матеріалізує host зі строго
  встановленого gitlink. Результат — owned RawByteString bytes T5M.
  Питання: хто звільняє F? Чому не читаємо людський .lisp?
  Що трапиться за часткового читання? }
function ReadBounded(const Path:String):RawByteString;
const Limit=4*1024*1024;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Require((F.Size>0) and (F.Size<=Limit),
      'Core1: файл не вкладається в фізичну межу');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function D7Key(Node:TD2Node;const Tables:TDomainSet):RawByteString;
var I:SizeInt; Key:TDomainKey;
begin
  Require((Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=256),
    'Core1: очікувалася обмежена точна D7-послідовність');
  Result:='';
  for I:=0 to High(Node.Children) do begin
    Require((Node.Children[I]<>nil) and
      (Node.Children[I].Kind=dkIdentity) and
      (Node.Children[I].Width=7),
      'Core1: ідентифікатор не має точного D7');
    Key:=ExactKey(Node.Children[I].Bits);
    Require((Key.Bits<Length(Tables[7])) and
      SameKey(Key,Tables[7][Key.Bits].Key),
      'Core1: ідентифікатор поза pinned D7');
    Result:=Result+Node.Children[I].Bits;
  end;
end;

procedure RequireD4(Node:TD2Node;const Bits:RawByteString;
  const Tables:TDomainSet);
var K:TDomainKey;
begin
  Require((Node<>nil) and (Node.Kind=dkIdentity) and
    (Node.Width=4) and (Node.Bits=Bits),
    'Core1: неузгоджена точна D4 координата');
  K:=ExactKey(Node.Bits);
  Require((K.Bits<Length(Tables[4])) and
    SameKey(K,Tables[4][K.Bits].Key),'Core1: немає pinned D4 ключа');
end;

{ Constructor приймає canonical physical Core1, а не людські DEFINE.
  FDoc володіє всім D2 AST на весь час життя цього вузького замикання.
  Ім'я/параметр — повні exact D7-послідовності, не Unicode і не lookup
  за написанням. Тіло залишається вузлом pinned документа.
  Запитання: чому D7:0101001 не синтаксис? Чому перевіряємо всю T5M?
  Який компонент дійсно виконує D4:1001? Де межа GC? }
constructor TCore1First.Create(const AuthorityRoot,PhysicalCore1Path:String);
var
  Bytes,Repacked:RawByteString;
  Words:TExactWords;
  D:TD2Document;
  R,L,Params,Body:TD2Node;
  Domains:TDomainSet;
begin
  inherited Create;
  FDoc:=nil;FRuntime:=nil;
  D:=nil;
  try
    LoadPinnedDomains(RawByteString(IncludeTrailingPathDelimiter(AuthorityRoot)+
      'external/sens'),Domains);
    Bytes:=ReadBounded(PhysicalCore1Path);
    DecodeT5M(Bytes,Words);
    Repacked:=EncodeT5M(Words);
    Require(Repacked=Bytes,'Core1: фізичний T5M не канонічний');
    D:=ParseD2WordsWide(Words);
    Require(Length(D.Roots)>0,'Core1: немає фізичних коренів');
    R:=D.Roots[0];
    Require((R.Kind=dkList) and (Length(R.Children)=3),
      'Core1: перший DEFINE не має трьох полів');
    RequireD4(R.Children[0],'0011',Domains);
    FName:=D7Key(R.Children[1],Domains);
    L:=R.Children[2];
    Require((L<>nil) and (L.Kind=dkList) and
      (Length(L.Children)=3),'Core1: відсутня LAMBDA');
    RequireD4(L.Children[0],'0010',Domains);
    Params:=L.Children[1];
    Require((Params<>nil) and (Params.Kind=dkList) and
      (Length(Params.Children)=1),'Core1: не один параметр');
    FParameter:=D7Key(Params.Children[0],Domains);
    Body:=L.Children[2];
    Require((Body<>nil) and (Body.Kind=dkList) and
      (Length(Body.Children)=2),'Core1: тіло першої функції не виконуване');
    RequireD4(Body.Children[0],'1001',Domains);
    Require(D7Key(Body.Children[1],Domains)=FParameter,
      'Core1: тіло не посилається на захоплений параметр');
    FSelector:=Body.Children[0].Bits;
    { Єдиний чинний виконавець D4:1001 — уже злитий FPC runtime.
      Його залежність від початкового Core4 є ТИМЧАСОВИМ вузьким
      механізмом і не означає, що Core1 семантично походить від Core4. }
    FRuntime:=TCore4Runtime.Create(AuthorityRoot);
    FDoc:=D;D:=nil;
  except
    D.Free;
    FRuntime.Free;FRuntime:=nil;
    raise;
  end;
end;

destructor TCore1First.Destroy;
begin
  FRuntime.Free;
  FDoc.Free;
  inherited Destroy;
end;

function TCore1First.PhysicalName:RawByteString;
begin Result:=FName end;

{ Caller передає borrowed packed T5M D4:1110 expression.
  Замикання зв'язує лише exact D7 параметр, а не інтерпретує
  українське/англійське ім'я. Нові слова — own dynamic array;
  єдиний результат — вже обчислений wsm.core4runtime packed T5M.
  Питання: чому зміна одного біта імені блокує виклик? Хто
  обчислює selector? Чому W24 тут не арифметичне число?
  Чому не вважаємо це загальним Core1 evaluator? }
function TCore1First.ExecutePhysical(
  const FullD7Name,PhysicalArgument:RawByteString):RawByteString;
var
  Values,Call:TExactWords;
  Argument:TD2Document;
  Root:TD2Node;
  I:SizeInt;
begin
  Result:='';
  Require((FullD7Name<>'') and (FullD7Name=FName),
    'Core1: невідоме точне D7 ім’я замикання');
  Require((Length(PhysicalArgument)>0) and
    (Length(PhysicalArgument)<=65536),
    'Core1: фізичний аргумент поза межею');
  DecodeT5M(PhysicalArgument,Values);
  Require(EncodeT5M(Values)=PhysicalArgument,
    'Core1: фізичний аргумент неканонічний');
  Argument:=ParseD2WordsWide(Values);
  try
    Require(Length(Argument.Roots)=1,'Core1: очікується рівно один аргумент');
    Root:=Argument.Roots[0];
    Require((Root<>nil) and (Root.Kind=dkList) and
      (Length(Root.Children)>=1),'Core1: очікується D4 конструктор списку');
    Require((Root.Children[0]<>nil) and
      (Root.Children[0].Kind=dkIdentity) and
      (Root.Children[0].Width=4) and
      (Root.Children[0].Bits='1110'),
      'Core1: аргумент не є D4:1110');
    { Жодного допуску D4:1110 лише зі spelling або width:
      остаточний фізичний admission виконує наявний runtime. }
    SetLength(Call,Length(Values)+3);
    Call[0]:='10';
    Call[1]:=FSelector; { із pinned фізичного тіла Core1, НЕ Pascal копія }
    for I:=0 to High(Values) do Call[I+2]:=Values[I];
    Call[High(Call)]:='01';
    Result:=TCore4Runtime(FRuntime).ExecutePhysicalCall(EncodeT5M(Call));
  finally Argument.Free end;
end;
end.
