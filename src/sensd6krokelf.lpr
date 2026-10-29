{ G6.81 — host AOT профіль pinned D6:001110 «додати-1», фізичний D12.
  Не є загальним компілятором D6. Використовує лише наявний перевірений
  BuildD12AddELF, який фізично виконує x86-64 ADD при запуску ELF.
  Авторитет: pinned SENS 12, D6:001110, profile current-domain-x86-64.
  Ніяких чисел із D7, текстового dispatch чи Common Lisp тегів. }
program sensd6krokelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.elfd12add,
  wsm.elfpublish,wsm.elfgeometry;

const MaxSourceBytes=64;
type ED6KrokError=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure OutputBytes(const Bytes:RawByteString; IsErr:Boolean);
var S:THandleStream; H:THandle;
begin
  if IsErr then H:=TextRec(StdErr).Handle
  else H:=TextRec(Output).Handle;
  S:=THandleStream.Create(H);
  try
    if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;

{ Path: borrowed шлях хоста до canonical .sens; Result — owned
  FPC-managed raw packed T5M bytes. Жодної конверсії у Unicode/десяткові.
  Межа 64 байти — захист host, не визначення numeric domain. }
function ReadPhysical(const Path:String):RawByteString;
var S:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') then
    raise ED6KrokError.Create(UA('потрібне двійкове джерело .sens'));
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<1) or (S.Size>MaxSourceBytes) then
      raise ED6KrokError.Create(UA('порожній або завеликий фізичний D12'));
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

procedure Run;
var
  Input,One,Image:RawByteString;
  Number:TExplicitNumeric;
  Geometry:TELFGeometry;
  OutputPath:String;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--додати-1-D12')) then
    raise ED6KrokError.Create(UA(
      'Виклик: sensd6krokelf --додати-1-D12 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise ED6KrokError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED6KrokError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  OutputPath:=ParamStr(3);
  if ExtractFileExt(OutputPath)<>'.elf' then
    raise ED6KrokError.Create(UA('потрібен новий вихід .elf'));

  Input:=ReadPhysical(ParamStr(2));
  Number:=ReadNumericPhysical(Input,12);
  if Number.DomainWidth<>12 then
    raise ED6KrokError.Create(UA('D12 admission не підтверджено'));
  { Єдине канонічне D12:1 — існуючий фізичний numeric codec,
    не виклик за текстовою проєкцією й не C/Pascal integer. }
  One:=EncodeNumericDecimal('1',12);
  { Повна допущена арифметика, машина ADD і D12 overflow guard —
    уже перевірені у wsm.elfd12add; повторно їх не реалізуємо. }
  Image:=BuildD12AddELF(Input,One);
  PublishNewELF64(OutputPath,Image,3,Geometry);
  OutputBytes('D6-001110-AOT-ELF64 bytes='+
    RawByteString(IntToStr(Geometry.FileBytes))+
    ' type=ET_DYN stdout=T5M'+#10,False);
end;

begin
  try Run
  except on E:Exception do begin
    OutputBytes(UA('КОМПІЛЯТОР-Д6-ВІДМОВА: ')+
      RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.

{ Життя: Input/One/Image — локальні керовані RawByteString і звільняються
  по виході Run; Number.ExactBits не втрачає провідних нулів. Image —
  фізичний ELF64 host ABI, НЕ .sens. PublishNewELF64 пише файл лише після
  повного guard і O_EXCL/no-clobber, failure не залишає ELF/stdout.
  1) Чому pinned D6 projection сама не є admission виклику?
  2) Чому використовується чинний BuildD12AddELF?
  3) Чому результат D12 overflow відхиляємо, а не обрізаємо?
  4) Чому machine ADD не доводить повний компілятор D6?
  5) Чому заблокована .lisp навіть для української проєкції? }