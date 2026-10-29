{ Core1.3: перше виконання pinned фізичного Core1.
  Жодне бібліотечне DEFINE не переписане на Pascal.
  Фактичне D4:1001 виконує лише вже перевірений wsm.core4runtime. }
program senscore1vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d2source,wsm.core4runtime;

type ECore1First=class(Exception);
  TCore1First=class
  private
    FDoc:TD2Document;
    FEngine:TCore4Runtime;
    FName,FParameter,FBody:RawByteString;
    function NameKey(N:TD2Node):RawByteString;
    procedure AdmitFirst(N:TD2Node);
  public
    constructor Create(const Root:String);
    destructor Destroy;override;
    function Apply(const Physical:RawByteString):RawByteString;
  end;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ECore1First.Create(Why) end;
function ReadFile(const Path:String;MaxBytes:Int64):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=1) and (F.Size<=MaxBytes),'порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
function Exact(N:TD2Node;W:SizeInt;const B:RawByteString):Boolean;
begin
  Result:=(N<>nil) and (N.Kind=dkIdentity) and
    (N.Width=W) and (N.Bits=B);
end;
{ Набір точних D7 W7 слів з уже допущеного фізичного AST.
  Результат власний RawByteString; вузол позичений з FDoc.
  Питання: чому utf8 назва не є викличним ключем?
  Чому провідні нулі зберігаємо? Хто звільняє FDoc? }
function TCore1First.NameKey(N:TD2Node):RawByteString;
var I:SizeInt;
begin
  Result:='';
  Need((N<>nil) and (N.Kind=dkList),'потрібна D7-послідовність');
  Need((Length(N.Children)>0) and (Length(N.Children)<=256),
    'неприпустима довжина D7-імені');
  for I:=0 to High(N.Children) do begin
    Need((N.Children[I]<>nil) and
      (N.Children[I].Kind=dkIdentity) and (N.Children[I].Width=7),
      'ідентифікатор містить не-D7 слово');
    Result:=Result+N.Children[I].Bits;
  end;
end;
{ Перший DEFINE міститься тільки у pinned core1.sens; зберігаємо
  її точне тіло й параметр. Ніяких евристик за проєкцією укр.
  Питання: чому D4:1001 не встановлюється за назвою?
  Чому параметр має збігатися з тілом?
  Чому невідома форма відхиляється, а не інтерпретується? }
procedure TCore1First.AdmitFirst(N:TD2Node);
var L,P,B:TD2Node;
begin
  Need((N<>nil) and (N.Kind=dkList) and
    (Length(N.Children)=3),'перше DEFINE не трипольове');
  Need(Exact(N.Children[0],4,'0011'),'не точний D4:0011 DEFINE');
  FName:=NameKey(N.Children[1]);
  L:=N.Children[2];
  Need((L<>nil) and (L.Kind=dkList) and
    (Length(L.Children)=3),'не трипольова LAMBDA');
  Need(Exact(L.Children[0],4,'0010'),'не точний D4:0010 LAMBDA');
  P:=L.Children[1];
  Need((P<>nil) and (P.Kind=dkList) and
    (Length(P.Children)=1),'не одна лексична змінна');
  FParameter:=NameKey(P.Children[0]);
  B:=L.Children[2];
  Need((B<>nil) and (B.Kind=dkList) and
    (Length(B.Children)=2),'тіло поза першим Core1 зрізом');
  Need(Exact(B.Children[0],4,'1001'),'тіло не D4:1001');
  Need(NameKey(B.Children[1])=FParameter,
    'тіло звертається не до зв’язаного параметра');
  FBody:=B.Children[0].Bits;
end;
constructor TCore1First.Create(const Root:String);
var P:RawByteString; W:TExactWords;
begin
  inherited Create;FDoc:=nil;FEngine:=nil;
  try
    Need(Root<>'','відсутній pinned корінь');
    P:=ReadFile(IncludeTrailingPathDelimiter(ExpandFileName(Root))+
      'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim+'core1.sens',
      MAX_T5M_FILE_BYTES);
    DecodeT5M(P,W);
    Need((Length(W)>0) and (EncodeT5M(W)=P),'Core1 T5M неканонічний');
    FDoc:=ParseD2WordsWide(W);
    Need(Length(FDoc.Roots)>0,'порожній фізичний Core1');
    AdmitFirst(FDoc.Roots[0]);
    FEngine:=TCore4Runtime.Create(Root,4096);
  except
    FreeAndNil(FDoc);FreeAndNil(FEngine);raise;
  end;
end;
destructor TCore1First.Destroy;
begin FEngine.Free;FDoc.Free;inherited Destroy end;
{ Аргумент: один канонічний фізичний D4:1110 список атомів.
  Копіюємо лише Wn слова у справжнє тіло замикання D4:1001:
  (точне-тіло <значення-аргумент>). Делегуємо виконання тому самому
  нативному D4-механізму Core4, НЕ реалізуємо selector у Pascal.
  Result — власні canonical packed T5M байти після повної перевірки.
  Питання: чому не можна друкувати результат до повного допуску?
  Чому обмежуємо фізичний розмір?
  Чому при помилці звільняється AST у finally? }
function TCore1First.Apply(const Physical:RawByteString):RawByteString;
var W,Call,R:TExactWords;D,Reply:TD2Document;I:SizeInt;N:TD2Node;
begin
  Result:='';D:=nil;Reply:=nil;
  Need((Length(Physical)>=1) and (Length(Physical)<=65536),
    'аргумент має містити 1..65536 T5M байтів');
  DecodeT5M(Physical,W);
  Need((Length(W)<=3000) and (EncodeT5M(W)=Physical),
    'не канонічний або завеликий фізичний аргумент');
  D:=ParseD2WordsWide(W);
  try
    Need(Length(D.Roots)=1,'потрібен один корінь аргументу');
    N:=D.Roots[0];
    Need((N<>nil) and (N.Kind=dkList) and
      (Length(N.Children)>=3) and Exact(N.Children[0],4,'1110'),
      'потрібний D4:1110 конструктор двох або більше значень');
    for I:=1 to High(N.Children) do
      Need((N.Children[I]<>nil) and ((N.Children[I].Kind=dkIdentity) or
         (N.Children[I].Kind=dkEmpty)),
        'у цьому зрізі допустимі лише точні атоми або порожній D3');
    SetLength(Call,Length(W)+3);
    Call[0]:='10';Call[1]:=FBody;
    for I:=0 to High(W) do Call[I+2]:=W[I];
    Call[High(Call)]:='01';
    Result:=FEngine.ExecutePhysicalCall(EncodeT5M(Call));
    DecodeT5M(Result,R);
    Need(EncodeT5M(R)=Result,'ненормативна T5M відповідь');
    Reply:=ParseD2WordsWide(R);
    Need(Length(Reply.Roots)=1,'виконавець повернув не один корінь');
  finally
    Reply.Free;D.Free;
  end;
end;
var Engine:TCore1First;Input,Answer:RawByteString;OutFile:THandleStream;Path:String;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>
     #$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$2D#$D0#$BF#$D0#$B5#$D1#$80#$D1#$88#$D0#$B8#$D0#$B9) then begin
    WriteLn(StdErr,'Використання: senscore1vykon --виконати-перший КОРІНЬ аргумент.sens');
    Halt(64);
  end;
  Path:=ParamStr(3);
  if LowerCase(ExtractFileExt(Path))<>'.sens' then begin
    WriteLn(StdErr,'CORE1-ВІДМОВА: потрібен фізичний .sens');
    Halt(64);
  end;
  Engine:=nil;
  try
    Engine:=TCore1First.Create(ParamStr(2));
    Input:=ReadFile(Path,65536);
    Answer:=Engine.Apply(Input);
    Need(Length(Answer)>0,'порожній результат виконання');
    OutFile:=THandleStream.Create(TextRec(Output).Handle);
    try OutFile.WriteBuffer(Answer[1],Length(Answer))
    finally OutFile.Free end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'CORE1-ВІДМОВА: ',E.Message);
      FreeAndNil(Engine);Halt(2);
    end;
  end;
  Engine.Free;
end.
