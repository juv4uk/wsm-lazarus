{ G6 / хвиля 1 / агент Б — незалежне stage-профілювання.
  Фізичні байти, перевірені pinned таблиці та native compiler незмінні.
  Цей вимір ЗНОВУ робить етапи перед повною компіляцією, тому значення
  стадій НЕ можна складати і видавати за тривалість першої компіляції.
  Ніяких мовних назв у диспетчеризації та ніякого нового evaluator. }
program test_once_ir_stage_profile;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.domain,
     wsm.wideir, wsm.wideirguard, wsm.irwidefront, wsm.elfgeometry;

const
  Samples=16;
  Repeats=6;
  MaxPhysical=65536;
  MonotonicClock=1;
type
  EStageProfile=class(Exception);
  TClockSpec=record
    Seconds:Int64;
    Nanoseconds:Int64;
  end;

function clock_gettime(ClockId:LongInt;var Value:TClockSpec):LongInt;
  cdecl;external 'c' name 'clock_gettime';

{ Системний годинник — ЛИШЕ host-time; не число D12+.
  ClockSpec — stack value, Result — монотонні наносекунди QWord.
  1. Чому не можна замінити монотонний час системною датою?
  2. Що станеться за помилки системного виклику?
  3. Чому потрібні сирі ns, а не лише «прискорення»? }
function NowNs:QWord;
var Clock:TClockSpec;
begin
  if clock_gettime(MonotonicClock,Clock)<>0 then
    raise EStageProfile.Create('не працює монотонний годинник');
  if (Clock.Seconds<0) or (Clock.Nanoseconds<0) or
     (Clock.Nanoseconds>=1000000000) then
    raise EStageProfile.Create('некоректний monotonic timestamp');
  Result:=QWord(Clock.Seconds)*1000000000+QWord(Clock.Nanoseconds);
end;

procedure Require(OK:Boolean;const Reason:String);
begin
  if not OK then raise EStageProfile.Create(Reason);
end;

{ Borrowed шлях до однієї packed фізичної .sens; Result — owned
  FPC-managed bytes. Не інтерпретуємо текстову проєкцію.
  1. Чому перед SetLength перевіряється квота?
  2. Хто звільняє файловий дескриптор після помилки?
  3. Чому .lisp не підміняє фізичний вхід? }
function ReadPhysical(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Result:='';
  Require(ExtractFileExt(Path)='.sens',
    'дозволено лише фізичні .sens');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Require((Stream.Size>0) and (Stream.Size<=MaxPhysical),
      'порожні або надмірні фізичні дані');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally
    Stream.Free;
  end;
end;

{ Image — owned managed ELF bytes; файл зберігається тільки для
  машинної перевірки у приватному тимчасовому каталозі тесту.
  1. Чому ELF записується після повної структурної перевірки?
  2. Чому запис не є семантичним виконанням?
  3. Як порівняти його з expected .sens без текстової проєкції? }
procedure SaveELF(const Path:String;const Image:RawByteString);
var Stream:TFileStream;
begin
  Require(Length(Image)>0,'немає ELF-байтів');
  Stream:=TFileStream.Create(Path,fmCreate);
  try Stream.WriteBuffer(Image[1],Length(Image))
  finally Stream.Free end;
end;

{ Вихідні стадії — різні ВИМІРИ на тій самій packed програмі.
  Whole повторно виконує попередні проходи + backend: це ВКЛАДЕНИЙ
  час, а не взаємовиключна стадія. Таблиці не кешуються між формами.
  1. Чому не можна сумувати WideIR та whole?
  2. Де перевіряється exact pinned D1–D10?
  3. Чому в BuildWideIR знову декодуються фізичні координати?
  4. Що доводить VerifySENSELF64, а чого не доводить?
  5. Хто володіє усіма TExactWords, IR і ELF? }
procedure ProfileOne(const InputDir,OutputDir,Authority:String;
                     RepeatNo,Index:SizeInt;
                     var FirstImage:array of RawByteString);
var
  Name,Source,Image:RawByteString;
  W:TExactWords;
  Tables:TDomainSet;
  IR:TWideIR;
  Stats:TWideIRGuardStats;
  Geometry:TELFGeometry;
  StartNs,EndNs:QWord;

  procedure Stamp(const Phase:RawByteString;const A,B:QWord);
  begin
    Require(B>A,'недодатний етап монотонного годинника');
    WriteLn(String(Name),#9,RepeatNo,#9,String(Phase),#9,B-A);
  end;
begin
  Name:=RawByteString(Format('%.2d',[Index]));
  Source:=ReadPhysical(InputDir+'/'+String(Name)+'.sens');
  StartNs:=NowNs;
  DecodeT5M(Source,W);
  Require(EncodeT5M(W)=Source,'неканонічна T5M програма');
  EndNs:=NowNs;
  Stamp('канонічність',StartNs,EndNs);

  StartNs:=NowNs;
  LoadPinnedDomains(RawByteString(Authority),Tables);
  EndNs:=NowNs;
  Stamp('pinned-домени',StartNs,EndNs);

  StartNs:=NowNs;
  BuildWideIR(Source,Tables,IR);
  EndNs:=NowNs;
  Stamp('wideir',StartNs,EndNs);

  StartNs:=NowNs;
  VerifyWideIRStructure(IR,Stats);
  EndNs:=NowNs;
  Stamp('структура',StartNs,EndNs);
  Require((Stats.Roots=1) and (Stats.Nodes>=3),
          'фізична форма не є однією D2 програмою');

  StartNs:=NowNs;
  Image:=BuildVerifiedWideELF(Source,RawByteString(Authority));
  EndNs:=NowNs;
  Stamp('повна-компіляція',StartNs,EndNs);

  StartNs:=NowNs;
  VerifySENSELF64(Image,Geometry);
  EndNs:=NowNs;
  Stamp('машинна-геометрія',StartNs,EndNs);
  Require((Geometry.Kind=3) and (Geometry.Entry=120) and
          (Geometry.FileBytes=Length(Image)) and
          (Geometry.MachineBytes>0),
          'скомпільоване не є перевіреним x86-64 ELF64 PIE');
  if RepeatNo=1 then begin
    FirstImage[Index-1]:=Image;
    SaveELF(OutputDir+'/'+String(Name)+'.elf',Image);
  end else
    Require(FirstImage[Index-1]=Image,
            'ELF змінився між повторами без зміни фізичного джерела');
end;

{ Два негативи — реальні з існуючого pinned generator.
  Після обох відмов один позитив повторюється і порівнюється з
  початковим образом; не створюємо кеш або stale verified context.
  1. Чому виняток не можна трактувати як успішний ELF?
  2. Чому останній повтор має зберегти byte equality?
  3. Хто залишається відповідальним за backend-specific admission? }
procedure NegativeAndRecover(const InputDir,Authority:String;
                             const First:array of RawByteString);
var Physical,Image:RawByteString;I,Rejected:SizeInt;
    RejectPaths:array[0..1] of String;
begin
  RejectPaths[0]:='bad-t5m.sens';
  RejectPaths[1]:='bad-zero-arity.sens';
  Rejected:=0;
  for I:=0 to High(RejectPaths) do begin
    Physical:=ReadPhysical(InputDir+'/'+RejectPaths[I]);
    try
      Image:=BuildVerifiedWideELF(Physical,RawByteString(Authority));
      Require(False,'помилкова компіляція некоректної програми');
    except
      on E:EStageProfile do raise;
      on E:Exception do Inc(Rejected);
    end;
  end;
  Require(Rejected=2,'два негативи не відхилено');
  Physical:=ReadPhysical(InputDir+'/01.sens');
  Image:=BuildVerifiedWideELF(Physical,RawByteString(Authority));
  Require((Length(Image)>0) and (Image=First[0]),
          'не відновлено фізичну компіляцію після відмов');
  WriteLn(ErrOutput,'STAGE-NEGATIVES-OK count=2 recovery=1');
end;

{ Для 6 повторів беремо повний набір 16 у чергуванні forward/reverse
  і з циклічним зсувом; процес залишається один, без cached ELF hits.
  Результат — 576 рядків сирих наносекунд, не підміна end-to-end #820.
  1. Чому холодний startup треба вимірювати окремо?
  2. Чому cached hits заборонені в цьому профілі?
  3. Чому кожен повтор охоплює всі 16 різних програм? }
procedure Run;
var InputDir,OutputDir,Authority:String;RoundNo,Slot,Index:SizeInt;
    FirstImage:array[0..Samples-1] of RawByteString;
begin
  Require(ParamCount=2,
    'виклик: test-once-ir-stage-profile фізичні-фікстури каталог-ELF');
  InputDir:=ExpandFileName(ParamStr(1));
  OutputDir:=ExpandFileName(ParamStr(2));
  Authority:=ExpandFileName('external/sens');
  Require(DirectoryExists(InputDir) and DirectoryExists(OutputDir),
          'немає тимчасового каталогу фізичних свідків');
  WriteLn('зразок',#9,'повтор',#9,'етап',#9,'наносекунди');
  for RoundNo:=1 to Repeats do
    for Slot:=1 to Samples do begin
      if (RoundNo mod 2)=1 then
        Index:=1+((Slot-1+(RoundNo-1)*3) mod Samples)
      else
        Index:=Samples-((Slot-1+(RoundNo-1)*3) mod Samples);
      ProfileOne(InputDir,OutputDir,Authority,RoundNo,Index,FirstImage);
    end;
  NegativeAndRecover(InputDir,Authority,FirstImage);
end;

begin
  try Run;
  except on E:Exception do begin
    WriteLn(ErrOutput,'ПРОФІЛЬ-ВІДМОВА: ',E.Message);
    ExitCode:=2;
  end end;
end.
