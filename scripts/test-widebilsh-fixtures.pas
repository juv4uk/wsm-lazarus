{ G6.85 — фізичні D2/T5M обгортки для 12 вже перевірених D12 пар.
  Fixture generator не створює нового semantic oracle і не визначає
  D5 закон: uses існуючі pinned numeric + T5M механізми. }
program test_widebilsh_fixtures;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;I:Integer;A,B,C:RawByteString;Count:Integer;Wide:TExactWords;

function ReadData(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise Exception.Create('потрібен уже сформований малий фізичний атом');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

function Words(const List:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(List));
  for J:=0 to High(List) do Result[J]:=List[J];
end;

{ Вхід borrowed canonical packed D12 із наявної матриці, вихід owned
  точний бітовий рисунок. D12 numeric admission виконується повторно
  чинним wsm.numericplane, а не виводиться з host десяткових слів.
  1) Чому Bits зберігають leading zeros?
  2) Чому D12 перевіряє ReadNumericPhysical?
  3) Чому downstream треба ще pinned WideIR?
  4) Чому fixture сам не oracle? }
function D12Bits(const Bytes:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(Bytes,12);
  Result:=N.ExactBits;
end;

{ Output files — owned physical bytes with real D2:10/01 framing.
  Naming is host-only; all function addresses are exact pinned bits.
  1) Чому D5:11011 не є англійською назвою?
  2) Чому D2 оформлення важливе?
  3) Хто перевіряє canonical packing?
  4) Чим відрізняється одиночний фізичний W12 від усієї форми? }
procedure ProgramCase(const Name:String;const L,R:RawByteString);
begin
  Save(Name,EncodeT5M(Words(['10','11011',L,R,'01'])));
end;

var Name:String;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Count:=0;
  for I:=1 to 12 do begin
    Name:=Format('%.2d',[I]);
    A:=D12Bits(ReadData(Folder+'/'+Name+'-l.sens'));
    B:=D12Bits(ReadData(Folder+'/'+Name+'-r.sens'));
    ProgramCase(Name+'-program.sens',A,B);
    Inc(Count);
  end;
  if Count<>12 then Halt(2);
  A:=D12Bits(ReadData(Folder+'/03-l.sens'));
  B:=D12Bits(ReadData(Folder+'/03-r.sens'));
  { D24 фізично не стає D12 тільки тому, що має ту саму величину. }
  C:=EncodeNumericDecimal('1',24);
  DecodeT5M(C,Wide);
  C:=Wide[0];
  Save('bad-head.sens',EncodeT5M(Words(['10','11010',A,B,'01'])));
  Save('bad-d7-head.sens',EncodeT5M(Words(['10','0010110',A,B,'01'])));
  Save('bad-unary.sens',EncodeT5M(Words(['10','11011',A,'01'])));
  Save('bad-arity.sens',EncodeT5M(Words(['10','11011',A,B,A,'01'])));
  Save('bad-d24.sens',EncodeT5M(Words(['10','11011',A,C,'01'])));
  Save('bad-w13.sens',EncodeT5M(Words(['10','11011',A,'0000000000001','01'])));
  Save('bad-nested.sens',EncodeT5M(Words(['10','11011','10',A,'01',B,'01'])));
  Save('bad-two-roots.sens',EncodeT5M(Words(['10','11011',A,B,'01','0'])));
  Save('bad-no-list.sens',EncodeT5M(Words(['11011',A,B])));
  Save('bad-dotted.sens',EncodeT5M(Words(['10','11011',A,'11',B,'01'])));
  Save('bad-corrupt.sens',#$FF);
  Save('bad-padding.sens',#$F2);
  Save('bad-empty.sens','');
  Save('bad-projection.lisp',EncodeT5M(Words(['10','11011',A,B,'01'])));
  WriteLn('ФІЗИЧНИЙ-D5-ГЕНЕРАТОР: ',Count,' програм; 14 негативних джерел');
end.
