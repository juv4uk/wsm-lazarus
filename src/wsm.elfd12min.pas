{ G6.84 — machine lowering для pinned D6:110101 «найменше».
  Ключ SENS визначає тільки pinned lib/domains/d6.lisp. Цей unit
  реалізує вузький host AOT шлях двох signed D12 T5M атомів.
  Реальна машинна відповідь обчислюється CMP/CMOVG у Linux ELF64;
  це НЕ загальний SENS-компілятор, не кодбук і не Lisp dispatch. }
unit wsm.elfd12min;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12MinELFError=class(Exception);
function BuildD12MinELF(const LPhysical,RPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;
const HeaderBytes=120;

procedure Need(Allowed:Boolean;const Reason:String);
begin if not Allowed then raise ED12MinELFError.Create(Reason) end;

{ ExactBits — borrowed 12-бітне слово після pinned ReadNumericPhysical.
  LongInt — transient host immediate, не semantic D12 identity. Sign
  extension не відкидає провідних бітів. Питання: (1) чому є явний
  D12 admission? (2) чому Int32 не визначає домен? (3) де знак? }
function Immediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Need(Length(Bits)=12,'потрібне саме фізичне D12 слово');
  V:=0;
  for I:=1 to Length(Bits) do begin
    Need(Bits[I] in ['0','1'],'не двійковий D12 атом');
    V:=2*V+(Ord(Bits[I])-Ord('0'));
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

{ Таблиця — лише механічне представлення canonical packed T5M.
  0..31 / 0..3 індексуються бітами CPU результату, а не D7 назвою.
  Результат: один owned байт із pinned wsm.t5m.EncodeT5M;
  transient FPC managed words вивільняються автоматично.
  Питання: (1) хто визначає T5M? (2) чому bits зберігаються всі?
  (3) чим lookup відрізняється від семантичного dispatch? }
function EncodedChunk(Index,Width:SizeInt):AnsiChar;
var Bits,Encoded:RawByteString;Words:TExactWords;I:SizeInt;
begin
  Need((Width=5) or (Width=2),'невірна ширина T5M частини');
  Need((Index>=0) and (Index<(1 shl Width)),'індекс T5M поза межами');
  SetLength(Bits,Width);
  for I:=1 to Width do
    if (Index and (1 shl (Width-I)))<>0 then Bits[I]:='1'
    else Bits[I]:='0';
  SetLength(Words,1);Words[0]:=Bits;
  Encoded:=EncodeT5M(Words);
  Need(Length(Encoded)=1,'відсутній точний packed T5M байт');
  Result:=Encoded[1];
end;

{ Входи — borrowed T5M файли двох окремих explicit D12 signed атомів.
  Повертає managed owned ELF64 PIE (ET_DYN), байти ще не опубліковані.
  Машина обчислює min: MOV eax,a; MOV ecx,b; CMP eax,ecx;
  CMOVG eax,ecx. Вивід: AND eax,4095 → 3-байтний D12 T5M,
  упакований через наші таблиці, отримані з чинного EncodeT5M.
  Pinned SENS law не визначається CPU flags; CMOVG є target mechanism.
  Питання: (1) чому signed CMOVG? (2) що коли a=b?
  (3) чому 3 байти, а не 12? (4) де verify ELF?
  (5) чому не допускаємо D24 автоматично? }
function BuildD12MinELF(const LPhysical,RPhysical:RawByteString):RawByteString;
var A,B:TExplicitNumeric;IA,IB:LongInt;
    Table5,Table2,Code:RawByteString;G:TELFGeometry;
    FirstLea,LastLea,CodeBytes,I:SizeInt;

  procedure Emit(const Bytes:RawByteString);
  begin
    Code:=Code+Bytes;
    Need(Length(Code)<4096,'завеликий машинний шлях');
  end;

  procedure Emit32(V:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin Emit(AnsiChar(V and 255));V:=V shr 8 end;
  end;

  procedure Patch32(Pos0:SizeInt;V:LongWord);
  var K:SizeInt;
  begin
    Need((Pos0>=0) and (Pos0<=Length(Code)-4),'rel32 за межами коду');
    for K:=0 to 3 do begin
      Code[Pos0+K+1]:=AnsiChar(V and 255);
      V:=V shr 8;
    end;
  end;

  procedure Put(Offset:SizeInt;V:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Offset>=0) and (Count>0) and (Count<=8) and
      (Offset<=Length(Result)-Count),'ELF header поле за межами образу');
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(V and 255));
      V:=V shr 8;
    end;
  end;
begin
  Result:='';
  A:=ReadNumericPhysical(LPhysical,12);
  B:=ReadNumericPhysical(RPhysical,12);
  IA:=Immediate12(A.ExactBits);IB:=Immediate12(B.ExactBits);
  Table5:='';Table2:='';
  for I:=0 to 31 do Table5:=Table5+EncodedChunk(I,5);
  for I:=0 to 3 do Table2:=Table2+EncodedChunk(I,2);
  Need((Length(Table5)=32) and (Length(Table2)=4),'неповні фізичні таблиці');

  Code:='';
  Emit(#$B8);Emit32(LongWord(IA));               { mov eax,a }
  Emit(#$B9);Emit32(LongWord(IB));               { mov ecx,b }
  Emit(#$39#$C8);                               { cmp eax,ecx }
  Emit(#$0F#$4F#$C1);                           { cmovg eax,ecx (signed min) }
  Emit(#$25#$FF#$0F#0#0);                       { and eax,0xFFF: D12 bits }
  Emit(#$48#$83#$EC#$10);                       { stack 3-byte buffer }
  Emit(#$89#$C1#$C1#$E9#$07#$83#$E1#$1F);     { ecx=(eax>>7)&31 }
  FirstLea:=Length(Code);
  Emit(#$48#$8D#$35#0#0#0#0);                   { lea rsi,[rip+T5M5] }
  Emit(#$8A#$14#$0E#$88#$14#$24);              { buffer[0]=table5[ecx] }
  Emit(#$89#$C1#$C1#$E9#$02#$83#$E1#$1F);     { ecx=(eax>>2)&31 }
  Emit(#$8A#$14#$0E#$88#$54#$24#$01);         { buffer[1]=table5[ecx] }
  Emit(#$89#$C1#$83#$E1#$03);                   { ecx=eax&3 }
  LastLea:=Length(Code);
  Emit(#$48#$8D#$3D#0#0#0#0);                   { lea rdi,[rip+T5M2] }
  Emit(#$8A#$14#$0F#$88#$54#$24#$02);         { buffer[2]=table2[ecx] }
  Emit(#$B8#$01#0#0#0);                         { write(1,rsp,3) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$03#0#0#0);
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);                         { exit(0) }
  Emit(#$31#$FF#$0F#$05);
  CodeBytes:=Length(Code);
  Patch32(FirstLea+3,LongWord(CodeBytes-(FirstLea+7)));
  Patch32(LastLea+3,LongWord(CodeBytes+32-(LastLea+7)));

  SetLength(Result,HeaderBytes+CodeBytes+Length(Table5)+Length(Table2));
  FillChar(Result[1],Length(Result),0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to Length(Table5) do Result[HeaderBytes+CodeBytes+I]:=Table5[I];
  for I:=1 to Length(Table2) do
    Result[HeaderBytes+CodeBytes+Length(Table5)+I]:=Table2[I];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Result)),
    'не пройдено перевірку ELF64 PIE геометрії');
end;
end.
