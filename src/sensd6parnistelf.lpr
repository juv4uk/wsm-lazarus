{ G6.85 — точний host AOT CLI для pinned D6:010000 / D6:010001.
  Canonical input тільки packed .sens; output — Linux ELF64 (не .sens).
  Два явні host-режими не є символічним SENS dispatch. }
program sensd6parnistelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd6parnist,wsm.elfpublish,wsm.elfgeometry;
type ED6CLIError=class(Exception);
const MaxAtomBytes=64;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Say(const B:RawByteString;Err:Boolean);
var S:THandleStream; H:THandle;
begin
  if Err then H:=TextRec(StdErr).Handle else H:=TextRec(Output).Handle;
  S:=THandleStream.Create(H);
  try if Length(B)>0 then S.WriteBuffer(B[1],Length(B))
  finally S.Free end;
end;

{ Borrowed Path до host файла; Result — owned canonical physical bytes.
  Файл відкрито без права змінювати, локальний потік закривається завжди.
  Розмір — тільки захист ресурсу; домен визначає нижчий numeric admission.
  1) Чому .lisp відхилено?
  2) Чому не виводимо домен із розміру файла?
  3) Що гарантує fmShareDenyWrite?
  4) Хто звільняє байти? }
function ReadSource(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ED6CLIError.Create(UA('потрібен канонічний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxAtomBytes) then
      raise ED6CLIError.Create(UA('порожній або завеликий фізичний атом'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Повний контроль перед публікацією: D12 numeric+signed, тільки
  pinned D6 selected explicit host mode; BuildD6ParnistELF повертає
  managed ELF, PublishNewELF64 робить exclusive/no-clobber commit.
  Питання: чому isOdd — механічна host гілка, не закон?
  Чому D1 відповідь не числове D12? Чому на відмові нема stdout? }
procedure Run;
var Physical,Image,Mode:RawByteString; IsOdd:Boolean;
  Geometry:TELFGeometry; Target:String;
begin
  if ParamCount<>3 then
    raise ED6CLIError.Create(UA(
      'Виклик: sensd6parnistelf --парне-D12|--непарне-D12 атом.sens новий.elf'));
  Mode:=RawByteString(ParamStr(1));
  if Mode=UA('--парне-D12') then IsOdd:=False
  else if Mode=UA('--непарне-D12') then IsOdd:=True
  else raise ED6CLIError.Create(UA('неприпустимий host-режим D6'));
  {$IFNDEF LINUX}
  raise ED6CLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED6CLIError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Target:=ParamStr(3);
  if ExtractFileExt(Target)<>'.elf' then
    raise ED6CLIError.Create(UA('потрібен новий .elf'));
  Physical:=ReadSource(ParamStr(2));
  Image:=BuildD6ParnistELF(Physical,IsOdd);
  PublishNewELF64(Target,Image,3,Geometry);
  Say(UA('КОМПІЛЯТОР-Д6-ПАРНІСТЬ-ELF-ГОТОВО байтів=')+
    RawByteString(IntToStr(Geometry.FileBytes))+UA(' відповідь=D1:T5M')+#10,False);
end;

begin
  try Run
  except on E:Exception do begin
    Say(UA('КОМПІЛЯТОР-Д6-ПАРНІСТЬ-ВІДМОВА: ')+RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
