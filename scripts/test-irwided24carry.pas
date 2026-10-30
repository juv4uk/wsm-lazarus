{ G6.257 — перевірити ПОВНУ фізичну SENS-форму D5:01010(D24,D24).
  Джерело — owned canonical packed T5M за чинним EncodeT5M, а не
  англійський/український текстовий dispatch. Тест передає форму через
  pinned TVerifiedWideContext до справжнього machine ELF64 (ADD/ADC).
  Очікувані байти рахуються окремим раніше перевіреним NumericAdd.
  Ця локальна перевірка не замінює незалежний SENS REPL oracle.
  Ресурси: файли закриті у finally; managed RawByteString звільняє FPC.
  Питання: 1) Чому D5 head ключ рівно W5?
  2) Чому D24 width мусить бути точно 24 на обох листках?
  3) Чому трити D2 зберігаємо у фізичному байтовому файлі?
  4) Чим матриця негативів відрізняється від пари вдалих запусків?
  5) Чому це не доводить загальне виконання Core1? }
program test_irwided24carry;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
     wsm.irwided24carry,wsm.elfgeometry;
type TExample=record
  LabelText,LeftText,RightText,AnswerText:String;
end;
const Cases:array[0..9] of TExample=(
  (LabelText:'01';LeftText:'65535';RightText:'1';AnswerText:'65536'),
  (LabelText:'02';LeftText:'131071';RightText:'1';AnswerText:'131072'),
  (LabelText:'03';LeftText:'-65536';RightText:'-1';AnswerText:'-65537'),
  (LabelText:'04';LeftText:'-1';RightText:'1';AnswerText:'0'),
  (LabelText:'05';LeftText:'-123456';RightText:'234567';AnswerText:'111111'),
  (LabelText:'06';LeftText:'8388606';RightText:'1';AnswerText:'8388607'),
  (LabelText:'07';LeftText:'-8388608';RightText:'1';AnswerText:'-8388607'),
  (LabelText:'08';LeftText:'-65535';RightText:'-2';AnswerText:'-65537'),
  (LabelText:'09';LeftText:'65535';RightText:'65535';AnswerText:'131070'),
  (LabelText:'10';LeftText:'0';RightText:'0';AnswerText:'0')
);
var Root,Folder:String;
    Manifest:TStringList;
    LeftNum,RightNum,SmallNum:TExplicitNumeric;
    Physical,Expected,Executable,Before,Original:RawByteString;
    G:TELFGeometry;
    I,Positives,Negatives:Integer;
    Rejected:Boolean;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('IR-D24-CARRY-ПОМИЛКА: '+Why) end;

function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for J:=0 to High(Tokens) do W[J]:=Tokens[J];
  Result:=EncodeT5M(W);
end;

procedure Save(const Filename:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Filename,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

function PhysicalAdd(const L,R:RawByteString):RawByteString;
begin
  Result:=Pack(['10','01010',L,R,'01']);
end;

procedure Positive(const E:TExample);
var LeftAtom,RightAtom:RawByteString;
begin
  LeftAtom:=EncodeNumericDecimal(E.LeftText,24);
  RightAtom:=EncodeNumericDecimal(E.RightText,24);
  LeftNum:=ReadNumericPhysical(LeftAtom,24);
  RightNum:=ReadNumericPhysical(RightAtom,24);
  Physical:=PhysicalAdd(LeftNum.ExactBits,RightNum.ExactBits);
  Expected:=AddNumericPhysical(LeftAtom,RightAtom,24);
  Need(Expected=EncodeNumericDecimal(E.AnswerText,24),
       'очікування різниться з pinned numeric addition');
  Executable:=BuildIRWideD24CarryELF(Physical,Root);
  VerifySENSELF64(Executable,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Executable)) and (G.MachineBytes>0),
       'source-backed ELF64 не пройшов перевірку геометрії');
  Save(E.LabelText+'.program.sens',Physical);
  Save(E.LabelText+'.expected.sens',Expected);
  Save(E.LabelText+'.elf',Executable);
  Manifest.Add(E.LabelText+#9+E.LeftText+#9+E.RightText+#9+E.AnswerText);
  Inc(Positives);
end;

procedure Reject(const Bad:RawByteString;const Why:String);
begin
  Before:=Executable;
  Rejected:=False;
  try
    Executable:=BuildIRWideD24CarryELF(Bad,Root);
  except
    on E:Exception do begin
      Need(E.Message<>'','відмова без діагностики: '+Why);
      Rejected:=True;
    end;
  end;
  Need(Rejected,'прийнято невалідну форму: '+Why);
  Need(Executable=Before,'змінено попередній ELF при відмові: '+Why);
  Inc(Negatives);
end;

begin
  Need(ParamCount=2,'потрібні pinned authority root і приватний каталог');
  Root:=ParamStr(1);
  Folder:=ParamStr(2);
  Need(DirectoryExists(Root),'немає pinned кореня');
  Need(DirectoryExists(Folder),'немає приватного каталогу');
  Manifest:=TStringList.Create;
  try
    Positives:=0;Negatives:=0;
    for I:=Low(Cases) to High(Cases) do Positive(Cases[I]);
    Need(Positives=10,'потрібно 10 повних фізичних виконуваних програм');
    Original:=Executable;
    LeftNum:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    RightNum:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24);
    Reject(Pack(['10','01011',LeftNum.ExactBits,RightNum.ExactBits,'01']),
           'D5 SUB замість ADD');
    Reject(Pack(['10','11010',LeftNum.ExactBits,RightNum.ExactBits,'01']),
           'D5 LESS замість ADD');
    Reject(Pack(['10','01010',LeftNum.ExactBits,'01']),
           'неповна арність');
    Reject(Pack(['10','01010',LeftNum.ExactBits,RightNum.ExactBits,
                 RightNum.ExactBits,'01']),'третій аргумент');
    SmallNum:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12);
    Reject(Pack(['10','01010',SmallNum.ExactBits,
                 RightNum.ExactBits,'01']),'D12 зліва');
    Reject(Pack(['10','01010',LeftNum.ExactBits,
                 SmallNum.ExactBits,'01']),'D12 справа');
    Reject(Pack(['10','01010','1',RightNum.ExactBits,'01']),
           'D1 замість D24');
    Reject(Pack(['10','01010',LeftNum.ExactBits,RightNum.ExactBits,
                 '01','1']),'другий root');
    Reject(Pack(['10','01010',LeftNum.ExactBits,RightNum.ExactBits]),
           'незакрита D2 форма');
    Reject(#$FF,'неправильний T5M');
    Reject('','порожній фізичний source');
    LeftNum:=ReadNumericPhysical(EncodeNumericDecimal('8388607',24),24);
    Reject(PhysicalAdd(LeftNum.ExactBits,RightNum.ExactBits),
           'overflow D24 -> D48');
    Need(Negatives=12,'потрібно 12 відхилень');
    Positive(Cases[0]);
    Need((Positives=11) and (Executable<>Original),
         'recovery не побудував відмінну програму');
    { Десять унікальних test cases: повтор першого перезаписує той
      самий файл тими самими детермінованими байтами. }
    Manifest.Delete(Manifest.Count-1);
    Need(Manifest.Count=10,'маніфест не дорівнює десяти кейсам');
    Manifest.SaveToFile(Folder+'/cases.tsv');
    WriteLn('IR-D24-CARRY-OK positives=10 negative=12 recovery=1 ',
      'source=T5M-D5-W24 IR=PINNED-WIDE ELF64=10 energy=NOT-MEASURED');
  finally
    Manifest.Free;
  end;
end.
