{ G6.9 — фізичні тести нативного ELF64 з кількох перевірених D1.
  Жодного нового SENS-закону: базовий G6.8 і фактичний G5.9 — оракули. }
program test_elfd1batch;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.elfd1, wsm.elfd1batch;

var Checks, Rejections: SizeInt;

procedure Check(Ok:Boolean;const Why:String);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,'НАТИВНИЙ-D1-ПАКЕТ-ТЕСТ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

function WordsOf(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free; end;
end;

function U32(const Data:RawByteString;Offset:SizeInt):QWord;
var I:SizeInt;
begin
  Result:=0;
  for I:=3 downto 0 do
    Result:=(Result shl 8) or Ord(Data[Offset+I+1]);
end;

function U64(const Data:RawByteString;Offset:SizeInt):QWord;
var I:SizeInt;
begin
  Result:=0;
  for I:=7 downto 0 do
    Result:=(Result shl 8) or Ord(Data[Offset+I+1]);
end;

procedure Confirm(const LabelName:String;const Words:TExactWords;
  ExpectedRoots:SizeInt);
var
  Physical,Elf,Reference:RawByteString;
  N,I:SizeInt;
begin
  N:=Length(Words);
  Physical:=EncodeT5M(Words);
  Save('build/m0.2/elfd1batch/'+LabelName+'.sens',Physical);
  Elf:=BuildD1BatchELF(Physical,'external/sens');
  Check((ExpectedRoots>=2) and (N>=ExpectedRoots),'зламана фікстура');
  Check(Length(Elf)=153+2*ExpectedRoots,'точний розмір машинного ELF');
  Check((Copy(Elf,1,4)=#$7F'ELF') and
        (Ord(Elf[5])=2) and (Ord(Elf[6])=1) and
        (Ord(Elf[17])=2) and (Ord(Elf[19])=62),
        'ELF64/ET_EXEC/x86-64');
  Check((U64(Elf,96)=QWord(Length(Elf))) and
        (U64(Elf,104)=QWord(Length(Elf))) and
        (U32(Elf,138)=QWord(ExpectedRoots*2)),
        'RX програма/довжина машинного виводу');
  Reference:='';
  { Для фікстур без фізичних D2 роздільників Words[I] має бути D1. }
  if N=ExpectedRoots then begin
    for I:=0 to N-1 do begin
      Check((Words[I]='0') or (Words[I]='1'),'фікстура не D1');
      Reference:=Reference+Words[I]+#10;
    end;
    Check(Copy(Elf,154,Length(Reference))=Reference,
      'machine payload не збігся із точними D1');
  end;
  Check((Ord(Elf[65])=1) and (Ord(Elf[69])=5),
    'відсутній PT_LOAD RX');
  Save('build/m0.2/elfd1batch/'+LabelName+'.expected.elf',Elf);
end;

procedure Reject(const Data:RawByteString;const Why:String);
var ResultBytes:RawByteString;Failed:Boolean;
begin
  ResultBytes:='';Failed:=False;
  try ResultBytes:=BuildD1BatchELF(Data,'external/sens');
  except on E:EELFD1BatchError do Failed:=True; end;
  Check(Failed and (ResultBytes=''),Why+' допустили або породили частковий ELF');
  Inc(Rejections);
end;

var
  W:TExactWords;
  I:SizeInt;
  Base:RawByteString;
begin
  Checks:=0;
  Rejections:=0;
  ForceDirectories('build/m0.2/elfd1batch');
  Confirm('два',WordsOf(['0','1']),2);
  Confirm('п’ять',WordsOf(['1','0','1','0','1']),5);
  SetLength(W,256);
  for I:=0 to High(W) do
    if I mod 2=0 then W[I]:='0' else W[I]:='1';
  Confirm('256',W,256);

  Base:=BuildD1ELF(EncodeT5M(WordsOf(['0'])),'external/sens');
  Check((Length(Base)=155) and (Base[154]='0') and (Base[155]=#10),
    'чинний одноформовий G6.8 не збережено');

  Reject('','порожній потік');
  Reject(#$F3,'заборонений байт T5M');
  Reject(EncodeT5M(WordsOf(['0'])),'один корінь належить G6.8');
  Reject(EncodeT5M(WordsOf(['000','1'])),'D3:000 не D1:0');
  Reject(EncodeT5M(WordsOf(['0','000'])),'другий корінь D3');
  Reject(EncodeT5M(WordsOf(['10','0','01','1'])),'D2 список не D1');
  Reject(EncodeT5M(WordsOf(['0','01'])),'пошкоджений D2');
  Reject(EncodeT5M(WordsOf(['0','10','1'])),'незавершений D2');
  Reject(EncodeT5M(WordsOf(['0','111','1'])),'невідомий D3');
  SetLength(W,257);
  for I:=0 to High(W) do W[I]:='1';
  Reject(EncodeT5M(W),'понад 256 коренів');
  WriteLn('НАТИВНИЙ-D1-ПАКЕТ-ГАРАЗД перевірок=',Checks,
    ' негативні=',Rejections,' ELF64=справжній ',
    'корені=2,5,256 D3=відмова pinned=чинний ',
    'SENS_повний_компілятор=ні');
end.
