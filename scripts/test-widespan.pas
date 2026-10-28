{ G1.8 — фізичні D12+ координати без числової семантики. }
program test_widespan;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.widespan;
var Physical, Bad, Report, First:RawByteString;
    Wide,Forge:TWideWords; W:TExactWords; Rejected:Boolean; I:SizeInt;
procedure Demand(Condition:Boolean;const Why:String);
begin
  if not Condition then begin
    WriteLn(StdErr,'ШИРОКІ-СЛОВА-ТЕСТ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;
function Pack(const Items:array of RawByteString):RawByteString;
var Words:TExactWords; J:SizeInt;
begin
  SetLength(Words,Length(Items));
  for J:=0 to High(Items) do Words[J]:=Items[J];
  Result:=EncodeT5M(Words);
end;
procedure CheckSpan(Index,WordNo,Width,StartTrit,EndTrit,StartByte,EndByte:SizeInt;
  const Bits:RawByteString);
begin
  Demand(Wide[Index].Span.WordIndex=WordNo,'номер фізичного слова');
  Demand(Wide[Index].Width=Width,'ширина не та');
  Demand(Wide[Index].Bits=Bits,'втрачені провідні нулі або точні біти');
  Demand((Wide[Index].Span.TritStart=StartTrit) and
         (Wide[Index].Span.TritEnd=EndTrit),'точні трити');
  Demand((Wide[Index].Span.ByteStart=StartByte) and
         (Wide[Index].Span.ByteEnd=EndByte),'точні байти');
end;
procedure MustRejectTSV(const Data:TWideWords;const Why:String);
var TextResult:RawByteString; Caught:Boolean;
begin
  Caught:=False;
  TextResult:='';
  try TextResult:=WideTSV(Data);
  except on E:EWideSpanError do Caught:=True; end;
  Demand(Caught,Why+' не відхилено');
  Demand(TextResult='',
    Why+' повернуло частковий або підроблений TSV');
end;
procedure MustReject(const Data:RawByteString;const Why:String);
begin
  Rejected:=False;
  try CollectWideWords(Data,Wide);
  except on E:Exception do Rejected:=True; end;
  Demand(Rejected,Why+' не відхилено');
  Demand(Length(Wide)=0,Why+' опублікувало часткові вузли');
end;
begin
  Physical:=Pack(['0','000000000001','01','0000000000000',
                  '10101010101','111111111111']);
  CollectWideWords(Physical,Wide);
  Demand(Length(Wide)=3,'не 3 слова D12+');
  CheckSpan(0,2,12,2,14,0,3,'000000000001');
  CheckSpan(1,4,13,18,31,3,7,'0000000000000');
  CheckSpan(2,6,12,44,56,8,12,'111111111111');
  Report:=WideTSV(Wide);
  Demand(Pos('D12'#9'000000000001'#9'[2,14)'#9'[0,3)',Report)>0,
         'TSV не відтворює ширину/біт/трит/байт');
  Demand(Pos('D13'#9'0000000000000',Report)>0,
         'D13 помилково прирівняли до D12');
  Demand(Pos('D11',Report)=0,'D11 помилково визнали числовою шириною');
  First:=WideTSV(Wide);
  Demand(First=Report,'недетерміноване TSV');

  { Два широкі слова фізично ділять один байт, не координату. }
  CollectWideWords(Pack(['000000000000','111111111111']),Wide);
  Demand(Length(Wide)=2,'пара широких слів');
  CheckSpan(0,1,12,0,12,0,3,'000000000000');
  CheckSpan(1,2,12,13,25,2,5,'111111111111');
  { Негативний свідок: приватний експорт WideTSV не повинен
    рекламувати підроблені exact-біти чи порядок фізичних слів. }
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[0].Bits[1]:='2';
  MustRejectTSV(Forge,'трійковий 2 під видом двійкового слова');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[0].Bits[2]:=#9;
  MustRejectTSV(Forge,'вставка TAB у колонку exact-бітів');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.WordIndex:=1;
  MustRejectTSV(Forge,'дубльований фізичний номер слова');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.WordIndex:=0;
  MustRejectTSV(Forge,'нульовий фізичний номер слова');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.TritStart:=10;
  Forge[1].Span.TritEnd:=22;
  Forge[1].Span.ByteStart:=2;
  Forge[1].Span.ByteEnd:=5;
  MustRejectTSV(Forge,'перетин тритів різних фізичних слів');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.TritStart:=12;
  Forge[1].Span.TritEnd:=24;
  Forge[1].Span.ByteStart:=2;
  Forge[1].Span.ByteEnd:=5;
  MustRejectTSV(Forge,'бракує трита-роздільника між словами');
  Demand(Pos('D12',WideTSV(Wide))>0,
    'негативна перевірка пошкодила справжній фізичний TSV');

  CollectWideWords(Pack(['0','1111111111','11111111111','10','01']),Wide);
  Demand(Length(Wide)=0,'D1/D10/D11/D2 помилково стали числами');
  { Поки D12+ у чинному D2 runtime НЕ допускається:
    транспорт зберігає біти, але не встановлює мовний закон. }
  Physical:=Pack(['000000000000']);
  CollectWideWords(Physical,Wide);
  Demand((Length(Wide)=1) and (Wide[0].Width=12),'D12 транспорт');
  Rejected:=False;
  try
    with ReadD2T5M(Physical) do Free;
  except on E:ED2SourceError do Rejected:=True; end;
  Demand(Rejected,'D12 пройшло мовний D2 допуск без ратифікованого шляху');

  MustReject('','порожній T5M');
  MustReject(#$F3,'заборонений фізичний байт 243');
  Bad:=Pack(['000000000000'])+#0;
  MustReject(Bad,'неканонічний заповнювач тритів');

  SetLength(W,4097);
  for I:=0 to High(W) do W[I]:='000000000000';
  MustReject(EncodeT5M(W),'перевищення 4096 широких слів');
  CollectWideWords(Pack(['000000000000']),Wide);
  Demand((Length(Wide)=1) and (Wide[0].Span.WordIndex=1),
         'не вдалося відновити роботу після помилки');

  WriteLn('ШИРОКІ-СЛОВА-ГАРАЗД D12=точне D13=точне спільний-байт=так ',
    'D10-D11=не-числа D2=відмова TSV-захист=6 атомарність=так арифметика=НЕ-ДОВЕДЕНА');
end.
