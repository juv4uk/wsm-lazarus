{ G6.265 — verified pinned D5 anchor → один dynamic native ELF64.
  НЕ новий evaluator: FPC будує тільки фізичні T5M fixtures і machine
  ELF з раніше перевіреного pinned WideIR; результат обчислює CPU.
  Owned RawByteString/TStringList/TFileStream із локальним lifetime.
  1) Чим одна динамічна ELF-машина відрізняється від 12 AOT машин?
  2) Чому T5M runtime input містить два окремі фізичні атоми?
  3) Чому переповнення D24→D48 очікує exit2 без stdout?
  4) Хто перевіряє семантичний закон форми якоря?
  5) Чому локальний NumericAdd не є незалежним SENS REPL? }
program test_elfd24stream;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
     wsm.elfd24stream,wsm.elfgeometry;
type TCase=record Left,Right:RawByteString end;
const
  Positives:array[0..11] of TCase=(
    (Left:'0';Right:'0'),
    (Left:'65535';Right:'1'),
    (Left:'65536';Right:'65535'),
    (Left:'-1';Right:'1'),
    (Left:'-65536';Right:'-1'),
    (Left:'8388607';Right:'0'),
    (Left:'-8388608';Right:'0'),
    (Left:'-8388608';Right:'1'),
    (Left:'8388606';Right:'1'),
    (Left:'-123456';Right:'234567'),
    (Left:'32767';Right:'32768'),
    (Left:'-8388607';Right:'-1')
  );
  Overflows:array[0..3] of TCase=(
    (Left:'8388607';Right:'1'),
    (Left:'8388607';Right:'8388607'),
    (Left:'-8388608';Right:'-1'),
    (Left:'-8388608';Right:'-8388608')
  );
var Folder,Root:String;Candidate,SourceAnchor,Exe,Original:RawByteString;
    P:TExplicitNumeric;G:TELFGeometry;
    Cases:TStringList;
    I,Rejected:Integer;
    NumZero,NumOne,NumMax,Small:TExplicitNumeric;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('Д24-ПОТІК-ПОМИЛКА: '+Why);
end;
procedure Save(const Filename:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Filename,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
function Pack(const A:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(A));
  for J:=0 to High(A) do W[J]:=A[J];
  Result:=EncodeT5M(W);
end;
function Atom(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(Decimal,24);
  N:=ReadNumericPhysical(Result,24);
  Need(N.DomainWidth=24,'втрачено D24 exact width');
end;
procedure RejectSource(const Bad:RawByteString;const Name:String);
var R:RawByteString;Failed:Boolean;
begin
  Failed:=False;
  try
    R:=BuildD24StreamAddELF(Bad,Root);
  except
    on E:Exception do begin
      Need(E.Message<>'','відсутня діагностика '+Name);
      Failed:=True;
    end;
  end;
  Need(Failed,'допущено некоректний anchor '+Name);
  Inc(Rejected);
end;

procedure EmitCase(const Prefix:String;C:TCase;IsOverflow:Boolean);
var L,R,V:RawByteString;N:TExplicitNumeric;
begin
  L:=Atom(C.Left);R:=Atom(C.Right);
  Save(Prefix+'.input.sens',L+R);
  Need(Length(L+R)=10,'дві фізичні D24 мають 10 байтів');
  if not IsOverflow then begin
    V:=AddNumericPhysical(L,R,24);
    N:=ReadNumericPhysical(V,24);
    Need(N.DomainWidth=24,'відхилено допустиму D24 суму');
    Save(Prefix+'.expected.sens',V);
    Cases.Add(Prefix+#9+C.Left+#9+C.Right+#9+
      RenderNumericDecimal(N));
  end;
end;

begin
  Need(ParamCount=2,'потрібні pinned authority і приватний каталог');
  Root:=ParamStr(1);Folder:=ParamStr(2);
  Need(DirectoryExists(Root) and DirectoryExists(Folder),
    'немає authority root або вихідного каталогу');
  Cases:=TStringList.Create;
  try
    NumZero:=ReadNumericPhysical(Atom('0'),24);
    NumOne:=ReadNumericPhysical(Atom('1'),24);
    NumMax:=ReadNumericPhysical(Atom('8388607'),24);
    Small:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12);
    SourceAnchor:=Pack(['10','01010',NumZero.ExactBits,
      NumZero.ExactBits,'01']);
    Save('anchor.sens',SourceAnchor);
    Exe:=BuildD24StreamAddELF(SourceAnchor,Root);
    VerifySENSELF64(Exe,G);
    Need((G.Kind=3) and (G.Entry=120) and
         (G.FileBytes=Length(Exe)) and
         (G.MachineBytes>0),'неверифікований ELF64');
    Save('dynamic.elf',Exe);
    Original:=BuildD24StreamAddELF(SourceAnchor,Root);
    Need(Exe=Original,'дві побудови ELF не є детермінованими');
    for I:=Low(Positives) to High(Positives) do begin
      if I+1<10 then EmitCase('ok-0'+IntToStr(I+1),Positives[I],False)
      else EmitCase('ok-'+IntToStr(I+1),Positives[I],False);
    end;
    for I:=Low(Overflows) to High(Overflows) do
      EmitCase('overflow-0'+IntToStr(I+1),Overflows[I],True);
    Need(Cases.Count=12,'неповний набір динамічних обчислень');
    Cases.SaveToFile(Folder+'/cases.tsv');
    Save('invalid-empty.sens','');
    Save('invalid-short.sens',Copy(Atom('0')+Atom('1'),1,9));
    Save('invalid-long.sens',Atom('0')+Atom('1')+#0);
    Save('invalid-prefix.sens',#$FF+Copy(Atom('0'),2,4)+Atom('1'));
    Save('invalid-suffix.sens',Copy(Atom('0'),1,4)+#$FF+Atom('1'));
    Save('invalid-second.sens',Atom('0')+#$FF+Copy(Atom('1'),2,4));

    Rejected:=0;
    P:=NumZero;
    RejectSource(Pack(['10','01011',P.ExactBits,P.ExactBits,'01']),
      'інша голова D5');
    RejectSource(Pack(['10','01010',P.ExactBits,'01']),
      'неповна арність');
    RejectSource(Pack(['10','01010',P.ExactBits,
      Small.ExactBits,'01']),
      'інший домен W12');
    RejectSource(#$FF,'пошкоджений canonical T5M');
    RejectSource('','порожній anchor');
    RejectSource(Pack(['10','01010',
      NumMax.ExactBits,NumOne.ExactBits,'01']),
      'D48 overflow у source');
    Need(Rejected=6,'потрібно шість негативних джерел');
    WriteLn('D24-STREAM-ФІКСТУРИ-ГОТОВО source=1 ELF64=1 ',
      'inputs=12 overflow=4 invalid=6 bad-anchors=6 ',
      'reproducible=1 oracle=LOCAL-PINNED energy=NOT-MEASURED');
  finally Cases.Free end;
end.
