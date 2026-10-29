{ G1.24. Справжній Lazarus-віджет для вже допущеного D7 v2.
  Символи ук/укр — лише pinned людські поверхні. Дужки, цифри і
  лапки тут ТЕКСТОВІ ДАНІ D7, не D2, не виклики, не числа D12+. }
program sens_d7_laboratoriia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,Grids,Dialogs,
  wsm.d7text,wsm.t5m;

type
  TD7Window=class(TForm)
  private
    FSurface:TComboBox;
    FInput,FOutput:TEdit;
    FGrid:TStringGrid;
    FStatus:TLabel;
    FEncode,FOpen:TButton;
    FDialog:TOpenDialog;
    FMap:TD7Map;
    FPhysical:RawByteString;
    function Mode:TD7Surface;
    procedure ClearResult;
    procedure Publish(const Physical,Human:RawByteString);
    procedure EncodeClick(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    function DecodeBytes(const Physical:RawByteString):Boolean;
    function EncodedWord(const Bits:RawByteString):RawByteString;
    procedure Need(Condition:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent);override;
    function EncodeEntered:Boolean;
    function LoadPhysicalFile(const Path:String):Boolean;
    procedure SelfTest(const GoodFile,BadFile:String);
  end;

var Window:TD7Window;

constructor TD7Window.Create(AOwner:TComponent);
var L:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — лабораторія фізичного D7';
  Width:=940;Height:=620;Position:=poScreenCenter;
  { Джерело карти — ТІЛЬКИ pinned external/sens/lib/domains/d7.lisp.
    У FMap 128 керованих FPC UTF-8 рядків, власник — екземпляр вікна. }
  LoadPinnedD7Map(GetCurrentDir,FMap);
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,14,900,26);
  L.Caption:='D7: український текст як фізичні W7 слова, не програма SENS';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,51,190,24);L.Caption:='Поверхня (явний вибір):';
  FSurface:=TComboBox.Create(Self);FSurface.Parent:=Self;
  FSurface.SetBounds(214,46,95,30);
  FSurface.Style:=csDropDownList;
  FSurface.Items.Add('ук');FSurface.Items.Add('укр');
  FSurface.ItemIndex:=1;
  FInput:=TEdit.Create(Self);FInput.Parent:=Self;
  FInput.SetBounds(18,93,898,32);
  FInput.Text:='Це 0() №Їґ';
  FEncode:=TButton.Create(Self);FEncode.Parent:=Self;
  FEncode.SetBounds(18,138,280,36);
  FEncode.Caption:='Текст D7 → двійковий T5M';
  FEncode.OnClick:=@EncodeClick;
  FOpen:=TButton.Create(Self);FOpen.Parent:=Self;
  FOpen.SetBounds(320,138,280,36);
  FOpen.Caption:='Відкрити фізичний .sens…';
  FOpen.OnClick:=@OpenClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Вибрати канонічні дані D7';
  FDialog.Filter:='Фізичні SENS (*.sens)|*.sens';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,188,800,24);
  L.Caption:='Точний результат української проєкції:';
  FOutput:=TEdit.Create(Self);FOutput.Parent:=Self;
  FOutput.SetBounds(18,215,898,31);
  FOutput.ReadOnly:=True;
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(18,262,898,272);
  FGrid.FixedCols:=0;FGrid.ColCount:=3;
  FGrid.RowCount:=17;FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=85;
  FGrid.ColWidths[1]:=250;
  FGrid.ColWidths[2]:=480;
  FGrid.Cells[0,0]:='№ слова';
  FGrid.Cells[1,0]:='Точні W7-біти';
  FGrid.Cells[2,0]:='Друкована поверхня (ук/укр)';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,537,890,20);
  L.Caption:='Показано перші 16 W7; усі біти залишаються у фізичному T5M.';
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,565,898,36);
  ClearResult;
end;

function TD7Window.Mode:TD7Surface;
begin
  if FSurface.ItemIndex=0 then Result:=dsUk
  else if FSurface.ItemIndex=1 then Result:=dsUkr
  else raise ED7TextError.Create('Не вибрано поверхню D7');
end;

procedure TD7Window.ClearResult;
var I,J:Integer;
begin
  FPhysical:='';
  FOutput.Text:='';
  for I:=1 to 16 do for J:=0 to 2 do FGrid.Cells[J,I]:='';
  FStatus.Caption:='Очікується текст або фізичні дані D7.';
end;

procedure TD7Window.Publish(const Physical,Human:RawByteString);
var W:TExactWords;I,J,K,Code,Shown:SizeInt;
begin
  { Той самий T5M decoder лише для VIEW; повний D7 admission і
    байт-канонічність уже встановили EncodeD7Text/DecodeD7Text. }
  DecodeT5M(Physical,W);
  if (Length(W)=0) or (EncodeT5M(W)<>Physical) then
    raise ED7TextError.Create('Неприпустимий фізичний T5M');
  ClearResult;
  Shown:=Length(W);
  if Shown>16 then Shown:=16;
  for I:=0 to Shown-1 do begin
    if Length(W[I])<>7 then
      raise ED7TextError.Create('Очікуються лише точні W7');
    Code:=0;
    for J:=1 to 7 do begin
      if not (W[I][J] in ['0','1']) then
        raise ED7TextError.Create('Небінарна фізична координата');
      Code:=Code*2+Ord(W[I][J])-Ord('0');
    end;
    K:=I+1;
    FGrid.Cells[0,K]:=IntToStr(K);
    FGrid.Cells[1,K]:=String(W[I]);
    if Mode=dsUk then FGrid.Cells[2,K]:=String(FMap[Code].Uk)
    else FGrid.Cells[2,K]:=String(FMap[Code].Ukr);
  end;
  { Публікація повного фізичного результату після усіх перевірок.
    RawByteString — managed bytes, без ANSI/Unicode opcode колізій. }
  FPhysical:=Physical;
  FOutput.Text:=String(Human);
  FStatus.Caption:='D7-допущено: фізичних байтів='+IntToStr(Length(Physical))+
    ', точних W7 слів='+IntToStr(Length(W))+'; це дані, не виконання.';
end;

function TD7Window.EncodeEntered:Boolean;
var Human,Physical,Decoded:RawByteString;
begin
  Result:=False;ClearResult;
  try
    Human:=RawByteString(FInput.Text);
    Physical:=EncodeD7Text(Human,FMap,Mode);
    Decoded:=DecodeD7Text(Physical,FMap,Mode);
    if Decoded<>Human then
      raise ED7TextError.Create('Невдалий зворотний D7 round-trip');
    Publish(Physical,Decoded);
    Result:=True;
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено D7: '+E.Message;
  end end;
end;

function TD7Window.DecodeBytes(const Physical:RawByteString):Boolean;
var Human,RoundTrip:RawByteString;
begin
  Result:=False;ClearResult;
  try
    Human:=DecodeD7Text(Physical,FMap,Mode);
    RoundTrip:=EncodeD7Text(Human,FMap,Mode);
    if RoundTrip<>Physical then
      raise ED7TextError.Create('Фізичні байти не збіглися після D7 round-trip');
    Publish(Physical,Human);
    FInput.Text:=String(Human);
    Result:=True;
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено фізичний D7: '+E.Message;
  end end;
end;

function TD7Window.LoadPhysicalFile(const Path:String):Boolean;
const MaxViewBytes=65536;
var Stream:TFileStream;Physical:RawByteString;
begin
  Result:=False;ClearResult;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ED7TextError.Create('Тільки фізичний .sens, не текстова .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxViewBytes) then
        raise ED7TextError.Create('Порожній або завеликий фізичний D7');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    Result:=DecodeBytes(Physical);
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено файл: '+E.Message;
  end end;
end;

function TD7Window.EncodedWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;
  Result:=EncodeT5M(W);
end;

procedure TD7Window.EncodeClick(Sender:TObject);
begin EncodeEntered end;
procedure TD7Window.OpenClick(Sender:TObject);
begin if FDialog.Execute then LoadPhysicalFile(FDialog.FileName) end;

procedure TD7Window.Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('LCL-D7-ПОМИЛКА: '+Why);
end;

procedure TD7Window.SelfTest(const GoodFile,BadFile:String);
const Sample='Це 0() №Їґ';
var Original:TExactWords; Physical,Example:RawByteString;
begin
  Need((FSurface<>nil) and (FInput<>nil) and (FOutput<>nil) and
    (FGrid<>nil) and FOutput.ReadOnly and
    Assigned(FEncode.OnClick) and Assigned(FOpen.OnClick),
    'немає реальних LCL контролів');
  FSurface.ItemIndex:=1;
  FInput.Text:=Sample;
  Need(EncodeEntered,'не закодовано український D7 текст');
  Physical:=FPhysical;
  Need((FOutput.Text=Sample) and (Length(Physical)>0),
    'після кодування втрачено українську проєкцію');
  DecodeT5M(Physical,Original);
  Need((Length(Original)>=6) and (Original[2]='0100000') and
    (Original[3]='0110000') and (Original[4]='0101000') and
    (Original[5]='0101001'), 'D7 пробіл/нуль/дужки стали D2 чи числами');
  Need((FGrid.Cells[1,3]='0100000') and
    (FGrid.Cells[2,5]='('), 'справжня W7 таблиця не показала точні біти');

  Need(LoadPhysicalFile(GoodFile),'не прочитано фізичний .sens');
  Need((FPhysical=Physical) and (FInput.Text=Sample) and
    (FOutput.Text=Sample),'CLI та Lazarus D7 фізично різні');

  { Окрема «ук» поверхня, а не неявний псевдонім укр. }
  FSurface.ItemIndex:=0;
  FInput.Text:=String(FMap[65].Uk+FMap[32].Uk+FMap[40].Uk);
  Need(EncodeEntered,'поверхня ук не закодована');
  DecodeT5M(FPhysical,Original);
  Need((Length(Original)=3) and
    (Original[0]='1000001') and (Original[1]='0100000') and
    (Original[2]='0101000'),'ук втратила точні 7-бітні координати');

  FSurface.ItemIndex:=1;
  FInput.Text:='i';
  Need(not EncodeEntered,'латинська i прийнята за українську і');
  Need((FPhysical='') and (FOutput.Text='') and
    (FGrid.Cells[1,1]=''),'після помилки лишився фізичний результат');
  FInput.Text:='«';
  Need(not EncodeEntered,'вигадано координату відсутнього glyph');
  Need(not DecodeBytes(EncodedWord('0010110')),
    'SYN D7:0010110 помилково перетворено на текст');
  Need(not DecodeBytes(EncodedWord('0')),'W1 прийняте за W7');
  Need(not DecodeBytes(EncodedWord('000000000000')),
    'W12 без домену прийнято за D7 або D12');
  Need(not DecodeBytes(#$F3),'неканонічний T5M байт прийнято');
  Need(not LoadPhysicalFile(BadFile),'пошкоджений файл прийнято');
  Need((FPhysical='') and (FOutput.Text='') and
    (FGrid.Cells[1,1]=''),'пізня фізична відмова лишила старі дані');
  Need(not LoadPhysicalFile('немає-файла.sens'),
    'відсутній фізичний файл прийнято');
  Need(not LoadPhysicalFile('проєкція.lisp'),
    'текстову .lisp прийнято за фізичні дані');
  FInput.Text:=Sample;
  Need(EncodeEntered and (FPhysical=Physical),
    'відновлення після негативів неканонічне');
  Example:=DecodeD7Text(FPhysical,FMap,dsUkr);
  Need(Example=Sample,'зворотне читання не відповідає pinned D7');
  Window.Show;Application.ProcessMessages;
  WriteLn('LCL-Д7-ЛАБОРАТОРІЯ-ГАРАЗД Lazarus=GTK2 W7=точні',
    ' ук/укр=окремо дужки=D7-дані SYN=відхилено',
    ' W1/W12=відхилено UTF8=строго .sens=канонічний',
    ' CLI-побайтово=так відновлення=так семантика=не-виконується');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — лабораторія D7';
    Application.CreateForm(TD7Window,Window);
    if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then begin
      Window.SelfTest(ParamStr(2),ParamStr(3));
      Window.Free;
    end else if ParamCount=0 then Application.Run
    else begin
      WriteLn(StdErr,'Використання: sens-d7-laboratoriia [--самоперевірка дані.sens брак.sens]');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-Д7-ПОМИЛКА: ',E.Message);Halt(2)
  end end;
end.
