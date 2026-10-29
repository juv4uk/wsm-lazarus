{ G6.91 — НЕЗАЛЕЖНИЙ golden-бенч машинного коду x86-64.
  Reference зберігає до-рефакторингову G6.67 послідовність байтів.
  Лише host opcode: ніякого власного мовного реєстру SENS.
  Тест не вимірює джоулі і не замінює pinned CLI oracle. }
program test_x64code;
{$mode objfpc}{$H+}
uses SysUtils,wsm.x64code;
var C:TX64Code; V:array[0..2] of Byte; I,N,Good,Bad:SizeInt;
    Ref,Got,Before:RawByteString; Failed:Boolean;

procedure Check(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create('X64-КОДЕР-ПРОВАЛ: '+Why) end;

{ Старий фіксований шаблон G6.67, незалежний від нового кодера.
  Golden вимірює точні машинні байти, а не лише результат програми.
  Усі вхідні D1-біти мають точний T5M Zero=$50 Delta=$51,
  реальний інтеграційний тест перевірить цей codec заново. }
function OldTemplate(const A,B,D:Byte;Const Delta,Zero:Byte):RawByteString;
begin
  Result:=
    #$B8+AnsiChar(A)+#0#0#0+
    #$B9+AnsiChar(B)+#0#0#0+
    #$BA+AnsiChar(D)+#0#0#0+
    #$48#$83#$EC#$20+
    #$48#$89#$04#$24+
    #$48#$89#$4C#$24#$08+
    #$48#$89#$54#$24#$10+
    #$48#$8D#$34#$24+
    #$48#$8B#$56#$10+
    #$6B#$D2+AnsiChar(Delta)+
    #$83#$C2+AnsiChar(Zero)+
    #$88#$14#$24+
    #$B8#$01#0#0#0+#$BF#$01#0#0#0+
    #$48#$89#$E6+#$BA#$01#0#0#0+#$0F#$05+
    #$B8#$3C#0#0#0+#$31#$FF+#$0F#$05;
end;

procedure Build(const A,B,D:Byte;const Delta,Zero:Byte);
begin
  X64Reset(C);
  X64MovImm32(C,xrAX,A);
  X64MovImm32(C,xrCX,B);
  X64MovImm32(C,xrDX,D);
  X64SubRsp8(C,32);
  X64StoreRspQword(C,xrAX,0);
  X64StoreRspQword(C,xrCX,8);
  X64StoreRspQword(C,xrDX,16);
  X64LeaRSIRsp(C);
  X64LoadRDXRSI(C,16);
  X64ImulEDX8(C,Delta);
  X64AddEDX8(C,Zero);
  X64StoreRspDL(C);
  X64MovImm32(C,xrAX,1);
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60);
  X64XorEDI(C);
  X64Syscall(C);
end;

procedure Rejection(const LabelText:String;Expected:Boolean);
begin
  Check(Expected,'не відхилено '+LabelText);
  Check(X64Image(C)=Before,'змінено код після відмови '+LabelText);
  Inc(Bad);
end;
begin
  Good:=0;Bad:=0;
  for I:=0 to 7 do begin
    V[0]:=(I shr 2) and 1;V[1]:=(I shr 1) and 1;V[2]:=I and 1;
    Build(V[0],V[1],V[2],$51,$50);
    Got:=X64Image(C);
    Ref:=OldTemplate(V[0],V[1],V[2],$51,$50);
    Check((Length(Got)=79) and (Got=Ref),
      'побайтовий baseline G6.67, D1 трійка №'+IntToStr(I));
    Inc(Good);
  end;
  X64Reset(C);
  X64MovImm32(C,xrDI,$A1B2C3D4);
  Check(X64Image(C)=#$BF#$D4#$C3#$B2#$A1,
    'little endian imm32 без host range conversion');
  X64Reset(C);
  X64ImulEDX8(C,-1);
  Check(X64Image(C)=#$6B#$D2#$FF,'signed8 -1 без range conversion');
  X64Reset(C);
  X64MovImm32(C,xrAX,0);
  Before:=X64Image(C);Failed:=False;
  try X64SubRsp8(C,128) except on E:EX64CodeError do Failed:=True end;
  Rejection('sub rsp більше imm8',Failed);
  Failed:=False;
  try X64StoreRspQword(C,xrCX,128)
  except on E:EX64CodeError do Failed:=True end;
  Rejection('store qword зі зміщенням 128',Failed);
  Failed:=False;
  try X64LoadRDXRSI(C,-1)
  except on E:EX64CodeError do Failed:=True end;
  Rejection('відʼємне зміщення rsi',Failed);
  Failed:=False;
  try X64ImulEDX8(C,128)
  except on E:EX64CodeError do Failed:=True end;
  Rejection('imul поза signed8',Failed);
  Failed:=False;
  try X64AddEDX8(C,-129)
  except on E:EX64CodeError do Failed:=True end;
  Rejection('add поза signed8',Failed);
  X64Reset(C);
  for I:=1 to 51 do X64MovImm32(C,xrAX,0);
  Before:=X64Image(C);
  Check(Length(Before)=255,'квота до переповнення');
  Failed:=False;
  try X64MovImm32(C,xrDX,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejection('понад 256 машинних байтів',Failed);
  X64Reset(C);
  Check(X64Image(C)='','очищення після відмов');
  Build(0,1,0,$51,$50);
  Check(X64Image(C)=OldTemplate(0,1,0,$51,$50),
    'після відмов не відновився машинний кодер');
  Check((Good=8) and (Bad=6),'лічильники');
  WriteLn('X64-CODE-OK golden=8 negative=6 recovery=1 bytes=79');
end.
