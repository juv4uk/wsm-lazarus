{ G6.126 — 26 різних повних T5M D3 умов для 1..3 гілок.
  Апаратний eligibility = test AND NOT(обрано_раніше), отже перша
  істинна гілка перемагає. Складні чисті D3:101 усередині кожного
  test/expression перевіряють найгірший ліміт 256 машинних байтів.
  Генератори працюють лише з TExactWords, які належать викликачу;
  утворені фізичні байти й ELF живуть до Save, а потім звільняються.
  1) Чому 2-га істинна гілка не повинна переписувати першу?
  2) Чому 3 вкладені EQ важливі для перевірки ліміту?
  3) Чому 4 гілки відхиляються, хоча pinned IR їх допускає?
  4) Що підтверджує незалежний oracle, а не host очікування? }
{ G6.116 — реальні повні фізичні D3:110 програми до CMOVcc PIE.
  Фізичні T5M байти генерує існуючий wsm.t5m; тільки pinned
  LowerPinnedIRCond допускає D1 та вкладений D3:101.
  FPC перевіряє ELF64 структуру, два CMOV opcode, атомарні негативи;
  bash запускає ВСІ ELF і незалежний pinned SENS oracle.

  Вхід: один приватний каталог; вихід: 10 packed .sens, 10 PIE,
  10 точних T5M-еталонів та 10 очікуваних oracle текстів.
  Усі RawByteString/динамічні масиви — owned FPC, звільняються
  у межах виклику; довічних таблиць або реєстру законів немає.
  Питання: 1) Чому D3:000 — не D1:0?
  2) Як відмова зберігає порожній ELF?
  3) Чи є source lisp канонічним оракулом?
  4) Які саме D3:101 форми допускає чинний lowered IR? }
program test_ircondcmov;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.ircondcmov,wsm.elfgeometry;
var PositiveCount,NegativeCount:SizeInt; Directory:String;
function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;
procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise Exception.Create('D3-CMOV-ТЕСТ-ПРОВАЛ: '+Why);
end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;
procedure Positive(const Name,ExpectedWord:RawByteString;
                   const SourceWords:array of RawByteString);
var Physical,Image,Expected,Oracle:RawByteString;
    Geometry:TELFGeometry;
begin
  Physical:=EncodeT5M(W(SourceWords));
  Image:=BuildPinnedIRCondCMovELF(Physical,'external/sens');
  Need((Length(Image)>120) and
       (Image=BuildPinnedIRCondCMovELF(Physical,'external/sens')),
       String(Name)+': недетермінований або порожній PIE');
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Image)) and
       (Geometry.MachineBytes<=256) and (Geometry.MachineBytes>30),
       String(Name)+': некоректна фізична геометрія PIE');
  Need(Pos(#$0F#$45#$CA,Image)>0,
       String(Name)+': бракує реального CMOVNE ECX,EDX');
  Need(Pos(#$0F#$44#$D9,Image)>0,
       String(Name)+': бракує реального CMOVE EBX,ECX');
  Expected:=EncodeT5M(W([ExpectedWord]));
  Need(Length(Expected)=1, String(Name)+': вихід не один T5M байт');
  if ExpectedWord='000' then Oracle:='()'+#10
  else Oracle:=ExpectedWord+#10;
  Save(Directory+'/'+String(Name)+'.sens',Physical);
  Save(Directory+'/'+String(Name)+'.elf',Image);
  Save(Directory+'/'+String(Name)+'.expected.sens',Expected);
  Save(Directory+'/'+String(Name)+'.oracle.txt',Oracle);
  Inc(PositiveCount);
end;
{ Групи фізичних D2:110 тестів: жодної людиночитаної назви
  у семантичній позиції. FirstTrue=-1 означає вичерпання;
  LaterAllTrue перевіряє пріоритет першої гілки, навіть коли наступні
  тести теж D1:1. Pinned LowerPinnedIRCond повторно перевірить кожну
  координату, ключ та точну форму перед генерацією ELF.
  TExactWords — локальний керований масив, результат owned.
  1) Чому клони з різними тестами мають різний packed T5M?
  2) Як виключена підміна D3:000 на D1:0?
  3) Як індекс I відповідає порядкові D2-гілки? }
function SeriesWords(Clauses,FirstTrue:SizeInt;
                     LaterAllTrue:Boolean):TExactWords;
var I,P:SizeInt;
begin
  Need((Clauses>=1) and (Clauses<=4) and
       (FirstTrue>=-1) and (FirstTrue<Clauses),
       'неприпустимі параметри фізичної серії');
  SetLength(Result,3+4*Clauses);
  Result[0]:='10';
  Result[1]:='110';
  for I:=0 to Clauses-1 do begin
    P:=2+I*4;
    Result[P]:='10';
    if (FirstTrue>=0) and
       ((I=FirstTrue) or (LaterAllTrue and (I>FirstTrue))) then
      Result[P+1]:='1'
    else Result[P+1]:='0';
    if (I mod 2)=0 then Result[P+2]:='0'
    else Result[P+2]:='1';
    Result[P+3]:='01';
  end;
  Result[High(Result)]:='01';
end;
procedure PositiveSeries(const Name:RawByteString;
                         Clauses,FirstTrue:SizeInt;
                         LaterAllTrue:Boolean);
var Expected:RawByteString;
begin
  if FirstTrue<0 then Expected:='000'
  else if (FirstTrue mod 2)=0 then Expected:='0'
  else Expected:='1';
  Positive(Name,Expected,SeriesWords(Clauses,FirstTrue,LaterAllTrue));
end;

{ Кожен test/expr є справжнім exact D3:101(D1,D1); навіть коли
  усі три гілки вкладені, реально виконується 6 CMP/SETE на CPU.
  Це підтверджує не тільки вихід, а й 256-byte code budget. }
function NestedSeriesWords(Clauses,FirstTrue:SizeInt):TExactWords;
var I,P:SizeInt;
begin
  Need((Clauses>=1) and (Clauses<=3) and
       (FirstTrue>=-1) and (FirstTrue<Clauses),
       'неприпустимий вкладений D3 сценарій');
  SetLength(Result,3+12*Clauses);
  Result[0]:='10';
  Result[1]:='110';
  for I:=0 to Clauses-1 do begin
    P:=2+12*I;
    Result[P]:='10';
    Result[P+1]:='10';
    Result[P+2]:='101';
    if I=FirstTrue then Result[P+3]:='1'
    else Result[P+3]:='0';
    Result[P+4]:='1';
    Result[P+5]:='01';
    Result[P+6]:='10';
    Result[P+7]:='101';
    if (I mod 2)=0 then Result[P+8]:='0'
    else Result[P+8]:='1';
    Result[P+9]:='1';
    Result[P+10]:='01';
    Result[P+11]:='01';
  end;
  Result[High(Result)]:='01';
end;
procedure PositiveNested(const Name:RawByteString;
                         Clauses,FirstTrue:SizeInt);
var Expected:RawByteString;
begin
  if FirstTrue<0 then Expected:='000'
  else if (FirstTrue mod 2)=0 then Expected:='0'
  else Expected:='1';
  Positive(Name,Expected,NestedSeriesWords(Clauses,FirstTrue));
end;
procedure NegativeRaw(const Why:RawByteString;
                      const Physical:RawByteString);
var Image:RawByteString;Failed:Boolean;
begin
  Image:=''; Failed:=False;
  try Image:=BuildPinnedIRCondCMovELF(Physical,'external/sens')
  except on E:EIRCondCMovError do Failed:=True end;
  Need(Failed and (Image=''),
       String(Why)+': не відхилено без публікації ELF');
  Inc(NegativeCount);
end;
procedure Negative(const Why:RawByteString;
                   const SourceWords:array of RawByteString);
begin
  NegativeRaw(Why,EncodeT5M(W(SourceWords)));
end;
begin
  Need((ParamCount=1) and DirectoryExists(ParamStr(1)),
       'потрібна існуюча приватна тека');
  Directory:=ParamStr(1);
  PositiveCount:=0; NegativeCount:=0;
  Positive('01-хибна-нуль','000',
    ['10','110','10','0','0','01','01']);
  Positive('02-хибна-одиниця','000',
    ['10','110','10','0','1','01','01']);
  Positive('03-істинна-нуль','0',
    ['10','110','10','1','0','01','01']);
  Positive('04-істинна-одиниця','1',
    ['10','110','10','1','1','01','01']);
  Positive('05-рівність-так','0',
    ['10','110','10','10','101','1','1','01','0','01','01']);
  Positive('06-рівність-ні','000',
    ['10','110','10','10','101','0','1','01','1','01','01']);
  Positive('07-вираз-рівність-так','1',
    ['10','110','10','1','10','101','0','0','01','01','01']);
  Positive('08-вираз-рівність-ні','0',
    ['10','110','10','1','10','101','0','1','01','01','01']);
  Positive('09-обидві-рівності-так','0',
    ['10','110','10','10','101','1','1','01',
     '10','101','1','0','01','01','01']);
  Positive('10-обидві-рівності-ні','000',
    ['10','110','10','10','101','0','1','01',
     '10','101','1','1','01','01','01']);
  PositiveSeries('11-дві-вичерпано',2,-1,False);
  PositiveSeries('12-дві-перша',2,0,False);
  PositiveSeries('13-дві-друга',2,1,False);
  PositiveSeries('14-дві-обидві-істинні',2,0,True);
  PositiveSeries('15-три-вичерпано',3,-1,False);
  PositiveSeries('16-три-перша',3,0,False);
  PositiveSeries('17-три-друга',3,1,False);
  PositiveSeries('18-три-третя',3,2,False);
  PositiveSeries('19-три-друга-і-третя',3,1,True);
  PositiveNested('20-вкладені-дві-вичерпано',2,-1);
  PositiveNested('21-вкладені-дві-перша',2,0);
  PositiveNested('22-вкладені-дві-друга',2,1);
  PositiveNested('23-вкладені-три-вичерпано',3,-1);
  PositiveNested('24-вкладені-три-перша',3,0);
  PositiveNested('25-вкладені-три-друга',3,1);
  PositiveNested('26-вкладені-три-третя',3,2);
  Negative('немає-гілки',['10','110','01']);
  Negative('чотири-гілки',SeriesWords(4,0,True));
  Negative('третя-гілка-D7-вираз',
    ['10','110','10','0','0','01','10','0','1','01',
     '10','1','0010110','01','01']);
  Negative('третя-гілка-D12-тест',
    ['10','110','10','0','0','01','10','0','1','01',
     '10','000000000000','0','01','01']);
  Negative('третя-гілка-третє-поле',
    ['10','110','10','0','0','01','10','0','1','01',
     '10','1','0','1','01','01']);
  Negative('інша-голова',
    ['10','101','10','1','0','01','01']);
  Negative('D3-000-тест',
    ['10','110','10','000','1','01','01']);
  Negative('D7-тест',
    ['10','110','10','0010110','1','01','01']);
  Negative('D12-тест',
    ['10','110','10','000000000000','1','01','01']);
  Negative('D12-вираз',
    ['10','110','10','1','000000000000','01','01']);
  Negative('D3-000-вираз',
    ['10','110','10','1','000','01','01']);
  NegativeRaw('зіпсований-T5M',#$F3);
  NegativeRaw('порожній-T5M','');
  Negative('непарний-D2',
    ['10','110','10','1','1','01']);
  Negative('другий-корінь',
    ['10','110','10','1','0','01','01','1']);
  Negative('вкладений-D7',
    ['10','110','10','10','101','0','0010110','01','1','01','01']);
  Need((PositiveCount=26) and (NegativeCount=16),
       'неправильні підсумки позитивів/негативів');
  { Після пізніх відмов перевірити повторний незалежний допуск. }
  Need(Length(BuildPinnedIRCondCMovELF(
       EncodeT5M(W(['10','110','10','1','1','01','01'])),
       'external/sens'))>120,'не відновився після відмов');
  WriteLn('D3-CMOV-OK positives=',PositiveCount,
          ' negatives=',NegativeCount,
          ' PIE=26 T5M=26 first-true=1 recovery=1 energy=NOT-MEASURED');
end.
