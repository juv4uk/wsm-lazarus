{ G6.195 — A/B першої компіляції фізичного D5:01000(D12).
  Лише вимір; OLD та VERIFIED використовують той самий emitter.
  1) Чому результати обох компіляторів повинні збігатися побайтово?
  2) Чому контекст створюємо для кожної форми заново?
  3) Чим час AOT відрізняється від часу виконання ELF?
  4) Чому фізична .sens не замінюється поверхнею .lisp? }
program benchmark_verifiedzero_first;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.verifiedwidecontext,wsm.irwidezero,wsm.elfgeometry;
const
  Count=16;Rounds=4;Samples=Count*Rounds;
  ClockMonotonic=1;
  Values:array[0..Count-1] of String=(
    '-2048','-1024','-17','-2','-1','0','1','2',
    '3','7','17','128','511','1024','2046','2047');
type
  TStamp=record Sec,Nano:Int64 end;
  TMode=(modeOld,modeVerified);
  TTimes=array[TMode,0..Samples-1] of Int64;
  TForms=array[0..Count-1] of RawByteString;
  EBenchmark=class(Exception);
function clock_gettime(Clock:LongInt;var S:TStamp):LongInt;
  cdecl;external 'c' name 'clock_gettime';
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EBenchmark.Create(Why) end;
{ CLOCK_MONOTONIC host ns, not SENS values or joules.
  1) Чому не використовуємо wall date?
  2) Які межі Int64?
  3) Чому ns не свідчить про енергію? }
function NowNs:Int64;
var S:TStamp;
begin
  Need(clock_gettime(ClockMonotonic,S)=0,'CLOCK_MONOTONIC відсутній');
  Need((S.Sec>=0) and (S.Sec<High(Int64) div 1000000000) and
       (S.Nano>=0) and (S.Nano<1000000000),'час поза межами');
  Result:=S.Sec*1000000000+S.Nano;
end;
function Elapsed(T:Int64):Int64;
begin
  Result:=NowNs-T;Need(Result>=0,'зворотний clock');
end;
{ Canonical packed D2/T5M words, D5 head exact width five,
  explicit signed D12 decoded from existing numericplane.
  Words owned by caller, Result owned RawByteString.
  1) Чому двійкові дужки є окремими словами?
  2) Чому W12 сам не є D12 законом?
  3) Чому не можна допустити ширину D24? }
function FormOf(const Head,Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,4);
  W[0]:='10';W[1]:=Head;W[2]:=Bits;W[3]:='01';
  Result:=EncodeT5M(W);
end;
function FormDecimal(const Number:String):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(
    EncodeNumericDecimal(RawByteString(Number),12),12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
       'потрібен ратифікований точний D12');
  Result:=FormOf('01000',N.ExactBits);
end;
function ExpectedD1(IsZero:Boolean):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);
  if IsZero then W[0]:='1' else W[0]:='0';
  Result:=EncodeT5M(W);
end;
{ Two independent existing compiler paths; return same ELF64 PIE.
  Context owned and freed in finally, without per-program cache.
  1) Чому два коди використовують один LowerVerifiedZero?
  2) Де помилки контексту не залишають stale state?
  3) Чому lowerer викликається лише раз? }
function Compile(const Physical,Root:RawByteString;
  Mode:TMode):RawByteString;
var C:TVerifiedWideContext;
begin
  if Mode=modeOld then
    Result:=BuildIRWideZeroELF(Physical,Root)
  else begin
    C:=TVerifiedWideContext.Create(Physical,Root);
    try Result:=BuildIRWideZeroFromContext(C)
    finally C.Free end;
  end;
end;
procedure WritePhysical(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  Need(Length(Data)>0,'відсутній фізичний результат');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
{ Median host-only, raw samples retained unmodified.
  1) Чому не задаємо наперед speedup?
  2) Чому порядок компіляції збалансований?
  3) Навіщо не лише медіана, а й сирі nanoseconds? }
function Median(const Times:TTimes;M:TMode):Int64;
var Sorted:array[0..Samples-1] of Int64;I,J:SizeInt;V:Int64;
begin
  for I:=0 to Samples-1 do Sorted[I]:=Times[M,I];
  for I:=1 to Samples-1 do begin
    J:=I;V:=Sorted[I];
    while J>0 do begin
      if Sorted[J-1]<=V then Break;
      Sorted[J]:=Sorted[J-1];Dec(J);
    end;
    Sorted[J]:=V;
  end;
  Result:=Sorted[Samples div 2-1]+
    (Sorted[Samples div 2]-Sorted[Samples div 2-1]) div 2;
end;
{ Report owned TStringList: JSON host data, not canonical SENS.
  Actual ratio determined by observed medians externally; NEVER
  substitute a presumed gain. No RAPL and no cold-start.
  1) Чому вимір не є доказом швидкості FPC self-compile?
  2) Чому JSON включає raw data?
  3) Чому повернення однакових ELF — окремий тест? }
procedure Report(const Path:String;const Times:TTimes);
var Doc:TStringList;I:SizeInt;Row:String;
begin
  Doc:=TStringList.Create;
  try
    Doc.Add('{');
    Doc.Add(' "mode":"FIRST_NEW_PROGRAM_PERSISTENT_HOST",');
    Doc.Add(' "energy":"NOT_MEASURED","cold_process":"NOT_MEASURED",');
    Doc.Add(' "sens_oracle":"NOT_CHECKED",');
    Doc.Add(' "count":64,"raw_ns":[');
    for I:=0 to Samples-1 do begin
      Row:=' {"cycle":'+IntToStr(I div Count)+
        ',"case":"'+Format('%.2d',[I mod Count+1])+
        '","legacy_ns":'+IntToStr(Times[modeOld,I])+
        ',"verified_ns":'+IntToStr(Times[modeVerified,I])+'}';
      if I<Samples-1 then Row:=Row+',';
      Doc.Add(Row);
    end;
    Doc.Add(' ],"median_legacy_ns":'+IntToStr(Median(Times,modeOld))+',');
    Doc.Add(' "median_verified_ns":'+IntToStr(Median(Times,modeVerified)));
    Doc.Add('}');
    Doc.SaveToFile(Path);
  finally Doc.Free end;
end;
{ Two compiles of each new physical program, four balanced cycles.
  Each ELF is verified, outputs saved for real Linux execution.
  4 invalid inputs are refused by BOTH paths, followed by valid
  recovery on fresh context, never a stale cache.
  1) Де доведений bit-for-bit parity?
  2) Чому обидві форми можуть мати різний час?
  3) Чому EOF і malformed байти не виконуються?
  4) Хто перевіряє реальний stdout ELF? }
procedure Run;
var Root,Folder,Name:String;Forms,First:TForms;
    Times:TTimes;T:Int64;I,Cycle,Index,Sample,N:SizeInt;
    OldELF,NewELF,Bad,Res:RawByteString;
    Mode:TMode;G:TELFGeometry;Rejected:Boolean;
begin
  Need(ParamCount=3,'аргументи: pinned-root каталог-ELF звіт.json');
  Root:=ParamStr(1);Folder:=ParamStr(2);
  Need(DirectoryExists(Folder),'немає каталогу ELF');
  for I:=0 to Count-1 do begin
    Forms[I]:=FormDecimal(Values[I]);
    for N:=0 to I-1 do Need(Forms[N]<>Forms[I],
      'дубль фізичної програми у вимірюванні');
    Name:=Format('%.2d',[I+1]);
    WritePhysical(Folder+'/'+Name+'.expected.sens',
      ExpectedD1(Values[I]='0'));
  end;
  for Cycle:=0 to Rounds-1 do
    for I:=0 to Count-1 do begin
      Index:=(I*5+Cycle*7) mod Count;
      Sample:=Cycle*Count+Index;
      if ((I+Cycle) mod 2)=0 then begin
        T:=NowNs;OldELF:=Compile(Forms[Index],
          RawByteString(Root),modeOld);
        Times[modeOld,Sample]:=Elapsed(T);
        T:=NowNs;NewELF:=Compile(Forms[Index],
          RawByteString(Root),modeVerified);
        Times[modeVerified,Sample]:=Elapsed(T);
      end else begin
        T:=NowNs;NewELF:=Compile(Forms[Index],
          RawByteString(Root),modeVerified);
        Times[modeVerified,Sample]:=Elapsed(T);
        T:=NowNs;OldELF:=Compile(Forms[Index],
          RawByteString(Root),modeOld);
        Times[modeOld,Sample]:=Elapsed(T);
      end;
      Need((OldELF=NewELF) and (Length(OldELF)>120),
           'порушено байтову тотожність legacy/verified ELF');
      VerifySENSELF64(NewELF,G);
      Need((G.Kind=3) and (G.Entry=120) and
           (G.FileBytes=Length(NewELF)),
           'немає перевіреного ELF64 PIE');
      Name:=Format('%.2d',[Index+1]);
      if Cycle=0 then begin
        First[Index]:=NewELF;
        WritePhysical(Folder+'/'+Name+'.elf',NewELF);
      end else
        Need(First[Index]=NewELF,
          'байти ELF відрізняються між компіляціями');
    end;
  for I:=0 to 3 do begin
    case I of
      0:Bad:='';
      1:Bad:=#$FF;
      2:Bad:=FormOf('01001','000000000000');
      3:Bad:=FormOf('01000','000000000000000000000000');
    end;
    for Mode:=Low(TMode) to High(TMode) do begin
      Rejected:=False;
      try Res:=Compile(Bad,RawByteString(Root),Mode);
      except on E:Exception do Rejected:=True end;
      Need(Rejected,'неправильний фізичний вхід пройшов admission');
      Res:=Compile(Forms[5],RawByteString(Root),Mode);
      Need(Res=First[5],'не відновлено стан після невдалої програми');
    end;
  end;
  Report(ParamStr(3),Times);
  Writeln('VERIFIEDZERO-AB-OK forms=16 samples=64 legacy=64 verified=64 negatives=4 recovery=8 parity=identical');
  Writeln('VERIFIEDZERO-AB-MEDIAN legacy_ns=',Median(Times,modeOld),
    ' verified_ns=',Median(Times,modeVerified));
end;
begin
  try Run;
  except on E:Exception do begin
    Writeln(ErrOutput,'VERIFIEDZERO-AB-FAIL: ',E.Message);
    ExitCode:=2;
  end end;
end.
