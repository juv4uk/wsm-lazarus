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
uses SysUtils,Classes,Forms,Controls,StdCtrls,ComCtrls,Dialogs,ExtCtrls,
  wsm.elfgeometry;
type
  TSensIDECompiler=class(TForm)
  private
    FRoot:String; FImage,FNativeResult:RawByteString; FGeom:TELFGeometry;
    FRootName,FStatus:TLabel; FPreview:TMemo;
    FIRTree:TTreeView; FIRNodeCount,FIRRootCount:SizeInt;
    FChooseRoot,FCompile,FPublish,FRun:TButton;
    FSourceDialog:TOpenDialog; FOutputDialog:TSaveDialog;
    procedure ClearOutput;
    procedure BuildIRTree(const Physical:RawByteString);
    procedure RootClick(Sender:TObject);
    procedure SourceClick(Sender:TObject);
    procedure PublishClick(Sender:TObject);
    procedure RunClick(Sender:TObject);
  public
    constructor Create(AOwner:TComponent);override;
    function SetRepositoryRoot(const Path:String):Boolean;
    function CompilePhysical(const Path:String):Boolean;
    function PublishNew(const Path:String):Boolean;
    function RunCurrent:Boolean;
    function NativeResult:RawByteString;
    function HasNativeResult:Boolean;
    function HasVerifiedImage:Boolean;
    function ImageBytes:SizeInt;
    function MachineBytes:SizeInt;
    function IRNodeCount:SizeInt;
    function IRRootCount:SizeInt;
    function IRNodeText(Index:SizeInt):String;
    function StatusText:String;
  end;
implementation
uses wsm.irwidefront,wsm.elfpublish,wsm.elfexecute,wsm.t5m,
  wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard;
const MaxInput=65536;DisplayMachine=48;
constructor TSensIDECompiler.Create(AOwner:TComponent);
var Bar:TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — компілятор у Lazarus IDE';
  Width:=920;Height:=580;Position:=poScreenCenter;
  Bar:=TPanel.Create(Self);Bar.Parent:=Self;Bar.Align:=alTop;Bar.Height:=165;
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
  FRun:=TButton.Create(Self);FRun.Parent:=Bar;
  FRun.SetBounds(10,53,370,34);
  FRun.Caption:='Виконати перевірений ELF64';
  FRun.OnClick:=@RunClick;
  FRootName:=TLabel.Create(Self);FRootName.Parent:=Bar;
  FRootName.SetBounds(10,94,895,24);
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Bar;
  FStatus.SetBounds(10,126,895,30);
  FIRTree:=TTreeView.Create(Self);FIRTree.Parent:=Self;
  FIRTree.Align:=alLeft;FIRTree.Width:=410;
  FIRTree.ReadOnly:=True;FIRTree.HideSelection:=False;
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
  FImage:='';FNativeResult:='';
  FIRTree.Items.Clear;FIRNodeCount:=0;FIRRootCount:=0;
  FillChar(FGeom,SizeOf(FGeom),0);
  FPublish.Enabled:=False;FRun.Enabled:=False;
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
procedure TSensIDECompiler.RunClick(Sender:TObject);
begin RunCurrent end;
{ G8.4: справжнє дерево перевіреного WideIR поруч із машинним ELF.
  Вхід — borrowed canonical packed T5M; managed IR і pinned таблиці
  локальні, TTreeNode належить LCL формі. Лише host-візуалізація.
  W12+ — непрозорі фізичні біти, НЕ новий числовий закон D12.
  Запитання: чому відображаємо тритний інтервал, а не тільки байти?
  Чому ParentIndex завжди менший за I? Чому W24 не значить D24?
  Хто звільняє IR і вузли форми? Що стається після невдалого build? }
procedure TSensIDECompiler.BuildIRTree(const Physical:RawByteString);
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
  Parents:array of TTreeNode;N:TWideIRNode;
  I:SizeInt;LabelText,Meaning:String;
begin
  LoadPinnedDomains(RawByteString(FRoot+'external/sens'),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  if (Stats.Roots<>1) or (Stats.Nodes<3) then
    raise Exception.Create('WideIR має містити один корінь і перевірені вузли');
  SetLength(Parents,Stats.Nodes);
  FIRTree.Items.BeginUpdate;
  try
    FIRTree.Items.Clear;FIRNodeCount:=0;FIRRootCount:=0;
    for I:=0 to High(IR.Nodes) do begin
      N:=IR.Nodes[I];
      case N.Kind of
        wkList:Meaning:='D2 список';
        wkPair:Meaning:='D2 похідна пара';
        wkEmpty:Meaning:='D3:000 порожній список';
        wkAtom:if N.HasPinnedKey then
          Meaning:='D'+IntToStr(N.Width)+':'+String(N.Bits)
          else Meaning:='W'+IntToStr(N.Width)+':'+String(N.Bits)+
            ' (непрозорі фізичні дані)';
        else raise Exception.Create('невідомий вузол pinned WideIR');
      end;
      LabelText:=Meaning+' | слово '+IntToStr(N.WordIndex)+
        ' | трити ['+IntToStr(N.Physical.TritStart)+','+
        IntToStr(N.Physical.TritEnd)+')'+
        ' | байти ['+IntToStr(N.Physical.ByteStart)+','+
        IntToStr(N.Physical.ByteEnd)+')';
      if N.ParentIndex=-1 then
        Parents[I]:=FIRTree.Items.Add(nil,LabelText)
      else begin
        if (N.ParentIndex<0) or (N.ParentIndex>=I) or
           (Parents[N.ParentIndex]=nil) then
          raise Exception.Create('неправильне батьківське ребро WideIR');
        Parents[I]:=FIRTree.Items.AddChild(Parents[N.ParentIndex],LabelText);
      end;
    end;
    FIRNodeCount:=Stats.Nodes;
    FIRRootCount:=Stats.Roots;
    if FIRTree.Items.GetFirstNode<>nil then
      FIRTree.Items.GetFirstNode.Expand(False);
  finally FIRTree.Items.EndUpdate end;
end;

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
    BuildIRTree(Input);
    FImage:=Output;FGeom:=G;
    FPreview.Clear;
    FPreview.Lines.Add('Вхід: '+Path);
    FPreview.Lines.Add('ELF64 PIE: '+IntToStr(G.FileBytes)+' байтів');
    FPreview.Lines.Add('Машинний x86-64: '+IntToStr(G.MachineBytes)+' байтів');
    FPreview.Lines.Add('Дерево pinned WideIR: '+IntToStr(FIRNodeCount)+
      ' вузлів, коренів='+IntToStr(FIRRootCount));
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
    FPublish.Enabled:=True;FRun.Enabled:=True;
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
{ G8.3: тільки вже допущений FImage (owned byte image) передається
  позиченим параметром перевіреному host-only RunVerifiedELF. TProcess,
  приватний виконуваний файл і каталог належать цьому donor і там
  звільняються; IDE володіє лише фізичним ResultRaw.
  Питання: чому ми не виконуємо довільний шлях?
  Чому після відмови не можна показати старий T5M?
  Чому stdout мусить бути одним точним словом, а не текстом «укр»?
  Чому width D12 і binary bits не переводяться до host integer?
  Що гарантує окремий ліміт виконання донорного host API? }
function TSensIDECompiler.RunCurrent:Boolean;
var Physical:RawByteString;Words:TExactWords;
begin
  Result:=False;FNativeResult:='';
  try
    if (not FRun.Enabled) or (not HasVerifiedImage) then
      raise EVerifiedELFRun.Create('немає допущеного машинного ELF64');
    RunVerifiedELF(FImage,Physical);
    DecodeT5M(Physical,Words);
    if (Length(Words)<>1) or (EncodeT5M(Words)<>Physical) then
      raise EVerifiedELFRun.Create('неканонічна фізична відповідь T5M');
    FNativeResult:=Physical;
    FPreview.Lines.Add('ВИКОНАНО: фізичний T5M stdout: '+
      IntToStr(Length(Physical))+' байтів, W'+IntToStr(Length(Words[0])));
    FPreview.Lines.Add('Точні двійкові біти: '+String(Words[0]));
    FStatus.Caption:='ВИКОНАНО: точний T5M stdout, '+
      IntToStr(Length(Physical))+' фізичних байтів';
    Result:=True;
  except on E:Exception do begin
    FNativeResult:='';FRun.Enabled:=False;
    FPreview.Lines.Add('ВІДМОВА ВИКОНАННЯ: '+E.Message);
    FStatus.Caption:='ВІДМОВА ВИКОНАННЯ: '+E.Message;
  end end;
end;
function TSensIDECompiler.NativeResult:RawByteString;
begin Result:=FNativeResult end;
function TSensIDECompiler.HasNativeResult:Boolean;
begin Result:=Length(FNativeResult)>0 end;
function TSensIDECompiler.HasVerifiedImage:Boolean;
begin Result:=FPublish.Enabled and (Length(FImage)>120) end;
function TSensIDECompiler.ImageBytes:SizeInt;
begin Result:=Length(FImage) end;
function TSensIDECompiler.MachineBytes:SizeInt;
begin Result:=FGeom.MachineBytes end;
function TSensIDECompiler.IRNodeCount:SizeInt;
begin Result:=FIRNodeCount end;
function TSensIDECompiler.IRRootCount:SizeInt;
begin Result:=FIRRootCount end;
function TSensIDECompiler.IRNodeText(Index:SizeInt):String;
begin
  Result:='';
  if (Index>=0) and (Index<FIRNodeCount) and
     (Index<FIRTree.Items.Count) then Result:=FIRTree.Items[Index].Text;
end;
function TSensIDECompiler.StatusText:String;
begin Result:=FStatus.Caption end;
end.
