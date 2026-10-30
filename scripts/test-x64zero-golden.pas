{ G6.95: Golden машинні байти з ПОПЕРЕДНЬОГО самостійного D12
  нуль? emitter; це не інша семантика SENS, тільки host механізм.
  Порівнюємо 10 реальних ELF зі старою послідовністю машинних байтів.
  D12→D1 закон залишається винятково pinned upstream SENS Contract 12. }
program test_x64zero_golden;
{$mode objfpc}{$H+}
uses SysUtils,wsm.x64code,wsm.elfd12zero,wsm.t5m,wsm.numericplane;

var Checks,Negs,I,Fix:SizeInt;
    Samples:array[0..9] of LongInt=
      (0,1,-1,2047,-2048,1024,-1024,17,-17,2);
    Image,Got,Ref,Before,Physical:RawByteString;
    Writer:TX64Code; Rejected:Boolean;

procedure Need(C:Boolean;const S:String);
begin if not C then raise Exception.Create('D12-X64-GOLDEN: '+S) end;

{ КОД старого G6.77 — спеціально НЕ використовує wsm.x64code.
  Тільки ця дубльована байтова форма є тестовим golden reference;
  жодного дублювання функцій SENS або runtime-арифметики. }
function OriginalMachine(V:LongInt):RawByteString;
var W:LongWord;L,Fixup,J:SizeInt;
  procedure Append32(Val:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin
      Result:=Result+AnsiChar(Byte(Val and $FF));
      Val:=Val shr 8;
    end;
  end;
begin
  Result:='';W:=LongWord(V);
  Result:=Result+#$B8;Append32(W);
  Result:=Result+#$85#$C0+#$0F#$94#$C0+#$0F#$B6#$C0;
  Fixup:=Length(Result);
  Result:=Result+#$48#$8D#$35#0#0#0#0;
  Result:=Result+#$8A#$14#$06+#$48#$83#$EC#$08+#$88#$14#$24;
  Result:=Result+#$B8#$01#0#0#0+#$BF#$01#0#0#0+#$48#$89#$E6;
  Result:=Result+#$BA#$01#0#0#0+#$0F#$05+#$B8#$3C#0#0#0;
  Result:=Result+#$31#$FF#$0F#$05;
  L:=Length(Result); W:=LongWord(L-(Fixup+7));
  for J:=0 to 3 do begin
    Result[Fixup+3+J+1]:=AnsiChar(Byte(W and $FF));
    W:=W shr 8;
  end;
end;

procedure RejectPatch(const Name:String;A,B:SizeInt);
begin
  Before:=X64Image(Writer);Rejected:=False;
  try X64PatchRIP32(Writer,A,B)
  except on E:EX64CodeError do Rejected:=True end;
  Need(Rejected and (Before=X64Image(Writer)),
       'RIP reject/atomicity '+Name);
  Inc(Negs);
end;

begin
  Checks:=0;Negs:=0;
  for I:=0 to High(Samples) do begin
    Physical:=EncodeNumericDecimal(IntToStr(Samples[I]),12);
    Image:=BuildD12ZeroELF(Physical);
    Ref:=OriginalMachine(Samples[I]);
    Need((Length(Image)=120+Length(Ref)+2) and
         (Copy(Image,1,4)=#$7F'ELF') and
         (Ord(Image[17])=3) and (Ord(Image[19])=62),
         'цілісний ELF/розмір '+IntToStr(I));
    Got:=Copy(Image,121,Length(Ref));
    Need(Got=Ref,'старі машинні байти порушено '+IntToStr(I));
    Need(BuildD12ZeroELF(Physical)=Image,'недетермінований ELF '+IntToStr(I));
    Inc(Checks);
  end;

  X64Reset(Writer);
  X64LeaRSIRip(Writer,Fix);
  X64LoadDLRSIRAX(Writer);
  RejectPatch('відємна ціль',Fix,-1);
  RejectPatch('поза квотою',Fix,257);
  RejectPatch('початок поза кодом',-1,Length(X64Image(Writer)));
  RejectPatch('поза RIP шаблоном',0,Length(X64Image(Writer)));
  X64PatchRIP32(Writer,Fix,Length(X64Image(Writer)));
  Need(X64Image(Writer)=
       #$48#$8D#$35#$03#0#0#0+#$8A#$14#$06,
       'RIP target після 7-байтової LEA має disp32=3');
  RejectPatch('подвійна підстановка',Fix,Length(X64Image(Writer)));
  X64Reset(Writer);
  X64LeaRSIRip(Writer,Fix);
  X64PatchRIP32(Writer,Fix,Length(X64Image(Writer)));
  Need(X64Image(Writer)=#$48#$8D#$35#0#0#0#0,
       'RIP-zero та reset');
  { G6.210: байтова квота має одночасно захистити буфер машини і
    видиму caller координату disp32. Pos=252 є першим байтом disp32
    після 249 байтів NOP та трьох байтів LEA. Вихідним є власний
    TX64Code.Bytes; жодний SENS закон чи numeric D12 тут не визначається.
    1) Чому 249+7=256 дозволено, а 250+7 — ні?
    2) Чому нульовий FixupPos позначає нездійснений Emit?
    3) Чому інші 10 повних ELF мають лишитися byte-identical?
    4) Чому скидання має відновити можливість нового виправлення? }
  X64Reset(Writer);
  Writer.Bytes:=StringOfChar(AnsiChar($90),249);
  Fix:=-17;
  X64LeaRSIRip(Writer,Fix);
  Need((Fix=252) and (Length(X64Image(Writer))=256) and
       (Copy(X64Image(Writer),250,7)=#$48#$8D#$35#0#0#0#0),
       'RIP-fixup у точній межі 256 байтів');
  X64PatchRIP32(Writer,Fix,256);
  Need(Length(X64Image(Writer))=256,
       'RIP-fixup на межі пошкодив машинний буфер');

  X64Reset(Writer);
  Writer.Bytes:=StringOfChar(AnsiChar($90),250);
  Before:=X64Image(Writer);
  Fix:=-123;
  Rejected:=False;
  try
    X64LeaRSIRip(Writer,Fix);
  except on E:EX64CodeError do Rejected:=True end;
  Need(Rejected and (Fix=0) and (X64Image(Writer)=Before),
       'RIP переповнення опублікувало невірну координату/частковий код');

  X64Reset(Writer);
  X64LeaRSIRip(Writer,Fix);
  Need((Fix=3) and
       (X64Image(Writer)=#$48#$8D#$35#0#0#0#0),
       'RIP reset після переповнення не відновив машинний кодер');

  Need((Checks=10) and (Negs=5),'неповна матриця');
  WriteLn('X64-D12-ZERO-GOLDEN-OK elf=10 negative=5 rip=exact recovery=1 rip-budget=2');
end.
