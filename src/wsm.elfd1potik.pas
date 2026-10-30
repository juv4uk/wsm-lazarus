{ G6.85. Один native ELF64 PIE виконує pinned D3:101 для ДВОХ
  ДИНАМІЧНИХ D1 фізичних атомів із host stdin (два послідовні
  окремі canonical packed W1 байти, НЕ один SENS .sens документ).
  Жодних SENS законів чи мовних імен у диспетчері — тільки механізм
  фізичного прийому, перевірки та x86-64 CMP/SETE/MOVZX.
  Результат — один канонічний T5M D1 байт. За помилки відсутній
  stdout, ненульовий exit code і UTF-8 повідомлення у stderr. }
unit wsm.elfd1potik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED1StreamELFError=class(Exception);
function BuildD1StreamKernelELF:RawByteString;
implementation
uses wsm.t5m,wsm.elfgeometry,wsm.x64frameio;

const HeaderBytes=120;

procedure Need(Condition:Boolean;const Why:String);
begin if not Condition then raise ED1StreamELFError.Create(Why) end;

{ Result: owned FPC managed RawByteString ELF bytes.
  Жодного heap-розподільника під час машинного виконання: 16 байтів
  стека syscall read/write. Один read(0,buf,3) приймає рівно 2 байти
  лише від завершеного pipe/file; short read відхиляється fail-closed.
  Цей host ABI НЕ є SENS текстовим reader чи відкритим stream decoder.
  Питання: 1) Чому host concatenation двох .sens не є одним .sens?
  2) Чому syscall read читає три байти для контролю зайвого?
  3) Чому SETE працює лише після валідації двох фізичних W1?
  4) Чому RIP-relative LEA незалежний від ASLR PIE?
  5) Коли звільняється Code, а коли Image? }
function BuildD1StreamKernelELF:RawByteString;
var
  Words:TExactWords;
  Zero,One,Table,Diagnostic,Code:RawByteString;
  Rejections:array[0..2] of SizeInt;
  RejectCount,Valid0,Valid1,RejectStart,DataLea,ErrorLea:SizeInt;
  I,Total:SizeInt;
  Geometry:TELFGeometry;

  procedure Add(const Bytes:RawByteString);
  begin
    Need(Length(Code)+Length(Bytes)<=2048,'перевищено host кодовий budget');
    Code:=Code+Bytes;
  end;

  procedure LE32(Value:LongWord);
  var J:SizeInt;
  begin
    for J:=0 to 3 do begin
      Add(AnsiChar(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

  procedure Patch32(Pos0:SizeInt;Val:LongInt);
  var J:SizeInt;V:LongWord;
  begin
    Need((Pos0>=0) and (Pos0<=Length(Code)-4),'ELF patch поза payload');
    V:=LongWord(Val);
    for J:=0 to 3 do begin
      Code[Pos0+J+1]:=AnsiChar(V and $FF);
      V:=V shr 8;
    end;
  end;

  function Jne:SizeInt;
  begin
    Result:=Length(Code);
    Add(#$0F#$85#0#0#0#0); { jne rel32 }
  end;

  function Je:SizeInt;
  begin
    Result:=Length(Code);
    Add(#$0F#$84#0#0#0#0); { je rel32 }
  end;

  procedure LinkBranch(Pos0,Target0:SizeInt);
  begin
    Need((Pos0>=0) and (Pos0+6<=Length(Code)),
      'невірна позиція переходу');
    Need((Target0>=0) and (Target0<=Length(Code)),
      'невірна ціль переходу');
    Patch32(Pos0+2,LongInt(Target0-(Pos0+6)));
  end;

  procedure Put(Off:SizeInt;Value:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Need((Off>=0) and (Count>=1) and (Count<=8) and
      (Off<=Length(Result)-Count),'ELF поле поза образом');
    for J:=0 to Count-1 do begin
      Result[Off+J+1]:=AnsiChar(Value and $FF);
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  SetLength(Words,1);
  Words[0]:='0';Zero:=EncodeT5M(Words);
  Words[0]:='1';One:=EncodeT5M(Words);
  Need((Length(Zero)=1) and (Length(One)=1) and
    (Zero<>One),'W1 фізичні байти не є однозначними');
  Table:=Zero+One;
  Diagnostic:=RawByteString(UTF8Encode(UnicodeString(
    'Д1-ПОТІК-ВІДМОВА: некоректні два фізичні W1 байти')))+#10;
  RejectCount:=0;Code:='';

  Add(#$48#$83#$EC#$10);     { sub rsp,16 — приватний буфер }
  Add(#$31#$C0);             { xor eax,eax — sys_read }
  Add(#$31#$FF);             { xor edi,edi — stdin }
  Add(#$48#$89#$E6);         { mov rsi,rsp }
  Add(#$BA#$03#0#0#0);       { mov edx,3 — вимога точних 2, зайве видно }
  Add(#$0F#$05);             { syscall }
  Add(#$48#$83#$F8#$02);     { cmp rax,2 — рівно два фізичні байти }
  Rejections[RejectCount]:=Jne;Inc(RejectCount);

  { Перший W1 атом: приймаємо тільки рівно ті байти, які
    видав pinned T5M codec для точних слів D1:0/D1:1. }
  Add(#$80#$3C#$24+Zero);   { cmp byte [rsp],zero }
  Valid0:=Je;
  Add(#$80#$3C#$24+One);    { cmp byte [rsp],one }
  Rejections[RejectCount]:=Jne;Inc(RejectCount);
  LinkBranch(Valid0,Length(Code));

  Add(#$80#$7C#$24#$01+Zero); { cmp byte [rsp+1],zero }
  Valid1:=Je;
  Add(#$80#$7C#$24#$01+One);  { cmp byte [rsp+1],one }
  Rejections[RejectCount]:=Jne;Inc(RejectCount);
  LinkBranch(Valid1,Length(Code));

  { Справжня машинна D3 рівність саме під час runtime виконання;
    жодного FPC precomputed результату для конкретних операндів. }
  Add(#$0F#$B6#$04#$24);    { movzx eax, byte [rsp] }
  Add(#$3A#$44#$24#$01);    { cmp al, byte [rsp+1] }
  Add(#$0F#$94#$C0);        { sete al }
  Add(#$0F#$B6#$C0);        { movzx eax,al }
  DataLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0); { lea rsi,[rip+table] }
  Add(#$0F#$B6#$04#$06);    { movzx eax, byte [rsi+rax] }
  Add(#$88#$04#$24);        { mov [rsp],al }
  Add(#$B8#$01#0#0#0);      { write(1,buf,1) }
  Add(#$BF#$01#0#0#0);
  Add(#$48#$89#$E6);
  Add(#$BA#$01#0#0#0);
  Add(#$0F#$05);             { sys_write: RAX = bytes or -errno }
  { G6.223: D1 має рівно ОДИН фізичний T5M байт. Не можна
    повідомляти exit(0) при -EBADF, -ENOSPC або короткому write.
    CMP/JNE — тільки host-механізм публікації; D3:101/D1 без змін.
    Стек [rsp] живе до exit, heap у машинному процесі немає.
    Відмова не друкує помилкову вхідну діагностику і завершується 2.
    1) Чому треба порівнювати повний RAX, а не AL?
    2) Чому позитивний exit(0) має рівно дев'ять машинних байтів?
    3) Чому зміна машинного коду не змінює SENS закон D3:101? }
  Add(#$48#$83#$F8#$01);     { cmp rax,1 (64-bit exact write) }
  Add(#$75#$09);             { jne +9 -> exit(2) }
  Add(#$B8#$3C#0#0#0);       { exit(0) тільки після повного write }
  Add(#$31#$FF);
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);       { exit(2) при частковому/невдалому write }
  Add(#$BF#$02#0#0#0);
  Add(#$0F#$05);

  RejectStart:=Length(Code);
  Add(#$B8#$01#0#0#0);      { write(2,diagnostic,strlen) }
  Add(#$BF#$02#0#0#0);
  ErrorLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0);
  Add(#$BA);LE32(LongWord(Length(Diagnostic)));
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);      { exit(2) }
  Add(#$BF#$02#0#0#0);
  Add(#$0F#$05);

  Need(RejectCount=3,'не всі контролі stdin додано');
  for I:=0 to RejectCount-1 do LinkBranch(Rejections[I],RejectStart);
  Patch32(DataLea+3,LongInt(Length(Code)-(DataLea+7)));
  Patch32(ErrorLea+3,LongInt(
    Length(Code)+Length(Table)-(ErrorLea+7)));

  Total:=HeaderBytes+Length(Code)+Length(Table)+Length(Diagnostic);
  Need((Total>HeaderBytes) and (Total<4096),'ELF перевищив host budget');
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to Length(Table) do
    Result[HeaderBytes+Length(Code)+I]:=Table[I];
  for I:=1 to Length(Diagnostic) do
    Result[HeaderBytes+Length(Code)+Length(Table)+I]:=Diagnostic[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Total),
    'ELF PIE не пройшов незалежний структурний admission');
  { G6.240: один host read(0,rsp,3) може законно повернути лише 1
    з двох packed W1 байтів. Перевірений спільний x64-механізм
    накопичує РІВНО два байти, retry лише EINTR, вимагає EOF
    і лише тоді переходить до незмінних CMP/SETE/MOVZX та T5M.
    Вхідні два W1 — окремі borrowed фізичні атоми host каналу,
    НЕ програма .sens. Образ Result — новий owned ELF64.
    1) Чому одноразовий Linux read не є строгим admission?
    2) Чому 3-й байт мусить відхилятися навіть після двох W1?
    3) Чому внутрішні RIP-rel32 не треба переписувати?
    4) Чому це не новий закон D3:101 і не D7 dispatch? }
  Result:=WrapExactTwoByteFrame(Result);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
    (Geometry.FileBytes=Length(Result)) and (Length(Result)>Total),
    'точний host кадр D1 не підтвердив ELF64 PIE');
end;
end.
