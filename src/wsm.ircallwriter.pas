{ G6.107 — фізичний ExactIR D3:101(D1,D1) через shared CALL/RET.
  Семантичний admission здійснює ВИКЛЮЧНО раніше перевірений
  LowerPinnedD3Eq; ніякого нового Pascal SENS register або D7-name
  dispatch. EDI/ESI=machine immediate, EAX=runtime D1 bit,
  CALLEE CMP/SETE/MOVZX/RET, caller записує packed T5M.
  Borrowed Physical/AuthorityRoot, stack Lowered, owned TX64Code/ELF.
  Збої fail closed до побудови ELF; host RSP 16-byte aligned at CALL,
  8-byte return pointer on callee entry. Не full APPLY/recursive runtime.
  Питання: 1) Чому output D1:T5M із codec, не ASCII?
  2) Чим CALL ABI відрізняється від SENS callable domain?
  3) Чому ELF PIE зберігає rel32 під ASLR?
  4) Чому результат не обчислюємо у Pascal?
  5) Чому ELF тест треба доповнити pinned SENS oracle? }
unit wsm.ircallwriter;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRCallWriterError=class(Exception);
function BuildPhysicalD3CallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.t5m,wsm.eqir,wsm.x64code,wsm.x64call,wsm.elfgeometry;

const
  HeaderBytes=120;
  MaxBytes=256;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRCallWriterError.Create(Why) end;

procedure Emit(var C:TX64Code;const Data:RawByteString);
begin
  Need((Length(Data)>0) and
       (Length(Data)<=MaxBytes) and
       (Length(C.Bytes)<=MaxBytes-Length(Data)),
       'CALL emitter перевищує квоту 256');
  C.Bytes:=C.Bytes+Data;
end;

procedure PutLE(var Image:RawByteString;Off:SizeInt;
  Value:QWord;Width:SizeInt);
var J:SizeInt;
begin
  Need((Off>=0) and (Width>=1) and (Width<=8) and
       (Off<=Length(Image)-Width),'поле ELF поза образом');
  for J:=0 to Width-1 do begin
    Image[Off+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function EmitELF(const Bits:TLoweredD3Eq):RawByteString;
var C:TX64Code;Words:TExactWords;
  Zero,One:RawByteString;
  Delta,CallFix,FunctionAt,I,Total:SizeInt;
  Geom:TELFGeometry;
begin
  Result:='';
  Need((Bits.LeftBit<=1) and (Bits.RightBit<=1),
       'LowerPinnedD3Eq не дав точного D1');
  SetLength(Words,1);
  Words[0]:='0';Zero:=EncodeT5M(Words);
  Words[0]:='1';One:=EncodeT5M(Words);
  Need((Length(Zero)=1) and (Length(One)=1) and
       (Ord(One[1])>Ord(Zero[1])) and
       (Ord(One[1])-Ord(Zero[1])<=127),
       'непідтверджені фізичні байти D1 у pinned codec');
  Delta:=Ord(One[1])-Ord(Zero[1]);
  X64Reset(C);
  X64MovImm32(C,xrDI,Bits.LeftBit);
  X64MovImm32(C,xrSI,Bits.RightBit);
  Emit(C,#$48#$83#$E4#$F0); { AND RSP,-16 }
  X64EmitCall(C,CallFix);
  { Значення EAX=0/1 повертає ТІЛЬКИ виконаний CALL. }
  Emit(C,#$6B#$C0+AnsiChar(Delta)); { IMUL EAX,EAX,delta }
  Emit(C,#$83#$C0+Zero[1]);        { ADD EAX,physical D1:0 }
  X64SubRsp8(C,8);
  Emit(C,#$88#$04#$24);             { MOV [RSP],AL }
  X64MovImm32(C,xrAX,1);          { write }
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60);         { exit(0) }
  X64XorEDI(C);
  X64Syscall(C);

  FunctionAt:=Length(C.Bytes);
  Emit(C,#$39#$F7);               { CMP EDI,ESI }
  X64SetEAL(C);
  X64MovzxEAXAL(C);
  X64EmitReturn(C);
  X64PatchCall(C,CallFix,FunctionAt);
  Need((Length(C.Bytes)>FunctionAt) and (Length(C.Bytes)<=MaxBytes),
       'Підпрограма має бути у тому самому bounded ELF');
  Total:=HeaderBytes+Length(C.Bytes);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,3,2);PutLE(Result,18,62,2);PutLE(Result,20,1,4);
  PutLE(Result,24,HeaderBytes,8);PutLE(Result,32,64,8);
  PutLE(Result,52,64,2);PutLE(Result,54,56,2);PutLE(Result,56,1,2);
  PutLE(Result,64,1,4);PutLE(Result,68,5,4);
  PutLE(Result,80,0,8);PutLE(Result,88,0,8);
  PutLE(Result,96,Total,8);PutLE(Result,104,Total,8);PutLE(Result,112,$1000,8);
  for I:=1 to Length(C.Bytes) do Result[HeaderBytes+I]:=C.Bytes[I];
  VerifySENSELF64(Result,Geom);
  Need((Geom.Kind=3) and (Geom.FileBytes=Total) and
       (Geom.MachineBytes=Length(C.Bytes)),
       'Непідтверджена ELF64 PIE геометрія');
end;

function BuildPhysicalD3CallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var Op:TLoweredD3Eq;
begin
  Result:='';
  try
    LowerPinnedD3Eq(Physical,AuthorityRoot,Op);
    Result:=EmitELF(Op);
  except
    on E:EIRCallWriterError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRCallWriterError.Create('Фізичний CALL відхилено: '+E.Message)
    end;
  end;
end;
end.
