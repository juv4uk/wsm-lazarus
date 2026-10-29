{ Core1.3: вузьке фізичне замикання ДРУГОГО pinned Core1 визначення.
  Roots[1] з lib/core1.sens (ядро1-третій-елемент у укр-проєкції).
  Виконання тіла делегуємо ІСНУЮЧОМУ TCore4Runtime, не переписуємо закон.
  Це НЕ повний Core1, GC, компілятор чи REPL. }
unit wsm.core1third;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.d2source, wsm.core4runtime;
type
  ECore1ThirdError = class(Exception);
  TCore1ThirdRuntime = class
  private
    FDocument:TD2Document;
    FExecutor:TCore4Runtime;
    FName,FParameter,FOperator:RawByteString;
    function IdentifierKey(Node:TD2Node):RawByteString;
    procedure AdmitSecond(const Node:TD2Node);
  public
    constructor Create(const PinnedSensRoot,WorkspaceRoot:String);
    destructor Destroy; override;
    function SecondIdentifier:RawByteString;
    function ExecutePhysicalCall(const Physical:RawByteString):RawByteString;
  end;
implementation
uses Classes, wsm.t5m;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Condition:Boolean;const MessageText:UnicodeString);
begin
  if not Condition then raise ECore1ThirdError.Create(Ukr(MessageText));
end;

function ReadPinnedCore1(const Root:String):RawByteString;
var Stream:TFileStream; Filename:String;
begin
  Need(Root<>'','не задано корінь pinned SENS');
  Filename:=IncludeTrailingPathDelimiter(ExpandFileName(Root))+
    'lib'+PathDelim+'core1.sens';
  try Stream:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  except on E:Exception do
    raise ECore1ThirdError.Create(Ukr('відсутній фізичний core1.sens: ')+
      E.Message); end;
  try
    Need((Stream.Size>0) and (Stream.Size<=MAX_T5M_FILE_BYTES),
      'фізичний Core1 за межами розміру');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

function TCore1ThirdRuntime.IdentifierKey(Node:TD2Node):RawByteString;
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

{ Друга pinned форма: DEFINE name (LAMBDA (x) (OP x)).
  OP береться з фізичного AST, не з текстової назви. }
procedure TCore1ThirdRuntime.AdmitSecond(const Node:TD2Node);
var Lambda,Args,Body:TD2Node;
begin
  Need((Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)=3),'Core1 друга форма не DEFINE');
  Need((Node.Children[0]<>nil) and
    (Node.Children[0].Kind=dkIdentity) and
    (Node.Children[0].Width=4) and
    (Node.Children[0].Bits='0011'),'Core1 потребує точне D4:0011');
  FName:=IdentifierKey(Node.Children[1]);
  Lambda:=Node.Children[2];
  Need((Lambda<>nil) and (Lambda.Kind=dkList) and
    (Length(Lambda.Children)=3),'Core1 друге значення не LAMBDA');
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
    (Length(Body.Children)=2),'непідтримане тіло другого замикання');
  { Pinned друге DEFINE використовує ратифікований D5:10011
    («третє»), а НЕ D4. Перевіряємо точні біти й ширину з AST,
    жодного dispatch за текстом або довільного host opcode. }
  Need((Body.Children[0]<>nil) and
    (Body.Children[0].Kind=dkIdentity) and
    (Body.Children[0].Width=5) and
    (Body.Children[0].Bits='10011'),
    'тіло другого замикання потребує точне D5:10011');
  Need(IdentifierKey(Body.Children[1])=FParameter,
    'тіло другого замикання не посилається на свій параметр');
  FOperator:=Body.Children[0].Bits;
end;

constructor TCore1ThirdRuntime.Create(
  const PinnedSensRoot,WorkspaceRoot:String);
var Physical:RawByteString; Words:TExactWords;
begin
  inherited Create;
  FDocument:=nil;FExecutor:=nil;
  try
    Physical:=ReadPinnedCore1(PinnedSensRoot);
    try DecodeT5M(Physical,Words);
    except on E:Exception do
      raise ECore1ThirdError.Create(Ukr('хибний pinned Core1 T5M: ')+E.Message); end;
    Need(EncodeT5M(Words)=Physical,'core1.sens не є канонічним T5M');
    FDocument:=ParseD2WordsWide(Words);
    Need(Length(FDocument.Roots)>=2,'фізичний Core1 без другого визначення');
    AdmitSecond(FDocument.Roots[1]);
    FExecutor:=TCore4Runtime.Create(WorkspaceRoot);
  except
    FreeAndNil(FExecutor);FreeAndNil(FDocument);
    raise;
  end;
end;

destructor TCore1ThirdRuntime.Destroy;
begin
  FExecutor.Free;
  FDocument.Free;
  inherited Destroy;
end;

function TCore1ThirdRuntime.SecondIdentifier:RawByteString;
begin Result:=FName end;

function TCore1ThirdRuntime.ExecutePhysicalCall(
  const Physical:RawByteString):RawByteString;
var Words,Bridge:TExactWords; Doc:TD2Document;
    Call,Argument:TD2Node; StartAt,AfterAt,I,N:SizeInt;
begin
  Result:='';Doc:=nil;
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
    'порожній або завеликий фізичний виклик Core1');
  try DecodeT5M(Physical,Words);
  except on E:Exception do
    raise ECore1ThirdError.Create(Ukr('хибний T5M виклику: ')+E.Message); end;
  Need((Length(Words)>0) and (Length(Words)<=4096),
    'перевищена фізична межа виклику Core1');
  try Doc:=ParseD2WordsWide(Words);
  except on E:Exception do
    raise ECore1ThirdError.Create(Ukr('хибний D2 виклику: ')+E.Message); end;
  try
    Need(Length(Doc.Roots)=1,'Core1 очікує один фізичний корінь');
    Call:=Doc.Roots[0];
    Need((Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)=2),
      'Core1 очікує виклик замикання з одним аргументом');
    Need(IdentifierKey(Call.Children[0])=FName,
      'невідомий exact D7 ідентифікатор другого Core1 замикання');
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
    Bridge[1]:=FOperator;
    for I:=0 to N-1 do Bridge[I+2]:=Words[StartAt+I];
    Bridge[High(Bridge)]:='01';
    Result:=FExecutor.ExecutePhysicalCall(EncodeT5M(Bridge));
  finally
    Doc.Free;
  end;
end;
end.
