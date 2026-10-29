{ G6.78. SENS D5:11011, signed D12 → D1 through x86-64 CMP/SETG.
  Language law is pinned juv4uk/sens Contract12, not this FPC code. }
unit wsm.elfd12greater;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12GreaterELFError=class(Exception);
function BuildD12GreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;
const HeaderBytes=120;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12GreaterELFError.Create(Why) end;
{ Bits borrowed exact W12, returned LongInt only for x86 immediate.
  1) Why sign extend? 2) Why width 12? 3) Who owns Bits?
  4) Why must numeric admission precede this conversion? }
function Immediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Need(Length(Bits)=12,'потрібне точне D12');
  V:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'пошкоджено двійковий D12');
    V:=V*2+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

{ Inputs borrowed two canonical packed D12 T5M atoms, output owned RawByteString
  ELF64 ET_DYN PIE. Machine computes signed relation, not Pascal.
  D1 transport zero/one derives from existing EncodeT5M, no new registry.
  Linux owns RW stack; binary owns RX code; caller owns managed ELF string.
  Questions: Why SETG instead of SETA? Why D1 vs host Boolean?
  Why is ELF geometry insufficient as semantic proof? Why no D7 dispatch?
  Which instructions execute the comparison? }
function BuildD12GreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var L,R:TExplicitNumeric;A,B:LongInt;W:TExactWords;
    Z,O,Code:RawByteString;Delta:LongInt;I:SizeInt;Geom:TELFGeometry;
  procedure Emit(const S:RawByteString);
  begin Code:=Code+S;Need(Length(Code)<512,'завеликий машинний код') end;
  procedure Emit32(V:LongWord);
  var J:Integer;
  begin
    for J:=0 to 3 do begin Emit(AnsiChar(V and $FF));V:=V shr 8 end
  end;
  procedure Put(Off:SizeInt;V:QWord;N:Integer);
  var J:Integer;
  begin
    Need((Off>=0) and (N>=1) and (N<=8) and (Off<=Length(Result)-N),
      'неприпустиме поле ELF64');
    for J:=0 to N-1 do begin
      Result[Off+J+1]:=AnsiChar(V and $FF);V:=V shr 8
    end
  end;
begin
  Result:='';
  L:=ReadNumericPhysical(LeftPhysical,12);
  R:=ReadNumericPhysical(RightPhysical,12);
  A:=Immediate12(L.ExactBits);B:=Immediate12(R.ExactBits);
  SetLength(W,1);
  W[0]:='0';Z:=EncodeT5M(W);
  W[0]:='1';O:=EncodeT5M(W);
  Need((Length(Z)=1) and (Length(O)=1),
    'D1 physical transport має один байт');
  Delta:=Ord(O[1])-Ord(Z[1]);
  Need((Delta>0) and (Delta<=127),'невідома різниця D1 T5M');
  Code:='';
  Emit(#$B8);Emit32(LongWord(A)); { mov eax,left }
  Emit(#$3D);Emit32(LongWord(B)); { cmp eax,right }
  Emit(#$0F#$9F#$C0);            { setg al, signed }
  Emit(#$0F#$B6#$C0);            { movzx eax,al }
  Emit(#$6B#$C0);Emit(AnsiChar(Delta)); { imul eax,delta }
  Emit(#$05);Emit32(Byte(Z[1]));{ add eax,canonical D1 zero }
  Emit(#$48#$83#$EC#$08);       { sub rsp,8 }
  Emit(#$88#$04#$24);           { mov [rsp],al }
  Emit(#$B8#$01#0#0#0);         { write }
  Emit(#$BF#$01#0#0#0);         { stdout }
  Emit(#$48#$89#$E6);          { rsi=rsp }
  Emit(#$BA#$01#0#0#0);         { count=1 }
  Emit(#$0F#$05);               { syscall }
  Emit(#$B8#$3C#0#0#0);         { exit }
  Emit(#$31#$FF#$0F#$05);
  Need((Length(Code)>40) and (Length(Code)<128),
    'неправильний машинний код');
  SetLength(Result,HeaderBytes+Length(Code));
  FillChar(Result[1],Length(Result),0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  VerifySENSELF64(Result,Geom);
  Need((Geom.Kind=3) and (Geom.MachineBytes=Length(Code)),
    'відхилена геометрія ELF64 PIE');
end;
end.