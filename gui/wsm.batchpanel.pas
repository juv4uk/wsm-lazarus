{ G5.10 — графічне пакетне ВІДОБРАЖЕННЯ окремих фізичних .sens.
  Немає власного виконавця, reader, закону SENS чи транзакції runtime.
  Кожен файл передається ВЖЕ злитому wsm.binaryexec, самостійно. }
unit wsm.batchpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Grids, Dialogs;

const MaxBatchFiles=16;
      MaxBatchOutputBytes=1024*1024;

type
  TBatchRow=record
    FileName:String;
    Bytes:SizeInt;
    Output:RawByteString;
  end;
  TBatchRows=array of TBatchRow;

  TBatchForm=class(TForm)
  private
    FTable:TStringGrid;
    FStatus:TLabel;
    FChoose:TButton;
    FSave:TButton;
    FDialog:TOpenDialog;
    FRows:TBatchRows;
    procedure ChooseClicked(Sender:TObject);
    procedure SaveClicked(Sender:TObject);
    procedure ClearResults(const MessageText:String);
  public
    constructor Create(AOwner:TComponent); override;
    function ExecuteFiles(const Paths:array of String):Boolean;
    function ResultAt(Index:SizeInt):RawByteString;
    function Evidence:RawByteString;
    function ResultCount:SizeInt;
    function StatusText:String;
    function HasWidgets:Boolean;
  end;

implementation
uses wsm.binaryexec, wsm.t5m;

constructor TBatchForm.Create(AOwner:TComponent);
var Bar,Bottom:TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — декілька фізичних програм';
  Position:=poScreenCenter;
  Width:=920; Height:=560;
  Bar:=TPanel.Create(Self);
  Bar.Parent:=Self; Bar.Align:=alTop; Bar.Height:=78;
  FChoose:=TButton.Create(Self);
  FChoose.Parent:=Bar;
  FChoose.Caption:='Вибрати до 16 файлів .sens';
  FChoose.SetBounds(12,9,278,32);
  FChoose.OnClick:=@ChooseClicked;
  FSave:=TButton.Create(Self);
  FSave.Parent:=Bar;
  FSave.Caption:='Зберегти результати TSV';
  FSave.SetBounds(308,9,250,32);
  FSave.OnClick:=@SaveClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичні файли SENS|*.sens';
  FDialog.Options:=FDialog.Options+[ofAllowMultiSelect,ofFileMustExist];
  FDialog.Title:='Виберіть окремі двійкові програми SENS';
  Bottom:=TPanel.Create(Self);
  Bottom.Parent:=Self; Bottom.Align:=alBottom; Bottom.Height:=54;
  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=Bottom;
  FStatus.AutoSize:=False; FStatus.WordWrap:=True;
  FStatus.SetBounds(12,6,875,44);
  FStatus.Caption:='Очікуються фізичні файли. Лише підтриманий D1/D3; Core4 не виконується.';
  FTable:=TStringGrid.Create(Self);
  FTable.Parent:=Self;
  FTable.Align:=alClient;
  FTable.FixedCols:=0; FTable.FixedRows:=1;
  FTable.ColCount:=4;
  FTable.RowCount:=2;
  FTable.Options:=FTable.Options-[goEditing]+[goRowSelect];
  FTable.ColWidths[0]:=70;
  FTable.ColWidths[1]:=340;
  FTable.ColWidths[2]:=110;
  FTable.ColWidths[3]:=330;
  FTable.Cells[0,0]:='№';
  FTable.Cells[1,0]:='Фізичний файл';
  FTable.Cells[2,0]:='Байтів';
  FTable.Cells[3,0]:='Дійсний результат D1/D3';
  ClearResults('Очікуються фізичні файли. Жодних виконаних форм.');
end;

procedure TBatchForm.ClearResults(const MessageText:String);
var I,J:Integer;
begin
  SetLength(FRows,0);
  FTable.BeginUpdate;
  try
    FTable.RowCount:=2;
    for I:=0 to 3 do
      for J:=1 to FTable.RowCount-1 do FTable.Cells[I,J]:='';
  finally FTable.EndUpdate; end;
  FStatus.Caption:=MessageText;
end;

function TBatchForm.ExecuteFiles(const Paths:array of String):Boolean;
var
  I,J:SizeInt;
  Data,Answer:RawByteString;
  Stream:TFileStream;
  Engine:TBinaryExecutor;
  Candidate:TBatchRows;
  TotalOutput:SizeInt;
  NamePart:String;
begin
  Result:=False;
  ClearResults('Перевіряємо всі фізичні файли…');
  if (Length(Paths)<1) or (Length(Paths)>MaxBatchFiles) then begin
    ClearResults('Відхилено: кількість файлів має бути від 1 до 16');
    Exit;
  end;
  Engine:=nil;
  SetLength(Candidate,Length(Paths));
  TotalOutput:=0;
  I:=-1;
  try
    Engine:=TBinaryExecutor.Create('external/sens');
    for I:=0 to High(Paths) do begin
      NamePart:=ExtractFileName(Paths[I]);
      if (NamePart='') or (Pos(#9,NamePart)>0) or
         (Pos(#10,NamePart)>0) or (Pos(#13,NamePart)>0) or
         (LowerCase(ExtractFileExt(Paths[I]))<>'.sens') then
        raise Exception.Create('очікується назва фізичного файлу .sens без керівних символів');
      Stream:=TFileStream.Create(Paths[I],fmOpenRead or fmShareDenyWrite);
      try
        if (Stream.Size<1) or (Stream.Size>MAX_T5M_FILE_BYTES) then
          raise Exception.Create('порожній або завеликий фізичний файл');
        SetLength(Data,SizeInt(Stream.Size));
        Stream.ReadBuffer(Data[1],Length(Data));
      finally Stream.Free; end;
      Answer:=Engine.ExecutePhysical(Data);
      { Жодних обрізань чи прихованого перетворення результату на мову. }
      if (Length(Answer)>MaxBatchOutputBytes-TotalOutput) then
        raise Exception.Create('перевищено квоту байтів результатів');
      if (Pos(#0,Answer)>0) or (Pos(#9,Answer)>0) or
         (Pos(#10,Answer)>0) or (Pos(#13,Answer)>0) then
        raise Exception.Create('результат містить керівний байт для TSV');
      Inc(TotalOutput,Length(Answer));
      Candidate[I].FileName:=NamePart;
      Candidate[I].Bytes:=Length(Data);
      Candidate[I].Output:=Answer;
    end;
    { Опублікувати результат тільки після успіху ВСІХ ExecutePhysical. }
    FRows:=Candidate;
    FTable.BeginUpdate;
    try
      FTable.RowCount:=Length(FRows)+1;
      for J:=0 to High(FRows) do begin
        FTable.Cells[0,J+1]:=IntToStr(J+1);
        FTable.Cells[1,J+1]:=FRows[J].FileName;
        FTable.Cells[2,J+1]:=IntToStr(FRows[J].Bytes);
        FTable.Cells[3,J+1]:=String(FRows[J].Output);
      end;
    finally FTable.EndUpdate; end;
    FStatus.Caption:='Виконано фізичних файлів: '+IntToStr(Length(FRows))+
      '. Усі результати перевірено; не є REPL або виконанням Core4.';
    Result:=True;
  except
    on E:EBinaryExecutionError do ClearResults('Відхилено файл №'+
      IntToStr(I+1)+': фізичне слово '+IntToStr(E.WordIndex)+': '+E.Message);
    on E:Exception do ClearResults('Відхилено файл №'+
      IntToStr(I+1)+': '+E.Message);
  end;
  Engine.Free;
end;

function TBatchForm.ResultAt(Index:SizeInt):RawByteString;
begin
  if (Index<0) or (Index>=Length(FRows)) then
    raise Exception.Create('індекс поза перевіреними результатами');
  Result:=FRows[Index].Output;
end;

function TBatchForm.ResultCount:SizeInt;
begin Result:=Length(FRows); end;

function TBatchForm.StatusText:String;
begin Result:=FStatus.Caption; end;

function TBatchForm.HasWidgets:Boolean;
begin
  Result:=(FTable<>nil) and (FChoose<>nil) and (FSave<>nil) and
          (FDialog<>nil) and Assigned(FChoose.OnClick) and
          Assigned(FSave.OnClick) and (ofAllowMultiSelect in FDialog.Options);
end;

function TBatchForm.Evidence:RawByteString;
var I:SizeInt;
begin
  if Length(FRows)=0 then Exit('');
  Result:='№'#9'Фізичний файл'#9'Байтів'#9'Результат D1/D3'#10;
  for I:=0 to High(FRows) do
    Result:=Result+IntToStr(I+1)+#9+RawByteString(FRows[I].FileName)+
      #9+IntToStr(FRows[I].Bytes)+#9+FRows[I].Output+#10;
end;

procedure TBatchForm.ChooseClicked(Sender:TObject);
var Names:array of String; I:Integer;
begin
  if not FDialog.Execute then Exit;
  SetLength(Names,FDialog.Files.Count);
  for I:=0 to FDialog.Files.Count-1 do Names[I]:=FDialog.Files[I];
  ExecuteFiles(Names);
end;

procedure TBatchForm.SaveClicked(Sender:TObject);
var Save:TSaveDialog; OutFile:TFileStream; Bytes:RawByteString;
begin
  if Length(FRows)=0 then begin
    MessageDlg('Немає перевірених результатів для експорту',mtInformation,[mbOK],0);
    Exit;
  end;
  Save:=TSaveDialog.Create(Self);
  try
    Save.Title:='Зберегти результати фізичних програм';
    Save.Filter:='Таблиця UTF-8 TSV|*.tsv';
    Save.DefaultExt:='tsv';
    if Save.Execute then begin
      Bytes:=Evidence;
      OutFile:=TFileStream.Create(Save.FileName,fmCreate);
      try
        if Length(Bytes)>0 then OutFile.WriteBuffer(Bytes[1],Length(Bytes));
      finally OutFile.Free; end;
    end;
  finally Save.Free; end;
end;
end.
