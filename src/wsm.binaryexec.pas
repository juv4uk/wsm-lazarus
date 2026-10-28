{ Вузький фізичний місток: T5M/D2 -> pinned українська проєкція ->
  ВЖЕ наявний D3 виконавець. Проєкція не є мовним законом чи оракулом.
  Цитати та dotted-пари відхиляються, бо втратили б точну ідентичність. }
unit wsm.binaryexec;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.bind, wsm.domain, wsm.d2source, wsm.nativeeval;
type
  { Приватний механічний слід байтів проєкції, не доменна семантика. }
  TProjectionMark = record
    StartByte, EndByte, WordIndex, Depth: SizeInt;
  end;
  TProjectionMarks = array of TProjectionMark;
  EBinaryExecutionError = class(Exception)
  public
    WordIndex: SizeInt; { 1-based; 0 якщо T5M відкинутий до розбору слів }
    constructor CreateAt(const Problem: String; AtWord: SizeInt);
  end;
  TBinaryExecutor = class
  private
    FDomains: TDomainSet;
    FNative: TNativeEvaluator;
    procedure ProjectNode(N: TD2Node; Depth: SizeInt;
      var Projection: RawByteString; var Marks: TProjectionMarks);
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

{ Одна побудова проєкції та її byte-to-word provenance.
  Start/End — 1-based half-open БАЙТИ тимчасової UTF-8 проєкції.
  Кожна позиція вписується у вкладені діапазони; найглибший
  вузол дає слово-джерело помилки, без вгадування нового закону. }
procedure TBinaryExecutor.ProjectNode(N: TD2Node; Depth: SizeInt;
  var Projection: RawByteString; var Marks: TProjectionMarks);
var I, MIndex: SizeInt; Key: TDomainKey; Row: TDomainRow;
  procedure AppendChecked(const Part: RawByteString);
  begin
    if Length(Part)>MaxProjectionBytes-Length(Projection) then
      Fail(N, #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D1#$83#$20#$D0#$B2#$D0#$BD#$D1#$83#$D1#$82#$D1#$80#$D1#$96#$D1#$88#$D0#$BD#$D1#$8C#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
    Projection:=Projection+Part;
  end;
begin
  if N=nil then Fail(N, #$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$BE#$D1#$97#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B8);
  if Depth>128 then Fail(N, #$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D0#$B0#$20#$D0#$B2#$D0#$BA#$D0#$BB#$D0#$B0#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$BE#$D1#$81#$D1#$82#$D1#$96#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
  MIndex:=Length(Marks);
  SetLength(Marks,MIndex+1);
  Marks[MIndex].StartByte:=Length(Projection)+1;
  Marks[MIndex].WordIndex:=N.WordIndex;
  Marks[MIndex].Depth:=Depth;
  case N.Kind of
    dkEmpty: begin
      if (N.Width<>3) or (N.Bits<>'000') then
        Fail(N, #$D0#$BF#$D0#$BE#$D1#$80#$D1#$83#$D1#$88#$D0#$B5#$D0#$BD#$D0#$B0#$20#$D0#$BA#$D0#$BE#$D0#$BE#$D1#$80#$D0#$B4#$D0#$B8#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B0#$20#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$8C#$D0#$BE#$D0#$B3#$D0#$BE#$20#$44#$33);
      AppendChecked('()');
    end;
    dkIdentity: begin
      if (N.Width<>1) and (N.Width<>3) then
        Fail(N, #$D1#$86#$D0#$B5#$D0#$B9#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$20#$D1#$89#$D0#$B5#$20#$D0#$BD#$D0#$B5#$20#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$B5#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$88#$D0#$BB#$D1#$8F#$D1#$85#$D1#$83#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F);
      try Key:=ExactKey(N.Bits);
      except on E:EDomainError do
        Fail(N, #$D0#$BD#$D0#$B5#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BD#$D1#$96#$20#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8#$20#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BA#$D0#$BE#$D0#$BE#$D1#$80#$D0#$B4#$D0#$B8#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8); end;
      if (Key.Width<>N.Width) or
         not DomainRowByKey(FDomains[Key.Width],Key,Row) or
         (Row.Ukrainian='') then
        Fail(N, #$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$BE#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D1#$83#$D0#$BA#$D1#$80#$D0#$B0#$D1#$97#$D0#$BD#$D1#$81#$D1#$8C#$D0#$BA#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97#$20#$70#$69#$6E#$6E#$65#$64#$20#$53#$45#$4E#$53);
      AppendChecked(Row.Ukrainian);
    end;
    dkList: begin
      if (Length(N.Children)>0) and
         (N.Children[0]<>nil) and
         (N.Children[0].Kind=dkIdentity) and
         (N.Children[0].Width=3) and
         (N.Children[0].Bits='001') then
        Fail(N.Children[0], #$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0#$20#$44#$33#$20#$D0#$BF#$D0#$BE#$D0#$BA#$D0#$B8#$20#$D0#$BD#$D0#$B5#$20#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$B4#$D0#$BE#$D0#$B2#$D0#$B5#$D0#$B4#$D0#$B5#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$B1#$D0#$B5#$D0#$B7#$D0#$B2#$D1#$82#$D1#$80#$D0#$B0#$D1#$82#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$97);
      AppendChecked('(');
      for I:=0 to High(N.Children) do begin
        if I>0 then AppendChecked(' ');
        ProjectNode(N.Children[I],Depth+1,Projection,Marks);
      end;
      AppendChecked(')');
    end;
    dkPair:
      Fail(N, #$44#$32#$20#$D0#$BA#$D1#$80#$D0#$B0#$D0#$BF#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D0#$BF#$D0#$B0#$D1#$80#$D0#$B0#$20#$D0#$BD#$D0#$B5#$20#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$81#$D0#$BA#$D0#$B0#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F#$20#$D1#$87#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B7#$20#$D1#$82#$D0#$B5#$D0#$BA#$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$BC#$D1#$96#$D1#$81#$D1#$82#$D0#$BE#$D0#$BA);
  else
    Fail(N, #$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$B4#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0);
  end;
  Marks[MIndex].EndByte:=Length(Projection)+1;
end;

function TBinaryExecutor.ExecutePhysical(
  const Physical: RawByteString): RawByteString;
var Doc: TD2Document; Source: RawByteString; AtWord,I,BestDepth: SizeInt;
  Marks:TProjectionMarks;
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
    Source:='';
    SetLength(Marks,0);
    ProjectNode(Doc.Roots[0],0,Source,Marks);
    { Лише вже злитий native evaluator визначає підтримані D3-виклики.
      Поверхня є тимчасовою адаптацією, а НЕ оракулом семантики SENS. }
    try Result := FNative.EvaluateSource(Source);
    except
      on E: ESourceError do begin
        { Відхилення з тимчасового UTF-8 AST локалізуємо у фізичному
          T5M/D2 слові. Жодних припущень про викличність. }
        AtWord:=0;
        BestDepth:=-1;
        if (E.ByteOffset>=1) and (E.ByteOffset<=Length(Source)) then
          for I:=0 to High(Marks) do
            if (E.ByteOffset>=Marks[I].StartByte) and
               (E.ByteOffset<Marks[I].EndByte) and
               (Marks[I].Depth>=BestDepth) then begin
              AtWord:=Marks[I].WordIndex;
              BestDepth:=Marks[I].Depth;
            end;
        raise EBinaryExecutionError.CreateAt(
          #$D0#$BD#$D0#$B0#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C#$20#$D0#$B2#$D1#$96#$D0#$B4#$D1#$85#$D0#$B8#$D0#$BB#$D0#$B8#$D0#$B2#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D1#$83#$3A#$20 + E.Message,
          AtWord);
      end;
    end;
  finally
    Doc.Free;
  end;
end;
end.
