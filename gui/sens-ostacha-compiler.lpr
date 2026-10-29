{ G6.114 — справжній Lazarus/LCL оглядач перевіреної native-компіляції
  D6:010100. GUI тільки проєктує вже допущений pinned WideIR та ELF64.
  Вхід: borrowed шлях до фізичної .sens; source/ELF — managed owned bytes.
  TTreeView/TStringGrid/TPaintBox володіє TForm; потік — finally.
  НІЯКОГО текстового dispatch, Core1 копіювання або виконання ELF у GUI.
  1) Чому слово W12 лишається непрозорим до BuildIRWideRestELF?
  2) Де незалежно перевірено pinned D6 та sign overflow?
  3) Чому збереження лише PublishNewELF64 без перезапису?
  4) Чому байти ELF не є законами SENS?
  5) Чому на відмові очищуємо всі віджети та майбутній образ? }
program sens_ostacha_compiler;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,ExtCtrls,
  Grids,ComCtrls,Dialogs,Graphics,
  wsm.irwiderest,wsm.wideir,wsm.wideirguard,wsm.domain,wsm.bind,
  wsm.t5m,wsm.elfgeometry,wsm.elfpublish;
const MaxDisplayBytes=64;
type
  TCompilerWindow=class(TForm)
  private
    FOpenButton,FSaveButton:TButton;
    FStatus,FSelected:TLabel;
    FOpenDialog:TOpenDialog;
    FSaveDialog:TSaveDialog;
    FTree:TTreeView;
    FNodeGrid,FByteGrid:TStringGrid;
    FPicture:TPaintBox;
    FImage:RawByteString;
    FNodes:TWideIR;
    FGeometry:TELFGeometry;
    FTreeNodes:array of TTreeNode;
    procedure ClearView;
    procedure Reject(const Reason:String);
    procedure OpenClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure TreeChange(Sender:TObject;Node:TTreeNode);
    procedure PreviewPaint(Sender:TObject);
    procedure DrawPreview(C:TCanvas);
    procedure Must(Condition:Boolean;const Why:String);
    function SaveELF(const Destination:String):Boolean;
  public
    constructor Create(AOwner:TComponent);override;
    function LoadPhysical(const Path:String):Boolean;
    procedure SelfTest(const First,Second,Bad,TextFile,ZeroFile,Output:String);
  end;
var Window:TCompilerWindow;

constructor TCompilerWindow.Create(AOwner:TComponent);
var BarTop,PaneLeft,PaneBottom,PaneRight:TPanel;Splitter:TSplitter;I:Integer;
const Titles:array[0..5] of String=
  ('№','Родина','Точні біти','Ширина','Трити','Байти');
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — компілятор D6 «остача» · Lazarus';
  Width:=1280;Height:=780;Position:=poScreenCenter;
  BarTop:=TPanel.Create(Self);BarTop.Parent:=Self;BarTop.Align:=alTop;
  BarTop.Height:=56;BarTop.BevelOuter:=bvNone;
  FOpenButton:=TButton.Create(Self);FOpenButton.Parent:=BarTop;
  FOpenButton.SetBounds(12,9,280,36);
  FOpenButton.Caption:='Компілювати фізичний .sens';
  FOpenButton.OnClick:=@OpenClick;
  FSaveButton:=TButton.Create(Self);FSaveButton.Parent:=BarTop;
  FSaveButton.SetBounds(309,9,310,36);
  FSaveButton.Caption:='Зберегти перевірений ELF64 (новий файл)';
  FSaveButton.OnClick:=@SaveClick;
  FOpenDialog:=TOpenDialog.Create(Self);
  FOpenDialog.Filter:='Фізичний SENS (*.sens)|*.sens';
  FOpenDialog.Title:='Оберіть canonical packed .sens';
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.Filter:='Виконуваний Linux ELF (*.elf)|*.elf';
  FSaveDialog.DefaultExt:='elf';
  FSaveDialog.Title:='Створити новий перевірений ELF64';
  PaneBottom:=TPanel.Create(Self);PaneBottom.Parent:=Self;PaneBottom.Align:=alBottom;
  PaneBottom.Height:=178;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=PaneBottom;
  FStatus.SetBounds(10,5,1240,26);
  FSelected:=TLabel.Create(Self);FSelected.Parent:=PaneBottom;
  FSelected.SetBounds(10,34,1240,25);
  FPicture:=TPaintBox.Create(Self);FPicture.Parent:=PaneBottom;
  FPicture.SetBounds(10,65,1240,100);FPicture.OnPaint:=@PreviewPaint;
  PaneLeft:=TPanel.Create(Self);PaneLeft.Parent:=Self;PaneLeft.Align:=alLeft;
  PaneLeft.Width:=315;PaneLeft.BevelOuter:=bvNone;
  FTree:=TTreeView.Create(Self);FTree.Parent:=PaneLeft;FTree.Align:=alClient;
  FTree.ReadOnly:=True;FTree.OnChange:=@TreeChange;
  Splitter:=TSplitter.Create(Self);Splitter.Parent:=Self;
  Splitter.Align:=alLeft;Splitter.Width:=6;
  PaneRight:=TPanel.Create(Self);PaneRight.Parent:=Self;PaneRight.Align:=alClient;
  PaneRight.BevelOuter:=bvNone;
  FNodeGrid:=TStringGrid.Create(Self);FNodeGrid.Parent:=PaneRight;
  FNodeGrid.Align:=alTop;FNodeGrid.Height:=255;
  FNodeGrid.ColCount:=6;FNodeGrid.FixedCols:=0;
  FNodeGrid.RowCount:=2;FNodeGrid.FixedRows:=1;
  FNodeGrid.ColWidths[0]:=45;FNodeGrid.ColWidths[1]:=110;
  FNodeGrid.ColWidths[2]:=220;FNodeGrid.ColWidths[3]:=110;
  FNodeGrid.ColWidths[4]:=130;FNodeGrid.ColWidths[5]:=130;
  for I:=0 to 5 do FNodeGrid.Cells[I,0]:=Titles[I];
  FByteGrid:=TStringGrid.Create(Self);FByteGrid.Parent:=PaneRight;
  FByteGrid.Align:=alClient;FByteGrid.ColCount:=3;
  FByteGrid.FixedCols:=0;FByteGrid.RowCount:=2;
  FByteGrid.FixedRows:=1;
  FByteGrid.ColWidths[0]:=120;FByteGrid.ColWidths[1]:=120;
  FByteGrid.ColWidths[2]:=560;
  FByteGrid.Cells[0,0]:='Фізичний offset ELF';
  FByteGrid.Cells[1,0]:='Байт hex';
  FByteGrid.Cells[2,0]:='Машинні дані · не Dn закон';
  ClearView;
end;

procedure TCompilerWindow.ClearView;
var I:Integer;
begin
  FImage:='';SetLength(FNodes.Nodes,0);SetLength(FNodes.Roots,0);
  SetLength(FTreeNodes,0);FillChar(FGeometry,SizeOf(FGeometry),0);
  FTree.Items.Clear;
  FNodeGrid.RowCount:=2;FByteGrid.RowCount:=2;
  for I:=0 to 5 do FNodeGrid.Cells[I,1]:='';
  for I:=0 to 2 do FByteGrid.Cells[I,1]:='';
  FSaveButton.Enabled:=False;
  FSelected.Caption:='W12 непрозорий до exact-domain допуску; машинні байти не є законами.';
  FPicture.Invalidate;
end;

procedure TCompilerWindow.Reject(const Reason:String);
begin
  ClearView;
  FStatus.Caption:='ВІДМОВА: '+Reason;
end;

procedure TCompilerWindow.Must(Condition:Boolean;const Why:String);
begin
  if not Condition then
    raise Exception.Create('LCL-перевірка: '+Why);
end;

procedure TCompilerWindow.OpenClick(Sender:TObject);
begin
  if FOpenDialog.Execute then LoadPhysical(FOpenDialog.FileName);
end;

procedure TCompilerWindow.SaveClick(Sender:TObject);
begin
  if FSaveDialog.Execute then SaveELF(FSaveDialog.FileName);
end;

function TCompilerWindow.LoadPhysical(const Path:String):Boolean;
var Stream:TFileStream; Source,Image:RawByteString;
    Tables:TDomainSet; Candidate:TWideIR; Stats:TWideIRGuardStats;
    Geometry:TELFGeometry;I,N,ParentIndex:SizeInt;Item:TWideIRNode;
    Nodes:array of TTreeNode;KindLabel,WidthLabel:String;
begin
  Result:=False;ClearView;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('вхід тільки двійковий .sens, не .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>65536) then
        raise Exception.Create('порожній або завеликий фізичний файл');
      SetLength(Source,SizeInt(Stream.Size));
      Stream.ReadBuffer(Source[1],Length(Source));
    finally Stream.Free end;
    { Вхід справді компілюється і проходить існуючий exact pin/IR,
      numeric admission, native emitter та ELF64 geometry. }
    Image:=BuildIRWideRestELF(Source,'external/sens');
    VerifySENSELF64(Image,Geometry);
    if (Geometry.Kind<>3) or (Geometry.Entry<>120) then
      raise Exception.Create('неправильний native PIE профіль');
    LoadPinnedDomains('external/sens',Tables);
    BuildWideIR(Source,Tables,Candidate);
    VerifyWideIRStructure(Candidate,Stats);
    if (Stats.Nodes<>4) or (Length(Candidate.Nodes)<>4) then
      raise Exception.Create('непідтримана кількість IR вузлів');
    FImage:=Image;FNodes:=Candidate;FGeometry:=Geometry;
    SetLength(Nodes,Length(FNodes.Nodes));
    FNodeGrid.RowCount:=Length(FNodes.Nodes)+1;
    FTree.Items.BeginUpdate;
    try
      for I:=0 to High(FNodes.Nodes) do begin
        Item:=FNodes.Nodes[I];
        ParentIndex:=Item.ParentIndex;
        if (ParentIndex>=I) then raise Exception.Create('неправильний IR батько');
        if ParentIndex>=0 then Nodes[I]:=FTree.Items.AddChild(Nodes[ParentIndex],
          IntToStr(I)+' · D'+IntToStr(Item.Width))
        else Nodes[I]:=FTree.Items.AddChild(nil,'Корінь · D2 список');
        Nodes[I].Data:=Pointer(PtrInt(I+1));
        KindLabel:='D2 список';WidthLabel:='—';
        if Item.Kind=wkAtom then begin
          KindLabel:='бінарний атом';
          if Item.HasPinnedKey then WidthLabel:='D'+IntToStr(Item.Width)+' pinned'
          else WidthLabel:='W'+IntToStr(Item.Width)+' opaque';
        end;
        FNodeGrid.Cells[0,I+1]:=IntToStr(I);
        FNodeGrid.Cells[1,I+1]:=KindLabel;
        FNodeGrid.Cells[2,I+1]:=String(Item.Bits);
        FNodeGrid.Cells[3,I+1]:=WidthLabel;
        if Item.OwnWord then begin
          FNodeGrid.Cells[4,I+1]:='['+
            IntToStr(Item.Physical.TritStart)+','+
            IntToStr(Item.Physical.TritEnd)+')';
          FNodeGrid.Cells[5,I+1]:='['+
            IntToStr(Item.Physical.ByteStart)+','+
            IntToStr(Item.Physical.ByteEnd)+')';
        end else begin
          FNodeGrid.Cells[4,I+1]:='похідний';
          FNodeGrid.Cells[5,I+1]:='—';
        end;
      end;
    finally FTree.Items.EndUpdate end;
    FTreeNodes:=Nodes;
    N:=Length(FImage)-120;
    if N>MaxDisplayBytes then N:=MaxDisplayBytes;
    FByteGrid.RowCount:=N+1;
    for I:=0 to N-1 do begin
      FByteGrid.Cells[0,I+1]:=IntToStr(I+120);
      FByteGrid.Cells[1,I+1]:=IntToHex(Byte(FImage[I+121]),2);
      FByteGrid.Cells[2,I+1]:='реальний ELF64/x86-64 · offset '+IntToStr(I);
    end;
    FTree.FullExpand;
    FStatus.Caption:='СКОМПІЛЬОВАНО: pinned D6:010100 → ELF64 PIE · '+
      IntToStr(FGeometry.FileBytes)+' байтів · Entry='+
      IntToStr(FGeometry.Entry)+' · НЕ повний SENS компілятор';
    FSaveButton.Enabled:=True;
    FTree.Selected:=FTreeNodes[1];
    FPicture.Invalidate;
    Result:=True;
  except on E:Exception do Reject(E.Message) end;
end;

procedure TCompilerWindow.TreeChange(Sender:TObject;Node:TTreeNode);
var I:SizeInt;
begin
  if Node=nil then Exit;
  I:=PtrInt(Node.Data)-1;
  if (I<0) or (I>=Length(FNodes.Nodes)) then Exit;
  FNodeGrid.Row:=I+1;
  FSelected.Caption:='Вузол '+IntToStr(I)+
    ' · слово '+IntToStr(FNodes.Nodes[I].WordIndex)+
    ' · ширина '+IntToStr(FNodes.Nodes[I].Width)+
    ' · біти '+String(FNodes.Nodes[I].Bits)+
    ' · бітовий рисунок ≠ десяткова семантика';
end;

procedure TCompilerWindow.DrawPreview(C:TCanvas);
var I,Count,X:Integer;
begin
  C.Brush.Color:=clWhite;
  C.FillRect(0,0,FPicture.Width,FPicture.Height);
  Count:=Length(FImage)-120;
  if Count>32 then Count:=32;
  if Count<=0 then Exit;
  for I:=0 to Count-1 do begin
    X:=8+I*24;
    if (Byte(FImage[121+I]) and 1)<>0 then C.Brush.Color:=clNavy
    else C.Brush.Color:=clSilver;
    C.Pen.Color:=clGray;
    C.Rectangle(X,8,X+18,29);
    C.Font.Color:=clBlack;
    C.TextOut(X,34,IntToHex(Byte(FImage[121+I]),2));
  end;
  C.Brush.Color:=clWhite;
  C.TextOut(8,74,'Перші '+IntToStr(Count)+
    ' реальних байтів машинного коду після ELF header; не SENS opcode');
end;

procedure TCompilerWindow.PreviewPaint(Sender:TObject);
begin DrawPreview(FPicture.Canvas) end;

function TCompilerWindow.SaveELF(const Destination:String):Boolean;
var G:TELFGeometry;
begin
  Result:=False;
  try
    if (not FSaveButton.Enabled) or (Length(FImage)<=120) then
      raise Exception.Create('немає допущеного машинного ELF');
    if LowerCase(ExtractFileExt(Destination))<>'.elf' then
      raise Exception.Create('потрібен новий .elf файл');
    PublishNewELF64(Destination,FImage,3,G);
    if (G.FileBytes<>Length(FImage)) then
      raise Exception.Create('неповне збереження ELF');
    Result:=True;
  except on E:Exception do FStatus.Caption:='ELF не збережено: '+E.Message end;
end;

procedure TCompilerWindow.SelfTest(
  const First,Second,Bad,TextFile,ZeroFile,Output:String);
var Saved:TFileStream;Payload:RawByteString;Bitmap:TBitmap;
    ExpectedColor:TColor;
begin
  Must(LoadPhysical(First),'перший фізичний positive не скомпільовано');
  Must((FTree.Items.Count=4) and (FNodeGrid.RowCount=5),
    'у справжньому LCL загублено 4 вузли pinned WideIR');
  Must(FNodes.Nodes[1].HasPinnedKey and
    (FNodes.Nodes[1].Bits='010100') and
    (FNodes.Nodes[2].Width=12) and
    (not FNodes.Nodes[2].HasPinnedKey),'D6 або opaque D12 підмінено');
  Must(FSaveButton.Enabled and (FByteGrid.RowCount>16) and
    (Pos('СКОМПІЛЬОВАНО',FStatus.Caption)=1),
    'справжня компіляція не заповнила GTK2 віджети');
  Bitmap:=TBitmap.Create;
  try
    Bitmap.SetSize(800,100);DrawPreview(Bitmap.Canvas);
    if (Byte(FImage[121]) and 1)<>0 then ExpectedColor:=clNavy
    else ExpectedColor:=clSilver;
    Must(Bitmap.Canvas.Pixels[10,12]=ExpectedColor,
      'Canvas не відобразив дійсний перший машинний байт');
  finally Bitmap.Free end;
  Must(SaveELF(Output),'не вдалося атомарно опублікувати ELF');
  Saved:=TFileStream.Create(Output,fmOpenRead);
  try
    SetLength(Payload,SizeInt(Saved.Size));
    Saved.ReadBuffer(Payload[1],Length(Payload));
  finally Saved.Free end;
  Must(Payload=FImage,'збережений ELF не тотожний машинному образу');
  Must(not SaveELF(Output),'існуючий ELF перезаписано');
  Must(LoadPhysical(Second),'signed фізичний positive не скомпільовано');
  Must(SaveELF(Output+'.signed.elf'),
    'signed фізична програма не зберегла машинний ELF');
  Must((FTree.Items.Count=4) and FSaveButton.Enabled,
    'signed програма не повернула свіжий графічний стан');
  Must(not LoadPhysical(Bad),'зіпсований T5M прийнято');
  Must((Length(FImage)=0) and (FTree.Items.Count=0) and
    (not FSaveButton.Enabled) and
    (FNodeGrid.Cells[2,1]='') and (FByteGrid.Cells[1,1]=''),
    'після відмови лишився старий ELF або вузли');
  Must(not LoadPhysical(TextFile),'текстова .lisp помилково стала каноном');
  Must(not LoadPhysical(ZeroFile),'ділення на нуль прийнято');
  Must(not SaveELF(Output+'-після-відмови.elf'),
    'після відмови створено ELF');
  Must(LoadPhysical(First),'немає відновлення після 3 помилок');
  WriteLn('ЛАЗАРУС-ОСТАЧА-ГОТОВО GTK2=так IR=4 ELF=справжній ',
    'signed=так Canvas=байти no-clobber=так відмов=3 recovery=так');
end;

begin
  Application.Initialize;
  Application.CreateForm(TCompilerWindow,Window);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>7 then Halt(64);
    try
      Window.Show;Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
      Halt(0);
    except on E:Exception do begin
      WriteLn(StdErr,'ЛАЗАРУС-ОСТАЧА-ПОМИЛКА: ',E.Message);
      Halt(1);
    end end
  end;
  if ParamCount=1 then Window.LoadPhysical(ParamStr(1));
  Application.Run;
end.
