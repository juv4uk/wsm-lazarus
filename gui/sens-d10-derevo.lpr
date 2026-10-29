{ Справжній Lazarus/LCL оглядач точних D1–D10 фізичних дерев.
  Відображає вже допущені T5M/D2 та pinned координати, не виконує SENS. }
program sens_d10_derevo;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids,
  ComCtrls, Dialogs, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind,
  wsm.binarytree, wsm.proektsii;

const MaxVisibleNodes = 4096;
type
  TD10Window = class(TForm)
  private
    FTree: TTreeView;
    FGrid: TStringGrid;
    FDetails: TMemo;
    FStatus: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FEntries: TBinaryTreeEntries;
    FCatalog: TProektsiiCatalog;
    FTestPath: String;
    procedure ClearView;
    procedure OpenClicked(Sender: TObject);
    procedure SelectedChanged(Sender: TObject; Node: TTreeNode);
    procedure Demand(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const Path: String): Boolean;
    procedure SelfCheck(const Good,W11,W12,Bad,Unclosed,TextPath: String);
  end;

var Window: TD10Window;

constructor TD10Window.Create(AOwner: TComponent);
var I: Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичне дерево D1–D10';
  Width:=1190; Height:=740; Position:=poScreenCenter;
  FOpen:=TButton.Create(Self);
  FOpen.Parent:=Self; FOpen.SetBounds(12,12,260,36);
  FOpen.Caption:='Відкрити фізичний .sens';
  FOpen.OnClick:=@OpenClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Виберіть двійковий файл SENS';
  FDialog.Filter:='Двійкові SENS (*.sens)|*.sens';
  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=Self; FStatus.SetBounds(12,54,1145,28);
  FTree:=TTreeView.Create(Self);
  FTree.Parent:=Self; FTree.SetBounds(12,90,365,435);
  FTree.ReadOnly:=True; FTree.HideSelection:=False;
  FTree.OnChange:=@SelectedChanged;
  FGrid:=TStringGrid.Create(Self);
  FGrid.Parent:=Self; FGrid.SetBounds(388,90,785,435);
  FGrid.ColCount:=6; FGrid.FixedCols:=0;
  FGrid.RowCount:=2; FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=53; FGrid.ColWidths[1]:=65;
  FGrid.ColWidths[2]:=77; FGrid.ColWidths[3]:=255;
  FGrid.ColWidths[4]:=151; FGrid.ColWidths[5]:=165;
  FGrid.Cells[0,0]:='Вузол';
  FGrid.Cells[1,0]:='Форма';
  FGrid.Cells[2,0]:='Домен';
  FGrid.Cells[3,0]:='Точні біти';
  FGrid.Cells[4,0]:='Трити [від,до)';
  FGrid.Cells[5,0]:='Байти [від,до)';
  FDetails:=TMemo.Create(Self);
  FDetails.Parent:=Self; FDetails.SetBounds(12,538,1160,155);
  FDetails.ReadOnly:=True; FDetails.WordWrap:=False;
  FDetails.ScrollBars:=ssBoth;
  FTestPath:='';
  ClearView;
  for I:=0 to 5 do
    if FGrid.Cells[I,0]='' then
      raise Exception.Create('немає заголовка таблиці');
end;

procedure TD10Window.ClearView;
var I,J:Integer;
begin
  SetLength(FEntries,0);
  for I:=1 to 10 do SetLength(FCatalog[I],0);
  FTree.Items.Clear;
  FGrid.RowCount:=2;
  for J:=0 to 5 do FGrid.Cells[J,1]:='';
  FDetails.Clear;
  FStatus.Caption:='D1–D10: фізична структура, викличність не перевірено.';
end;

procedure TD10Window.Demand(Condition:Boolean;const Why:String);
begin
  if not Condition then
    raise Exception.Create('LCL-перевірка: '+Why);
end;

{ Entry отримано тільки після ReadBinaryTreeD10 і pinned catalog.
  Поверхні — дані; навіть D7 SYN не стає викличною головою. }
procedure TD10Window.SelectedChanged(Sender:TObject;Node:TTreeNode);
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var I,D,K,J:SizeInt; E:TBinaryTreeEntry; R:TProektsiiaRow;
begin
  FDetails.Clear;
  if Node=nil then Exit;
  I:=SizeInt(PtrUInt(Node.Data))-1;
  if (I<0) or (I>=Length(FEntries)) then Exit;
  E:=FEntries[I];
  FGrid.Row:=I+1;
  FDetails.Lines.Add(String(BinaryTreeCaption(E)));
  if E.HasPhysicalWord then
    FDetails.Lines.Add('Фізичне слово №'+IntToStr(E.Physical.WordIndex)+
      '; трити=['+IntToStr(E.Physical.TritStart)+','+
      IntToStr(E.Physical.TritEnd)+'); байти=['+
      IntToStr(E.Physical.ByteStart)+','+IntToStr(E.Physical.ByteEnd)+')')
  else
    FDetails.Lines.Add('Похідна D2 пара: власного фізичного слова немає');
  if not (E.Kind in [dkIdentity,dkEmpty]) then Exit;
  D:=E.Key.Width;
  if (D<1) or (D>10) then
    raise Exception.Create('листок поза точними D1–D10');
  K:=E.Key.Bits;
  if (K<0) or (K>=Length(FCatalog[D])) then
    raise Exception.Create('немає pinned проєкції');
  R:=FCatalog[D][K];
  if not SameKey(R.Key,E.Key) then
    raise Exception.Create('не збіглася точна координата проєкції');
  FDetails.Lines.Add('D'+IntToStr(D)+':'+String(KeyBits(E.Key))+
    ' — шість проєкцій, не мовний dispatch');
  for J:=0 to 5 do
    FDetails.Lines.Add(Names[J]+': '+SurfaceForDisplay(R.Surface[J]));
end;

function TD10Window.LoadFile(const Path:String):Boolean;
var Stream:TFileStream; Physical:RawByteString; Tables:TDomainSet;
    NewEntries:TBinaryTreeEntries; NewCatalog:TProektsiiCatalog;
    Nodes:array of TTreeNode; I,D,K:SizeInt; E:TBinaryTreeEntry;
begin
  Result:=False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('вхід лише двійковий .sens, не проєкція .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<=0) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або завеликий фізичний файл');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free;end;
    LoadPinnedDomains('external/sens',Tables);
    LoadPinnedProjections('external/sens',NewCatalog);
    ReadBinaryTreeD10(Physical,Tables,NewEntries);
    if (Length(NewEntries)=0) or (Length(NewEntries)>MaxVisibleNodes) then
      raise Exception.Create('поза межею 1..4096 вузлів');
    { Повний exact-domain/projection guard до публікації віджетів. }
    for I:=0 to High(NewEntries) do begin
      E:=NewEntries[I];
      if not (E.Kind in [dkIdentity,dkEmpty]) then Continue;
      D:=E.Key.Width; K:=E.Key.Bits;
      if (D<1) or (D>10) or (K<0) or
         (K>=Length(NewCatalog[D])) then
        raise Exception.Create('невідома координата D1–D10');
      if not SameKey(NewCatalog[D][K].Key,E.Key) then
        raise Exception.Create('несумісність із pinned проєкцією');
    end;
    FEntries:=NewEntries;
    FCatalog:=NewCatalog;
    SetLength(Nodes,Length(FEntries));
    FGrid.RowCount:=Length(FEntries)+1;
    FTree.Items.BeginUpdate;
    try
      for I:=0 to High(FEntries) do begin
        E:=FEntries[I];
        if E.ParentIndex=-1 then
          Nodes[I]:=FTree.Items.Add(nil,String(BinaryTreeCaption(E)))
        else begin
          if (E.ParentIndex<0) or (E.ParentIndex>=I) then
            raise Exception.Create('неправильний індекс D2-батька');
          Nodes[I]:=FTree.Items.AddChild(Nodes[E.ParentIndex],
            String(BinaryTreeCaption(E)));
        end;
        Nodes[I].Data:=Pointer(PtrUInt(I+1));
        FGrid.Cells[0,I+1]:=IntToStr(I);
        FGrid.Cells[1,I+1]:=IntToStr(E.RootIndex);
        if E.Kind in [dkIdentity,dkEmpty] then begin
          FGrid.Cells[2,I+1]:='D'+IntToStr(E.Key.Width);
          FGrid.Cells[3,I+1]:=String(KeyBits(E.Key));
        end else begin
          FGrid.Cells[2,I+1]:='—';
          FGrid.Cells[3,I+1]:='—';
        end;
        if E.HasPhysicalWord then begin
          FGrid.Cells[4,I+1]:='['+IntToStr(E.Physical.TritStart)+','+
            IntToStr(E.Physical.TritEnd)+')';
          FGrid.Cells[5,I+1]:='['+IntToStr(E.Physical.ByteStart)+','+
            IntToStr(E.Physical.ByteEnd)+')';
        end else begin
          FGrid.Cells[4,I+1]:='немає';
          FGrid.Cells[5,I+1]:='немає';
        end;
      end;
      FTree.FullExpand;
    finally FTree.Items.EndUpdate;end;
    FStatus.Caption:='Допущено '+IntToStr(Length(FEntries))+
      ' вузлів D1–D10; виконання та викличність не доведені.';
    SelectedChanged(FTree,Nodes[0]);
    Result:=True;
  except
    on E:Exception do begin
      ClearView;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

procedure TD10Window.OpenClicked(Sender:TObject);
begin
  if FTestPath<>'' then LoadFile(FTestPath)
  else if FDialog.Execute then LoadFile(FDialog.FileName);
end;

procedure TD10Window.SelfCheck(
  const Good,W11,W12,Bad,Unclosed,TextPath:String);
begin
  FTestPath:=Good;
  FOpen.Click; { справжнє натискання кнопки LCL }
  Demand(Length(FEntries)=5,'не допущено п’ять D2 вузлів');
  Demand((FTree.Items.Count=5) and
    (FTree.Items[1].Parent=FTree.Items[0]) and
    (FTree.Items[3].Parent=FTree.Items[0]) and
    (FTree.Items[4].Parent=nil),'зіпсована ієрархія D2');
  Demand((FGrid.RowCount=6) and
    (FGrid.Cells[2,2]='D10') and
    (FGrid.Cells[3,2]='0000000000') and
    (FGrid.Cells[2,3]='D7') and
    (FGrid.Cells[3,3]='0010110') and
    (FGrid.Cells[2,4]='D3') and
    (FGrid.Cells[3,4]='000') and
    (FGrid.Cells[3,5]='1111111111'),
    'втрата точних бітів D10/D7/D3');
  Demand((FEntries[1].Key.Width=10) and
    (FEntries[2].Key.Width=7) and
    (FEntries[3].Key.Width=3) and
    (FEntries[4].Key.Width=10) and
    (FEntries[1].Physical.WordIndex=2) and
    (FEntries[4].Physical.WordIndex=6),
    'помилкова фізична або доменна тотожність');
  SelectedChanged(FTree,FTree.Items[2]);
  Demand((Pos('D7:0010110',FDetails.Text)>0) and
    (Pos('ук:',FDetails.Text)>0) and
    (Pos('укр:',FDetails.Text)>0) and
    (Pos('san:',FDetails.Text)>0) and
    (Pos('en:',FDetails.Text)>0) and
    (Pos('LISP:',FDetails.Text)>0) and
    (Pos('sym:',FDetails.Text)>0),
    'не показано шість pinned поверхонь D7 SYN');
  SelectedChanged(FTree,FTree.Items[3]);
  Demand(Pos('D3:000',FDetails.Text)>0,'D3:000 втратило власну адресу');
  Demand(not LoadFile(W11),'W11 не підтримано доменним binder');
  Demand((Length(FEntries)=0) and (FTree.Items.Count=0) and
    (FGrid.RowCount=2) and (FDetails.Text=''),
    'W11 залишив старі вузли');
  Demand(not LoadFile(W12),'W12 не стає автоматично числовим D12');
  Demand(not LoadFile(Bad),'пошкоджений T5M прийнято');
  Demand(not LoadFile(Unclosed),'незакритий D2 прийнято');
  Demand(not LoadFile(TextPath),'підміна фізичного .sens файлом .lisp');
  Demand((FGrid.Cells[3,1]='') and (FDetails.Text=''),
    'пізня відмова залишила стару проєкцію');
  Demand(LoadFile(Good) and (Length(FEntries)=5),
    'не вдалося відновити після відмов');
  WriteLn('LCL-Д10-ДЕРЕВО-ГАРАЗД Lazarus=GTK2 D10=точний ',
    'D7=SYN-дані D3:000=окремий D2=дерево ',
    'проєкцій=6 відмови=очищено відновлення=так ',
    'виконання=НЕ-ДОВЕДЕНО');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичне дерево D10';
    Application.CreateForm(TD10Window,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>7 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
      Halt(0);
    end;
    if ParamCount>1 then Halt(64);
    if ParamCount=1 then Window.LoadFile(ParamStr(1));
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-Д10-ДЕРЕВО-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
