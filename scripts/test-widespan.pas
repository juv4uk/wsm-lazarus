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

  { G1.29: дійсна фізична відстань між #1 та #3 із
    пропущеним W1: 1 трит роздільника + W1 + 1 роздільник.
    Колекція отримана з РЕАЛЬНОГО packed T5M, не підроблена. }
  CollectWideWords(Pack(['000000000000','0','111111111111']),Wide);
  Demand(Length(Wide)=2,'пропущене коротке D1 не стало широким');
  CheckSpan(0,1,12,0,12,0,3,'000000000000');
  CheckSpan(1,3,12,15,27,3,6,'111111111111');
  Demand(Pos('3'#9'D12'#9'111111111111'#9'[15,27)'#9'[3,6)',
    WideTSV(Wide))>0,'правильний розрив через D1 відхилено');

  { Дані pinned D7 W7:0010110 (SYN) не дають ні викличності,
    ні числа. Їхні СІМ фізичних бітів однак мають займати місце. }
  CollectWideWords(Pack(['000000000000','0010110','111111111111']),Wide);
  Demand(Length(Wide)=2,'D7 дані підмінено шириною D12');
  CheckSpan(1,3,12,21,33,4,7,'111111111111');
  Demand(Pos('3'#9'D12'#9'111111111111'#9'[21,33)'#9'[4,7)',
    WideTSV(Wide))>0,'фізичний D7-проміжок відхилено');

  { Підроблена геометрія: #1 НЕ може починатися після трита 0,
    #3 НЕ може починатися з 0 або мати тільки два трити проміжку
    після кінця #1 (для проміжного W1 потрібно рівно >=3). }
  CollectWideWords(Pack(['000000000000','111111111111']),Wide);
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[0].Span.TritStart:=1;
  Forge[0].Span.TritEnd:=13;
  MustRejectTSV(Forge,'перше слово #1 не починається з трита 0');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[0].Span.WordIndex:=3;
  MustRejectTSV(Forge,'слово #3 підроблено у триті 0');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.WordIndex:=3;
  Forge[1].Span.TritStart:=14;
  Forge[1].Span.TritEnd:=26;
  Forge[1].Span.ByteStart:=2;
  Forge[1].Span.ByteEnd:=6;
  MustRejectTSV(Forge,'фізично неможливі два трити між #1 і #3');
  { Правильний sparse 1 -> 3 свідок не втратив жодних бітів. }
  CollectWideWords(Pack(['000000000000','0','111111111111']),Wide);
  Demand(Pos('3'#9'D12'#9'111111111111'#9'[15,27)',
    WideTSV(Wide))>0,'не відновлено фізичний експорт після помилки');
  WriteLn('ШИРОКІ-ПРОМІЖКИ-ГАРАЗД: перший=0 ',
    'пропущені=D1,D7 три-роздільники=точні ',
    'підроблені-адреси=3-відхилено відновлення=так');



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

  { G1.35: останнє широке слово може бути №4096 у реальному
    packed T5M, але не №4097 навіть через публічний TSV API.
    Усі числа — лічильники FPC, НЕ числові координати SENS. }
  { Точні фізичні ПРОМІЖКИ мають не тільки нижню, а й верхню
    межу: невидимі записи у TWideWords — лише W1..W11. }
  CollectWideWords(Pack(['00000000000','111111111111']),Wide);
  Demand((Length(Wide)=1) and
    (Wide[0].Span.WordIndex=2) and
    (Wide[0].Span.TritStart=12) and
    (Wide[0].Span.TritEnd=24),
    'справжній перший широкий W12 після W11 не прийнято');
  Demand(Pos('2'#9'D12',WideTSV(Wide))>0,
    'перший широкий W12 після найбільшого W11 загублено');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[0].Span.TritStart:=13;
  Forge[0].Span.TritEnd:=25;
  Forge[0].Span.ByteStart:=2;
  Forge[0].Span.ByteEnd:=5;
  MustRejectTSV(Forge,'неіснуючий 12-й біт перед першим W12');

  CollectWideWords(Pack(['000000000000','111111111111']),Wide);
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.TritStart:=14; { між сусідніми #1 і #2 тільки 1 трит }
  Forge[1].Span.TritEnd:=26;
  Forge[1].Span.ByteStart:=2;
  Forge[1].Span.ByteEnd:=6;
  MustRejectTSV(Forge,'зайвий трит між сусідніми фізичними W12');

  CollectWideWords(Pack(['000000000000','00000000000',
    '111111111111']),Wide);
  Demand(Length(Wide)=2,
    'правильний пропущений W11 не сховано зі звіту W12+');
  Demand(Pos('3'#9'D12'#9'111111111111'#9'[25,37)',WideTSV(Wide))>0,
    'фізичний граничний проміжок через W11 відхилено');
  Forge:=Copy(Wide,0,Length(Wide));
  Forge[1].Span.TritStart:=26; { #1 -> #3: максимум Gap=13 }
  Forge[1].Span.TritEnd:=38;
  Forge[1].Span.ByteStart:=5;
  Forge[1].Span.ByteEnd:=8;
  MustRejectTSV(Forge,'неможливий W12 замість прихованого W11');

  CollectWideWords(Pack(['000000000000','111111111111']),Wide);
  Forge:=Copy(Wide,0,Length(Wide));
  { Довжина локально W12, але end за абсолютною 4 МіБ T5M межею.
    Уникаємо 20 МіБ виділення — достатньо підробленого host span. }
  Forge[1].Span.TritStart:=MAX_T5M_FILE_BYTES*5-10;
  Forge[1].Span.TritEnd:=Forge[1].Span.TritStart+12;
  Forge[1].Span.ByteStart:=Forge[1].Span.TritStart div 5;
  Forge[1].Span.ByteEnd:=(Forge[1].Span.TritEnd-1) div 5+1;
  MustRejectTSV(Forge,'фізична адреса W12 за максимальною межею T5M');
  WriteLn('ШИРОКІ-МЕЖІ-TSV-ГАРАЗД',
    ' W11-розрив=точно-12 W12-сусіди=один-роздільник',
    ' forged-4097=відхилено за-4-МіБ=відхилено');

  SetLength(W,MaxWideWords);
  for I:=0 to High(W) do W[I]:='000000000000';
  CollectWideWords(EncodeT5M(W),Wide);
  Demand(Length(Wide)=MaxWideWords,
    'реальні 4096 фізичних W12 відхилені до публікації');
  Report:=WideTSV(Wide);
  Demand(Pos('4096'#9'D12'#9'000000000000',Report)>0,
    'останнє реальне фізичне слово W12 втрачено в TSV');
  Forge:=Copy(Wide,0,Length(Wide));
  SetLength(Forge,MaxWideWords+1);
  MustRejectTSV(Forge,'сторонні 4097 підроблених записів TSV');
  SetLength(W,MaxWideWords+1);
  for I:=0 to High(W) do W[I]:='000000000000';
  MustReject(EncodeT5M(W),'перевищення 4096 широких слів');
  CollectWideWords(Pack(['000000000000']),Wide);
  Demand((Length(Wide)=1) and (Wide[0].Span.WordIndex=1),
         'не вдалося відновити роботу після помилки');

  WriteLn('ШИРОКІ-СЛОВА-ГАРАЗД D12=точне D13=точне спільний-байт=так ',
    'D10-D11=не-числа D2=відмова TSV-захист=6 атомарність=так арифметика=НЕ-ДОВЕДЕНА');
end.
