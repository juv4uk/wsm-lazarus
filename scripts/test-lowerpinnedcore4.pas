{ G6.130 — незалежний свідок: physical Core4 DEFINE/LAMBDA from pinned
  library executes through ALREADY MERGED TCore4Runtime, not fake host identity.
  CPU ELF exit low8 is compared with THIS source-derived physical result. }
program test_lowerpinnedcore4;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.lowerpinnedcore4,wsm.core4runtime;
var Folder:String;RT:TCore4Runtime;Count:SizeInt;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create(Why) end;

{ Borrowed filename/Data. Stream is locally allocated and always freed;
  physical .sens is written BYTE-EXACTLY, no human projection.
  Питання: чому T5M байт, не людська проєкція? Хто закриває Stream?
  Чому не зчитуємо число з UTF-8? }
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

{ Borrowed decimal fixture INPUT, not SENS law. The only expected SENS
  result comes from the ACTUAL pinned Core4 runtime for same physical call.
  Pinned method builds call from first exact D7 identifier IN library.
  Питання: хто визначає семантику бібліотечного DEFINE?
  Чому Oracle не інша Pascal-функція тотожності? Чому D24 exact?
  Як byte-for-byte response proves equal to original Arg? }
procedure CaseOf(const ID,Decimal:RawByteString);
var Arg,Call,Answer:RawByteString;W:TExactWords;Num:TExplicitNumeric;
begin
  Arg:=EncodeNumericDecimal(Decimal,24);
  DecodeT5M(Arg,W);
  Need((Length(W)=1) and (Length(W[0])=24),'змінено точний D24 формат');
  Num:=ReadNumericPhysical(Arg,24);
  Need(Num.DomainWidth=24,'помилка фізичного D24');
  Call:=PinnedCore4PhysicalCall('.',Arg);
  Answer:=RT.ExecutePhysicalCall(Call);
  Need(Answer=Arg,
    'реальний pinned Core4 runtime не повернув фізичний D24');
  Save(Folder+'/'+String(ID)+'-arg.sens',Arg);
  Save(Folder+'/'+String(ID)+'-call.sens',Call);
  Save(Folder+'/'+String(ID)+'-expected.sens',Answer);
  WriteLn(ID,#9,Decimal,#9,StrToInt(String(Decimal)) and 255);
  Inc(Count);
end;

{ Negative values are only malformed ARGUMENT source for a native lowering;
  actual pinned Core4 definition is NEVER replaced, nor retyped in Pascal. }
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  Need(ForceDirectories(Folder),'не створено тимчасову теку');
  RT:=TCore4Runtime.Create('.');
  try
    Need(RT.BindingCount=3,'очікуємо три початкові pinned DEFINE');
    Need(RT.BindingIsFunction(0),'перше pinned DEFINE не замикання');
    Count:=0;
    CaseOf('01','0');
    CaseOf('02','1');
    CaseOf('03','2');
    CaseOf('04','10');
    CaseOf('05','42');
    CaseOf('06','127');
    CaseOf('07','128');
    CaseOf('08','255');
    CaseOf('09','256');
    CaseOf('10','511');
    CaseOf('11','1023');
    CaseOf('12','2047');
    Need(Count=12,'неповна матриця бібліотечних аргументів');
    Save(Folder+'/bad-empty.sens','');
    Save(Folder+'/bad-padding.sens',#$F2);
    Save(Folder+'/bad-corrupt.sens',#$FF);
    Save(Folder+'/bad-d12.sens',EncodeNumericDecimal('10',12));
    Save(Folder+'/bad-d25.sens',EncodeT5M([
      '0000000000000000000001010']));
    Save(Folder+'/bad-d1.sens',EncodeT5M(['1']));
    Save(Folder+'/bad-two.sens',EncodeT5M(['000000000000000000001010',
      '000000000000000000001011']));
    Save(Folder+'/fake.lisp',
      '(тотожність 10)'+#10);
    WriteLn(StdErr,'PINNED-CORE4-ТІЛО-СВІДКИ: ',Count,
      ' фізичних викликів; 7 негативних');
  finally RT.Free end;
end.
