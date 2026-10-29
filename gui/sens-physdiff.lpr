{ Справжнє вікно Lazarus/LCL, один фізичний backend, жодної семантики. }
program sens_physdiff;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  Dialogs, Grids, wsm.t5m, wsm.t5mdiff;
type
  TDiffForm=class(TForm)
  private
    FLeft,FRight:TEdit;
    FGrid:TStringGrid;
    FBitLeft,FBitRight:TEdit;
    FStatus:TLabel;
    FPicker:TOpenDialog;
    FCurrent:TPhysicalComparison;
    procedure PickLeft(Sender:TObject);
    procedure PickRight(Sender:TObject);
    procedure CompareClick(Sender:TObject);
    procedure ResetResult;
    function ReadPhysical(const PhysicalPath:String):RawByteString;
    procedure Need(Ok:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent); override;
    function CompareFiles(const LeftFile,RightFile:String):Boolean;
    procedure SelfTest(const A,B,D,ShortFile,BadFile:String);
  end;
var Window:TDiffForm;

{ Точний UTF-8 для CI: LCL widget captions і stdout — різні шляхи. }
procedure PrintUTF8(const MessageText:UnicodeString);
const LF:AnsiChar=#10;
var Octets:UTF8String; OutputBytes:THandleStream;
begin
  Octets:=UTF8Encode(MessageText);
  OutputBytes:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(Octets)>0 then
      OutputBytes.WriteBuffer(Octets[1],Length(Octets));
    OutputBytes.WriteBuffer(LF,1);
  finally OutputBytes.Free; end;
end;


constructor TDiffForm.Create(AOwner:TComponent);
var B:TButton; L:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичні відмінності';
  Width:=1030; Height:=535; Position:=poScreenCenter;
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(18,15,850,25);
  L.Caption:='Два фізичні .sens — точні біти й адреси, не мовна семантика.';
  FLeft:=TEdit.Create(Self); FLeft.Parent:=Self;
  FLeft.SetBounds(18,50,800,30);
  B:=TButton.Create(Self); B.Parent:=Self;
  B.SetBounds(835,50,165,30); B.Caption:='Лівий .sens';
  B.OnClick:=@PickLeft;
  FRight:=TEdit.Create(Self); FRight.Parent:=Self;
  FRight.SetBounds(18,92,800,30);
  B:=TButton.Create(Self); B.Parent:=Self;
  B.SetBounds(835,92,165,30); B.Caption:='Правий .sens';
  B.OnClick:=@PickRight;
  B:=TButton.Create(Self); B.Parent:=Self;
  B.SetBounds(18,135,255,34);
  B.Caption:='Порівняти фізичні слова';
  B.OnClick:=@CompareClick;
  FPicker:=TOpenDialog.Create(Self);
  FPicker.Filter:='Фізичні свідки SENS (*.sens)|*.sens';
  FGrid:=TStringGrid.Create(Self); FGrid.Parent:=Self;
  FGrid.SetBounds(18,184,982,160);
  FGrid.ColCount:=3; FGrid.RowCount:=6; FGrid.FixedRows:=1;
  FGrid.FixedCols:=0;
  FGrid.ColWidths[0]:=240; FGrid.ColWidths[1]:=354;
  FGrid.ColWidths[2]:=354;
  FGrid.Cells[0,0]:='Координата';
  FGrid.Cells[1,0]:='Лівий свідок';
  FGrid.Cells[2,0]:='Правий свідок';
  FGrid.Cells[0,1]:='Кількість слів';
  FGrid.Cells[0,2]:='Точна ширина';
  FGrid.Cells[0,3]:='Трити [початок,кінець)';
  FGrid.Cells[0,4]:='Байти [початок,кінець)';
  FGrid.Cells[0,5]:='Перший різний біт';
  { Реальні read-only LCL поля прокручують навіть довгі exact слова;
    власник віджетів — Self. Ніякого перетворення бітів у host integer. }
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(18,357,480,24);
  L.Caption:='Ліве фізичне слово (точні біти)';
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(520,357,480,24);
  L.Caption:='Праве фізичне слово (точні біти)';
  FBitLeft:=TEdit.Create(Self); FBitLeft.Parent:=Self;
  FBitLeft.SetBounds(18,385,480,30);
  FBitLeft.ReadOnly:=True; FBitLeft.Font.Name:='Monospace';
  FBitLeft.HideSelection:=False; { видимий один точний біт без фокусу }
  FBitRight:=TEdit.Create(Self); FBitRight.Parent:=Self;
  FBitRight.SetBounds(520,385,480,30);
  FBitRight.ReadOnly:=True; FBitRight.Font.Name:='Monospace';
  FBitRight.HideSelection:=False;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(18,441,975,56);
  ResetResult;
end;

procedure TDiffForm.ResetResult;
var R,K:Integer;
begin
  { TPhysicalComparison містить managed RawByteString: FillChar втрачає
    посилання й витікає при кожній наступній перевірці. }
  FCurrent:=Default(TPhysicalComparison);
  FCurrent.Kind:=pdNotChecked;
  for R:=1 to 5 do
    for K:=1 to 2 do FGrid.Cells[K,R]:='';
  FBitLeft.Text:=''; FBitRight.Text:='';
  FBitLeft.SelStart:=0; FBitLeft.SelLength:=0;
  FBitRight.SelStart:=0; FBitRight.SelLength:=0;
  FStatus.Caption:='Порівняння не виконано.';
end;

function TDiffForm.ReadPhysical(const PhysicalPath:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(PhysicalPath))<>'.sens' then
    raise Exception.Create('потрібен двійковий .sens');
  F:=TFileStream.Create(PhysicalPath,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або завеликий .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

function TDiffForm.CompareFiles(const LeftFile,RightFile:String):Boolean;
var C:TPhysicalComparison;
begin
  Result:=False; ResetResult;
  FLeft.Text:=LeftFile; FRight.Text:=RightFile;
  try
    ComparePhysicalWords(ReadPhysical(LeftFile),ReadPhysical(RightFile),C);
    FCurrent:=C;
    { Публікуємо лише після повного admission обох фізичних файлів.
      EOF не замінюємо на D3:000; провідні нулі не губимо. }
    if C.Kind<>pdEqual then begin
      if C.LeftSpan.IsEOF then FBitLeft.Text:='EOF (слова немає)'
      else FBitLeft.Text:=String(C.LeftBits);
      if C.RightSpan.IsEOF then FBitRight.Text:='EOF (слова немає)'
      else FBitRight.Text:=String(C.RightBits);
    end;
    { Біт у TPhysicalComparison — 1-based усередині двійкового слова;
      TCustomEdit.SelStart — 0-based символ. Біти 0/1 однобайтові. }
    if (C.Kind=pdBits) and (C.BitIndex>=1) and
       (C.BitIndex<=Length(C.LeftBits)) and
       (C.BitIndex<=Length(C.RightBits)) then begin
      FBitLeft.SelStart:=C.BitIndex-1;
      FBitLeft.SelLength:=1;
      FBitRight.SelStart:=C.BitIndex-1;
      FBitRight.SelLength:=1;
      { Лише фізична адреса: T5M містить п'ять тритів на байт.
        BitIndex — 1-based, а TritStart і байт — 0-based.
        Дані походять із вже перевірених TPhysicalWordSpan, не з
        десяткової/текстової поверхні та не визначають семантику. }
      FGrid.Cells[1,5]:='трит='+
        IntToStr(C.LeftSpan.TritStart+C.BitIndex-1)+
        ' байт='+IntToStr((C.LeftSpan.TritStart+C.BitIndex-1) div 5)+
        ' позиція='+IntToStr((C.LeftSpan.TritStart+C.BitIndex-1) mod 5);
      FGrid.Cells[2,5]:='трит='+
        IntToStr(C.RightSpan.TritStart+C.BitIndex-1)+
        ' байт='+IntToStr((C.RightSpan.TritStart+C.BitIndex-1) div 5)+
        ' позиція='+IntToStr((C.RightSpan.TritStart+C.BitIndex-1) mod 5);
    end;
    FGrid.Cells[1,1]:=IntToStr(C.LeftCount);
    FGrid.Cells[2,1]:=IntToStr(C.RightCount);
    if C.Kind=pdEqual then
      FStatus.Caption:='Фізичні свідки тотожні; семантика не перевірена.'
    else begin
      FGrid.Cells[1,2]:=IntToStr(C.LeftWidth);
      FGrid.Cells[2,2]:=IntToStr(C.RightWidth);
      if C.LeftSpan.IsEOF then begin
        FGrid.Cells[1,3]:='EOF';
        FGrid.Cells[1,4]:=IntToStr(C.LeftSpan.ByteStart);
      end else begin
        FGrid.Cells[1,3]:='['+IntToStr(C.LeftSpan.TritStart)+','+
          IntToStr(C.LeftSpan.TritEnd)+')';
        FGrid.Cells[1,4]:='['+IntToStr(C.LeftSpan.ByteStart)+','+
          IntToStr(C.LeftSpan.ByteEnd)+')';
      end;
      if C.RightSpan.IsEOF then begin
        FGrid.Cells[2,3]:='EOF';
        FGrid.Cells[2,4]:=IntToStr(C.RightSpan.ByteStart);
      end else begin
        FGrid.Cells[2,3]:='['+IntToStr(C.RightSpan.TritStart)+','+
          IntToStr(C.RightSpan.TritEnd)+')';
        FGrid.Cells[2,4]:='['+IntToStr(C.RightSpan.ByteStart)+','+
          IntToStr(C.RightSpan.ByteEnd)+')';
      end;
      FStatus.Caption:='Різниця: '+DiffKindName(C.Kind)+
        ', слово '+IntToStr(C.WordIndex)+', біт '+IntToStr(C.BitIndex)+
        '. Мовна семантика не перевірена.';
    end;
    Result:=True;
  except
    on E:Exception do begin
      ResetResult;
      FStatus.Caption:='Фізичний вхід відхилено: '+E.Message;
    end;
  end;
end;

procedure TDiffForm.PickLeft(Sender:TObject);
begin
  if FPicker.Execute then begin FLeft.Text:=FPicker.FileName; ResetResult; end;
end;
procedure TDiffForm.PickRight(Sender:TObject);
begin
  if FPicker.Execute then begin FRight.Text:=FPicker.FileName; ResetResult; end;
end;
procedure TDiffForm.CompareClick(Sender:TObject);
begin CompareFiles(FLeft.Text,FRight.Text); end;
procedure TDiffForm.Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('LCL-ФІЗИЧНА-РІЗНИЦЯ: '+Why);
end;

procedure TDiffForm.SelfTest(const A,B,D,ShortFile,BadFile:String);
begin
  Need(CompareFiles(A,A),'не відкрився фізичний .sens');
  Need((FCurrent.Kind=pdEqual) and (FGrid.Cells[1,1]='3') and
    (FBitLeft.Text='') and (FBitRight.Text='') and
    FBitLeft.ReadOnly and FBitRight.ReadOnly,
    'невірний стан рівних свідків або редаговані біти');
  Need(CompareFiles(A,B),'не зіставлено два свідки');
  Need((FCurrent.Kind=pdBits) and (FCurrent.WordIndex=3) and
    (FCurrent.BitIndex=3) and (FGrid.Cells[1,3]='[15,18)') and
    (FGrid.Cells[1,4]='[3,4)') and
    (FBitLeft.Text='111') and (FBitRight.Text='110') and
    (FGrid.Cells[1,5]='трит=17 байт=3 позиція=2') and
    (FGrid.Cells[2,5]='трит=17 байт=3 позиція=2'),
    'неправильна точна адреса або бітові свідки');
  Need((FBitLeft.SelStart=2) and (FBitLeft.SelLength=1) and
    (FBitLeft.SelText='1') and
    (FBitRight.SelStart=2) and (FBitRight.SelLength=1) and
    (FBitRight.SelText='0') and
    (not FBitLeft.HideSelection) and (not FBitRight.HideSelection),
    'перший відмінний біт не виділено в справжніх TEdit');
  Need(CompareFiles(A,D),'не зіставлено ширину');
  Need((FCurrent.Kind=pdWidth) and (FGrid.Cells[1,2]='12') and
    (FGrid.Cells[2,2]='13') and
    (FBitLeft.Text='000000000001') and
    (FBitRight.Text='0000000000001') and
    (FBitLeft.SelLength=0) and (FBitRight.SelLength=0) and
    (FGrid.Cells[1,5]='') and (FGrid.Cells[2,5]=''),
    'втрачені провідні нулі D12+ або залишено стару адресу біта');
  Need(CompareFiles(A,ShortFile),'немає EOF-зрізу');
  Need((FCurrent.Kind=pdWordCount) and
    (FGrid.Cells[2,3]='EOF') and
    (FBitLeft.Text='111') and (FBitRight.Text='EOF (слова немає)') and
    (FGrid.Cells[1,5]='') and (FGrid.Cells[2,5]=''),
    'не позначено EOF або втрачено точні біти');
  Need(not CompareFiles(A,BadFile),'помилкові байти прийнято');
  Need((FCurrent.Kind=pdNotChecked) and (FGrid.Cells[1,1]='') and
    (FGrid.Cells[1,3]='') and
    (FBitLeft.Text='') and (FBitRight.Text='') and
    (FBitLeft.SelLength=0) and (FBitRight.SelLength=0) and
    (FGrid.Cells[1,5]='') and (FGrid.Cells[2,5]=''),
    'застарілий результат після відмови');
  Need(CompareFiles(A,A) and (FCurrent.Kind=pdEqual) and
    (FBitLeft.Text='') and (FBitRight.Text='') and
    (FBitLeft.SelLength=0) and (FBitRight.SelLength=0) and
    (FGrid.Cells[1,5]='') and (FGrid.Cells[2,5]=''),
    'неможливо відновити вікно після помилки');
  Need(CompareFiles(A,D) and
    (FBitLeft.Text='000000000001') and
    (FBitRight.Text='0000000000001'),
    'після відмови точні біти не відновилися');
  Need(CompareFiles(A,B) and (FBitLeft.SelText='1') and
    (FBitRight.SelText='0') and
    (FGrid.Cells[1,5]='трит=17 байт=3 позиція=2') and
    (FGrid.Cells[2,5]='трит=17 байт=3 позиція=2'),
    'після відмови не відновилося фізичне виділення й адреси бітів');
  PrintUTF8('LCL-АДРЕСА-БІТА-ГАРАЗД трит=17 байт=3 позиція=2'+
    ' обидва-свідки=так відмова=очищено');
  PrintUTF8('LCL-БІТ-ПІДСВІЧЕНО-ГАРАЗД біт=3 LCL-позиція=2'+
    ' лівий=1 правий=0 без-фокусу=так відмова=очищено');
  PrintUTF8('LCL-ДВА-ДВІЙКОВІ-СЛОВА-ГАРАЗД W12=000000000001'+
    ' W13=0000000000001 різний-біт=3 EOF=явний'+
    ' після-відмови=очищено відновлення=так');
  PrintUTF8('LCL-ФІЗИЧНА-РІЗНИЦЯ-ГАРАЗД Lazarus=GTK2'+
    ' координати=точні відмови=без-старих-даних'+
    ' семантика=НЕ-ПЕРЕВІРЕНО');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичні відмінності';
    Application.CreateForm(TDiffForm,Window);
    if (ParamCount=6) and (ParamStr(1)='--самоперевірка') then begin
      Window.Show; Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6));
      Window.Free;
    end else if ParamCount=0 then
      Application.Run
    else begin
      WriteLn(StdErr,
        'Використання: sens-physdiff [--самоперевірка 5 файлів .sens]');
      ExitCode:=64;
      Window.Free;
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ФІЗИЧНА-РІЗНИЦЯ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
