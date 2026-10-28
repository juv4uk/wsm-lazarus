{ G5.9 — кілька фізичних верхніх форм без другого evaluator або reader.
  Вхід: один канонічний .sens/T5M; структура — готовий D2 AST.
  Вихід: значення існуючого TBinaryExecutor, лише після повного успіху.
  Кожна форма незалежна: цей механізм не обіцяє persistent REPL. }
unit wsm.binarybatch;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.binaryexec;
const MaxBatchRoots = 1024;
type
  EBinaryBatchError = class(Exception)
  public
    RootIndex, WordIndex: SizeInt; { корінь 0-based, слово 1-based }
    constructor CreateAt(const Why: String; Root, Word: SizeInt);
  end;
  TBinaryBatchAnswers = array of RawByteString;

procedure ExecuteBinaryBatch(const Physical: RawByteString;
  Executor: TBinaryExecutor; out Answers: TBinaryBatchAnswers);

implementation
uses wsm.t5m, wsm.d2source;

constructor EBinaryBatchError.CreateAt(
  const Why: String; Root, Word: SizeInt);
begin
  inherited Create(Why);
  RootIndex := Root;
  WordIndex := Word;
end;

procedure ExecuteBinaryBatch(const Physical: RawByteString;
  Executor: TBinaryExecutor; out Answers: TBinaryBatchAnswers);
var
  Words, Part: TExactWords;
  Doc: TD2Document;
  Candidate: TBinaryBatchAnswers;
  I, J, StartWord, EndWord, N: SizeInt;
begin
  SetLength(Answers, 0);
  if Executor = nil then
    raise EBinaryBatchError.CreateAt(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C,0,0);
  Doc := nil;
  try
    { Транспорт і D2 перевіряються ПОВНІСТЮ до першого виконання. }
    try
      DecodeT5M(Physical, Words);
    except
      on E: ET5MError do
        raise EBinaryBatchError.CreateAt(
          #$D0#$BD#$D0#$B5#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$54#$35#$4D#$3A#$20+E.Message,0,0);
    end;
    try
      Doc := ParseD2Words(Words);
    except
      on E: ED2SourceError do
        raise EBinaryBatchError.CreateAt(
          #$D0#$BD#$D0#$B5#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BD#$D0#$B0#$20#$D1#$81#$D1#$82#$D1#$80#$D1#$83#$D0#$BA#$D1#$82#$D1#$83#$D1#$80#$D0#$B0#$20#$44#$32#$3A#$20+E.Message,0,E.WordIndex);
    end;
    N := Length(Doc.Roots);
    if (N < 1) or (N > MaxBatchRoots) then
      raise EBinaryBatchError.CreateAt(
        #$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B8#$D0#$BF#$D1#$83#$D1#$81#$D1#$82#$D0#$B8#$D0#$BC#$D0#$B0#$20#$D0#$BA#$D1#$96#$D0#$BB#$D1#$8C#$D0#$BA#$D1#$96#$D1#$81#$D1#$82#$D1#$8C#$20#$D0#$B2#$D0#$B5#$D1#$80#$D1#$85#$D0#$BD#$D1#$96#$D1#$85#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC,0,0);
    SetLength(Candidate, N);
    for I := 0 to N-1 do begin
      if Doc.Roots[I] = nil then
        raise EBinaryBatchError.CreateAt(
          #$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$8F#$20#$D0#$B2#$D0#$B5#$D1#$80#$D1#$85#$D0#$BD#$D1#$8F#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0#$20#$44#$32,I,0);
      StartWord := Doc.Roots[I].WordIndex;
      if I+1 < N then
        EndWord := Doc.Roots[I+1].WordIndex-1
      else
        EndWord := Length(Words);
      if (StartWord < 1) or (EndWord < StartWord) or
         (EndWord > Length(Words)) then
        raise EBinaryBatchError.CreateAt(
          #$D0#$BD#$D0#$B5#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BD#$D1#$96#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D1#$96#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D1#$96#$20#$D0#$B2#$D0#$B5#$D1#$80#$D1#$85#$D0#$BD#$D1#$8C#$D0#$BE#$D1#$97#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B8,I,StartWord);
      SetLength(Part, EndWord-StartWord+1);
      for J := 0 to High(Part) do
        Part[J] := Words[StartWord+J-1];
      try
        { Повторне пакування лише транспорту для існуючого single-root
          executor, не створення нової surface чи D3 dispatch. }
        Candidate[I] := Executor.ExecutePhysical(EncodeT5M(Part));
      except
        on E: EBinaryExecutionError do begin
          if E.WordIndex > 0 then
            raise EBinaryBatchError.CreateAt(E.Message,I,
              StartWord+E.WordIndex-1);
          raise EBinaryBatchError.CreateAt(E.Message,I,0);
        end;
      end;
    end;
    { Жоден результат не доступний до завершення останнього кореня. }
    Answers := Candidate;
  finally
    Doc.Free;
  end;
end;
end.
