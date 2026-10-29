{ G6.53 — реальний знижений D3:101 ExactIR → ELF64, 4 машинні свідки.
  SENS — pinned authority; тут НЕ створюється власний закон. }
program test_eqir;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.eqir, wsm.elfeq,
  wsm.elfgeometry;

var Passed, Rejected: SizeInt;

function W(const Parts: array of RawByteString): TExactWords;
var I: SizeInt;
begin
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do Result[I] := Parts[I];
end;

procedure Check(Yes: Boolean; const Why: String);
begin
  if not Yes then raise Exception.Create('ЗНИЖЕННЯ-Д3-ПРОВАЛ: '+Why);
end;

procedure Save(const Path: String; const Bytes: RawByteString);
var F: TFileStream;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    if Length(Bytes) > 0 then F.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    F.Free;
  end;
end;

procedure Positive(const Name, Left, Right, Expected: RawByteString);
var
  Physical, Machine, Prior: RawByteString;
  Operation: TLoweredD3Eq;
  Geometry: TELFGeometry;
begin
  Physical := EncodeT5M(W(['10','101',Left,Right,'01']));
  LowerPinnedD3Eq(Physical,'external/sens',Operation);
  Check((Operation.LeftBit = Ord(Left[1])-48) and
        (Operation.RightBit = Ord(Right[1])-48) and
        (Operation.HeadWord = 2) and
        (Operation.LeftWord = 3) and
        (Operation.RightWord = 4),
    String(Name)+': втрачено точні D1 біти або фізичні позиції');
  Machine := BuildPinnedD3EqIRELF(Physical,'external/sens');
  Prior := BuildEqELF(Physical,'external/sens');
  Check(Machine = Prior,
    String(Name)+': IR-емітер не дорівнює перевіреному D3 машинному backend');
  VerifySENSELF64(Machine,Geometry);
  Check((Geometry.Kind = 2) and (Geometry.FileBytes = Length(Machine)) and
        (Pos(#$39#$C8#$0F#$94#$C0,Machine) > 0),
    String(Name)+': ELF64 геометрія або машинна CMP/SETE відсутня');
  Save('build/m0.2/eqir/'+String(Name)+'.sens',Physical);
  Save('build/m0.2/eqir/'+String(Name)+'.elf',Machine);
  Save('build/m0.2/eqir/'+String(Name)+'.expected',Expected+#10);
  Inc(Passed);
end;

procedure NegativeRaw(const Name, Physical: RawByteString);
var
  Returned: RawByteString;
  Lowered: TLoweredD3Eq;
  RejectedHere: Boolean;
begin
  Lowered.LeftBit := 255;
  RejectedHere := False;
  try
    LowerPinnedD3Eq(Physical,'external/sens',Lowered);
  except on E:Exception do RejectedHere := True end;
  Check(RejectedHere and (Lowered.LeftBit = 0),
    String(Name)+': неповна або неатомарна відмова lowering');
  Returned := '';
  RejectedHere := False;
  try
    Returned := BuildPinnedD3EqIRELF(Physical,'external/sens');
  except on E:Exception do RejectedHere := True end;
  Check(RejectedHere and (Returned = ''),
    String(Name)+': недопустима форма породила машинний результат');
  Inc(Rejected);
end;

procedure Negative(const Name: RawByteString;
  const Parts: array of RawByteString);
begin
  NegativeRaw(Name,EncodeT5M(W(Parts)));
end;

begin
  ForceDirectories('build/m0.2/eqir');
  Passed := 0; Rejected := 0;
  Positive('d1-00','0','0','1');
  Positive('d1-01','0','1','0');
  Positive('d1-10','1','0','0');
  Positive('d1-11','1','1','1');

  Negative('самотній-D1',['0']);
  Negative('голова-CONS',['10','111','0','1','01']);
  Negative('голова-ATOM',['10','010','0','1','01']);
  Negative('відсутній-аргумент',['10','101','0','01']);
  Negative('зайвий-аргумент',['10','101','0','1','1','01']);
  Negative('порожнеча-не-D1',['10','101','000','1','01']);
  Negative('D2-список-не-D1',['10','101','10','01','1','01']);
  Negative('крапкова-пара',['10','101','0','11','1','01']);
  Negative('D7-SYN-не-D1',['10','101','0010110','1','01']);
  Negative('D7-SYN-не-голова',['10','0010110','0','1','01']);
  Negative('D12-не-D1',['10','101','000000000000','1','01']);
  Negative('другий-корінь',['10','101','0','1','01','1']);
  Negative('незакритий-D2',['10','101','0','1']);
  Negative('W10-не-D3',['10','0000000101','0','1','01']);
  NegativeRaw('неприпустимий-фізичний-байт',#$F3);
  NegativeRaw('порожній-фізичний-файл','');
  Check((Passed = 4) and (Rejected = 16),
    'неправильна кількість фізичних позитивів/негативів');
  WriteLn('ЗНИЖЕННЯ-Д3-IR-ГАРАЗД ELF=4 негативи=',Rejected,
    ' рівність-байтів-старий-backend=так T5M=первинний');
  WriteLn('ЗНИЖЕННЯ-Д3-IR-МЕЖА D7=дані D12+=заборонено',
    ' Core4=не-підтримано інші-D3=не-підтримано');
end.
