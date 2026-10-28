{ G6.8: механічні негативні/позитивні свідки справжнього ELF64.
  Значення літерала перевіряє чинний фізичний SENS evaluator. }
program test_elfd1;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.elfd1;
var
  Physical,Elf:RawByteString;
  Rejected:SizeInt;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then begin
    WriteLn(StdErr,UkrBytes('НАТИВНИЙ-ELF-ТЕСТ-ПОМИЛКА: '),Why);
    Halt(1);
  end;
end;

function WordsOf(const Items:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(Items));
  for J:=0 to High(Items) do Result[J]:=Items[J];
end;

procedure Save(const Path:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free; end;
end;

procedure Reject(const Words:TExactWords;const Why:String);
var Payload:RawByteString;Output:RawByteString;Seen:Boolean;
begin
  Payload:=EncodeT5M(Words);
  Seen:=False;Output:='';
  try Output:=BuildD1ELF(Payload,'external/sens');
  except on E:EELFD1Error do Seen:=True; end;
  Check(Seen and (Output=''),Why);
  Inc(Rejected);
end;

procedure CheckELF(const Bits:RawByteString;const Path:String);
var P:RawByteString;N:SizeInt;
begin
  P:=EncodeT5M(WordsOf([Bits]));
  Save('build/m0.2/elfd1/'+String(Bits)+'.sens',P);
  N:=Length(P);
  Check((N=1) and
    ((Bits='0') and (Ord(P[1])=80) or
     (Bits='1') and (Ord(P[1])=161)),
    'золотий фізичний T5M D1');
  Elf:=BuildD1ELF(P,'external/sens');
  Check(Length(Elf)=155,'неправильна довжина мінімального ELF');
  Check((Copy(Elf,1,4)=#$7F'ELF') and
    (Ord(Elf[5])=2) and (Ord(Elf[6])=1),
    'не ELF64 little-endian');
  Check((Ord(Elf[17])=2) and (Ord(Elf[19])=62) and
    (Ord(Elf[57])=1),'ELF64 не ET_EXEC/x86-64/1 PT_LOAD');
  Check((Ord(Elf[65])=1) and (Ord(Elf[69])=5),
    'ELF PT_LOAD не RX');
  Check((Elf[154]=Bits[1]) and (Elf[155]=#10),
    'згенерований ELF не містить підтверджений D1 і LF');
  Save(Path,Elf);
end;

begin
  ForceDirectories('build/m0.2/elfd1');
  Rejected:=0;
  CheckELF('0','build/m0.2/elfd1/zero.expected.elf');
  CheckELF('1','build/m0.2/elfd1/one.expected.elf');
  Save('build/m0.2/elfd1/many.sens',
    EncodeT5M(WordsOf(['0','1'])));
  Save('build/m0.2/elfd1/quote.sens',
    EncodeT5M(WordsOf(['10','001','0','01'])));

  Reject(WordsOf(['000']),'D3:000 сплутано з D1:0');
  Reject(WordsOf(['10','0','01']),'D2 форма прийнята як D1');
  Reject(WordsOf(['0','1']),'два корені прийнято як один');
  Reject(WordsOf(['111']),'сторонній D3 прийнято як літерал');
  Reject(WordsOf(['01']),'помилкова закривна D2 дужка');
  Reject(WordsOf(['10','0']),'незакритий список D2');
  Reject(WordsOf(['1111111111']),'непідтверджена ширина D10');
  Physical:=#$F3; Elf:=''; Inc(Rejected);
  try Elf:=BuildD1ELF(Physical,'external/sens');
  except on E:EELFD1Error do begin Check(Elf='','зіпсований T5M повернув ELF'); end; end;
  Check(Elf='','байт 243 не відхилено');
  Physical:='';Elf:='';Inc(Rejected);
  try Elf:=BuildD1ELF(Physical,'external/sens');
  except on E:EELFD1Error do begin Check(Elf='','порожній T5M повернув ELF'); end; end;
  Check(Elf='','порожній T5M не відхилено');
  WriteLn(UkrBytes('НАТИВНИЙ-ELF-ДОПУСК-ГАРАЗД D1=0,1 ELF64=155 негативні='),Rejected,
    UkrBytes(' D3=відмова багатоформовість=відмова pinned=так'));
end.
