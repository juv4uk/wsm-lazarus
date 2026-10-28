{ Lazarus/LCL: дерево широкого фізичного IR (1..192 біти).
  Вікно проєктує вже перевірене механічне подання,
  НЕ призначає семантику D12+ за довжиною слова. }
program wide_exactir;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,ExtCtrls,
  ComCtrls,Grids,Dialogs,Graphics,
  wsm.t5m,wsm.wideir,wsm.domain,wsm.bind;
const MaxVisible=8192;
type
  TWideWindow=class(TForm)
  private
    Tree:TTreeView;
    Grid:TStringGrid;
    Picture:TPaintBox;
    Status,Detail:TLabel;
    Dialog:TOpenDialog;
    OpenButton:TButton;
    Current:TWideIR;
    RowNodes:array of TTreeNode;
    Selected:SizeInt;
    procedure OpenClick(Sender:TObject);
    procedure TreeClick(Sender:TObject;Node:TTreeNode);
    procedure DrawBits(TargetCanvas:TCanvas;W,H:Integer);
    procedure PicturePaint(Sender:TObject);
    procedure ClearData;
    procedure Reject(const Why:String);
    function LoadPhysical(const FileName:String):Boolean;
    procedure Must(Yes:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent);override;
    procedure SelfTest(const RootFile,WideFile,BadFile:String);
  end;
var Window:TWideWindow;

function LabelKind(Kind:TWideIRKind):String;
begin
  case Kind of
    wkList: Result:='список D2';
    wkPair: Result:='похідна пара';
    wkAtom: Result:='двійкове слово';
    wkEmpty:Result:='порожня структура D3';
  else Result:='невідомий вузол';
  end;
end;
function Interval(A,B:SizeInt):String;
begin Result:='['+IntToStr(A)+','+IntToStr(B)+')'; end;

constructor TWideWindow.Create(AOwner:TComponent);
var TopBar,LeftPanel,BottomPanel:TPanel; Split:TSplitter; I:Integer;
const Titles:array[0..7] of String=('№','Вид','Корінь','Батько','Ширина',
  'Точні біти','Трити','Байти');
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — широке фізичне дерево IR у Lazarus';
  Width:=1320;Height:=730;Position:=poScreenCenter;
  TopBar:=TPanel.Create(Self);TopBar.Parent:=Self;
  TopBar.Align:=alTop;TopBar.Height:=48;TopBar.BevelOuter:=bvNone;
  OpenButton:=TButton.Create(Self);OpenButton.Parent:=TopBar;
  OpenButton.SetBounds(12,7,235,34);
  OpenButton.Caption:='Відкрити двійковий .sens…';
  OpenButton.OnClick:=@OpenClick;
  Dialog:=TOpenDialog.Create(Self);
  Dialog.Title:='Оберіть фізичний файл SENS';
  Dialog.Filter:='Фізичні слова SENS (*.sens)|*.sens';
  BottomPanel:=TPanel.Create(Self);BottomPanel.Parent:=Self;
  BottomPanel.Align:=alBottom;BottomPanel.Height:=173;
  Status:=TLabel.Create(Self);Status.Parent:=BottomPanel;
  Status.SetBounds(10,4,1280,27);
  Detail:=TLabel.Create(Self);Detail.Parent:=BottomPanel;
  Detail.SetBounds(10,30,1280,25);
  Picture:=TPaintBox.Create(Self);Picture.Parent:=BottomPanel;
  Picture.SetBounds(10,61,1250,105);Picture.OnPaint:=@PicturePaint;
  LeftPanel:=TPanel.Create(Self);LeftPanel.Parent:=Self;
  LeftPanel.Align:=alLeft;LeftPanel.Width:=375;
  Tree:=TTreeView.Create(Self);Tree.Parent:=LeftPanel;Tree.Align:=alClient;
  Tree.ReadOnly:=True;Tree.OnChange:=@TreeClick;
  Split:=TSplitter.Create(Self);Split.Parent:=Self;
  Split.Align:=alLeft;Split.Width:=6;
  Grid:=TStringGrid.Create(Self);Grid.Parent:=Self;Grid.Align:=alClient;
  Grid.ColCount:=8;Grid.FixedCols:=0;Grid.RowCount:=2;Grid.FixedRows:=1;
  Grid.Options:=Grid.Options+[goColSizing,goRowSelect];
  for I:=0 to 7 do Grid.Cells[I,0]:=Titles[I];
  Grid.ColWidths[0]:=65;Grid.ColWidths[1]:=160;
  Grid.ColWidths[2]:=68;Grid.ColWidths[3]:=70;
  Grid.ColWidths[4]:=140;Grid.ColWidths[5]:=235;
  Grid.ColWidths[6]:=106;Grid.ColWidths[7]:=110;
  ClearData;
end;

procedure TWideWindow.ClearData;
var I:Integer;
begin
  Selected:=-1;Tree.Items.Clear;
  SetLength(RowNodes,0);SetLength(Current.Nodes,0);
  SetLength(Current.Roots,0);Current.PhysicalLeaves:=0;
  Current.OpaqueLeaves:=0;Grid.RowCount:=2;
  for I:=0 to Grid.ColCount-1 do Grid.Cells[I,1]:='';
  Detail.Caption:='Оберіть вузол: ширина не дорівнює числовому допуску.';
  Picture.Invalidate;
end;

procedure TWideWindow.Reject(const Why:String);
begin
  ClearData;
  Status.Caption:='Помилка фізичного IR: '+Why;
end;

procedure TWideWindow.OpenClick(Sender:TObject);
begin
  if Dialog.Execute then LoadPhysical(Dialog.FileName);
end;

function TWideWindow.LoadPhysical(const FileName:String):Boolean;
var F:TFileStream;Raw:RawByteString;T:TDomainSet;
  Candidate:TWideIR;I:SizeInt;N:TWideIRNode;
  ParentNode:TTreeNode;TitleText,WidthText,BitsText:String;
begin
  Result:=False;ClearData;
  try
    if LowerCase(ExtractFileExt(FileName))<>'.sens' then
      raise Exception.Create('потрібен фізичний .sens');
    F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<=0) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або завеликий двійковий файл');
      SetLength(Raw,SizeInt(F.Size));
      F.ReadBuffer(Raw[1],Length(Raw));
    finally F.Free; end;
    LoadPinnedDomains('external/sens',T);
    BuildWideIR(Raw,T,Candidate);
    if (Length(Candidate.Nodes)=0) or
       (Length(Candidate.Nodes)>MaxVisible) then
      raise Exception.Create('недопустима кількість вузлів вікна');
    Current:=Candidate;
    SetLength(RowNodes,Length(Current.Nodes));
    Grid.RowCount:=Length(Current.Nodes)+1;
    Tree.Items.BeginUpdate;
    try
      for I:=0 to High(Current.Nodes) do begin
        N:=Current.Nodes[I];
        ParentNode:=nil;
        if N.ParentIndex>=0 then begin
          if N.ParentIndex>=I then
            raise Exception.Create('неправильний preorder батька');
          ParentNode:=RowNodes[N.ParentIndex];
        end;
        WidthText:='—';BitsText:='—';
        if N.Kind in [wkAtom,wkEmpty] then begin
          if N.HasPinnedKey then WidthText:='D'+IntToStr(N.Width)+' · pinned'
          else WidthText:='W'+IntToStr(N.Width)+' · opaque';
          BitsText:=String(N.Bits);
        end;
        TitleText:=IntToStr(I)+' · '+LabelKind(N.Kind);
        if N.Kind in [wkAtom,wkEmpty] then TitleText:=TitleText+
          ' · '+WidthText;
        RowNodes[I]:=Tree.Items.AddChild(ParentNode,TitleText);
        RowNodes[I].Data:=Pointer(PtrInt(I+1));
        Grid.Cells[0,I+1]:=IntToStr(I);
        Grid.Cells[1,I+1]:=LabelKind(N.Kind);
        Grid.Cells[2,I+1]:=IntToStr(N.RootIndex);
        Grid.Cells[3,I+1]:=IntToStr(N.ParentIndex);
        Grid.Cells[4,I+1]:=WidthText;
        Grid.Cells[5,I+1]:=BitsText;
        if N.OwnWord then begin
          Grid.Cells[6,I+1]:=Interval(N.Physical.TritStart,
            N.Physical.TritEnd);
          Grid.Cells[7,I+1]:=Interval(N.Physical.ByteStart,
            N.Physical.ByteEnd);
        end else begin
          Grid.Cells[6,I+1]:='похідний';
          Grid.Cells[7,I+1]:='—';
        end;
      end;
    finally Tree.Items.EndUpdate; end;
    Tree.FullExpand;
    Status.Caption:='Точний фізичний IR: '+IntToStr(Length(Current.Nodes))+
      ' вузлів, '+IntToStr(Current.OpaqueLeaves)+
      ' непрозорих широких слів. D12+ семантика НЕ виводиться із ширини.';
    Tree.Selected:=RowNodes[0];
    TreeClick(Tree,RowNodes[0]);
    Result:=True;
  except on E:Exception do Reject(E.Message); end;
end;

procedure TWideWindow.TreeClick(Sender:TObject;Node:TTreeNode);
var I:SizeInt; N:TWideIRNode;
begin
  if Node=nil then Exit;
  I:=PtrInt(Node.Data)-1;
  if (I<0) or (I>=Length(Current.Nodes)) then Exit;
  Selected:=I;N:=Current.Nodes[I];
  Grid.Row:=I+1;
  Detail.Caption:='Вузол '+IntToStr(I)+', слово '+IntToStr(N.WordIndex)+
    ', глибина '+IntToStr(N.Depth);
  if (N.Kind in [wkAtom,wkEmpty]) and not N.HasPinnedKey then
    Detail.Caption:=Detail.Caption+' · W'+IntToStr(N.Width)+
      ': тільки фізичні біти, НЕ перевірений числовий закон';
  if not N.OwnWord then
    Detail.Caption:=Detail.Caption+' · пара не має власного T5M слова';
  Picture.Invalidate;
end;

procedure TWideWindow.DrawBits(TargetCanvas:TCanvas;W,H:Integer);
var I,Count,X,Step:Integer;Bits:RawByteString;
begin
  TargetCanvas.Brush.Color:=clWhite;TargetCanvas.FillRect(0,0,W,H);
  if (Selected<0) or (Selected>=Length(Current.Nodes)) then Exit;
  Bits:=Current.Nodes[Selected].Bits;
  Count:=Length(Bits);
  if Count>64 then Count:=64;
  if Count<=0 then Exit;
  Step:=18;
  for I:=0 to Count-1 do begin
    X:=12+I*Step;
    if Bits[I+1]='1' then TargetCanvas.Brush.Color:=clNavy
    else TargetCanvas.Brush.Color:=clSilver;
    TargetCanvas.Pen.Color:=clGray;
    TargetCanvas.Rectangle(X,10,X+15,54);
  end;
  TargetCanvas.Font.Color:=clBlack;
  TargetCanvas.Brush.Color:=clWhite;
  TargetCanvas.TextOut(12,64,'Перші '+IntToStr(Count)+' з '+
    IntToStr(Length(Bits))+' фізичних бітів (не десяткове число)');
end;

procedure TWideWindow.PicturePaint(Sender:TObject);
begin DrawBits(Picture.Canvas,Picture.Width,Picture.Height); end;

procedure TWideWindow.Must(Yes:Boolean;const Why:String);
begin if not Yes then raise Exception.Create('LCL-перевірка: '+Why); end;

procedure TWideWindow.SelfTest(const RootFile,WideFile,BadFile:String);
var I,Count24,Opaque:SizeInt;Bmp:TBitmap;
begin
  Must(LoadPhysical(RootFile),'pinned числовий свідок не прочитано');
  Count24:=0;
  for I:=0 to High(Current.Nodes) do
    if (Current.Nodes[I].Width=24) then begin
      Inc(Count24);
      Must((not Current.Nodes[I].HasPinnedKey) and
        (Pos('W24',Grid.Cells[4,I+1])=1),
        'W24 неправдиво названо допущеним D24');
    end;
  Must(Count24=2,'у справжньому pinned SENS має бути два W24');
  Must(LoadPhysical(WideFile),'фізичний список W12–W192');
  Must((Length(Current.Nodes)=7) and (Current.OpaqueLeaves=6),
    'сім широт, шість непрозорих листків');
  Must((Tree.Items.Count=7) and (Tree.Items[1].Parent=Tree.Items[0]) and
    (Tree.Items[6].Parent=Tree.Items[0]),'справжня GTK2 ієрархія');
  Must((Current.Nodes[1].Width=12) and
    (Current.Nodes[5].Width=192) and
    (Current.Nodes[6].Width=13),'W12/W192/W13 не загублені');
  Tree.Selected:=RowNodes[1];
  Application.ProcessMessages;
  Must((Grid.Row=2) and
    (Pos('НЕ перевірений числовий закон',Detail.Caption)>0),
    'вибір TTreeView не синхронізує рядок');
  Bmp:=TBitmap.Create;
  try
    Bmp.SetSize(1220,100);
    DrawBits(Bmp.Canvas,1220,100);
    Must(Bmp.Canvas.Pixels[15,20]=clSilver,
      'Canvas не намалював точний нульовий біт');
    Must(Bmp.Canvas.Pixels[15+11*18,20]=clNavy,
      'Canvas не намалював точний одиничний біт');
  finally Bmp.Free; end;
  Must(not LoadPhysical(BadFile),'зіпсований T5M прийнято');
  Must((Tree.Items.Count=0) and (Grid.Cells[0,1]='') and
    (Pos('Помилка',Status.Caption)=1),'після відмови лишились клітинки');
  Must(not LoadPhysical('не-існує.sens'),'неіснуючий файл прийнято');
  Must((Tree.Items.Count=0) and (Selected=-1),'частковий GUI після відмови');
  WriteLn('LAZARUS-ШИРОКЕ-IR-ГАРАЗД: GTK2=справжній pinned-W24=2 ',
    'W12-W192=точні дерева=так Canvas=біти fail-closed=так');
end;

begin
  Application.Initialize;
  Application.CreateForm(TWideWindow,Window);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>4 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4));
      Window.Free;
      Halt(0);
    except on E:Exception do begin
      WriteLn(StdErr,'LAZARUS-ШИРОКЕ-IR-ПОМИЛКА: ',E.Message);
      Halt(1);
    end;end;
  end;
  if ParamCount=1 then Window.LoadPhysical(ParamStr(1));
  Application.Run;
end.
