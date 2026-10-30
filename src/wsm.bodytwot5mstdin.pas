{ G6.175 — два runtime D24 (фізичні 2×5 байтів T5M) у готовому ELF.
  Жодної SENS арифметики або визначень Core1 у Pascal: цей unit
  модифікує ТІЛЬКИ вхідний ABI чинного source-backed lowering D24.
  GNU-as canonical witness: scripts/dvaparam-t5mstdin-x86-64.S.
  CI побайтово звіряє машинний stub, виконує справжній x86-64 ELF.
  Original borrowed; Result owned. Відмова до файлової публікації.
  Питання: 1) Чому D12 не можна тихо прийняти як D24?
  2) Чому має бути саме ДВА фізичні документи W24?
  3) Чому rel32 скомпільованого тіла НЕ змінюються після append?
  4) Чому ABI EDI/ESI не визначає мовних законів?
  5) Навіщо повторно VerifySENSELF64 після postpass? }
unit wsm.bodytwot5mstdin;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ETwoT5MStdinError=class(Exception);
function DynamicTwoD24StdinELF(const Original:RawByteString):RawByteString;
implementation
uses wsm.elfgeometry;
const
  HeaderBytes=120;
  StubSize=658;
  StubJumpAt=111; { zero-index E9, rel32 starts at 112 }
  StubHex=
    '4883ec204531e431c031ff4a8d3424ba0a0000004429e20f054883f8fc74e84885c00f8e5e0200004901c44983fc0a72d631c031ff488d' +
    '74240aba010000000f054883f8fc74ea4885c00f8536020000488d3424e81b0000004189c5488d742405e80e00000089c64489ef4883c4' +
    '20e90000000031db0fb60e81f9a20000000f830102000083f951720783e9510fbaeb1783f9360f83ec01000083f91b720783e91b0fbaeb' +
    '1683f9120f83d701000083f909720783e9090fbaeb1583f9060f83c201000083f903720783e9030fbaeb1483f9020f83ad01000083f901' +
    '720783e9010fbaeb130fb64e0181f9a20000000f839101000083f951720783e9510fbaeb1283f9360f837c01000083f91b720783e91b0f' +
    'baeb1183f9120f836701000083f909720783e9090fbaeb1083f9060f835201000083f903720783e9030fbaeb0f83f9020f833d01000083' +
    'f901720783e9010fbaeb0e0fb64e0281f9a20000000f832101000083f951720783e9510fbaeb0d83f9360f830c01000083f91b720783e9' +
    '1b0fbaeb0c83f9120f83f700000083f909720783e9090fbaeb0b83f9060f83e200000083f903720783e9030fbaeb0a83f9020f83cd0000' +
    '0083f901720783e9010fbaeb090fb64e0381f9a20000000f83b100000083f951720783e9510fbaeb0883f9360f839c00000083f91b7207' +
    '83e91b0fbaeb0783f9120f838700000083f909720783e9090fbaeb0683f906737683f903720783e9030fbaeb0583f902736583f9017207' +
    '83e9010fbaeb040fb64e0481f9a2000000734d83f951720783e9510fbaeb0383f936733c83f91b720783e91b0fbaeb0283f912732b83f9' +
    '09720783e9090fbaeb0183f906731a83f903720783e9030fbaeb0083f9027509c1e308c1fb0889d8c3bf02000000b83c0000000f05';
  StdoutPrefix:array[0..9] of Byte=($89,$C1,$C1,$E1,$08,$C1,$F9,$08,$39,$C8);
procedure Need(OK:Boolean;const Message:UnicodeString);
begin if not OK then raise ETwoT5MStdinError.Create(UTF8Encode(Message)) end;
function Nibble(C:AnsiChar):Byte;
begin
  case C of
    '0'..'9':Result:=Ord(C)-Ord('0');
    'a'..'f':Result:=Ord(C)-Ord('a')+10;
    else raise ETwoT5MStdinError.Create('пошкоджений байтовий декодер');
  end;
end;
function StubBytes:RawByteString;
var I:SizeInt;
begin
  Need(Length(StubHex)=2*StubSize,'помилка розміру машинного декодера');
  SetLength(Result,StubSize);
  for I:=0 to StubSize-1 do
    Result[I+1]:=AnsiChar((Nibble(StubHex[2*I+1]) shl 4) or
                         Nibble(StubHex[2*I+2]));
  Need(Copy(Result,StubJumpAt+1,5)=#$E9#0#0#0#0,
    'немає контрольованого переходу назад до тіла');
end;
procedure PutLE(var B:RawByteString;Offset,N:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (N>=1) and (N<=8) and
       (Offset<=Length(B)-N),'переповнення поля ELF');
  for I:=0 to N-1 do begin
    B[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function Read32(const B:RawByteString;Offset:SizeInt):LongInt;
var I:Integer;V:LongWord;
begin
  Need((Offset>=0) and (Offset<=Length(B)-4),'CALL поза образом');
  V:=0;
  for I:=3 downto 0 do
    V:=(V shl 8) or LongWord(Byte(B[Offset+I+1]));
  Result:=LongInt(V);
end;
procedure VerifyTwoParameterBody(const B:RawByteString;out G:TELFGeometry);
var Target,I:SizeInt;
begin
  VerifySENSELF64(B,G);
  Need((G.Kind=2) and (G.Entry=$400078) and (G.MachineBytes>80) and
       (G.FileBytes+StubSize<=1024*1024),
       'потрібен чинний source-backed D24 ET_EXEC ELF64');
  Need((Byte(B[HeaderBytes+1])=$BF) and
       (Byte(B[HeaderBytes+6])=$BE) and
       (Byte(B[HeaderBytes+11])=$E8),
       'потрібен саме двоаргументний D24 ABI');
  for I:=0 to High(StdoutPrefix) do
    Need(Byte(B[HeaderBytes+15+I+1])=StdoutPrefix[I],
         'немає доведеного фізичного T5M D24 stdout');
  Target:=HeaderBytes+15+SizeInt(Read32(B,HeaderBytes+11));
  Need((Target>HeaderBytes+25) and (Target<=G.FileBytes-3),
    'CALL target вийшов за executable сегмент');
  Need((Byte(B[Target+1])=$57) and (Byte(B[Target+2])=$56) and
       (Byte(B[Target+3])=$53),
       'непізнаний compiled two-param lexical frame');
end;
function DynamicTwoD24StdinELF(const Original:RawByteString):RawByteString;
var G,A:TELFGeometry;Stub:RawByteString;OldSize,I:SizeInt;
begin
  Result:='';
  VerifyTwoParameterBody(Original,G);
  Stub:=StubBytes;
  OldSize:=Length(Original);
  Result:=Original+Stub;
  { mov edi,imm32; mov esi,imm32 (10 bytes) → jmp stub; 5 NOP.
    По поверненні stub EDI/ESI — два знакові D24, вхід+10 = CALL.
    1) Чому зміщення переходу з 5 байтів до кінця stub?
    2) Чому наявний CALL rel32 не переписується?
    3) Чому до непідтвердженого ELF робиться відмова? }
  Result[HeaderBytes+1]:=AnsiChar($E9);
  PutLE(Result,HeaderBytes+1,4,
    LongWord(LongInt(OldSize-(HeaderBytes+5))));
  for I:=5 to 9 do Result[HeaderBytes+I+1]:=AnsiChar($90);
  PutLE(Result,OldSize+StubJumpAt+1,4,
    LongWord(LongInt(HeaderBytes+10-
      (OldSize+StubJumpAt+5))));
  PutLE(Result,96,8,QWord(Length(Result)));
  PutLE(Result,104,8,QWord(Length(Result)));
  VerifySENSELF64(Result,A);
  Need((A.Kind=2) and (A.Entry=$400078) and
    (A.FileBytes=Length(Result)),
    'пошкоджена фізична геометрія ELF64');
end;
end.
