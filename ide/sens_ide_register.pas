{ Підключення команди SENS до справжньої Lazarus IDE, без нового
  reader, compiler, executor, registry або зміни pinned законів. }
unit sens_ide_register;
{$mode objfpc}{$H+}{$codepage utf8}
interface
procedure Register;
implementation
uses SysUtils, Classes, Forms, Controls, MenuIntf, LazIDEIntf,
     sens_ide_window,sens_ide_compiler;

type
  TSensIDEBridge=class
  private
    FWindow:TSensMapWindow;
    FCompiler:TSensIDECompiler;
    procedure HideWindow(Sender:TObject;var CloseAction:TCloseAction);
  public
    procedure ShowMap(Sender:TObject);
    procedure ShowCompiler(Sender:TObject);
    procedure OpenPath(const Path:String);
    destructor Destroy;override;
  end;
var Bridge:TSensIDEBridge;

procedure TSensIDEBridge.HideWindow(Sender:TObject;var CloseAction:TCloseAction);
begin CloseAction:=caHide end;

procedure TSensIDEBridge.ShowMap(Sender:TObject);
begin
  if FWindow=nil then begin
    FWindow:=TSensMapWindow.Create(nil);
    FWindow.OnClose:=@HideWindow;
    FWindow.OnOpenPath:=@OpenPath;
  end;
  FWindow.Show;
  FWindow.BringToFront;
end;

{ Замість зовнішнього shell-процесу використовуємо IDEIntf.
  Документ .lpi відкривається як проєкт, інші шляхи — як файли.
  Тут не здійснюється запуск або семантичне розпізнавання SENS.
  1) Чому .lpi потребує DoOpenProjectFile, а не компілятора?
  2) Чому .sens тут можна переглядати, але не виконувати?
  3) Хто володіє вікном між повторними викликами меню?
  4) Де перевірено існування файлу? }
{ Друга IDE-команда відкриває сам Lazarus TForm над спільним
  headless BuildVerifiedWideELF. Жодного окремого процесу GUI. }
procedure TSensIDEBridge.ShowCompiler(Sender:TObject);
begin
  if FCompiler=nil then begin
    FCompiler:=TSensIDECompiler.Create(nil);
    FCompiler.OnClose:=@HideWindow;
  end;
  FCompiler.Show;
  FCompiler.BringToFront;
end;

procedure TSensIDEBridge.OpenPath(const Path:String);
begin
  if SameText(ExtractFileExt(Path),'.lpi') then
    LazarusIDE.DoOpenProjectFile(Path,[ofAddToRecent])
  else
    LazarusIDE.DoOpenEditorFile(Path,-1,-1,
      [ofOnlyIfExists,ofAddToRecent,ofRegularFile]);
end;

destructor TSensIDEBridge.Destroy;
begin
  FWindow.Free;
  FCompiler.Free;
  inherited Destroy;
end;

procedure Register;
begin
  if Bridge=nil then Bridge:=TSensIDEBridge.Create;
  RegisterIDEMenuCommand(itmSecondaryTools,'SENSMapaProiektu',
    'SENS: мапа проєкту',@Bridge.ShowMap,nil,nil);
  RegisterIDEMenuCommand(itmSecondaryTools,'SENSVerifiedCompiler',
    'SENS: скомпілювати .sens',@Bridge.ShowCompiler,nil,nil);
end;

finalization
  Bridge.Free;
end.
