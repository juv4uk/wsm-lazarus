{ Справжній LCL/Xvfb тест форми, якою користується IDEIntf пакунок.
  Немає виконання .sens або прихованого текстового SENS dispatch. }
program test_sens_ide_map;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,SysUtils,Classes,sens_ide_window;
type
  TOpenProbe=class
    Count:Integer;
    LastPath:String;
    procedure OpenPath(const Path:String);
  end;
procedure TOpenProbe.OpenPath(const Path:String);
begin
  Inc(Count);LastPath:=Path;
end;
procedure Need(Ok:Boolean;const Reason:String);
begin
  if not Ok then raise Exception.Create('КАРТА-IDE-ПРОВАЛ: '+Reason);
end;
var Window:TSensMapWindow;Probe:TOpenProbe;Root,WrongRoot:String;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);WrongRoot:=ParamStr(2);
  Application.Initialize;
  Probe:=TOpenProbe.Create;
  Window:=TSensMapWindow.Create(nil);
  try
    Need(Window.SetRepositoryRoot(Root),'дійсний корінь відхилено');
    Need(Window.EntryCount=8,'мапа має рівно 8 наявних координат шляхів');
    Need(not Window.OpenEntry(-1),'негативний індекс');
    Need(not Window.OpenEntry(8),'індекс поза межами');
    Need(not Window.OpenEntry(6),'без IDE callback відкриття заборонено');
    Window.OnOpenPath:=@Probe.OpenPath;
    Window.Show;
    Application.ProcessMessages;
    Need(Window.Visible,'справжнє графічне LCL-вікно не показано');
    Need(Window.OpenEntry(6),'не відкрився дійсний LCL інспектор');
    Need(Probe.Count=1,'рівно один IDE callback');
    Need(ExtractFileName(Probe.LastPath)='sens-inspector.lpi',
      'мапа відкрила не існуючий інспектор');
    Need(Window.OpenEntry(4),'не відкрився source WideIR');
    Need(Probe.Count=2,'другий IDE callback');
    Need(ExtractFileName(Probe.LastPath)='wsm.irwidefront.pas',
      'неправильний компіляторний файл');
    Need(not Window.SetRepositoryRoot(WrongRoot),
      'неправильний корінь допущено');
    Need(Window.EntryCount=0,'старий snapshot лишився після відмови');
    Need(not Window.OpenEntry(6),'відкриття після відмови');
    Need(Probe.Count=2,'callback після відмови');
    Need(Window.SetRepositoryRoot(Root),'відновлення кореня');
    Need(Window.EntryCount=8,'відновлення повної карти');
    WriteLn('SENS-LAZARUS-IDE-МАПА-ГАРАЗД: LCL=так файлів=8 відкриттів=2 негативи=4 відновлення=так');
  finally
    Window.Free;
    Probe.Free;
  end;
end.
