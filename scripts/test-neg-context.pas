{ G6.193: 14 фізичних pinned D6:010010 через два шляхи до одного ELF.
  Тут немає семантичного Pascal evaluator: вхід .sens, вихід ELF64.
  Всі expected .sens створює наявний source-backed fixture generator. }
program test_neg_context;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideneg,wsm.verifiedwidecontext;
const PositiveCount=14;
      NegativeCount=17;
type ETest=class(Exception);
var SourceDir,ImageDir:String;Positives,Rejected:SizeInt;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise ETest.Create(Why) end;

{ Path — host шлях до canonical packed .sens, Result — власні байти.
  TFileStream володіє файлом тільки до return.
  1) Чому .lisp не є machine каноном?
  2) Хто декодує точні D2 слова та перевіряє домен?
  3) Чому один байт не визначає сам по собі закон? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Must(F.Size<=65536,'фізична програма перевищує host квоту');
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Image — вже перевірені ELF64 bytes, шлях — тільки тимчасова test dir.
  File owns its descriptor; managed Image is borrowed, not mutated.
  1) Чому це не production atomic publish?
  2) Хто перевірив геометрію?
  3) Чи можна результат назвати SENS числом? }
procedure Save(const Path:String;const Image:RawByteString);
var F:TFileStream;
begin
  Must(Length(Image)>120,'недостатньо фізичних байтів ELF64');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Image[1],Length(Image));
  finally F.Free end;
end;

{ Один context — одна повна компіляція; старий маршрут не змінено.
  Дві незалежні алокації byte-exact ELF та точний machine-результат
  звіряється зовнішнім shell і фізичним expected .sens.
  1) Чому ELF output має бути побайтово однаковим?
  2) Чому повторне Lower для того самого контексту — помилка?
  3) Чому -2048 повинен промотуватися в D24?
  4) Хто звільняє приватні FPC IR поля при помилці? }
procedure Positive(const LabelText:String);
var Physical,OldELF,NewELF:RawByteString;Ctx:TVerifiedWideContext;
    Reused:Boolean;
begin
  Physical:=ReadPhysical(SourceDir+'/'+LabelText+'.sens');
  OldELF:=BuildIRWideNegELF(Physical,'external/sens');
  Ctx:=TVerifiedWideContext.Create(Physical,'external/sens');
  try
    NewELF:=BuildIRWideNegFromContext(Ctx);
    Reused:=False;
    try
      BuildIRWideNegFromContext(Ctx);
    except on E:Exception do Reused:=True end;
    Must(Reused,'контекст повторно прийняв Lower');
  finally Ctx.Free end;
  Must((OldELF=NewELF) and (Length(NewELF)>120),
    'машинні ELF змінилися у перевіреному маршруті');
  Save(ImageDir+'/'+LabelText+'.old.elf',OldELF);
  Save(ImageDir+'/'+LabelText+'.new.elf',NewELF);
  Inc(Positives);
end;

{ Негативи мають відхилятися двома шляхами до відкриття ELF файла.
  Виняток не може опублікувати контекст наступній програмі.
  1) Чому хибний T5M не може залишити partial machine bytes?
  2) Чому негатив не вважається успішно виконаною функцією?
  3) Як нова програма ізолюється від попереднього відхилення? }
procedure Negative(const Name:String);
var Physical,Image:RawByteString;OldRejected,NewRejected:Boolean;
    Ctx:TVerifiedWideContext;
begin
  Physical:=ReadPhysical(SourceDir+'/'+Name+'.sens');
  OldRejected:=False;
  try
    Image:=BuildIRWideNegELF(Physical,'external/sens');
  except on E:Exception do OldRejected:=True end;
  NewRejected:=False;
  Ctx:=nil;
  try
    Ctx:=TVerifiedWideContext.Create(Physical,'external/sens');
    Image:=BuildIRWideNegFromContext(Ctx);
  except on E:Exception do NewRejected:=True end;
  Ctx.Free;
  Must(OldRejected and NewRejected,'негатив помилково створив ELF: '+Name);
  Inc(Rejected);
end;

procedure Run;
const Bad:array[1..NegativeCount] of String=(
  'other-d6','other-d5','other-d7','d1','d3-empty','d7','d24',
  'missing','extra','nested','two-roots','dotted','root-atom',
  'unclosed','close-only','bad-t5m','empty');
var I:SizeInt;
begin
  if ParamCount<>2 then raise ETest.Create('виклик: фізичні/ образи/');
  SourceDir:=ParamStr(1);ImageDir:=ParamStr(2);
  Must(DirectoryExists(SourceDir) and DirectoryExists(ImageDir),
    'немає тимчасового каталогу');
  Positives:=0;Rejected:=0;
  for I:=1 to PositiveCount do Positive(Format('%.2d',[I]));
  for I:=1 to NegativeCount do Negative(Bad[I]);
  { Відновлення тієї самої фізичної програми після 17 відмов. }
  Positive('08');
  Must((Positives=15) and (Rejected=17),'порушено кількість свідків');
  WriteLn('NEG-КОНТЕКСТ-ГАРАЗД фізичних=14 parity=14 негативів=17 відновлено=так повторний-контекст=відмова');
end;

begin
  try Run
  except on E:Exception do begin
    WriteLn(ErrOutput,'NEG-КОНТЕКСТ-ПРОВАЛ: ',E.Message);
    ExitCode:=2;
  end end;
end.
