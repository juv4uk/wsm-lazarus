{ Вузький фізичний місток: T5M/D2 -> pinned українська проєкція ->
  ВЖЕ наявний D3 виконавець. Проєкція не є мовним законом чи оракулом.
  Цитати та dotted-пари відхиляються, бо втратили б точну ідентичність. }
unit wsm.binaryexec;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.bind, wsm.domain, wsm.d2source, wsm.nativeeval;
type
  EBinaryExecutionError = class(Exception)
  public
    WordIndex: SizeInt; { 1-based; 0 якщо T5M відкинутий до розбору слів }
    constructor CreateAt(const Problem: String; AtWord: SizeInt);
  end;
  TBinaryExecutor = class
  private
    FDomains: TDomainSet;
    FNative: TNativeEvaluator;
    function ProjectNode(N: TD2Node; Depth: SizeInt): RawByteString;
    procedure Fail(N: TD2Node; const Why: String);
  public
    constructor Create(const AuthorityRoot: RawByteString);
    destructor Destroy; override;
    function ExecutePhysical(const Physical: RawByteString): RawByteString;
  end;
implementation
uses wsm.t5m, wsm.source;

const MaxProjectionBytes = 1024 * 1024;
constructor EBinaryExecutionError.CreateAt(const Problem: String; AtWord: SizeInt);
begin
  inherited Create(Problem);
  WordIndex := AtWord;
end;

constructor TBinaryExecutor.Create(const AuthorityRoot: RawByteString);
begin
  inherited Create;
  FNative := nil;
  try
    LoadPinnedDomains(AuthorityRoot, FDomains);
    FNative := TNativeEvaluator.Create(AuthorityRoot);
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
  if N = nil then raise EBinaryExecutionError.CreateAt(Why, 0);
  raise EBinaryExecutionError.CreateAt(Why, N.WordIndex);
end;

function TBinaryExecutor.ProjectNode(N: TD2Node; Depth: SizeInt): RawByteString;
var I: SizeInt; Key: TDomainKey; Row: TDomainRow; Part: RawByteString;
begin
  if N = nil then Fail(N, #$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$BE#$D1#$97#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B8);
  if Depth > 128 then Fail(N, #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D0#$B0#$20#$D0#$B2#$D0#$BA#$D0#$BB#$D0#$B0#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$BE#$D1#$81#$D1#$82#$D1#$96#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
  case N.Kind of
    dkEmpty: begin
      if (N.Width <> 3) or (N.Bits <> '000') then
        Fail(N, #$D0#$BF#$D0#$BE#$D1#$80#$D1#$83#$D1#$88#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BA#$D0#$BE#$D0#$BE#$D1#$80#$D0#$B4#$D0#$B8#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B0#$20#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$8C#$D0#$BE#$D0#$B3#$D0#$BE#$20#$44#$33);
      Result := '()';
    end;
    dkIdentity: begin
      if (N.Width <> 1) and (N.Width <> 3) then
        Fail(N, #$D1#$86#$D0#$B5#$D0#$B9#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$20#$D1#$89#$D0#$B5#$20#$D0#$BD#$D0#$B5#$20#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$B5#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$88#$D0#$BB#$D1#$8F#$D1#$85#$D1#$83#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F);
      try Key := ExactKey(N.Bits);
      except on E: EDomainError do
        Fail(N, #$D0#$BD#$D0#$B5#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BD#$D1#$96#$20#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BA#$D0#$BE#$D0#$BE#$D1#$80#$D0#$B4#$D0#$B8#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8);
      end;
      if (Key.Width <> N.Width) or
         not DomainRowByKey(FDomains[Key.Width], Key, Row) or
         (Row.Ukrainian = '') then
        Fail(N, #$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$BE#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D1#$83#$D0#$BA#$D1#$80#$D0#$B0#$D1#$97#$D0#$BD#$D1#$81#$D1#$8C#$D0#$BA#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97#$20#$70#$69#$6E#$6E#$65#$64#$20#$53#$45#$4E#$53);
      Result := Row.Ukrainian;
    end;
    dkList: begin
      if (Length(N.Children) > 0) and
         (N.Children[0] <> nil) and
         (N.Children[0].Kind = dkIdentity) and
         (N.Children[0].Width = 3) and
         (N.Children[0].Bits = '001') then
        Fail(N.Children[0],
          #$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$20#$44#$33#$20#$D0#$BF#$D0#$BE#$D0#$BA#$D0#$B8#$20#$D0#$BD#$D0#$B5#$20#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$B4#$D0#$BE#$D0#$B2#$D0#$B5#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$B1#$D0#$B5#$D0#$B7#$D0#$B2#$D1#$82#$D1#$80#$D0#$B0#$D1#$82#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
      Result := '(';
      for I := 0 to High(N.Children) do begin
        if I > 0 then Result := Result + ' ';
        Part := ProjectNode(N.Children[I], Depth + 1);
        if Length(Result) > MaxProjectionBytes - Length(Part) - 1 then
          Fail(N, #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D1#$83#$20#$D0#$B2#$D0#$BD#$D1#$83#$D1#$82#$D1#$80#$D1#$96#$D1#$88#$D0#$BD#$D1#$8C#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
        Result := Result + Part;
      end;
      Result := Result + ')';
    end;
    dkPair: begin
      Fail(N, #$44#$32#$20#$64#$6F#$74#$74#$65#$64#$2D#$D0#$BF#$D0#$B0#$D1#$80#$D0#$B0#$20#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$81#$D0#$BA#$D0#$B0#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F#$20#$D1#$87#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B7#$20#$D1#$82#$D0#$B5#$D0#$BA#$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$BC#$D1#$96#$D1#$81#$D1#$82#$D0#$BE#$D0#$BA);
      Result := '';
    end;
  else
    Fail(N, #$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$B4#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0);
    Result := '';
  end;
  if Length(Result) > MaxProjectionBytes then
    Fail(N, #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D1#$83#$20#$D0#$B2#$D0#$BD#$D1#$83#$D1#$82#$D1#$80#$D1#$96#$D1#$88#$D0#$BD#$D1#$8C#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
end;

function TBinaryExecutor.ExecutePhysical(
  const Physical: RawByteString): RawByteString;
var Doc: TD2Document; Source: RawByteString; AtWord: SizeInt;
begin
  Doc := nil;
  try
    try Doc := ReadD2T5M(Physical);
    except
      on E: ET5MError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BF#$D0#$BE#$D1#$88#$D0#$BA#$D0#$BE#$D0#$B4#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D1#$82#$D1#$80#$D0#$B0#$D0#$BD#$D1#$81#$D0#$BF#$D0#$BE#$D1#$80#$D1#$82#$20#$54#$35#$4D#$3A#$20 + E.Message, 0);
      on E: ED2SourceError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BA#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B8#$20#$44#$32#$3A#$20 + E.Message, E.WordIndex);
    end;
    if Length(Doc.Roots) <> 1 then begin
      AtWord := 1;
      if Length(Doc.Roots) > 1 then AtWord := Doc.Roots[1].WordIndex;
      raise EBinaryExecutionError.CreateAt(
        #$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$BD#$D0#$B0#$20#$D1#$80#$D1#$96#$D0#$B2#$D0#$BD#$D0#$BE#$20#$D0#$BE#$D0#$B4#$D0#$BD#$D0#$B0#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0, AtWord);
    end;
    Source := ProjectNode(Doc.Roots[0], 0);
    { Лише вже злитий native evaluator визначає підтримані D3-виклики.
      Поверхня є тимчасовою адаптацією, а НЕ оракулом семантики SENS. }
    try Result := FNative.EvaluateSource(Source);
    except
      on E: ESourceError do
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BD#$D0#$B0#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C#$20#$D0#$B2#$D1#$96#$D0#$B4#$D1#$85#$D0#$B8#$D0#$BB#$D0#$B8#$D0#$B2#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D1#$83#$3A#$20 + E.Message,
          Doc.Roots[0].WordIndex);
    end;
  finally
    Doc.Free;
  end;
end;
end.
