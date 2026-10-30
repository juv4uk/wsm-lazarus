{ G6.151 — фізичний stdin → ТОЙ САМИЙ pinned WideIR → ELF64 stdout.
  Це host-потік байтів T5M, не новий reader, evaluator чи закон SENS.
  Доступний лише перевірений профіль BuildVerifiedWideELF.
  Усі повідомлення людини — українською; stdout містить лише ELF. }
program senswidepotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,Unix,wsm.irwidefront,wsm.elfgeometry;
const MaxPhysicalBytes=65536;
type EWidePipeError=class(Exception);

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Borrowed host stdin FD, owned Source wrapper та один RawByteString.
  Буфер росте 1024→2048→...→65536 без окремого TMemoryStream і
  повторного повного копіювання фізичного потоку; UTF-8 проєкцій немає.
  Result — owned packed T5M байти фактичної довжини; EOF host відмежовує
  одну програму, але не замінює D2 рамку чи pinned перевірку.
  1) Чому читання частинами не змінює T5M-домени?
  2) Чому переповнення перевіряємо ДО SetLength та Move?
  3) Чому host EOF не вважаємо SENS-операцією?
  4) Хто володіє Result після успіху, а Source після винятку?
  5) Чому Reserved не є шириною домену чи довжиною канонічного .sens? }
function ReadPhysical:RawByteString;
var Source:THandleStream;
    Chunk:array[0..1023] of Byte;N:LongInt;
    Used,Reserved,Next:SizeInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Used:=0;
    Reserved:=0;
    repeat
      N:=Source.Read(Chunk,SizeOf(Chunk));
      if N<0 then
        raise EWidePipeError.Create(Ukr('не вдалося прочитати stdin'));
      if N=0 then Break;
      { Невідомий або надмірний host-ввід відхиляємо ДО виділення:
        MaxPhysicalBytes — межа транспорту, не домен SENS. }
      if Used>MaxPhysicalBytes-N then
        raise EWidePipeError.Create(Ukr('фізичний T5M перевищив 65536 байтів'));
      Next:=Used+N;
      if Next>Reserved then begin
        if Reserved=0 then Reserved:=SizeOf(Chunk);
        while Reserved<Next do begin
          if Reserved<=MaxPhysicalBytes div 2 then
            Reserved:=Reserved*2
          else
            Reserved:=MaxPhysicalBytes;
        end;
        SetLength(Result,Reserved);
      end;
      Move(Chunk[0],Result[Used+1],N);
      Used:=Next;
    until False;
    if Used=0 then
      raise EWidePipeError.Create(Ukr('порожній фізичний потік'));
    { Точно фактична кількість packed T5M байтів, без нульового хвоста. }
    SetLength(Result,Used);
  finally Source.Free end;
end;

{ Text is owned UTF-8 status. Stream wraps borrowed stderr descriptor;
  never mix host diagnostics with machine ELF stdout.
  1) Чому відмову не можна надрукувати в ELF stdout?
  2) Чи змінює український текст ратифіковані координати? }
procedure FailMessage(const Text:RawByteString);
var Err:THandleStream;S:RawByteString;
begin
  S:=Ukr('ШИРОКИЙ-ПОТІК-ВІДМОВА: ')+Text+#10;
  Err:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(S[1],Length(S));
  finally Err.Free end;
end;

{ Root — позичений абсолютний host-шлях pinned SENS, НЕ D7 і не
  текстова проєкція. За старого 1-аргументного CLI корінь залежить від
  cwd; 3-аргументний режим призначено для IDE та інших викликачів.
  У явному режимі перевіряємо фізичний Git tree чинного pin та всі
  одинадцять робочих файлів ДО ReadPhysical. Legacy cwd не змінюємо.
  1) Чому шлях не визначає семантичний закон SENS?
  2) Чому відносний корінь заборонено в явному режимі?
  3) Чому перевірка відбувається раніше за фізичний stdin?
  4) Хто володіє повернутим RawByteString? }
{ Механічний Git preflight: перевіряємо НЕ status/index, а байти
  одинадцяти файлів проти tree pinned commit. Вхід Root — позичений
  host-каталог, Output — owned stdout git, ніякого SENS значення.
  Пам'ять stdout, pipe та child звільняються після виклику.
  1) Чому правильний HEAD не доводить робочі байти?
  2) Чому assume-unchanged не може сховати модифікацію від hash-object?
  3) Чому поява .lisp не створює новий мовний закон?
  4) Чому перевірка робиться раніше за читання .sens? }
{ Шлях до Git — привілейована host-конфігурація, а не частина
  синтаксису або ратифікованих законів SENS. Застосунок із Lazarus IDE
  не має шукати Git у недовіреному cwd/PATH: сторонній bin/git зміг би
  сфальсифікувати rev-parse, ls-tree і hash-object одночасно.
  Нестандартні Guix/Nix-середовища задають явний абсолютний
  SENS_TRUSTED_GIT. Відносні executable — відмова до fork. }
function TrustedGitExecutable:String;
const
  Paths:array[0..4] of String=(
    '/usr/bin/git', '/bin/git',
    '/run/current-system/profile/bin/git',
    '/run/current-system/sw/bin/git',
    '/nix/var/nix/profiles/default/bin/git');
var I:SizeInt;
begin
  Result:=GetEnvironmentVariable('SENS_TRUSTED_GIT');
  if Result<>'' then begin
    if (Length(Result)>4096) or (Result[1]<>'/') or
       (not FileExists(Result)) then
      raise EWidePipeError.Create(
        'шлях довіреного Git має бути абсолютним наявним файлом');
    Exit;
  end;
  for I:=Low(Paths) to High(Paths) do
    if FileExists(Paths[I]) then Exit(Paths[I]);
  raise EWidePipeError.Create(
    'немає системного Git; потрібен абсолютний SENS_TRUSTED_GIT');
end;

function GitOutput(const Root:String;const Args:array of String):RawByteString;
var
  Descriptors:TFilDes;
  Arguments:array of PChar;
  GitBinary:String;
  Child,Waited:TPid;
  Status:LongInt;
  I,N,OldSize:SizeInt;
  Started:QWord;
  Finished:Boolean;
  Chunk:array[0..1023] of Byte;
begin
  { Жодного shell і FCL Process: тільки RTL Unix/BaseUnix.
    Root та Args — позичені host-рядки, Arguments — тимчасові
    вказівники на них, Result — власні байти stdout Git.
    1) Чому execvp отримує масив аргументів, а не shell-команду?
    2) Чому replace-об'єкти вимкнені до визначення Git дерева?
    3) Хто закриває обидва кінці pipe та прибирає child?
    4) Чому не можна віддати часткові байти при помилці? }
  Result:='';
  GitBinary:=TrustedGitExecutable;
  SetLength(Arguments,Length(Args)+5);
  Arguments[0]:=PChar(GitBinary);
  Arguments[1]:=PChar('--no-replace-objects');
  Arguments[2]:=PChar('-C');
  Arguments[3]:=PChar(Root);
  for I:=Low(Args) to High(Args) do
    Arguments[I+4]:=PChar(Args[I]);
  Arguments[High(Arguments)]:=nil;
  if fpPipe(Descriptors)<>0 then
    raise EWidePipeError.Create('не створено канал pinned Git');
  Child:=fpFork;
  if Child=0 then begin
    fpClose(Descriptors[0]);
    if (fpDup2(Descriptors[1],1)<0) or
       (fpDup2(Descriptors[1],2)<0) then fpExit(127);
    fpClose(Descriptors[1]);
    { Наявність '/' в executable змушує execvp виконати рівно цей
      файл без пошуку за недовіреним PATH. }
    fpExecVP(PChar(GitBinary),@Arguments[0]);
    fpExit(127);
  end;
  if Child<0 then begin
    fpClose(Descriptors[0]);
    fpClose(Descriptors[1]);
    raise EWidePipeError.Create('не створено процес pinned Git');
  end;
  fpClose(Descriptors[1]);
  Finished:=False;
  try
    Started:=GetTickCount64;
    repeat
      Waited:=fpWaitPid(Child,@Status,WNOHANG);
      if Waited=Child then begin Finished:=True; Break end;
      if Waited<0 then
        raise EWidePipeError.Create('помилка очікування pinned Git');
      if GetTickCount64-Started>10000 then
        raise EWidePipeError.Create('вичерпано час перевірки pinned SENS');
      Sleep(5);
    until False;
    if Status<>0 then
      raise EWidePipeError.Create('не пройдено Git-перевірку pinned SENS');
    repeat
      N:=fpRead(Descriptors[0],Chunk[0],SizeOf(Chunk));
      if N<0 then
        raise EWidePipeError.Create('помилка читання pinned Git');
      if N=0 then Break;
      OldSize:=Length(Result);
      if OldSize+N>8192 then
        raise EWidePipeError.Create('завелика відповідь Git-перевірки');
      SetLength(Result,OldSize+N);
      Move(Chunk[0],Result[OldSize+1],N);
    until False;
  finally
    if not Finished then begin
      fpKill(Child,9);
      fpWaitPid(Child,@Status,0);
    end;
    fpClose(Descriptors[0]);
  end;
end;

procedure CheckPinnedRoot(const Root:String);
const
  Pin='2c498b35af53c085450eac6f51b87facf7f9aa47';
  Paths:array[0..10] of String=(
    'contracts/language-contract-12.lisp',
    'lib/domains/d1.lisp', 'lib/domains/d10.lisp',
    'lib/domains/d2.lisp', 'lib/domains/d3.lisp',
    'lib/domains/d4.lisp', 'lib/domains/d5.lisp',
    'lib/domains/d6.lisp', 'lib/domains/d7.lisp',
    'lib/domains/d8.lisp', 'lib/domains/d9.lisp');
var Tree,Actual:TStringList;TreeArgs,HashArgs:array of String;
    I:SizeInt;Line:RawByteString;
begin
  if Trim(String(GitOutput(Root,['rev-parse','HEAD'])))<>Pin then
    raise EWidePipeError.Create('корінь SENS має інший pinned commit');
  SetLength(TreeArgs,Length(Paths)+4);
  TreeArgs[0]:='ls-tree';TreeArgs[1]:='-r';
  TreeArgs[2]:=Pin;TreeArgs[3]:='--';
  SetLength(HashArgs,Length(Paths)+3);
  HashArgs[0]:='hash-object';HashArgs[1]:='--no-filters';
  HashArgs[2]:='--';
  for I:=Low(Paths) to High(Paths) do begin
    TreeArgs[I+4]:=Paths[I];
    HashArgs[I+3]:=Paths[I];
  end;
  Tree:=TStringList.Create;
  try
    Actual:=TStringList.Create;
    try
      Tree.Text:=String(GitOutput(Root,TreeArgs));
      Actual.Text:=String(GitOutput(Root,HashArgs));
      if (Tree.Count<>Length(Paths)) or (Actual.Count<>Length(Paths)) then
        raise EWidePipeError.Create('неповний pinned набір D1–D10 та Contract 12');
      for I:=Low(Paths) to High(Paths) do begin
        Line:=RawByteString(Tree[I]);
        if (Length(Line)<54) or
           (Copy(Line,1,12)<>'100644 blob ') or
           (Line[53]<>#9) or
           (Copy(Line,54,Length(Line)-53)<>RawByteString(Paths[I])) or
           (Length(Actual[I])<>40) or
           (Copy(Line,13,40)<>RawByteString(Actual[I])) then
          raise EWidePipeError.Create(
            'вміст pinned SENS відрізняється від Git tree: '+Paths[I]);
      end;
    finally Actual.Free end;
  finally Tree.Free end;
end;


function AuthorityRoot:RawByteString;
var P:String;
begin
  if ParamCount=1 then Exit('external/sens');
  if (ParamCount<>3) or
     (RawByteString(ParamStr(2))<>Ukr('--корінь-sens')) then
    raise EWidePipeError.Create(Ukr('потрібен явний --корінь-sens'));
  P:=ParamStr(3);
  if (P='') or (Length(P)>4096) or (P[1]<>'/') then
    raise EWidePipeError.Create(Ukr('корінь SENS має бути абсолютним шляхом'));
  P:=ExcludeTrailingPathDelimiter(ExpandFileName(P));
  if (not DirectoryExists(P)) or
     (not FileExists(P+'/contracts/language-contract-12.lisp')) then
    raise EWidePipeError.Create(Ukr('немає фізичного каталогу контракту SENS 12.0'));
  CheckPinnedRoot(P);
  Result:=RawByteString(P);
end;

{ Physical та Image — owned RawByteString, verified Geometry — stack.
  Лише ПІСЛЯ повного pinned T5M/D2/WideIR і ELF64 PIE admission
  відкриваємо borrowed stdout FD; failure під час запису OS pipe
  може лишити префікс ELF — транзакційність після write НЕ обіцяємо.
  1) Де перевіряються exact pinned координати D5/D6?
  2) Чому SIR1 не підміняє перевірений ELF?
  3) Чому перевірка geometry не є доказом семантики?
  4) Чим відрізняється host write error від compiler reject?
  5) Кому належить пам'ять Image після повернення? }
procedure Compile(const Root:RawByteString);
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
    Offset,Written:SizeInt;
begin
  Physical:=ReadPhysical;
  Image:=BuildVerifiedWideELF(Physical,Root);
  VerifySENSELF64(Image,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Image)) or (Length(Image)<=120) then
    raise EWidePipeError.Create(Ukr('ELF64 PIE не пройшов остаточний допуск'));
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    { Host POSIX pipe/sock може легально прийняти тільки префікс;
      один WriteBuffer вимагав увесь ELF за один syscall. Пишемо
      залишок ДО повної публікації або fail-closed на 0/-errno.
      Вхідна фізична форма і весь pinned WideIR уже перевірені.
      1) Чому позитивний короткий host write не змінює ELF?
      2) Чому нульовий write має бути явною host-відмовою?
      3) Чому Offset не є числовою D12 координатою?
      4) Чому помилка після часткового stdout не атомарна? }
    Offset:=0;
    while Offset<Length(Image) do begin
      Written:=Sink.Write(Image[Offset+1],Length(Image)-Offset);
      if (Written<=0) or (Written>Length(Image)-Offset) then
        raise EWidePipeError.Create(
          Ukr('Linux stdout не прийняв повний машинний ELF64'));
      Inc(Offset,Written);
    end;
  finally Sink.Free end;
end;

begin
  ExitCode:=0;
  if ((ParamCount<>1) and (ParamCount<>3)) or
     (RawByteString(ParamStr(1))<>Ukr('--скомпілювати-фізичний-потік')) then
  begin
    FailMessage(Ukr('виклик: senswidepotikelf --скомпілювати-фізичний-потік [--корінь-sens /absolute/external/sens] < вхід.sens > результат.elf'));
    ExitCode:=64;
  end
  else
    try
      {$IFNDEF LINUX}
      raise EWidePipeError.Create(Ukr('потрібен Linux'));
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise EWidePipeError.Create(Ukr('потрібен x86-64'));
      {$ENDIF}
      Compile(AuthorityRoot);
    except on E:Exception do begin
      FailMessage(Ukr(UnicodeString(E.Message)));
      ExitCode:=2;
    end end;
end.
