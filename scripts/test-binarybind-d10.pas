{ G2.43 — фізичний W10 є D10 лише за явною pinned доменною координатою.
  Жодної автоматичної числової семантики D12+ чи текстового dispatch. }
program test_binarybind_d10;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind,
     wsm.binarybind;
var Tables:TDomainSet; Values:TBinaryWords; Words:TExactWords;
    Physical:RawByteString; Doc:TD2Document; Positives,Negatives:SizeInt;
procedure Check(Condition:Boolean;const MessageText:String);
begin
  if not Condition then begin
    WriteLn(StdErr,'D10-ЗВЯЗУВАННЯ-ПОМИЛКА: ',MessageText);
    Halt(1);
  end;
end;
function ExactWords(const Input:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Input));
  for I:=0 to High(Input) do Result[I]:=Input[I];
end;
procedure MustReject(const Data:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  SetLength(Values,1);
  Values[0].Key:=ExactKey('1');
  try
    BindT5MBinaryD10(Data,Tables,Values);
  except
    on E:Exception do Rejected:=True;
  end;
  Check(Rejected,Why+': прийнято пошкоджений фізичний ввід');
  Check(Length(Values)=0,Why+': оприлюднено старий або частковий результат');
  Inc(Negatives);
end;
begin
  Check(ParamCount=0,'запуск без аргументів із кореня репозиторію');
  LoadPinnedDomains('external/sens',Tables);
  Check(Length(Tables[10])=1024,'неповна pinned таблиця D10');
  Words:=ExactWords(['0000000000','00','1111111111','00',
                     '0010110','00','1']);
  Physical:=EncodeT5M(Words);
  Check(Length(Physical)>0,'немає канонічних фізичних байтів');
  BindT5MBinaryD10(Physical,Tables,Values);
  Check(Length(Values)=4,'чотири корені W10, W10, W7, W1');
  Check((Values[0].WordIndex=1) and (Values[0].RootIndex=0) and
        SameKey(Values[0].Key,ExactKey('0000000000')),
        'D10:0000000000 із усіма провідними нулями');
  Check((Values[1].WordIndex=3) and (Values[1].RootIndex=1) and
        SameKey(Values[1].Key,ExactKey('1111111111')),
        'D10:1111111111');
  Check((Values[2].WordIndex=5) and (Values[2].RootIndex=2) and
        SameKey(Values[2].Key,ExactKey('0010110')) and
        (Values[2].Key.Width=7),'SYN — pinned D7 дані, не команда');
  Check((Values[3].WordIndex=7) and (Values[3].RootIndex=3) and
        SameKey(Values[3].Key,ExactKey('1')),'D1:1 відокремлений');
  Check((Values[0].Ukrainian=Tables[10][0].Ukrainian) and
        (Values[1].Ukrainian=Tables[10][1023].Ukrainian),
        'текст — тільки pinned проєкція exact-ключа');
  Positives:=6;Negatives:=0;

  Words:=ExactWords(['10','0000000000','00','0010110','01']);
  Physical:=EncodeT5M(Words);
  BindT5MBinaryD10(Physical,Tables,Values);
  Check((Length(Values)=2) and
        (Values[0].WordIndex=2) and (Values[1].WordIndex=4) and
        (Values[0].RootIndex=0) and (Values[1].RootIndex=0),
        'D2 дужки і сепаратори не є доменними атомами');
  Inc(Positives);

  Doc:=ReadD2T5MWide(Physical);
  try
    BindD2BinaryD10(Doc,Tables,Values);
    Check((Length(Values)=2) and
          SameKey(Values[0].Key,ExactKey('0000000000')),
          'публічний wide AST binder');
    Inc(Positives);
  finally Doc.Free end;

  { Історичний вузький API лишається W1..W9, без прихованого
    розширення; старий фізичний reader має відхилити W10. }
  Physical:=EncodeT5M(ExactWords(['0000000000']));
  Check(Physical<>'','фізичний W10 порожній');
  try
    BindT5MBinary(Physical,Tables,Values);
    Check(False,'W10 непомітно пройшов старий API');
  except on E:ED2SourceError do Inc(Negatives) end;

  MustReject(EncodeT5M(ExactWords(['00000000000'])),'W11 без окремого закону');
  MustReject(EncodeT5M(ExactWords(['000000000000'])),'W12 не дорівнює D12 автоматично');
  MustReject(#243,'пошкоджений T5M байт');
  MustReject(EncodeT5M(ExactWords(['10','0000000000'])),'пізній EOF списку');

  LoadPinnedDomains('external/sens',Tables);
  Tables[10][0].Key.Width:=9;
  MustReject(EncodeT5M(ExactWords(['1'])),'пошкоджена ширина D10');
  LoadPinnedDomains('external/sens',Tables);
  Tables[10][0].Key.Bits:=1;
  MustReject(EncodeT5M(ExactWords(['1'])),'дублікат exact D10');
  LoadPinnedDomains('external/sens',Tables);
  SetLength(Tables[10],0);
  MustReject(EncodeT5M(ExactWords(['1'])),'відсутній pinned D10');
  LoadPinnedDomains('external/sens',Tables);
  BindT5MBinaryD10(EncodeT5M(ExactWords(['000','00','0000000000'])),
    Tables,Values);
  Check((Length(Values)=2) and Values[0].IsEmpty and
        SameKey(Values[0].Key,ExactKey('000')) and
        not SameKey(Values[0].Key,ExactKey('0')) and
        SameKey(Values[1].Key,ExactKey('0000000000')),
        'повне відновлення: D3:000 не D1:0, D10 збережено');
  Inc(Positives);

  WriteLn('D10-ДВІЙКОВИЙ-ДОПУСК-ГАРАЗД позитиви=',Positives,
    ' негативи=',Negatives,' pinned=10-бітів D7=дані D12+=не-виводити');
end.
