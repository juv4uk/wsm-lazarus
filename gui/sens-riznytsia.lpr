{ Справжній Lazarus/LCL: перша фізична відмінність двох T5M .sens.
  Тільки огляд. Слова не стають функціями чи числами. }
program sens_riznytsia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,SysUtils,Classes,Controls,StdCtrls,Grids,
  wsm.t5m,wsm.t5mdiff;
type
  TCompareWindow=class(TForm)
  private
    LeftPath,RightPath:TEdit;
    CheckButton:TButton;
    Status:TLabel;
    Table:TStringGrid;
    HasResult:Boolean;
    procedure ClearResult;
    procedure CheckClick(Sender:TObject);
    function ReadPhysical(const Path:String):RawByteString;
  public
    constructor Create(AOwner:TComponent);override;
    procedure CompareFiles(const L,R:String);
    procedure SelfTest(const L,R:String);
  end;
var Window:TCompareWindow;

constructor TCompareWindow.Create(AOwner:TComponent);
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — порівняння двох фізичних .sens';
  Width:=980;Height:=470;Position:=poScreenCenter;
  LeftPath:=TEdit.Create(Self);LeftPath.Parent:=Self;
  LeftPath.Align:=alTop;LeftPath.TextHint:='Перший двійковий .sens';
  RightPath:=TEdit.Create(Self);RightPath.Parent:=Self;
  RightPath.Align:=alTop;RightPath.TextHint:='Другий двійковий .sens';
  CheckButton:=TButton.Create(Self);CheckButton.Parent:=Self;
  CheckButton.Align:=alTop;CheckButton.Height:=40;
  CheckButton.Caption:='Знайти перше точне розходження';
  CheckButton.OnClick:=@CheckClick;
  Status:=TLabel.Create(Self);Status.Parent:=Self;
  Status.Align:=alBottom;Status.Height:=35;
  Table:=TStringGrid.Create(Self);Table.Parent:=Self;
  Table.Align:=alClient;Table.ColCount:=3;Table.RowCount:=3;
  Table.FixedCols:=0;Table.FixedRows:=1;
  Table.ColWidths[0]:=120;Table.ColWidths[1]:=340;
  Table.ColWidths[2]:=410;
  Table.Cells[0,0]:='Документ';
  Table.Cells[1,0]:='Точна ширина та біти';
  Table.Cells[2,0]:='Фізичний інтервал [початок,кінець)';
  Table.Cells[0,1]:='Лівий';Table.Cells[0,2]:='Правий';
  ClearResult;
end;

procedure TCompareWindow.ClearResult;
begin
  HasResult:=False;
  Table.Cells[1,1]:='';Table.Cells[2,1]:='';
  Table.Cells[1,2]:='';Table.Cells[2,2]:='';
  Status.Caption:='Немає допущеного порівняння';
end;

function TCompareWindow.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('вхід має бути .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('недопустимий розмір T5M');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure TCompareWindow.CompareFiles(const L,R:String);
var D:TPhysicalDifference; PL,PR:RawByteString;
  function WordText(const Bits:RawByteString;Present:Boolean):String;
  begin
    if Present then Result:='W'+IntToStr(Length(Bits))+':'+String(Bits)
    else Result:='КІНЕЦЬ ФАЙЛУ';
  end;
  function LocationText(HasWord:Boolean;TritA,TritB,ByteA,ByteB:SizeInt):String;
  begin
    if HasWord then Result:='трити ['+IntToStr(TritA)+','+
      IntToStr(TritB)+')  байти ['+IntToStr(ByteA)+','+IntToStr(ByteB)+')'
    else Result:='EOF; фізичне слово відсутнє';
  end;
begin
  ClearResult;LeftPath.Text:=L;RightPath.Text:=R;
  try
    PL:=ReadPhysical(L);PR:=ReadPhysical(R);
    ComparePhysical(PL,PR,D);
    if D.Equal then begin
      Status.Caption:='Файли мають рівні точні фізичні слова';
      Table.Cells[1,1]:='ОДНАКОВІ';Table.Cells[1,2]:='ОДНАКОВІ';
    end else begin
      Status.Caption:='Перша відмінність — слово '+IntToStr(D.WordIndex);
      Table.Cells[1,1]:=WordText(D.LeftBits,D.LeftPresent);
      Table.Cells[1,2]:=WordText(D.RightBits,D.RightPresent);
      Table.Cells[2,1]:=LocationText(D.LeftPresent,
        D.LeftSpan.TritStart,D.LeftSpan.TritEnd,
        D.LeftSpan.ByteStart,D.LeftSpan.ByteEnd);
      Table.Cells[2,2]:=LocationText(D.RightPresent,
        D.RightSpan.TritStart,D.RightSpan.TritEnd,
        D.RightSpan.ByteStart,D.RightSpan.ByteEnd);
    end;
    HasResult:=True;
  except
    on E:Exception do begin
      ClearResult;
      Status.Caption:='Відхилено: '+E.Message;
      raise;
    end;
  end;
end;

procedure TCompareWindow.CheckClick(Sender:TObject);
begin
  try CompareFiles(LeftPath.Text,RightPath.Text)
  except on E:Exception do begin end end;
end;

procedure TCompareWindow.SelfTest(const L,R:String);
var Rejected:Boolean;
  procedure Demand(C:Boolean;const Why:String);
  begin if not C then raise Exception.Create('LCL-РІЗНИЦЯ-ПОМИЛКА: '+Why) end;
begin
  CompareFiles(L,R);
  Demand(HasResult and (Pos('Перша відмінність',Status.Caption)>0),
    'порівняння не виконано в LCL');
  Demand((Table.Cells[1,1]<>'') and (Table.Cells[1,2]<>''),
    'не видно фізичних слів');
  Demand((Table.ColCount=3) and (Table.RowCount=3),
    'немає реальної таблиці');
  CompareFiles(L,L);
  Demand(HasResult and (Table.Cells[1,1]='ОДНАКОВІ'),
    'два однакові фізичні файли помилково різні');
  Rejected:=False;
  try CompareFiles(L,L+'.відсутній')
  except on E:Exception do Rejected:=True end;
  Demand(Rejected and (not HasResult) and (Table.Cells[1,1]=''),
    'помилка залишила старий стан GUI');
  CompareFiles(L,R);
  Demand(HasResult,'після відмови не відновилося');
  WriteLn('LCL-РІЗНИЦЯ-ГАРАЗД точні-слова=так два-файли=так ',
    'відмова=атомарна відновлення=так');
end;

begin
  Application.Initialize;
  Application.CreateForm(TCompareWindow,Window);
  if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then begin
    try Window.SelfTest(ParamStr(2),ParamStr(3))
    except on E:Exception do begin WriteLn(StdErr,E.Message);Halt(1) end end;
    Halt(0);
  end;
  if ParamCount=2 then begin
    try Window.CompareFiles(ParamStr(1),ParamStr(2))
    except on E:Exception do WriteLn(StdErr,E.Message) end;
  end;
  Application.Run;
end.
