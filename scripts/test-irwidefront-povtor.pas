{ G6.157 — повторний виклик вже наявного фізичного WideIR→ELF64
  у тому самому FPC-процесі. Це перевірка механізму, НЕ новий SENS
  evaluator, закон, registry чи семантичний оракул.
  Чинні 16 фізичних свідків генерує scripts/test-irwidefront.pas. }
program test_irwidefront_povtor;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.irwidefront, wsm.elfgeometry;
const
  CasesCount=16;
  CyclesCount=4;
type
  TCaseBytes=array[1..CasesCount] of RawByteString;
var
  Inputs,InitialELF:TCaseBytes;
  GoodCount,BadCount,RecoveryCount:SizeInt;

{ Name — borrowed host-шлях. Result — owned FPC-managed фізичні байти,
  жодного перетворення на людську «укр» або числовий opcode.
  1) Чому весь файл читається як байти, а не рядки?
  2) Хто звільняє TFileStream при відмові?
  3) Чому нульова довжина не читає Result[1]? }
function ReadBytes(const Name:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  F:=TFileStream.Create(Name,fmOpenRead or fmShareDenyWrite);
  try
    if F.Size>65536 then
      raise Exception.Create('фізичний свідок перевищив межу');
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Image — borrowed ELF, шлях — host output у приватній тестовій теці.
  Виконуваний результат перевіряється окремим shell runner.
  1) Чому не записуємо байти до повного допуску?
  2) Кому належить FPC-managed Image?
  3) Чому тека тесту мусить бути тимчасовою? }
procedure WriteBytes(const Name:String;const Image:RawByteString);
var F:TFileStream;
begin
  if Length(Image)=0 then raise Exception.Create('порожній ELF');
  F:=TFileStream.Create(Name,fmCreate);
  try F.WriteBuffer(Image[1],Length(Image));
  finally F.Free end;
end;

{ Physical — borrowed canonical T5M; ELF — owned Result компілятора.
  Єдиний semantic admission — pinned BuildVerifiedWideELF.
  1) Чому геометрія PIE не доводить семантику?
  2) Чому не переходимо до десяткового значення D12?
  3) Чому однакові фізичні слова мають давати однаковий ELF? }
function Compile(const Physical:RawByteString):RawByteString;
var G:TELFGeometry;
begin
  Result:=BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Result,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Result)) or (Length(Result)<=120) then
    raise Exception.Create('непридатна машинна геометрія ELF64 PIE');
  Inc(GoodCount);
end;

{ Повна відмова повинна лишати процес придатним до нового виклику.
  Це тільки host-інваріант: виняток не надає жодного нового закону SENS.
  1) Чому відхилення є позитивним тестом безпеки?
  2) Чому виняток не можна перетворити на порожній ELF?
  3) Навіщо після негативу повторити фізичну компіляцію? }
procedure ExpectReject(const Physical:RawByteString);
var Returned:RawByteString;DidReject:Boolean;
begin
  DidReject:=False;
  try
    Returned:=BuildVerifiedWideELF(Physical,'external/sens');
  except
    on E:Exception do DidReject:=True;
  end;
  if not DidReject then
    raise Exception.Create('некоректний фізичний вхід допущено до ELF');
  Inc(BadCount);
end;

procedure Run;
var Dir,Tag:String;I,N,Cycle,K:SizeInt;Image:RawByteString;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен шлях до 16 свідків');
  Dir:=ParamStr(1);
  if not DirectoryExists(Dir) then
    raise Exception.Create('тека фізичних свідків відсутня');
  GoodCount:=0;BadCount:=0;RecoveryCount:=0;

  { 16 різних pinned T5M програм з наявного незалежного генератора.
    InitialELF зберігається як FPC-managed побайтовий еталон ТОГО САМОГО
    компілятора; це тест детермінізму, а НЕ SENS oracle. }
  for I:=1 to CasesCount do begin
    Tag:=IntToStr(I);
    if I<10 then Tag:='0'+Tag;
    Inputs[I]:=ReadBytes(Dir+'/'+Tag+'.sens');
    InitialELF[I]:=Compile(Inputs[I]);
    WriteBytes(Dir+'/'+Tag+'.povtor.elf',InitialELF[I]);
  end;

  { Чергування напрямків обходу перевіряє відсутність стану
    попереднього профілю. Після КОЖНОГО успіху — некоректний суфікс
    T5M, після КОЖНОГО циклу — дві незалежні форми відмови.
    1) Навіщо міняти порядок позитивів?
    2) Чому суфікс #$FF не є дозволеним T5M словом?
    3) Хто звільняє Image після кожного присвоєння? }
  for Cycle:=1 to CyclesCount do begin
    for K:=1 to CasesCount do begin
      if Odd(Cycle) then N:=CasesCount+1-K else N:=K;
      Image:=Compile(Inputs[N]);
      if Image<>InitialELF[N] then
        raise Exception.Create('ELF відрізняється при повторі профілю '+IntToStr(N));
      ExpectReject(Inputs[N]+#$FF);
    end;
    ExpectReject(ReadBytes(Dir+'/two-roots.sens'));
    ExpectReject(ReadBytes(Dir+'/bad-t5m.sens'));
    ExpectReject('');
  end;

  { Останній виклик ПІСЛЯ всіх відмов: не лишається stale frontend-стану. }
  Image:=Compile(Inputs[1]);
  if Image<>InitialELF[1] then
    raise Exception.Create('компілятор не відновився після відмов');
  Inc(RecoveryCount);
  if (GoodCount<>81) or (BadCount<>76) or (RecoveryCount<>1) then
    raise Exception.Create('неповний механічний облік перевірок');
  WriteLn('G6.157-WIDEIR-POVTOR-PASS physical=16 good=81 ',
          'negative=76 recovery=1 byte-identical=65 energy=NOT-MEASURED');
end;

begin
  ExitCode:=0;
  try Run;
  except on E:Exception do begin
    WriteLn(ErrOutput,'КОМПІЛЯТОР-ПОВТОР-ВІДМОВА: ',E.Message);
    ExitCode:=2;
  end end;
end.
