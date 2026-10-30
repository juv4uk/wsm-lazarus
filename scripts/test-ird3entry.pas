{ G6.128 — тест єдиного pinned exact D3 → existing verified ELF entrypoint.
  Жодного паралельного SENS evaluator, нових законів чи текстового
  dispatch. Позитивні профілі: точні цілі D2/T5M із канонічного codec.
  Негативи: structural, domain, unknown callable, nonphysical .lisp.
  Physical, Image — managed owned bytes per test; Profile host enum,
  НІКОЛИ не SENS key. HeapTrc має бути без незвільнених блоків.

  Питання: 1) чому всі профілі з одного ExactIR?
  2) чому невідома D3 голова не передається іншому backend?
  3) чому негатив має залишити Profile=dpNone?
  4) чому D7 текст не тотожний packed .sens?
  5) як це пов'язано із межами повного native compiler? }
program test_ird3entry;
{$mode objfpc}{$H+}
uses SysUtils,wsm.t5m,wsm.ird3entry,wsm.ircallwriter,
  wsm.irnestedeqcall,wsm.ircondcall,wsm.elfgeometry;
var Passed,Bad:SizeInt;

function Words(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I]
end;
procedure Check(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('G6_128_FAIL: '+Why) end;

procedure Positive(const Name:String;
  const Parts:array of RawByteString;Expected:TNativeD3Profile);
var Physical,Image,Old:RawByteString;Profile:TNativeD3Profile;
    Geom:TELFGeometry;
begin
  Physical:=EncodeT5M(Words(Parts));
  Profile:=dpNone;
  Image:=BuildVerifiedD3ELF(Physical,'external/sens',Profile);
  Check(Profile=Expected,Name+': неправильний host профіль');
  case Expected of
    dpSingleEq:Old:=BuildPhysicalD3CallELF(Physical,'external/sens');
    dpNestedEq:Old:=BuildPhysicalNestedEqCallELF(Physical,'external/sens');
    dpCond:Old:=BuildIRCondCallELF(Physical,'external/sens');
    else raise Exception.Create('невалідний positive profile')
  end;
  Check((Image=Old) and
    (Image=BuildVerifiedD3ELF(Physical,'external/sens',Profile)),
    Name+': ідентичні фізичні джерела не дали той самий машинний ELF');
  VerifySENSELF64(Image,Geom);
  Check((Geom.Kind=3) and (Geom.Entry=120) and
    (Geom.FileBytes=Length(Image)) and
    (Geom.MachineBytes>0) and (Geom.MachineBytes<=256),
    Name+': неправильний ELF64');
  Inc(Passed);
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Image:RawByteString;Profile:TNativeD3Profile;Rejected:Boolean;Why:String;
begin
  Image:='';Profile:=dpCond;Rejected:=False;Why:='';
  try Image:=BuildVerifiedD3ELF(Physical,'external/sens',Profile)
  except on E:Exception do begin Rejected:=True;Why:=E.Message end end;
  Check(Rejected and (Image='') and (Profile=dpNone) and
    (Length(Why)>5),Name+': не атомарний pinned fail-closed');
  Inc(Bad);
end;
procedure Negative(const Name:String;const Parts:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(Words(Parts))) end;

begin
  Passed:=0;Bad:=0;
  Positive('eq-true',['10','101','1','1','01'],dpSingleEq);
  Positive('eq-false',['10','101','1','0','01'],dpSingleEq);
  Positive('nested-eq',['10','101',
    '10','101','1','1','01',
    '10','101','0','0','01','01'],dpNestedEq);
  Positive('nested-unequal',['10','101',
    '10','101','1','0','01',
    '10','101','0','0','01','01'],dpNestedEq);
  Positive('cond-empty',['10','110','01'],dpCond);
  Positive('cond-eq',['10','110','10','10','101','1','1','01',
    '10','101','0','1','01','01','01'],dpCond);
  Positive('cond-two',['10','110','10','0','1','01',
    '10','10','101','0','0','01','1','01','01'],dpCond);

  Negative('інша-голова',['10','001','1','01']);
  Negative('невідома-голова',['10','111','0','0','01']);
  Negative('D7-голова',['10','0010110','1','01']);
  Negative('D12-голова',['10','000000000000','1','01']);
  Negative('eq-one-arg',['10','101','1','01']);
  Negative('eq-three-args',['10','101','1','1','0','01']);
  Negative('eq-D7-right',['10','101','1','0010110','01']);
  Negative('eq-D3-empty',['10','101','000','1','01']);
  Negative('nested-one-side',['10','101','10','101','1','1','01',
    '0','01']);
  Negative('nested-wrong-head',['10','101',
    '10','111','1','1','01','10','101','0','0','01','01']);
  Negative('cond-three',['10','110','10','0','1','01',
    '10','0','1','01','10','1','0','01','01']);
  Negative('cond-malformed',['10','110','10','1','01','01']);
  Negative('two-roots',['10','101','1','1','01','0']);
  Negative('root-atom',['1']);
  NegativeRaw('empty','');
  NegativeRaw('not-t5m',#$F3);
  NegativeRaw('projection-text','(тотожне? так так)'+#10);
  Check((Passed=7) and (Bad=17),'неповні позитивні/негативні свідки');
  WriteLn('G6_128_PASS PROFILE=3 PHYSICAL=7 NEGATIVE=17');
end.
