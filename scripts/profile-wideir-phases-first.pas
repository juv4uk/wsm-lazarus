{ G6 — окреме вимірювання етапів першої компіляції 16 різних .sens.
  НЕ compiler, НЕ semantic evaluator, НЕ альтернатива pinned Contract 12.0.
  Профайлер лише ВИКЛИКАЄ чинні FPC компоненти, нічого не кешує.
  Input: borrowed фізичні T5M файли; Samples/IR/ELF: owned FPC-managed.
  Profile JSON містить raw monotonic ns, а не вигадану енергію.
  1) Чому не додаємо незалежні часи етапів як точний час компіляції?
  2) Чому кожний вхід має іншу точну T5M послідовність?
  3) Чим вимір всередині процесу відрізняється від cold process?
  4) Чому T5M не можна зводити до текстового .lisp?
  5) Хто доводить фактичне виконання створеного ELF? }
program profile_wideir_phases_first;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.irwidefront,wsm.elfgeometry;
const
  Cases=16;
  Rounds=4;
  Count=Cases*Rounds;
  CLOCK_MONOTONIC=1;
type
  TClockStamp=record Sec,Nano: Int64;end;
  TPhase=(phDecode,phPinned,phWideIR,phVerify,phCompiler);
  TMeasurements=array[TPhase,0..Count-1] of Int64;
  TImages=array[0..Cases-1] of RawByteString;
  TPrograms=array[0..Cases-1] of RawByteString;
  EProfileError=class(Exception);
function clock_gettime(clockid:LongInt;var Stamp:TClockStamp):LongInt;
  cdecl;external 'c' name 'clock_gettime';

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EProfileError.Create(Why);
end;

{ Host-only monotonic clock: NOT a SENS number or T5M token.
  Returned Int64 ns is owned scalar; no allocation.
  1) Чому clock_gettime monotonic, а не настінна дата?
  2) Чому не можна трактувати ns як Joules?
  3) Чому діапазон Int64 перевіряємо? }
function NowNs:Int64;
var C:TClockStamp;
begin
  Need(clock_gettime(CLOCK_MONOTONIC,C)=0,
       'не вдалося прочитати CLOCK_MONOTONIC');
  Need((C.Sec>=0) and (C.Nano>=0) and (C.Nano<1000000000) and
       (C.Sec<High(Int64) div 1000000000),
       'переповнення monotonic часу');
  Result:=C.Sec*1000000000+C.Nano;
end;

function Duration(Start:Int64):Int64;
var Finish:Int64;
begin
  Finish:=NowNs;
  Need(Finish>=Start,'зворотний монотонний час');
  Result:=Finish-Start;
end;

{ Read full physical packed bytes, own the returned RawByteString.
  TFileStream owned temporarily and released even after IO error.
  No width, bit-order, domain or language law inferred from bytes.
  1) Чому не відкриваємо .lisp?
  2) Хто відхиляє некоректний T5M?
  3) Чому ліміт розміру перед SetLength?
  4) Коли TFileStream звільняється? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  Need(ExtractFileExt(Path)='.sens','потрібен фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=65536),
         'відсутня або завелика фізична програма');
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  Need(Length(Bytes)>0,'заборонено писати порожній ELF');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

{ Median over 64 raw nanosecond samples, no speed claim. Sorted
  local host-only clone (owned stack), original measurements unchanged.
  1) Чому медіана робастніша до випадкових CI spikes?
  2) Чому в JSON також потрібні всі сирі числа?
  3) Чому не встановлено поріг прискорення? }
function Median(const M:TMeasurements;P:TPhase):Int64;
var Sorted:array[0..Count-1] of Int64;I,J:SizeInt;V:Int64;
begin
  for I:=0 to Count-1 do Sorted[I]:=M[P,I];
  for I:=1 to Count-1 do begin
    V:=Sorted[I];J:=I;
    while (J>0) and (Sorted[J-1]>V) do begin
      Sorted[J]:=Sorted[J-1];Dec(J);
    end;
    Sorted[J]:=V;
  end;
  Result:=Sorted[Count div 2-1]+
          (Sorted[Count div 2]-Sorted[Count div 2-1]) div 2;
end;

procedure WriteJson(const Path:String;const M:TMeasurements);
const Keys:array[TPhase] of String=(
  't5m_decode_encode_ns','pinned_load_ns','wideir_build_ns',
  'wideir_verify_ns','full_compiler_ns');
var Doc:TStringList;I:SizeInt;P:TPhase;Row:String;
begin
  Doc:=TStringList.Create;
  try
    Doc.Add('{');
    Doc.Add('  "mode":"FIRST_DISTINCT_NO_OUTPUT_CACHE",');
    Doc.Add('  "host":"MONOTONIC_IN_PROCESS",');
    Doc.Add('  "non_additive":true,');
    Doc.Add('  "cold_process":"NOT_MEASURED",');
    Doc.Add('  "independent_sens_oracle":"NOT_MEASURED",');
    Doc.Add('  "energy":"NOT_MEASURED",');
    Doc.Add('  "sample_count":'+IntToStr(Count)+',');
    Doc.Add('  "raw_ns":[');
    for I:=0 to Count-1 do begin
      Row:='    {"cycle":'+IntToStr(I div Cases)+
        ',"case":"'+Format('%.2d',[(I mod Cases)+1])+'"';
      for P:=Low(TPhase) to High(TPhase) do
        Row:=Row+',"'+Keys[P]+'":'+IntToStr(M[P,I]);
      Row:=Row+'}';
      if I<Count-1 then Row:=Row+',';
      Doc.Add(Row);
    end;
    Doc.Add('  ],');
    Row:='  "median_ns":{';
    for P:=Low(TPhase) to High(TPhase) do begin
      if P<>Low(TPhase) then Row:=Row+',';
      Row:=Row+'"'+Keys[P]+'":'+IntToStr(Median(M,P));
    end;
    Doc.Add(Row+'}');
    Doc.Add('}');
    Doc.SaveToFile(Path);
  finally Doc.Free end;
end;

{ Profiles *isolated* mechanics AND independent complete compilation.
  It does NOT subtract times or pass the pre-built IR into backend:
  that would silently bypass backend admission before verified API.
  A separate new SENS program is validated each input; existing full
  compiler is the only emitter. No shared persistent scope/cache.
  1) Чому LoadPinnedDomains викликаємо для кожного нового входу?
  2) Чому DecodeT5MWithLocations усередині BuildWideIR дублює роботу?
  3) Чому VerifyWideIRStructure не можна просто викреслити?
  4) Чому байти ELF мають збігатися у чотирьох незалежних циклах?
  5) Чому кінцеве машинне виконання тестує зовнішній .sh? }
procedure Run;
var Root,Fixtures,Outputs,Report,Name:String;
    Programmes:TPrograms;Images:TImages;
    Measurements:TMeasurements;Words:TExactWords;
    Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    ELF:RawByteString;G:TELFGeometry;
    Cycle,I,Index,Sample:SizeInt;T:Int64;
    Rejected:Boolean;Bad:RawByteString;
begin
  Need(ParamCount=4,
       'виклик: профайлер pinned-root фізичні-входи каталог-elf звіт.json');
  Root:=ParamStr(1);
  Fixtures:=ParamStr(2);
  Outputs:=ParamStr(3);
  Report:=ParamStr(4);
  Need(DirectoryExists(Outputs),'каталог ELF має існувати');
  for I:=0 to Cases-1 do begin
    Name:=Format('%.2d',[I+1]);
    Programmes[I]:=ReadPhysical(Fixtures+'/'+Name+'.sens');
    for Index:=0 to I-1 do
      Need(Programmes[Index]<>Programmes[I],
           'потрібні 16 фізично різних canonical програм');
  end;
  for Cycle:=0 to Rounds-1 do
    for I:=0 to Cases-1 do begin
      Index:=(I*5+Cycle*7) mod Cases;
      Sample:=Cycle*Cases+Index;
      T:=NowNs;
      DecodeT5M(Programmes[Index],Words);
      Need(EncodeT5M(Words)=Programmes[Index],
           'відхилено неканонічне T5M');
      Measurements[phDecode,Sample]:=Duration(T);
      T:=NowNs;
      LoadPinnedDomains(RawByteString(Root),Tables);
      Measurements[phPinned,Sample]:=Duration(T);
      T:=NowNs;
      BuildWideIR(Programmes[Index],Tables,IR);
      Measurements[phWideIR,Sample]:=Duration(T);
      T:=NowNs;
      VerifyWideIRStructure(IR,Stats);
      Measurements[phVerify,Sample]:=Duration(T);
      Need((Stats.Roots=1) and (Stats.Nodes>=3),
           'помилково допущений WideIR');
      T:=NowNs;
      ELF:=BuildVerifiedWideELF(Programmes[Index],RawByteString(Root));
      Measurements[phCompiler,Sample]:=Duration(T);
      VerifySENSELF64(ELF,G);
      Need((G.Kind=3) and (G.Entry=120) and
           (G.FileBytes=Length(ELF)),
           'повний компілятор повернув не ELF64 PIE');
      Name:=Format('%.2d',[Index+1]);
      if Cycle=0 then begin
        Images[Index]:=ELF;
        SaveBytes(Outputs+'/'+Name+'.elf',ELF);
      end else
        Need(Images[Index]=ELF,'порушено байтову ідентичність ELF');
    end;

  { Must reject invalid physical inputs and then still compile a valid
    input without residual state. This is a control, NOT oracle SENS. }
  for I:=0 to 1 do begin
    Rejected:=False;
    if I=0 then Bad:='' else Bad:=#$FF;
    try
      ELF:=BuildVerifiedWideELF(Bad,RawByteString(Root));
    except on E:Exception do Rejected:=True end;
    Need(Rejected,'компілятор прийняв некоректне фізичне джерело');
    ELF:=BuildVerifiedWideELF(Programmes[0],RawByteString(Root));
    Need(ELF=Images[0],'залишковий стан після відмови');
  end;
  WriteJson(Report,Measurements);
  Writeln('ФАЗИ-WIDEIR-ГАРАЗД cases=16 rounds=4 raw=64 elf-identical=yes negatives=2 recovery=2 oracle=NOT-CHECKED energy=NOT-MEASURED');
  Writeln('ФАЗИ-WIDEIR-МЕДІАНИ-НС t5m=',Median(Measurements,phDecode),
    ' pinned=',Median(Measurements,phPinned),
    ' wideir=',Median(Measurements,phWideIR),
    ' verify=',Median(Measurements,phVerify),
    ' full=',Median(Measurements,phCompiler));
end;

begin
  try Run;
  except on E:Exception do begin
    Writeln(ErrOutput,'ФАЗИ-WIDEIR-ВІДМОВА: ',E.Message);
    ExitCode:=2;
  end end;
end.
