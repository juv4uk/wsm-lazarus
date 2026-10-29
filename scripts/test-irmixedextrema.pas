{ G6.105 — 16 physical D2/T5M nested min/max programs; fixture
  expectation is host-only, never replaces independent pinned SENS oracle. }
program test_irmixedextrema;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
const
  Bases:array[0..3] of Integer=(-7,2047,-2048,0);
  Rights:array[0..3,0..3] of Integer=
    ((-3,5,-1,17),(-2048,2046,0,-11),(2047,-2048,123,-17),(0,0,-1,1));
var Dir:String;Cases:Integer;

function Bits12(Value:Integer):RawByteString;
var I:Integer;
begin
  if Value<0 then Value:=4096+Value;
  Result:=StringOfChar('0',12);
  for I:=12 downto 1 do begin
    if (Value and 1)<>0 then Result[I]:='1';
    Value:=Value shr 1;
  end;
end;

{ Saved bytes are owned packed physical T5M. FPC stream freed on
  exception; path is only host metadata. Why is .lisp not binary?
  What exact width do 12 bit strings have? What closes file? }
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

function Pack(const Items:array of RawByteString):RawByteString;
var W:TExactWords;I:Integer;
begin
  SetLength(W,Length(Items));
  for I:=0 to High(Items) do W[I]:=Items[I];
  Result:=EncodeT5M(W);
end;

{ Pattern only changes host test cases, NOT SENS semantic dispatch.
  110101,110111 are pinned exact D6 keys verified by compiler.
  How is min distinguished from max? Why W6 not English name?
  Why does user .lisp remain a projection? }
function Head(I,Pattern:Integer):RawByteString;
begin
  if ((I+Pattern) mod 2)=0 then Result:='110101'
  else Result:='110111';
end;

function ProgramBytes(Depth,Pattern:Integer):RawByteString;
var W:TExactWords;K,I:Integer;
begin
  SetLength(W,4*Depth+1);K:=0;
  for I:=0 to Depth-1 do begin
    W[K]:='10';Inc(K);
    W[K]:=Head(I,Pattern);Inc(K);
  end;
  W[K]:=Bits12(Bases[Pattern]);Inc(K);
  W[K]:=Bits12(Rights[Pattern,0]);Inc(K);
  for I:=Depth-1 downto 0 do begin
    W[K]:='01';Inc(K);
    if I>0 then begin
      W[K]:=Bits12(Rights[Pattern,Depth-I]);Inc(K);
    end;
  end;
  if K<>Length(W) then raise Exception.Create('хибна кількість слів');
  Result:=EncodeT5M(W);
end;

procedure Reject(const LabelText:String;const Bytes:RawByteString);
begin Save(Dir+'/'+LabelText+'.sens',Bytes) end;

procedure Run;
var D,P,I,Want,Right:Integer; K:String;Nested,TextOps,Source:RawByteString;
    Physical:TExactWords;W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(3);
  Cases:=0;
  for D:=1 to 4 do for P:=0 to 3 do begin
    K:=IntToStr(D)+'-'+IntToStr(P);
    Source:=ProgramBytes(D,P);
    Save(Dir+'/'+K+'.sens',Source);
    Want:=Bases[P];
    Nested:=IntToStr(Want);
    TextOps:='';
    for I:=D-1 downto 0 do begin
      Right:=Rights[P,D-1-I];
      if Head(I,P)='110101' then begin
        if Right<Want then Want:=Right;
        Nested:='(найменше '+Nested+' '+IntToStr(Right)+')';
        TextOps:=TextOps+'cmovg'+#10;
      end else begin
        if Right>Want then Want:=Right;
        Nested:='(найбільше '+Nested+' '+IntToStr(Right)+')';
        TextOps:=TextOps+'cmovl'+#10;
      end;
    end;
    Save(Dir+'/'+K+'.expected.sens',EncodeNumericDecimal(IntToStr(Want),12));
    Save(Dir+'/'+K+'.lisp',Nested+#10);
    Save(Dir+'/'+K+'.ops',TextOps);
    Inc(Cases);
  end;
  { Independent negative physical programs; compiler must reject each. }
  Reject('bad-depth5',Pack(['10','110101','10','110111','10',
    '110101','10','110111','10','110101',
    Bits12(0),Bits12(0),'01',Bits12(0),'01',Bits12(0),
    '01',Bits12(0),'01',Bits12(0),'01']));
  Reject('bad-source-d1',Pack(['1']));
  Reject('bad-source-d7',Pack(['0010110']));
  Reject('bad-source-d24',Pack([StringOfChar('0',23)+'1']));
  Reject('bad-corrupt',#$FF);
  Reject('bad-empty','');
  DecodeT5M(ProgramBytes(2,1),W);
  Physical:=Copy(W,0,Length(W)-1);
  Reject('bad-unclosed',EncodeT5M(Physical));
  SetLength(Physical,Length(W)+1);
  for I:=0 to High(W) do Physical[I]:=W[I];
  Physical[High(Physical)]:='0';
  Reject('bad-two-roots',EncodeT5M(Physical));
  Physical:=Copy(W,0,Length(W));
  Physical[1]:='010100';
  Reject('bad-head-d6',EncodeT5M(Physical));
  Physical[1]:='11010';
  Reject('bad-head-d5',EncodeT5M(Physical));
  Physical[1]:='0010110';
  Reject('bad-head-d7',EncodeT5M(Physical));
  Physical:=Copy(W,0,Length(W));
  Physical[3]:='010100';
  Reject('bad-nested-head',EncodeT5M(Physical));
  Physical:=Copy(W,0,Length(W));
  Physical[4]:='1';
  Reject('bad-left-d1',EncodeT5M(Physical));
  Physical[4]:='0010110';
  Reject('bad-left-d7',EncodeT5M(Physical));
  Physical[4]:=StringOfChar('0',23)+'1';
  Reject('bad-left-d24',EncodeT5M(Physical));
  Physical:=Copy(W,0,Length(W));
  Physical[5]:='1';
  Reject('bad-right-d1',EncodeT5M(Physical));
  Physical[5]:='0010110';
  Reject('bad-right-d7',EncodeT5M(Physical));
  Physical[5]:=StringOfChar('0',23)+'1';
  Reject('bad-right-d24',EncodeT5M(Physical));
  if Cases<>16 then Halt(3);
  WriteLn('G6.105-FIXTURES-OK positive=16 negative=18');
end;
begin
  try Run except on E:Exception do begin
    WriteLn(StdErr,'G6.105-FIXTURES-FAIL ',E.Message);Halt(2)
  end end;
end.
