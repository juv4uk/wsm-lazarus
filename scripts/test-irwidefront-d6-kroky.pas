{ G6.146 — два вже ратифіковані D6 профілі в одному спільному AOT.
  Вхідні packed T5M fixtures та донорний машинний ELF породжує чинний
  scripts/test-irmixedstep.pas; цей тест НЕ визначає SENS арифметику.
  Жодного дублювання Core1/Core4 або D7 текстового dispatch. }
program test_irwidefront_d6_kroky;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwidefront,wsm.elfgeometry;
var Folder:String;PositiveCount,NegativeCount,Depth,Pattern:SizeInt;
    Geometry:TELFGeometry;

procedure Need(Allowed:Boolean;const Why:String);
begin
  if not Allowed then raise Exception.Create('Д6-СПІЛЬНИЙ-ПРОВАЛ: '+Why);
end;

{ Path позичений, фізичний буфер owned RawByteString. Обмеження
  host-файлу не змінює ні width, ні закон SENS.
  Питання: хто закриває Stream? Чому 0 байтів теж дозволяємо для
  негативного свідка? Чи можна вгадувати D12 із довжини файла? }
function ReadBytes(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>=0) and (Stream.Size<=1048576),
      'неприпустимий розмір фізичного свідка');
    SetLength(Result,SizeInt(Stream.Size));
    if Length(Result)>0 then Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

procedure SaveBytes(const Path:String;const Physical:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Physical)>0 then
      Stream.WriteBuffer(Physical[1],Length(Physical));
  finally Stream.Free end;
end;

{ Words — explicit фізичні бітові слова, у тому числі D2:10/01.
  Packed T5M належить Result і звільняється managed FPC.
  Питання: чому D2 не ASCII? Чому W6 не є шістьма літерами?
  Чи створює це новий numeric law? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

function Bits12(Value:Integer):RawByteString;
var Number:TExplicitNumeric;
begin
  Number:=ReadNumericPhysical(
    EncodeNumericDecimal(IntToStr(Value),12),12);
  Result:=Number.ExactBits;
end;

procedure Refuse(const LabelText:String;const Physical:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;Candidate:='';
  try
    Candidate:=BuildVerifiedWideELF(Physical,'external/sens');
  except on E:Exception do Rejected:=True end;
  Need(Rejected and (Candidate=''),'прийнятий негатив '+LabelText);
  Inc(NegativeCount);
end;

{ Кожний позитив — повна canonical .sens D2 форма, 1..5 nested D6.
  Новий frontend має породити byte-identical host ELF як уже
  незалежно перевірений mixed-step backend; machine stdout перевіряє shell.
  Питання: чому порівнюємо увесь ELF, а не тільки його довжину?
  Де перевірено pinned W6 перед викликом?
  Чому це ще не доводить довільну Core4 програму?
  Хто перевіряє виконуваний код на процесорі? }
procedure CheckPositive(const Name:String);
var Source,Donor,Actual,Expected:RawByteString;
begin
  Source:=ReadBytes(Folder+Name+'.sens');
  Donor:=ReadBytes(Folder+Name+'.elf');
  Expected:=ReadBytes(Folder+Name+'.expected.sens');
  Actual:=BuildVerifiedWideELF(Source,'external/sens');
  Need((Length(Actual)>120) and (Actual=Donor),
    'не збіглися машинні байти frontend/donor '+Name);
  VerifySENSELF64(Actual,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Actual)),
    'некоректна ELF64 PIE геометрія '+Name);
  Need(Length(Expected)=3,'очікується лише точний D12 T5M');
  SaveBytes(Folder+Name+'.frontend.elf',Actual);
  Inc(PositiveCount);
end;

procedure CheckNegative;
var W:TExactWords;I:SizeInt;Wide24,B0,B1,B2047:RawByteString;
begin
  B0:=Bits12(0);B1:=Bits12(1);B2047:=Bits12(2047);
  Wide24:=StringOfChar('0',23)+'1';
  Refuse('підміна D6 голови',Pack(['10','001100',B1,'01']));
  Refuse('D5 замість D6',Pack(['10','00111',B1,'01']));
  Refuse('D7 замість D6',Pack(['10','0010110',B1,'01']));
  Refuse('D24 замість D12',Pack(['10','001110',Wide24,'01']));
  Refuse('бракує D12',Pack(['10','001110','01']));
  Refuse('зайвий D12',Pack(['10','001110',B1,B1,'01']));
  Refuse('два корені',Pack(['10','001110',B1,'01','0']));
  Refuse('крапкова структура',Pack(['10','001110','11',B1,'01']));
  Refuse('D6 відняти-1 від нуля',Pack(['10','001111',B0,'01']));
  Refuse('D6 відняти-1 від відємного',
         Pack(['10','001111',Bits12(-1),'01']));
  Refuse('D12 підвищення до D24',
         Pack(['10','001110',B2047,'01']));
  Refuse('відсутній фізичний потік','');
  Refuse('пошкоджений T5M',#$FF);
  Refuse('корінь-атом',Pack(['001110']));
  SetLength(W,19);
  for I:=0 to 5 do begin W[2*I]:='10';W[2*I+1]:='001110' end;
  W[12]:=B1;
  for I:=0 to 5 do W[13+I]:='01';
  Refuse('шість вкладених кроків',EncodeT5M(W));
end;

begin
  try
    Need(ParamCount=1,'потрібна приватна тека свідків');
    Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
    Need(DirectoryExists(Folder),'відсутня тека фізичних свідків');
    PositiveCount:=0;NegativeCount:=0;
    for Depth:=1 to 5 do
      for Pattern:=0 to 3 do
        CheckPositive(IntToStr(Depth)+'-'+IntToStr(Pattern));
    CheckNegative;
    Need((PositiveCount=20) and (NegativeCount=15),
      'неповна матриця позитивів/негативів');
    WriteLn('Д6-СПІЛЬНИЙ-UNIT-ГАРАЗД physical=20 byte-identical=20 negative=15');
  except on E:Exception do begin
    WriteLn(StdErr,'Д6-СПІЛЬНИЙ-ПРОВАЛ: ',E.Message);
    Halt(1);
  end end;
end.
