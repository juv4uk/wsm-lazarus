{ G4.8: вузький завантажувач canonical Core4 binary.
  Піднімає перші три DEFINE з pinned core4.sens: замикання та два атоми.
  Немає бібліотечних визначень у Pascal і dispatch за поверхневими назвами. }
unit wsm.core4runtime;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.d2source;
type
  ECore4RuntimeError = class(Exception);
  TCore4Binding = record
    NameKey, ParameterKey, BodyKey, ValueBits: RawByteString;
    ValueWidth: SizeInt;
    IsFunction: Boolean;
  end;
  TCore4Bindings = array of TCore4Binding;
  TCore4Runtime = class
  private
    FDefinition: TD2Document;
    FBindings: TCore4Bindings;
    FMaxCallWords: SizeInt;
    function IsIdentifierSequence(Node: TD2Node): Boolean;
    function IdentifierKey(Node: TD2Node): RawByteString;
    function FindBinding(const NameKey: RawByteString): SizeInt;
    procedure AdmitDefinition(const Root: TD2Node; out Binding: TCore4Binding);
  public
    constructor Create(const RepoRoot: String; MaxCallWords: SizeInt=4096);
    destructor Destroy; override;
    { Значення/виклик надходить фізичним T5M .sens, не з .lisp.
      Вихід — T5M exact атома з Core4 або аргумента замикання. }
    function ExecutePhysicalCall(const Physical: RawByteString): RawByteString;
    { Діагностичний доступ до exact D7 sequence, без текстової проєкції. }
    function FirstDefinitionIdentifier: RawByteString;
    function BindingIdentifier(Index: SizeInt): RawByteString;
    function BindingCount: SizeInt;
  end;
implementation
uses Classes, wsm.t5m, wsm.domain, wsm.physloc;

{ Внутрішній host-виняток не є новим станом чи законом SENS.
  WordIndex — фізичне 1-based слово НАЙГЛИБШОГО відхиленого D2-вузла. }
type
  ECore4NodeError=class(ECore4RuntimeError)
    WordIndex:SizeInt;
    constructor CreateAt(const MessageText:String; AWordIndex:SizeInt);
  end;

constructor ECore4NodeError.CreateAt(const MessageText:String;
  AWordIndex:SizeInt);
begin
  inherited Create(MessageText);
  WordIndex:=AWordIndex;
end;

{ Напіввідкриті інтервали тритів точні навіть якщо слова ділять байт.
  EOF фізично має нульову тритову та байтову довжину. }
function PhysicalPositionText(const At:TPhysicalWordSpan):String;
var EOFName:String;
begin
  if At.IsEOF then EOFName:='так' else EOFName:='ні';
  Result:=' слово='+IntToStr(At.WordIndex)+
    ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+')'+
    ' байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')'+
    ' EOF='+EOFName;
end;

const
  Core4BinaryLimit = 4 * 1024 * 1024;
  MaxFirstFormWords = 16384;
  Core4InitialForms = 3;
  MaxIdentifierGlyphs = 256;

function ReadPhysicalCore4(const RepoRoot: String): RawByteString;
var F: TFileStream; Path: String;
begin
  if RepoRoot='' then raise ECore4RuntimeError.Create('порожній корінь репозиторію');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+ 'external' +
    PathDelim + 'sens' + PathDelim + 'lib' + PathDelim + 'core4.sens';
  try F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  except on E:Exception do
    raise ECore4RuntimeError.Create('немає pinned Core4 .sens: '+E.Message); end;
  try
    if (F.Size<1) or (F.Size>Core4BinaryLimit) then
      raise ECore4RuntimeError.Create('розмір Core4 .sens поза межею');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function InitialFormWords(const Words:TExactWords):TExactWords;
var I,Depth,Forms,Finish:SizeInt;
begin
  Result:=nil;
  if (Length(Words)=0) or (Words[0]<>'10') then
    raise ECore4RuntimeError.Create('перші Core4-форми не починаються D2-відкриттям');
  Depth:=0; Forms:=0; Finish:=-1;
  for I:=0 to High(Words) do begin
    if I>=MaxFirstFormWords then
      raise ECore4RuntimeError.Create('початкові Core4-форми перевищили межу слів');
    if Words[I]='10' then Inc(Depth)
    else if Words[I]='01' then begin
      Dec(Depth);
      if Depth<0 then raise ECore4RuntimeError.Create('зайве D2-закриття Core4');
      if Depth=0 then begin
        Inc(Forms);
        if Forms=Core4InitialForms then begin Finish:=I; Break end;
      end;
    end;
  end;
  if Finish<0 then raise ECore4RuntimeError.Create('немає трьох повних початкових форм Core4');
  SetLength(Result,Finish+1);
  for I:=0 to Finish do Result[I]:=Words[I];
end;

function TCore4Runtime.IdentifierKey(Node:TD2Node):RawByteString;
var I:SizeInt;
begin
  Result:='';
  if (Node=nil) or (Node.Kind<>dkList) or (Length(Node.Children)<1) or
     (Length(Node.Children)>MaxIdentifierGlyphs) then
    raise ECore4RuntimeError.Create('очікувалася обмежена D7-послідовність ідентифікатора');
  for I:=0 to High(Node.Children) do begin
    if (Node.Children[I]=nil) or (Node.Children[I].Kind<>dkIdentity) or
       (Node.Children[I].Width<>7) then
      raise ECore4RuntimeError.Create('ідентифікатор має містити точні D7-слова');
    Result:=Result+Node.Children[I].Bits;
  end;
end;

function TCore4Runtime.IsIdentifierSequence(Node:TD2Node):Boolean;
var I:SizeInt;
begin
  Result:=(Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=MaxIdentifierGlyphs);
  if not Result then Exit;
  for I:=0 to High(Node.Children) do
    if (Node.Children[I]=nil) or (Node.Children[I].Kind<>dkIdentity) or
       (Node.Children[I].Width<>7) then Exit(False);
  Result:=True;
end;

procedure TCore4Runtime.AdmitDefinition(const Root:TD2Node;
  out Binding:TCore4Binding);
var Lambda,Params:TD2Node;
begin
  Binding:=Default(TCore4Binding);
  if (Root=nil) or (Root.Kind<>dkList) or (Length(Root.Children)<>3) then
    raise ECore4RuntimeError.Create('перша форма Core4 не є підтриманим DEFINE');
  if (Root.Children[0].Kind<>dkIdentity) or
     (Root.Children[0].Width<>4) or (Root.Children[0].Bits<>'0011') then
    raise ECore4RuntimeError.Create('перша форма Core4 не має exact D4 DEFINE');
  Binding.NameKey:=IdentifierKey(Root.Children[1]);
  Lambda:=Root.Children[2];
  if (Lambda<>nil) and (Lambda.Kind=dkList) and
     (Length(Lambda.Children)=3) and (Lambda.Children[0]<>nil) and
     (Lambda.Children[0].Kind=dkIdentity) and
     (Lambda.Children[0].Width=4) and (Lambda.Children[0].Bits='0010') then begin
    Params:=Lambda.Children[1];
    if (Params.Kind<>dkList) or (Length(Params.Children)<>1) then
      raise ECore4RuntimeError.Create('підтримується лише один обов’язковий параметр');
    Binding.IsFunction:=True;
    Binding.ParameterKey:=IdentifierKey(Params.Children[0]);
    Binding.BodyKey:=IdentifierKey(Lambda.Children[2]);
    Exit;
  end;
  { Початкові атомні глобали з Core4 залишаються exact opaque words.
    Їхній закон і роль не виводяться з ширини або payload. }
  if (Lambda=nil) or (Lambda.Kind<>dkIdentity) then
    raise ECore4RuntimeError.Create('DEFINE має непідтримане початкове значення Core4');
  Binding.IsFunction:=False;
  Binding.ValueWidth:=Lambda.Width;
  Binding.ValueBits:=Lambda.Bits;
end;

function TCore4Runtime.FindBinding(const NameKey:RawByteString):SizeInt;
var I:SizeInt;
begin
  for I:=0 to High(FBindings) do
    if FBindings[I].NameKey=NameKey then Exit(I);
  Result:=-1;
end;

constructor TCore4Runtime.Create(const RepoRoot:String; MaxCallWords:SizeInt);
var Physical:RawByteString; AllWords,Prefix:TExactWords; Parsed:TD2Document;
    I,N:SizeInt; Item:TCore4Binding;
begin
  inherited Create;
  FDefinition:=nil; SetLength(FBindings,0);
  if (MaxCallWords<1) or (MaxCallWords>MaxD2Words) then
    raise ECore4RuntimeError.Create('неприпустима межа фізичного виклику');
  FMaxCallWords:=MaxCallWords;
  Physical:=ReadPhysicalCore4(RepoRoot);
  try DecodeT5M(Physical,AllWords);
  except on E:Exception do raise ECore4RuntimeError.Create('Core4 T5M відхилено: '+E.Message); end;
  Prefix:=InitialFormWords(AllWords);
  Parsed:=ParseD2WordsWide(Prefix);
  if Length(Parsed.Roots)<>Core4InitialForms then begin Parsed.Free;
    raise ECore4RuntimeError.Create('не вдалося ізолювати перші три Core4-форми'); end;
  FDefinition:=Parsed;
  try
    for I:=0 to High(FDefinition.Roots) do begin
      AdmitDefinition(FDefinition.Roots[I],Item);
      if FindBinding(Item.NameKey)>=0 then
        raise ECore4RuntimeError.Create('повторний exact D7-ідентифікатор у Core4');
      N:=Length(FBindings); SetLength(FBindings,N+1); FBindings[N]:=Item;
    end;
  except FDefinition.Free; FDefinition:=nil; SetLength(FBindings,0); raise end;
end;

destructor TCore4Runtime.Destroy;
begin
  FDefinition.Free;
  inherited Destroy;
end;

function TCore4Runtime.FirstDefinitionIdentifier:RawByteString;
begin
  Result:=FBindings[0].NameKey;
end;

function TCore4Runtime.BindingIdentifier(Index:SizeInt):RawByteString;
begin
  if (Index<0) or (Index>=Length(FBindings)) then
    raise ECore4RuntimeError.Create('індекс поза набором початкових Core4-визначень');
  Result:=FBindings[Index].NameKey;
end;

function TCore4Runtime.BindingCount:SizeInt;
begin Result:=Length(FBindings) end;

function TCore4Runtime.ExecutePhysicalCall(const Physical:RawByteString):RawByteString;
const
  { Межа стеку саме цього нативного зрізу, НЕ новий закон Core4. }
  MaxNestedCalls=64;
var
  Words,OutWords:TExactWords;
  Spans:TPhysicalWordSpans;
  ErrorAt:TPhysicalWordSpan;
  Doc:TD2Document;
  Call:TD2Node;
  Answer:RawByteString;
  I,SerializedCount:SizeInt;
  ListNode,FirstList:TD2Node;
  IsListCall,IsAppendCall,IsSecondCall,IsRestRestCall,IsRestFirstCall,
    IsFirstFirstCall:Boolean;

  function EvaluateSupported(const Node:TD2Node; Depth:SizeInt):RawByteString;
  var
    NameKey:RawByteString;
    Index:SizeInt;
  begin
    try
    { Не дозволяти необмежену рекурсію навіть коли фізичний D2 валідний. }
    if Depth>MaxNestedCalls then
      raise ECore4RuntimeError.Create('перевищено межу вкладених Core4-викликів');
    if Node=nil then
      raise ECore4RuntimeError.Create('відсутня форма вкладеного Core4-виклику');
    if Node.Kind=dkIdentity then begin
      { Точний уже прочитаний атом; без математичного тлумачення W12+. }
      Result:=Node.Bits;
      Exit;
    end;
    if Node.Kind<>dkList then
      raise ECore4RuntimeError.Create('поза зрізом: порожня структура або пара Core4');
    if IsIdentifierSequence(Node) then begin
      { Пошук тільки за повною D7-послідовністю з pinned DEFINE. }
      NameKey:=IdentifierKey(Node);
      Index:=FindBinding(NameKey);
      if Index<0 then
        raise ECore4RuntimeError.Create('невідоме точне D7-глобальне ім’я Core4');
      if FBindings[Index].IsFunction then
        raise ECore4RuntimeError.Create('замикання Core4 потребує виклику');
      Result:=FBindings[Index].ValueBits;
      Exit;
    end;
    if Length(Node.Children)<>2 then
      raise ECore4RuntimeError.Create('підтриманий Core4-виклик має два поля');
    if (Node.Children[0]<>nil) and
       (Node.Children[0].Kind=dkIdentity) and
       (Node.Children[0].Width=4) then
      raise ECore4RuntimeError.Create('raw D4-координата не є D7-замиканням');
    NameKey:=IdentifierKey(Node.Children[0]);
    Index:=FindBinding(NameKey);
    if Index<0 then
      raise ECore4RuntimeError.Create('невідомий точний D7-ідентифікатор Core4');
    if not FBindings[Index].IsFunction then
      raise ECore4RuntimeError.Create('атомний Core4-глобал не є викличним');
    { Не копіюємо визначення тотожності: лише вже ЗАВАНТАЖЕНЕ pinned
      DEFINE/LAMBDA із точним D7-посиланням body=parameter допущено.
      Інші форми тіла залишаються заборонені. }
    if FBindings[Index].BodyKey<>FBindings[Index].ParameterKey then
      raise ECore4RuntimeError.Create('тіло замикання поза межами зрізу');
    Result:=EvaluateSupported(Node.Children[1],Depth+1);
    except
      { Уже локалізовану ГЛИБШУ відмову не переприв'язувати
        до предка, інакше втратиться точний фізичний вузол. }
      on E:ECore4NodeError do raise;
      on E:ECore4RuntimeError do begin
        if Node=nil then raise;
        raise ECore4NodeError.CreateAt(E.Message,Node.WordIndex);
      end;
    end;
  end;

  procedure AppendExactWord(var Target:TExactWords;
    const Bits:RawByteString; AtWord:SizeInt);
  var Capacity:SizeInt;
  begin
    if SerializedCount>=FMaxCallWords then
      raise ECore4NodeError.CreateAt(
        'результат селектора D4 перевищив межу фізичних слів',AtWord);
    if SerializedCount=Length(Target) then begin
      if Length(Target)=0 then Capacity:=16
      else Capacity:=Length(Target)*2;
      if Capacity>FMaxCallWords then Capacity:=FMaxCallWords;
      SetLength(Target,Capacity);
    end;
    Target[SerializedCount]:=Bits;
    Inc(SerializedCount);
  end;

  procedure SerializeExactValue(const Node:TD2Node;
    var Target:TExactWords; Depth:SizeInt);
  var I:SizeInt;
  begin
    if Node=nil then
      raise ECore4NodeError.CreateAt(
        'селектор D4 вибрав відсутнє точне значення',Call.WordIndex);
    if Depth>MaxD2SyntaxDepth then
      raise ECore4NodeError.CreateAt(
        'вибране значення селектора D4 перевищило межу D2-вкладеності',
        Node.WordIndex);
    case Node.Kind of
      dkIdentity:
        AppendExactWord(Target,Node.Bits,Node.WordIndex);
      dkEmpty:
        AppendExactWord(Target,Node.Bits,Node.WordIndex);
      dkList: begin
        AppendExactWord(Target,'10',Node.WordIndex);
        for I:=0 to High(Node.Children) do
          SerializeExactValue(Node.Children[I],Target,Depth+1);
        AppendExactWord(Target,'01',Node.WordIndex);
      end;
      dkPair: begin
        if Length(Node.Children)<>2 then
          raise ECore4NodeError.CreateAt(
            'селектор D4 вибрав некоректну D2-пару',Node.WordIndex);
        AppendExactWord(Target,'10',Node.WordIndex);
        SerializeExactValue(Node.Children[0],Target,Depth+1);
        AppendExactWord(Target,'11',Node.WordIndex);
        SerializeExactValue(Node.Children[1],Target,Depth+1);
        AppendExactWord(Target,'01',Node.WordIndex);
      end;
    end;
  end;

  procedure AppendProperListOperand(const Operand:TD2Node);
  var I:SizeInt;
  begin
    if Operand=nil then
      raise ECore4NodeError.CreateAt(
        'D4:1111 очікує непорожній D4:1110 список',Call.WordIndex);
    if Operand.Kind<>dkList then
      raise ECore4NodeError.CreateAt(
        'D4:1111 приймає лише форми правильного списку',Operand.WordIndex);
    if Length(Operand.Children)<2 then
      raise ECore4NodeError.CreateAt(
        'D4:1111 у цьому зрізі потребує непорожній D4:1110 список',
        Operand.WordIndex);
    if Operand.Children[0]=nil then
      raise ECore4NodeError.CreateAt(
        'D4:1111 очікує точну D4:1110 голову',Operand.WordIndex);
    if (Operand.Children[0].Kind<>dkIdentity) or
       (Operand.Children[0].Width<>4) or
       (Operand.Children[0].Bits<>'1110') then
      raise ECore4NodeError.CreateAt(
        'D4:1111 очікує точну D4:1110 голову',
        Operand.Children[0].WordIndex);
    for I:=1 to High(Operand.Children) do begin
      if Operand.Children[I]=nil then
        raise ECore4NodeError.CreateAt(
          'D4:1111 цього зрізу приймає лише точні атоми',Operand.WordIndex);
      if Operand.Children[I].Kind<>dkIdentity then
        raise ECore4NodeError.CreateAt(
          'D4:1111 цього зрізу приймає лише точні атоми',
          Operand.Children[I].WordIndex);
      AppendExactWord(OutWords,Operand.Children[I].Bits,
        Operand.Children[I].WordIndex);
    end;
  end;

begin
  Result:=''; Doc:=nil; SerializedCount:=0;
  if (Length(Physical)=0) or (Length(Physical)>Core4BinaryLimit) then
    raise ECore4RuntimeError.Create('порожній або завеликий фізичний виклик');
  try DecodeT5MWithLocations(Physical,Words,Spans);
  except on E:Exception do
    raise ECore4RuntimeError.Create('виклик T5M відхилено: '+E.Message); end;
  if Length(Words)>FMaxCallWords then
    raise ECore4RuntimeError.Create('фізичний виклик перевищив межу слів');
  try Doc:=ParseD2WordsWide(Words);
  except
    on E:ED2SourceError do begin
      ErrorAt:=LocatePhysicalWord(Physical,Spans,E.WordIndex);
      raise ECore4RuntimeError.Create('виклик D2 відхилено:'+
        PhysicalPositionText(ErrorAt)+' '+E.Message);
    end;
    on E:Exception do
      raise ECore4RuntimeError.Create('виклик D2 відхилено: '+E.Message);
  end;
  try
    if Length(Doc.Roots)<>1 then
      raise ECore4RuntimeError.Create('виклик має містити одну форму');
    Call:=Doc.Roots[0];
    IsListCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='1110');
    IsAppendCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='1111');
    IsSecondCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='1001');
    IsRestRestCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='0111');
    IsRestFirstCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='0110');
    IsFirstFirstCall:=(Call<>nil) and (Call.Kind=dkList) and
      (Length(Call.Children)>0) and (Call.Children[0]<>nil) and
      (Call.Children[0].Kind=dkIdentity) and
      (Call.Children[0].Width=4) and (Call.Children[0].Bits='1000');
    if (Call=nil) or (Call.Kind<>dkList) or
       (not IsListCall and not IsAppendCall and not IsSecondCall and
        not IsRestRestCall and
       not IsRestFirstCall and not IsFirstFirstCall and
        not IsIdentifierSequence(Call) and
        (Length(Call.Children)<>2)) then
      raise ECore4RuntimeError.Create('непідтримана коренева форма Core4');
    try
      if IsListCall then begin
        { SENS D4:1110 — канонічний конструктор правильного списку
          (pinned Core4 projection, рядок про D4:1110). Цей вузький
          фізичний зріз приймає тільки точні атоми; він не копіює
          бібліотечні DEFINE і не тлумачить ширину/біти. }
        SetLength(OutWords,Length(Call.Children)+1);
        OutWords[0]:='10';
        for I:=1 to High(Call.Children) do begin
          if Call.Children[I]=nil then
            raise ECore4NodeError.CreateAt(
              'D4:1110 цього зрізу приймає лише точні атоми',Call.WordIndex);
          if Call.Children[I].Kind<>dkIdentity then
            raise ECore4NodeError.CreateAt(
              'D4:1110 цього зрізу приймає лише точні атоми',
              Call.Children[I].WordIndex);
          OutWords[I]:=Call.Children[I].Bits;
        end;
        OutWords[High(OutWords)]:='01';
      end else if IsAppendCall then begin
        { D4:1111 — pinned Core4 визначає приєднання правильних списків.
          Цей фізичний зріз приймає рівно два непорожні D4:1110 вирази. }
        if Length(Call.Children)<>3 then
          raise ECore4NodeError.CreateAt(
            'D4:1111 цього зрізу потребує рівно два списки',Call.WordIndex);
        SerializedCount:=0;
        SetLength(OutWords,0);
        AppendExactWord(OutWords,'10',Call.WordIndex);
        AppendProperListOperand(Call.Children[1]);
        AppendProperListOperand(Call.Children[2]);
        AppendExactWord(OutWords,'01',Call.WordIndex);
      end else if IsSecondCall then begin
        { D4:1001 — точне друге = перше(решта(x)); перевіряємо його
          композиційний закон над результатом D4:1110, не над текстом. }
        if Length(Call.Children)<>2 then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу потребує одного списку',Call.WordIndex);
        ListNode:=Call.Children[1];
        if ListNode=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу приймає результат D4:1110',
            Call.WordIndex);
        if ListNode.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу приймає результат D4:1110',
            ListNode.WordIndex);
        if Length(ListNode.Children)<1 then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу приймає результат D4:1110',
            ListNode.WordIndex);
        if ListNode.Children[0]=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу приймає результат D4:1110',
            ListNode.WordIndex);
        if (ListNode.Children[0].Kind<>dkIdentity) or
           (ListNode.Children[0].Width<>4) or
           (ListNode.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:1001 цього зрізу приймає результат D4:1110',
            ListNode.Children[0].WordIndex);
        if Length(ListNode.Children)<3 then
          raise ECore4NodeError.CreateAt(
            'D4:1001 потребує щонайменше два значення',ListNode.WordIndex);
        SerializeExactValue(ListNode.Children[2],OutWords,0);
      end else if IsRestRestCall then begin
        { D4:0111 — «решта-решти» над результатом D4:1110.
          Межа цього фізичного зрізу: принаймні два точні атоми; результат
          зберігає без переінтерпретації кожне слово суфікса. }
        if Length(Call.Children)<>2 then
          raise ECore4NodeError.CreateAt(
            'D4:0111 цього зрізу потребує одного списку',Call.WordIndex);
        ListNode:=Call.Children[1];
        if ListNode=nil then
          raise ECore4NodeError.CreateAt(
            'D4:0111 цього зрізу приймає результат D4:1110',Call.WordIndex);
        if ListNode.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:0111 цього зрізу приймає результат D4:1110',
            Call.Children[1].WordIndex);
        if (Length(ListNode.Children)<1) or
           (ListNode.Children[0]=nil) or
           (ListNode.Children[0].Kind<>dkIdentity) or
           (ListNode.Children[0].Width<>4) or
           (ListNode.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:0111 цього зрізу приймає результат D4:1110',
            ListNode.WordIndex);
        if Length(ListNode.Children)<3 then
          raise ECore4NodeError.CreateAt(
            'D4:0111 потребує щонайменше два атоми',ListNode.WordIndex);
        for I:=1 to High(ListNode.Children) do begin
          if ListNode.Children[I]=nil then
            raise ECore4NodeError.CreateAt(
              'D4:0111 цього зрізу приймає лише точні атоми',
              ListNode.WordIndex);
          if ListNode.Children[I].Kind<>dkIdentity then
            raise ECore4NodeError.CreateAt(
              'D4:0111 цього зрізу приймає лише точні атоми',
              ListNode.Children[I].WordIndex);
        end;
        SetLength(OutWords,Length(ListNode.Children)-1);
        OutWords[0]:='10';
        for I:=3 to High(ListNode.Children) do
          OutWords[I-2]:=ListNode.Children[I].Bits;
        OutWords[High(OutWords)]:='01';
      end else if IsRestFirstCall then begin
        { D4:0110 — чинний складений селектор «решта-першого»:
          перше значення зовнішнього D4:1110 є внутрішнім D4:1110;
          результатом стає його суфікс після першого значення. }
        if Length(Call.Children)<>2 then
          raise ECore4NodeError.CreateAt(
            'D4:0110 цього зрізу потребує один зовнішній список',
            Call.WordIndex);
        ListNode:=Call.Children[1];
        if ListNode=nil then
          raise ECore4NodeError.CreateAt(
            'D4:0110 цього зрізу приймає зовнішній D4:1110 список',
            Call.WordIndex);
        if ListNode.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:0110 цього зрізу приймає зовнішній D4:1110 список',
            ListNode.WordIndex);
        if Length(ListNode.Children)<1 then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує зовнішній D4:1110 список',
            ListNode.WordIndex);
        if ListNode.Children[0]=nil then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує зовнішній D4:1110 список',
            ListNode.WordIndex);
        if (ListNode.Children[0].Kind<>dkIdentity) or
           (ListNode.Children[0].Width<>4) or
           (ListNode.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує зовнішній D4:1110 список',
            ListNode.Children[0].WordIndex);
        if Length(ListNode.Children)<2 then
          raise ECore4NodeError.CreateAt(
            'D4:0110 потребує перший внутрішній список',ListNode.WordIndex);
        FirstList:=ListNode.Children[1];
        if FirstList=nil then
          raise ECore4NodeError.CreateAt(
            'D4:0110 перший елемент має бути D4:1110 списком',
            ListNode.WordIndex);
        if FirstList.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:0110 перший елемент має бути D4:1110 списком',
            FirstList.WordIndex);
        if Length(FirstList.Children)<1 then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує внутрішній D4:1110 список',
            FirstList.WordIndex);
        if FirstList.Children[0]=nil then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує внутрішній D4:1110 список',
            FirstList.WordIndex);
        if (FirstList.Children[0].Kind<>dkIdentity) or
           (FirstList.Children[0].Width<>4) or
           (FirstList.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:0110 очікує внутрішній D4:1110 список',
            FirstList.Children[0].WordIndex);
        if Length(FirstList.Children)<2 then
          raise ECore4NodeError.CreateAt(
            'D4:0110 потребує перше значення внутрішнього списку',
            FirstList.WordIndex);
        for I:=2 to High(ListNode.Children) do begin
          if ListNode.Children[I]=nil then
            raise ECore4NodeError.CreateAt(
              'D4:0110 цього зрізу приймає лише точні атоми у хвості зовнішнього списку',
              ListNode.WordIndex);
          if ListNode.Children[I].Kind<>dkIdentity then
            raise ECore4NodeError.CreateAt(
              'D4:0110 цього зрізу приймає лише точні атоми у хвості зовнішнього списку',
              ListNode.Children[I].WordIndex);
        end;
        SerializedCount:=0;
        SetLength(OutWords,0);
        AppendExactWord(OutWords,'10',FirstList.WordIndex);
        for I:=2 to High(FirstList.Children) do
          SerializeExactValue(FirstList.Children[I],OutWords,0);
        AppendExactWord(OutWords,'01',FirstList.WordIndex);
      end else if IsFirstFirstCall then begin
        { D4:1000 — точна композиція «перше-першого» над двома
          фізичними D4:1110 списками; вибране D2-значення зберігається повністю. }
        if Length(Call.Children)<>2 then
          raise ECore4NodeError.CreateAt(
            'D4:1000 цього зрізу потребує один зовнішній список',
            Call.WordIndex);
        ListNode:=Call.Children[1];
        if ListNode=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1000 цього зрізу приймає зовнішній D4:1110 список',
            Call.WordIndex);
        if ListNode.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:1000 цього зрізу приймає зовнішній D4:1110 список',
            ListNode.WordIndex);
        if Length(ListNode.Children)<1 then
          raise ECore4NodeError.CreateAt(
            'D4:1000 потребує перший елемент зовнішнього списку',
            ListNode.WordIndex);
        if ListNode.Children[0]=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1000 очікує зовнішній D4:1110 список',
            ListNode.WordIndex);
        if (ListNode.Children[0].Kind<>dkIdentity) or
           (ListNode.Children[0].Width<>4) or
           (ListNode.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:1000 очікує зовнішній D4:1110 список',
            ListNode.Children[0].WordIndex);
        if Length(ListNode.Children)<2 then
          raise ECore4NodeError.CreateAt(
            'D4:1000 потребує перший вкладений список',ListNode.WordIndex);
        FirstList:=ListNode.Children[1];
        if FirstList=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1000 потребує перший вкладений список',ListNode.WordIndex);
        if FirstList.Kind<>dkList then
          raise ECore4NodeError.CreateAt(
            'D4:1000 перший елемент має бути D4:1110 списком',
            FirstList.WordIndex);
        if Length(FirstList.Children)<1 then
          raise ECore4NodeError.CreateAt(
            'D4:1000 очікує внутрішній D4:1110 список',
            FirstList.WordIndex);
        if FirstList.Children[0]=nil then
          raise ECore4NodeError.CreateAt(
            'D4:1000 очікує внутрішній D4:1110 список',
            FirstList.WordIndex);
        if (FirstList.Children[0].Kind<>dkIdentity) or
           (FirstList.Children[0].Width<>4) or
           (FirstList.Children[0].Bits<>'1110') then
          raise ECore4NodeError.CreateAt(
            'D4:1000 очікує внутрішній D4:1110 список',
            FirstList.Children[0].WordIndex);
        if Length(FirstList.Children)<2 then
          raise ECore4NodeError.CreateAt(
            'D4:1000 потребує атом у першому внутрішньому списку',
            FirstList.WordIndex);
        for I:=2 to High(FirstList.Children) do begin
          if FirstList.Children[I]=nil then
            raise ECore4NodeError.CreateAt(
              'D4:1000 цього зрізу приймає лише точні атоми у внутрішньому списку',
              FirstList.WordIndex);
          if FirstList.Children[I].Kind<>dkIdentity then
            raise ECore4NodeError.CreateAt(
              'D4:1000 цього зрізу приймає лише точні атоми у внутрішньому списку',
              FirstList.Children[I].WordIndex);
        end;
        for I:=2 to High(ListNode.Children) do begin
          if ListNode.Children[I]=nil then
            raise ECore4NodeError.CreateAt(
              'D4:1000 цього зрізу приймає лише точні атоми у хвості зовнішнього списку',
              ListNode.WordIndex);
          if ListNode.Children[I].Kind<>dkIdentity then
            raise ECore4NodeError.CreateAt(
              'D4:1000 цього зрізу приймає лише точні атоми у хвості зовнішнього списку',
              ListNode.Children[I].WordIndex);
        end;
        SerializeExactValue(FirstList.Children[1],OutWords,0);
      end else begin
        Answer:=EvaluateSupported(Call,0);
        SetLength(OutWords,1);
        OutWords[0]:=Answer;
      end;
    except
      on E:ECore4NodeError do begin
        ErrorAt:=LocatePhysicalWord(Physical,Spans,E.WordIndex);
        raise ECore4RuntimeError.Create('виклик Core4 відхилено:'+
          PhysicalPositionText(ErrorAt)+' '+E.Message);
      end;
    end;
    if IsFirstFirstCall or IsRestFirstCall or IsAppendCall or IsSecondCall then
      SetLength(OutWords,SerializedCount);
    Result:=EncodeT5M(OutWords);
  finally
    Doc.Free;
  end;
end;
end.
