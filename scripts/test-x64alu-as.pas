{ G6.96. Незалежне байтове звіряння host-ALU з GNU assembler.
  Цей тест НЕ визначає SENS opcode, закон чи проєкцію.
  На вході — 6 host-операцій і 8x8 регістрів x86-64 r32.
  Вихід — два owned файли: суцільний машинний потік і текст GNU as;
  їхня семантика виключно машинна, SENS Dn/D7/D12+ не декодуються.
  TX64Code володіє managed RawByteString; TFileStream і TStringList
  звільняються у finally, вихід тесту відокремлено від SENS джерел.

  Питання: 1) Чому GNU as — незалежний машинний оракул?
  2) Чому для IMUL порядок ModRM відрізняється від ADD?
  3) Чому перевіряються всі 64 пари, зокрема ESP/EBP?
  4) Чому 384 машинні інструкції не є 384 функціями SENS?
  5) Чому винятки перевіряють незмінність TX64Code? }
program test_x64alu_as;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.x64code, wsm.x64alu;

const
  Operations: array[0..5] of TX64ALU =
    (xaAdd, xaSub, xaXor, xaAnd, xaCmp, xaImul);
  Mnemonics: array[0..5] of String =
    ('addl', 'subl', 'xorl', 'andl', 'cmpl', 'imull');
  Registers: array[0..7] of String =
    ('%eax', '%ecx', '%edx', '%ebx',
     '%esp', '%ebp', '%esi', '%edi');
var
  Code: TX64Code;
  Machine: TFileStream;
  Assembly: TStringList;
  O, D, S, Good, Bad: Integer;
  Old, Bytes: RawByteString;
  Rejected: Boolean;

procedure Require(Condition: Boolean; const Why: String);
begin
  if not Condition then raise Exception.Create('ALU-AS-ПОМИЛКА: '+Why);
end;

procedure CheckFailure(const Why: String);
begin
  Require(Rejected, 'не відхилено '+Why);
  Require(X64Image(Code)=Old, 'виняток змінив машинний потік: '+Why);
  Inc(Bad);
end;

begin
  Require(ParamCount=2, 'потрібні шляхи до потоку і GNU as');
  Good:=0;
  Bad:=0;
  Machine:=TFileStream.Create(ParamStr(1),fmCreate);
  try
    Assembly:=TStringList.Create;
    try
      Assembly.Add('.text');
      Assembly.Add('.globl _start');
      Assembly.Add('_start:');
      for O:=Low(Operations) to High(Operations) do
        for D:=Low(Registers) to High(Registers) do
          for S:=Low(Registers) to High(Registers) do begin
            X64Reset(Code);
            X64ALU32(Code, Operations[O], TX64Reg(D), TX64Reg(S));
            Bytes:=X64Image(Code);
            if Operations[O]=xaImul then
              Require(Length(Bytes)=3, 'IMUL має три байти')
            else
              Require(Length(Bytes)=2, 'ALU має два байти');
            Machine.WriteBuffer(Bytes[1],Length(Bytes));
            { AT&T: джерело перед призначенням; GNU as не читає Pascal. }
            Assembly.Add('  '+Mnemonics[O]+' '+Registers[S]+', '+Registers[D]);
            Inc(Good);
          end;
      Assembly.SaveToFile(ParamStr(2));
      Require(Good=384, 'неповна матриця 6x8x8');
      Require(Machine.Size=832, 'розмір 320 двобайтових + 64 трибайтових');
    finally
      Assembly.Free;
    end;
  finally
    Machine.Free;
  end;

  X64Reset(Code);
  Code.Bytes:=StringOfChar(#$90,254);
  X64ALU32(Code,xaAdd,xrAX,xrCX);
  Require(Length(Code.Bytes)=256,'немає точного краю квоти');
  Old:=X64Image(Code);
  Rejected:=False;
  try
    X64ALU32(Code,xaAdd,xrAX,xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('257-й байт');
  Rejected:=False;
  try
    X64ALU32(Code,xaImul,xrAX,xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('258-й/259-й байт');

  X64Reset(Code);
  Code.Bytes:=#$90;
  Old:=X64Image(Code);
  Rejected:=False;
  try
    X64ALU32(Code,TX64ALU(255),xrAX,xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('невідома host операція');
  Rejected:=False;
  try
    X64ALU32(Code,xaAdd,TX64Reg(8),xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('недопустимий host регістр');
  Rejected:=False;
  try
    X64ALU32(Code,xaImul,xrCX,TX64Reg(8));
  except on E:Exception do Rejected:=True end;
  CheckFailure('недопустиме джерело');
  X64Reset(Code);
  X64ALU32(Code,xaImul,xrDI,xrSP);
  Require(X64Image(Code)=#$0F#$AF#$FC,
    'відновлення IMUL edi,esp після пізнього винятку');
  Require(Bad=5,'неповний набір негативів');
  WriteLn('ALU-AS-ГОТОВО машинних=384 байтів=832 негативів=5 відновлення=1');
end.
