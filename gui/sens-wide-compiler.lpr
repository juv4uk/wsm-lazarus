{ Візуальний клієнт спільного перевіреного компілятора.
  Вхід — borrowed шлях до фізичного .sens; RawByteString читається до
  65536 байтів, результат — owned ELF і WideIR у TForm до ClearView.
  Всі форми, LCL controls і managed масиви звільняються з TForm.
  BuildVerifiedWideELF є єдиним шляхом компіляції, не GUI-закон.
  Питання: чому W12 opaque? чому .lisp не canonical?
  навіщо атомарна відмова? хто володіє ELF? чому GUI не oracle? }
program sens_wide_compiler;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,ExtCtrls,
  Grids,ComCtrls,Dialogs,Graphics,
  wsm.irwidefront,wsm.wideir,wsm.wideirguard,wsm.domain,wsm.bind,
  wsm.elfgeometry,wsm.elfpublish;
type
  TCompilerWindow=class(TForm)
  private
    FOpen,FSave:TButton;FStatus,FSelected:TLabel;
    FOpenDialog:TOpenDialog;FSaveDialog:TSaveDialog;
    FTree:TTreeView;FGrid,FBytes:TStringGrid;FPreview:TPaintBox;
    FImage:RawByteString;FNodes:TWideIR;
    procedure ClearView;
    procedure Fail(const Reason:String);
    procedure OpenClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure TreeChange(Sender:TObject;Node:TTreeNode);
    procedure PreviewPaint(Sender:TObject);
    procedure PaintBytes(C:TCanvas);
    procedure Need(OK:Boolean;const Why:String);
    function SaveVerified(const Path:String):Boolean;
  public
    constructor Create(AOwner:TComponent);override;
    function LoadPhysical(const Path:String):Boolean;
    procedure SelfTest(const SubFile,NsdFile,BadFile,TextFile,Unsupported,Prefix:String);
  end;
var Window:TCompilerWindow;
constructor TCompilerWindow.Create(AOwner:TComponent);
var Top,Left,Right,Bottom:TPanel;Split:TSplitter;I:Integer;
const Headers:array[0..5] of String=
  ('Вузол','Структура','Точні біти','Домен/слово','Трити','Байти');
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — спільний фізичний компілятор · Lazarus';
  Width:=1230;Height:=780;Position:=poScreenCenter;
  Top:=TPanel.Create(Self);Top.Parent:=Self;Top.Align:=alTop;Top.Height:=53;
  FOpen:=TButton.Create(Self);FOpen.Parent:=Top;
  FOpen.SetBounds(12,8,280,35);FOpen.Caption:='Компілювати фізичний .sens';
  FOpen.OnClick:=@OpenClick;
  FSave:=TButton.Create(Self);FSave.Parent:=Top;
  FSave.SetBounds(312,8,315,35);
  FSave.Caption:='Створити новий перевірений ELF64';
  FSave.OnClick:=@SaveClick;
  FOpenDialog:=TOpenDialog.Create(Self);
  FOpenDialog.Title:='Оберіть двійкову canonical SENS-програму';
  FOpenDialog.Filter:='Фізичний SENS (*.sens)|*.sens';
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.Title:='Створити ELF64 без перезапису';
  FSaveDialog.Filter:='Виконуваний ELF (*.elf)|*.elf';
  FSaveDialog.DefaultExt:='elf';
  Bottom:=TPanel.Create(Self);Bottom.Parent:=Self;
  Bottom.Align:=alBottom;Bottom.Height:=175;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Bottom;
  FStatus.SetBounds(10,5,1190,25);
  FSelected:=TLabel.Create(Self);FSelected.Parent:=Bottom;
  FSelected.SetBounds(10,35,1190,25);
  FPreview:=TPaintBox.Create(Self);FPreview.Parent:=Bottom;
  FPreview.SetBounds(10,65,1190,95);FPreview.OnPaint:=@PreviewPaint;
  Left:=TPanel.Create(Self);Left.Parent:=Self;Left.Align:=alLeft;Left.Width:=310;
  FTree:=TTreeView.Create(Self);FTree.Parent:=Left;FTree.Align:=alClient;
  FTree.ReadOnly:=True;FTree.OnChange:=@TreeChange;
  Split:=TSplitter.Create(Self);Split.Parent:=Self;Split.Align:=alLeft;
  Right:=TPanel.Create(Self);Right.Parent:=Self;Right.Align:=alClient;
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Right;
  FGrid.Align:=alTop;FGrid.Height:=260;FGrid.ColCount:=6;
  FGrid.FixedCols:=0;FGrid.RowCount:=2;FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=57;FGrid.ColWidths[1]:=110;FGrid.ColWidths[2]:=270;
  FGrid.ColWidths[3]:=120;FGrid.ColWidths[4]:=145;FGrid.ColWidths[5]:=145;
  for I:=0 to 5 do FGrid.Cells[I,0]:=Headers[I];
  FBytes:=TStringGrid.Create(Self);FBytes.Parent:=Right;
  FBytes.Align:=alClient;FBytes.ColCount:=3;
  FBytes.FixedCols:=0;FBytes.RowCount:=2;FBytes.FixedRows:=1;
  FBytes.ColWidths[0]:=130;FBytes.ColWidths[1]:=100;FBytes.ColWidths[2]:=450;
  FBytes.Cells[0,0]:='ELF offset';FBytes.Cells[1,0]:='Hex';
  FBytes.Cells[2,0]:='Машинний код, НЕ закон SENS';
  FStatus.Caption:='Відкрийте фізичну програму .sens';
  ClearView;
end;
procedure TCompilerWindow.ClearView;
var I:Integer;
begin
  FImage:='';SetLength(FNodes.Nodes,0);SetLength(FNodes.Roots,0);
  FTree.Items.Clear;FGrid.RowCount:=2;FBytes.RowCount:=2;
  for I:=0 to 5 do FGrid.Cells[I,1]:='';
  for I:=0 to 2 do FBytes.Cells[I,1]:='';
  FSave.Enabled:=False;
  FSelected.Caption:='Точна тотожність: домен + ширина + біти + закон';
  FPreview.Invalidate;
end;
procedure TCompilerWindow.Fail(const Why:String);
begin ClearView;FStatus.Caption:='ВІДМОВА: '+Why end;
procedure TCompilerWindow.Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('LCL WideIR: '+Why) end;
procedure TCompilerWindow.OpenClick(Sender:TObject);
begin if FOpenDialog.Execute then LoadPhysical(FOpenDialog.FileName) end;
procedure TCompilerWindow.SaveClick(Sender:TObject);
begin if FSaveDialog.Execute then SaveVerified(FSaveDialog.FileName) end;
function TCompilerWindow.LoadPhysical(const Path:String):Boolean;
var Stream:TFileStream;Physical,Image:RawByteString;G:TELFGeometry;
    Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    I,Parent,Count:SizeInt;N:TWideIRNode;Nodes:array of TTreeNode;
    KindText,DomainText:String;
begin
  Result:=False;ClearView;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('лише двійковий .sens; .lisp є проєкцією');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>65536) then
        raise Exception.Create('порожнє чи завелике фізичне джерело');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    Image:=BuildVerifiedWideELF(Physical,'external/sens');
    VerifySENSELF64(Image,G);
    if (G.Kind<>3) or (G.Entry<>120) or (G.FileBytes<>Length(Image)) then
      raise Exception.Create('хибна геометрія ELF64 PIE');
    LoadPinnedDomains('external/sens',Tables);
    BuildWideIR(Physical,Tables,IR);
    VerifyWideIRStructure(IR,Stats);
    if (Stats.Roots<>1) or (Length(IR.Roots)<>1) or
       (Length(IR.Nodes)<3) then
      raise Exception.Create('пошкоджене фізичне дерево IR');
    SetLength(Nodes,Length(IR.Nodes));
    FTree.Items.BeginUpdate;
    try
      FGrid.RowCount:=Length(IR.Nodes)+1;
      for I:=0 to High(IR.Nodes) do begin
        N:=IR.Nodes[I];Parent:=N.ParentIndex;
        if Parent>=I then raise Exception.Create('циклічний IR parent');
        if Parent>=0 then
          Nodes[I]:=FTree.Items.AddChild(Nodes[Parent],
            IntToStr(I)+' · W'+IntToStr(N.Width))
        else Nodes[I]:=FTree.Items.AddChild(nil,'D2 · фізичний корінь');
        Nodes[I].Data:=Pointer(PtrInt(I+1));
        KindText:='D2 список';DomainText:='—';
        if N.Kind=wkPair then KindText:='D2 пара';
        if N.Kind in [wkAtom,wkEmpty] then begin
          KindText:='двійковий атом';
          if N.HasPinnedKey then DomainText:='D'+IntToStr(N.Width)+' pinned'
          else DomainText:='W'+IntToStr(N.Width)+' opaque';
        end;
        FGrid.Cells[0,I+1]:=IntToStr(I);
        FGrid.Cells[1,I+1]:=KindText;
        FGrid.Cells[2,I+1]:=String(N.Bits);
        FGrid.Cells[3,I+1]:=DomainText;
        if N.OwnWord then begin
          FGrid.Cells[4,I+1]:='['+IntToStr(N.Physical.TritStart)+
            ','+IntToStr(N.Physical.TritEnd)+')';
          FGrid.Cells[5,I+1]:='['+IntToStr(N.Physical.ByteStart)+
            ','+IntToStr(N.Physical.ByteEnd)+')';
        end else begin
          FGrid.Cells[4,I+1]:='похідний';FGrid.Cells[5,I+1]:='—';
        end;
      end;
    finally FTree.Items.EndUpdate end;
    FNodes:=IR;FImage:=Image;
    Count:=Length(Image)-120;if Count>32 then Count:=32;
    FBytes.RowCount:=Count+1;
    for I:=0 to Count-1 do begin
      FBytes.Cells[0,I+1]:=IntToStr(I+120);
      FBytes.Cells[1,I+1]:=IntToHex(Byte(Image[I+121]),2);
      FBytes.Cells[2,I+1]:='x86-64 · байт машинного коду';
    end;
    FTree.FullExpand;FSave.Enabled:=True;
    FStatus.Caption:='СКОМПІЛЬОВАНО: pinned WideIR → ELF64 PIE · '+
      IntToStr(G.FileBytes)+' байтів · лише підтримані профілі';
    FPreview.Invalidate;Result:=True;
  except on E:Exception do Fail(E.Message) end;
end;
procedure TCompilerWindow.TreeChange(Sender:TObject;Node:TTreeNode);
var I:SizeInt;
begin
  if Node=nil then Exit;
  I:=PtrInt(Node.Data)-1;
  if (I<0) or (I>=Length(FNodes.Nodes)) then Exit;
  FGrid.Row:=I+1;
  FSelected.Caption:='Вузол '+IntToStr(I)+
    ' · слово '+IntToStr(FNodes.Nodes[I].WordIndex)+
    ' · W'+IntToStr(FNodes.Nodes[I].Width)+
    ' · біти '+String(FNodes.Nodes[I].Bits);
end;
procedure TCompilerWindow.PaintBytes(C:TCanvas);
var I,Count,X:Integer;
begin
  C.Brush.Color:=clWhite;
  C.FillRect(0,0,FPreview.Width,FPreview.Height);
  Count:=Length(FImage)-120;if Count>32 then Count:=32;
  if Count<=0 then Exit;
  for I:=0 to Count-1 do begin
    X:=8+I*24;
    if (Byte(FImage[I+121]) and 1)<>0 then C.Brush.Color:=clNavy
    else C.Brush.Color:=clSilver;
    C.Pen.Color:=clGray;C.Rectangle(X,8,X+18,29);
    C.Font.Color:=clBlack;
    C.TextOut(X,34,IntToHex(Byte(FImage[I+121]),2));
  end;
  C.Brush.Color:=clWhite;
  C.TextOut(8,73,'Машинні байти ELF64, а не коди функцій SENS');
end;
procedure TCompilerWindow.PreviewPaint(Sender:TObject);
begin PaintBytes(FPreview.Canvas) end;
function TCompilerWindow.SaveVerified(const Path:String):Boolean;
var G:TELFGeometry;
begin
  Result:=False;
  try
    if (not FSave.Enabled) or (Length(FImage)<=120) then
      raise Exception.Create('немає перевіреного ELF');
    if LowerCase(ExtractFileExt(Path))<>'.elf' then
      raise Exception.Create('потрібен файл .elf');
    PublishNewELF64(Path,FImage,3,G);
    if G.FileBytes<>Length(FImage) then
      raise Exception.Create('неповний запис ELF');
    Result:=True;
  except on E:Exception do FStatus.Caption:='ELF не збережено: '+E.Message end;
end;
procedure TCompilerWindow.SelfTest(
  const SubFile,NsdFile,BadFile,TextFile,Unsupported,Prefix:String);
var B:TBitmap;Expected:TColor;Previous:RawByteString;
begin
  Need(LoadPhysical(SubFile),'не скомпільовано D5 SUB');
  Need((FTree.Items.Count=4) and (FGrid.RowCount=5) and
    (FNodes.Nodes[1].Width=5) and (FNodes.Nodes[1].Bits='01011') and
    FNodes.Nodes[1].HasPinnedKey and (FNodes.Nodes[2].Width=12) and
    (not FNodes.Nodes[2].HasPinnedKey),'D5/W12 pinned/opaque/tree');
  Need(FSave.Enabled and (FBytes.RowCount>12) and
    (Pos('СКОМПІЛЬОВАНО',FStatus.Caption)=1),'реальний ELF/LCL');
  Previous:=FImage;
  B:=TBitmap.Create;
  try
    B.SetSize(800,95);PaintBytes(B.Canvas);
    if (Byte(FImage[121]) and 1)<>0 then Expected:=clNavy
    else Expected:=clSilver;
    Need(B.Canvas.Pixels[10,12]=Expected,'Canvas не показав машинні байти');
  finally B.Free end;
  Need(SaveVerified(Prefix+'-sub.elf'),'не збережено SUB');
  Need(not SaveVerified(Prefix+'-sub.elf'),'перезаписано SUB');
  Need(LoadPhysical(NsdFile),'не скомпільовано D6 NSD');
  Need((FTree.Items.Count=4) and (FNodes.Nodes[1].Width=6) and
    (FNodes.Nodes[1].Bits='010101') and FNodes.Nodes[1].HasPinnedKey,
    'D6 координата не відновилась');
  Need(FImage<>Previous,'два машинні образи однакові');
  Need(SaveVerified(Prefix+'-nsd.elf'),'не збережено NSD');
  Need(not LoadPhysical(BadFile),'пошкоджений T5M прийнято');
  Need((FImage='') and (FTree.Items.Count=0) and
    (not FSave.Enabled) and (FGrid.Cells[2,1]='') and
    (FBytes.Cells[1,1]=''),'старий ELF залишився після помилки');
  Need(not LoadPhysical(TextFile),'текстова .lisp стала каноном');
  Need(not LoadPhysical(Unsupported),'недопущений профіль прийнято');
  Need(not SaveVerified(Prefix+'-after-error.elf'),
    'після помилки створено ELF');
  Need(LoadPhysical(SubFile),'після негативів не відновилося');
  WriteLn('ЛАЗАРУС-СПІЛЬНИЙ-ГОТОВО GTK2=так WideIR=4 ',
    'профілі=2 ELF=2 відмов=3 Canvas=байти no-clobber=так recovery=так');
end;
begin
  Application.Initialize;Application.CreateForm(TCompilerWindow,Window);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>7 then Halt(64);
    try
      Window.Show;Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;Halt(0);
    except on E:Exception do begin
      WriteLn(StdErr,'ЛАЗАРУС-СПІЛЬНИЙ-ПОМИЛКА: ',E.Message);Halt(1);
    end end;
  end;
  if ParamCount=1 then Window.LoadPhysical(ParamStr(1));
  Application.Run;
end.
