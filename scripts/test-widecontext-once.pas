{ G6 — захист одноразового host Verified WideIR контексту.
  Це механічний тест без нового evaluator, D1/D7 dispatch чи закону.
  Точна фізична D5:01000 програма — чинний pinned fixture.
  1) Чому повторне Lower забороняється навіть після успіху?
  2) Чому після помилки не можна повторно використати IR?
  3) Чому вкладений callback не повинен обійти guard?
  4) Чому ELF перевіряємо запуском окремо від геометрії? }
program test_widecontext_once;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.verifiedwidecontext,wsm.wideir,
     wsm.wideirguard,wsm.irwidezero;

var Nested:TVerifiedWideContext; NestedRejected:Boolean;
    Checks:SizeInt;

procedure Need(Yes:Boolean;const Reason:String);
begin
  if not Yes then raise Exception.Create(Reason);
  Inc(Checks);
end;

function ReadBytes(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result,F.Size);
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally
    F.Free;
  end;
end;

procedure SaveBytes(const Path:String;const Content:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Content)>0 then F.WriteBuffer(Content[1],Length(Content));
  finally
    F.Free;
  end;
end;

{ Неприпустимий machine-image: callback отримує read-only borrowed IR,
  повертає owned невірні bytes; VerifySENSELF64 зобов'язаний відмовити.
  1) Чому невірна геометрія не може дати успішний компіляторний стан?
  2) Хто володіє поверненими байтами? }
function BadLower(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
begin
  Result:='not ELF';
end;

{ Вкладений callback перевіряє guard: другий Lower мусить відмовити
  ДО повторного входу в механізм. Nested — лише тестовий host pointer.
  1) Чому такий self-reference не становить новий SENS рекурсивний закон?
  2) Як виявити пропущений захист від повторного виклику? }
function ReentrantLower(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
begin
  NestedRejected:=False;
  try
    Nested.Lower(@BadLower);
  except
    on E:EVerifiedWideContext do NestedRejected:=True;
  end;
  Result:='not ELF';
end;

procedure ExpectUsed(C:TVerifiedWideContext);
var Rejected:Boolean;
begin
  Rejected:=False;
  try
    C.Lower(@BadLower);
  except
    on E:EVerifiedWideContext do Rejected:=True;
  end;
  Need(Rejected,'другу спробу lowering не відхилено');
end;

procedure Run;
var Physical,OldELF,NewELF,SecondELF:RawByteString;
    A,B,C,D:TVerifiedWideContext;
    Failed:Boolean;
begin
  Need(ParamCount=2,'потрібні фізичний .sens і вихідний .elf');
  Physical:=ReadBytes(ParamStr(1));
  Need(Length(Physical)>0,'немає фізичної програми');
  OldELF:=BuildIRWideZeroELF(Physical,'external/sens');
  Need(Copy(OldELF,1,4)=#$7F+'ELF','старий backend не повернув ELF');
  A:=TVerifiedWideContext.Create(Physical,'external/sens');
  try
    NewELF:=BuildIRWideZeroFromContext(A);
    Need(NewELF=OldELF,'порушено побайтову ELF тотожність');
    ExpectUsed(A);
    ExpectUsed(A);
  finally
    A.Free;
  end;
  SaveBytes(ParamStr(2),NewELF);
  B:=TVerifiedWideContext.Create(Physical,'external/sens');
  try
    SecondELF:=BuildIRWideZeroFromContext(B);
    Need(SecondELF=NewELF,'новий контекст не детермінований');
    ExpectUsed(B);
  finally
    B.Free;
  end;
  { Callback створив неправильні ELF байти. Помилка звільняє право
    на подальший Lower; інша програма може створити СВІЙ новий контекст. }
  C:=TVerifiedWideContext.Create(Physical,'external/sens');
  try
    Failed:=False;
    try C.Lower(@BadLower)
    except on E:Exception do Failed:=True end;
    Need(Failed,'невірний ELF callback прийнято');
    ExpectUsed(C);
  finally
    C.Free;
  end;
  D:=TVerifiedWideContext.Create(Physical,'external/sens');
  try
    Nested:=D;
    Failed:=False;
    try D.Lower(@ReentrantLower)
    except on E:Exception do Failed:=True end;
    Need(NestedRejected,'вкладений Lower не заблоковано');
    Need(Failed,'неправильну зовнішню ELF геометрію прийнято');
    ExpectUsed(D);
  finally
    Nested:=nil;
    D.Free;
  end;
  Failed:=False;
  try
    A:=TVerifiedWideContext.Create(#$FF,'external/sens');
    A.Free;
  except on E:Exception do Failed:=True end;
  Need(Failed,'зіпсований T5M пройшов admission');
  Writeln('WIDECONTEXT-ONCE-PASS checks=',Checks,' machine=EXTERNAL');
end;

begin
  try Run
  except on E:Exception do begin
    Writeln(StdErr,'WIDECONTEXT-ONCE-FAIL: ',E.Message);
    Halt(2);
  end end;
end.
