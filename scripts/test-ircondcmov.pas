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
  Negative('немає-гілки',['10','110','01']);
  Negative('дві-гілки',
    ['10','110','10','1','0','01','10','1','1','01','01']);
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
  Need((PositiveCount=10) and (NegativeCount=13),
       'неправильні підсумки позитивів/негативів');
  { Після пізніх відмов перевірити повторний незалежний допуск. }
  Need(Length(BuildPinnedIRCondCMovELF(
       EncodeT5M(W(['10','110','10','1','1','01','01'])),
       'external/sens'))>120,'не відновився після відмов');
  WriteLn('D3-CMOV-OK positives=',PositiveCount,
          ' negatives=',NegativeCount,
          ' PIE=10 T5M=10 recovery=1 energy=NOT-MEASURED');
end.
