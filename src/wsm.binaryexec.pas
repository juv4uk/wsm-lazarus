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
  if N = nil then Fail(N, 'відсутній вузол двійкової структури');
  if Depth > 128 then Fail(N, 'перевищена межа вкладеності проєкції');
  case N.Kind of
    dkEmpty: begin
      if (N.Width <> 3) or (N.Bits <> '000') then
        Fail(N, 'порушена координата порожнього D3');
      Result := '()';
    end;
    dkIdentity: begin
      if (N.Width <> 1) and (N.Width <> 3) then
        Fail(N, 'цей домен ще не має перевіреного шляху виконання');
      try Key := ExactKey(N.Bits);
      except on E: EDomainError do
        Fail(N, 'некоректні біти доменної координати');
      end;
      if (Key.Width <> N.Width) or
         not DomainRowByKey(FDomains[Key.Width], Key, Row) or
         (Row.Ukrainian = '') then
        Fail(N, 'немає однозначної української проєкції pinned SENS');
      Result := Row.Ukrainian;
    end;
    dkList: begin
      if (Length(N.Children) > 0) and
         (N.Children[0] <> nil) and
         (N.Children[0].Kind = dkIdentity) and
         (N.Children[0].Width = 3) and
         (N.Children[0].Bits = '001') then
        Fail(N.Children[0],
          'двійкова цитата D3 поки не має доведеної безвтратної проєкції');
      Result := '(';
      for I := 0 to High(N.Children) do begin
        if I > 0 then Result := Result + ' ';
        Part := ProjectNode(N.Children[I], Depth + 1);
        if Length(Result) > MaxProjectionBytes - Length(Part) - 1 then
          Fail(N, 'перевищено межу внутрішньої проєкції');
        Result := Result + Part;
      end;
      Result := Result + ')';
    end;
    dkPair: begin
      Fail(N, 'D2 dotted-пара не допускається через текстовий місток');
      Result := '';
    end;
  else
    Fail(N, 'невідомий вид структурного вузла');
    Result := '';
  end;
  if Length(Result) > MaxProjectionBytes then
    Fail(N, 'перевищено межу внутрішньої проєкції');
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
          'пошкоджений двійковий транспорт T5M: ' + E.Message, 0);
      on E: ED2SourceError do
        raise EBinaryExecutionError.CreateAt(
          'помилка фізичної структури D2: ' + E.Message, E.WordIndex);
    end;
    if Length(Doc.Roots) <> 1 then begin
      AtWord := 1;
      if Length(Doc.Roots) > 1 then AtWord := Doc.Roots[1].WordIndex;
      raise EBinaryExecutionError.CreateAt(
        'потрібна рівно одна двійкова форма', AtWord);
    end;
    Source := ProjectNode(Doc.Roots[0], 0);
    { Лише вже злитий native evaluator визначає підтримані D3-виклики.
      Поверхня є тимчасовою адаптацією, а НЕ оракулом семантики SENS. }
    try Result := FNative.EvaluateSource(Source);
    except
      on E: ESourceError do
        raise EBinaryExecutionError.CreateAt(
          'наявний нативний виконавець відхилив форму: ' + E.Message,
          Doc.Roots[0].WordIndex);
    end;
  finally
    Doc.Free;
  end;
end;
end.
