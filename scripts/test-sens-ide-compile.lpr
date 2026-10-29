{ G8.2 — перевірка реальної LCL форми спільного IDE-компілятора.
  Вхід: borrow 7 host paths; unit owns compiled ELF RawByteString.
  Вихід: тільки ELF у приватному каталозі тесту, не нова SENS програма.
  Питання: як встановлено точний pin? Чому .lisp відхиляється?
  Де перевіряється відсутність старого ELF? Хто володіє формою?
  Чим byte-for-byte ELF переконливіший за назву кнопки? }
program test_sens_ide_compile;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,SysUtils,Classes,sens_ide_compiler;
var Window:TSensIDECompiler;Root,Sub,NSD,Bad,TextFile,Other,Prefix:String;
    FirstBytes:SizeInt;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('IDE-КОМПІЛЯТОР-ПРОВАЛ: '+Why)
end;
{ Реальний очікуваний T5M читаємо як БАЙТИ з pinned фізичних
  fixtures, а не перераховуємо числові результати у Pascal.
  F: owned file descriptor, bytes: owned RawByteString.
  1) Чому формат .expected.sens не декодуємо як текст?
  2) Чому навіть еквівалентне десяткове число не доводить exact width?
  3) Хто звільняє файл за винятку читання? }
function ReadExpected(const Source:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(ChangeFileExt(Source,'.expected.sens'),fmOpenRead);
  try
    Need((F.Size>0) and (F.Size<=64),'хибна квота expected T5M');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure CheckNative(const Source:String;ExpectedSize:SizeInt);
var Expected:RawByteString;
begin
  Expected:=ReadExpected(Source);
  Need(Window.RunCurrent,'не виконано verified native ELF: '+Window.StatusText);
  Need(Window.HasNativeResult and (Window.NativeResult=Expected) and
    (Length(Window.NativeResult)=ExpectedSize),
    'native stdout не тотожний exact pinned фізичному T5M');
  Need(Pos('ВИКОНАНО:',Window.StatusText)=1,
    'LCL не показує результат фактичного виконання');
end;
begin
  if ParamCount<>7 then Halt(64);
  Root:=ParamStr(1);Sub:=ParamStr(2);NSD:=ParamStr(3);
  Bad:=ParamStr(4);TextFile:=ParamStr(5);
  Other:=ParamStr(6);Prefix:=ParamStr(7);
  Application.Initialize;
  Window:=TSensIDECompiler.Create(nil);
  try
    Window.Show;Application.ProcessMessages;
    Need(Window.Visible,'не відкрито справжню LCL форму');
    Need(Window.SetRepositoryRoot(Root),'pinned корінь');
    Need(Window.CompilePhysical(Sub),'D5 фізична програма');
    Need(Window.HasVerifiedImage and (Window.ImageBytes>120) and
      (Window.MachineBytes>0) and
      (Pos('СКОМПІЛЬОВАНО:',Window.StatusText)=1),
      'не показано справжню геометрію ELF64');
    FirstBytes:=Window.ImageBytes;
    CheckNative(Sub,5);
    Need(Window.PublishNew(Prefix+'-sub.elf'),'немає нового ELF64 D5');
    Need(not Window.PublishNew(Prefix+'-sub.elf'),'перезаписано старий ELF');
    Need(Window.CompilePhysical(NSD),'D6 фізична програма');
    Need(Window.HasVerifiedImage and (Window.ImageBytes>120),
      'D6 ELF не пройшов verification');
    Need(Window.PublishNew(Prefix+'-nsd.elf'),'немає нового ELF64 D6');
    CheckNative(NSD,3);
    Need(not Window.CompilePhysical(Bad),'неканонічний T5M прийнято');
    Need(not Window.HasVerifiedImage and (not Window.HasNativeResult) and
      (Window.NativeResult='') and
      (Window.ImageBytes=0) and (Window.MachineBytes=0),
      'після помилки залишився старий ELF');
    Need(not Window.PublishNew(Prefix+'-after.elf'),'збережено старий ELF');
    Need(not Window.RunCurrent,'допущено запуск застарілого ELF');
    Need(not Window.HasNativeResult,'стара фізична відповідь після відмови');
    Need(not Window.CompilePhysical(TextFile),
      'текстову .lisp-проєкцію прийнято як canonical');
    Need(not Window.CompilePhysical(Other),
      'сторонній машинний профіль прийнято');
    Need(Window.CompilePhysical(Sub),'відновлення після негативів');
    Need(Window.ImageBytes=FirstBytes,'недетермінований повторний D5 ELF');
    CheckNative(Sub,5);
    Need(Window.PublishNew(Prefix+'-recovery.elf'),'не збережено recovery');
    Need(not Window.SetRepositoryRoot(Prefix+'-absent'),
      'вигаданий SENS root прийнято');
    Need(not Window.HasVerifiedImage and (not Window.HasNativeResult),
      'старий ELF або stdout після втрати authority');
    Need(not Window.RunCurrent,'після втрати authority виконано ELF');
    Need(not Window.CompilePhysical(Sub),'виконання без pinned root');
    WriteLn('SENS-LAZARUS-IDE-КОМПІЛЯТОР-ГАРАЗД: ',
      'IDEIntf=так LCL=так фізичних=2 ELF=3 ',
      'native=3 T5M=exact no-stale=так відмов=5 ',
      'no-clobber=так recovery=так');
  finally Window.Free end;
end.
