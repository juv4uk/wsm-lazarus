{ G6: вузький машинний свідок FPC inline asm ABI, а НЕ T5M reader чи SENS закон.
  Pascal QWord — host-слово з вісьмох байтів, canonical T5M лишається
  RawByteString; ні байти, ні точні біти не мають числового dispatch.
  1) Чому BSWAP не може підмінити T5M decoding?
  2) Чому cdecl + Linux x86-64 прив'язують параметр до RDI?
  3) Хто володіє фізичним RawByteString під час Move?
  4) Чому подвійний BSWAP має зберегти кожен байт?
  5) Чому це ще не доказ економії джоулів? }
program test_fpc_inline_t5m;
{$mode objfpc}{$H+}{$codepage utf8}
{$asmmode intel}
uses SysUtils, wsm.t5m;
var Checks, I, J, Pairs: SizeInt;
    Seed, Actual, Expected: QWord;
    Physical, Changed, Restored, Bits: RawByteString;
    Words, Decoded: TExactWords;
    Rejected: Boolean;

procedure Need(Condition:Boolean;const MessageText:String);
begin
  if not Condition then begin
    WriteLn(StdErr,'АСЕМБЛЕР-T5M-ПРОВАЛ ',MessageText);
    Halt(1);
  end;
  Inc(Checks);
end;

{ Linux x86-64 SysV cdecl: borrowed 64-бітний аргумент у RDI.
  Результат RAX, жодної купи/стеку; не використовувати на інших ABI. }
function AsmReverseByteOrder(V:QWord):QWord; cdecl; assembler; nostackframe;
asm
  mov rax, rdi
  bswap rax
end;

{ Portable host еталон: повертає вісім тих самих байтів у зворотному
  порядку, без жодної інтерпретації домену або opcode SENS. }
function PascalReverseByteOrder(V:QWord):QWord;
var K:Integer;
begin
  Result:=0;
  for K:=0 to 7 do begin
    Result:=(Result shl 8) or (V and $FF);
    V:=V shr 8;
  end;
end;

{ Owned RawByteString: копія при Copy; переставляємо ЛИШЕ повні
  вісім host-байтів. Неповний хвіст не змінюємо. }
function ReverseChunks(const Source:RawByteString):RawByteString;
var Off:SizeInt; X,Y:QWord;
begin
  Result:=Copy(Source,1,Length(Source));
  for Off:=0 to (Length(Result) div 8)-1 do begin
    Move(Result[1+Off*8],X,SizeOf(X));
    Y:=AsmReverseByteOrder(X);
    Move(Y,Result[1+Off*8],SizeOf(Y));
  end;
end;

begin
  Checks:=0;
  Need((SizeOf(QWord)=8) and (SizeOf(SizeInt)=8),
    'потрібна 64-бітна архітектура');
  Need(AsmReverseByteOrder($0102030405060708)=$0807060504030201,
    'BSWAP зламав регістровий ABI');
  Need(AsmReverseByteOrder(0)=0,'нульова машина');
  Need(AsmReverseByteOrder(High(QWord))=High(QWord),'максимальне слово');

  Seed:=$123456789ABCDEF0;
  for I:=1 to 1024 do begin
    Seed:=Seed xor (Seed shl 13);
    Seed:=Seed xor (Seed shr 7);
    Seed:=Seed xor (Seed shl 17);
    Expected:=PascalReverseByteOrder(Seed);
    Actual:=AsmReverseByteOrder(Seed);
    Need(Actual=Expected,'машинне BSWAP не тотожне Pascal');
    Need(AsmReverseByteOrder(Actual)=Seed,'подвійний BSWAP не тотожний');
  end;

  { 64 точних W12 НЕ є числовими значеннями D12: лише непрозорі
    бітові слова для існуючого canonical EncodeT5M/DecodeT5M. }
  SetLength(Words,64);
  for I:=0 to High(Words) do begin
    SetLength(Bits,12);
    for J:=1 to 12 do
      if ((I*17+J*31) mod 7)<3 then Bits[J]:='0'
      else Bits[J]:='1';
    Words[I]:=Bits;
  end;
  Physical:=EncodeT5M(Words);
  Need(Length(Physical)>64,'занадто короткий фізичний T5M свідок');
  Pairs:=Length(Physical) div 8;
  Changed:=ReverseChunks(Physical);
  Need(Changed<>Physical,'BSWAP не змінив жодного восьмибайтового блоку');
  Restored:=ReverseChunks(Changed);
  Need(Restored=Physical,'пошкоджено фізичні байти після другого BSWAP');
  DecodeT5M(Restored,Decoded);
  Need(Length(Decoded)=Length(Words),'втрачено точні Wn-слова');
  for I:=0 to High(Words) do
    Need(Decoded[I]=Words[I],'змінено біти/ширину фізичного слова');
  Need(EncodeT5M(Decoded)=Physical,'незворотний canonical T5M');

  { Fail closed: недопустимі T5M байти не стають словами.
    Негатив виконує наявний canonical reader без альтернативної копії. }
  Rejected:=False;
  try
    DecodeT5M(#$FF,Decoded)
  except on E:ET5MError do Rejected:=True end;
  Need(Rejected,'неканонічний T5M байт допущено');
  Need(Length(Decoded)=0,'негатив повернув часткові слова');

  WriteLn('INLINE-T5M-PASS vectors=1024 double=1024',
    ' physical_bytes=',Length(Physical),' blocks=',Pairs,
    ' words=64 negative=1 reference=Pascal checks=',Checks,
    ' oracle=NOT_RUN energy=NOT_MEASURED');
end.
