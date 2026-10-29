{ G6.119 — exhaustive 16 D1^4 nested D3:101 machine CALL tests.
  Binary .sens фізично створює наявний T5M, ніякого D7 dispatch.
  Фактичні відповіді перевіряють реальні Linux ELF64 та pinned SENS.
  Негативи доводять fail-closed до ELF, не перетворюють D12 на D1.
  Питання: (1) чому W7 не приймаємо як W1? (2) що доводить 3 CALL?
  (3) чому кожний call повертається з однієї shared підпрограми?
  (4) де фізичні байти T5M відрізняються від utf8?
  (5) чому потрібно порівняння з незалежним oracle? }
program test_irnestedeqcall;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.irnestedeqcall,wsm.elfgeometry;

var OutputDir:String; Passed,Rejected:SizeInt; I:Integer;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('G6_119_FAIL: '+Why)
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(OutputDir+'/'+Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end
end;

function OneBit(Bit:Integer):RawByteString;
begin
  Check((Bit=0) or (Bit=1),'test vector D1 range');
  if Bit=0 then Result:='0' else Result:='1';
end;

function Source(A,B,C,D:Integer):RawByteString;
begin
  Result:=EncodeT5M(W(['10','101',
    '10','101',OneBit(A),OneBit(B),'01',
    '10','101',OneBit(C),OneBit(D),'01','01']));
end;

function CountByte(const S:RawByteString;Value:AnsiChar):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=1 to Length(S) do if S[I]=Value then Inc(Result)
end;

procedure Positive(I:Integer);
var A,B,C,D:Integer;SourcePhysical,Image,Expected,Machine:RawByteString;
    Name:String;ExpectedWords,Decoded:TExactWords;Geometry:TELFGeometry;
begin
  A:=(I shr 3) and 1;B:=(I shr 2) and 1;
  C:=(I shr 1) and 1;D:=I and 1;
  Name:='d3-'+OneBit(A)+OneBit(B)+OneBit(C)+OneBit(D);
  SourcePhysical:=Source(A,B,C,D);
  Image:=BuildPhysicalNestedEqCallELF(SourcePhysical,'external/sens');
  Check(Image=BuildPhysicalNestedEqCallELF(SourcePhysical,'external/sens'),
    Name+': недетермінований виконуваний ELF');
  VerifySENSELF64(Image,Geometry);
  Check((Geometry.Kind=3) and (Geometry.Entry=120) and
    (Geometry.MachineBytes>50) and (Geometry.MachineBytes<=256) and
    (Geometry.FileBytes=Length(Image)),
    Name+': некоректний ET_DYN ELF64');
  Machine:=Copy(Image,121,Length(Image)-120);
  Check(CountByte(Machine,#$E8)=3,
    Name+': відсутні три справжні CALL rel32');
  Check(CountByte(Machine,#$C3)=1,
    Name+': має бути один shared RET');
  Check(Pos(#$39#$F7#$0F#$94#$C0#$0F#$B6#$C0#$C3,Machine)>0,
    Name+': один shared CMP/SETE/MOVZX/RET не знайдено');
  Check((Pos(#$48#$83#$EC#$10,Machine)>0) and
    (Pos(#$48#$89#$04#$24,Machine)>0) and
    (Pos(#$48#$8B#$3C#$24,Machine)>0),
    Name+': збереження/відновлення RAX на реальному RSP відсутнє');
  SetLength(ExpectedWords,1);
  if (A=B)=(C=D) then ExpectedWords[0]:='1'
  else ExpectedWords[0]:='0';
  Expected:=EncodeT5M(ExpectedWords);
  DecodeT5M(Expected,Decoded);
  Check((Length(Expected)=1) and (Length(Decoded)=1) and
    (Decoded[0]=ExpectedWords[0]),Name+': D1 T5M втрачено');
  Save(Name+'.sens',SourcePhysical);
  Save(Name+'.elf',Image);
  Save(Name+'.expected.sens',Expected);
  Inc(Passed);
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Failed:Boolean;Image:RawByteString;MessageText:String;
begin
  Image:='';Failed:=False;MessageText:='';
  try Image:=BuildPhysicalNestedEqCallELF(Physical,'external/sens');
  except on E:Exception do begin
    Failed:=True;MessageText:=E.Message
  end end;
  Check(Failed and (Image='') and (Length(MessageText)>4),
    Name+': непідтриманий source не відхилено атомарно');
  Inc(Rejected);
end;
procedure Negative(const Name:String;const Words:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(W(Words))) end;

begin
  Check((ParamCount=1) and DirectoryExists(ParamStr(1)),
    'потрібен існуючий каталог .sens ELF свідків');
  OutputDir:=ParamStr(1);
  Passed:=0;Rejected:=0;
  for I:=0 to 15 do Positive(I);

  Negative('head-other',['10','110','10','101','0','0','01',
    '10','101','0','0','01','01']);
  Negative('left-head-other',['10','101','10','010','0','0','01',
    '10','101','0','0','01','01']);
  Negative('right-head-other',['10','101','10','101','0','0','01',
    '10','110','0','0','01','01']);
  Negative('left-empty',['10','101','10','101','000','0','01',
    '10','101','0','0','01','01']);
  Negative('right-empty',['10','101','10','101','0','0','01',
    '10','101','000','0','01','01']);
  Negative('left-d7',['10','101','10','101','0010110','0','01',
    '10','101','0','0','01','01']);
  Negative('right-d12',['10','101','10','101','0','0','01',
    '10','101','000000000000','0','01','01']);
  Negative('missing-left-arg',['10','101','10','101','0','01',
    '10','101','0','0','01','01']);
  Negative('extra-right-arg',['10','101','10','101','0','0','01',
    '10','101','0','0','1','01','01']);
  Negative('outer-extra',['10','101','10','101','0','0','01',
    '10','101','0','0','01','1','01']);
  Negative('outer-missing-right',['10','101','10','101','0','0','01','01']);
  Negative('root-atom',['1']);
  Negative('two-roots',['10','101','10','101','0','0','01',
    '10','101','0','0','01','01','0']);
  Negative('malformed-d2',['10','101','10','101','0','0','01',
    '10','101','0','0','01']);
  Negative('dotted-left',['10','101','10','101','0','0','01',
    '11','0','0','01']);
  NegativeRaw('malformed-t5m',#$F3);
  NegativeRaw('empty-physical','');
  NegativeRaw('not-a-physical-lisp','(тотожне? (тотожне? так так) (тотожне? так так))'+#10);
  Check((Passed=16) and (Rejected=18),
    'неповне покриття позитивів або негативів');
  WriteLn('G6_119_OK ELF=16 NEG=18 CALLS=3 RET=1 SOURCE=PACKED_T5M',
    ' ENERGY=NOT_MEASURED');
end.
