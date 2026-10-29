{ G3.29 — графічний оглядач уже ратифікованої фізичної числової площини.
  ТІЛЬКИ механізми з wsm.numericplane, жодної арифметики та D12 dispatch
  з написання. .sens — точні T5M байти; .lisp — людський десятковий токен.
  D7 — окрема текстова площина, не числове значення. }
program sens_chysla_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, SysUtils, Classes,
  wsm.numericplane, wsm.t5m;

type
  TChyslaWindow = class(TForm)
  private
    FPhysical: RawByteString;
    DomainBox: TComboBox;
    DecimalEdit: TEdit;
    EncodeButton, OpenButton: TButton;
    Details: TMemo;
    StateLabel: TLabel;
    OpenBinary: TOpenDialog;
    procedure InvalidateSnapshot;
    procedure InputChanged(Sender: TObject);
    procedure EncodeClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    function SelectedWidth: SizeInt;
    procedure ShowPhysical(const Physical: RawByteString);
    procedure LoadPhysical(const Path: String);
    procedure Check(OK: Boolean; const Why: String);
    procedure WriteFixture(const Path: String; const Data: RawByteString);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SelfTest(const TempDir: String);
  end;

var Window: TChyslaWindow;

constructor TChyslaWindow.Create(AOwner: TComponent);
var Bar: TPanel; HintLabel, NumberLabel, DomainLabel: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичні числа Д12+ (укр)';
  Width:=920; Height:=520; Position:=poScreenCenter;
  FPhysical:='';

  HintLabel:=TLabel.Create(Self); HintLabel.Parent:=Self;
  HintLabel.Align:=alTop; HintLabel.Height:=48;
  HintLabel.Caption:='Явний числовий домен Д12+; укр — лише людський десятковий запис.'+
    LineEnding+'Шість поверхонь: ук / укр / san / en / LISP / sym. Д7 — текст, не число.';

  Bar:=TPanel.Create(Self); Bar.Parent:=Self; Bar.Align:=alTop; Bar.Height:=108;
  DomainLabel:=TLabel.Create(Self); DomainLabel.Parent:=Bar;
  DomainLabel.SetBounds(12,8,160,18); DomainLabel.Caption:='Точний домен';
  DomainBox:=TComboBox.Create(Self); DomainBox.Parent:=Bar;
  DomainBox.SetBounds(12,28,126,28); DomainBox.Style:=csDropDownList;
  DomainBox.Items.Add('D12'); DomainBox.Items.Add('D24');
  DomainBox.Items.Add('D48'); DomainBox.Items.Add('D96');
  DomainBox.Items.Add('D192'); DomainBox.ItemIndex:=0;
  DomainBox.OnChange:=@InputChanged;

  NumberLabel:=TLabel.Create(Self); NumberLabel.Parent:=Bar;
  NumberLabel.SetBounds(160,8,340,18);
  NumberLabel.Caption:='Звичайна десяткова проєкція укр (.lisp)';
  DecimalEdit:=TEdit.Create(Self); DecimalEdit.Parent:=Bar;
  DecimalEdit.SetBounds(160,28,520,28);
  DecimalEdit.Text:='-2048'; DecimalEdit.OnChange:=@InputChanged;

  EncodeButton:=TButton.Create(Self); EncodeButton.Parent:=Bar;
  EncodeButton.SetBounds(12,66,255,32);
  EncodeButton.Caption:='Показати точний T5M'; EncodeButton.OnClick:=@EncodeClick;

  OpenButton:=TButton.Create(Self); OpenButton.Parent:=Bar;
  OpenButton.SetBounds(280,66,255,32);
  OpenButton.Caption:='Відкрити фізичний .sens'; OpenButton.OnClick:=@OpenClick;

  StateLabel:=TLabel.Create(Self); StateLabel.Parent:=Self;
  StateLabel.Align:=alBottom; StateLabel.Height:=29;
  StateLabel.Caption:='Результату ще немає.';

  Details:=TMemo.Create(Self); Details.Parent:=Self; Details.Align:=alClient;
  Details.ScrollBars:=ssBoth; Details.WordWrap:=False;
  Details.ReadOnly:=True;
  OpenBinary:=TOpenDialog.Create(Self);
  OpenBinary.Title:='Відкрити канонічне двійкове число SENS';
  OpenBinary.Filter:='Фізична програма SENS (*.sens)|*.sens';
  OpenBinary.Options:=OpenBinary.Options+[ofFileMustExist];
end;

{ FPhysical — власний RawByteString канонічних T5M байтів, живе лише
  до зміни вводу, домену або закриття TForm. Details — копія текстового
  host-огляду; жоден із них не є обчисленим SENS-значенням.
  Питання: 1) Чому навіть нульові префікси бітів необхідні?
  2) Чому DomWidth не можна виводити з десяткового значення?
  3) Чому відмова очищує попередні фізичні байти?
  4) Чому видимі шість поверхонь не змінюють SENS закон? }
procedure TChyslaWindow.InvalidateSnapshot;
begin
  FPhysical:='';
  Details.Clear;
  StateLabel.Caption:='Результат скинуто; потрібна нова перевірка.';
end;

procedure TChyslaWindow.InputChanged(Sender: TObject);
begin
  InvalidateSnapshot;
end;

function TChyslaWindow.SelectedWidth:SizeInt;
begin
  if DomainBox.ItemIndex<0 then
    raise ENumericPlaneError.Create('не вибрано точний числовий домен');
  Result:=SelectedNumericDomain(RawByteString(DomainBox.Text));
end;

{ Borrowed Physical -> wsm.numericplane read (explicit Width) -> owned
  TExplicitNumeric.ExactBits + перевірка зворотного T5M, без D5 виконання.
  Успішний запис FPhysical лише ПІСЛЯ всіх перевірок. }
procedure TChyslaWindow.ShowPhysical(const Physical:RawByteString);
var N:TExplicitNumeric; Dec,HexBytes:RawByteString; I:SizeInt;
begin
  N:=ReadNumericPhysical(Physical,SelectedWidth);
  Dec:=RenderNumericDecimal(N);
  if EncodeNumericDecimal(Dec,N.DomainWidth)<>Physical then
    raise ENumericPlaneError.Create('порушено побайтову оборотність T5M');
  HexBytes:='';
  for I:=1 to Length(Physical) do begin
    if I>1 then HexBytes:=HexBytes+' ';
    HexBytes:=HexBytes+RawByteString(IntToHex(Ord(Physical[I]),2));
  end;
  DecimalEdit.Text:=String(Dec);  { OnChange інвалідовує старий знімок }
  Details.Lines.Add('Домен: D'+IntToStr(N.DomainWidth));
  Details.Lines.Add('Укр, десяткове: '+String(Dec));
  Details.Lines.Add('Точні біти: '+String(N.ExactBits));
  Details.Lines.Add('Фізичний T5M, байтів: '+IntToStr(Length(Physical)));
  Details.Lines.Add('Канонічні байти (hex): '+String(HexBytes));
  Details.Lines.Add('Арифметика D5: НЕ ВИКОНУЄТЬСЯ; Core4/REPL: НЕ ВИКОНУЮТЬСЯ.');
  FPhysical:=Physical;
  StateLabel.Caption:='Канонічний T5M перевірено; домен явний, W='+IntToStr(N.DomainWidth);
end;

procedure TChyslaWindow.EncodeClick(Sender:TObject);
var Bytes:RawByteString;
begin
  InvalidateSnapshot;
  try
    Bytes:=EncodeNumericDecimal(RawByteString(DecimalEdit.Text),SelectedWidth);
    ShowPhysical(Bytes);
  except
    on E:Exception do begin
      InvalidateSnapshot;
      StateLabel.Caption:='Відмова: '+E.Message;
    end;
  end;
end;

{ Фізичний файл не парситься як UTF-8; запозичений шлях має явне
  розширення .sens. TFileStream звільняється навіть при I/O-відмові.
  Читання обмежене 64 байтами, результат стає видимим атомарно. }
procedure TChyslaWindow.LoadPhysical(const Path:String);
var F:TFileStream; Bytes:RawByteString;
begin
  InvalidateSnapshot;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ENumericPlaneError.Create('дозволено тільки фізичний файл .sens');
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>64) then
        raise ENumericPlaneError.Create('фізичний файл поза межею 1..64 байти');
      SetLength(Bytes,SizeInt(F.Size));
      F.ReadBuffer(Bytes[1],Length(Bytes));
    finally F.Free end;
    ShowPhysical(Bytes);
  except
    on E:Exception do begin
      InvalidateSnapshot;
      StateLabel.Caption:='Відмова: '+E.Message;
    end;
  end;
end;

procedure TChyslaWindow.OpenClick(Sender:TObject);
begin
  if OpenBinary.Execute then LoadPhysical(OpenBinary.FileName);
end;

procedure TChyslaWindow.Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ЛКЛ-ЧИСЛА-ПОМИЛКА: '+Why);
end;

procedure TChyslaWindow.WriteFixture(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure TChyslaWindow.SelfTest(const TempDir:String);
var D12,Path:String; RawD12:RawByteString; Words:TExactWords;
begin
  Check((DomainBox.Items.Count=5) and Details.ReadOnly,
    'немає п''яти числових доменів або доступний запис у фізичний огляд');
  DecimalEdit.Text:='-2048';
  EncodeButton.Click;
  Check((FPhysical<>'') and
    (Pos('Точні біти: 100000000000',Details.Text)>0),
    'кнопка не побудувала мінімальний D12 з точними провідними бітами');
  RawD12:=FPhysical;
  D12:=IncludeTrailingPathDelimiter(TempDir)+'мінімум.sens';
  WriteFixture(D12,RawD12);

  DecimalEdit.Text:='2047'; EncodeButton.Click;
  Check(Pos('Точні біти: 011111111111',Details.Text)>0,
    'максимум D12 втратив провідний нуль');

  DecimalEdit.Text:='2048'; EncodeButton.Click;
  Check((FPhysical='') and (Details.Text='') and
    (Pos('Відмова:',StateLabel.Caption)>0),
    'переповнення не знищило попередню відповідь');
  DecimalEdit.Text:='-2048'; EncodeButton.Click;
  Check(FPhysical=RawD12,'після переповнення не відновлено фізичні байти');

  DomainBox.ItemIndex:=1; InputChanged(nil);
  Check((FPhysical='') and (Details.Text=''),
    'зміна домену не очистила знімок');
  LoadPhysical(D12);
  Check((FPhysical='') and (Pos('Відмова:',StateLabel.Caption)>0),
    'D12 неявно допущено як D24');

  DecimalEdit.Text:='-8388608'; EncodeButton.Click;
  Check((Length(FPhysical)>0) and
    (Pos('Точні біти: 100000000000000000000000',Details.Text)>0),
    'не відтворено знаковий мінімум D24');

  DomainBox.ItemIndex:=4; InputChanged(nil);
  DecimalEdit.Text:='-3138550867693340381917894711603833208051177722232017256448';
  EncodeButton.Click;
  Check((FPhysical<>'') and
    (Pos('Домен: D192',Details.Text)>0) and
    (Pos('Точні біти: 1'+StringOfChar('0',191),Details.Text)>0),
    'не відтворено точну межу D192 без host Int64');

  DomainBox.ItemIndex:=0; InputChanged(nil);
  LoadPhysical(D12);
  Check((FPhysical=RawD12) and (DecimalEdit.Text='-2048'),
    'читання фізичного .sens втратило точні байти або проєкцію');

  Path:=IncludeTrailingPathDelimiter(TempDir)+'людський.lisp';
  WriteFixture(Path,RawByteString('-2048'));
  LoadPhysical(Path);
  Check((FPhysical='') and (Pos('Відмова:',StateLabel.Caption)>0),
    '.lisp помилково прочитано як фізичний .sens');

  Path:=IncludeTrailingPathDelimiter(TempDir)+'зіпсований.sens';
  WriteFixture(Path,#243);
  LoadPhysical(Path);
  Check(FPhysical='','неканонічний T5M не відхилено');

  Path:=IncludeTrailingPathDelimiter(TempDir)+'два-слова.sens';
  SetLength(Words,2); Words[0]:=StringOfChar('0',12);Words[1]:=StringOfChar('1',12);
  WriteFixture(Path,EncodeT5M(Words));
  LoadPhysical(Path);
  Check(FPhysical='','два слова помилково визнано одним numeric atom');

  Path:=IncludeTrailingPathDelimiter(TempDir)+'ді1.sens';
  SetLength(Words,1);Words[0]:='1';
  WriteFixture(Path,EncodeT5M(Words));
  LoadPhysical(Path);
  Check(FPhysical='','D1 помилково став D12');

  LoadPhysical(IncludeTrailingPathDelimiter(TempDir)+'відсутній.sens');
  Check(FPhysical='','відсутній файл залишив старий фізичний результат');
  LoadPhysical(D12);
  Check((FPhysical=RawD12) and
    (Pos('Канонічний T5M перевірено',StateLabel.Caption)>0),
    'не відновлено роботу після негативних фізичних файлів');

  WriteLn('ЛКЛ-ЧИСЛА-ГАРАЗД Lazarus=GTK2 кліки=5',
    ' D12-межі=так D24=так D192=так',
    ' .sens=побайтово невірний-домен=відхилено',
    ' D1=відхилено багатослівний=відхилено T5M-помилка=відхилено',
    ' .lisp-як-бінарний=відхилено відновлення=так',
    ' арифметика=НЕ_РЕАЛІЗОВАНО');
end;

begin
  Application.Initialize;
  Window:=TChyslaWindow.Create(Application);
  try
    if (ParamCount=2) and (ParamStr(1)='--самоперевірка') then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2));
    end else if ParamCount=0 then begin
      Window.Show;
      Application.Run;
    end else
      raise Exception.Create('Виклик: sens-chysla-okno [--самоперевірка тимчасова-тека]');
  finally
    Window.Free;
  end;
end.
