{ G5.12 — одна фізична .sens-програма, кілька незалежних коренів.
  Віджети LCL; виконання виключно через вже злитий wsm.binarybatch.
  Точні адреси — тільки готовий wsm.physloc, не нова семантика. }
unit wsm.formpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Grids, Dialogs;

const MaxFormOutputBytes = 1024*1024;
type
  TFormResult = record
    RootWord:SizeInt;
    Coordinate:RawByteString;
    TritStart,TritEnd,ByteStart,ByteEnd:SizeInt;
    Value:RawByteString;
  end;
  TFormResults = array of TFormResult;
  TFormWindow = class(TForm)
  private
    FTable:TStringGrid;
    FInfo:TLabel;
    FChoose:TButton;
    FDialog:TOpenDialog;
    FRows:TFormResults;
    procedure ChooseClicked(Sender:TObject);
    procedure ClearView(const MessageText:String);
  public
    constructor Create(AOwner:TComponent); override;
    function ExecuteFile(const Path:String):Boolean;
    function ResultCount:SizeInt;
    function ValueAt(Index:SizeInt):RawByteString;
    function RootWordAt(Index:SizeInt):SizeInt;
    function CoordinateAt(Index:SizeInt):RawByteString;
    function TritStartAt(Index:SizeInt):SizeInt;
    function StatusText:String;
    function HasWidgets:Boolean;
    function Evidence:RawByteString;
  end;

implementation
uses wsm.t5m, wsm.binarybatch, wsm.binaryexec,
     wsm.physloc, wsm.d2source;

constructor TFormWindow.Create(AOwner:TComponent);
var Bar,Footer:TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — форми одного двійкового файлу';
  Width:=1180; Height:=575; Position:=poScreenCenter;

  Bar:=TPanel.Create(Self);
  Bar.Parent:=Self; Bar.Align:=alTop; Bar.Height:=60;
  FChoose:=TButton.Create(Self);
  FChoose.Parent:=Bar;
  FChoose.Caption:='Вибрати один фізичний .sens';
  FChoose.SetBounds(12,10,275,35);
  FChoose.OnClick:=@ChooseClicked;

  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичний двійковий SENS (*.sens)|*.sens';
  FDialog.Title:='Оберіть файл із кількома верхніми формами';
  FDialog.Options:=FDialog.Options+[ofFileMustExist];

  Footer:=TPanel.Create(Self);
  Footer.Parent:=Self; Footer.Align:=alBottom; Footer.Height:=60;
  FInfo:=TLabel.Create(Self);
  FInfo.Parent:=Footer;
  FInfo.AutoSize:=False; FInfo.WordWrap:=True;
  FInfo.SetBounds(12,8,1130,45);

  FTable:=TStringGrid.Create(Self);
  FTable.Parent:=Self; FTable.Align:=alClient;
  FTable.ColCount:=6; FTable.FixedCols:=0; FTable.FixedRows:=1;
  FTable.RowCount:=2;
  FTable.Options:=FTable.Options-[goEditing]+[goRowSelect,goColSizing];
  FTable.ColWidths[0]:=85; FTable.ColWidths[1]:=120;
  FTable.ColWidths[2]:=160; FTable.ColWidths[3]:=225;
  FTable.ColWidths[4]:=225; FTable.ColWidths[5]:=290;
  FTable.Cells[0,0]:='Форма №';
  FTable.Cells[1,0]:='Точне слово №';
  FTable.Cells[2,0]:='Координата кореня';
  FTable.Cells[3,0]:='Трити [початок,кінець)';
  FTable.Cells[4,0]:='Байти [початок,кінець)';
  FTable.Cells[5,0]:='Дійсний результат D1/D3';
  ClearView('Оберіть фізичний .sens. Кожна форма незалежна; Core4/REPL не підтримано.');
end;

procedure TFormWindow.ClearView(const MessageText:String);
var C:SizeInt;
begin
  SetLength(FRows,0);
  FTable.BeginUpdate;
  try
    FTable.RowCount:=2;
    for C:=0 to FTable.ColCount-1 do FTable.Cells[C,1]:='';
  finally FTable.EndUpdate; end;
  FInfo.Caption:=MessageText;
end;

function TFormWindow.ExecuteFile(const Path:String):Boolean;
var
  Stream:TFileStream;
  Data:RawByteString;
  Answers:TBinaryBatchAnswers;
  Candidate:TFormResults;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Engine:TBinaryExecutor;
  Source:TPhysicalWordSpan;
  Index,WordNo,OutputBytes:SizeInt;
  N:TD2Node;
begin
  Result:=False;
  ClearView('Перевірка фізичного T5M/D2 і виконання всіх форм…');
  Doc:=nil; Engine:=nil;
  try
    if (LowerCase(ExtractFileExt(Path))<>'.sens') then
      raise Exception.Create('потрібен канонічний двійковий файл .sens');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надто великий фізичний файл');
      SetLength(Data,SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[1],Length(Data));
    finally Stream.Free; end;

    Engine:=TBinaryExecutor.Create('external/sens');
    { Повний атомарний прийом та ВИКОНАННЯ тільки через чинний
      багатоформовий механізм. Ніякої локальної D3-логіки тут немає. }
    ExecuteBinaryBatch(Data,Engine,Answers);
    { Другий ПІДТВЕРДЖЕНИЙ фізичний огляд лише для показу адрес:
      локальні текстові/числові координати не є мовними законами. }
    Doc:=ReadD2WithPhysicalLocations(Data,Spans);
    if (Length(Answers)<1) or
       (Length(Answers)<>Length(Doc.Roots)) or
       (Length(Answers)>MaxBatchRoots) then
      raise Exception.Create('не збігається кількість фізичних коренів');
    SetLength(Candidate,Length(Answers));
    OutputBytes:=0;
    for Index:=0 to High(Answers) do begin
      N:=Doc.Roots[Index];
      if N=nil then
        raise Exception.Create('відсутня верхня форма');
      WordNo:=N.WordIndex;
      Source:=LocatePhysicalWord(Data,Spans,WordNo);
      if Source.IsEOF then
        raise Exception.Create('корінь указує на кінець файлу');
      Candidate[Index].RootWord:=WordNo;
      Candidate[Index].TritStart:=Source.TritStart;
      Candidate[Index].TritEnd:=Source.TritEnd;
      Candidate[Index].ByteStart:=Source.ByteStart;
      Candidate[Index].ByteEnd:=Source.ByteEnd;
      if N.Kind=dkList then
        Candidate[Index].Coordinate:='D2:10'
      else if N.Kind=dkPair then
        raise Exception.Create('похідна пара не має власного фізичного кореня')
      else
        Candidate[Index].Coordinate:='D'+IntToStr(N.Width)+':'+N.Bits;
      if (Length(Answers[Index])>MaxFormOutputBytes-OutputBytes) or
         (Pos(#0,Answers[Index])>0) or (Pos(#9,Answers[Index])>0) or
         (Pos(#10,Answers[Index])>0) or (Pos(#13,Answers[Index])>0) then
        raise Exception.Create('недопустимий обсяг або керівний байт результату');
      Inc(OutputBytes,Length(Answers[Index]));
      Candidate[Index].Value:=Answers[Index];
    end;
    { Тільки тепер результати відкриваються віджетам LCL. }
    FRows:=Candidate;
    FTable.BeginUpdate;
    try
      FTable.RowCount:=Length(FRows)+1;
      for Index:=0 to High(FRows) do begin
        FTable.Cells[0,Index+1]:=IntToStr(Index+1);
        FTable.Cells[1,Index+1]:=IntToStr(FRows[Index].RootWord);
        FTable.Cells[2,Index+1]:=String(FRows[Index].Coordinate);
        FTable.Cells[3,Index+1]:='['+IntToStr(FRows[Index].TritStart)+','+
          IntToStr(FRows[Index].TritEnd)+')';
        FTable.Cells[4,Index+1]:='['+IntToStr(FRows[Index].ByteStart)+','+
          IntToStr(FRows[Index].ByteEnd)+')';
        FTable.Cells[5,Index+1]:=String(FRows[Index].Value);
      end;
    finally FTable.EndUpdate; end;
    FInfo.Caption:='Виконано верхніх форм: '+IntToStr(Length(FRows))+
      '. Позиції фізичного T5M; незалежні D1/D3 без спільного середовища.';
    Result:=True;
  except
    on E:EBinaryBatchError do ClearView('Відхилено форму №'+
      IntToStr(E.RootIndex+1)+', фізичне слово '+IntToStr(E.WordIndex)+': '+E.Message);
    on E:Exception do ClearView('Відхилено фізичний файл: '+E.Message);
  end;
  Doc.Free; Engine.Free;
end;

procedure TFormWindow.ChooseClicked(Sender:TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

function TFormWindow.ResultCount:SizeInt;
begin Result:=Length(FRows); end;
function TFormWindow.ValueAt(Index:SizeInt):RawByteString;
begin
  if (Index<0) or (Index>=Length(FRows)) then
    raise Exception.Create('немає підтвердженого результату');
  Result:=FRows[Index].Value;
end;
function TFormWindow.RootWordAt(Index:SizeInt):SizeInt;
begin
  if (Index<0) or (Index>=Length(FRows)) then
    raise Exception.Create('немає фізичного слова кореня');
  Result:=FRows[Index].RootWord;
end;
function TFormWindow.CoordinateAt(Index:SizeInt):RawByteString;
begin
  if (Index<0) or (Index>=Length(FRows)) then
    raise Exception.Create('немає точних координат кореня');
  Result:=FRows[Index].Coordinate;
end;
function TFormWindow.TritStartAt(Index:SizeInt):SizeInt;
begin
  if (Index<0) or (Index>=Length(FRows)) then
    raise Exception.Create('немає тритової адреси');
  Result:=FRows[Index].TritStart;
end;
function TFormWindow.StatusText:String;
begin Result:=FInfo.Caption; end;
function TFormWindow.HasWidgets:Boolean;
begin
  Result:=(FTable<>nil) and (FChoose<>nil) and (FDialog<>nil) and
    Assigned(FChoose.OnClick) and (FTable.ColCount=6);
end;
function TFormWindow.Evidence:RawByteString;
var I:SizeInt;
begin
  Result:='';
  for I:=0 to High(FRows) do
    Result:=Result+IntToStr(I+1)+#9+IntToStr(FRows[I].RootWord)+#9+
      FRows[I].Coordinate+#9+
      '['+IntToStr(FRows[I].TritStart)+','+IntToStr(FRows[I].TritEnd)+')'+#9+
      '['+IntToStr(FRows[I].ByteStart)+','+IntToStr(FRows[I].ByteEnd)+')'+#9+
      FRows[I].Value+#10;
end;
end.
