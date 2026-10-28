{ G2.7. Двійкове зв'язування без текстової проєкції як джерела істини.
  Вхід: фізичний T5M -> структурний D2 AST, уже наявні реалізації.
  Бінарні координати первинні. «ук» — тільки необов'язкова проєкція.
  Немає висновків про викличність, арифметику, значення чи виконання. }
unit wsm.binarybind;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind;
type
  EBinaryBindError = class(Exception);
  TBinaryWord = record
    Key: TDomainKey;             { точні width + bits, не host integer }
    WordIndex: SizeInt;          { фізичне слово, починаючи з 1 }
    RootIndex: SizeInt;          { верхня форма, починаючи з 0 }
    IsEmpty: Boolean;            { D3:000, не D1:0 }
    Ukrainian: RawByteString;    { «ук» із pinned таблиці; може бути порожня }
  end;
  TBinaryWords = array of TBinaryWord;

procedure BindD2Binary(const Document: TD2Document;
  const Tables: TDomainSet; out Bound: TBinaryWords);
procedure BindT5MBinary(const Physical: RawByteString;
  const Tables: TDomainSet; out Bound: TBinaryWords);

implementation
type
  TPending = record
    Node: TD2Node;
    RootIndex: SizeInt;
  end;

procedure BindD2Binary(const Document: TD2Document;
  const Tables: TDomainSet; out Bound: TBinaryWords);
var Candidate: TBinaryWords;
    Stack: array of TPending;
    StackCount, StackCapacity, Count, Capacity, I, J, Width: SizeInt;
    Pending: TPending;
    Node: TD2Node;
    Key: TDomainKey;
    Row: TDomainRow;
    Value: TBinaryWord;
  procedure Push(N: TD2Node; Root: SizeInt);
  begin
    if N = nil then raise EBinaryBindError.Create('відсутній вузол D2');
    if StackCount >= MaxD2Words then
      raise EBinaryBindError.Create('перевищено межу вузлів D2');
    if StackCount = StackCapacity then begin
      if StackCapacity = 0 then StackCapacity := 16
      else StackCapacity := StackCapacity * 2;
      if StackCapacity > MaxD2Words then StackCapacity := MaxD2Words;
      SetLength(Stack, StackCapacity);
    end;
    Stack[StackCount].Node := N;
    Stack[StackCount].RootIndex := Root;
    Inc(StackCount);
  end;
  procedure Append(const Item: TBinaryWord);
  begin
    if Count >= MaxD2Words then
      raise EBinaryBindError.Create('перевищено межу двійкових слів');
    if Count = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity * 2;
      if Capacity > MaxD2Words then Capacity := MaxD2Words;
      SetLength(Candidate, Capacity);
    end;
    Candidate[Count] := Item;
    Inc(Count);
  end;
begin
  SetLength(Bound, 0);
  SetLength(Candidate, 0);
  if Document = nil then raise EBinaryBindError.Create('відсутній документ D2');
  { Довідкові таблиці повинні бути повними; порожня поверхня не означає
    відсутність двійкової координати. }
  for I := 1 to 9 do
    if Length(Tables[I]) <> (SizeInt(1) shl I) then
      raise EBinaryBindError.Create('неповна pinned таблиця домену');
  StackCount := 0; StackCapacity := 0;
  Count := 0; Capacity := 0;
  for I := High(Document.Roots) downto 0 do Push(Document.Roots[I], I);
  while StackCount > 0 do begin
    Dec(StackCount);
    Pending := Stack[StackCount];
    Node := Pending.Node;
    case Node.Kind of
      dkList, dkPair: begin
        if (Node.Kind = dkPair) and (Length(Node.Children) <> 2) then
          raise EBinaryBindError.Create('некоректна структура крапкової пари');
        for J := High(Node.Children) downto 0 do
          Push(Node.Children[J], Pending.RootIndex);
      end;
      dkIdentity, dkEmpty: begin
        if Length(Node.Children) <> 0 then
          raise EBinaryBindError.Create('двійковий атом містить нащадків');
        if (Node.WordIndex < 1) or (Node.WordIndex > MaxD2Words) then
          raise EBinaryBindError.Create('некоректний індекс фізичного слова');
        Width := Length(Node.Bits);
        if (Width < 1) or (Width > 9) or (Width = 2) or
           (Node.Width <> Width) then
          raise EBinaryBindError.Create('неприпустима фізична ширина слова');
        if (Node.Kind = dkEmpty) <> (Node.Bits = '000') then
          raise EBinaryBindError.Create('порушено окрему тотожність D3:000');
        try
          Key := ExactKey(Node.Bits);
        except
          on E: EDomainError do
            raise EBinaryBindError.Create('небінарне фізичне слово');
        end;
        if not DomainRowByKey(Tables[Width], Key, Row) then
          raise EBinaryBindError.Create('немає координати в pinned таблиці');
        Value.Key := Key;
        Value.WordIndex := Node.WordIndex;
        Value.RootIndex := Pending.RootIndex;
        Value.IsEmpty := Node.Kind = dkEmpty;
        Value.Ukrainian := Row.Ukrainian;
        Append(Value);
      end;
      else raise EBinaryBindError.Create('невідомий тип вузла D2');
    end;
  end;
  { До повного успіху жоден частковий результат не стає видимим. }
  SetLength(Candidate, Count);
  Bound := Candidate;
end;

procedure BindT5MBinary(const Physical: RawByteString;
  const Tables: TDomainSet; out Bound: TBinaryWords);
var Document: TD2Document;
begin
  Document := ReadD2T5M(Physical);
  try
    BindD2Binary(Document, Tables, Bound);
  finally
    Document.Free;
  end;
end;

end.
