{ G1.9: справжній Lazarus/LCL перегляд фізичних широких бітових слів.
  SENS визначає значення, а wsm.widespan — лише трити/байти/ширину.
  Порогова довжина >=12 НЕ ратифікує кожну ширину як числовий домен.
  Звичайний український .lisp є людською проєкцією, не T5M input. }
program sens_wide_inspector;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Graphics, Dialogs, Types, wsm.t5m, wsm.widespan;
const
  MaxViewBytes = 512*1024;
  VisibleBars = 8;
  RowHeight = 32;
  BarLeft = 225;
  BarTop = 24;
type
  TWideWindow = class(TForm)
  private
    FGrid: TStringGrid;
    FChart: TPaintBox;
    FStatus, FSelection: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FWords: TWideWords;
    FSelected: SizeInt;
    procedure ClearView;
    procedure OpenClicked(Sender: TObject);
    procedure DrawBars(C: TCanvas; AWidth,AHeight: Integer);
    procedure PaintBars(Sender: TObject);
    procedure ClickBars(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X,Y: Integer);
    procedure SelectBar(Index: SizeInt);
    procedure Require(Ok: Boolean; const Why: String);
  public
    constructor Create(AOwner:TComponent); override;
    function LoadPhysical(const FileName: String):Boolean;
    procedure SelfCheck(const SmallFile, UpstreamFile, BadFile,
      EmptyFile, HumanFile: String);
  end;
var Win: TWideWindow;

constructor TWideWindow.Create(AOwner:TComponent);
var Toolbar,Footer:TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичні широкі слова D12+';
  Width:=1120; Height:=780; Position:=poScreenCenter;
  Toolbar:=TPanel.Create(Self); Toolbar.Parent:=Self;
  Toolbar.Align:=alTop; Toolbar.Height:=55; Toolbar.BevelOuter:=bvNone;
  FOpen:=TButton.Create(Self); FOpen.Parent:=Toolbar;
  FOpen.SetBounds(12,9,300,36);
  FOpen.Caption:='Відкрити фізичний двійковий .sens';
  FOpen.OnClick:=@OpenClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Оберіть фізичний потік SENS';
  FDialog.Filter:='Двійковий SENS (*.sens)|*.sens';
  Footer:=TPanel.Create(Self); Footer.Parent:=Self;
  Footer.Align:=alBottom; Footer.Height:=65;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Footer;
  FStatus.SetBounds(10,7,1080,25);
  FSelection:=TLabel.Create(Self); FSelection.Parent:=Footer;
  FSelection.SetBounds(10,36,1080,24);
  FChart:=TPaintBox.Create(Self); FChart.Parent:=Self;
  FChart.Align:=alTop; FChart.Height:=310;
  FChart.OnPaint:=@PaintBars; FChart.OnMouseDown:=@ClickBars;
  FGrid:=TStringGrid.Create(Self); FGrid.Parent:=Self;
  FGrid.Align:=alClient; FGrid.FixedRows:=1; FGrid.ColCount:=5;
  FGrid.RowCount:=2;
  FGrid.ColWidths[0]:=100; FGrid.ColWidths[1]:=125;
  FGrid.ColWidths[2]:=340; FGrid.ColWidths[3]:=195;
  FGrid.ColWidths[4]:=195;
  FGrid.Cells[0,0]:='Слово №';
  FGrid.Cells[1,0]:='Довжина, біт';
  FGrid.Cells[2,0]:='Точні біти (із нулями)';
  FGrid.Cells[3,0]:='Трити [від,до)';
  FGrid.Cells[4,0]:='Байти [від,до)';
  ClearView;
end;

procedure TWideWindow.ClearView;
var I:Integer;
begin
  SetLength(FWords,0);
  FSelected:=-1;
  FGrid.RowCount:=2;
  for I:=0 to 4 do FGrid.Cells[I,1]:='';
  FStatus.Caption:='Показуються фізичні слова від 12 біт; числова семантика не визначається довжиною.';
  FSelection.Caption:='Українська .lisp — проєкція, не фізичний вхід.';
  FChart.Invalidate;
end;

procedure TWideWindow.OpenClicked(Sender:TObject);
begin
  if FDialog.Execute then LoadPhysical(FDialog.FileName);
end;

function TWideWindow.LoadPhysical(const FileName:String):Boolean;
var F:TFileStream; Physical, Audit:RawByteString;
    Candidate:TWideWords; Words:TExactWords; I:SizeInt;
begin
  Result:=False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(FileName))<>'.sens' then
      raise Exception.Create('очікується лише фізичний .sens');
    F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MaxViewBytes) then
        raise Exception.Create('порожній або більший за 512 КіБ фізичний файл');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    { Суворий чинний codec. Жодного власного T5M чи доменного decoder. }
    DecodeT5M(Physical,Words);
    if EncodeT5M(Words)<>Physical then
      raise Exception.Create('неканонічні фізичні T5M байти');
    CollectWideWords(Physical,Candidate);
    Audit:=WideTSV(Candidate);
    if Audit='' then raise Exception.Create('некоректний широкий огляд');
    if Length(Candidate)>MaxWideWords then
      raise Exception.Create('надмірна кількість широких слів');
    { UI-commit лише після повного фізичного допуску. }
    FWords:=Candidate;
    if Length(FWords)>0 then FGrid.RowCount:=Length(FWords)+1;
    for I:=0 to High(FWords) do begin
      FGrid.Cells[0,I+1]:=IntToStr(FWords[I].Span.WordIndex);
      FGrid.Cells[1,I+1]:=IntToStr(FWords[I].Width);
      FGrid.Cells[2,I+1]:=String(FWords[I].Bits);
      FGrid.Cells[3,I+1]:='['+IntToStr(FWords[I].Span.TritStart)+','+
        IntToStr(FWords[I].Span.TritEnd)+')';
      FGrid.Cells[4,I+1]:='['+IntToStr(FWords[I].Span.ByteStart)+','+
        IntToStr(FWords[I].Span.ByteEnd)+')';
    end;
    FStatus.Caption:='Фізичних слів ≥12 біт: '+IntToStr(Length(FWords))+
      '. Ширина сама по собі НЕ доводить числовий домен.';
    FChart.Invalidate;
    Result:=True;
  except
    on E:Exception do begin
      ClearView;
      FStatus.Caption:='Відхилено: '+E.Message;
    end;
  end;
end;

procedure TWideWindow.SelectBar(Index:SizeInt);
begin
  if (Index<0) or (Index>=Length(FWords)) then Exit;
  FSelected:=Index;
  FGrid.Row:=Index+1;
  FSelection.Caption:='Фізичне слово №'+IntToStr(FWords[Index].Span.WordIndex)+
    '; '+IntToStr(FWords[Index].Width)+' біт; точні біти: '+
    String(FWords[Index].Bits);
  FChart.Invalidate;
end;

procedure TWideWindow.ClickBars(Sender:TObject; Button:TMouseButton;
  Shift:TShiftState; X,Y:Integer);
var Index:SizeInt;
begin
  if (Button<>mbLeft) or (X<BarLeft) or (X>=FChart.Width) or
    (Y<BarTop) then Exit;
  Index:=(Y-BarTop) div RowHeight;
  if Index<VisibleBars then SelectBar(Index);
end;

procedure TWideWindow.DrawBars(C:TCanvas; AWidth,AHeight:Integer);
var I,MaxWidth,LengthPx,XEnd,Y:Integer; F:TWideWord;
begin
  C.Brush.Color:=clWhite;
  C.FillRect(Rect(0,0,AWidth,AHeight));
  C.Font.Color:=clBlack;
  C.TextOut(10,3,'Біти фізичних слів; перші 8; натисніть смугу');
  if Length(FWords)=0 then Exit;
  MaxWidth:=12;
  for I:=0 to High(FWords) do
    if FWords[I].Width>MaxWidth then MaxWidth:=FWords[I].Width;
  for I:=0 to High(FWords) do begin
    if I>=VisibleBars then Break;
    F:=FWords[I];
    Y:=BarTop+I*RowHeight;
    C.Font.Color:=clBlack;
    C.TextOut(7,Y+4,'слово '+IntToStr(F.Span.WordIndex)+
      ' · '+IntToStr(F.Width)+' біт');
    LengthPx:=Int64(F.Width)*(AWidth-BarLeft-22) div MaxWidth;
    if LengthPx<2 then LengthPx:=2;
    XEnd:=BarLeft+LengthPx;
    if I=FSelected then C.Brush.Color:=clMaroon
    else C.Brush.Color:=clTeal;
    C.FillRect(Rect(BarLeft,Y+3,XEnd,Y+20));
  end;
  C.Font.Color:=clBlack;
  C.TextOut(8,BarTop+VisibleBars*RowHeight+3,
    'D12+ — поріг огляду, не твердження про арифметику.');
end;

procedure TWideWindow.PaintBars(Sender:TObject);
begin
  DrawBars(FChart.Canvas,FChart.Width,FChart.Height);
end;

procedure TWideWindow.Require(Ok:Boolean; const Why:String);
begin
  if not Ok then raise Exception.Create('LCL-ШИРОКІ-ПОМИЛКА: '+Why);
end;

procedure TWideWindow.SelfCheck(const SmallFile,UpstreamFile,BadFile,
  EmptyFile,HumanFile:String);
var Bitmap:TBitmap;
begin
  Require((FChart.Parent=Self) and (FGrid.Parent=Self),
    'немає графічних віджетів Lazarus');
  Require(LoadPhysical(SmallFile),'невірний позитив D12/D13/D24');
  Require((Length(FWords)=3) and (FWords[0].Width=12) and
    (FWords[1].Width=13) and (FWords[2].Width=24),
    'фізичні довжини втрачено');
  Require((FWords[0].Bits='000000000001') and
    (FWords[1].Bits='0000000000000') and
    (FWords[2].Bits='000000000000000000000001'),
    'загублено провідні нулі');
  Require((FGrid.Cells[0,1]='2') and (FGrid.Cells[1,2]='13') and
    (FGrid.Cells[3,1]='[2,14)') and
    (FGrid.Cells[4,1]='[0,3)'),
    'змінено фізичні адреси');
  Bitmap:=TBitmap.Create;
  try
    Bitmap.SetSize(FChart.Width,FChart.Height);
    DrawBars(Bitmap.Canvas,Bitmap.Width,Bitmap.Height);
    Require(Bitmap.Canvas.Pixels[BarLeft+10,BarTop+10]=clTeal,
      'реальний Canvas не намалював бітову ширину');
  finally Bitmap.Free; end;
  ClickBars(FChart,mbLeft,[],BarLeft+15,BarTop+RowHeight+10);
  Require((FSelected=1) and (FGrid.Row=2) and
    (Pos('13 біт',FSelection.Caption)>0),
    'фізичний клік не синхронізував таблицю');
  Require(LoadPhysical(UpstreamFile),
    'pinned SENS .sens свідок не прочитано');
  Require((Length(FWords)>=2) and
    (FWords[0].Width=24) and (FWords[1].Width=24),
    'реальний pinned D12 числовий .sens не зберіг ширини 24');
  Require(not LoadPhysical(BadFile),'зіпсований T5M прийнято');
  Require((Length(FWords)=0) and (FSelected=-1) and
    (FGrid.Cells[0,1]=''),'зіпсований файл залишив дані');
  Require(Pos('Відхилено:',FStatus.Caption)=1,
    'немає української діагностики');
  Require(not LoadPhysical(HumanFile),'.lisp прийнято за .sens');
  Require((Length(FWords)=0) and (FGrid.Cells[2,1]=''),
    'після .lisp лишилися попередні біти');
  Require(not LoadPhysical(EmptyFile),'порожній файл прийнято');
  Require(not LoadPhysical('неіснуючий.sens'),'відсутній файл прийнято');
  Require(Length(FWords)=0,'помилка лишила широкі слова');
  WriteLn('LCL-ШИРОКІ-ГАРАЗД Lazarus=GTK2 Canvas=справжній',
    ' D12,D13,D24=фізичні pinned-SENS=24-біт',
    ' провідні-нулі=так адреси=точні відмови=очищені',
    ' арифметика=НЕ_ДОВЕДЕНА');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — широкі фізичні слова';
    Application.CreateForm(TWideWindow,Win);
    if ParamCount=0 then Application.Run
    else if (ParamCount=1) then begin
      Win.LoadPhysical(ParamStr(1)); Application.Run;
    end else if (ParamCount=6) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка')) then begin
      Win.Show; Application.ProcessMessages;
      Win.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6));
    end else raise Exception.Create('невідомі аргументи широкого оглядача');
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ШИРОКІ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
