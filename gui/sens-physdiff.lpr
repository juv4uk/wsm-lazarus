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
  Width:=1030; Height:=435; Position:=poScreenCenter;
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
  FGrid.ColCount:=3; FGrid.RowCount:=5; FGrid.FixedRows:=1;
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
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(18,360,975,43);
  ResetResult;
end;

procedure TDiffForm.ResetResult;
var R,K:Integer;
begin
  FillChar(FCurrent,SizeOf(FCurrent),0);
  FCurrent.Kind:=pdNotChecked;
  for R:=1 to 4 do
    for K:=1 to 2 do FGrid.Cells[K,R]:='';
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
  Need((FCurrent.Kind=pdEqual) and (FGrid.Cells[1,1]='3'),
    'невірний стан рівних свідків');
  Need(CompareFiles(A,B),'не зіставлено два свідки');
  Need((FCurrent.Kind=pdBits) and (FCurrent.WordIndex=3) and
    (FCurrent.BitIndex=3) and (FGrid.Cells[1,3]='[15,18)') and
    (FGrid.Cells[1,4]='[3,4)'), 'неправильна точна адреса біта');
  Need(CompareFiles(A,D),'не зіставлено ширину');
  Need((FCurrent.Kind=pdWidth) and (FGrid.Cells[1,2]='12') and
    (FGrid.Cells[2,2]='13'), 'втрачені точні D12+ біти');
  Need(CompareFiles(A,ShortFile),'немає EOF-зрізу');
  Need((FCurrent.Kind=pdWordCount) and
    (FGrid.Cells[2,3]='EOF'), 'не позначено EOF');
  Need(not CompareFiles(A,BadFile),'помилкові байти прийнято');
  Need((FCurrent.Kind=pdNotChecked) and (FGrid.Cells[1,1]='') and
    (FGrid.Cells[1,3]=''), 'застарілий результат після відмови');
  Need(CompareFiles(A,A) and (FCurrent.Kind=pdEqual),
    'неможливо відновити вікно після помилки');
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
