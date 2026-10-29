{ G6.145 — перевірка ЛИШЕ Linux x86-64 sys_write для вже допущеного
  ELF64 PIE; мовні закони належать pinned juv4uk/sens Contract 12.0.
  Механічний postpass не змінює D6, D12/D24, WideIR чи T5M tables. }
unit wsm.elfwriteguard;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EELFWriteGuardError=class(Exception);
function RequireCompleteNativeWrite(const Original:RawByteString):RawByteString;
implementation
uses wsm.elfgeometry;
const
  HeaderBytes=120;
  { Перевірений попередній кінець:
    mov eax,60; xor edi,edi; syscall — помилково завжди exit(0). }
  LegacyExit:RawByteString=#$B8#$3C#0#0#0#$31#$FF#$0F#$05;
  { Віддалений новий кінець, який виконується ПІСЛЯ sys_write:
    cmp eax,edx; setne dil; push 60; pop rax; syscall.
    EAX — фактично записані байти або -errno, EDX — бажана довжина.
    До write EDI=1, отже SETNE DIL змінює тільки нижній байт на 0/1.
    Push/pop гарантує повний RAX=60 навіть за від'ємного write return. }
  CheckedExit:RawByteString=#$39#$D0#$40#$0F#$95#$C7#$6A#$3C#$58#$0F#$05;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EELFWriteGuardError.Create(Why);
end;

{ Original — borrowed immutable machine ELF64, Result — owned
  copy-on-write ELF64 PIE. At — 1-based host byte index, displacement —
  signed relative x86 JMP rel32 to extra code AFTER unchanged T5M LUT.
  No previous RIP-relative LEA moves: all tables remain exactly in place.
  out on failure: exception, no partially published filesystem artifact.
  Questions: 1) Чому перевіряємо попередній Linux syscall?
  2) Чому не можна просто подовжити код ПЕРЕД T5M tables?
  3) Як зберігається байтове розташування усіх RIP-relative tables?
  4) Чому signed -errno гарантує відмінність EAX від EDX?
  5) Хто володіє Result після перевірки ELF geometry? }
function RequireCompleteNativeWrite(const Original:RawByteString):RawByteString;
var G:TELFGeometry;I,At,Found,NewSize:SizeInt;
    Distance:Int64;U:LongWord;J:Integer;
  procedure PutLE64(var Image:RawByteString;Offset:SizeInt;V:QWord);
  var K:Integer;
  begin
    Need((Offset>=0) and (Offset<=Length(Image)-8),
      'поле ELF64 поза фізичним образом');
    for K:=0 to 7 do begin
      Image[Offset+K+1]:=AnsiChar(Byte(V and $FF));V:=V shr 8;
    end;
  end;
begin
  Result:='';
  VerifySENSELF64(Original,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (Length(Original)<8192) and (G.FileBytes=Length(Original)),
       'потрібен малий verified ELF64 PIE з відомим ABI');
  Need(Length(CheckedExit)=11, 'неправильна ширина нового sys_exit');
  At:=0;Found:=0;
  for I:=HeaderBytes+3 to Length(Original)-Length(LegacyExit)+1 do
    if Copy(Original,I,Length(LegacyExit))=LegacyExit then begin
      Inc(Found);At:=I;
    end;
  Need(Found=1,'невідомий або неоднозначний машинний шаблон sys_exit');
  Need((At>=HeaderBytes+3) and
    (Copy(Original,At-2,2)=#$0F#$05),
    'попередній машинний виклик НЕ є очікуваним sys_write');
  NewSize:=Length(Original)+Length(CheckedExit);
  Need(NewSize<8192,'переповнена квота перевіреного ELF64');
  { JMP rel32 розміщено на місці 9-байтового exit. Нова ціль
    починається за останнім старим байтом, який зберігає своє місце. }
  Distance:=Int64(Length(Original))-Int64(At-1+5);
  Need((Distance>=Low(LongInt)) and (Distance<=High(LongInt)),
    'відносний перехід не представний x86-64 rel32');
  Result:=Original+CheckedExit;
  UniqueString(Result);
  Result[At]:=#$E9;
  U:=LongWord(LongInt(Distance));
  for J:=1 to 4 do begin
    Result[At+J]:=AnsiChar(Byte(U and $FF));U:=U shr 8;
  end;
  for J:=5 to 8 do Result[At+J]:=#$90;
  PutLE64(Result,96,NewSize);
  PutLE64(Result,104,NewSize);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=NewSize) and
    (Copy(Result,Length(Original)+1,Length(CheckedExit))=CheckedExit),
    'не пройдено незалежну ELF64 геометрію та check-epilogue');
end;
end.
