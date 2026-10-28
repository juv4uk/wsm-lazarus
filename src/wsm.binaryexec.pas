{ G3.4: фізичний .sens -> T5M/D2 -> pinned exact-domain bind ->
  той САМИЙ native D3 evaluator, без українського text projection.
  «ук» лишається лише людиночитаною проєкцією в інших інтерфейсах.
  D3:001, D2 dotted pair, Core4, невідомі форми — явно BLOCKED.
  Немає дублювання D3 механізмів, власного реєстру законів чи SID8. }
unit wsm.binaryexec;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.bind, wsm.d2source, wsm.nativeeval;
type
  EBinaryExecutionError = class(Exception)
  public
    WordIndex: SizeInt; { 1-based фізичний індекс, 0 лише для хибного T5M }
    constructor CreateAt(const Problem: String; AtWord: SizeInt);
  end;

  TBinaryExecutor = class
  private
    FDomains: TDomainSet;
    FNative: TNativeEvaluator;
    procedure Fail(N: TD2Node; const Why: String);
  public
    constructor Create(const AuthorityRoot: RawByteString);
    destructor Destroy; override;
    function ExecutePhysical(const Physical: RawByteString): RawByteString;
  end;

implementation
uses wsm.t5m, wsm.domain, wsm.binarybind, wsm.source;

constructor EBinaryExecutionError.CreateAt(const Problem: String;
  AtWord: SizeInt);
begin
  inherited Create(Problem);
  WordIndex:=AtWord;
end;

constructor TBinaryExecutor.Create(const AuthorityRoot: RawByteString);
begin
  inherited Create;
  FNative:=nil;
  try
    LoadPinnedDomains(AuthorityRoot, FDomains);
    FNative:=TNativeEvaluator.Create(AuthorityRoot);
  except
    FreeAndNil(FNative);
    raise;
  end;
end;

destructor TBinaryExecutor.Destroy;
begin
  FNative.Free;
  inherited Destroy;
end;

procedure TBinaryExecutor.Fail(N: TD2Node; const Why: String);
begin
  if N=nil then raise EBinaryExecutionError.CreateAt(Why,0);
  raise EBinaryExecutionError.CreateAt(Why,N.WordIndex);
end;

{ Вузли є механічними адаптерами до ТОГО САМОГО native evaluator:
  їхні Text порожні; існує тільки зовнішній exact ключ з pinned binder.
  ByteOffset тут — 1-based номер фізичного слова, а не offset .lisp;
  його використовує тільки приватний адаптер діагностики нижче. }
function ToNativeNode(N:TD2Node; Root,Depth:SizeInt;
  const Bound:TBinaryWords; var Leaf:SizeInt;
  var Atoms:TNativeKeyedAtoms; var AtomCount:SizeInt):TSourceNode;
var I:SizeInt; Key:TDomainKey; Item:TSourceNode;
begin
  if N=nil then
    raise EBinaryExecutionError.CreateAt(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB#$20#$44#$32,0);
  if Depth>128 then
    raise EBinaryExecutionError.CreateAt(#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$B3#$D0#$BB#$D0#$B8#$D0#$B1#$D0#$B8#$D0#$BD#$D1#$83#$20#$44#$33,N.WordIndex);
  Result:=TSourceNode.Create;
  Result.ByteOffset:=N.WordIndex;
  Result.Line:=1;
  Result.ByteColumn:=1;
  try
    case N.Kind of
      dkList: begin
        Result.Kind:=skList;
        { Поки не підтверджено фізичну quote семантику: та сама
          негативна межа G3.3. НЕ перетворюємо її на текстову цитату. }
        if (Length(N.Children)>0) and (N.Children[0]<>nil) and
           (N.Children[0].Kind=dkIdentity) and
           (N.Children[0].Width=3) and
           (N.Children[0].Bits='001') then
          raise EBinaryExecutionError.CreateAt(
            #$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$20#$44#$33#$20#$D0#$BF#$D0#$BE#$D0#$BA#$D0#$B8#$20#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$89#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$B4#$D0#$BE#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F,
            N.Children[0].WordIndex);
        for I:=0 to High(N.Children) do begin
          Item:=ToNativeNode(N.Children[I],Root,Depth+1,
            Bound,Leaf,Atoms,AtomCount);
          Result.Add(Item);
        end;
      end;
      dkPair: raise EBinaryExecutionError.CreateAt(
        #$D0#$BF#$D0#$BE#$D1#$85#$D1#$96#$D0#$B4#$D0#$BD#$D1#$83#$20#$44#$32#$20#$D0#$BA#$D1#$80#$D0#$B0#$D0#$BF#$D0#$BA#$D0#$BE#$D0#$B2#$D1#$83#$20#$D0#$BF#$D0#$B0#$D1#$80#$D1#$83#$20#$D0#$BD#$D0#$B5#$20#$D0#$BC#$D0#$BE#$D0#$B6#$D0#$BD#$D0#$B0#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B4#$D0#$B0#$D0#$B2#$D0#$B0#$D1#$82#$D0#$B8#$20#$D1#$8F#$D0#$BA#$20#$D1#$82#$D0#$B5#$D0#$BA#$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D1#$83#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D1#$83,
        N.WordIndex);
      dkEmpty,dkIdentity: begin
        { Звірка з чинним pinned binder у preorder.
          Навіть D3:000 є фізично зв'язаною координатою, але
          внутрішня нульова pair-arena комірка не є текстовим ім'ям. }
        if (Leaf>=Length(Bound)) or
           (Bound[Leaf].RootIndex<>Root) or
           (Bound[Leaf].WordIndex<>N.WordIndex) or
           (Bound[Leaf].IsEmpty<>(N.Kind=dkEmpty)) then
          raise EBinaryExecutionError.CreateAt(
            #$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BF#$D0#$BE#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D1#$96#$D1#$81#$D1#$82#$D1#$8C#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$BC#$D1#$83#$20#$70#$69#$6E#$6E#$65#$64#$20#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8E,N.WordIndex);
        Key:=Bound[Leaf].Key;
        if (Key.Width<>N.Width) or (KeyBits(Key)<>N.Bits) then
          raise EBinaryExecutionError.CreateAt(
            #$D0#$B2#$D1#$82#$D1#$80#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BE#$20#$65#$78#$61#$63#$74#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D1#$83#$20#$D1#$87#$D0#$B8#$20#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8#$20#$70#$69#$6E#$6E#$65#$64#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B0,N.WordIndex);
        Inc(Leaf);
        if N.Kind=dkEmpty then
          Result.Kind:=skList
        else begin
          Result.Kind:=skAtom;
          if AtomCount>=Length(Atoms) then
            raise EBinaryExecutionError.CreateAt(
              #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BA#$D1#$96#$D0#$BB#$D1#$8C#$D0#$BA#$D1#$96#$D1#$81#$D1#$82#$D1#$8C#$20#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D0#$B0#$D0#$BD#$D0#$B8#$D1#$85#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D1#$85#$20#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC#$D1#$96#$D0#$B2,N.WordIndex);
          Atoms[AtomCount].Node:=Result;
          Atoms[AtomCount].Key:=Key;
          Inc(AtomCount);
        end;
      end;
    else
      raise EBinaryExecutionError.CreateAt(
        #$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$B4#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0,N.WordIndex);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TBinaryExecutor.ExecutePhysical(
  const Physical: RawByteString): RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  NativeRoot:TSourceNode;
  Atoms:TNativeKeyedAtoms;
  Leaf,AtomCount,WordAt:SizeInt;
begin
  Doc:=nil;
  NativeRoot:=nil;
  try
    try
      Doc:=ReadD2T5M(Physical);
    except
      on E:ET5MError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$54#$35#$4D#$3A#$20+E.Message,0);
      on E:ED2SourceError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BA#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$44#$32#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B8#$3A#$20+E.Message,E.WordIndex);
    end;

    if Length(Doc.Roots)<>1 then begin
      WordAt:=1;
      if Length(Doc.Roots)>1 then WordAt:=Doc.Roots[1].WordIndex;
      raise EBinaryExecutionError.CreateAt(
        #$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$BD#$D0#$B0#$20#$D1#$80#$D1#$96#$D0#$B2#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$B4#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0,WordAt);
    end;

    { УСІ домени/листи перевіряються ПЕРЕД будь-яким виконанням.
      З bound key не виводиться callability: її межа лишається
      у вже наявному TNativeEvaluator (D3 механізми G3.2). }
    try
      BindD2Binary(Doc,FDomains,Bound);
    except
      on E:EBinaryBindError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$70#$69#$6E#$6E#$65#$64#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B5#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3A#$20+E.Message,
          Doc.Roots[0].WordIndex);
    end;

    SetLength(Atoms,Length(Bound));
    Leaf:=0; AtomCount:=0;
    NativeRoot:=ToNativeNode(Doc.Roots[0],0,0,
      Bound,Leaf,Atoms,AtomCount);
    if Leaf<>Length(Bound) then
      raise EBinaryExecutionError.CreateAt(
        #$D0#$B7#$D0#$B0#$D0#$BB#$D0#$B8#$D1#$88#$D0#$B8#$D0#$BB#$D0#$B8#$D1#$81#$D1#$8F#$20#$D0#$BD#$D0#$B5#$D0#$B7#$D0#$B2#$E2#$80#$99#$D1#$8F#$D0#$B7#$D0#$B0#$D0#$BD#$D1#$96#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D1#$96#$20#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B0,Doc.Roots[0].WordIndex);
    SetLength(Atoms,AtomCount);
    try
      { Жодного .lisp, українського spelling або повторного
        source parsing у фізичному тракті. Тільки bound keys. }
      Result:=FNative.EvaluateKeyedNode(NativeRoot,Atoms);
    except
      on E:ENativeEvalError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$44#$33#$20#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$81#$D1#$82#$D0#$B8#$D0#$B2#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D1#$83#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D1#$83#$3A#$20+E.Message,
          E.ByteOffset);
    end;
  finally
    NativeRoot.Free;
    Doc.Free;
  end;
end;

end.
