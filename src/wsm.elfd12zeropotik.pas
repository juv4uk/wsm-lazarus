{ G6.97: pinned SENS Contract12 D5:01000; лише x86-64 ISA, не закон.
  Фізичний stdin — один canonical packed D12 W12 (три байти).
  Читання до EOF; відповіді D1 без часткового stdout; no English dispatch.
  RawByteString: managed FPC owned, вихід — ELF64 PIE; стек — host. }
unit wsm.elfd12zeropotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12ZeroStreamError=class(Exception);
function BuildD12ZeroStreamELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120; MaxCode=4096; Bad=255;
type TBranch=array of SizeInt;
     TLea=record At:SizeInt; Kind:Byte end;
     TLeas=array of TLea;
procedure Need(Yes:Boolean;const Why:String);
begin if not Yes then raise ED12ZeroStreamError.Create(Why) end;

{ Питання: 1) Чому потрібен EOF? 2) Чому W12 не дає домен?
  3) Як відхиляється хибний T5M padding?
  4) Де виконується машинний TEST/SETE? 5) Чому немає partial stdout? }
function BuildD12ZeroStreamELF:RawByteString;
var Code,Dec5,Dec2,Answer,Diagnostic,Encoded,Bits:RawByteString;
    Words:TExactWords; Rejects:TBranch; Leas:TLeas;
    LoopAt,FinishAt,RejectAt,JmpRead,Total,CodeEnd,Data5,Data2,
    DataAnswer,DataDiagnostic,I,J,At,Target:SizeInt;
    Geometry:TELFGeometry;
  procedure Emit(const Bytes:RawByteString);
  begin
    Need((Length(Bytes)>0) and (Length(Code)+Length(Bytes)<MaxCode),
      'перевищено машинний бюджет');
    Code:=Code+Bytes;
  end;
  procedure Emit32(X:LongWord);
  var K:SizeInt;
  begin for K:=0 to 3 do begin Emit(AnsiChar(X and $FF));X:=X shr 8 end end;
  procedure Patch32(Position:SizeInt;Value:LongInt);
  var K:SizeInt; U:LongWord;
  begin
    Need((Position>=0) and (Position+4<=Length(Code)),
      'машинне зміщення поза кодом');
    U:=LongWord(Value);
    for K:=0 to 3 do begin
      Code[Position+K+1]:=AnsiChar(U and $FF);U:=U shr 8;
    end;
  end;
  procedure RejectOn(Condition:AnsiChar);
  var N:SizeInt;
  begin
    N:=Length(Rejects);SetLength(Rejects,N+1);
    Rejects[N]:=Length(Code);
    Emit(#$0F+Condition+#0#0#0#0);
  end;
  procedure LeaTable(Kind:Byte);
  var N:SizeInt;
  begin
    N:=Length(Leas);SetLength(Leas,N+1);
    Leas[N].At:=Length(Code);Leas[N].Kind:=Kind;
    Emit(#$48#$8D#$35#0#0#0#0);
  end;
  function BitWord(Value,Width:SizeInt):RawByteString;
  var K:SizeInt;
  begin
    SetLength(Result,Width);
    for K:=1 to Width do
      if (Value and (1 shl (Width-K)))<>0 then Result[K]:='1'
      else Result[K]:='0';
  end;
  procedure Put(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Offset>=0) and (Count>0) and (Count<=8) and
      (Offset+Count<=Length(Result)),'поле ELF поза образом');
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Value and $FF);Value:=Value shr 8
    end;
  end;
  procedure DecodeChunk(Offset:Byte;Kind:Byte);
  begin
    if Offset=0 then Emit(#$0F#$B6#$04#$24)
    else Emit(#$0F#$B6#$44#$24+AnsiChar(Offset));
    LeaTable(Kind);
    Emit(#$0F#$B6#$04#$06);
    Emit(#$3D#$FF#0#0#0);
    RejectOn(#$84);
    Emit(#$41#$09#$C0);
  end;
begin
  Result:='';Code:='';SetLength(Rejects,0);SetLength(Leas,0);
  Dec5:=StringOfChar(AnsiChar(Bad),256);
  Dec2:=StringOfChar(AnsiChar(Bad),256);
  SetLength(Words,1);
  for I:=0 to 31 do begin
    Bits:=BitWord(I,5);Words[0]:=Bits;Encoded:=EncodeT5M(Words);
    Need(Length(Encoded)=1,'неочікуваний T5M W5');
    Need(Ord(Dec5[Ord(Encoded[1])+1])=Bad,'колізія T5M W5');
    Dec5[Ord(Encoded[1])+1]:=AnsiChar(I);
  end;
  for I:=0 to 3 do begin
    Bits:=BitWord(I,2);Words[0]:=Bits;Encoded:=EncodeT5M(Words);
    Need(Length(Encoded)=1,'неочікуваний T5M W2');
    Need(Ord(Dec2[Ord(Encoded[1])+1])=Bad,'колізія T5M W2');
    Dec2[Ord(Encoded[1])+1]:=AnsiChar(I);
  end;
  Words[0]:='0';Answer:=EncodeT5M(Words);
  Words[0]:='1';Answer:=Answer+EncodeT5M(Words);
  Need(Length(Answer)=2,'неочікуване exact D1 пакування');
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString('Д12-ПОТІК-ВІДМОВА: некоректне фізичне слово'+#10)));
  Emit(#$48#$83#$EC#$10);
  Emit(#$45#$31#$E4);
  LoopAt:=Length(Code);
  Emit(#$31#$C0#$31#$FF);
  Emit(#$4A#$8D#$34#$24);
  Emit(#$BA#$04#0#0#0);
  Emit(#$44#$29#$E2);
  Emit(#$0F#$05);
  Emit(#$48#$85#$C0);
  RejectOn(#$88);
  RejectOn(#$84);
  FinishAt:=Rejects[High(Rejects)];SetLength(Rejects,Length(Rejects)-1);
  Emit(#$49#$01#$C4);
  Emit(#$49#$83#$FC#$04);
  RejectOn(#$83);
  JmpRead:=Length(Code);Emit(#$E9#0#0#0#0);
  At:=Length(Code);
  Patch32(FinishAt+2,LongInt(At-(FinishAt+6)));
  Emit(#$41#$83#$FC#$03);
  RejectOn(#$85);
  Emit(#$45#$31#$C0);
  DecodeChunk(0,0);DecodeChunk(1,0);DecodeChunk(2,1);
  Emit(#$45#$85#$C0);
  Emit(#$0F#$94#$C0);
  Emit(#$0F#$B6#$C0);
  LeaTable(2);
  Emit(#$8A#$14#$06);
  Emit(#$88#$14#$24);
  Emit(#$B8#$01#0#0#0#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6#$BA#$01#0#0#0#$0F#$05);
  Emit(#$B8#$3C#0#0#0#$31#$FF#$0F#$05);
  RejectAt:=Length(Code);
  Emit(#$B8#$01#0#0#0#$BF#$02#0#0#0);
  LeaTable(3);
  Emit(#$BA);Emit32(LongWord(Length(Diagnostic)));
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0#$BF#$02#0#0#0#$0F#$05);
  CodeEnd:=Length(Code);
  Patch32(JmpRead+1,LongInt(LoopAt-(JmpRead+5)));
  for I:=0 to High(Rejects) do
    Patch32(Rejects[I]+2,LongInt(RejectAt-(Rejects[I]+6)));
  Data5:=CodeEnd; Data2:=Data5+Length(Dec5);
  DataAnswer:=Data2+Length(Dec2);
  DataDiagnostic:=DataAnswer+Length(Answer);
  for I:=0 to High(Leas) do begin
    case Leas[I].Kind of
      0:Target:=Data5;
      1:Target:=Data2;
      2:Target:=DataAnswer;
      3:Target:=DataDiagnostic;
    else raise ED12ZeroStreamError.Create('невідома host T5M таблиця') end;
    Patch32(Leas[I].At+3,LongInt(Target-(Leas[I].At+7)));
  end;
  Total:=HeaderBytes+CodeEnd+Length(Dec5)+Length(Dec2)+
    Length(Answer)+Length(Diagnostic);
  Need((Total>HeaderBytes) and (Total<8192),'ELF поза фізичною квотою');
  SetLength(Result,Total);FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  J:=HeaderBytes+Length(Code);
  for I:=1 to Length(Dec5) do Result[J+I]:=Dec5[I];
  Inc(J,Length(Dec5));
  for I:=1 to Length(Dec2) do Result[J+I]:=Dec2[I];
  Inc(J,Length(Dec2));
  for I:=1 to Length(Answer) do Result[J+I]:=Answer[I];
  Inc(J,Length(Answer));
  for I:=1 to Length(Diagnostic) do Result[J+I]:=Diagnostic[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Total) and
    (Geometry.Entry=HeaderBytes),'не підтверджено ELF64 PIE');
end;
end.
