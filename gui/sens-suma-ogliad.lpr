{ G3.43 — реальне GTK2/LCL виконання фізичного додавання D12+.
  Мовний закон тільки в pinned SENS; реальне виконання у wsm.numericadd.
  Людська таблиця є проєкцією, ніколи не семантичним dispatch. }
program sens_suma_ogliad;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids, Dialogs,
     wsm.t5m, wsm.numericplane, wsm.numericadd;
const
  MaxPhysicalBytes=65536;
type
  TSumWindow=class(TForm)
  private
    FDomain:TComboBox;
    FLeftPath,FRightPath:TEdit;
    FLeftChoose,FRightChoose,FRun:TButton;
    FPicker:TOpenDialog;
    FGrid:TStringGrid;
    FDetails:TMemo;
    FStatus:TLabel;
    FResultPhysical:RawByteString;
    FResultWidth:SizeInt;
    procedure ClearAnswer;
    procedure Changed(Sender:TObject);
    procedure Choose(Sender:TObject);
    procedure RunClicked(Sender:TObject);
    function ReadPhysical(const Path:String):RawByteString;
    procedure Need(Ok:Boolean;const Why:String);
    procedure SetInputs(const Left,Right:String; DomainIndex:Integer);
    procedure ExpectSum(const Decimal:String; ExpectedWidth:SizeInt);
    procedure ExpectReject(const Why:String);
  public
    constructor Create(AOwner:TComponent);override;
    function Calculate:Boolean;
    procedure SelfTest(const P7,PN7,PMax12,P1,PMin24,PN1_24,
      P1_48,P2_48,P1_96,P2_96,P1_192,P2_192,PMax192,
      PBad,PProjection,PMissing:String);
  end;
var Window:TSumWindow;

{ Для LCL-віджета доступні тільки вже перевірені власні байти фізичної
  відповіді. ClearAnswer знищує stale snapshot ДО читання наступного.
  Питання: чи залишиться попередня сума після пошкодженого файла?
  Чому статус помилки не є D1-хибою? }
procedure TSumWindow.ClearAnswer;
var I:Integer;
begin
  FResultPhysical:='';
  FResultWidth:=0;
  FGrid.RowCount:=4;
  for I:=1 to 3 do begin
    FGrid.Cells[1,I]:='';
    FGrid.Cells[2,I]:='';
    FGrid.Cells[3,I]:='';
  end;
  FDetails.Clear;
  FStatus.Caption:='Немає обчисленої фізичної відповіді';
end;
procedure TSumWindow.Changed(Sender:TObject);
begin ClearAnswer end;
procedure TSumWindow.Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('LCL-СУМА-ТЕСТ: '+Why) end;
constructor TSumWindow.Create(AOwner:TComponent);
var L:TLabel;I:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — точне фізичне додавання D12+';
  Width:=1100;Height:=700;Position:=poScreenCenter;

  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,17,165,22);
  L.Caption:='Явний числовий домен:';
  FDomain:=TComboBox.Create(Self);FDomain.Parent:=Self;
  FDomain.SetBounds(185,12,130,28);FDomain.Style:=csDropDownList;
  for I:=0 to 4 do
    case I of
      0:FDomain.Items.Add('D12');
      1:FDomain.Items.Add('D24');
      2:FDomain.Items.Add('D48');
      3:FDomain.Items.Add('D96');
      4:FDomain.Items.Add('D192');
    end;
  FDomain.ItemIndex:=0;FDomain.OnChange:=@Changed;

  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,53,155,24);
  L.Caption:='Лівий фізичний .sens:';
  FLeftPath:=TEdit.Create(Self);FLeftPath.Parent:=Self;
  FLeftPath.SetBounds(175,50,730,28);FLeftPath.OnChange:=@Changed;
  FLeftChoose:=TButton.Create(Self);FLeftChoose.Parent:=Self;
  FLeftChoose.SetBounds(920,50,160,28);
  FLeftChoose.Caption:='Вибрати лівий';FLeftChoose.Tag:=1;
  FLeftChoose.OnClick:=@Choose;

  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,91,155,24);
  L.Caption:='Правий фізичний .sens:';
  FRightPath:=TEdit.Create(Self);FRightPath.Parent:=Self;
  FRightPath.SetBounds(175,88,730,28);FRightPath.OnChange:=@Changed;
  FRightChoose:=TButton.Create(Self);FRightChoose.Parent:=Self;
  FRightChoose.SetBounds(920,88,160,28);
  FRightChoose.Caption:='Вибрати правий';FRightChoose.Tag:=2;
  FRightChoose.OnClick:=@Choose;

  FPicker:=TOpenDialog.Create(Self);
  FPicker.Filter:='Фізичний SENS (*.sens)|*.sens';
  FRun:=TButton.Create(Self);FRun.Parent:=Self;FRun.SetBounds(12,132,220,38);
  FRun.Caption:='Додати фізичні числа';FRun.OnClick:=@RunClicked;

  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(250,138,825,60);
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(12,190,1065,215);
  FGrid.ColCount:=4;FGrid.RowCount:=4;FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=155;FGrid.ColWidths[1]:=155;
  FGrid.ColWidths[2]:=175;FGrid.ColWidths[3]:=550;
  FGrid.Cells[0,0]:='Фізичний учасник';
  FGrid.Cells[1,0]:='Явний домен';
  FGrid.Cells[2,0]:='укр: число';
  FGrid.Cells[3,0]:='Точне двійкове слово';
  FGrid.Cells[0,1]:='Лівий доданок';
  FGrid.Cells[0,2]:='Правий доданок';
  FGrid.Cells[0,3]:='Обчислена сума';

  FDetails:=TMemo.Create(Self);FDetails.Parent:=Self;
  FDetails.SetBounds(12,418,1065,205);FDetails.ReadOnly:=True;
  ClearAnswer;
end;
procedure TSumWindow.Choose(Sender:TObject);
begin
  if FPicker.Execute then
    if (Sender as TButton).Tag=1 then FLeftPath.Text:=FPicker.FileName
    else FRightPath.Text:=FPicker.FileName;
end;
function TSumWindow.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if (Path='') or (ExtractFileExt(Path)<>'.sens') then
    raise Exception.Create('потрібен явно вибраний фізичний файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysicalBytes) then
      raise Exception.Create('порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Вхід: два запозичені file path, явний Dn із ComboBox.
  Значення RawByteString — власні packed T5M-байти, без .lisp декодування.
  Вихід після успіху: незмінні canonical T5M байти з wsm.numericadd.
  ReadNumericPhysical лише РЕНДЕРИТЬ вже обчислену суму, не визначає
  ні закон, ні викличність. Помилка → нуль опублікованих байтів.
  Питання: де саме відбувається арифметика? Хто обрав вхідний Dn?
  Чому signed widening перевіряємо через повернену ширину?
  Як уникнути stale result, якщо правий файл пошкоджено? }
function TSumWindow.Calculate:Boolean;
var L,R,Answer:RawByteString;
    LN,RN,AN:TExplicitNumeric;
    W,OutputW:SizeInt;
    AnswerWords:TExactWords;
begin
  Result:=False;
  ClearAnswer;
  try
    W:=SelectedNumericDomain(RawByteString(FDomain.Text));
    L:=ReadPhysical(FLeftPath.Text);
    R:=ReadPhysical(FRightPath.Text);
    LN:=ReadNumericPhysical(L,W);
    RN:=ReadNumericPhysical(R,W);
    Answer:=AddNumericPhysical(L,R,W); { ЄДИНА точка додавання }
    DecodeT5M(Answer,AnswerWords);
    if Length(AnswerWords)<>1 then
      raise Exception.Create('суму не надано одним фізичним атомом');
    OutputW:=Length(AnswerWords[0]);
    if (OutputW<>W) and
       not ((W<192) and (OutputW=W*2)) then
      raise Exception.Create('неочікуваний домен фізичного результату');
    AN:=ReadNumericPhysical(Answer,OutputW);
    FGrid.Cells[1,1]:='D'+IntToStr(LN.DomainWidth);
    FGrid.Cells[1,2]:='D'+IntToStr(RN.DomainWidth);
    FGrid.Cells[1,3]:='D'+IntToStr(AN.DomainWidth);
    FGrid.Cells[2,1]:=String(RenderNumericDecimal(LN));
    FGrid.Cells[2,2]:=String(RenderNumericDecimal(RN));
    FGrid.Cells[2,3]:=String(RenderNumericDecimal(AN));
    FGrid.Cells[3,1]:=String(LN.ExactBits);
    FGrid.Cells[3,2]:=String(RN.ExactBits);
    FGrid.Cells[3,3]:=String(AN.ExactBits);
    FResultPhysical:=Answer;
    FResultWidth:=OutputW;
    FDetails.Lines.Add('Фізична сума отримана через wsm.numericadd.');
    FDetails.Lines.Add('Вхід: два канонічні одноатомні пакети T5M.');
    FDetails.Lines.Add('Вихід: канонічний пакет T5M, байтів: '+
      IntToStr(Length(FResultPhysical)));
    FDetails.Lines.Add('Вхідний домен D'+IntToStr(W)+
      '; фактичний домен результату D'+IntToStr(OutputW));
    FDetails.Lines.Add('укр: лише десяткова проєкція, а не джерело законів.');
    FDetails.Lines.Add('Поверхні D7 не виконуються і не є dispatch.');
    FStatus.Caption:='ВИКОНАНО: точне додавання D'+IntToStr(W)+
      ' → D'+IntToStr(OutputW);
    Result:=True;
  except on E:Exception do begin
    ClearAnswer;
    FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
  end end;
end;
procedure TSumWindow.RunClicked(Sender:TObject);
begin Calculate end;
procedure TSumWindow.SetInputs(const Left,Right:String;DomainIndex:Integer);
begin
  FDomain.ItemIndex:=DomainIndex;
  FDomain.OnChange(FDomain);
  FLeftPath.Text:=Left;
  FRightPath.Text:=Right;
end;
procedure TSumWindow.ExpectSum(const Decimal:String;ExpectedWidth:SizeInt);
var N:TExplicitNumeric;Expected:RawByteString;
begin
  FRun.Click; { обов'язково дійсна подія LCL-кнопки }
  Need((FResultPhysical<>'') and (FResultWidth=ExpectedWidth),
    'немає очікуваного фізичного результату');
  Expected:=EncodeNumericDecimal(RawByteString(Decimal),ExpectedWidth);
  Need(FResultPhysical=Expected,'не збіглися канонічні байти відповіді');
  N:=ReadNumericPhysical(FResultPhysical,ExpectedWidth);
  Need(FGrid.Cells[2,3]=Decimal,'невірна українська десяткова проєкція');
  Need(FGrid.Cells[3,3]=String(N.ExactBits),'втрачено точні двійкові біти');
  Need(FGrid.Cells[1,3]='D'+IntToStr(ExpectedWidth),
    'неправильний точний домен відповіді');
end;
procedure TSumWindow.ExpectReject(const Why:String);
begin
  FRun.Click;
  Need((FResultPhysical='') and (FResultWidth=0) and
       (FGrid.Cells[3,3]='') and (FDetails.Text='') and
       (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),Why);
end;
procedure TSumWindow.SelfTest(const P7,PN7,PMax12,P1,PMin24,PN1_24,
  P1_48,P2_48,P1_96,P2_96,P1_192,P2_192,PMax192,
  PBad,PProjection,PMissing:String);
begin
  SetInputs(P7,PN7,0);ExpectSum('0',12);
  SetInputs(PMax12,P1,0);ExpectSum('2048',24);
  SetInputs(PMin24,PN1_24,1);ExpectSum('-8388609',48);
  SetInputs(P1_48,P2_48,2);ExpectSum('3',48);
  SetInputs(P1_96,P2_96,3);ExpectSum('3',96);
  SetInputs(P1_192,P2_192,4);ExpectSum('3',192);
  SetInputs(PMax192,P1_192,4);
  { P1_192 = одиниця D192; sum позитивний overflow → відмова. }
  ExpectReject('потрібно відхилити переповнення D192');
  SetInputs(P7,PMin24,0);ExpectReject('змішано D12 з D24');
  SetInputs(P7,PBad,0);ExpectReject('пошкоджений T5M прийнятий');
  SetInputs(PProjection,P1,0);ExpectReject('.lisp підмінено під .sens');
  SetInputs(PMissing,P1,0);ExpectReject('відсутній фізичний файл');
  SetInputs(P7,PN7,0);ExpectSum('0',12);
  FRightPath.Text:=PBad;
  Need((FResultPhysical='') and (FDetails.Text=''),
    'зміна шляху залишила stale фізичну суму');
  SetInputs(PMax12,P1,0);ExpectSum('2048',24);
  WriteLn('LCL-СУМА-ГАРАЗД GTK2=так TButton.Click=так',
    ' D12-D192=усі widening=перевірено fail-close=так',
    ' output=T5M-byte-exact runtime=wsm.numericadd');
end;
begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичне додавання D12+';
    Application.CreateForm(TSumWindow,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>17 then Halt(64);
      Window.Show;Application.ProcessMessages;
      Window.SelfTest(
        ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),
        ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10),ParamStr(11),ParamStr(12),ParamStr(13),
        ParamStr(14),ParamStr(15),ParamStr(16),ParamStr(17));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>0 then Halt(64);
    Application.Run;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-СУМА-ПОМИЛКА: ',E.Message);
    Halt(2);
  end end;
end.
