program test_binarybind;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind,
  wsm.binarybind;
var Tables: TDomainSet; W, Roundtrip: TExactWords;
    Items: TBinaryWords; Doc: TD2Document;
    B: RawByteString; I: SizeInt; Failed: Boolean;
procedure Check(Value: Boolean; const Why: String);
begin
  if not Value then begin WriteLn(StdErr,'BINARYBIND-FAIL ',Why); Halt(1); end;
end;
function WordsOf(const Data: array of RawByteString): TExactWords;
var K: SizeInt;
begin
  SetLength(Result, Length(Data));
  for K:=0 to High(Data) do Result[K]:=Data[K];
end;
begin
  LoadPinnedDomains('external/sens', Tables);
  { Реальний фізичний T5M, а не український текст як оракул. }
  W:=WordsOf(['10','111','00','1','000','01']);
  B:=EncodeT5M(W);
  DecodeT5M(B,Roundtrip);
  Check(Length(W)=Length(Roundtrip),'кількість фізичних слів');
  for I:=0 to High(W) do Check(W[I]=Roundtrip[I],'побітова оборотність T5M');
  BindT5MBinary(B,Tables,Items);
  Check(Length(Items)=3,'кількість двійкових атомів');
  Check((Items[0].WordIndex=2) and (Items[0].RootIndex=0) and
    SameKey(Items[0].Key,ExactKey('111')) and
    (Items[0].Ukrainian='сполучити') and not Items[0].IsEmpty,
    'D3:111, проєкція лише після тотожності');
  Check((Items[1].WordIndex=4) and
    SameKey(Items[1].Key,ExactKey('1')) and
    (Items[1].Ukrainian='так'),'D1:1');
  Check((Items[2].WordIndex=5) and Items[2].IsEmpty and
    SameKey(Items[2].Key,ExactKey('000')) and
    (Items[2].Key.Width=3),'порожня структура D3:000');
  Check(not SameKey(Items[2].Key,ExactKey('0')),
    'D3:000 не дорівнює D1:0');
  Check(not SameKey(Items[2].Key,ExactKey('00')),
    'D3:000 не дорівнює D2:00');

  W:=WordsOf(['0','00','1']);
  BindT5MBinary(EncodeT5M(W),Tables,Items);
  Check(Length(Items)=2,'дві кореневі форми');
  Check((Items[0].RootIndex=0) and (Items[0].WordIndex=1) and
    SameKey(Items[0].Key,ExactKey('0')),'перший корінь D1:0');
  Check((Items[1].RootIndex=1) and (Items[1].WordIndex=3) and
    SameKey(Items[1].Key,ExactKey('1')),'другий корінь D1:1');

  W:=WordsOf(['10','1','11','0','01']);
  BindT5MBinary(EncodeT5M(W),Tables,Items);
  Check(Length(Items)=2,'крапкова пара має два фізичні атоми');
  Check((Items[0].WordIndex=2) and (Items[1].WordIndex=4) and
    SameKey(Items[0].Key,ExactKey('1')) and
    SameKey(Items[1].Key,ExactKey('0')),
    'крапкова пара зберегла точні координати');

  Failed:=False;
  try BindD2Binary(nil,Tables,Items);
  except on E:EBinaryBindError do Failed:=True; end;
  Check(Failed,'відсутній AST прийнято');

  W:=WordsOf(['1']);
  Doc:=ParseD2Words(W);
  try
    SetLength(Tables[1],0);
    Failed:=False;
    try BindD2Binary(Doc,Tables,Items);
    except on E:EBinaryBindError do Failed:=True; end;
    Check(Failed,'неповну pinned таблицю прийнято');
  finally Doc.Free; end;

  LoadPinnedDomains('external/sens',Tables);
  { Атомарний fail-closed: перший атом уже пройшов, другий помилковий.
    Після винятку не можна повертати ані префікс, ані старе значення. }
  Doc:=TD2Document.Create;
  try
    Doc.Add(TD2Node.Create);
    Doc.Roots[0].Kind:=dkList;
    Doc.Roots[0].WordIndex:=1;
    Doc.Roots[0].Add(TD2Node.Create);
    Doc.Roots[0].Children[0].Kind:=dkIdentity;
    Doc.Roots[0].Children[0].Bits:='1';
    Doc.Roots[0].Children[0].Width:=1;
    Doc.Roots[0].Children[0].WordIndex:=2;
    Doc.Roots[0].Add(TD2Node.Create);
    Doc.Roots[0].Children[1].Kind:=dkIdentity;
    Doc.Roots[0].Children[1].Bits:='11';
    Doc.Roots[0].Children[1].Width:=2;
    Doc.Roots[0].Children[1].WordIndex:=3;
    SetLength(Items,1);
    Items[0].Key:=ExactKey('0');
    Failed:=False;
    try BindD2Binary(Doc,Tables,Items);
    except on E:EBinaryBindError do Failed:=True; end;
    Check(Failed,'неприпустимий другий атом не відхилено');
    Check(Length(Items)=0,'частковий або старий результат після помилки binder');
  finally Doc.Free; end;

  Doc:=TD2Document.Create;
  try
    Doc.Add(TD2Node.Create);
    Doc.Roots[0].Kind:=dkIdentity;
    Doc.Roots[0].Bits:='11';
    Doc.Roots[0].Width:=2;
    Doc.Roots[0].WordIndex:=1;
    Failed:=False;
    try BindD2Binary(Doc,Tables,Items);
    except on E:EBinaryBindError do Failed:=True; end;
    Check(Failed,'структурний D2 прикидається доменною тотожністю');
    Doc.Roots[0].Bits:='000';
    Doc.Roots[0].Width:=3;
    Failed:=False;
    try BindD2Binary(Doc,Tables,Items);
    except on E:EBinaryBindError do Failed:=True; end;
    Check(Failed,'D3:000 прикидається звичайним атомом');
    Doc.Roots[0].Kind:=dkEmpty;
    Doc.Roots[0].Bits:='0';
    Doc.Roots[0].Width:=1;
    Failed:=False;
    try BindD2Binary(Doc,Tables,Items);
    except on E:EBinaryBindError do Failed:=True; end;
    Check(Failed,'D1:0 прикидається порожньою структурою');
  finally Doc.Free; end;

  Failed:=False;
  try BindT5MBinary(#243,Tables,Items);
  except on E:ET5MError do Failed:=True; end;
  Check(Failed,'неприпустимий фізичний байт T5M прийнято');

  WriteLn('ДВІЙКОВЕ-ЗВЯЗУВАННЯ-ГАРАЗД: T5M=так D2=структура ',
    'координати=точні українська=проєкція викличність=не-доведено');
end.
