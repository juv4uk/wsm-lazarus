{ G6.248. Незалежне байтове звіряння восьми host-ALU з GNU assembler.
  Цей тест НЕ визначає SENS opcode, закон чи проєкцію.
  На вході — 6 початкових + OR/XCHG host-операції й регістри x86-64 r32.
  Вихід — два owned файли: суцільний машинний потік і текст GNU as;
  їхня семантика виключно машинна, SENS Dn/D7/D12+ не декодуються.
  TX64Code володіє managed RawByteString; TFileStream і TStringList
  звільняються у finally, вихід тесту відокремлено від SENS джерел.

  Питання: 1) Чому GNU as — незалежний машинний оракул?
  2) Чому для IMUL порядок ModRM відрізняється від ADD?
  3) Чому перевіряються всі 64 пари, зокрема ESP/EBP?
  4) Чому 497 машинних інструкцій не є 497 функціями SENS?
  5) Чому винятки перевіряють незмінність TX64Code? }
program test_x64alu_as;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.x64code, wsm.x64alu;

const
  Operations: array[0..7] of TX64ALU =
    (xaAdd, xaSub, xaXor, xaAnd, xaCmp, xaImul, xaOr, xaXchg);
  Mnemonics: array[0..7] of String =
    ('addl', 'subl', 'xorl', 'andl', 'cmpl', 'imull', 'orl', 'xchgl');
  Registers: array[0..7] of String =
    ('%eax', '%ecx', '%edx', '%ebx',
     '%esp', '%ebp', '%esi', '%edi');
var
  Code: TX64Code;
  Machine: TFileStream;
  Assembly: TStringList;
  O, D, S, Good, Bad: Integer;
  Invalid: Byte;
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
            { GNU as скорочує xchg eax,r32 до 90+r (1 байт):
              семантика та сама, але це НЕ ModRM 87/r з нашого
              emitter. Для незалежної побайтової матриці залишаємо
              7x7 пар без EAX; EAX має окремі golden/ELF тести.
              Параметри D/S — host-регістри; вихід — власний
              керований RawByteString у TX64Code, а Machine є
              тимчасовим TFileStream. Нічого не зберігається
              в SENS, а GNU as не призначає мовних законів.
              Питання: 1) Чому EAX XCHG не входить у byte parity?
              2) Чому 87/r і 90+r семантично однакові?
              3) Хто звільняє Machine та Assembly при винятку?
              4) Чому ми не змінили викличність доменів?
            }
            if (Operations[O]=xaXchg) and ((D=0) or (S=0)) then
              Continue;
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
      Require(Good=497, 'неповна матриця 6x8x8 + OR 8x8 + XCHG 7x7');
      Require(Machine.Size=1058,
        'розмір 384 старих + 64 OR + 49 XCHG команд');
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
  Invalid:=255;
  Rejected:=False;
  try
    X64ALU32(Code,TX64ALU(Invalid),xrAX,xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('невідома host операція');
  Invalid:=8;
  Rejected:=False;
  try
    X64ALU32(Code,xaAdd,TX64Reg(Invalid),xrCX);
  except on E:Exception do Rejected:=True end;
  CheckFailure('недопустимий host регістр');
  Rejected:=False;
  try
    X64ALU32(Code,xaImul,xrCX,TX64Reg(Invalid));
  except on E:Exception do Rejected:=True end;
  CheckFailure('недопустиме джерело');
  X64Reset(Code);
  X64ALU32(Code,xaImul,xrDI,xrSP);
  Require(X64Image(Code)=#$0F#$AF#$FC,
    'відновлення IMUL edi,esp після пізнього винятку');
  Require(Bad=5,'неповний набір негативів');
  WriteLn('ALU-AS-ГОТОВО машинних=497 байтів=1058 негативів=5 відновлення=1');
end.
