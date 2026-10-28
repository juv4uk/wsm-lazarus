{ Візуальна історія ФІЗИЧНОГО GC. Значення з wsm.gc, не мова SENS.
  Графік не виконує форм, не конструює мовних законів та не є REPL. }
unit wsm.gctimeline;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses
  Classes, SysUtils, Forms, Controls, Grids, Graphics, ExtCtrls,
  StdCtrls, Dialogs, wsm.gc;

const MaxGCSamples = 4096;

type
  EGCTimelineError = class(Exception);
  TGCMeasure = record
    Phase: QWord;
    Slots, Live, FreeSlots, Roots, ScopedRoots, ScopeDepth, Reclaimed: SizeInt;
  end;
  TGCMeasures = array of TGCMeasure;

  TGCViewerForm = class(TForm)
  private
    FGrid: TStringGrid;
    FChart: TPaintBox;
    FStatus: TLabel;
    FValues: TGCMeasures;
    FPaintCount: SizeInt;
    procedure ChartPaint(Sender:TObject);
    procedure SaveClicked(Sender:TObject);
  public
    constructor Create(AOwner:TComponent); override;
    procedure LoadHistory(const Data:TGCMeasures);
    function Evidence:RawByteString;
    function Cell(ACol,ARow:Integer):String;
    function SampleCount:SizeInt;
    function PaintCount:SizeInt;
  end;

function CaptureGC(Heap:TGCHeap; Phase:QWord; Freed:SizeInt):TGCMeasure;

implementation

function CaptureGC(Heap:TGCHeap; Phase:QWord; Freed:SizeInt):TGCMeasure;
begin
  if Heap=nil then raise EGCTimelineError.Create('відсутній фізичний GC');
  Result.Phase:=Phase;
  Result.Slots:=Heap.SlotCount;
  Result.Live:=Heap.LiveCount;
  Result.FreeSlots:=Heap.FreeCount;
  Result.Roots:=Heap.RootCount;
  Result.ScopedRoots:=Heap.ScopedRootCount;
  Result.ScopeDepth:=Heap.ScopeDepth;
  Result.Reclaimed:=Freed;
end;

constructor TGCViewerForm.Create(AOwner:TComponent);
var TopBar:TPanel; Btn:TButton; I:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — візуальна історія фізичної пам’яті GC';
  Width:=1040;
  Height:=650;
  Position:=poScreenCenter;
  TopBar:=TPanel.Create(Self);
  TopBar.Parent:=Self;
  TopBar.Align:=alTop;
  TopBar.Height:=77;
  Btn:=TButton.Create(Self);
  Btn.Parent:=TopBar;
  Btn.SetBounds(12,12,250,31);
  Btn.Caption:='Експортувати точні лічильники';
  Btn.OnClick:=@SaveClicked;
  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=TopBar;
  FStatus.SetBounds(12,50,980,24);
  FStatus.Caption:='Фізичний GC, без виконання законів SENS';
  FChart:=TPaintBox.Create(Self);
  FChart.Parent:=Self;
  FChart.Align:=alBottom;
  FChart.Height:=230;
  FChart.OnPaint:=@ChartPaint;
  FGrid:=TStringGrid.Create(Self);
  FGrid.Parent:=Self;
  FGrid.Align:=alClient;
  FGrid.ColCount:=8;
  FGrid.FixedCols:=0;
  FGrid.FixedRows:=1;
  FGrid.RowCount:=2;
  FGrid.Options:=FGrid.Options-[goEditing]+[goRowSelect];
  FGrid.Cells[0,0]:='Фаза';
  FGrid.Cells[1,0]:='Слотів';
  FGrid.Cells[2,0]:='Живих';
  FGrid.Cells[3,0]:='Вільних';
  FGrid.Cells[4,0]:='Коренів';
  FGrid.Cells[5,0]:='Тимчасових коренів';
  FGrid.Cells[6,0]:='Глибина областей';
  FGrid.Cells[7,0]:='Звільнено';
  for I:=0 to 7 do FGrid.ColWidths[I]:=112;
  FGrid.ColWidths[5]:=162;
  FGrid.ColWidths[6]:=162;
  FPaintCount:=0;
end;

procedure TGCViewerForm.LoadHistory(const Data:TGCMeasures);
var I:SizeInt; M:TGCMeasure; Prior:QWord;
begin
  if (Length(Data)<1) or (Length(Data)>MaxGCSamples) then
    raise EGCTimelineError.Create('число знімків має бути 1..4096');
  Prior:=0;
  { ПЕРЕД зміною GUI валідуємо кожний фізичний snapshot. }
  for I:=0 to High(Data) do begin
    M:=Data[I];
    if (M.Phase=0) or (M.Phase<=Prior) then
      raise EGCTimelineError.Create('неприпустимий порядок фаз GC');
    Prior:=M.Phase;
    if (M.Slots<0) or (M.Live<0) or (M.FreeSlots<0) or
       (M.Roots<0) or (M.ScopedRoots<0) or
       (M.ScopeDepth<0) or (M.Reclaimed<0) then
      raise EGCTimelineError.Create('від’ємний фізичний лічильник');
    if (M.Live>M.Slots) or (M.FreeSlots<>M.Slots-M.Live) then
      raise EGCTimelineError.Create('живі + вільні не збігаються зі слотами');
    if M.Reclaimed>M.Slots then
      raise EGCTimelineError.Create('звільнено більше ніж фізичних слотів');
  end;
  FValues:=Copy(Data,0,Length(Data));
  FGrid.BeginUpdate;
  try
    FGrid.RowCount:=Length(FValues)+1;
    for I:=0 to High(FValues) do begin
      M:=FValues[I];
      FGrid.Cells[0,I+1]:=UIntToStr(M.Phase);
      FGrid.Cells[1,I+1]:=IntToStr(M.Slots);
      FGrid.Cells[2,I+1]:=IntToStr(M.Live);
      FGrid.Cells[3,I+1]:=IntToStr(M.FreeSlots);
      FGrid.Cells[4,I+1]:=IntToStr(M.Roots);
      FGrid.Cells[5,I+1]:=IntToStr(M.ScopedRoots);
      FGrid.Cells[6,I+1]:=IntToStr(M.ScopeDepth);
      FGrid.Cells[7,I+1]:=IntToStr(M.Reclaimed);
    end;
  finally FGrid.EndUpdate; end;
  FStatus.Caption:='Знімків: '+IntToStr(Length(FValues))+
    ' | механічний GC | виконання SENS не перевіряється';
  FChart.Invalidate;
end;

procedure TGCViewerForm.ChartPaint(Sender:TObject);
var I,W,H,X,Y,BarWidth,MaxSlots:Integer; LiveH,FreeH:Integer;
begin
  Inc(FPaintCount);
  W:=FChart.Width; H:=FChart.Height;
  FChart.Canvas.Brush.Color:=clWhite;
  FChart.Canvas.FillRect(Rect(0,0,W,H));
  FChart.Canvas.Font.Color:=clBlack;
  FChart.Canvas.TextOut(9,5,'GC: зайняті (зелений) / вільні (сірий) фізичні слоти');
  if Length(FValues)=0 then Exit;
  MaxSlots:=1;
  for I:=0 to High(FValues) do
    if FValues[I].Slots>MaxSlots then MaxSlots:=FValues[I].Slots;
  if W<60 then Exit;
  if H<60 then Exit;
  BarWidth:=(W-30) div Length(FValues);
  if BarWidth<1 then BarWidth:=1;
  for I:=0 to High(FValues) do begin
    X:=15+I*BarWidth;
    { Висота обох смуг пропорційна реальним лічильникам. }
    LiveH:=Int64(FValues[I].Live)*(H-47) div MaxSlots;
    FreeH:=Int64(FValues[I].FreeSlots)*(H-47) div MaxSlots;
    Y:=H-20;
    FChart.Canvas.Brush.Color:=clGreen;
    FChart.Canvas.FillRect(Rect(X,Y-LiveH,X+BarWidth-2,Y));
    Dec(Y,LiveH);
    FChart.Canvas.Brush.Color:=clSilver;
    FChart.Canvas.FillRect(Rect(X,Y-FreeH,X+BarWidth-2,Y));
  end;
end;

function TGCViewerForm.Evidence:RawByteString;
var I:SizeInt; M:TGCMeasure;
begin
  Result:='Фаза'#9'Слотів'#9'Живих'#9'Вільних'#9 +
    'Коренів'#9'Тимчасових коренів'#9'Глибина областей'#9 +
    'Звільнено'#10;
  for I:=0 to High(FValues) do begin
    M:=FValues[I];
    Result:=Result+UIntToStr(M.Phase)+#9+IntToStr(M.Slots)+#9+
      IntToStr(M.Live)+#9+IntToStr(M.FreeSlots)+#9+
      IntToStr(M.Roots)+#9+IntToStr(M.ScopedRoots)+#9+
      IntToStr(M.ScopeDepth)+#9+IntToStr(M.Reclaimed)+#10;
  end;
end;

function TGCViewerForm.Cell(ACol,ARow:Integer):String;
begin
  if (ACol<0) or (ACol>=8) or (ARow<1) or
     (ARow>Length(FValues)) then
    raise EGCTimelineError.Create('поза таблицею фізичних знімків');
  Result:=FGrid.Cells[ACol,ARow];
end;

function TGCViewerForm.SampleCount:SizeInt;
begin Result:=Length(FValues); end;
function TGCViewerForm.PaintCount:SizeInt;
begin Result:=FPaintCount; end;

procedure TGCViewerForm.SaveClicked(Sender:TObject);
var D:TSaveDialog; Stream:TFileStream; Data:RawByteString;
begin
  if Length(FValues)=0 then begin
    MessageDlg('Немає перевірених фізичних знімків',mtInformation,[mbOK],0);
    Exit;
  end;
  D:=TSaveDialog.Create(Self);
  try
    D.Title:='Експорт фізичної історії GC';
    D.Filter:='Таблиця UTF-8 TSV|*.tsv';
    D.DefaultExt:='tsv';
    if D.Execute then begin
      Data:=Evidence;
      Stream:=TFileStream.Create(D.Filename,fmCreate);
      try
        if Length(Data)>0 then Stream.WriteBuffer(Data[1],Length(Data));
      finally Stream.Free; end;
    end;
  finally D.Free; end;
end;

end.
