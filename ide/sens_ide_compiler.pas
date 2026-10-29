{ G8.2 — IDE-вікно для справжнього verified WideIR->ELF64.
  Вхід: borrowed шлях до канонічного packed .sens; owned RawByteString.
  Результат: owned ELF image до наступного CompilePhysical.
  FPC тільки запускає наявний BuildVerifiedWideELF, не реалізує закони.
  Запитання: чому .lisp не є входом? Хто володіє FD?
  Чому ELF не є SENS доменом? Як чиститься попередній образ?
  Чому PublishNewELF64 не перезаписує існуючий файл? }
unit sens_ide_compiler;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,Classes,Forms,Controls,StdCtrls,Dialogs,ExtCtrls,
  wsm.elfgeometry;
type
  TSensIDECompiler=class(TForm)
  private
    FRoot:String; FImage:RawByteString; FGeom:TELFGeometry;
    FRootName,FStatus:TLabel; FPreview:TMemo;
    FChooseRoot,FCompile,FPublish:TButton;
    FSourceDialog:TOpenDialog; FOutputDialog:TSaveDialog;
    procedure ClearOutput;
    procedure RootClick(Sender:TObject);
    procedure SourceClick(Sender:TObject);
    procedure PublishClick(Sender:TObject);
  public
    constructor Create(AOwner:TComponent);override;
    function SetRepositoryRoot(const Path:String):Boolean;
    function CompilePhysical(const Path:String):Boolean;
    function PublishNew(const Path:String):Boolean;
    function HasVerifiedImage:Boolean;
    function ImageBytes:SizeInt;
    function MachineBytes:SizeInt;
    function StatusText:String;
  end;
implementation
uses wsm.irwidefront,wsm.elfpublish;
const MaxInput=65536;DisplayMachine=48;
constructor TSensIDECompiler.Create(AOwner:TComponent);
var Bar:TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — компілятор у Lazarus IDE';
  Width:=920;Height:=580;Position:=poScreenCenter;
  Bar:=TPanel.Create(Self);Bar.Parent:=Self;Bar.Align:=alTop;Bar.Height:=125;
  FChooseRoot:=TButton.Create(Self);FChooseRoot.Parent:=Bar;
  FChooseRoot.SetBounds(10,8,255,34);
  FChooseRoot.Caption:='Обрати корінь SENS';FChooseRoot.OnClick:=@RootClick;
  FCompile:=TButton.Create(Self);FCompile.Parent:=Bar;
  FCompile.SetBounds(275,8,265,34);
  FCompile.Caption:='Скомпілювати двійковий .sens';
  FCompile.OnClick:=@SourceClick;
  FPublish:=TButton.Create(Self);FPublish.Parent:=Bar;
  FPublish.SetBounds(550,8,355,34);
  FPublish.Caption:='Створити новий перевірений ELF64';
  FPublish.OnClick:=@PublishClick;
  FRootName:=TLabel.Create(Self);FRootName.Parent:=Bar;
  FRootName.SetBounds(10,49,895,24);
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Bar;
  FStatus.SetBounds(10,81,895,30);
  FPreview:=TMemo.Create(Self);FPreview.Parent:=Self;
  FPreview.Align:=alClient;FPreview.ReadOnly:=True;
  FPreview.ScrollBars:=ssVertical;
  FSourceDialog:=TOpenDialog.Create(Self);
  FSourceDialog.Title:='Обрати фізичний packed SENS';
  FSourceDialog.Filter:='Фізичний SENS (*.sens)|*.sens';
  FOutputDialog:=TSaveDialog.Create(Self);
  FOutputDialog.Filter:='Виконуваний ELF (*.elf)|*.elf';
  FOutputDialog.DefaultExt:='elf';
  FOutputDialog.Title:='Створити новий ELF64 без перезапису';
  FRoot:='';ClearOutput;
  FStatus.Caption:='Оберіть корінь wsm-lazarus з pinned SENS';
  if GetEnvironmentVariable('SENS_REPO_ROOT')<>'' then
    SetRepositoryRoot(GetEnvironmentVariable('SENS_REPO_ROOT'));
end;
procedure TSensIDECompiler.ClearOutput;
begin
  FImage:='';FillChar(FGeom,SizeOf(FGeom),0);FPublish.Enabled:=False;
  FPreview.Clear;
  FPreview.Lines.Add('Немає перевіреного машинного ELF64.');
end;
function TSensIDECompiler.SetRepositoryRoot(const Path:String):Boolean;
var Candidate:String;
begin
  FRoot:='';ClearOutput;Result:=False;
  FRootName.Caption:='Корінь: не встановлено';
  if Path='' then begin
    FStatus.Caption:='ВІДМОВА: порожній каталог';Exit;
  end;
  Candidate:=IncludeTrailingPathDelimiter(ExpandFileName(Path));
  if (not FileExists(Candidate+'AGENTS.md')) or
     (not FileExists(Candidate+'external/sens/contracts/language-contract-12.lisp')) or
     (not FileExists(Candidate+'external/sens/lib/core4.sens')) then begin
    FStatus.Caption:='ВІДМОВА: немає матеріалізованого pinned SENS';Exit;
  end;
  FRoot:=Candidate;FRootName.Caption:='Корінь: '+FRoot;
  FStatus.Caption:='Фізичний .sens; ратифікація лише pinned SENS';
  Result:=True;
end;
procedure TSensIDECompiler.RootClick(Sender:TObject);
var Picker:TSelectDirectoryDialog;
begin
  Picker:=TSelectDirectoryDialog.Create(Self);
  try
    Picker.Title:='Оберіть каталог wsm-lazarus';
    if Picker.Execute then SetRepositoryRoot(Picker.FileName);
  finally Picker.Free end;
end;
procedure TSensIDECompiler.SourceClick(Sender:TObject);
begin if FSourceDialog.Execute then CompilePhysical(FSourceDialog.FileName) end;
procedure TSensIDECompiler.PublishClick(Sender:TObject);
begin if FOutputDialog.Execute then PublishNew(FOutputDialog.FileName) end;
{ Попередній артефакт знищуємо ДО читання; тільки verified output
  повертається у стан IDE після pinned compiler і VerifySENSELF64. }
function TSensIDECompiler.CompilePhysical(const Path:String):Boolean;
var Input,Output:RawByteString;G:TELFGeometry;
    F:TFileStream;I,BytesToDisplay:SizeInt;Line:String;
begin
  Result:=False;ClearOutput;
  try
    if FRoot='' then raise Exception.Create('не обрано pinned корінь');
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('не канонічна текстова проєкція');
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MaxInput) then
        raise Exception.Create('порожній або завеликий T5M');
      SetLength(Input,SizeInt(F.Size));
      F.ReadBuffer(Input[1],Length(Input));
    finally F.Free end;
    Output:=BuildVerifiedWideELF(Input,
      RawByteString(FRoot+'external/sens'));
    VerifySENSELF64(Output,G);
    if (G.Kind<>3) or (G.Entry<>120) or
       (G.FileBytes<>Length(Output)) or (G.MachineBytes<1) then
      raise Exception.Create('непридатний ELF64 PIE');
    FImage:=Output;FGeom:=G;
    FPreview.Clear;
    FPreview.Lines.Add('Вхід: '+Path);
    FPreview.Lines.Add('ELF64 PIE: '+IntToStr(G.FileBytes)+' байтів');
    FPreview.Lines.Add('Машинний x86-64: '+IntToStr(G.MachineBytes)+' байтів');
    FPreview.Lines.Add('Точка входу: '+IntToStr(G.Entry));
    FPreview.Lines.Add('Машинні байти (hex, НЕ код SENS):');
    BytesToDisplay:=G.MachineBytes;
    if BytesToDisplay>DisplayMachine then BytesToDisplay:=DisplayMachine;
    Line:='';
    for I:=0 to BytesToDisplay-1 do begin
      if (I>0) and (I mod 12=0) then begin
        FPreview.Lines.Add(Line);Line:='';
      end;
      if Line<>'' then Line:=Line+' ';
      Line:=Line+IntToHex(Byte(FImage[121+I]),2);
    end;
    if Line<>'' then FPreview.Lines.Add(Line);
    FPublish.Enabled:=True;
    FStatus.Caption:='СКОМПІЛЬОВАНО: verified WideIR → ELF64';
    Result:=True;
  except on E:Exception do begin
    ClearOutput;FStatus.Caption:='ВІДМОВА: '+E.Message;
  end end;
end;
{ Публікація — тільки вже перевіреним no-clobber host API. }
function TSensIDECompiler.PublishNew(const Path:String):Boolean;
var G:TELFGeometry;
begin
  Result:=False;
  try
    if (not FPublish.Enabled) or (Length(FImage)=0) then
      raise Exception.Create('немає перевіреного ELF64');
    if LowerCase(ExtractFileExt(Path))<>'.elf' then
      raise Exception.Create('вихід повинен бути .elf');
    PublishNewELF64(Path,FImage,3,G);
    if (G.Kind<>3) or (G.FileBytes<>Length(FImage)) then
      raise Exception.Create('пошкоджено публікацію ELF64');
    FStatus.Caption:='ЗБЕРЕЖЕНО НОВИЙ ELF64: '+Path;
    Result:=True;
  except on E:Exception do
    FStatus.Caption:='ВІДМОВА ЗБЕРЕЖЕННЯ: '+E.Message;
  end;
end;
function TSensIDECompiler.HasVerifiedImage:Boolean;
begin Result:=FPublish.Enabled and (Length(FImage)>120) end;
function TSensIDECompiler.ImageBytes:SizeInt;
begin Result:=Length(FImage) end;
function TSensIDECompiler.MachineBytes:SizeInt;
begin Result:=FGeom.MachineBytes end;
function TSensIDECompiler.StatusText:String;
begin Result:=FStatus.Caption end;
end.
