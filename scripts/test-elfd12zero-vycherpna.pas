{ G6.101 — повний фізичний корпус всіх 4096 signed D12.
  Host fixtures .bin: конкатенація ОКРЕМИХ канонічних W12 атомів,
  НЕ один файл .sens чи новий семантичний транспорт SENS.
  Відповіді — окремі W1 T5M, ніколи host-boolean. }
program test_elfd12zero_vycherpna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane, wsm.elfd12zeropotik;
const FirstD12=-2048; LastD12=2047;
var
  Dir:String;
  Atoms,Answers:TFileStream;
  Number,Counter:LongInt;
  Physical,Expected,ELF,YesWord,NoWord:RawByteString;
  Bits:TExactWords;

procedure Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create(Why);
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Data<>'' then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

begin
  Need(ParamCount=1,'потрібна приватна тека для host fixture');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'немає теки результатів');
  ELF:=BuildD12ZeroStreamELF;
  Need(Length(ELF)>120,'відсутній виконуваний ELF64');
  Save(Dir+'/stream.elf',ELF);
  Save(Dir+'/stream-repeated.elf',BuildD12ZeroStreamELF);
  SetLength(Bits,1);
  Bits[0]:='1';YesWord:=EncodeT5M(Bits);
  Bits[0]:='0';NoWord:=EncodeT5M(Bits);
  Need((Length(YesWord)=1) and (Length(NoWord)=1) and
       (YesWord<>NoWord),'невірні фізичні D1 відповіді');
  Atoms:=TFileStream.Create(Dir+'/atoms.bin',fmCreate);
  try
    Answers:=TFileStream.Create(Dir+'/answers.bin',fmCreate);
    try
      Counter:=0;
      for Number:=FirstD12 to LastD12 do begin
        Physical:=EncodeNumericDecimal(IntToStr(Number),12);
        Need(Length(Physical)=3,'втрата точного W12 T5M атома');
        Atoms.WriteBuffer(Physical[1],3);
        if Number=0 then Expected:=YesWord else Expected:=NoWord;
        Answers.WriteBuffer(Expected[1],1);
        Inc(Counter);
      end;
      Need((Counter=4096) and (Atoms.Size=12288) and
           (Answers.Size=4096),'неповна фізична матриця D12');
    finally Answers.Free end;
  finally Atoms.Free end;
  { Маркер host CI — ASCII, щоб не залежати від локалі FPC;
    українські пояснення лишаються в джерелі. }
  WriteLn('D12-EXHAUSTIVE-OK cases=4096 elf=1');
end.

{ Типи й життєвий цикл: Physical/Expected/ELF — керовані
  RawByteString, D12 Word має рівно три packed T5M байти, D1 — один;
  TFileStream володіє файлом і звільняється у finally.
  Питання: (1) Чому atoms.bin не є однією програмою .sens?
  (2) Чому 4096 — повний набір signed D12?
  (3) Чому для D1:0 і D1:1 потрібні різні байти?
  (4) Хто звільняє потоки при невдалому кодуванні?
  (5) Чому очікуване значення треба ще звірити з pinned REPL? }
