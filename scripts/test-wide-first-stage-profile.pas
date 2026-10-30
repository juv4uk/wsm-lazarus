{ G6: первинний РОЗКЛАД часу реально перевірених T5M→WideIR→ELF.
  Не новий компілятор, закон, кеш, evaluator чи метрика енергії.
  Окремі етапи вимірюються незалежно; час end-to-end НЕ є їх сумою. }
program test_wide_first_stage_profile;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.physloc,wsm.domain,wsm.bind,
     wsm.wideir,wsm.wideirguard,wsm.irwidefront,wsm.elfgeometry;
const ClockMonotonic=1; ProgramCount=16; Rounds=3;
type
  TTimespec=record Sec:Int64;NSec:Int64 end;
  EProfile=class(Exception);
function clock_gettime(ClockId:LongInt;var Time:TTimespec):LongInt; cdecl;
  external 'c' name 'clock_gettime';

{ QWord — host монотонні наносекунди, НЕ SENS D12 число.
  Ніяких алокацій, час не є свідком семантичної правильності.
  1) Чому цей час не можна називати джоулями?
  2) Чому NSec має бути менш ніж 10^9?
  3) Що буде при збої системного годинника? }
function NanoStamp:QWord;
var T:TTimespec;
begin
  if clock_gettime(ClockMonotonic,T)<>0 then
    raise EProfile.Create('недоступний монотонний годинник');
  if (T.Sec<0) or (T.NSec<0) or (T.NSec>=1000000000) then
    raise EProfile.Create('некоректний монотонний час');
  Result:=QWord(T.Sec)*1000000000+QWord(T.NSec);
end;

{ Позичений шлях .sens; Result — власний обмежений фізичний T5M.
  F володіє дескриптором тільки до кінця цієї процедури.
  1) Чому перевірка суфікса не є достатнім допуском T5M?
  2) Чому 65536 байтів — host quota, не мовний закон?
  3) Хто звільняє байтовий буфер Result? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise EProfile.Create('потрібен фізичний .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EProfile.Create('порожній або завеликий T5M');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Машинний ELF — managed bytes після VerifySENSELF64.
  Тимчасова ціль належить лише ізольованому тестовому каталогу.
  1) Чому цей запис не замінює production no-clobber публікацію?
  2) Хто володіє Image?
  3) Чому тут не використовується українська проєкція .lisp? }
procedure SaveImage(const Path:String;const Image:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Image[1],Length(Image));
  finally F.Free end;
end;

{ Фізичні байти, таблиці, IR і ELF — ЛОКАЛЬНІ керовані об'єкти
  рівно одного відліку. Кожне BuildVerifiedWideELF має власний pinned
  scope (PR #847); в кожній новій програмі перший load — фізичний.
  Ступені ДО компіляції — окремі виміри, не частини compile_ns.
  1) Чому BuildWideIR іще раз декодує T5M?
  2) Чому guard не можна прибрати для швидкості?
  3) Як відрізняється compile_ns від суми stage_ns?
  4) Чому одноразовий scope закривається навіть на винятку?
  5) Чому виконання ELF перевіряє окремий незалежний скрипт? }
procedure ProfileOne(const Name,InputDir,OutputDir:String;Round:SizeInt);
var Physical,Image:RawByteString;
    Words:TExactWords;Spans:TPhysicalWordSpans;
    Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Geom:TELFGeometry;
    T0,T1,DDecode,DDomains,DWide,DGuard,DCompile:QWord;
begin
  Physical:=ReadPhysical(InputDir+'/'+Name+'.sens');
  T0:=NanoStamp;
  DecodeT5MWithLocations(Physical,Words,Spans);
  T1:=NanoStamp;DDecode:=T1-T0;

  T0:=NanoStamp;
  LoadPinnedDomains('external/sens',Tables);
  T1:=NanoStamp;DDomains:=T1-T0;

  T0:=NanoStamp;
  BuildWideIR(Physical,Tables,IR);
  T1:=NanoStamp;DWide:=T1-T0;

  T0:=NanoStamp;
  VerifyWideIRStructure(IR,Stats);
  T1:=NanoStamp;DGuard:=T1-T0;
  if (Stats.Roots<>1) or (Length(IR.Roots)<>1) then
    raise EProfile.Create('профіль потребує один D2 корінь');

  T0:=NanoStamp;
  BeginPinnedLoadScope;
  try
    Image:=BuildVerifiedWideELF(Physical,'external/sens');
  finally EndPinnedLoadScope end;
  T1:=NanoStamp;DCompile:=T1-T0;
  VerifySENSELF64(Image,Geom);
  if (Geom.Kind<>3) or (Geom.Entry<>120) or
     (Geom.FileBytes<>Length(Image)) then
    raise EProfile.Create('ELF64 не пройшов геометрію');
  if Round=1 then SaveImage(OutputDir+'/'+Name+'.elf',Image);
  WriteLn(Name,#9,Round,#9,DDecode,#9,DDomains,#9,
          DWide,#9,DGuard,#9,DCompile,#9,Length(Image));
end;

{ E.Message — host diagnostics, not a semantic value. UTF-8 bytes are
  written to borrowed stderr FD; the THandleStream wrapper is owned here.
  1) Why must no failure bytes reach ELF stdout?
  2) Which object owns the descriptor versus its wrapper?
  3) Why is a host diagnostic not a D7 law? }
procedure SayFailure(const Problem:String);
var Err:THandleStream; B:RawByteString;
begin
  B:=RawByteString(UTF8Encode(UnicodeString('ЕТАПИ-ПРОВАЛ: ')))+
     RawByteString(Problem)+#10;
  Err:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(B[1],Length(B));
  finally Err.Free end;
end;

procedure Run;
var InputDir,OutputDir,Name,Physical: String;
    R,I,Index:SizeInt;Image:RawByteString;
    G:TELFGeometry;
begin
  {$IFNDEF LINUX} raise EProfile.Create('потрібен Linux'); {$ENDIF}
  {$IFNDEF CPUX86_64} raise EProfile.Create('потрібен x86-64'); {$ENDIF}
  if (ParamCount=2) and
     (RawByteString(ParamStr(1))=RawByteString(UTF8Encode('--негатив'))) then
  begin
    Physical:=String(ReadPhysical(ParamStr(2)));
    Image:=BuildVerifiedWideELF(RawByteString(Physical),'external/sens');
    VerifySENSELF64(Image,G);
    raise EProfile.Create('негатив помилково допущено');
  end;
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>RawByteString(UTF8Encode('--етапи'))) then
    raise EProfile.Create('виклик: --етапи фізичні/ результати/');
  InputDir:=ParamStr(2);OutputDir:=ParamStr(3);
  if not DirectoryExists(OutputDir) then
    raise EProfile.Create('немає тимчасового каталогу результатів');
  for R:=1 to Rounds do begin
    for I:=1 to ProgramCount do begin
      if (R mod 2)=0 then Index:=ProgramCount+1-I else Index:=I;
      Name:=Format('%.2d',[Index]);
      ProfileOne(Name,InputDir,OutputDir,R);
    end;
  end;
end;

begin
  ExitCode:=0;
  try
    Run;
  except on E:Exception do begin
    SayFailure(E.Message);
    ExitCode:=2;
  end end;
end.
