{ Core1.2: вузьке фізичне замикання ПЕРШОГО pinned Core1 визначення.
  Справжній D4:0011/D4:0010/D7 читаємо з lib/core1.sens.
  Виконання точного тіла D4:1001 делегуємо ІСНУЮЧОМУ evaluator,
  не переписуємо закон вибірки й не створюємо нового SENS registry.
  Зараз це НЕ повний Core1, GC, компілятор чи REPL. }
unit wsm.core1first;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.d2source, wsm.core4runtime;
type
  ECore1FirstError = class(Exception);
  TCore1FirstRuntime = class
  private
    FDocument:TD2Document;       { owned: перший і решта фізичних AST }
    FExecutor:TCore4Runtime;    { owned: чинний механізм D4 селекторів }
    FName,FParameter,FOperator:RawByteString;
    function IdentifierKey(Node:TD2Node):RawByteString;
    procedure AdmitFirst(const Node:TD2Node);
  public
    constructor Create(const PinnedSensRoot,WorkspaceRoot:String);
    destructor Destroy; override;
    function FirstIdentifier:RawByteString;
    function ExecutePhysicalCall(const Physical:RawByteString):RawByteString;
  end;
implementation
uses Classes, wsm.t5m;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Condition:Boolean;const MessageText:UnicodeString);
begin
  if not Condition then raise ECore1FirstError.Create(Ukr(MessageText));
end;

function ReadPinnedCore1(const Root:String):RawByteString;
var Stream:TFileStream; Filename:String;
begin
  Need(Root<>'','не задано корінь pinned SENS');
  Filename:=IncludeTrailingPathDelimiter(ExpandFileName(Root))+
    'lib'+PathDelim+'core1.sens';
  try Stream:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  except on E:Exception do
    raise ECore1FirstError.Create(Ukr('відсутній фізичний core1.sens: ')+
      E.Message); end;
  try
    Need((Stream.Size>0) and (Stream.Size<=MAX_T5M_FILE_BYTES),
      'фізичний Core1 за межами розміру');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

{ Власник вузлів — FDocument; ключ копіюється (RawByteString).
  D7 — послідовність точних семибітних слів, НЕ написання і не opcode.
  Питання: чому D7 не визначає закон? Чому 7 біт не дорівнюють числу?
  Хто звільняє вузли? Де зберігається фізичний зв'язок? }
function TCore1FirstRuntime.IdentifierKey(Node:TD2Node):RawByteString;
var I:SizeInt;
begin
  Need((Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=256),
    'очікувана точна D7-послідовність');
  Result:='';
  for I:=0 to High(Node.Children) do begin
    Need((Node.Children[I]<>nil) and
      (Node.Children[I].Kind=dkIdentity) and
      (Node.Children[I].Width=7),
      'недійсна фізична D7-координата ідентифікатора');
    Result:=Result+Node.Children[I].Bits;
  end;
end;

{ Приймаємо лише першу pinned форму (DEFINE name (LAMBDA (x) (D4:1001 x))).
  Це вузький admission до ВЖЕ НАЯВНОГО фізичного D4:1001 evaluator.
  Тіло не створюється з тексту/host-імені: FOperator береться з AST.
  Непідтримане або підмінене тіло явно відхиляється. }
procedure TCore1FirstRuntime.AdmitFirst(const Node:TD2Node);
var Lambda,Args,Body:TD2Node;
begin
  Need((Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)=3),'Core1 перша форма не DEFINE');
  Need((Node.Children[0]<>nil) and
    (Node.Children[0].Kind=dkIdentity) and
    (Node.Children[0].Width=4) and
    (Node.Children[0].Bits='0011'),'Core1 потребує точне D4:0011');
  FName:=IdentifierKey(Node.Children[1]);
  Lambda:=Node.Children[2];
  Need((Lambda<>nil) and (Lambda.Kind=dkList) and
    (Length(Lambda.Children)=3),'Core1 перше значення не LAMBDA');
  Need((Lambda.Children[0]<>nil) and
    (Lambda.Children[0].Kind=dkIdentity) and
    (Lambda.Children[0].Width=4) and
    (Lambda.Children[0].Bits='0010'),'Core1 потребує точне D4:0010');
  Args:=Lambda.Children[1];
  Need((Args<>nil) and (Args.Kind=dkList) and
    (Length(Args.Children)=1),'потрібен рівно один лексичний параметр');
  FParameter:=IdentifierKey(Args.Children[0]);
  Body:=Lambda.Children[2];
  Need((Body<>nil) and (Body.Kind=dkList) and
    (Length(Body.Children)=2),'непідтримане тіло першого замикання');
  Need((Body.Children[0]<>nil) and
    (Body.Children[0].Kind=dkIdentity) and
    (Body.Children[0].Width=4) and
    (Body.Children[0].Bits='1001'),
    'поки підтримано лише pinned D4:1001 як тіло');
  Need(IdentifierKey(Body.Children[1])=FParameter,
    'тіло першого замикання не посилається на свій параметр');
  FOperator:=Body.Children[0].Bits;
end;

constructor TCore1FirstRuntime.Create(
  const PinnedSensRoot,WorkspaceRoot:String);
var Physical:RawByteString; Words:TExactWords;
begin
  inherited Create;
  FDocument:=nil;FExecutor:=nil;
  try
    Physical:=ReadPinnedCore1(PinnedSensRoot);
    try DecodeT5M(Physical,Words);
    except on E:Exception do
      raise ECore1FirstError.Create(Ukr('хибний pinned Core1 T5M: ')+E.Message); end;
    Need(EncodeT5M(Words)=Physical,'core1.sens не є канонічним T5M');
    FDocument:=ParseD2WordsWide(Words);
    Need(Length(FDocument.Roots)>0,'фізичний Core1 без визначень');
    AdmitFirst(FDocument.Roots[0]);
    { Повторно використовуємо тільки поточний перевірений FPC evaluator
      D4, без місцевого виконання CAR/CDR або бібліотечних DEFINE.
      Перший Core1 closure зберігається тут, не в Core4. }
    FExecutor:=TCore4Runtime.Create(WorkspaceRoot);
  except
    FreeAndNil(FExecutor);FreeAndNil(FDocument);
    raise;
  end;
end;

destructor TCore1FirstRuntime.Destroy;
begin
  FExecutor.Free;
  FDocument.Free;
  inherited Destroy;
end;

function TCore1FirstRuntime.FirstIdentifier:RawByteString;
begin Result:=FName end;

{ Physical: borrowed packed T5M; локальні Words/Doc/Bridge owned до finally.
  FDocument живе разом із closure; FExecutor єдиний реальний evaluator.
  Результат — новий packed T5M RawByteString без часткового виводу.
  Лише одне ім'я, один аргумент — вже перевірене D4:1110-вираження.
  Питання: чому не декодуємо D12+? Чому не підставляємо назву тіла?
  Де гарантія точного D4? Хто звільняє Doc? Чому це не загальний REPL? }
function TCore1FirstRuntime.ExecutePhysicalCall(
  const Physical:RawByteString):RawByteString;
var Words,Bridge:TExactWords; Doc:TD2Document;
    Call,Argument:TD2Node; StartAt,AfterAt,I,N:SizeInt;
begin
  Result:='';Doc:=nil;
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
    'порожній або завеликий фізичний виклик Core1');
  try DecodeT5M(Physical,Words);
  except on E:Exception do
    raise ECore1FirstError.Create(Ukr('хибний T5M виклику: ')+E.Message); end;
  Need((Length(Words)>0) and (Length(Words)<=4096),
    'перевищена фізична межа виклику Core1');
  try Doc:=ParseD2WordsWide(Words);
  except on E:Exception do
    raise ECore1FirstError.Create(Ukr('хибний D2 виклику: ')+E.Message); end;
  try
    Need(Length(Doc.Roots)=1,'Core1 очікує один фізичний корінь');
    Call:=Doc.Roots[0];
    Need((Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)=2),
      'Core1 очікує виклик замикання з одним аргументом');
    Need(IdentifierKey(Call.Children[0])=FName,
      'невідомий exact D7 ідентифікатор Core1 замикання');
    Argument:=Call.Children[1];
    Need((Argument<>nil) and (Argument.Kind=dkList),
      'потрібен фізичний список-аргумент');
    Need((Length(Argument.Children)>0) and
      (Argument.Children[0]<>nil) and
      (Argument.Children[0].Kind=dkIdentity) and
      (Argument.Children[0].Width=4) and
      (Argument.Children[0].Bits='1110'),
      'цей зріз приймає лише точний D4:1110 список');
    StartAt:=Argument.WordIndex-1;
    AfterAt:=Argument.EndWordIndexExclusive-1;
    Need((StartAt>=0) and (AfterAt>StartAt) and
      (AfterAt<=Length(Words)),'пошкоджений фізичний інтервал аргумента');
    N:=AfterAt-StartAt;
    Need(N+3<=4096,'перевищено межу тіла замикання Core1');
    SetLength(Bridge,N+3);
    Bridge[0]:='10';
    Bridge[1]:=FOperator; { З ПОТОЧНОГО фізичного pinned тіла, не константа }
    for I:=0 to N-1 do Bridge[I+2]:=Words[StartAt+I];
    Bridge[High(Bridge)]:='01';
    { Один дійсний шлях виконання D4, відпрацьований на Core4.
      Перевірку аргументів і точне повернення робить цей evaluator. }
    Result:=FExecutor.ExecutePhysicalCall(EncodeT5M(Bridge));
  finally
    Doc.Free;
  end;
end;
end.
