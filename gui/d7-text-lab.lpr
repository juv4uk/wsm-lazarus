{ G1.24. Візуальне D7 text-data ↔ T5M, НЕ інтерпретатор SENS.
  Єдина карта: pinned external/sens/lib/domains/d7.lisp через wsm.d7text.
  Другий раніше злитий кодек wsm.d7tekst — тільки незалежний parity-test;
  третього Unicode→D7 кодування тут НЕМАЄ. }
program d7_text_lab;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Dialogs, Grids, wsm.d7text, wsm.d7tekst, wsm.t5m, wsm.physloc;

const
  MaxShownD7 = 4096;
type
  TD7Laboratory = class(TForm)
  private
    TextField: TEdit;
    SurfaceChoice: TComboBox;
    EncodeButton, ImportButton, DecodeButton: TButton;
    WordGrid: TStringGrid;
    Status, Explanation: TLabel;
    OpenDialog: TOpenDialog;
    Map: TD7Map;
    Physical: RawByteString;
    procedure ClearWitness;
    procedure Failed(const Why: String);
    procedure EncodeClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure DecodeClick(Sender: TObject);
    procedure SurfaceChanged(Sender: TObject);
    function Surface: TD7Surface;
    function ReadPhysicalFile(const FileName: String): RawByteString;
    procedure ShowPhysical(const Candidate: RawByteString);
    procedure LoadPhysical(const FileName: String);
    procedure ValidateSecondExistingCodec;
    procedure SelfTest(const GoodFile, SynFile, MixedFile, BadFile:String);
  public
    constructor Create(AOwner:TComponent); override;
  end;

var
  Laboratory: TD7Laboratory;

function HalfOpen(A,B:SizeInt):String;
begin
  Result:='['+IntToStr(A)+','+IntToStr(B)+')';
end;

constructor TD7Laboratory.Create(AOwner:TComponent);
var Top, Bottom: TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — лабораторія українських проєкцій Д7';
  Width:=1260; Height:=650; Position:=poScreenCenter;
  Physical:='';
  { Під час створення інтерфейсу СПЕРШУ вся pinned таблиця.
    Жодного локального fallback на Unicode/ASCII або D2. }
  LoadPinnedD7Map('.',Map);

  Top:=TPanel.Create(Self);
  Top.Parent:=Self; Top.Align:=alTop; Top.Height:=98; Top.BevelOuter:=bvNone;
  TextField:=TEdit.Create(Self);
  TextField.Parent:=Top; TextField.SetBounds(12,9,820,32);
  TextField.Text:='Це 0() №Їґ';
  SurfaceChoice:=TComboBox.Create(Self);
  SurfaceChoice.Parent:=Top;
  SurfaceChoice.SetBounds(842,9,120,32);
  SurfaceChoice.Style:=csDropDownList;
  SurfaceChoice.Items.Add('ук');
  SurfaceChoice.Items.Add('укр');
  SurfaceChoice.ItemIndex:=1;
  SurfaceChoice.OnChange:=@SurfaceChanged;
  EncodeButton:=TButton.Create(Self);
  EncodeButton.Parent:=Top;
  EncodeButton.SetBounds(12,50,246,34);
  EncodeButton.Caption:='Кодувати український Д7';
  EncodeButton.OnClick:=@EncodeClick;
  ImportButton:=TButton.Create(Self);
  ImportButton.Parent:=Top;
  ImportButton.SetBounds(270,50,246,34);
  ImportButton.Caption:='Відкрити фізичний .sens…';
  ImportButton.OnClick:=@ImportClick;
  DecodeButton:=TButton.Create(Self);
  DecodeButton.Parent:=Top;
  DecodeButton.SetBounds(528,50,304,34);
  DecodeButton.Caption:='Декодувати точний Д7';
  DecodeButton.OnClick:=@DecodeClick;
  DecodeButton.Enabled:=False;
  OpenDialog:=TOpenDialog.Create(Self);
  OpenDialog.Title:='Відкрити тільки фізичні D7 текстові дані';
  OpenDialog.Filter:='Фізичний T5M (*.sens)|*.sens';

  Bottom:=TPanel.Create(Self);
  Bottom.Parent:=Self; Bottom.Align:=alBottom; Bottom.Height:=86;
  Bottom.BevelOuter:=bvNone;
  Status:=TLabel.Create(Self); Status.Parent:=Bottom;
  Status.SetBounds(12,6,1210,30);
  Status.Caption:='Д7: лише текстові дані; не D1, D2, D12+ і не виклики';
  Explanation:=TLabel.Create(Self); Explanation.Parent:=Bottom;
  Explanation.SetBounds(12,39,1210,30);
  Explanation.Caption:='Точні семибітні слова і адреси фізичного T5M; проєкції ук/укр з pinned SENS';

  WordGrid:=TStringGrid.Create(Self);
  WordGrid.Parent:=Self; WordGrid.Align:=alClient;
  WordGrid.ColCount:=6; WordGrid.FixedCols:=0;
  WordGrid.FixedRows:=1; WordGrid.RowCount:=2;
  WordGrid.ColWidths[0]:=80;
  WordGrid.ColWidths[1]:=130;
  WordGrid.ColWidths[2]:=140;
  WordGrid.ColWidths[3]:=140;
  WordGrid.ColWidths[4]:=250;
  WordGrid.ColWidths[5]:=220;
  WordGrid.Cells[0,0]:='Слово';
  WordGrid.Cells[1,0]:='Д7: 7 біт';
  WordGrid.Cells[2,0]:='ук';
  WordGrid.Cells[3,0]:='укр';
  WordGrid.Cells[4,0]:='Трити [початок, кінець)';
  WordGrid.Cells[5,0]:='Байти [початок, кінець)';
  WordGrid.Options:=WordGrid.Options+[goRowSelect];
  ClearWitness;
end;

procedure TD7Laboratory.ClearWitness;
var Col:SizeInt;
begin
  Physical:='';
  DecodeButton.Enabled:=False;
  WordGrid.RowCount:=2;
  for Col:=0 to 5 do WordGrid.Cells[Col,1]:='';
end;

procedure TD7Laboratory.Failed(const Why:String);
begin
  ClearWitness;
  Status.Caption:='Д7-ВІДМОВА: '+Why;
  Explanation.Caption:='Жодного часткового фізичного результату чи адреси не оприлюднено';
end;

function TD7Laboratory.Surface:TD7Surface;
begin
  if SurfaceChoice.ItemIndex=0 then Result:=dsUk
  else Result:=dsUkr;
end;

function TD7Laboratory.ReadPhysicalFile(const FileName:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(FileName))<>'.sens' then
    raise Exception.Create('потрібен фізичний файл .sens');
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або надмірний фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure TD7Laboratory.ShowPhysical(const Candidate:RawByteString);
var W:TExactWords; Span:TPhysicalWordSpans; I,J,Code:SizeInt;
    TextUkr,TextUk:RawByteString; C:TD7Glyph;
begin
  { Спершу ВЕСЬ кандидат перевірити, тільки потім публікувати UI.
    D7 «0», «(», «)» — 7-бітні дані, не D1 або D2. }
  TextUk:=DecodeD7Text(Candidate,Map,dsUk);
  TextUkr:=DecodeD7Text(Candidate,Map,dsUkr);
  DecodeT5MWithLocations(Candidate,W,Span);
  if (Length(W)<1) or (Length(W)>MaxShownD7) or
     (Length(Span)<>Length(W)) or (EncodeT5M(W)<>Candidate) then
    raise Exception.Create('неканонічна фізична таблиця D7');
  for I:=0 to High(W) do begin
    if Length(W[I])<>7 then
      raise Exception.Create('не семибітне слово у D7');
    Code:=0;
    for J:=1 to 7 do begin
      Code:=Code*2;
      if W[I][J]='1' then Inc(Code)
      else if W[I][J]<>'0' then
        raise Exception.Create('не двійкове слово D7');
    end;
    C:=Map[Code]; { тільки ПОСИЛАННЯ на вже допущений pinned row }
    if (C.Uk='') or (C.Ukr='') or
       (Span[I].WordIndex<>I+1) or Span[I].IsEOF then
      raise Exception.Create('керувальна координата/пошкоджений інтервал D7');
  end;
  WordGrid.RowCount:=Length(W)+1;
  for I:=0 to High(W) do begin
    Code:=0;
    for J:=1 to 7 do begin
      Code:=Code*2;
      if W[I][J]='1' then Inc(Code);
    end;
    WordGrid.Cells[0,I+1]:=IntToStr(I+1);
    WordGrid.Cells[1,I+1]:=String(W[I]);
    WordGrid.Cells[2,I+1]:=String(Map[Code].Uk);
    WordGrid.Cells[3,I+1]:=String(Map[Code].Ukr);
    WordGrid.Cells[4,I+1]:=HalfOpen(Span[I].TritStart,Span[I].TritEnd);
    WordGrid.Cells[5,I+1]:=HalfOpen(Span[I].ByteStart,Span[I].ByteEnd);
  end;
  Physical:=Candidate;
  DecodeButton.Enabled:=True;
  if Surface=dsUk then TextField.Text:=String(TextUk)
  else TextField.Text:=String(TextUkr);
  Status.Caption:='Д7-ГОТОВО: '+IntToStr(Length(W))+
    ' точних семибітних слів; '+IntToStr(Length(Candidate))+
    ' фізичних байтів T5M';
  Explanation.Caption:='Текстова поверхня явно обрана: '+
    SurfaceChoice.Text+'; байти й координати не змінюються від перемикання';
end;

procedure TD7Laboratory.EncodeClick(Sender:TObject);
var Candidate:RawByteString;
begin
  ClearWitness;
  try
    Candidate:=EncodeD7Text(RawByteString(TextField.Text),Map,Surface);
    ShowPhysical(Candidate);
  except on E:Exception do Failed(E.Message) end;
end;

procedure TD7Laboratory.LoadPhysical(const FileName:String);
var Candidate:RawByteString;
begin
  ClearWitness;
  try
    Candidate:=ReadPhysicalFile(FileName);
    ShowPhysical(Candidate);
  except on E:Exception do Failed(E.Message) end;
end;

procedure TD7Laboratory.ImportClick(Sender:TObject);
begin
  if OpenDialog.Execute then LoadPhysical(OpenDialog.FileName);
end;

procedure TD7Laboratory.DecodeClick(Sender:TObject);
begin
  if Physical='' then begin
    Failed('немає допущеного фізичного Д7');
    Exit;
  end;
  try
    ShowPhysical(Physical);
  except on E:Exception do Failed(E.Message) end;
end;

procedure TD7Laboratory.SurfaceChanged(Sender:TObject);
begin
  if Physical<>'' then DecodeClick(Sender);
end;

procedure TD7Laboratory.ValidateSecondExistingCodec;
var Alphabet:TD7Alphabet; I,Count:SizeInt;
    Witness,Decoded:RawByteString;
begin
  { Два існуючих кодеки — спільні pinned 95 друкованих W7.
    Перевіряємо їхню побайтову еквівалентність; третього немає. }
  LoadPinnedD7('external/sens',Alphabet);
  Count:=0;
  for I:=32 to 126 do begin
    if Map[I].Uk<>Alphabet[I] then
      raise Exception.Create('розходження двох pinned D7 кодеків у рядку '+
        IntToStr(I));
    Witness:=EncodeD7Text(Map[I].Uk,Map,dsUk);
    Decoded:=PhysicalD7ToUkrainian(Witness,Alphabet);
    if (Decoded<>Map[I].Uk) or
       (UkrainianD7ToPhysical(Decoded,Alphabet)<>Witness) or
       (DecodeD7Text(Witness,Map,dsUk)<>Decoded) then
      raise Exception.Create('колізія фізичного D7 W7 у рядку '+IntToStr(I));
    Inc(Count);
  end;
  if Count<>95 then
    raise Exception.Create('неповний pinned D7 контроль 95 символів');
end;

procedure TD7Laboratory.SelfTest(const GoodFile,SynFile,
  MixedFile,BadFile:String);
var Good,Snapshot:RawByteString;Words:TExactWords;Spans:TPhysicalWordSpans;
    Rejected:Boolean;
begin
  ValidateSecondExistingCodec;
  Good:=ReadPhysicalFile(GoodFile);
  SurfaceChoice.ItemIndex:=1;
  TextField.Text:='Це 0() №Їґ';
  EncodeClick(Self);
  if (Physical<>Good) or (not DecodeButton.Enabled) or
     (Pos('Д7-ГОТОВО',Status.Caption)<>1) then
    raise Exception.Create('укр → точний фізичний D7 не працює');
  DecodeT5MWithLocations(Physical,Words,Spans);
  if (Length(Words)<>10) or (Words[3]<>'0110000') or
     (Words[4]<>'0101000') or (Words[5]<>'0101001') or
     (Spans[0].TritStart<>0) or (Spans[0].TritEnd<>7) or
     (Spans[1].TritStart<>8) or (Spans[1].TritEnd<>15) or
     (WordGrid.Cells[1,5]<>'0101000') or
     (WordGrid.Cells[4,1]<>'[0,7)') or
     (WordGrid.Cells[5,1]<>'[0,2)') then
    raise Exception.Create('D7 0/() або точні тритові/байтові межі зіпсовані');
  Snapshot:=Physical;
  SurfaceChoice.ItemIndex:=0;
  SurfaceChanged(Self);
  if (Physical<>Snapshot) or
     (RawByteString(TextField.Text)<>DecodeD7Text(Good,Map,dsUk)) then
    raise Exception.Create('перемикання ук/укр змінило фізичні дані');
  SurfaceChoice.ItemIndex:=1;
  SurfaceChanged(Self);
  if RawByteString(TextField.Text)<>'Це 0() №Їґ' then
    raise Exception.Create('укр після перемикання не відновлено');
  LoadPhysical(GoodFile);
  if Physical<>Good then
    raise Exception.Create('імпорт канонічного D7 .sens не працює');
  TextField.Text:='i'; EncodeClick(Self);
  if (Physical<>'') or DecodeButton.Enabled or
     (WordGrid.Cells[1,1]<>'') then
    raise Exception.Create('непідтверджений латинський символ залишив свідок');
  Rejected:=False;
  try EncodeD7Text(#$C0#$AF,Map,dsUkr)
  except on E:Exception do Rejected:=True end;
  if not Rejected then
    raise Exception.Create('неканонічний UTF8 прийнято D7 кодеком');
  LoadPhysical(SynFile);
  if (Physical<>'') or DecodeButton.Enabled or
     (WordGrid.Cells[1,1]<>'') then
    raise Exception.Create('reserved D7 SYN отримав людську проєкцію');
  LoadPhysical(MixedFile);
  if Physical<>'' then
    raise Exception.Create('змішані D7/W1 байти прийнято');
  LoadPhysical(BadFile);
  if Physical<>'' then
    raise Exception.Create('неканонічний T5M опубліковано');
  LoadPhysical('неіснуючий-д7-рядок.sens');
  if Physical<>'' then
    raise Exception.Create('відсутній файл залишив старі байти');
  LoadPhysical(GoodFile);
  if (Physical<>Good) or (WordGrid.RowCount<>11) then
    raise Exception.Create('здорова D7 проєкція не відновлена');
  WriteLn('LCL-Д7-ТЕКСТ-ГАРАЗД рядків=10 друковані=95',
    ' кодеки=2-перевірені карта=ОДНА колізій=0',
    ' ук/укр=побайтово-точно T5M=канонічний',
    ' trit-byte=точні негативні=очищення D12=НЕ-ЧИСЛО');
end;

begin
  Application.Initialize;
  Application.CreateForm(TD7Laboratory,Laboratory);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка-д7') then begin
    if ParamCount<>5 then Halt(64);
    try
      Laboratory.Show;
      Application.ProcessMessages;
      Laboratory.SelfTest(ParamStr(2),ParamStr(3),
        ParamStr(4),ParamStr(5));
      Laboratory.Free;
      Halt(0);
    except on E:Exception do begin
      WriteLn(StdErr,'LCL-Д7-ТЕКСТ-ПОМИЛКА: ',E.Message);
      Halt(1);
    end end;
  end;
  Application.Run;
end.
