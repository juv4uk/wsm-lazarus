{ G3.2: обмежений механізм виконання п'яти D3-операцій.
  Закони й проєкції належать pinned SENS Contract 12, не Pascal.
  Немає Core4, SID-сумісності, чисел або канонічного T5M reader. }
unit wsm.nativeeval;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.source, wsm.domain, wsm.bind, wsm.bindindex;
type
  ENativeEvalError=class(ESourceError);
  { Фізичні теги контейнера, а не другий реєстр мовних функцій. }
  TNativeCellKind=(ncEmpty,ncDomain,ncPair);
  TNativeCell=record
    Kind:TNativeCellKind;
    Key:TDomainKey;
    First,Rest:SizeInt;
  end;
  TNativeEvaluator=class
  private
    FDomains:TDomainSet;
    FIndex:TBindIndex;
    FCells:array of TNativeCell;
    FUsed,FMaxCells,FMaxSteps,FSteps,FMaxDepth:SizeInt;
    procedure Reset;
    procedure Fail(N:TSourceNode; const MessageText:String);
    procedure Step(N:TSourceNode; Depth:SizeInt);
    function Append(const Cell:TNativeCell; N:TSourceNode):SizeInt;
    function DomainCell(const Key:TDomainKey; N:TSourceNode):SizeInt;
    function PairCell(A,B:SizeInt; N:TSourceNode):SizeInt;
    function Quote(N:TSourceNode; Depth:SizeInt):SizeInt;
    function Eval(N:TSourceNode; Depth:SizeInt):SizeInt;
    function Render(H:SizeInt; Depth:SizeInt):RawByteString;
  public
    constructor Create(const Root:RawByteString; Cells:SizeInt=4096;
      Steps:SizeInt=16384; Depth:SizeInt=128);
    function EvaluateNode(N:TSourceNode):RawByteString;
    function EvaluateSource(const Source:RawByteString):RawByteString;
  end;
implementation
constructor TNativeEvaluator.Create(const Root:RawByteString;
  Cells:SizeInt; Steps:SizeInt; Depth:SizeInt);
begin
  inherited Create;
  if (Cells<1) or (Cells>65536) or (Steps<1) or (Steps>1048576) or
     (Depth<1) or (Depth>128) then
    raise ENativeEvalError.CreateAt('invalid native resource limits',1,1,1);
  FMaxCells:=Cells; FMaxSteps:=Steps; FMaxDepth:=Depth;
  LoadPinnedDomains(Root,FDomains);
  BuildBindIndex(FDomains,FIndex);
  Reset;
end;
procedure TNativeEvaluator.Reset;
begin
  SetLength(FCells,0); SetLength(FCells,1);
  FCells[0].Kind:=ncEmpty;
  FCells[0].Key:=ExactKey('000'); { D3:000, не D1:0. }
  FUsed:=1; FSteps:=0;
end;
procedure TNativeEvaluator.Fail(N:TSourceNode; const MessageText:String);
begin
  raise ENativeEvalError.CreateAt(MessageText,N.ByteOffset,N.Line,N.ByteColumn);
end;
procedure TNativeEvaluator.Step(N:TSourceNode; Depth:SizeInt);
begin
  if Depth>FMaxDepth then Fail(N,'native depth limit');
  if FSteps>=FMaxSteps then Fail(N,'native step limit');
  Inc(FSteps);
end;
function TNativeEvaluator.Append(const Cell:TNativeCell; N:TSourceNode):SizeInt;
var Capacity:SizeInt;
begin
  if FUsed>=FMaxCells then Fail(N,'native cell limit');
  if FUsed=Length(FCells) then begin
    Capacity:=Length(FCells)*2;
    if Capacity>FMaxCells then Capacity:=FMaxCells;
    SetLength(FCells,Capacity);
  end;
  Result:=FUsed; FCells[Result]:=Cell; Inc(FUsed);
end;
function TNativeEvaluator.DomainCell(const Key:TDomainKey; N:TSourceNode):SizeInt;
var C:TNativeCell;
begin
  C:=Default(TNativeCell); C.Kind:=ncDomain; C.Key:=Key;
  Result:=Append(C,N);
end;
function TNativeEvaluator.PairCell(A,B:SizeInt; N:TSourceNode):SizeInt;
var C:TNativeCell;
begin
  C:=Default(TNativeCell); C.Kind:=ncPair; C.First:=A; C.Rest:=B;
  Result:=Append(C,N);
end;
function TNativeEvaluator.Quote(N:TSourceNode; Depth:SizeInt):SizeInt;
var I,J,Width,Count,Item:SizeInt; Ch:RawByteString;
    Letters:array of SizeInt; Key:TDomainKey;
begin
  Step(N,Depth);
  Result:=0;
  if N.Kind=skList then begin
    for I:=High(N.Children) downto 0 do begin
      Item:=Quote(N.Children[I],Depth+1);
      Result:=PairCell(Item,Result,N);
    end;
    Exit;
  end;
  if N.Kind<>skAtom then Fail(N,'unsupported native quoted string');
  if (N.Text='.') or (N.Text='') or (N.Text[1]='''') then
    Fail(N,'unsupported native reader syntax');
  { Quote-текст є D7-даними. Жодного Pascal symbol interning.
    Підтриманий тут вузький вхід — незакодовані літери таблиці D7.
    Числові літерали/escape/surface у лапках не вгадуємо. }
  I:=1; Count:=0; SetLength(Letters,0);
  while I<=Length(N.Text) do begin
    Step(N,Depth);
    if Ord(N.Text[I])<$80 then Width:=1
    else if Ord(N.Text[I])<$E0 then Width:=2
    else if Ord(N.Text[I])<$F0 then Width:=3 else Width:=4;
    Ch:=Copy(N.Text,I,Width);
    try Key:=IndexedUkrainianInDomain(FIndex,Ch,7);
    except on X:EBindError do Fail(N,'unsupported native D7 projection'); end;
    { Пунктуаційні/числові surface у таблиці мають лапки, тому цей
      прямий lookup не приймає їх як текстові літери. }
    SetLength(Letters,Count+1);
    Letters[Count]:=DomainCell(Key,N); Inc(Count); Inc(I,Width);
  end;
  for J:=Count-1 downto 0 do Result:=PairCell(Letters[J],Result,N);
end;
function TNativeEvaluator.Eval(N:TSourceNode; Depth:SizeInt):SizeInt;
var Key:TDomainKey; A,B,ArgCount:SizeInt;
begin
  Step(N,Depth);
  if N.Kind=skAtom then begin
    try Key:=IndexedUkrainian(FIndex,N.Text);
    except on X:EBindError do Fail(N,'unknown native binding'); end;
    if Key.Width<>1 then Fail(N,'unsupported native value domain');
    Exit(DomainCell(Key,N));
  end;
  if N.Kind<>skList then Fail(N,'unsupported native string value');
  if Length(N.Children)=0 then Exit(0);
  if N.Children[0].Kind<>skAtom then Fail(N,'unsupported computed native head');
  try Key:=IndexedUkrainian(FIndex,N.Children[0].Text);
  except on X:EBindError do Fail(N.Children[0],'unknown native call head'); end;
  { Поверхня вже стала точним ключем; подальший dispatch лише D3+біти.
    Членство у таблиці НЕ дозволяє довільний виклик. Решта BLOCKED. }
  if Key.Width<>3 then Fail(N.Children[0],'unsupported native callable domain');
  case Key.Bits of
    %001,%010,%011,%100: ArgCount:=1;
    %111: ArgCount:=2;
    else begin Fail(N.Children[0],'native mechanism not implemented'); ArgCount:=0; end;
  end;
  if Length(N.Children)<>ArgCount+1 then Fail(N,'native arity error');
  if Key.Bits=%001 then Exit(Quote(N.Children[1],Depth+1));
  A:=Eval(N.Children[1],Depth+1);
  case Key.Bits of
    %010: begin
      Key:=ExactKey('0');
      if FCells[A].Kind<>ncPair then Key:=ExactKey('1');
      Result:=DomainCell(Key,N);
    end;
    %011,%100: begin
      if FCells[A].Kind<>ncPair then Fail(N,'native selector requires nonempty pair');
      if Key.Bits=%100 then Result:=FCells[A].First
      else Result:=FCells[A].Rest;
    end;
    %111: begin
      B:=Eval(N.Children[2],Depth+1);
      Result:=PairCell(A,B,N);
    end;
    else begin Fail(N,'native mechanism not implemented'); Result:=0; end;
  end;
end;
function TNativeEvaluator.Render(H:SizeInt; Depth:SizeInt):RawByteString;
var Tail:SizeInt;
begin
  if Depth>256 then raise ENativeEvalError.CreateAt('native output depth limit',1,1,1);
  case FCells[H].Kind of
    ncEmpty: Result:='()';
    ncDomain: Result:=KeyBits(FCells[H].Key);
    ncPair: begin
      Result:='('; Tail:=H;
      while FCells[Tail].Kind=ncPair do begin
        if Tail<>H then Result:=Result+' ';
        Result:=Result+Render(FCells[Tail].First,Depth+1);
        Tail:=FCells[Tail].Rest;
      end;
      if FCells[Tail].Kind<>ncEmpty then Result:=Result+' . '+Render(Tail,Depth+1);
      Result:=Result+')';
    end;
  end;
end;
{ Вхід із уже перевіреного AST: не перетворюємо українську проєкцію
  на повторний текст і не створюємо нового мовного dispatch. }
function TNativeEvaluator.EvaluateNode(N:TSourceNode):RawByteString;
var H:SizeInt;
begin
  if N=nil then
    raise ENativeEvalError.CreateAt('відсутня форма для виконання',1,1,1);
  Reset;
  try
    H:=Eval(N,0);
    Result:=Render(H,0);
  finally
    Reset;
  end;
end;
function TNativeEvaluator.EvaluateSource(const Source:RawByteString):RawByteString;
var Doc:TSourceDocument;
begin
  Doc:=ReadUkrainianSource(Source);
  try
    if Length(Doc.Forms)<>1 then
      raise ENativeEvalError.CreateAt('native evaluation requires one form',1,1,1);
    Result:=EvaluateNode(Doc.Forms[0]);
  finally
    Doc.Free;
  end;
end;
end.
