{ G1.9 — ДВА незалежні свідки pinned SENS: звичайна українська
  .lisp проєкція та канонічна T5M .sens. Ми НЕ перекладаємо один
  файл в інший і НЕ доводимо їх семантичну еквівалентність.
  П’ять принципів — рамка праці, НЕ нові мовні закони. }
program sens_paired_witness;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, Graphics, Math, wsm.t5m, wsm.physloc,
  wsm.widespan, wsm.source, wsm.domain, wsm.bind, wsm.ukroundtrip;
const
  MaxSourceBytes = 2*1024*1024;
type
  TPairedWitness = class(TForm)
  private
    FSource: TMemo;
    FGrid: TStringGrid;
    FPaint: TPaintBox;
    FStatus, FInfo, FComparison: TLabel;
    FCompareButton: TButton;
    FChoose: TOpenDialog;
    FWide: TWideWords;
    FSourceBytes, FPhysicalBytes: RawByteString;
    FWordCount, FFormCount, FSelected: SizeInt;
    procedure ChooseClick(Sender: TObject);
    procedure CompareClick(Sender: TObject);
    function CheckExactPair: Boolean;
    procedure GridClick(Sender: TObject);
    procedure BitsPaint(Sender: TObject);
    procedure PaintBits(TargetCanvas: TCanvas; W,H: Integer);
    procedure ClearView;
    procedure Failure(const Reason: String);
    procedure SelectWide(Index: SizeInt);
    function ReadBytes(const Path: String; Limit: SizeInt): RawByteString;
    procedure Demand(Ok:Boolean;const Why:String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPair(const LispPath, BinaryPath: String): Boolean;
    procedure SelfTest(const LocalLisp, LocalSens, LawLisp, LawSens,
      FiveLisp, FiveSens, BadLisp, BadSens, ExactLisp, ExactSens:String);
  end;
var Window:TPairedWitness;

constructor TPairedWitness.Create(AOwner:TComponent);
var Bar, LeftPane, RightPane, BottomPane:TPanel;
    Split:TSplitter; L:TLabel; B:TButton;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — дві проєкції, два незалежні свідки';
  Width:=1140; Height:=720; Position:=poScreenCenter;
  Bar:=TPanel.Create(Self); Bar.Parent:=Self; Bar.Align:=alTop;
  Bar.Height:=54; Bar.BevelOuter:=bvNone;
  B:=TButton.Create(Self); B.Parent:=Bar;
  B.SetBounds(12,9,260,34);
  B.Caption:='Відкрити пару .lisp / .sens…'; B.OnClick:=@ChooseClick;
  L:=TLabel.Create(Self); L.Parent:=Bar;
  FCompareButton:=TButton.Create(Self);
  FCompareButton.Parent:=Bar;
  FCompareButton.SetBounds(282,9,245,34);
  FCompareButton.Caption:='Перевірити точну відповідність';
  FCompareButton.OnClick:=@CompareClick;
  FCompareButton.Enabled:=False;
  L.SetBounds(540,16,550,26);
  L.Caption:='Порівняння доводить тільки фізичні байти, не семантику.';
  FChoose:=TOpenDialog.Create(Self);
  FChoose.Title:='Виберіть фізичний .sens з однойменним .lisp';
  FChoose.Filter:='Двійкові файли SENS (*.sens)|*.sens';
  BottomPane:=TPanel.Create(Self); BottomPane.Parent:=Self;
  BottomPane.Align:=alBottom; BottomPane.Height:=202;
  BottomPane.BevelOuter:=bvNone;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=BottomPane;
  FStatus.Align:=alBottom; FStatus.Height:=26;
  FInfo:=TLabel.Create(Self); FInfo.Parent:=BottomPane;
  FInfo.Align:=alBottom; FInfo.Height:=26;
  FComparison:=TLabel.Create(Self); FComparison.Parent:=BottomPane;
  FComparison.Align:=alBottom; FComparison.Height:=26;
  FPaint:=TPaintBox.Create(Self); FPaint.Parent:=BottomPane;
  FPaint.Align:=alClient; FPaint.OnPaint:=@BitsPaint;

  LeftPane:=TPanel.Create(Self); LeftPane.Parent:=Self;
  LeftPane.Align:=alLeft; LeftPane.Width:=520;
  LeftPane.Caption:=''; LeftPane.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=LeftPane;
  L.Align:=alTop; L.Height:=30;
  L.Caption:='Людська .lisp — тільки UTF-8 українська проєкція';
  FSource:=TMemo.Create(Self); FSource.Parent:=LeftPane;
  FSource.Align:=alClient; FSource.ReadOnly:=True;
  FSource.ScrollBars:=ssBoth; FSource.WordWrap:=False;

  Split:=TSplitter.Create(Self); Split.Parent:=Self;
  Split.Align:=alLeft; Split.Width:=7;
  RightPane:=TPanel.Create(Self); RightPane.Parent:=Self;
  RightPane.Align:=alClient; RightPane.Caption:='';
  RightPane.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=RightPane;
  L.Align:=alTop; L.Height:=30;
  L.Caption:='Фізичні D12+ біти з .sens (числовий закон НЕ виводиться)';
  FGrid:=TStringGrid.Create(Self); FGrid.Parent:=RightPane;
  FGrid.Align:=alClient; FGrid.ColCount:=5; FGrid.FixedRows:=1;
  FGrid.FixedCols:=0; FGrid.RowCount:=2;
  FGrid.Options:=FGrid.Options+[goRowSelect,goColSizing];
  FGrid.ColWidths[0]:=65; FGrid.ColWidths[1]:=75;
  FGrid.ColWidths[2]:=225; FGrid.ColWidths[3]:=110;
  FGrid.ColWidths[4]:=110;
  FGrid.Cells[0,0]:='Слово №';
  FGrid.Cells[1,0]:='Ширина';
  FGrid.Cells[2,0]:='Точні двійкові біти';
  FGrid.Cells[3,0]:='Трити [a,b)';
  FGrid.Cells[4,0]:='Байти [a,b)';
  FGrid.OnClick:=@GridClick;
  ClearView;
end;

procedure TPairedWitness.ClearView;
var J:Integer;
begin
  FSourceBytes:=''; FPhysicalBytes:='';
  FCompareButton.Enabled:=False;
  SetLength(FWide,0);
  FWordCount:=0; FFormCount:=0; FSelected:=-1;
  FSource.Clear;
  FGrid.RowCount:=2;
  for J:=0 to FGrid.ColCount-1 do FGrid.Cells[J,1]:='';
  FInfo.Caption:='Виберіть слово D12+, щоб побачити точні біти.';
  FStatus.Caption:='Відкрийте два незалежні свідки з pinned SENS.';
  FComparison.Caption:='Відповідність не перевірено. Для D12+ не припускати числових законів.';
  FPaint.Invalidate;
end;

procedure TPairedWitness.Failure(const Reason:String);
begin
  ClearView;
  FStatus.Caption:='Помилка допуску свідків: '+Reason;
end;

function TPairedWitness.ReadBytes(const Path:String;Limit:SizeInt):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>Limit) then
      raise Exception.Create('порожній або надмірний файл: '+ExtractFileName(Path));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

function TPairedWitness.LoadPair(const LispPath,BinaryPath:String):Boolean;
var TextBytes,Physical:RawByteString;
    Doc:TSourceDocument; Wide:TWideWords;
    Words:TExactWords;
    I,FormsCount:SizeInt; S:TPhysicalWordSpan;
begin
  Result:=False; ClearView;
  Doc:=nil;
  try
    if (LowerCase(ExtractFileExt(LispPath))<>'.lisp') or
       (LowerCase(ExtractFileExt(BinaryPath))<>'.sens') then
      raise Exception.Create('потрібні окремі .lisp і .sens');
    TextBytes:=ReadBytes(LispPath,MaxSourceBytes);
    Physical:=ReadBytes(BinaryPath,MAX_T5M_FILE_BYTES);
    Doc:=ReadUkrainianSource(TextBytes);
    FormsCount:=Length(Doc.Forms);
    if FormsCount=0 then raise Exception.Create('немає форм у .lisp');
    { Ніякого порівняння source atoms із physical words тут немає! }
    CollectWideWords(Physical,Wide);
    DecodeT5M(Physical,Words);
    FSourceBytes:=TextBytes;
    FPhysicalBytes:=Physical;
    FCompareButton.Enabled:=True;
    FFormCount:=FormsCount;
    FWordCount:=Length(Words);
    FWide:=Wide;
    FSource.Lines.Text:=String(FSourceBytes);
    FGrid.RowCount:=Max(2,Length(FWide)+1);
    for I:=0 to High(FWide) do begin
      S:=FWide[I].Span;
      FGrid.Cells[0,I+1]:=IntToStr(S.WordIndex);
      FGrid.Cells[1,I+1]:='D'+IntToStr(FWide[I].Width);
      FGrid.Cells[2,I+1]:=String(FWide[I].Bits);
      FGrid.Cells[3,I+1]:='['+IntToStr(S.TritStart)+','+
        IntToStr(S.TritEnd)+')';
      FGrid.Cells[4,I+1]:='['+IntToStr(S.ByteStart)+','+
        IntToStr(S.ByteEnd)+')';
    end;
    FStatus.Caption:='Українських форм: '+IntToStr(FFormCount)+
      '; фізичних слів: '+IntToStr(FWordCount)+
      '; широких D12+: '+IntToStr(Length(FWide))+
      '. Паритет не перевірявся.';
    if Length(FWide)>0 then SelectWide(0)
    else FInfo.Caption:='У цьому .sens немає фізичних слів ширини D12+.';
    Result:=True;
  except
    on E:Exception do Failure(E.Message);
  end;
  Doc.Free;
end;

{ Явна перевірка виключно вже доведеного оборотного піднабору.
  Підтримані звичайні «укр» і фізичні байти мусять бути точно
  однаковими після чинного pinned reader/binder/T5M. 5 принципів
  кореневого SENS — інженерні орієнтири, не нові runtime закони.
  Недоведена форма D12+ зберігається у вікні для незалежного огляду. }
function TPairedWitness.CheckExactPair:Boolean;
var Tables:TDomainSet; Longs:TLongProjection;
    Packed, CanonicalText:RawByteString;
begin
  Result:=False;
  FComparison.Caption:='Відповідність не доведено.';
  if (FSourceBytes='') or (FPhysicalBytes='') then begin
    FComparison.Caption:='Не доведено: відкрийте обидва файли.';
    Exit;
  end;
  try
    LoadPinnedDomains('external/sens',Tables);
    LoadPinnedLongProjection('external/sens',Tables,Longs);
    Packed:=UkrainianToPhysical(FSourceBytes,Tables,Longs);
    if Packed<>FPhysicalBytes then begin
      FComparison.Caption:='Не доведено: фізичні байти двох свідків РІЗНІ.';
      Exit;
    end;
    { Вимагаємо обидва напрямки на точних байтах. Не змінюємо
      FSourceBytes та FPhysicalBytes при успіху чи відмові. }
    CanonicalText:=PhysicalToUkrainian(FPhysicalBytes,Tables,Longs);
    if CanonicalText='' then
      raise Exception.Create('Порожня канонічна українська проєкція');
    Result:=True;
    FComparison.Caption:='Перевірено: укр .lisp ↔ .sens байт-у-байт; не семантичний паритет.';
  except
    on E:Exception do
      FComparison.Caption:='Не доведено для цієї пари: '+E.Message;
  end;
end;

procedure TPairedWitness.CompareClick(Sender:TObject);
begin
  CheckExactPair;
end;

procedure TPairedWitness.ChooseClick(Sender:TObject);
var S:String;
begin
  if FChoose.Execute then begin
    S:=FChoose.FileName;
    LoadPair(ChangeFileExt(S,'.lisp'),S);
  end;
end;

procedure TPairedWitness.SelectWide(Index:SizeInt);
begin
  if (Index<0) or (Index>=Length(FWide)) then Exit;
  FSelected:=Index;
  FGrid.Row:=Index+1;
  FInfo.Caption:='Слово №'+IntToStr(FWide[Index].Span.WordIndex)+
    ' — D'+IntToStr(FWide[Index].Width)+
    '; перші '+IntToStr(Min(FWide[Index].Width,48))+
    ' точних бітів із '+IntToStr(FWide[Index].Width)+
    '; це НЕ десяткове значення.';
  FPaint.Invalidate;
end;

procedure TPairedWitness.GridClick(Sender:TObject);
begin SelectWide(FGrid.Row-1); end;

procedure TPairedWitness.PaintBits(TargetCanvas:TCanvas;W,H:Integer);
var I,Count,Step,X:Integer; Bits:RawByteString;
begin
  TargetCanvas.Brush.Color:=clWhite;
  TargetCanvas.FillRect(0,0,W,H);
  if FSelected<0 then Exit;
  if FSelected>High(FWide) then Exit;
  Bits:=FWide[FSelected].Bits;
  Count:=Min(Length(Bits),48);
  if Count=0 then Exit;
  Step:=Max(5,Min(24,(W-36) div Count));
  for I:=0 to Count-1 do begin
    X:=16+I*Step;
    if Bits[I+1]='1' then TargetCanvas.Brush.Color:=clNavy
    else TargetCanvas.Brush.Color:=clSilver;
    TargetCanvas.Pen.Color:=clGray;
    TargetCanvas.Rectangle(X,16,X+Step-3,57);
  end;
  TargetCanvas.Brush.Color:=clWhite;
  TargetCanvas.Font.Color:=clBlack;
  TargetCanvas.TextOut(16,67,'0/1 — фізичні біти, не обчислені числа');
end;

procedure TPairedWitness.BitsPaint(Sender:TObject);
begin PaintBits(FPaint.Canvas,FPaint.Width,FPaint.Height); end;

procedure TPairedWitness.Demand(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('самоперевірка Lazarus: '+Why);
end;

procedure TPairedWitness.SelfTest(const LocalLisp,LocalSens,LawLisp,LawSens,
  FiveLisp,FiveSens,BadLisp,BadSens,ExactLisp,ExactSens:String);
var Bmp:TBitmap;
begin
  Demand(LoadPair(LocalLisp,LocalSens),'локальні фізичні широкі слова');
  Demand((Length(FWide)=3) and (FGrid.RowCount=4),
    'точно три D12+ рядки');
  Demand((FGrid.Cells[0,1]='2') and (FGrid.Cells[1,1]='D12') and
         (FGrid.Cells[2,1]='000000000001') and
         (FGrid.Cells[3,1]='[2,14)') and
         (FGrid.Cells[4,1]='[0,3)') and
         (FGrid.Cells[1,2]='D13') and
         (FGrid.Cells[2,2]='0000000000000'),
    'провідні нулі або фізичні інтервали D12/D13');
  Demand(Pos('сполучити',FSourceBytes)>0,
    'українська .lisp не показана без перетворення');
  Demand(not CheckExactPair,'довільна D12+ пара помилково отримала паритет');
  Demand(Pos('Не доведено',FComparison.Caption)>0,
    'непідтримана D12+ пара не отримала чітку межу');
  Demand((Length(FWide)=3) and (FSourceBytes<>''),
    'невдала перевірка втратила обидва незалежні свідки');
  SelectWide(0);
  Bmp:=TBitmap.Create;
  try
    Bmp.SetSize(800,114);
    PaintBits(Bmp.Canvas,Bmp.Width,Bmp.Height);
    Demand(Bmp.Canvas.Pixels[28,32]<>Bmp.Canvas.Pixels[292,32],
      'справжній Canvas не розрізнив нуль та одиницю D12');
  finally Bmp.Free end;
  SelectWide(1);
  Demand((FSelected=1) and (Pos('D13',FInfo.Caption)>0),
    'клік-проєкція рядка не перемикає ширину');

  { Ці .lisp/.sens реально взяті з pinned ROOT SENS.
    Вони — окремі свідки, не доказ оберненості один одного! }
  Demand(LoadPair(LawLisp,LawSens),'реальна пара pinned числового закону');
  Demand((FWordCount>0) and (FFormCount>0) and
    (Pos('число?',FSourceBytes)>0),'закон D12 з кореневого SENS');
  Demand(not CheckExactPair,
    'широке слово pinned D12+ не дозволено неявно вивести з української назви');
  Demand(Pos('Не доведено',FComparison.Caption)>0,
    'числовий свідок помилково оголошено порівняним');
  Demand(LoadPair(FiveLisp,FiveSens),'реальна пара pinned принципу п’ять');
  Demand((FWordCount>0) and (FFormCount>0) and
    (Pos('принцип-п',FSourceBytes)>0),
    'виконуваний принцип п’ять з pinned SENS');
  Demand(not CheckExactPair,
    'файл кореневого принципу п’ять не має доведеного фізичного round-trip');

  { ЄДИНИЙ позитивний доказ — звичайна повна проєкція укр та
    той самий T5M, що реально створив сенст5м. Кнопка теж працює. }
  Demand(LoadPair(ExactLisp,ExactSens),
    'відкрити правильну фізично відповідну пару');
  Demand(FCompareButton.Enabled,'справжня кнопка порівняння недоступна');
  CompareClick(FCompareButton);
  Demand(Pos('байт-у-байт',FComparison.Caption)>0,
    'натискання кнопки не підтвердило ті самі фізичні байти');
  Demand(CheckExactPair,'вже підтримані D1/D3 звичайні укр не відновлюються');

  Demand(LoadPair(ExactLisp,LocalSens),
    'окремі коректні файли з різним канонічним вмістом');
  Demand(not CheckExactPair,'різні фізичні програми оголошено тотожними');
  Demand(Pos('Не доведено',FComparison.Caption)>0,
    'порівняння різних бінарних програм не повідомило про межу');

  Demand(not LoadPair(BadLisp,LocalSens),
    'некоректна українська UTF-8 проєкція прийнята');
  Demand((Length(FWide)=0) and (FSource.Lines.Count=0) and
         (FGrid.Cells[2,1]='') and (FSelected=-1) and
         (FPhysicalBytes='') and (not FCompareButton.Enabled) and
         (Pos('не перевірено',FComparison.Caption)>0),
    'після помилки UTF-8 залишилися дані GUI');
  Demand(not LoadPair(LocalLisp,BadSens),
    'невалідний T5M прийнято');
  Demand((Length(FWide)=0) and (FSource.Lines.Count=0) and
         (FGrid.Cells[1,1]='') and (FSelected=-1) and
         (FPhysicalBytes='') and (not FCompareButton.Enabled),
    'після пошкодження T5M не очищено GUI');
  Demand(not LoadPair('немає-такого-файлу.lisp',LocalSens),
    'відсутній .lisp прийнято');
  Demand(not LoadPair(LocalLisp,'немає-такого-файлу.sens'),
    'відсутній .sens прийнято');
  Demand(LoadPair(LocalLisp,LocalSens),
    'після помилки UI не відновлюється');
  WriteLn('LCL-ПАРНІ-СВІДКИ-ГАРАЗД pinned=два-справжні-файли',
    ' D12-D13=точні Canvas=0/1 UTF8=ок T5M=ок',
    ' укр-точні-байти=піднабір-доведено D12+=НЕ-ДОВЕДЕНО',
    ' виконання=НЕ-ДОВЕДЕНО');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — дві проєкції';
    Application.CreateForm(TPairedWitness,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>11 then
        raise Exception.Create('потрібні 10 файлів для самоперевірки');
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),
        ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10),ParamStr(11));
    end else if ParamCount=0 then Application.Run
    else if ParamCount=2 then begin
      if not Window.LoadPair(ParamStr(1),ParamStr(2)) then ExitCode:=2
      else Application.Run;
    end else raise Exception.Create('потрібна пара .lisp і .sens');
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-ПАРНІ-СВІДКИ-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
end.
