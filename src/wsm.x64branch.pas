{ G6.97 — лише host-механіка x86-64 відносних переходів для lowering.
  Координата fixup — 0-based BYTE offset першого байта signed disp32
  у керованому Code.Bytes; Target — 0-based BYTE offset реальної
  інструкції. Не SENS Dn, не назви функцій, не реєстр законів.
  За відмови байти коду не змінюються; квота 256 host-байтів.

  Запитання:
  1) Чому rel32 відраховується від кінця інструкції?
  2) Чому розташування гілки не визначає закон SENS?
  3) Як захищено буфер від часткової підстановки?
  4) Навіщо заборонений нульовий (непотрібний) перехід?
  5) Чому fixup не можна застосувати двічі? }
unit wsm.x64branch;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64Branch=(xbJump,xbZero);
procedure X64EmitBranch(var Code:TX64Code;Kind:TX64Branch;
  out DispOffset:SizeInt);
procedure X64PatchBranch(var Code:TX64Code;Kind:TX64Branch;
  DispOffset,TargetOffset:SizeInt);
implementation
const MaxCodeBytes=256;
procedure Need(Good:Boolean;const Reason:String);
begin
  if not Good then raise EX64CodeError.Create(Reason);
end;
procedure X64EmitBranch(var Code:TX64Code;Kind:TX64Branch;
  out DispOffset:SizeInt);
var Instruction:RawByteString; Existing:SizeInt;
begin
  DispOffset:=-1;
  case Kind of
    xbJump:Instruction:=#$E9#0#0#0#0;
    xbZero:Instruction:=#$0F#$84#0#0#0#0;
    else raise EX64CodeError.Create('невідомий host тип переходу');
  end;
  Existing:=Length(Code.Bytes);
  Need(Existing<=MaxCodeBytes-Length(Instruction),
       'перехід перевищує квоту 256 байтів');
  { Одне атомарне дописування; після успіху існує фізичний fixup. }
  Code.Bytes:=Code.Bytes+Instruction;
  DispOffset:=Existing+Length(Instruction)-4;
end;
procedure X64PatchBranch(var Code:TX64Code;Kind:TX64Branch;
  DispOffset,TargetOffset:SizeInt);
var N,I:SizeInt; Distance:Int64; Encoded:QWord; Candidate:RawByteString;
begin
  N:=Length(Code.Bytes);
  Need((N>0) and (N<=MaxCodeBytes) and
       (DispOffset>=0) and (DispOffset<=N-4),
       'fixup поза машинним кодом');
  case Kind of
    xbJump:Need((DispOffset>=1) and
       (Copy(Code.Bytes,DispOffset,1)=#$E9),
       'fixup не є JMP rel32');
    xbZero:Need((DispOffset>=2) and
       (Copy(Code.Bytes,DispOffset-1,2)=#$0F#$84),
       'fixup не є JZ rel32');
    else raise EX64CodeError.Create('невідомий host тип переходу');
  end;
  Need(Copy(Code.Bytes,DispOffset+1,4)=#0#0#0#0,
       'переходу вже підставлено зміщення');
  Need((TargetOffset>=0) and (TargetOffset<N),
       'ціль переходу поза машинним кодом');
  Distance:=Int64(TargetOffset)-Int64(DispOffset+4);
  Need((Distance<>0) and
       (Distance>=Low(LongInt)) and (Distance<=High(LongInt)),
       'нульовий або переповнений signed rel32 перехід');
  Candidate:=Copy(Code.Bytes,1,N);
  Encoded:=QWord(Distance) and $FFFFFFFF;
  for I:=0 to 3 do begin
    Candidate[DispOffset+I+1]:=AnsiChar(Byte(Encoded and $FF));
    Encoded:=Encoded shr 8;
  end;
  Code.Bytes:=Candidate;
end;
end.
