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
    Need(Window.PublishNew(Prefix+'-sub.elf'),'немає нового ELF64 D5');
    Need(not Window.PublishNew(Prefix+'-sub.elf'),'перезаписано старий ELF');
    Need(Window.CompilePhysical(NSD),'D6 фізична програма');
    Need(Window.HasVerifiedImage and Window.ImageBytes>120,
      'D6 ELF не пройшов verification');
    Need(Window.PublishNew(Prefix+'-nsd.elf'),'немає нового ELF64 D6');
    Need(not Window.CompilePhysical(Bad),'неканонічний T5M прийнято');
    Need(not Window.HasVerifiedImage and
      (Window.ImageBytes=0) and (Window.MachineBytes=0),
      'після помилки залишився старий ELF');
    Need(not Window.PublishNew(Prefix+'-after.elf'),'збережено старий ELF');
    Need(not Window.CompilePhysical(TextFile),
      'текстову .lisp-проєкцію прийнято як canonical');
    Need(not Window.CompilePhysical(Other),
      'сторонній машинний профіль прийнято');
    Need(Window.CompilePhysical(Sub),'відновлення після негативів');
    Need(Window.ImageBytes=FirstBytes,'недетермінований повторний D5 ELF');
    Need(Window.PublishNew(Prefix+'-recovery.elf'),'не збережено recovery');
    Need(not Window.SetRepositoryRoot(Prefix+'-absent'),
      'вигаданий SENS root прийнято');
    Need(not Window.HasVerifiedImage,'старий ELF після втрати authority');
    Need(not Window.CompilePhysical(Sub),'виконання без pinned root');
    WriteLn('SENS-LAZARUS-IDE-КОМПІЛЯТОР-ГАРАЗД: ',
      'IDEIntf=так LCL=так фізичних=2 ELF=3 ',
      'відмов=5 no-clobber=так recovery=так');
  finally Window.Free end;
end.
