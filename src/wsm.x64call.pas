{ G6.107 — лише host механіка x86-64 CALL rel32 / RET, не закон SENS.
  dispOffset: 0-based позиція першого байта signed disp32,
  targetOffset: 0-based позиція ПЕРШОГО байта цільової інструкції.
  Обидва належать до owned керованого TX64Code.Bytes (<=256).
  Всі відмови зберігають байти попереднього коду й не повертають
  фіктивного fixup; patch виконується copy-on-write.
  CALL створює машинну адресу повернення на стеку. Ні цей кодер,
  ні RET самі не доводять вирівнювання ABI, callable SENS чи GC.
  Питання: 1) Чому rel32 відлічують від кінця CALL?
  2) Чому host CALL не визначає мовний закон D3?
  3) Чому fixup має бути ще нульовим?
  4) Хто відповідає за RSP та lifetime кадру?
  5) Чому перевіряємо точні інструкційні межі? }
unit wsm.x64call;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64EmitCall(var Code:TX64Code;out DispOffset:SizeInt);
procedure X64PatchCall(var Code:TX64Code;DispOffset,TargetOffset:SizeInt);
procedure X64EmitReturn(var Code:TX64Code);
implementation
const MaxBytes=256;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EX64CodeError.Create(Why)
end;
procedure X64EmitCall(var Code:TX64Code;out DispOffset:SizeInt);
var Existing:SizeInt;
begin
  DispOffset:=-1;
  Existing:=Length(Code.Bytes);
  Need(Existing<=MaxBytes-5,'CALL rel32 перевищує квоту 256 байтів');
  Code.Bytes:=Code.Bytes+#$E8#0#0#0#0;
  DispOffset:=Existing+1;
end;
procedure X64PatchCall(var Code:TX64Code;DispOffset,TargetOffset:SizeInt);
var N,I:SizeInt; Delta:Int64; U:QWord; Candidate:RawByteString;
begin
  N:=Length(Code.Bytes);
  Need((N<=MaxBytes) and (DispOffset>=1) and
       (DispOffset<=N-4),'CALL: позиція fixup поза кодом');
  Need(Copy(Code.Bytes,DispOffset,1)=#$E8,
       'CALL: немає точного host opcode E8 перед disp32');
  Need(Copy(Code.Bytes,DispOffset+1,4)=#0#0#0#0,
       'CALL: fixup уже застосовано або початкові байти не нулі');
  Need((TargetOffset>=0) and (TargetOffset<N),
       'CALL: ціль поза виконуваним буфером');
  Delta:=Int64(TargetOffset)-Int64(DispOffset+4);
  Need((Delta<>0) and (Delta>=Low(LongInt)) and
       (Delta<=High(LongInt)),
       'CALL: нульове або непредставне signed rel32');
  Candidate:=Copy(Code.Bytes,1,N);
  U:=QWord(Delta) and $FFFFFFFF;
  for I:=0 to 3 do begin
    Candidate[DispOffset+I+1]:=AnsiChar(Byte(U and $FF));
    U:=U shr 8
  end;
  Code.Bytes:=Candidate;
end;
procedure X64EmitReturn(var Code:TX64Code);
begin
  Need(Length(Code.Bytes)<MaxBytes,
       'RET перевищує квоту 256 байтів');
  Code.Bytes:=Code.Bytes+#$C3;
end;
end.
