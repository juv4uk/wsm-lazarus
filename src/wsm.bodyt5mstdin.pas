{ G6.161 — постперетворення ПЕРЕВІРЕНОГО ELF64 з фізичним D24 stdin.
  Machine stub — лише x86-64 ABI: read(0,5), strict base3 T5M,
  signed D24 -> edi і перехід у вже зкомпільований CALL.
  Джерело машинних байтів — scripts/par-t5mstdin-x86-64.S;
  CI перевіряє їхню byte-for-byte тотожність асемблеру GNU.
  Упаковані .sens лишаються мовою; ELF, syscall та EDI — host-механізми.
  Вхідний ELF borrowed; Result owned RawByteString, без побічних файлів.
  Питання: 1) Чому заголовок ELF зберігає entry=120?
  2) Чому не можна декодувати D24 як ASCII або D12?
  3) Чому будь-який третій трит, відсутній 2 чи trailing byte — відмова?
  4) Чому старі rel32 між двома функціями лишаються чинними?
  5) Чому статичний компіляторний аргумент більше не використовується? }
unit wsm.bodyt5mstdin;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EBodyT5MStdinError=class(Exception);
function DynamicD24T5MStdinELF(const StaticImage:RawByteString):RawByteString;
implementation
uses wsm.elfgeometry;
const
  HeaderBytes=120;
  JumpFieldAt=618; { offset у машинному stub: pair_jump+1 = $26b }
  StubBytes=635;
  StubHex=
    '4883ec1031db4531e431c031ff4a8d3424ba050000004429e20f054883f8fc74e84885c00f8e450200004901c44983fc0572d631c031ff' +
    '488d742405ba010000000f054883f8fc74ea4885c00f851d0200000fb60c2481f9a20000000f830d02000083f951720783e9510fbaeb17' +
    '83f9360f83f801000083f91b720783e91b0fbaeb1683f9120f83e301000083f909720783e9090fbaeb1583f9060f83ce01000083f90372' +
    '0783e9030fbaeb1483f9020f83b901000083f901720783e9010fbaeb130fb64c240181f9a20000000f839c01000083f951720783e9510f' +
    'baeb1283f9360f838701000083f91b720783e91b0fbaeb1183f9120f837201000083f909720783e9090fbaeb1083f9060f835d01000083' +
    'f903720783e9030fbaeb0f83f9020f834801000083f901720783e9010fbaeb0e0fb64c240281f9a20000000f832b01000083f951720783' +
    'e9510fbaeb0d83f9360f831601000083f91b720783e91b0fbaeb0c83f9120f830101000083f909720783e9090fbaeb0b83f9060f83ec00' +
    '000083f903720783e9030fbaeb0a83f9020f83d700000083f901720783e9010fbaeb090fb64c240381f9a20000000f83ba00000083f951' +
    '720783e9510fbaeb0883f9360f83a500000083f91b720783e91b0fbaeb0783f9120f839000000083f909720783e9090fbaeb0683f90673' +
    '7f83f903720783e9030fbaeb0583f902736e83f901720783e9010fbaeb040fb64c240481f9a20000000735583f951720783e9510fbaeb0' +
    '383f936734483f91b720783e91b0fbaeb0283f912733383f909720783e9090fbaeb0183f906732283f903720783e9030fbaeb0083f9027' +
    '511c1e308c1fb0889df4883c410e900000000bf02000000b83c0000000f05';
  StdoutStart:array[0..9] of Byte=($89,$C1,$C1,$E1,$08,$C1,$F9,$08,$39,$C8);

procedure Need(OK:Boolean;const Reason:UnicodeString);
begin
  if not OK then raise EBodyT5MStdinError.Create(UTF8Encode(Reason));
end;

function Nibble(C:AnsiChar):Byte;
begin
  case C of
    '0'..'9':Result:=Ord(C)-Ord('0');
    'a'..'f':Result:=Ord(C)-Ord('a')+10;
    else raise EBodyT5MStdinError.Create('некоректні байти stub');
  end;
end;

{ Hex bytes are an auditable copy of the included GNU-as source,
  machine code is not interpreted as SENS laws.
  Question: how is accidental drift of embedded bytes caught in CI? }
function ExactStub:RawByteString;
var I:SizeInt;
begin
  Need(Length(StubHex)=StubBytes*2,'невірний розмір машинного декодера');
  SetLength(Result,StubBytes);
  for I:=0 to StubBytes-1 do
    Result[I+1]:=AnsiChar((Nibble(StubHex[2*I+1]) shl 4) or
                               Nibble(StubHex[2*I+2]));
  Need(Byte(Result[JumpFieldAt])=$E9,'немає контрольованого rel32 переходу');
end;

procedure Put32(var Data:RawByteString;Offset:SizeInt;Value:LongWord);
var I:Integer;
begin
  Need((Offset>=0) and (Offset<=Length(Data)-4),'ELF rel32 виходить за буфер');
  for I:=0 to 3 do begin
    Data[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
procedure Put64(var Data:RawByteString;Offset:SizeInt;Value:QWord);
var I:Integer;
begin
  Need((Offset>=0) and (Offset<=Length(Data)-8),'ELF поле виходить за буфер');
  for I:=0 to 7 do begin
    Data[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function Read32(const Data:RawByteString;Offset:SizeInt):LongWord;
var I:Integer;
begin
  Need((Offset>=0) and (Offset<=Length(Data)-4),'ELF поле поза буфером');
  Result:=0;
  for I:=3 downto 0 do Result:=(Result shl 8) or
    LongWord(Byte(Data[Offset+I+1]));
end;

{ Fail closed: only accept current known pair stdout emitter.
  Existing ELF must be ET_EXEC, single RX segment, fixed _start,
  mov edi,imm32; call target; canonical D24 stdout stub; paired
  prologue push rdi / push rbx. No generic or arbitrary ELF injection.
  Questions: Why does verifying geometry alone not prove compiler origin?
  Why verify call target within the file before patching? }
procedure VerifyPairBody(const Image:RawByteString;out G:TELFGeometry);
var I,Target:SizeInt;
begin
  VerifySENSELF64(Image,G);
  Need((G.Kind=2) and (G.Entry=$400078) and
    (G.MachineBytes>StubBytes) and (G.FileBytes+StubBytes<=1024*1024),
    'очікується перевірений фізичний pair D24 T5M ELF64');
  Need((Byte(Image[HeaderBytes+1])=$BF) and
    (Byte(Image[HeaderBytes+6])=$E8),
    'невідомий вхідний машинний ABI двох тіл');
  for I:=0 to High(StdoutStart) do
    Need(Byte(Image[HeaderBytes+11+I])=StdoutStart[I],
      'не знайдено перевірений D24 T5M stdout');
  Target:=HeaderBytes+10+LongInt(Read32(Image,HeaderBytes+6));
  Need((Target>=HeaderBytes+10+10) and (Target+2<=G.FileBytes),
    'адреса фізичного тіла виходить за ELF');
  Need((Byte(Image[Target+1])=$57) and (Byte(Image[Target+2])=$53),
    'не впізнано пару функцій із власними лексичними кадрами');
end;

function DynamicD24T5MStdinELF(const StaticImage:RawByteString):RawByteString;
var G,After:TELFGeometry;Stub:RawByteString;OldSize:SizeInt;
begin
  Result:='';
  VerifyPairBody(StaticImage,G);
  OldSize:=G.FileBytes;
  Stub:=ExactStub;
  Result:=StaticImage+Stub;
  { Original entry 120 must remain intact for strict ELF admission.
    Replace only five-byte mov edi,IMM32 with near-jump to appended
    decoder. It returns to old entry+5 (CALL), never to old immediate.
    All function/call rel32 deltas remain identical.
    1) Why is the first jmp relative to 125?
    2) Why does appended stub jump backward to 125?
    3) What makes this one executable reusable for all runtime args? }
  Result[HeaderBytes+1]:=AnsiChar($E9);
  Put32(Result,HeaderBytes+1,LongWord(LongInt(OldSize-(HeaderBytes+5))));
  Put32(Result,OldSize+JumpFieldAt,
    LongWord(LongInt((HeaderBytes+5)-(OldSize+JumpFieldAt+4))));
  Put64(Result,96,QWord(Length(Result)));
  Put64(Result,104,QWord(Length(Result)));
  VerifySENSELF64(Result,After);
  Need((After.Kind=2) and (After.Entry=$400078) and
       (After.FileBytes=Length(Result)),
       'пошкоджено геометрію нового ELF');
end;
end.
