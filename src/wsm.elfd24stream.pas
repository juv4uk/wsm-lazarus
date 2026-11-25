{ G6.265 — динамічне D24+D24 після канонічного pinned D5/WideIR.
  Це ТІЛЬКИ Linux x86-64 механізм: мовний допуск повної D5:01010
  форми виконано чинним BuildIRWideD24CarryELF; не новий SENS закон.
  У runtime stdin: два ОКРЕМІ packed W24 атоми (5+5=10 байтів),
  не одна багатослівна .sens програма. Транспорт перевіряється через
  T5M lookup, створені виключно чинним EncodeT5M, і точний EOF.
  CPU обчислює обидва operands та signed overflow; результат D24
  видає незмінений donor ADD→ADC/T5M output; D48 overflow — exit(2).
  Source/Root borrowed RawByteString; Result — owned verified ELF64 PIE.
  Donor, Prefix, maps — managed FPC із lifetime цього виклику.
  1) Чому повна форма D5 обов'язкова перед генерацією machine code?
  2) Чому два W24 у stdin — host ABI, а не нова граматика SENS?
  3) Як invalid T5M відрізняється від реального нуля?
  4) Чому donor RIP-відстані лишаються незмінними після prepend?
  5) Чому exit(2) на D48 — чесніше, ніж тихо обрізати D24? }
unit wsm.elfd24stream;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED24StreamError=class(Exception);
function BuildD24StreamAddELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry,wsm.irwided24carry;
const HeaderBytes=120; MaxMachineBytes=4096; T5MByteCount=243;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED24StreamError.Create(Why) end;

{ Map: власна 243-байтна lookup для п'яти T5M тритів.
  InvalidByte=255 не є припустимим W5/W4 значенням;
  valid entries породжує лише EncodeT5M поточного pin.
  1) Чому 3^5=243 не означає 243 мовні слова?
  2) Чому W4 має іншу padding identity ніж W5?
  3) Чому не можна вивести table з ASCII кодів?
  4) Хто звільняє managed Map? }
function DecodeMap(Width:Integer):RawByteString;
var Words:TExactWords;Bits,Physical:RawByteString;I,J:Integer;
begin
  Need(Width in [4,5],'дозволено лише host lookup W4/W5');
  SetLength(Result,T5MByteCount);
  FillChar(Result[1],Length(Result),255);
  SetLength(Words,1);
  for I:=0 to (1 shl Width)-1 do begin
    SetLength(Bits,Width);
    for J:=1 to Width do
      if (I and (1 shl (Width-J)))<>0 then Bits[J]:='1'
      else Bits[J]:='0';
    Words[0]:=Bits;
    Physical:=EncodeT5M(Words);
    Need((Length(Physical)=1) and
         (Ord(Physical[1])<T5MByteCount),'порушено canonical T5M');
    Need(Byte(Result[Ord(Physical[1])+1])=255,
         'неоднозначний canonical W4/W5 mapping');
    Result[Ord(Physical[1])+1]:=AnsiChar(Byte(I));
  end;
end;

{ Signed little endian машинні rel32: At — нульове зміщення в Prefix,
  Target — нульова адреса від entry ELF64. Слідкуємо за capacity
  до кожної patch, жодного часткового Result на помилці. }
procedure PatchRel32(var Prefix:RawByteString;At:SizeInt;Target:Int64);
var Delta:Int64;U:LongWord;I:Integer;
begin
  Delta:=Target-Int64(At)-4;
  Need((At>=0) and (At+4<=Length(Prefix)) and
       (Delta>=Low(LongInt)) and (Delta<=High(LongInt)),
       'відносна машинна адреса поза допустимим простором');
  U:=LongWord(LongInt(Delta));
  UniqueString(Prefix);
  for I:=0 to 3 do begin
    Prefix[At+I+1]:=AnsiChar(Byte(U and $FF));U:=U shr 8;
  end;
end;

procedure PatchElfSize(var Image:RawByteString;At:SizeInt;Value:QWord);
var I:Integer;
begin
  Need((At>=0) and (At+8<=Length(Image)),'поле ELF64 поза образом');
  UniqueString(Image);
  for I:=0 to 7 do begin
    Image[At+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Від donor беремо вже доведену машину ADD→ADC, її T5M lookup
  і sys_write перевірку. Перевіряємо чотири exact mov imm32 W24 anchor:
  новий prelude розраховує EAX/ECX/EDX/EBX для тих САМИХ інструкцій,
  а один JMP перестрибує тільки anchor-константи. Усі донорські
  RIP-relative звернення зсуваються разом із його 237 байтами.
  1) Чому donor не переінтерпретує runtime ввід як вихідні константи?
  2) Чому після читання R10 можна використовувати для sign extension?
  3) Де EOF probe зупиняє одинадцятий байт?
  4) Чому ADD→ADC зберігає carry між двома машинними інструкціями?
  5) Де фіксуємо машинний вихід, а не тільки ELF header? }
function BuildD24StreamAddELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Donor,Prefix,Map5,Map4,SourceBytes:RawByteString;
    G:TELFGeometry;
    I,J,LoopAt,ProbeAt,RejectAt,JumpAt,PrefixLen,MapStart:SizeInt;
    Rejects:array[0..27] of SizeInt;
    RejectCount:Integer;
    Leas:array[0..9] of SizeInt;
    LeaKinds:array[0..9] of Integer;
    LeaCount:Integer;

  procedure Emit(const Bytes:RawByteString);
  begin
    Need((Length(Bytes)>0) and (Length(Prefix)+Length(Bytes)<=2048),
         'перевищено квоту x86 machine prelude');
    Prefix:=Prefix+Bytes;
  end;
  procedure EmitJumpReject(ByteCode:Byte);
  begin
    Need(RejectCount<Length(Rejects),'переповнено машинні гілки');
    Rejects[RejectCount]:=Length(Prefix)+2;
    Inc(RejectCount);
    Emit(#$0F+AnsiChar(ByteCode)+#0#0#0#0);
  end;
  procedure EmitLea(Kind:Integer);
  begin
    Need(LeaCount<Length(Leas),'переповнено machine T5M lookup');
    Leas[LeaCount]:=Length(Prefix)+3;
    LeaKinds[LeaCount]:=Kind;
    Inc(LeaCount);
    Emit(#$48#$8D#$35#0#0#0#0); { lea rsi,[rip+map] }
  end;
  procedure EmitDecode(Atom,Offset:Integer);
  var K:Integer;
  begin
    if Atom=0 then Emit(#$45#$31#$C0) { xor r8d,r8d }
    else Emit(#$45#$31#$C9);          { xor r9d,r9d }
    for K:=0 to 4 do begin
      { movzx ecx,byte [rsp+N], indexes from canonical 10-byte stdin. }
      Emit(#$0F#$B6#$4C#$24+AnsiChar(Byte(Offset+K)));
      { T5M byte 243..255: перевірити ІНДЕКС до таблиці 243 bytes;
        без цього untrusted stdin міг прочитати пам'ять після map. }
      Emit(#$81#$F9#$F3#0#0#0);     { cmp ecx,243 }
      EmitJumpReject($83);           { jae reject BEFORE lookup }
      if K=4 then EmitLea(1) else EmitLea(0);
      Emit(#$0F#$B6#$0C#$0E);        { movzx ecx,[rsi+rcx] }
      if K=4 then Emit(#$83#$F9#$10) { cmp ecx,16 }
      else Emit(#$83#$F9#$20);       { cmp ecx,32 }
      EmitJumpReject($83);           { jae invalid lookup }
      if Atom=0 then begin
        if K=4 then Emit(#$41#$C1#$E0#$04)
        else Emit(#$41#$C1#$E0#$05); { shl r8d,4/5 }
        Emit(#$41#$09#$C8);          { or r8d,ecx }
      end else begin
        if K=4 then Emit(#$41#$C1#$E1#$04)
        else Emit(#$41#$C1#$E1#$05); { shl r9d,4/5 }
        Emit(#$41#$09#$C9);          { or r9d,ecx }
      end;
    end;
  end;
begin
  Result:='';
  { Повна фізична D5 форма й дві exact W24 — уже admission донора.
    Не наділяємо W24 мовним законом за самим runtime розміром 5. }
  Donor:=BuildIRWideD24CarryELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Donor,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Donor)) and
       (Length(Donor)>HeaderBytes+20) and
       (Copy(Donor,HeaderBytes+1,1)=#$B8) and
       (Copy(Donor,HeaderBytes+6,1)=#$B9) and
       (Copy(Donor,HeaderBytes+11,1)=#$BA) and
       (Copy(Donor,HeaderBytes+16,1)=#$BB) and
       (Copy(Donor,HeaderBytes+21,2)=#$01#$C8),
       'непідтверджений машинний ADD/ADC donor');
  { Донорський байт за EAX/ECX — ADD. Після нього маємо ADC. }
  Need(Copy(Donor,HeaderBytes+23,2)=#$11#$DA,
       'непідтверджено machine ADC після ADD');

  Map5:=DecodeMap(5);
  Map4:=DecodeMap(4);
  Prefix:='';RejectCount:=0;LeaCount:=0;
  { sub rsp,32; r10 — точна кількість прийнятих байтів. }
  Emit(#$48#$83#$EC#$20);
  Emit(#$45#$31#$D2);
  LoopAt:=Length(Prefix);
  Emit(#$31#$C0);                     { eax=read syscall }
  Emit(#$31#$FF);                     { edi=fd0 }
  Emit(#$4A#$8D#$34#$14);             { lea rsi,[rsp+r10] }
  Emit(#$BA#$0A#0#0#0);               { edx=10 }
  Emit(#$44#$29#$D2);                 { sub edx,r10d }
  Emit(#$0F#$05);                     { read }
  Emit(#$48#$83#$F8#$FC);             { cmp rax,-EINTR }
  J:=Length(Prefix)+2;Emit(#$0F#$84#0#0#0#0);
  PatchRel32(Prefix,J,LoopAt);
  Emit(#$48#$85#$C0);                 { test rax,rax }
  EmitJumpReject($8E);                { jle: short EOF/other error }
  Emit(#$49#$01#$C2);                 { add r10,rax }
  Emit(#$49#$83#$FA#$0A);             { cmp r10,10 }
  J:=Length(Prefix)+2;Emit(#$0F#$8C#0#0#0#0);
  PatchRel32(Prefix,J,LoopAt);

  ProbeAt:=Length(Prefix);
  Emit(#$31#$C0);                     { read=0, fd=0 }
  Emit(#$31#$FF);
  Emit(#$48#$8D#$74#$24#$0A);         { probe [rsp+10] }
  Emit(#$BA#$01#0#0#0);
  Emit(#$0F#$05);
  Emit(#$48#$83#$F8#$FC);             { EINTR: retry probe }
  J:=Length(Prefix)+2;Emit(#$0F#$84#0#0#0#0);
  PatchRel32(Prefix,J,ProbeAt);
  Emit(#$48#$85#$C0);
  EmitJumpReject($85);                { jne: surplus/other error }
  EmitDecode(0,0);
  EmitDecode(1,5);

  { Sign-extend 24-bit values r8/r9 to signed 32 using SHL 8 / SAR 8.
    Signed 32-bit sum fits ([-2^24,2^24-2]), so comparisons safe. }
  Emit(#$45#$89#$C2);                 { mov r10d,r8d }
  Emit(#$41#$C1#$E2#$08);             { shl r10d,8 }
  Emit(#$41#$C1#$FA#$08);             { sar r10d,8 }
  Emit(#$45#$89#$CB);                 { mov r11d,r9d }
  Emit(#$41#$C1#$E3#$08);             { shl r11d,8 }
  Emit(#$41#$C1#$FB#$08);             { sar r11d,8 }
  Emit(#$45#$01#$DA);                 { add r10d,r11d }
  Emit(#$41#$81#$FA#$FF#$FF#$7F#0); { cmp r10d, 8388607 }
  EmitJumpReject($8F);                { jg: D24->D48 }
  Emit(#$41#$81#$FA#0#0#$80#$FF);    { cmp r10d,-8388608 }
  EmitJumpReject($8C);                { jl: D24->D48 }

  { Convert two dynamic W24 values to the EXACT registers expected
    after the donor's four mov imm32: low16 left/right shl16,
    high8 left/right in edx/ebx. No flag-clobber between ADD and ADC. }
  Emit(#$44#$89#$C0);                 { mov eax,r8d }
  Emit(#$44#$89#$C9);                 { mov ecx,r9d }
  Emit(#$89#$C2);                     { mov edx,eax }
  Emit(#$C1#$EA#$10);                 { shr edx,16 }
  Emit(#$89#$CB);                     { mov ebx,ecx }
  Emit(#$C1#$EB#$10);                 { shr ebx,16 }
  Emit(#$C1#$E0#$10);                 { shl eax,16 }
  Emit(#$C1#$E1#$10);                 { shl ecx,16 }
  JumpAt:=Length(Prefix)+1;
  Emit(#$E9#0#0#0#0);                 { skip 4 donor immediates }
  RejectAt:=Length(Prefix);
  Emit(#$B8#$3C#0#0#0);               { exit(2) }
  Emit(#$BF#$02#0#0#0);
  Emit(#$0F#$05);
  PrefixLen:=Length(Prefix);
  Need((PrefixLen>0) and (PrefixLen<1024) and
       (PrefixLen+Length(Donor)-HeaderBytes+2*T5MByteCount<MaxMachineBytes),
       'machine prelude або decode lookup понад квотою');
  PatchRel32(Prefix,JumpAt,PrefixLen+20);
  for I:=0 to RejectCount-1 do PatchRel32(Prefix,Rejects[I],RejectAt);
  MapStart:=PrefixLen+Length(Donor)-HeaderBytes;
  for I:=0 to LeaCount-1 do
    PatchRel32(Prefix,Leas[I],MapStart+LeaKinds[I]*T5MByteCount);

  SourceBytes:=Copy(Donor,HeaderBytes+1,Length(Donor)-HeaderBytes);
  Result:=Copy(Donor,1,HeaderBytes)+Prefix+SourceBytes+Map5+Map4;
  PatchElfSize(Result,96,Length(Result));
  PatchElfSize(Result,104,Length(Result));
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)) and
       (Copy(Result,HeaderBytes+PrefixLen+1,Length(SourceBytes))=SourceBytes) and
       (Copy(Result,HeaderBytes+PrefixLen+Length(SourceBytes)+1,
          T5MByteCount)=Map5),
       'порушено байтову точність donor/ELF64');
end;
end.
