{ G6.135 — 16 канонічних фізичних nested D3 EQ (D1^4).
  Кожний позитив генеруємо існуючим T5M, незалежний pinned SENS
  oracle виконується у shell. FPC/CPU не визначає закону.
  Після оптимізації 3 CALL/3 RET ДИНАМІЧНО відсутні: замість цього
  три тотожні inline послідовності CMP/SETE/MOVZX, без host precompute.
  Physical, Baseline, Inlined — managed bytes кожного test case,
  вихідні свідки належать тимчасовому каталогу bash runner.
  Питання: 1) чому 16 комбінацій вичерпують рівно D1^4?
  2) чому не можна замінити CPU порівняння Pascal constant fold?
  3) чому byte length порівнюємо незалежно від semantics?
  4) що доводить readelf/objdump і чого не доводить?
  5) чому без окремого вимірювання не заявляємо економію джоулів? }
program test_irnestedinline;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.irnestedeqcall,
  wsm.irnestedinline,wsm.elfgeometry;

var Dir:String;Passed,Bad:SizeInt;

function W(const Values:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Values));
  for I:=0 to High(Values) do Result[I]:=Values[I];
end;
function Bit(V:SizeInt):RawByteString;
begin if V=0 then Result:='0' else Result:='1' end;
procedure Check(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('G6_135_FAIL '+Why) end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
function CountByte(const Bytes:RawByteString;Value:AnsiChar):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=1 to Length(Bytes) do if Bytes[I]=Value then Inc(Result);
end;
function CountPattern(const S,Pattern:RawByteString):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=1 to Length(S)-Length(Pattern)+1 do
    if Copy(S,I,Length(Pattern))=Pattern then Inc(Result);
end;

procedure Positive(Index:SizeInt);
var A,B,C,D:SizeInt;
    Name:String;Physical,Original,Optimized,Expected,Machine:RawByteString;
    G,H:TELFGeometry;Encoded:TExactWords;
begin
  A:=(Index shr 3) and 1;B:=(Index shr 2) and 1;
  C:=(Index shr 1) and 1;D:=Index and 1;
  Name:='d3-'+Bit(A)+Bit(B)+Bit(C)+Bit(D);
  Physical:=EncodeT5M(W(['10','101',
    '10','101',Bit(A),Bit(B),'01',
    '10','101',Bit(C),Bit(D),'01','01']));
  Original:=BuildPhysicalNestedEqCallELF(Physical,'external/sens');
  Optimized:=BuildPhysicalNestedEqInlineELF(Physical,'external/sens');
  Check((Optimized<>Original) and
    (Optimized=BuildPhysicalNestedEqInlineELF(Physical,'external/sens')),
    Name+': недетермінований або незмінений codegen');
  VerifySENSELF64(Original,G);
  VerifySENSELF64(Optimized,H);
  Check((G.Kind=3) and (H.Kind=3) and (G.Entry=H.Entry) and
    (G.FileBytes=H.FileBytes) and
    (G.MachineBytes=H.MachineBytes) and
    (Length(Original)=Length(Optimized)) and
    (G.MachineBytes<=256),Name+': змінили довжину чи геометрію');
  Machine:=Copy(Optimized,121,G.MachineBytes);
  Check((CountByte(Machine,#$E8)=0) and
    (CountByte(Machine,#$C3)=0) and
    (CountPattern(Machine,#$39#$F7#$0F#$94#$C0#$0F#$B6#$C0)=3),
    Name+': CAL[L]/RET не повністю замінено на три реальні EQ');
  Check((CountByte(Copy(Original,121,G.MachineBytes),#$E8)=3) and
    (CountByte(Copy(Original,121,G.MachineBytes),#$C3)=1),
    Name+': базовий verified CALL/RET профіль змінився');
  SetLength(Encoded,1);
  if (A=B)=(C=D) then Encoded[0]:='1' else Encoded[0]:='0';
  Expected:=EncodeT5M(Encoded);
  Check(Length(Expected)=1,Name+': pinned D1 physical width');
  Save(Name+'.sens',Physical);
  Save(Name+'.baseline.elf',Original);
  Save(Name+'.inline.elf',Optimized);
  Save(Name+'.expected.sens',Expected);
  Inc(Passed);
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Image:RawByteString;Rejected:Boolean;Why:String;
begin
  Image:='';Rejected:=False;Why:='';
  try Image:=BuildPhysicalNestedEqInlineELF(Physical,'external/sens')
  except on E:Exception do begin Rejected:=True;Why:=E.Message end end;
  Check(Rejected and (Image='') and (Length(Why)>=5),
    Name+': не повернуто fail-closed');
  Inc(Bad);
end;
procedure Negative(const Name:String;const Parts:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(W(Parts))) end;

var I:SizeInt;
begin
  Check((ParamCount=1) and DirectoryExists(ParamStr(1)),
    'потрібен існуючий тимчасовий каталог для T5M і ELF');
  Dir:=ParamStr(1);Passed:=0;Bad:=0;
  for I:=0 to 15 do Positive(I);
  Negative('хибна-зовнішня-голова',
    ['10','110','10','101','0','0','01','10','101','0','0','01','01']);
  Negative('хибна-ліва-голова',
    ['10','101','10','110','0','0','01','10','101','0','0','01','01']);
  Negative('хибна-права-голова',
    ['10','101','10','101','0','0','01','10','111','0','0','01','01']);
  Negative('ліва-D7',
    ['10','101','10','101','0010110','0','01','10','101','0','0','01','01']);
  Negative('права-D12',
    ['10','101','10','101','0','0','01','10','101','000000000000','0','01','01']);
  Negative('ліва-порожнеча',
    ['10','101','10','101','000','0','01','10','101','0','0','01','01']);
  Negative('зайвий-зовнішній-аргумент',
    ['10','101','10','101','0','0','01','10','101','0','0','01','0','01']);
  Negative('зайвий-аргумент-справа',
    ['10','101','10','101','0','0','01','10','101','0','0','1','01','01']);
  Negative('один-аргумент-зліва',
    ['10','101','10','101','0','01','10','101','0','0','01','01']);
  Negative('два-корені',
    ['10','101','10','101','0','0','01','10','101','0','0','01','01','0']);
  Negative('корінь-D1',['1']);
  Negative('крапкова-пара',
    ['10','101','10','101','0','0','01','11','0','0','01']);
  NegativeRaw('битий-T5M',#$F3);
  NegativeRaw('порожній-T5M','');
  NegativeRaw('людська-проєкція','(тотожне? (тотожне? так так) (тотожне? так так))'+#10);
  Check((Passed=16) and (Bad=15),'неповне охоплення 16/15');
  WriteLn('G6_135_OK PHYSICAL=16 OPTIMIZED=16 NEGATIVE=15',
    ' MACHINE_CALL=0 MACHINE_RET=0 INLINE_EQ=3',
    ' DELTA_ELF_BYTES=0 ENERGY=NOT_MEASURED');
end.
