{ G3.29: справжній Lazarus/LCL оглядач точних числових D12+.
  Вхід — лише людська десяткова проєкція або канонічний фізичний T5M.
  Мовна влада належить pinned SENS; арифметики та реєстру законів немає.
  Жодного записування .sens з GUI: тільки перевірений read-only snapshot. }
program sens_chysla_d12;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs,
  wsm.t5m, wsm.numericplane;

type
  TNumericWindow = class(TForm)
  private
    FDomain: TComboBox;
    FDecimal: TEdit;
    FEncode: TButton;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FResult: TMemo;
    FStatus: TLabel;
    FPhysical: RawByteString; { власна перевірена фізична копія }
    FTestPath: String;       { лише host шлях для GUI самоперевірки }
    procedure ClearSnapshot;
    procedure DomainChanged(Sender: TObject);
    procedure DecimalChanged(Sender: TObject);
    procedure EncodeClicked(Sender: TObject);
    procedure OpenClicked(Sender: TObject);
    procedure Publish(const Bytes: RawByteString;
      const Number: TExplicitNumeric);
    function ExplicitWidth: SizeInt;
    procedure Demand(Ok: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function ReadPhysicalFile(const Path: String): Boolean;
    procedure SelfCheck(const Good12, Good192, Corrupt, TextFile: String);
  end;

var Window: TNumericWindow;

constructor TNumericWindow.Create(AOwner: TComponent);
const Domains: array[0..4] of String=('D12','D24','D48','D96','D192');
var I: Integer; CaptionLabel: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — точні числові домени D12–D192';
  Position:=poScreenCenter;
  Width:=980; Height:=630;

  CaptionLabel:=TLabel.Create(Self);
  CaptionLabel.Parent:=Self;
  CaptionLabel.SetBounds(16,16,930,26);
  CaptionLabel.Caption:='Числовий домен обирається явно. Десятковий запис — українська людська проєкція.';
  FDomain:=TComboBox.Create(Self);
  FDomain.Parent:=Self;
  FDomain.SetBounds(16,52,148,32);
  FDomain.Style:=csDropDownList;
  for I:=0 to High(Domains) do FDomain.Items.Add(Domains[I]);
  FDomain.ItemIndex:=0;
  FDomain.OnChange:=@DomainChanged;

  FDecimal:=TEdit.Create(Self);
  FDecimal.Parent:=Self;
  FDecimal.SetBounds(172,52,770,32);
  FDecimal.Text:='-2048';
  FDecimal.OnChange:=@DecimalChanged;

  FEncode:=TButton.Create(Self);
  FEncode.Parent:=Self;
  FEncode.SetBounds(16,104,440,42);
  FEncode.Caption:='Перевірити десятковий запис → двійковий .sens';
  FEncode.OnClick:=@EncodeClicked;
  FOpen:=TButton.Create(Self);
  FOpen.Parent:=Self;
  FOpen.SetBounds(470,104,470,42);
  FOpen.Caption:='Відкрити фізичний .sens (явний домен)';
  FOpen.OnClick:=@OpenClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Виберіть канонічний двійковий файл SENS';
  FDialog.Filter:='SENS фізичний (*.sens)|*.sens';

  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=Self;
  FStatus.SetBounds(16,155,930,38);
  FStatus.Caption:='Введіть звичайне десяткове число або відкрийте .sens.';
  FResult:=TMemo.Create(Self);
  FResult.Parent:=Self;
  FResult.SetBounds(16,201,926,365);
  FResult.ReadOnly:=True;
  FResult.WordWrap:=False;
  FResult.ScrollBars:=ssBoth;
  FTestPath:='';
  FPhysical:='';
end;

{ Усі результати стають недійсними до першого кроку нового вводу.
  Host Boolean повертає лише успіх дії, не має стосунку до SENS D1. }
procedure TNumericWindow.ClearSnapshot;
begin
  FPhysical:='';
  FResult.Clear;
  FStatus.Caption:='Немає перевіреного фізичного результату.';
end;

procedure TNumericWindow.DomainChanged(Sender:TObject);
begin
  ClearSnapshot;
end;

procedure TNumericWindow.DecimalChanged(Sender:TObject);
begin
  ClearSnapshot;
end;

function TNumericWindow.ExplicitWidth:SizeInt;
begin
  if (FDomain.ItemIndex<0) or
     (FDomain.ItemIndex>=FDomain.Items.Count) then
    raise ENumericPlaneError.Create('виберіть числовий домен');
  Result:=SelectedNumericDomain(RawByteString(FDomain.Items[FDomain.ItemIndex]));
end;

{ Bytes: канонічний T5M, Number: уже перевірений точний явний домен.
  RawByteString має власне FPC ref-counted життя, жодних native pointers.
  Коміт віджетів відбувається лише ПІСЛЯ всього byte/width/round-trip guard. }
procedure TNumericWindow.Publish(const Bytes: RawByteString;
  const Number:TExplicitNumeric);
var TextNumber:RawByteString;
begin
  if Length(Number.ExactBits)<>Number.DomainWidth then
    raise ENumericPlaneError.Create('втрачено точну ширину числа');
  TextNumber:=RenderNumericDecimal(Number);
  if EncodeNumericDecimal(TextNumber, Number.DomainWidth)<>Bytes then
    raise ENumericPlaneError.Create('не зійшлися фізичні байти T5M');
  FPhysical:=Bytes;
  FResult.Lines.Add('Явний домен: D'+IntToStr(Number.DomainWidth));
  FResult.Lines.Add('Точні двійкові біти ('+
    IntToStr(Length(Number.ExactBits))+'): '+String(Number.ExactBits));
  FResult.Lines.Add('Українська десяткова проєкція: '+String(TextNumber));
  FResult.Lines.Add('Канонічний .sens: '+IntToStr(Length(Bytes))+
    ' фізичних байтів T5M (лише перегляд, без запису).');
  FResult.Lines.Add('D1:0, D3:000, D7 та викличність не визначають число.');
  FStatus.Caption:='Фізичний T5M та точна числова проєкція перевірені.';
end;

procedure TNumericWindow.EncodeClicked(Sender:TObject);
var SelectedWidth:SizeInt; Physical:RawByteString; Num:TExplicitNumeric;
begin
  ClearSnapshot;
  try
    SelectedWidth:=ExplicitWidth;
    Physical:=EncodeNumericDecimal(RawByteString(FDecimal.Text),SelectedWidth);
    Num:=ReadNumericPhysical(Physical,SelectedWidth);
    if RenderNumericDecimal(Num)<>RawByteString(FDecimal.Text) then
      raise ENumericPlaneError.Create('необоротна десяткова проєкція');
    Publish(Physical,Num);
  except
    on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

{ Path — лише host шлях, ніколи не є SENS програмою або мовним законом.
  Stream звільняється в finally; понад 64 байти відхиляються ДО читання.
  Помилка не залишає старий snapshot, новий — не публікується частково. }
function TNumericWindow.ReadPhysicalFile(const Path:String):Boolean;
var Stream:TFileStream; Bytes:RawByteString; Number:TExplicitNumeric;
begin
  Result:=False;
  ClearSnapshot;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ENumericPlaneError.Create('очікується двійковий .sens, не .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<=0) or (Stream.Size>64) then
        raise ENumericPlaneError.Create('некоректна довжина фізичного числа');
      SetLength(Bytes,SizeInt(Stream.Size));
      Stream.ReadBuffer(Bytes[1],Length(Bytes));
    finally Stream.Free;end;
    Number:=ReadNumericPhysical(Bytes,ExplicitWidth);
    Publish(Bytes,Number);
    Result:=True;
  except
    on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

procedure TNumericWindow.OpenClicked(Sender:TObject);
begin
  if FTestPath<>'' then ReadPhysicalFile(FTestPath)
  else if FDialog.Execute then ReadPhysicalFile(FDialog.FileName);
end;

procedure TNumericWindow.Demand(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('LCL-ЧИСЛО-ТЕСТ: '+Why);
end;

{ Тести натискають РЕАЛЬНІ LCL кнопки та виконують справжній numericplane.
  Два файли Good містять незалежно створений FPC CLI канонічний T5M. }
procedure TNumericWindow.SelfCheck(
  const Good12, Good192, Corrupt, TextFile:String);
const
  LargeMin='-3138550867693340381917894711603833208051177722232017256448';
var I:Integer;
begin
  FDomain.ItemIndex:=0;
  FDecimal.Text:='-2048'; FEncode.Click;
  Demand((Pos('D12',FResult.Text)>0) and
    (Pos('100000000000',FResult.Text)>0) and
    (FPhysical<>''),'D12 мінімум не породив точний T5M');
  FDecimal.Text:='2047'; FEncode.Click;
  Demand(Pos('011111111111',FResult.Text)>0,
    'D12 максимум утратив старший нуль');
  for I:=0 to 4 do begin
    FDomain.ItemIndex:=I;
    FDecimal.Text:='-1'; FEncode.Click;
    Demand((FPhysical<>'') and
      (Pos(StringOfChar('1',SelectedNumericDomain(
        RawByteString(FDomain.Items[I]))),FResult.Text)>0),
      'не пройшла точна знакова ширина D12/D24/D48/D96/D192');
  end;

  FDomain.ItemIndex:=0;
  FDecimal.Text:='2048'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'переповнення D12 залишило попередній snapshot');
  FDecimal.Text:='-0'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'неканонічний мінус-нуль прийнято');
  FDecimal.Text:='00'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'неканонічні початкові нулі прийнято');
  FDecimal.Text:='1.5'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'дробовий літерал без окремого закону прийнято');

  FTestPath:=Good12; FOpen.Click;
  Demand((FPhysical<>'') and (Pos('100000000000',FResult.Text)>0),
    'реальний фізичний D12 не прочитано');
  FDomain.ItemIndex:=1; FTestPath:=Good12; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'неявне розширення D12→D24 допущено');

  FDomain.ItemIndex:=4; FTestPath:=Good192; FOpen.Click;
  Demand((FPhysical<>'') and (Pos(LargeMin,FResult.Text)>0) and
    (Pos('Точні двійкові біти (192):',FResult.Text)>0),
    'втрачено фізичну D192 мінімальну межу');

  FTestPath:=Corrupt; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'пошкоджений T5M залишив старі дані');
  FTestPath:=TextFile; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'текстова .lisp підмінила фізичний .sens');
  FTestPath:=Good192; FOpen.Click;
  Demand((FPhysical<>'') and (Pos(LargeMin,FResult.Text)>0),
    'не відновлено читання після негативів');
  WriteLn('LCL-ЧИСЛА-D12-ГАРАЗД Lazarus=GTK2 FPC=реальний ',
    'D12-D192=точні T5M=канонічний укр=проєкція ',
    'переповнення=відхилено W12->W24=неявно-заборонено ',
    'очищення=атомарне арифметика=НЕ-ДОВЕДЕНА');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — точні числа D12–D192';
    Application.CreateForm(TNumericWindow,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>5 then Halt(64);
      Window.Show; Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>0 then Halt(64);
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ЧИСЛА-D12-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
