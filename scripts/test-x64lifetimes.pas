{ G6.108 — verified host live intervals + pinned physical D5 compiler witness.
  Два незалежні механічні oracle: GNU as для 8 REX MOVABS байтів,
  дійсні ELF64 для 9 D5 повних packed .sens форм.
  Семантичний oracle — pinned SENS REPL тільки в shell CI.
  Дані: фізичні RawByteString T5M належать цьому тесту; allocator
  повертає власний dynamic array. Нічого не публікує за винятку.
  Запитання: 1) Чому unsigned machine slot не є D12?
  2) Чому 9 одночасних значень повинні викликати відмову?
  3) Як GNU as перевіряє REX регістри?
  4) Чому pinned REPL потрібно запускати окремо?
  5) Як перевіряємо незмінність виходу після помилки? }
program test_x64lifetimes;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64lifetimes,wsm.x64rex,wsm.x64code,
     wsm.t5m,wsm.numericplane,wsm.numericadd,
     wsm.irwiderexadd,wsm.elfgeometry;
var Directory:String; Lifetimes:array of TX64LiveInterval;
    Allocated:TRegLifetimes; TestCount,NegativeCount,CaseNo,I,J:Integer;
    Machine:TX64Code; A:TStringList; ByteCode,Source,LeftPhysical,
    RightPhysical,Expected,ELF:RawByteString;
    LeftNumber,RightNumber:TExplicitNumeric; G:TELFGeometry;
    LabelNumber:String;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('РЕГІСТРИ-ЖИТТЯ-ПРОВАЛ: '+Why);
end;
procedure WriteBytes(const Path:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;
function ReadBytes(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>0) and (Stream.Size<=128),'невірна фізична довжина атома');
    SetLength(Result,Stream.Size);
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;
function Pack(const Words:array of RawByteString):RawByteString;
var V:TExactWords; K:SizeInt;
begin
  SetLength(V,Length(Words));
  for K:=0 to High(Words) do V[K]:=Words[K];
  Result:=EncodeT5M(V);
end;
procedure Prepare(var Live:array of TX64LiveInterval;
                  Index,Slot,First,After:Integer);
begin
  Live[Index].Slot:=Slot;
  Live[Index].First:=First;
  Live[Index].After:=After;
end;
procedure Reject(const Why:String);
var ReturnValue:TRegLifetimes; Refused:Boolean;
begin
  SetLength(ReturnValue,1);
  ReturnValue[0].Slot:=777;
  Refused:=False;
  try AssignX64Lifetimes(Lifetimes,ReturnValue)
  except on E:EX64LifetimesError do Refused:=True end;
  Need(Refused and (Length(ReturnValue)=0),
    'не відхилено атомарно: '+Why);
  Inc(NegativeCount);
end;
procedure NegativeTests;
begin
  NegativeCount:=0;
  SetLength(Lifetimes,0);Reject('порожнє');
  SetLength(Lifetimes,1);
  Prepare(Lifetimes,0,0,0,1);Reject('нульовий slot');
  Prepare(Lifetimes,0,4096,0,1);Reject('slot > 4095');
  Prepare(Lifetimes,0,1,-1,1);Reject('негативний First');
  Prepare(Lifetimes,0,1,1,1);Reject('порожній interval');
  Prepare(Lifetimes,0,1,2,1);Reject('After < First');
  Prepare(Lifetimes,0,1,0,1025);Reject('After > quota');
  SetLength(Lifetimes,2);
  Prepare(Lifetimes,0,1,3,4);Prepare(Lifetimes,1,2,2,5);
  Reject('непосортовані First');
  Prepare(Lifetimes,0,2,0,4);Prepare(Lifetimes,1,1,0,4);
  Reject('непосортовані Slot при First tie');
  Prepare(Lifetimes,0,1,0,1);Prepare(Lifetimes,1,1,1,2);
  Reject('повторний slot навіть після завершення');
  SetLength(Lifetimes,9);
  for I:=0 to 8 do Prepare(Lifetimes,I,I+1,0,20);
  Reject('дев''ятий одночасно живий interval');
  SetLength(Lifetimes,129);
  for I:=0 to 128 do Prepare(Lifetimes,I,I+1,I,I+1);
  Reject('понад 128 intervals');
  Need(NegativeCount=12,'невірне число негативів');
end;
procedure PositiveTests;
begin
  TestCount:=0;
  SetLength(Lifetimes,128);
  for I:=0 to 127 do
    Prepare(Lifetimes,I,I+1,(I div 8)*2,((I div 8)+1)*2);
  AssignX64Lifetimes(Lifetimes,Allocated);
  Need(Length(Allocated)=128,'пропущено перевірку 128 інтервалів');
  for I:=0 to 127 do begin
    Need((Allocated[I].Slot=I+1) and
         (Allocated[I].Reg=TX64WideReg(Ord(wrR8)+(I mod 8))),
      'нестабільне призначення або передчасне перевикористання');
    Inc(TestCount);
  end;
  { Reuse на ТОЧНОМУ граничному First=After, всі R8..R15.
    На один інтервал пізніше жоден register не виділяється знову
    доки старий After не настиг поточний First. }
  SetLength(Lifetimes,16);
  for I:=0 to 7 do Prepare(Lifetimes,I,I+1,0,2);
  for I:=8 to 15 do Prepare(Lifetimes,I,I+1,2,4);
  AssignX64Lifetimes(Lifetimes,Allocated);
  for I:=0 to 15 do begin
    Need(Allocated[I].Reg=TX64WideReg(Ord(wrR8)+(I mod 8)),
         'неприпустима повторна алокація фізичного регістра');
    Inc(TestCount);
  end;
  SetLength(Lifetimes,8);
  for I:=0 to 7 do Prepare(Lifetimes,I,I+1,0,8);
  AssignX64Lifetimes(Lifetimes,Allocated);
  X64Reset(Machine);
  A:=TStringList.Create;
  try
    A.Add('.intel_syntax noprefix');
    A.Add('.text');
    A.Add('.global _start');
    A.Add('_start:');
    for I:=0 to 7 do begin
      X64RexMovAbs(Machine,Allocated[I].Reg,QWord(Allocated[I].Slot));
      A.Add('  movabs r'+IntToStr(I+8)+',0x'+IntToHex(I+1,16));
    end;
    ByteCode:=X64Image(Machine);
    Need(Length(ByteCode)=80,'8 MOVABS має бути точно 80 байтів');
    A.SaveToFile(Directory+'/allocator.s');
    WriteBytes(Directory+'/allocator.fpc.bin',ByteCode);
  finally A.Free end;
end;
procedure PhysicalProgramTests;
begin
  SetLength(Lifetimes,2);
  Prepare(Lifetimes,0,1,0,2);
  Prepare(Lifetimes,1,2,0,2);
  AssignX64Lifetimes(Lifetimes,Allocated);
  Need((Length(Allocated)=2) and (Allocated[0].Reg=wrR8) and
       (Allocated[1].Reg=wrR9),
       'живі два W12 операнди не отримали R8 та R9');
  for CaseNo:=1 to 9 do begin
    LabelNumber:=Format('%.2d',[CaseNo]);
    LeftPhysical:=ReadBytes(Directory+'/'+LabelNumber+'-l.sens');
    RightPhysical:=ReadBytes(Directory+'/'+LabelNumber+'-r.sens');
    LeftNumber:=ReadNumericPhysical(LeftPhysical,12);
    RightNumber:=ReadNumericPhysical(RightPhysical,12);
    Source:=Pack(['10','01010',LeftNumber.ExactBits,
                 RightNumber.ExactBits,'01']);
    { Повна фізична форма; існуючий compiler перевіряє всі Dn і
      арифметичний overflow. Цей тест лише з'єднує allocator із
      already verified register usage, НЕ дублює numeric law. }
    ELF:=BuildIRWideRexAddELF(Source,'external/sens');
    VerifySENSELF64(ELF,G);
    Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(ELF)),
      'REX PIE не пройшов геометрію');
    Need(Copy(ELF,141,6)=#$4D#$01#$C8#$4C#$89#$C0,
      'R8/R9 ISA не відповідає allocation record');
    Expected:=AddNumericPhysical(LeftPhysical,RightPhysical,12);
    WriteBytes(Directory+'/'+LabelNumber+'.sens',Source);
    WriteBytes(Directory+'/'+LabelNumber+'.elf',ELF);
    WriteBytes(Directory+'/'+LabelNumber+'-expected.sens',Expected);
  end;
end;
begin
  Need(ParamCount=1,'потрібна приватна тека');
  Directory:=ParamStr(1);
  Need(DirectoryExists(Directory),'тека не існує');
  PositiveTests;
  NegativeTests;
  PhysicalProgramTests;
  WriteLn('X64-LIFETIMES-OK interval=144 register-matrix=8 ',
          'negative=',NegativeCount,' physical-d5=9');
end.
