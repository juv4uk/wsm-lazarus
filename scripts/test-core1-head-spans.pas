{ G3.50 — фізичне місце відхиленої D7-голови у спільному Core1 runtime.
  Немає додаткового evaluator: викликається лише TCore1Dispatch. }
program TestCore1HeadSpans;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
     wsm.core1index, wsm.core1dispatch;

var Index:TCore1Index;
    Runtime:TCore1Dispatch;
    Checked,Rejected:SizeInt;

procedure Need(Ok:Boolean;const Reason:String);
begin
  if not Ok then raise Exception.Create(Reason);
  Inc(Checked);
end;

{ KeyPhysical запозичені canonical T5M bytes, Items — точні слова
  фізичного D4:1110 аргументу. Результат — новий packed T5M;
  передача і життя повністю обмежені цим тестом.
  Питання: чому не можна просто з'єднати два packed T5M файли?
  Де D2 початок/кінець голови? Хто звільняє decoded words? }
function MakeCall(const KeyPhysical:RawByteString):RawByteString;
var Key,Words:TExactWords; I,P:SizeInt;
begin
  DecodeT5M(KeyPhysical,Key);
  SetLength(Words,Length(Key)+8);
  P:=0;Words[P]:='10';Inc(P);
  for I:=0 to High(Key) do begin Words[P]:=Key[I];Inc(P) end;
  Words[P]:='10';Inc(P);
  Words[P]:='1110';Inc(P);
  Words[P]:='1';Inc(P);
  Words[P]:='0';Inc(P);
  Words[P]:='1';Inc(P);
  Words[P]:='01';Inc(P);
  Words[P]:='01';Inc(P);
  Need(P=Length(Words),'пошкоджено структуру тестового виклику');
  Result:=EncodeT5M(Words);
end;

procedure InspectHead(const Physical:RawByteString;
  const Failure:ECore1HeadError);
var Doc:TD2Document; Spans:TPhysicalWordSpans; Expect:TPhysicalNodeSpan;
begin
  Doc:=ReadD2WideWithPhysicalLocations(Physical,Spans);
  try
    Need(Length(Doc.Roots)=1,'не одна фізична форма у свідку');
    Need((Doc.Roots[0]<>nil) and
         (Length(Doc.Roots[0].Children)=2),'пошкоджено фізичний виклик');
    Expect:=LocatePhysicalNodeSpan(Physical,Spans,Doc.Roots[0].Children[0]);
  finally Doc.Free end;
  Need(Failure.Span.WordStart=2,'слово голови починається не з #2');
  Need((Failure.Span.WordStart=Expect.WordStart) and
       (Failure.Span.WordEndExclusive=Expect.WordEndExclusive),
       'невірна 1-based напіввідкрита межа слів');
  Need((Failure.Span.TritStart=Expect.TritStart) and
       (Failure.Span.TritEnd=Expect.TritEnd) and
       (Failure.Span.TritStart=3),
       'невірна точна тритова адреса D7');
  Need((Failure.Span.ByteStart=Expect.ByteStart) and
       (Failure.Span.ByteEnd=Expect.ByteEnd),
       'невірний physical byte-envelope голови');
  Need((Pos('слово=[',Failure.Message)>0) and
       (Pos('трити=[',Failure.Message)>0) and
       (Pos('байти=[',Failure.Message)>0),
       'текст винятку не повідомляє фізичні інтервали');
end;

{ Відмова повинна мати саме фізичне місце; жодна ідентичність
  не визначається текстом помилки чи шириною. }
procedure RejectHead(const Physical:RawByteString;const LabelText:String;
  const Required:String);
var Seen:Boolean;
begin
  Seen:=False;
  try Runtime.ExecutePhysical(Physical)
  except
    on E:ECore1HeadError do begin
      Seen:=True;
      Need(Pos(Required,E.Message)>0,LabelText+': інша причина відмови');
      InspectHead(Physical,E);
    end;
  end;
  Need(Seen,LabelText+': немає структурованої D7-діагностики');
  Inc(Rejected);
end;

procedure RejectDamaged(const Physical:RawByteString);
var Seen:Boolean;
begin
  Seen:=False;
  try Runtime.ExecutePhysical(Physical)
  except on E:Exception do begin
    Need(not (E is ECore1HeadError),
      'пошкоджений фізичний транспорт має відмовити до D7');
    Seen:=True;
  end end;
  Need(Seen,'пошкоджені T5M bytes прийнято');
  Inc(Rejected);
end;

procedure CheckValid;
var Answer,Call:TExactWords;
begin
  DecodeT5M(MakeCall(Index.PhysicalIdentifier(1)),Call);
  Need(Length(Call)>5,'немає справжнього фізичного Core1-виклику');
  DecodeT5M(Runtime.ExecutePhysical(EncodeT5M(Call)),Answer);
  Need((Length(Answer)=1) and (Answer[0]='0'),
       'перше pinned замикання перестало виконуватись');
end;

var Invalid:TExactWords;
begin
  Checked:=0;Rejected:=0;Index:=nil;Runtime:=nil;
  if ParamCount<>1 then Halt(64);
  try
    Index:=TCore1Index.Create(ParamStr(1));
    Runtime:=TCore1Dispatch.Create(ParamStr(1));
    Need((Index.Count=96) and (Runtime.Count=96),
      'не знайдено всі 96 pinned D7-імен');
    CheckValid;
    RejectHead(MakeCall(Index.PhysicalIdentifier(2)),
      'підтримуване лише перше ім’я','не підтримано');
    RejectHead(MakeCall(Index.PhysicalIdentifier(96)),
      'останнє pinned ім’я','не підтримано');
    SetLength(Invalid,3);
    Invalid[0]:='10';Invalid[1]:='0000000';Invalid[2]:='01';
    RejectHead(MakeCall(EncodeT5M(Invalid)),
      'неіснуюча D7-послідовність','невідоме');
    Invalid[1]:='0';
    RejectHead(MakeCall(EncodeT5M(Invalid)),
      'інший фізичний домен','невірне точне слово');
    RejectDamaged(MakeCall(Index.PhysicalIdentifier(1))+AnsiChar(243));
    CheckValid; { один збережений pinned runtime після ВСІХ відмов }
    WriteLn('CORE1-ФІЗИЧНІ-ГОЛОВИ-ГАРАЗД FPC=так ',
      'визначень=96 відмов=',Rejected,' перевірок=',Checked,
      ' голова=слово/трити/байти відновлення=так ',
      'D7=точно D12+=без-перетлумачення');
  finally
    Runtime.Free;Index.Free;
  end;
end.
