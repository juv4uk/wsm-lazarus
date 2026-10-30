{ G6.154 — фізичний D24 T5M stdout з чинного native body lowering.
  Лише x86-64 Linux postpass: exact signed D24 EAX → canonical T5M.
  Контракт тритів бере чинний wsm.t5m і pinned SENS; жодних мовних
  законів, D7-dispatch чи нового evaluator.
  Owned RawByteString — результат. Жодних heap-алокацій усередині ELF.
  Питання: чому D24 — 24 точних біти, а не host EAX?
  Чому кінцевий трит 2? Чому перевіряємо шаблон EXIT?
  Чому self CALL не потребує перепатчування? Хто власник ELF? }
unit wsm.bodyt5mstdout;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EBodyT5MStdoutError=class(Exception);
function BodyD24T5MStdoutELF(const ExitImage:RawByteString):RawByteString;
implementation
uses wsm.elfgeometry;
const
  HeaderBytes=120;
  OriginalExit:array[0..11] of Byte=
    ($89,$C7,$83,$E7,$FF,$B8,$3C,$00,$00,$00,$0F,$05);
  TernaryWeight:array[0..4] of Byte=(81,27,9,3,1);
procedure Need(Ok:Boolean;const Why:UnicodeString);
begin
  if not Ok then raise EBodyT5MStdoutError.Create(UTF8Encode(Why))
end;
{ Буфер — owned керований байтовий рядок. Індекси little-endian
  це лише host-ELF, не нумерація Dn. Перевірки меж до запису.
  Питання: чому little endian? Чому поле 4 байти?
  Чому це не новий SENS numeric domain? }
procedure Put32(var Data:RawByteString;Pos:SizeInt;V:LongWord);
var I:Integer;
begin
  Need((Pos>=0) and (Pos<=Length(Data)-4),'поле ELF поза образом');
  for I:=0 to 3 do begin
    Data[Pos+I+1]:=AnsiChar(Byte(V and $FF));V:=V shr 8;
  end;
end;
function Get32(const Data:RawByteString;Pos:SizeInt):LongWord;
var I:Integer;
begin
  Need((Pos>=0) and (Pos<=Length(Data)-4),'читання ELF поза образом');
  Result:=0;
  for I:=3 downto 0 do Result:=(Result shl 8) or
    LongWord(Byte(Data[Pos+I+1]));
end;
{ Вхід EAX із перевіреної функції; перевірка знакового D24 через
  sign-extension (SHL/SAR), переповнення → exit2 без stdout.
  Рівно 24 двійкові трити і ОДИН кінцевий 2 у п'яти байтах base3.
  Машинний syscall write повинен записати рівно 5 байтів; інакше exit2.
  Результат — власні host-інструкції RawByteString, їхній lifetime
  до формування нового ELF; machine stack використовує рівно 8 байтів.
  Питання: чому не можна тихо відкинути старші 8 бітів EAX?
  Чому T5M byte обчислюємо в base3? Чому padding лише один трит?
  Чому після write перевіряємо RAX? Чому немає ASCII-проєкції? }
function StubD24:RawByteString;
var I,J,BitNo,Shift,Weight,FailAt,JneRange,JneWrite:SizeInt;
  procedure Emit(const Bytes:array of Byte);
  var K,N:SizeInt;
  begin
    N:=Length(Result);SetLength(Result,N+Length(Bytes));
    for K:=0 to High(Bytes) do Result[N+K+1]:=AnsiChar(Bytes[K]);
  end;
  procedure PatchJne(StartAt,Dest:SizeInt);
  begin Put32(Result,StartAt+2,LongWord(LongInt(Dest-(StartAt+6)))) end;
begin
  Result:='';
  Emit([$89,$C1,$C1,$E1,$08,$C1,$F9,$08,$39,$C8]);
  JneRange:=Length(Result);
  Emit([$0F,$85,0,0,0,0]); { jne fail if EAX is not exact signed D24 }
  Emit([$48,$83,$EC,$08]); { sub rsp,8 }
  for I:=0 to 4 do begin
    Emit([$31,$D2]); { xor edx,edx }
    for J:=0 to 4 do begin
      BitNo:=I*5+J;
      if BitNo=24 then begin
        Emit([$83,$C2,$02]); { last pad trit 2 }
        Continue;
      end;
      Need(BitNo<24,'неприпустимий номер трита');
      Shift:=23-BitNo;
      Weight:=TernaryWeight[J];
      Emit([$89,$C1]); { mov ecx,eax }
      if Shift<>0 then Emit([$C1,$E9,Byte(Shift)]); { shr ecx,shift }
      Emit([$83,$E1,$01]); { and ecx,1 }
      if Weight<>1 then Emit([$6B,$C9,Byte(Weight)]); { imul ecx,weight }
      Emit([$01,$CA]); { add edx,ecx }
    end;
    Emit([$88,$54,$24,Byte(I)]); { mov [rsp+i],dl }
  end;
  Emit([$B8,$01,0,0,0, $BF,$01,0,0,0, $48,$89,$E6,
        $BA,$05,0,0,0, $0F,$05, $48,$83,$F8,$05]);
  JneWrite:=Length(Result);
  Emit([$0F,$85,0,0,0,0]); { short write / errno → fail }
  Emit([$31,$FF, $B8,$3C,0,0,0, $0F,$05]); { exit0 }
  FailAt:=Length(Result);
  Emit([$BF,$02,0,0,0, $B8,$3C,0,0,0, $0F,$05]); { exit2 }
  PatchJne(JneRange,FailAt);
  PatchJne(JneWrite,FailAt);
end;
{ Позичений Image із уже допущеного wsm.lowerd24: початковий
  пролог (1 або 2 аргументи), CALL rel32, точний 12-byte EXIT.
  Замінюємо тільки EXIT, рухаємо ВСЮ функцію разом (внутрішні
  selfcall rel32 не змінюються), виправляємо перший CALL та
  p_filesz/p_memsz, знову VerifySENSELF64.
  Результат — новий managed ELF, нуль файлових побічних дій.
  Питання: чому звіряємо повні байти старого EXIT?
  Чому SELF call delta не залежить від місця функції?
  Чому entry point лишається $400078? Чому перевірка ELF повторна?
  Чому графічна проєкція D7 не впливає на ABI? }
function BodyD24T5MStdoutELF(const ExitImage:RawByteString):RawByteString;
var G:TELFGeometry;CallAt,I,SuffixAt,Delta:SizeInt;Stub:RawByteString;
begin
  Result:='';
  VerifySENSELF64(ExitImage,G);
  Need(G.Kind=2,'очікується ET_EXEC з поточного D24 lowering');
  Need((G.MachineBytes>=27) and
    (Byte(ExitImage[HeaderBytes+1])=$BF),'невідомий D24 пролог');
  CallAt:=5;
  if Byte(ExitImage[HeaderBytes+CallAt+1])=$BE then begin
    Need(G.MachineBytes>=32,'неповний пролог двох параметрів');
    Inc(CallAt,5);
  end;
  Need((Byte(ExitImage[HeaderBytes+CallAt+1])=$E8) and
       (Get32(ExitImage,HeaderBytes+CallAt+1)=12),
       'невідомий CALL ABI D24 lowering');
  SuffixAt:=HeaderBytes+CallAt+5+12;
  Need(SuffixAt<G.FileBytes,'відсутня машинна функція');
  for I:=0 to High(OriginalExit) do
    Need(Byte(ExitImage[HeaderBytes+CallAt+5+I+1])=OriginalExit[I],
       'непізнаний exit trampoline: відмова');
  Stub:=StubD24;
  Delta:=Length(Stub)-Length(OriginalExit);
  Need((Delta>=0) and (G.FileBytes+Delta<=1024*1024),
       'квота ELF64 перевищена');
  Result:=Copy(ExitImage,1,HeaderBytes+CallAt+5)+Stub+
    Copy(ExitImage,SuffixAt+1,MaxInt);
  Put32(Result,HeaderBytes+CallAt+1,LongWord(Length(Stub)));
  Put32(Result,96,LongWord(Length(Result)));
  Put32(Result,104,LongWord(Length(Result)));
  VerifySENSELF64(Result,G);
  Need((G.Kind=2) and (G.FileBytes=Length(Result)),
       'пошкоджений результуючий ELF');
end;
end.
