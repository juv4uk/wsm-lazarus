{ G6.121 — механічний x86-64 префікс read-exact із EOF для вже
  перевіреного ELF64 PIE донора (два ОКРЕМІ packed D12 W12, 6 host байтів).
  Ні домен, ні SENS закон тут не визначаються, це тільки Linux I/O ABI.
  Донорський код і всі RIP-rel32 таблиці зміщуються РАЗОМ без patch. }
unit wsm.x64frameio;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EFrameIO=class(Exception);
function WrapExactSixByteFrame(const Original:RawByteString):RawByteString;
implementation
uses wsm.elfgeometry;
const HeaderBytes=120; OriginalReadBytes=28; ReadLimit=6;

procedure Require(Yes:Boolean;const Why:String);
begin if not Yes then raise EFrameIO.Create(Why) end;

{ Original: borrowed immutable ELF64 from verified donor, exact read
  prologue expected at entry 120; Result: owned copy-on-write ELF64.
  The prefixed code runs BEFORE the unmodified donor, reads 6 bytes
  through repeated Linux read(0) calls and probes ONE MORE byte until
  EOF, then jumps over the donor's old single-read prologue.
  On short EOF, extra byte or syscall errors OTHER than -EINTR, jumps
  directly to donor's unchanged error handler. On -EINTR retries only
  the interrupted syscall, without moving buffer or changing r10.
  Adds no partial stdout.
  All original code, jcc and RIP lookup tables shift together; since
  every machine reference is rel32, their existing distances remain
  bit-identical. Only PT_LOAD file/mem sizes grow; entry stays at 120.
  Limitations: Linux x86-64, host stdin may block until EOF, only EINTR
  is retried; EIO/EAGAIN and all other errors fail closed.
  Exact original donor prologue is mandatory.

  1) Чому short read сам по собі ще не недійсний фізичний D12?
  2) Чому EOF необхідний для відмови від зайвого сьомого байта?
  3) Чому незмінні внутрішні RIP-rel32 після спільного зсуву?
  4) Чому невідомий донорський машинний шаблон відхиляємо?
  5) Чому frame-retry не змінює r10, а probe-retry не чіпає frame?
  6) Хто володіє Prefix та Result, де перевірено ELF64 геометрію? }
function WrapExactSixByteFrame(const Original:RawByteString):RawByteString;
var
  Prefix:RawByteString;
  G:TELFGeometry;Disp:LongWord;
  I,RejectRelative,LoopAt,FrameRetryAt,TooShortAt,RepeatAt,
  ProbeAt,ProbeRetryAt,TooLongAt,DecodeAt,NewLen:SizeInt;

  procedure Add(const Bytes:RawByteString);
  begin
    Require((Length(Bytes)>0) and (Length(Prefix)+Length(Bytes)<256),
      'перевищено машинну квоту bounded read');
    Prefix:=Prefix+Bytes;
  end;

  { At is ZERO-based starting offset of signed little-endian rel32,
    target is ZERO-based entry-relative address, including prefix. }
  procedure PatchRel32(At,Target:SizeInt);
  var D:Int64;U:LongWord;K:SizeInt;
  begin
    D:=Int64(Target)-(Int64(At)+4);
    Require((D>=Low(LongInt)) and (D<=High(LongInt)) and
      (At>=0) and (At+4<=Length(Prefix)),
      'branch rel32 поза кодом або неможливий');
    U:=LongWord(LongInt(D));
    for K:=0 to 3 do begin
      Prefix[At+K+1]:=AnsiChar(Byte(U and $FF));
      U:=U shr 8;
    end;
  end;

  procedure PutQWord(var Image:RawByteString;At:SizeInt;Value:QWord);
  var K:SizeInt;
  begin
    Require((At>=0) and (At+8<=Length(Image)),
      'машинний ELF64 заголовок поза образом');
    for K:=0 to 7 do begin
      Image[At+K+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  VerifySENSELF64(Original,G);
  Require((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Original)) and (Length(Original)<8192),
    'донор не має точної ELF64 PIE геометрії');
  Require((Copy(Original,HeaderBytes+1,22)=
       #$48#$83#$EC#$20+#$31#$C0+#$31#$FF+#$48#$89#$E6+
       #$BA#$07#0#0#0+#$0F#$05+#$48#$83#$F8#$06) and
       (Copy(Original,HeaderBytes+23,2)=#$0F#$85),
    'донор не має раніше перевіреного Linux read(0,rsp,7) прологу');
  Disp:=0;
  for I:=0 to 3 do
    Disp:=Disp or (LongWord(Byte(Original[HeaderBytes+24+I+1])) shl (8*I));
  Require(Disp<=4096,'неочікуваний відносний перехід донора');
  RejectRelative:=OriginalReadBytes+SizeInt(Disp);
  Require((RejectRelative>OriginalReadBytes) and
    (HeaderBytes+RejectRelative+16<Length(Original)) and
    (Copy(Original,HeaderBytes+RejectRelative+1,5)=#$B8#$01#0#0#0),
    'машинна гілка відмови донора не підтверджена');
  Prefix:='';
  Add(#$48#$83#$EC#$20);         { sub rsp,32; frame buffer }
  Add(#$45#$31#$D2);             { xor r10d,r10d; received=0 }
  LoopAt:=Length(Prefix);
  Add(#$31#$C0);                 { read syscall=0 }
  Add(#$31#$FF);                 { fd stdin=0 }
  Add(#$48#$89#$E6);             { mov rsi,rsp }
  Add(#$4C#$01#$D6);             { add rsi,r10 (current fill) }
  Add(#$BA#$06#0#0#0);          { edx=6 }
  Add(#$44#$29#$D2);             { sub edx,r10d; bytes remaining }
  Add(#$0F#$05);                 { syscall read }
  Add(#$48#$83#$F8#$FC);         { cmp rax,-EINTR (Linux errno 4) }
  Add(#$0F#$84#0#0#0#0);         { je retry same unfilled frame }
  FrameRetryAt:=Length(Prefix)-4;
  Add(#$48#$85#$C0);             { test rax,rax }
  Add(#$0F#$8E#0#0#0#0);         { jle reject on EOF/other error }
  TooShortAt:=Length(Prefix)-4;
  Add(#$49#$01#$C2);             { add r10,rax (received) }
  Add(#$49#$83#$FA#$06);         { cmp r10,6 }
  Add(#$0F#$8C#0#0#0#0);         { jl loop }
  RepeatAt:=Length(Prefix)-4;
  ProbeAt:=Length(Prefix);
  Add(#$31#$C0);                 { read syscall=0; EOF probe }
  Add(#$31#$FF);                 { stdin fd=0 }
  Add(#$48#$8D#$74#$24#$06);     { lea rsi,[rsp+6]; 7th byte }
  Add(#$BA#$01#0#0#0);          { probe 1 byte }
  Add(#$0F#$05);
  Add(#$48#$83#$F8#$FC);         { cmp rax,-EINTR }
  Add(#$0F#$84#0#0#0#0);         { je retry ONLY EOF probe }
  ProbeRetryAt:=Length(Prefix)-4;
  Add(#$48#$85#$C0);             { test rax,rax }
  Add(#$0F#$85#0#0#0#0);         { jne reject on surplus/other error }
  TooLongAt:=Length(Prefix)-4;
  Add(#$E9#0#0#0#0);             { jmp directly to donor decoder }
  DecodeAt:=Length(Prefix)-4;
  NewLen:=Length(Prefix);
  PatchRel32(FrameRetryAt,LoopAt);
  PatchRel32(TooShortAt,NewLen+RejectRelative);
  PatchRel32(RepeatAt,LoopAt);
  PatchRel32(ProbeRetryAt,ProbeAt);
  PatchRel32(TooLongAt,NewLen+RejectRelative);
  PatchRel32(DecodeAt,NewLen+OriginalReadBytes);
  Require((NewLen<160) and (Length(Original)+NewLen<8192),
    'порушена машинна квота/геометрія');
  Result:=Copy(Original,1,HeaderBytes)+Prefix+
    Copy(Original,HeaderBytes+1,Length(Original)-HeaderBytes);
  Require(Length(Result)=Length(Original)+NewLen,
    'помилка копіювання незмінного донора');
  PutQWord(Result,96,Length(Result));    { PT_LOAD filesz }
  PutQWord(Result,104,Length(Result));   { PT_LOAD memsz }
  VerifySENSELF64(Result,G);
  Require((G.Kind=3) and (G.Entry=HeaderBytes) and
    (G.FileBytes=Length(Result)) and
    (Copy(Result,HeaderBytes+NewLen+1,OriginalReadBytes)=
     Copy(Original,HeaderBytes+1,OriginalReadBytes)),
    'після звірки змінилися донорські інструкції');
end;
end.
