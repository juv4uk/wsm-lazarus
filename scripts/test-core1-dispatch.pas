{ Core1.4 — справжній інтеграційний тест двох уже існуючих модулів.
  Індекс бере реальний pinned core1.sens, замикання виконує чинний D4.
  Жодної текстової функції, числового D12 закону або нового evaluator. }
program TestCore1Dispatch;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1index, wsm.core1dispatch;

var
  Index:TCore1Index;
  Dispatcher:TCore1Dispatch;
  Passed,KnownBlocked:SizeInt;

procedure Check(Ok:Boolean; const Why:String);
begin
  if not Ok then raise Exception.Create(Why);
  Inc(Passed);
end;

{ Загальна фізична форма (D7-key (D4:1110 elements...)).
  Key — тільки canonical T5M із pinned index, не UTF-8 слово.
  Result — новий T5M без неявного surface packing. }
function MakeCall(const KeyPhysical:RawByteString;
  const Elements:TExactWords):RawByteString;
var
  KeyWords,Words:TExactWords;
  I,N:SizeInt;
begin
  DecodeT5M(KeyPhysical,KeyWords);
  SetLength(Words,Length(KeyWords)+Length(Elements)+5);
  N:=0;
  Words[N]:='10';Inc(N);
  for I:=0 to High(KeyWords) do begin
    Words[N]:=KeyWords[I];Inc(N);
  end;
  Words[N]:='10';Inc(N);
  Words[N]:='1110';Inc(N);
  for I:=0 to High(Elements) do begin
    Words[N]:=Elements[I];Inc(N);
  end;
  Words[N]:='01';Inc(N);
  Words[N]:='01';Inc(N);
  Check(N=Length(Words),'пошкоджений тестовий D2 конструктор');
  Result:=EncodeT5M(Words);
end;

function CallOrdinal(Ordinal:SizeInt;
  const Elements:TExactWords):RawByteString;
begin
  Result:=MakeCall(Index.PhysicalIdentifier(Ordinal),Elements);
end;

{ Перевірка відмови НЕ друкує stdout і не стирає long-lived runtime;
  відкинутий T5M не може повертати D3:000 чи D1:0 замість помилки. }
procedure Reject(const Physical:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try
    Dispatcher.ExecutePhysical(Physical);
  except
    on E:Exception do Rejected:=True;
  end;
  Check(Rejected,Why);
end;

procedure AnswerIs(const Elements:TExactWords; const Bits:RawByteString);
var
  Answer,Repeated,Expected:RawByteString;
  One:TExactWords;
begin
  SetLength(One,1);
  One[0]:=Bits;
  Expected:=EncodeT5M(One);
  Answer:=Dispatcher.ExecutePhysical(CallOrdinal(1,Elements));
  Repeated:=Dispatcher.ExecutePhysical(CallOrdinal(1,Elements));
  Check(Answer=Expected,'фізичний Core1 результат не збігається із точним T5M');
  Check(Repeated=Expected,'повторний виклик змінив семантичну відповідь');
end;

procedure ShowSuccess;
var S:RawByteString; OutStream:THandleStream;
begin
  S:=RawByteString(UTF8Encode(UnicodeString(
    'CORE1-МАРШРУТ-ГАРАЗД фізичних-визначень=')))+
      RawByteString(IntToStr(Index.Count))+
      RawByteString(UTF8Encode(UnicodeString(
      ' відхилено-відомих=')))+RawByteString(IntToStr(KnownBlocked))+
      RawByteString(UTF8Encode(UnicodeString(
      ' перевірок=')))+RawByteString(IntToStr(Passed))+
      RawByteString(UTF8Encode(UnicodeString(
      ' D7=точний виконання=перше GC=без-змін')))+#10;
  OutStream:=THandleStream.Create(TextRec(Output).Handle);
  try
    OutStream.WriteBuffer(S[1],Length(S));
  finally
    OutStream.Free;
  end;
end;

var
  Elements,InvalidName:TExactWords;
  I:SizeInt;
  Physical,Good:RawByteString;
begin
  Passed:=0;KnownBlocked:=0; Index:=nil; Dispatcher:=nil;
  if ParamCount<>1 then Halt(64);
  try
    Index:=TCore1Index.Create(ParamStr(1));
    Dispatcher:=TCore1Dispatch.Create(ParamStr(1));
    Check((Index.Count=96) and (Dispatcher.Count=Index.Count),
      'потрібні 96 pinned фізичних визначень');
    Check(Index.FindPhysicalDefinition(Index.PhysicalIdentifier(1))=
      Index.PhysicalDefinition(1),'перше DEFINE не шукається за точним D7');
    SetLength(Elements,3);
    Elements[0]:='1';Elements[1]:='0';Elements[2]:='1';
    Good:=CallOrdinal(1,Elements);
    AnswerIs(Elements,'0');
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';
    AnswerIs(Elements,'1');
    Elements[0]:='1';Elements[1]:='000000000000000000000001';
    Elements[2]:='0';AnswerIs(Elements,Elements[1]);

    { Всі 95 справжніх але ще НЕ підтриманих pinned D7 ідентифікаторів
      мають відмовити, а не тихо виконати ПЕРШЕ замикання. }
    for I:=2 to Index.Count do begin
      Physical:=CallOrdinal(I,Elements);
      Reject(Physical,'відоме інше DEFINE не повинно виконатись');
      Inc(KnownBlocked);
    end;
    Check(KnownBlocked=95,'не всі 95 визначень fail-closed');

    { Незнайоме D7 і неправдиві/пошкоджені фізичні виклики. }
    SetLength(InvalidName,3);
    InvalidName[0]:='10';InvalidName[1]:='0000000';
    InvalidName[2]:='01';
    Reject(MakeCall(EncodeT5M(InvalidName),Elements),
      'невідоме D7 визначення прийнято');
    Reject('', 'порожній фізичний вхід');
    Reject(AnsiChar(243),'пошкоджений T5M прийнято');
    Reject(Good+#0,'неканонічний хвіст T5M прийнято');
    Reject(Good+Good,'два top-level D2-корені прийнято');
    SetLength(Elements,1);
    Elements[0]:='1';
    Reject(CallOrdinal(1,Elements),'закороткий аргумент прийнято');

    { Той самий native dispatcher знову працює ПІСЛЯ всіх відмов. }
    SetLength(Elements,3);
    Elements[0]:='1';Elements[1]:='0';Elements[2]:='1';
    AnswerIs(Elements,'0');
    ShowSuccess;
  finally
    Dispatcher.Free;
    Index.Free;
  end;
end.
