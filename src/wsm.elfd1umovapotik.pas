{ G6.89. Сталий native ELF64 PIE: два динамічні D3:110 двопольові
  речення над рівно чотирма фізичними D1 атомами.
  stdin — host-конкатенація чотирьох ОКРЕМИХ packed W1 байтів,
  НЕ канонічна SENS програма. Справжній D2/T5M oracle окремо.
  Вихід: точно один T5M D1 або D3:000 за pinned exhaustion.
  Лише pinned external/sens Contract12 K12.3, D3:110 і CMP+Jcc;
  не створює нового закону, текстового dispatch або Pascal-evaluator.
  Питання: чому D3:000 не є D1:0?
  Чому перевіряємо кожний фізичний W1 байт перед машинним JNE?
  Чому для даних stdin немає compile-time константної відповіді?
  Кому належать image/Code, а кому — стек виконуваного Linux процесу?
  Чому чотири W1 host байти не утворюють самостійної D2 програми? }
unit wsm.elfd1umovapotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED1CondStreamError=class(Exception);
function BuildD1CondStreamELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise ED1CondStreamError.Create(Why) end;

{ Return — owned RawByteString, immutable executable image after build.
  All machine branches are rel32 and patched against complete Code.
  FPC manages every Code/Diagnostic RawByteString allocation; OS owns
  stack and sys_read/sys_write buffers only while ELF executes.
  1) Why make only ONE image for all sixteen combinations?
  2) Why does a signed rel32 branch not depend on PIE base?
  3) Why does stdout occur only after full admission?
  4) How are invalid stdin bytes rejected without a D1 result?
  5) Why does D3:000 use its own T5M encoding? }
function BuildD1CondStreamELF:RawByteString;
var
  Words:TExactWords;
  Zero,One,Empty,Diagnostic,Code:RawByteString;
  Geometry:TELFGeometry;
  Rejections:array[0..4] of SizeInt;
  RejectCount,I,Valid,SkipFirst,SkipSecond,FinishFirst,FinishSecond:SizeInt;
  Exhausted,Finish,RejectStart,DiagnosticLea,Total:SizeInt;

  procedure Add(const S:RawByteString);
  begin
    Need(Length(Code)+Length(S)<=2048,'перевищено бюджет машинного коду');
    Code:=Code+S;
  end;
  procedure LE32(V:LongWord);
  var J:SizeInt;
  begin
    for J:=0 to 3 do begin Add(AnsiChar(V and $FF)); V:=V shr 8 end;
  end;
  procedure Patch32(Pos0:SizeInt;Value:LongInt);
  var J:SizeInt; V:LongWord;
  begin
    Need((Pos0>=0) and (Pos0<=Length(Code)-4),
      'машинне rel32 поза кодом');
    V:=LongWord(Value);
    for J:=0 to 3 do begin
      Code[Pos0+J+1]:=AnsiChar(V and $FF); V:=V shr 8;
    end;
  end;
  function Branch(Opcode:AnsiChar):SizeInt;
  begin
    Result:=Length(Code);
    Add(#$0F+Opcode+#0#0#0#0); { rel32: 0F 84 JE / 0F 85 JNE }
  end;
  function Jump:SizeInt;
  begin
    Result:=Length(Code);
    Add(#$E9#0#0#0#0);
  end;
  procedure LinkBranch(Pos0,Target0:SizeInt);
  begin
    Need((Pos0>=0) and (Pos0+6<=Length(Code)) and
      (Target0>=0) and (Target0<=Length(Code)),
      'невірна геометрія D1 переходу');
    Patch32(Pos0+2,LongInt(Target0-Pos0-6));
  end;
  procedure LinkJump(Pos0,Target0:SizeInt);
  begin
    Need((Pos0>=0) and (Pos0+5<=Length(Code)) and
      (Target0>=0) and (Target0<=Length(Code)),
      'невірний безумовний перехід');
    Patch32(Pos0+1,LongInt(Target0-Pos0-5));
  end;
  procedure Put(Offset:SizeInt;V:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Need((Offset>=0) and (Count>0) and (Count<=8) and
      (Offset<=Length(Result)-Count),'поле ELF поза образом');
    for J:=0 to Count-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(V and $FF)); V:=V shr 8;
    end;
  end;
begin
  Result:='';
  SetLength(Words,1);
  Words[0]:='0';Zero:=EncodeT5M(Words);
  Words[0]:='1';One:=EncodeT5M(Words);
  Words[0]:='000';Empty:=EncodeT5M(Words);
  Need((Length(Zero)=1) and (Length(One)=1) and
    (Length(Empty)=1) and (Zero<>One) and
    (Zero<>Empty) and (One<>Empty),
    'порушено відмінність D1 від D3:000 у T5M');
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString(
    'Д1-УМОВА-ПОТІК-ВІДМОВА: очікуються чотири канонічні W1 байти')))+#10;
  Code:='';RejectCount:=0;

  Add(#$48#$83#$EC#$10);      { sub rsp,16 }
  Add(#$31#$C0);              { xor eax,eax = sys_read }
  Add(#$31#$FF);              { xor edi,edi = stdin }
  Add(#$48#$89#$E6);          { mov rsi,rsp }
  Add(#$BA#$05#0#0#0);        { read 5: exact 4 or reject extra }
  Add(#$0F#$05);
  Add(#$48#$83#$F8#$04);      { cmp rax,4 }
  Rejections[RejectCount]:=Branch(#$85);Inc(RejectCount);

  { Чотири незалежні D1 атоми, кожен zero/one тільки через EncodeT5M.
    Валідація не обчислює істину в Pascal, лише перевіряє формат. }
  for I:=0 to 3 do begin
    if I=0 then Add(#$80#$3C#$24+Zero)
    else Add(#$80#$7C#$24+AnsiChar(I)+Zero);
    Valid:=Branch(#$84);      { byte=canonical D1:0 }
    if I=0 then Add(#$80#$3C#$24+One)
    else Add(#$80#$7C#$24+AnsiChar(I)+One);
    Rejections[RejectCount]:=Branch(#$85);Inc(RejectCount);
    LinkBranch(Valid,Length(Code));
  end;
  Need(RejectCount=5,'неперевірений W1 stdin');

  { Дві впорядковані двопольові гілки pinned D3:110.
    Жодної неявної логічної хиби з D3:000: тест лише D1:1.
    Дійсне JNE обирає лише виконувану гілку під час ELF runtime. }
  Add(#$80#$3C#$24+One);       { cmp byte [rsp], canonical D1:1 }
  SkipFirst:=Branch(#$85);     { false → second clause }
  Add(#$8A#$44#$24#$01);       { mov al,[rsp+1] = first expression }
  FinishFirst:=Jump;
  LinkBranch(SkipFirst,Length(Code));
  Add(#$80#$7C#$24#$02+One);  { cmp byte [rsp+2], D1:1 }
  SkipSecond:=Branch(#$85);
  Add(#$8A#$44#$24#$03);       { mov al,[rsp+3] = second expression }
  FinishSecond:=Jump;
  LinkBranch(SkipSecond,Length(Code));
  Exhausted:=Length(Code);
  Add(#$B0+Empty);             { mov al, exact structural D3:000 }
  Finish:=Length(Code);
  LinkJump(FinishFirst,Finish);
  LinkJump(FinishSecond,Finish);
  Need(Exhausted<Finish,'відсутній окремий шлях вичерпання');

  Add(#$88#$04#$24);         { mov [rsp],al }
  Add(#$B8#$01#0#0#0);       { sys_write stdout,1 }
  Add(#$BF#$01#0#0#0);
  Add(#$48#$89#$E6);
  Add(#$BA#$01#0#0#0);
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);       { sys_exit 0 }
  Add(#$31#$FF);
  Add(#$0F#$05);

  RejectStart:=Length(Code);
  Add(#$B8#$01#0#0#0);       { sys_write stderr, diagnostics }
  Add(#$BF#$02#0#0#0);
  DiagnosticLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0);
  Add(#$BA);LE32(LongWord(Length(Diagnostic)));
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);       { sys_exit 2 }
  Add(#$BF#$02#0#0#0);
  Add(#$0F#$05);

  for I:=0 to RejectCount-1 do LinkBranch(Rejections[I],RejectStart);
  Patch32(DiagnosticLea+3,LongInt(Length(Code)-DiagnosticLea-7));
  Total:=HeaderBytes+Length(Code)+Length(Diagnostic);
  Need((Total>HeaderBytes) and (Total<4096),'завеликий ELF');
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  Put(0,$464C457F,4); Put(4,2,1); Put(5,1,1); Put(6,1,1);
  Put(16,3,2); Put(18,62,2); Put(20,1,4);
  Put(24,HeaderBytes,8); Put(32,64,8);
  Put(52,64,2); Put(54,56,2); Put(56,1,2);
  Put(64,1,4); Put(68,5,4);
  Put(80,0,8); Put(88,0,8); Put(96,Total,8);
  Put(104,Total,8); Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to Length(Diagnostic) do
    Result[HeaderBytes+Length(Code)+I]:=Diagnostic[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Total) and
    (Geometry.Entry=HeaderBytes),
    'невірна незалежна геометрія ELF64 PIE');
end;
end.
