{ G3.16 — лише механічний ФІЗИЧНИЙ пакет незалежних D3 форм.
  Семантика кожної форми живе виключно в чинному pinned
  TBinaryExecutor.ExecutePhysicalT5M. Не Core4 і не REPL. }
unit wsm.d3batch;
{$mode objfpc}{$H+}
interface
uses SysUtils;

type
  ED3BatchError = class(Exception)
  public
    FormIndex: SizeInt; { 1-based top-level D2 форма; 0 для preflight }
    WordIndex: SizeInt; { 1-based слово початкового .sens; 0 для T5M }
    constructor CreateAt(const MessageText: String;
      AForm, AWord: SizeInt);
  end;

{ Перевіряє лише механічну цілісність уже обчисленої фізичної відповіді.
  Тип: RawByteString packed T5M + host SizeInt (очікувана кількість форм).
  Жодних нових законів SENS; помилка ED3BatchError, без часткового виходу.
  Дочірній TD2Document є приватним і завжди звільняється. }
procedure ValidatePhysicalD3BatchAnswer(const Physical: RawByteString;
  ExpectedForms: SizeInt);

procedure ExecutePhysicalD3Batch(const Physical, AuthorityRoot: RawByteString;
  out Answer: RawByteString; out CompletedForms: SizeInt);

implementation
uses wsm.t5m, wsm.d2source, wsm.binaryexec;

const MaxBatchForms = 64;

constructor ED3BatchError.CreateAt(const MessageText: String;
  AForm, AWord: SizeInt);
begin
  inherited Create(MessageText);
  FormIndex := AForm;
  WordIndex := AWord;
end;

procedure Reject(const Why: String; F, W: SizeInt);
begin
  raise ED3BatchError.CreateAt(Why,F,W);
end;

procedure ValidatePhysicalD3BatchAnswer(const Physical: RawByteString;
  ExpectedForms: SizeInt);
var
  Words: TExactWords;
  Document: TD2Document;
begin
  { Host-квоти — не числові домени SENS. Не оприлюднюємо даних
    до повного DecodeT5M -> ParseD2Words -> root-count admission. }
  if (ExpectedForms < 1) or (ExpectedForms > MaxBatchForms) then
    Reject('кількість очікуваних D3 відповідей поза межею 1..64',0,0);
  if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    Reject('порожня або завелика фізична відповідь D3',0,0);
  Document := nil;
  try
    try
      DecodeT5M(Physical,Words);
      if (Length(Words)=0) or (EncodeT5M(Words)<>Physical) then
        Reject('не канонічні фізичні байти відповіді D3',0,0);
      Document:=ParseD2Words(Words);
    except
      on E:ET5MError do
        Reject('пошкоджені фізичні байти відповіді D3: '+E.Message,0,0);
      on E:ED2SourceError do
        Reject('неправильна структура D2 у відповіді D3: '+E.Message,
          0,E.WordIndex);
    end;
    if Length(Document.Roots)<>ExpectedForms then
      Reject('не збігається кількість кореневих D2 відповідей D3',0,0);
  finally
    Document.Free;
  end;
end;

procedure ExecutePhysicalD3Batch(const Physical, AuthorityRoot: RawByteString;
  out Answer: RawByteString; out CompletedForms: SizeInt);
var
  Doc: TD2Document;
  Engine: TBinaryExecutor;
  InputWords, OneWords, ResultWords, PartWords: TExactWords;
  OnePhysical, PartPhysical, Candidate: RawByteString;
  Root, First, Last, I, J, Used, Capacity, Limit: SizeInt;
begin
  { Жодного часткового результату навіть після успішної ранньої форми. }
  Answer := ''; CompletedForms := 0;
  Doc := nil; Engine := nil; Used := 0; Capacity := 0;
  if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    Reject('порожній або надмірний фізичний пакет D3',0,0);
  try
    try
      DecodeT5M(Physical,InputWords);
      if EncodeT5M(InputWords)<>Physical then
        Reject('фізичний пакет має бути канонічним T5M',0,0);
      Doc := ParseD2Words(InputWords);
    except
      on E:ET5MError do
        Reject('неканонічний фізичний T5M: '+E.Message,0,0);
      on E:ED2SourceError do
        Reject('некоректна структура фізичного D2: '+E.Message,
          0,E.WordIndex);
    end;
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxBatchForms) then
      Reject('пакет дозволяє лише 1..64 незалежні D3 форми',0,0);
    Engine := TBinaryExecutor.Create(AuthorityRoot);
    for Root:=0 to High(Doc.Roots) do begin
      First := Doc.Roots[Root].WordIndex - 1;
      Last := Doc.Roots[Root].EndWordIndexExclusive - 1;
      if (First<0) or (Last<=First) or (Last>Length(InputWords)) then
        Reject('некоректна фізична межа форми D2',Root+1,First+1);
      SetLength(OneWords,Last-First);
      for I:=First to Last-1 do OneWords[I-First]:=InputWords[I];
      OnePhysical:=EncodeT5M(OneWords);
      try
        PartPhysical:=Engine.ExecutePhysicalT5M(OnePhysical);
      except
        on E:EBinaryExecutionError do begin
          if E.WordIndex>0 then
            Reject('фізична форма D3 відхилена: '+E.Message,
              Root+1,First+E.WordIndex)
          else
            Reject('фізична форма D3 відхилена: '+E.Message,Root+1,0);
        end;
      end;
      try
        DecodeT5M(PartPhysical,PartWords);
        if EncodeT5M(PartWords)<>PartPhysical then
          Reject('неканонічний фізичний результат D3',Root+1,First+1);
      except
        on E:ET5MError do
          Reject('пошкоджені байти результату D3: '+E.Message,
            Root+1,First+1);
      end;
      if Length(PartWords)<1 then
        Reject('відсутня фізична відповідь D3',Root+1,First+1);
      if Length(PartWords)>MaxD2Words-Used then
        Reject('результат пакета перевищує межу фізичних слів',
          Root+1,First+1);
      Limit:=Used+Length(PartWords);
      if Limit>Capacity then begin
        if Capacity=0 then Capacity:=16;
        while Capacity<Limit do begin
          if Capacity>MaxD2Words div 2 then begin
            Capacity:=MaxD2Words;
            Break;
          end;
          Capacity:=Capacity*2;
        end;
        SetLength(ResultWords,Capacity);
      end;
      for J:=0 to High(PartWords) do
        ResultWords[Used+J]:=PartWords[J];
      Used:=Limit;
    end;
    SetLength(ResultWords,Used);
    try
      Candidate:=EncodeT5M(ResultWords);
    except
      on E:ET5MError do Reject('результат пакета не вміщується в T5M: '+
        E.Message,0,0);
    end;
    { Не тільки транспорт T5M: ДІЙСНИЙ структурний D2 розбір
      фінальних байтів, рівно один корінь на виконану вхідну форму.
      Жодне значення не публікується до цього незалежного postflight. }
    ValidatePhysicalD3BatchAnswer(Candidate,Length(Doc.Roots));
    Answer:=Candidate;
    CompletedForms:=Length(Doc.Roots);
  finally
    Engine.Free;
    Doc.Free;
  end;
end;
end.
