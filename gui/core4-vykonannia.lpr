{ G4.9 — справжнє вікно виконання вузького pinned Core4 binary.
  Мовні закони належать SENS; усе виконання делегується TCore4Runtime.
  Людський .lisp тут не приймається за канонічну програму. }
program core4_vykonannia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs,
  Grids, wsm.core4runtime, wsm.t5m, wsm.d2source, wsm.physloc;
const MaxCallBytes=1024*1024;
      MaxHistoryRows=32;
      MaxPacketForms=64;
type
  TCore4Window=class(TForm)
  private
    FRuntime:TCore4Runtime;
    FOpen,FBatch,FPacketButton,FArchiveButton:TButton;
    FDialog,FBatchDialog,FArchiveDialog:TOpenDialog;
    FStatus,FFile,FAnswer:TLabel;
    FHistory,FPacketGrid:TStringGrid;
    FHistoryCount,FPacketCount:SizeInt;
    FResultBits:RawByteString;
    procedure OpenClick(Sender:TObject);
    procedure BatchClick(Sender:TObject);
    procedure PacketClick(Sender:TObject);
    procedure ArchiveClick(Sender:TObject);
    procedure ClearPacket;
    function PacketPhysical(const Calls:array of RawByteString):RawByteString;
    function EvaluatePhysicalFile(const Path:String):RawByteString;
    procedure ClearResult;
    procedure ClearHistory;
    procedure AddHistory(const Path,State,ExactWidth,Bits:String);
    procedure Need(Condition:Boolean;const Why:String);
    procedure SavePhysical(const Path:String;const Data:RawByteString);
    function MakeCall(const Id,Arg:RawByteString;IncludeArg:Boolean=True):RawByteString;
    function MakeIdentifier(const Id:RawByteString):RawByteString;
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    function LoadAuthority(const Root:String):Boolean;
    function ExecuteFile(const Path:String):Boolean;
    function ExecuteBatchFiles(const Paths:TStrings):Boolean;
    function ExecutePacketFile(const Path:String):Boolean;
    function InspectAnswerArchive(const Path:String):Boolean;
    procedure SelfCheck(const Root,TempDir:String);
  end;
type
  TBatchEntry=record
    Path:String;            { шлях хоста, не доменне ім'я }
    Bits:RawByteString;     { незмінне exact-бітове слово результату }
  end;
var Window:TCore4Window;

constructor TCore4Window.Create(AOwner:TComponent);
var Note:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — виконання початкового Core4';
  Width:=820; Height:=905; Position:=poScreenCenter;
  FRuntime:=nil;
  FOpen:=TButton.Create(Self); FOpen.Parent:=Self;
  FOpen.SetBounds(14,14,340,38);
  FOpen.Caption:='Виконати двійковий файл .sens';
  FOpen.OnClick:=@OpenClick; FOpen.Enabled:=False;
  FBatch:=TButton.Create(Self); FBatch.Parent:=Self;
  FBatch.SetBounds(369,14,387,38);
  FBatch.Caption:='Виконати групу файлів .sens (до 8)';
  FBatch.OnClick:=@BatchClick; FBatch.Enabled:=False;
  FPacketButton:=TButton.Create(Self); FPacketButton.Parent:=Self;
  FPacketButton.SetBounds(14,60,742,38);
  FPacketButton.Caption:='Виконати кілька форм в одному файлі .sens (до 64)';
  FPacketButton.OnClick:=@PacketClick; FPacketButton.Enabled:=False;
  FArchiveButton:=TButton.Create(Self); FArchiveButton.Parent:=Self;
  FArchiveButton.SetBounds(14,754,742,38);
  FArchiveButton.Caption:='Оглянути фізичний архів відповідей .sens (до 64 слів)';
  FArchiveButton.OnClick:=@ArchiveClick;
  { Архів є фізичними даними, тому не потребує виконуваного Core4. }
  FArchiveButton.Enabled:=True;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Фізична програма SENS';
  FDialog.Filter:='Двійковий SENS (*.sens)|*.sens';
  FBatchDialog:=TOpenDialog.Create(Self);
  FBatchDialog.Title:='Група фізичних файлів SENS';
  FBatchDialog.Filter:='Двійковий SENS (*.sens)|*.sens';
  FBatchDialog.Options:=FBatchDialog.Options+[ofAllowMultiSelect,ofFileMustExist];
  FArchiveDialog:=TOpenDialog.Create(Self);
  FArchiveDialog.Title:='Фізичні відповіді SENS (огляд без виконання)';
  FArchiveDialog.Filter:='Фізичний архів SENS (*.sens)|*.sens';
  FArchiveDialog.Options:=FArchiveDialog.Options+[ofFileMustExist];
  FFile:=TLabel.Create(Self); FFile.Parent:=Self;
  FFile.SetBounds(14,111,776,26); FFile.Caption:='Файл не вибрано';
  FAnswer:=TLabel.Create(Self); FAnswer.Parent:=Self;
  FAnswer.SetBounds(14,150,776,35); FAnswer.Caption:='';
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(14,193,776,54);
  FStatus.AutoSize:=False; FStatus.WordWrap:=True;
  FHistory:=TStringGrid.Create(Self); FHistory.Parent:=Self;
  FHistory.SetBounds(14,255,776,219);
  FHistory.FixedCols:=0;
  FHistory.FixedRows:=1;
  FHistory.ColCount:=5;
  FHistory.RowCount:=2;
  FHistory.ColWidths[0]:=42;
  FHistory.ColWidths[1]:=165;
  FHistory.ColWidths[2]:=108;
  FHistory.ColWidths[3]:=82;
  FHistory.ColWidths[4]:=340;
  FHistory.Cells[0,0]:='№';
  FHistory.Cells[1,0]:='Файл .sens';
  FHistory.Cells[2,0]:='Результат';
  FHistory.Cells[3,0]:='Ширина';
  FHistory.Cells[4,0]:='Точні біти';
  FHistory.Options:=FHistory.Options+[goColSizing];
  FPacketGrid:=TStringGrid.Create(Self); FPacketGrid.Parent:=Self;
  FPacketGrid.SetBounds(14,497,776,241);
  FPacketGrid.FixedCols:=0; FPacketGrid.FixedRows:=1;
  FPacketGrid.ColCount:=5; FPacketGrid.RowCount:=2;
  FPacketGrid.ColWidths[0]:=40;
  FPacketGrid.ColWidths[1]:=85;
  FPacketGrid.ColWidths[2]:=75;
  FPacketGrid.ColWidths[3]:=300;
  FPacketGrid.ColWidths[4]:=250;
  FPacketGrid.Cells[0,0]:='№';
  FPacketGrid.Cells[1,0]:='Слово';
  FPacketGrid.Cells[2,0]:='Ширина';
  FPacketGrid.Cells[3,0]:='Точні біти';
  FPacketGrid.Cells[4,0]:='Адреса у .sens';
  FPacketGrid.Options:=FPacketGrid.Options+[goColSizing];
  Note:=TLabel.Create(Self); Note.Parent:=Self;
  Note.SetBounds(14,813,776,58);
  Note.AutoSize:=False; Note.WordWrap:=True;
  Note.Caption:='Лише перші три визначення pinned core4.sens. '+
    'Результат — точні біти, не десяткове число D12+; '+
    'це не повний Core4, не REPL і не семантичний oracle.';
  FHistoryCount:=0;
  FPacketCount:=0;
  ClearHistory;
  ClearPacket;
  ClearResult;
end;

destructor TCore4Window.Destroy;
begin
  FRuntime.Free;
  inherited Destroy;
end;

procedure TCore4Window.ClearResult;
begin
  FResultBits:='';
  FAnswer.Caption:='';
  FFile.Caption:='Файл не вибрано';
  FStatus.Caption:='Немає виконаного фізичного виклику.';
end;

{ Історія — лише host-перегляд фізичних свідків: ніякого Dn admission.
  Не більше 32 видимих записів; попередній результат не повторюється
  у рядку помилки. Вміст грида звільняється власником LCL форми. }
procedure TCore4Window.ClearHistory;
var R,C:Integer;
begin
  FHistoryCount:=0;
  FHistory.RowCount:=2;
  for R:=1 to FHistory.RowCount-1 do
    for C:=0 to FHistory.ColCount-1 do FHistory.Cells[C,R]:='';
end;

procedure TCore4Window.AddHistory(const Path,State,ExactWidth,Bits:String);
var R,C:Integer;
begin
  if FHistoryCount=MaxHistoryRows then
  begin
    for R:=1 to MaxHistoryRows-1 do
      for C:=0 to FHistory.ColCount-1 do
        FHistory.Cells[C,R]:=FHistory.Cells[C,R+1];
    R:=MaxHistoryRows;
  end
  else
  begin
    Inc(FHistoryCount);
    R:=FHistoryCount;
    FHistory.RowCount:=FHistoryCount+1;
  end;
  FHistory.Cells[0,R]:=IntToStr(R);
  FHistory.Cells[1,R]:=ExtractFileName(Path);
  FHistory.Cells[2,R]:=State;
  FHistory.Cells[3,R]:=ExactWidth;
  FHistory.Cells[4,R]:=Bits;
end;

{ Лише host-таблиця фізичних результатів. Ніколи не показувати
  підтверджений префікс пакета, якщо пізня форма відхилена. }
procedure TCore4Window.ClearPacket;
var R,C:Integer;
begin
  FPacketCount:=0;
  FPacketGrid.RowCount:=2;
  for R:=1 to FPacketGrid.RowCount-1 do
    for C:=0 to FPacketGrid.ColCount-1 do
      FPacketGrid.Cells[C,R]:='';
end;

{ Об'єднання лише фізичних T5M слів, а не конкатенація
  окремих байтових контейнерів з їхнім padding. }
function TCore4Window.PacketPhysical(
  const Calls:array of RawByteString):RawByteString;
var AllWords,One:TExactWords; I,J,N:SizeInt;
begin
  SetLength(AllWords,0);
  for I:=0 to High(Calls) do begin
    DecodeT5M(Calls[I],One);
    N:=Length(AllWords);
    SetLength(AllWords,N+Length(One));
    for J:=0 to High(One) do AllWords[N+J]:=One[J];
  end;
  Result:=EncodeT5M(AllWords);
end;

procedure TCore4Window.Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('перевірка Lazarus Core4: '+Why);
end;

function TCore4Window.LoadAuthority(const Root:String):Boolean;
var Candidate:TCore4Runtime;
begin
  Result:=False;
  ClearResult;
  ClearHistory;
  ClearPacket;
  FreeAndNil(FRuntime);
  FOpen.Enabled:=False;
  FBatch.Enabled:=False;
  FPacketButton.Enabled:=False;
  Candidate:=nil;
  try
    Candidate:=TCore4Runtime.Create(Root);
    if Candidate.BindingCount<>3 then
      raise Exception.Create('очікувалися три перевірені початкові визначення');
    FRuntime:=Candidate;
    Candidate:=nil;
    FOpen.Enabled:=True;
    FBatch.Enabled:=True;
    FPacketButton.Enabled:=True;
    FStatus.Caption:='Pinned Core4: завантажено три початкові визначення.';
    Result:=True;
  except on E:Exception do begin
    FStatus.Caption:='Core4 не завантажено: '+E.Message;
  end end;
  Candidate.Free;
end;

{ Спільний фізичний шлях для одиночного й групового LCL-запиту.
  Мовний закон не дублюється: виконання лише через pinned runtime. }
function TCore4Window.EvaluatePhysicalFile(const Path:String):RawByteString;
var Stream:TFileStream;Physical,Answer:RawByteString;Words:TExactWords;
begin
  if FRuntime=nil then raise Exception.Create('спочатку потрібен pinned Core4');
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('виконуються лише фізичні .sens');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxCallBytes) then
      raise Exception.Create('файл порожній або завеликий');
    SetLength(Physical,SizeInt(Stream.Size));
    Stream.ReadBuffer(Physical[1],Length(Physical));
  finally Stream.Free end;
  Answer:=FRuntime.ExecutePhysicalCall(Physical);
  DecodeT5M(Answer,Words);
  if (Length(Words)<>1) or (EncodeT5M(Words)<>Answer) then
    raise Exception.Create('невідомий формат фізичної відповіді');
  Result:=Words[0];
end;

function TCore4Window.ExecuteFile(const Path:String):Boolean;
begin
  Result:=False;
  ClearResult;
  ClearPacket;
  try
    FResultBits:=EvaluatePhysicalFile(Path);
    FFile.Caption:='Виконано файл: '+ExtractFileName(Path);
    FAnswer.Caption:='Фізичне слово W'+IntToStr(Length(FResultBits))+
      ' · '+String(FResultBits);
    FStatus.Caption:='Фізичне виконання одного підтриманого Core4-виклику; '+
      'ширина Wn не є автоматичним доменом Dn.';
    AddHistory(Path,'виконано','W'+IntToStr(Length(FResultBits)),
      String(FResultBits));
    Result:=True;
  except on E:Exception do begin
    ClearResult;
    FStatus.Caption:='Відмова виконання: '+E.Message;
    AddHistory(Path,'відхилено','','');
  end end;
end;

{ Окремі фізичні файли, а не багато форм одного файла. Успішні
  записи не потрапляють у GUI, поки всі виклики не завершені.
  Файлові потоки звільняє EvaluatePhysicalFile; Staged — кероване
  локальне сховище. Єдиний FRuntime належить TCore4Window. }
function TCore4Window.ExecuteBatchFiles(const Paths:TStrings):Boolean;
const MaxBatchFiles=8;
var Staged:array of TBatchEntry; I:SizeInt;
begin
  Result:=False;
  ClearResult;
  ClearPacket;
  try
    if FRuntime=nil then raise Exception.Create('спочатку потрібен pinned Core4');
    if Paths=nil then raise Exception.Create('список файлів відсутній');
    if (Paths.Count<1) or (Paths.Count>MaxBatchFiles) then
      raise Exception.Create('допустимо від одного до восьми файлів .sens');
    SetLength(Staged,Paths.Count);
    for I:=0 to High(Staged) do begin
      Staged[I].Path:=Paths[I];
      try
        Staged[I].Bits:=EvaluatePhysicalFile(Staged[I].Path);
      except on E:Exception do
        raise Exception.Create('файл '+IntToStr(I+1)+': '+E.Message);
      end;
    end;
    { Одна фаза публікації після повного успіху. }
    for I:=0 to High(Staged) do
      AddHistory(Staged[I].Path,'виконано',
        'W'+IntToStr(Length(Staged[I].Bits)),String(Staged[I].Bits));
    FResultBits:=Staged[High(Staged)].Bits;
    FFile.Caption:='Виконано групу файлів: '+IntToStr(Length(Staged));
    FAnswer.Caption:='Останнє фізичне слово W'+IntToStr(Length(FResultBits))+
      ' · '+String(FResultBits);
    FStatus.Caption:='Група виконана тим самим pinned Core4 runtime. '+
      'Wn є лише фізичною шириною, не семантичним Dn.';
    Result:=True;
  except on E:Exception do begin
    ClearResult;
    FStatus.Caption:='Відмова групи: '+E.Message;
    AddHistory('група','відхилено','','');
  end end;
end;

{ GUI використовує той самий Core4 runtime, який виконує одне фізичне
  застосування. Секвенсинг, обмеження 64 і зведення результатів — це
  host-механізм; семантика кожної форми належить pinned SENS. }
function TCore4Window.ExecutePacketFile(const Path:String):Boolean;
var
  Stream:TFileStream;
  Physical,Answer:RawByteString;
  Words,Part,ResponseWords,Results:TExactWords;
  Locations:TPhysicalWordSpans;
  AtRoots:array of TPhysicalWordSpan;
  Doc:TD2Document;
  ProblemAt:TPhysicalWordSpan;
  EofText:String;
  I,J,FirstWord,AfterLast:SizeInt;
begin
  Result:=False;
  ClearResult;
  ClearPacket;
  try
    if FRuntime=nil then raise Exception.Create('спочатку потрібен pinned Core4');
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('виконуються лише фізичні .sens');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxCallBytes) then
        raise Exception.Create('файл порожній або завеликий');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    DecodeT5MWithLocations(Physical,Words,Locations);
    { D2 помилка локалізується у ВХІДНОМУ фізичному T5M,
      включно з одним уявним словом на EOF. Лише чинний reader
      визначає синтаксис, host додає перевірені координати. }
    try
      Doc:=ParseD2WordsWide(Words);
    except
      on E:ED2SourceError do begin
        ProblemAt:=LocatePhysicalWord(Physical,Locations,E.WordIndex);
        if ProblemAt.IsEOF then EofText:='так'
        else EofText:='ні';
        raise Exception.Create('помилка D2: слово='+
          IntToStr(ProblemAt.WordIndex)+
          ' трити=['+IntToStr(ProblemAt.TritStart)+','+
            IntToStr(ProblemAt.TritEnd)+')'+
          ' байти=['+IntToStr(ProblemAt.ByteStart)+','+
            IntToStr(ProblemAt.ByteEnd)+')'+
          ' EOF='+EofText+' '+E.Message);
      end;
    end;
    try
      if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxPacketForms) then
        raise Exception.Create('неприпустима кількість фізичних форм у пакеті');
      SetLength(Results,Length(Doc.Roots));
      SetLength(AtRoots,Length(Doc.Roots));
      for I:=0 to High(Doc.Roots) do begin
        AtRoots[I]:=LocatePhysicalWord(Physical,Locations,
          Doc.Roots[I].WordIndex);
        FirstWord:=Doc.Roots[I].WordIndex-1;
        if I<High(Doc.Roots) then
          AfterLast:=Doc.Roots[I+1].WordIndex-1
        else
          AfterLast:=Length(Words);
        if (FirstWord<0) or (AfterLast<=FirstWord) then
          raise Exception.Create('пошкоджено фізичні межі пакета');
        SetLength(Part,AfterLast-FirstWord);
        for J:=0 to High(Part) do Part[J]:=Words[FirstWord+J];
        try
          Answer:=FRuntime.ExecutePhysicalCall(EncodeT5M(Part));
        except on E:Exception do
          raise Exception.Create('форма '+IntToStr(I+1)+
            ', початок слова '+IntToStr(AtRoots[I].WordIndex)+
            ', байт '+IntToStr(AtRoots[I].ByteStart)+': '+E.Message);
        end;
        DecodeT5M(Answer,ResponseWords);
        if (Length(ResponseWords)<>1) or
           (EncodeT5M(ResponseWords)<>Answer) then
          raise Exception.Create('форма не дала одного канонічного слова');
        Results[I]:=ResponseWords[0];
      end;
      { Публікація — тільки після успішного виконання ВСІХ форм. }
      FPacketGrid.RowCount:=Length(Results)+1;
      for I:=0 to High(Results) do begin
        FPacketGrid.Cells[0,I+1]:=IntToStr(I+1);
        FPacketGrid.Cells[1,I+1]:=IntToStr(AtRoots[I].WordIndex);
        FPacketGrid.Cells[2,I+1]:='W'+IntToStr(Length(Results[I]));
        FPacketGrid.Cells[3,I+1]:=String(Results[I]);
        FPacketGrid.Cells[4,I+1]:='трит '+
          IntToStr(AtRoots[I].TritStart)+'; байт '+
          IntToStr(AtRoots[I].ByteStart);
      end;
      FPacketCount:=Length(Results);
      FFile.Caption:='Виконано пакет: '+ExtractFileName(Path);
      FAnswer.Caption:='Виконано фізичних форм: '+IntToStr(FPacketCount);
      FStatus.Caption:='Відповіді — точні фізичні біти та Wn; '+
        'ширина не надає домену чи числової семантики.';
      AddHistory(Path,'пакет виконано',IntToStr(FPacketCount)+' форм','');
      Result:=True;
    finally Doc.Free end;
  except on E:Exception do begin
    ClearResult;
    ClearPacket;
    FStatus.Caption:='Відмова пакета: '+E.Message;
    AddHistory(Path,'пакет відхилено','','');
  end end;
end;

procedure TCore4Window.PacketClick(Sender:TObject);
begin
  if FDialog.Execute then ExecutePacketFile(FDialog.FileName);
end;

{ ЦЕ НЕ ВИКОНАННЯ .sens: архів G5.21 містить результати викликів,
  а не AST програми. Доступний навіть без pinned runtime.
  Декодування і фізичні координати — лише чинний wsm.physloc. }
function TCore4Window.InspectAnswerArchive(const Path:String):Boolean;
var Stream:TFileStream;Physical:RawByteString;
    Words:TExactWords;Spans:TPhysicalWordSpans;
    I:SizeInt;
begin
  Result:=False;
  ClearResult;
  ClearPacket;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('архів має бути фізичним файлом .sens');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxCallBytes) then
        raise Exception.Create('архів порожній або завеликий');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    DecodeT5MWithLocations(Physical,Words,Spans);
    if (Length(Words)<1) or (Length(Words)>MaxPacketForms) then
      raise Exception.Create('архів повинен містити 1..64 фізичні слова');
    { Публікація всіх рядків відбувається лише після повного
      канонічного T5M admission і перевірки меж. }
    FPacketGrid.RowCount:=Length(Words)+1;
    for I:=0 to High(Words) do begin
      FPacketGrid.Cells[0,I+1]:=IntToStr(I+1);
      FPacketGrid.Cells[1,I+1]:=IntToStr(Spans[I].WordIndex);
      FPacketGrid.Cells[2,I+1]:='W'+IntToStr(Length(Words[I]));
      FPacketGrid.Cells[3,I+1]:=String(Words[I]);
      FPacketGrid.Cells[4,I+1]:='трит '+
        IntToStr(Spans[I].TritStart)+'; байт '+
        IntToStr(Spans[I].ByteStart);
    end;
    FPacketCount:=Length(Words);
    FFile.Caption:='Оглянуто архів: '+ExtractFileName(Path);
    FAnswer.Caption:='Фізичних слів у знімку: '+IntToStr(FPacketCount);
    FStatus.Caption:='Лише огляд готових двійкових відповідей без виконання; '+
      'Wn — фізична ширина, не домен Dn.';
    { Не додаємо до історії виконання: це тільки host-огляд. }
    Result:=True;
  except on E:Exception do begin
    ClearResult;
    ClearPacket;
    FStatus.Caption:='Відмова огляду архіву: '+E.Message;
  end end;
end;

procedure TCore4Window.ArchiveClick(Sender:TObject);
begin
  if FArchiveDialog.Execute then
    InspectAnswerArchive(FArchiveDialog.FileName);
end;

procedure TCore4Window.OpenClick(Sender:TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

procedure TCore4Window.BatchClick(Sender:TObject);
begin
  if FBatchDialog.Execute then ExecuteBatchFiles(FBatchDialog.Files);
end;

procedure TCore4Window.SavePhysical(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

function TCore4Window.MakeCall(const Id,Arg:RawByteString;
  IncludeArg:Boolean):RawByteString;
var Words:TExactWords; I,N:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('некоректний фізичний D7-ідентифікатор');
  SetLength(Words,Length(Id) div 7+5);
  N:=0;Words[N]:='10';Inc(N);Words[N]:='10';Inc(N);
  for I:=0 to (Length(Id) div 7)-1 do begin
    Words[N]:=Copy(Id,I*7+1,7);Inc(N);
  end;
  Words[N]:='01';Inc(N);
  if IncludeArg then begin Words[N]:=Arg;Inc(N) end;
  Words[N]:='01';Inc(N);SetLength(Words,N);
  Result:=EncodeT5M(Words);
end;

function TCore4Window.MakeIdentifier(const Id:RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('некоректне фізичне ім’я');
  SetLength(Words,Length(Id) div 7+2);
  Words[0]:='10';
  for I:=0 to (Length(Id) div 7)-1 do
    Words[I+1]:=Copy(Id,I*7+1,7);
  Words[High(Words)]:='01';
  Result:=EncodeT5M(Words);
end;

procedure TCore4Window.SelfCheck(const Root,TempDir:String);
var Id,Path,PacketPath:RawByteString;
    SyntaxWords:TExactWords;
    Calls:array of RawByteString;
    I:SizeInt;
    Files:TStringList; BatchA,BatchB,BatchC:String;
begin
  Need(LoadAuthority(Root),'завантаження справжнього pinned core4.sens');
  Id:=FRuntime.FirstDefinitionIdentifier;
  Need(Length(Id)>0,'точне ім’я із pinned Core4');
  Path:=IncludeTrailingPathDelimiter(TempDir)+'виклик.sens';
  SavePhysical(String(Path),MakeCall(Id,'1'));
  Need(ExecuteFile(String(Path)) and (FResultBits='1') and
    (FHistoryCount=1) and (FHistory.Cells[3,1]='W1') and
    (FHistory.Cells[4,1]='1') and
    (Pos('W1',FAnswer.Caption)>0) and (Pos('D1',FAnswer.Caption)=0),
    'реальне виконання D1:1 з фізичною шириною W1, без підміни D1');
  SavePhysical(String(Path),MakeCall(Id,'0'));
  Need(ExecuteFile(String(Path)) and (FResultBits='0'),
    'повторний виклик D1:0 у тому самому runtime');
  SavePhysical(String(Path),MakeCall(Id,'000000000000000000000001'));
  Need(ExecuteFile(String(Path)) and
    (FResultBits='000000000000000000000001') and
    (FHistory.Cells[3,FHistoryCount]='W24') and
    (FHistory.Cells[4,FHistoryCount]='000000000000000000000001') and
    (Pos('W24',FAnswer.Caption)>0) and (Pos('D24',FAnswer.Caption)=0),
    '24 біти залишаються W24, без вигаданого D24 admission');
  SavePhysical(String(Path),MakeIdentifier(FRuntime.BindingIdentifier(2)));
  Need(ExecuteFile(String(Path)) and
    (FResultBits='000000000000000000000001'),
    'читання реального pinned D24-глобала');
  SavePhysical(String(Path),MakeCall(Id,'',False));
  Need(not ExecuteFile(String(Path)) and (FResultBits='') and
    (FAnswer.Caption='') and
    (FHistory.Cells[2,FHistoryCount]='відхилено') and
    (FHistory.Cells[3,FHistoryCount]='') and
    (FHistory.Cells[4,FHistoryCount]=''),
    'відмова за неправильною арністю не повторює попередні біти');
  SavePhysical(String(Path),Chr(243));
  Need(not ExecuteFile(String(Path)) and (FResultBits=''),
    'зіпсований фізичний T5M не дає відповіді');
  SavePhysical(String(Path),'');
  Need(not ExecuteFile(String(Path)) and (FResultBits=''),
    'порожній фізичний файл не дає відповіді');
  SavePhysical(IncludeTrailingPathDelimiter(TempDir)+'людський.lisp',
    MakeCall(Id,'1'));
  Need(not ExecuteFile(IncludeTrailingPathDelimiter(TempDir)+'людський.lisp'),
    'людський .lisp не є фізичним викликом');
  Need(not ExecuteFile(IncludeTrailingPathDelimiter(TempDir)+'немає.sens'),
    'відсутній файл відхилено');
  SavePhysical(String(Path),MakeCall(Id,'1'));
  Need(ExecuteFile(String(Path)) and (FResultBits='1'),
    'відновлення після помилок у тій самій LCL-сесії');
  { Перевіряємо, що історія не росте безмежно, але той самий runtime
    виконує фізичні форми після негативних викликів. }
  while FHistoryCount<MaxHistoryRows do
    Need(ExecuteFile(String(Path)), 'заповнення обмеженої історії');
  Need((FHistoryCount=MaxHistoryRows) and
    (FHistory.Cells[2,MaxHistoryRows]='виконано'),
    '32 фізичні записи в таблиці');
  Need(ExecuteFile(String(Path)) and (FHistoryCount=MaxHistoryRows) and
    (FHistory.Cells[0,MaxHistoryRows]='32') and
    (FHistory.Cells[3,MaxHistoryRows]='W1'),
    'виштовхування найстарішого запису без росту таблиці');
  Need(LoadAuthority(Root) and (FHistoryCount=0) and
    (FHistory.Cells[4,1]=''), 'повторне завантаження Core4 очищає історію');
  Need(not LoadAuthority(TempDir) and (FHistoryCount=0) and
    (FAnswer.Caption='') and (not FOpen.Enabled),
    'відмова завантаження Core4 не показує старі свідки');
  Need(LoadAuthority(Root) and ExecuteFile(String(Path)) and
    (FHistoryCount=1), 'відновлення після помилки завантаження');
  { Реальні бінарні файли з визначень завантаженого pinned Core4.
    До завершення всіх трьох результат у grid не публікується. }
  BatchA:=IncludeTrailingPathDelimiter(TempDir)+'пакет-а.sens';
  BatchB:=IncludeTrailingPathDelimiter(TempDir)+'пакет-б.sens';
  BatchC:=IncludeTrailingPathDelimiter(TempDir)+'пакет-в.sens';
  SavePhysical(BatchA,MakeCall(FRuntime.FirstDefinitionIdentifier,'1'));
  SavePhysical(BatchB,MakeCall(FRuntime.FirstDefinitionIdentifier,
    '000000000000000000000001'));
  SavePhysical(BatchC,MakeCall(FRuntime.FirstDefinitionIdentifier,'0'));
  Files:=TStringList.Create;
  try
    Files.Add(BatchA);Files.Add(BatchB);Files.Add(BatchC);
    Need(ExecuteBatchFiles(Files) and (FHistoryCount=4) and
      (FResultBits='0') and
      (FHistory.Cells[4,2]='1') and
      (FHistory.Cells[3,3]='W24') and
      (FHistory.Cells[4,3]='000000000000000000000001') and
      (FHistory.Cells[4,4]='0') and
      (Pos('W1',FAnswer.Caption)>0) and
      (Pos('D24',FAnswer.Caption)=0),
      'справжні три фізичні виклики без домену з довжини');
    SavePhysical(BatchC,Chr(243));
    Need((not ExecuteBatchFiles(Files)) and (FHistoryCount=5) and
      (FResultBits='') and (FAnswer.Caption='') and
      (FHistory.Cells[2,5]='відхилено') and
      (FHistory.Cells[4,5]='') and
      (FHistory.Cells[4,4]='0'),
      'пізня помилка не публікує часткових результатів');
    SavePhysical(BatchC,MakeCall(FRuntime.FirstDefinitionIdentifier,'0'));
    Need(ExecuteBatchFiles(Files) and (FHistoryCount=8) and
      (FHistory.Cells[4,8]='0'),'відновлення тієї ж Core4-сесії');
    Files.Clear;
    Need((not ExecuteBatchFiles(Files)) and (FHistoryCount=9) and
      (FResultBits=''),'порожній пакет відхилено');
    Files.Add(BatchA);
    Files.Add(IncludeTrailingPathDelimiter(TempDir)+'немає-пакета.sens');
    Need((not ExecuteBatchFiles(Files)) and (FHistoryCount=10) and
      (FHistory.Cells[2,10]='відхилено'),
      'відсутній другий файл не друкує перший');
    Files[1]:=IncludeTrailingPathDelimiter(TempDir)+'людський.lisp';
    Need((not ExecuteBatchFiles(Files)) and (FHistoryCount=11),
      'людська проєкція не стає машинним викликом');
    Files.Clear;
    while Files.Count<9 do Files.Add(BatchA);
    Need((not ExecuteBatchFiles(Files)) and (FHistoryCount=12),
      'дев’ять файлів перевищують межу восьми');
    Files.Clear;Files.Add(BatchA);
    Need(not LoadAuthority(TempDir) and (not FBatch.Enabled) and
      (FHistoryCount=0),'втрата pinned authority скидає стан групи');
    Need(LoadAuthority(Root) and FBatch.Enabled and
      ExecuteBatchFiles(Files) and (FHistoryCount=1) and
      (FHistory.Cells[4,1]='1'),
      'група відновлена після повторного завантаження authority');
  finally Files.Free end;
  { Новий G4.15: ті самі реально завантажені визначення pinned
    core4.sens, але три фізичні виклики через один LCL-сеанс. }
  PacketPath:=IncludeTrailingPathDelimiter(TempDir)+'пакет.sens';
  SetLength(Calls,3);
  Calls[0]:=MakeCall(Id,'1');
  Calls[1]:=MakeCall(Id,'0');
  Calls[2]:=MakeIdentifier(FRuntime.BindingIdentifier(2));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need(ExecutePacketFile(String(PacketPath)) and
    (FPacketCount=3) and (FPacketGrid.RowCount=4) and
    (FPacketGrid.Cells[1,1]='1') and
    (FPacketGrid.Cells[3,1]='1') and
    (FPacketGrid.Cells[3,2]='0') and
    (FPacketGrid.Cells[2,3]='W24') and
    (FPacketGrid.Cells[3,3]='000000000000000000000001') and
    (FPacketGrid.Cells[1,3]<>'1') and
    (Pos('байт ',FPacketGrid.Cells[4,3])>0),
    'Lazarus пакет: три справжні Core4-форми, exact W24 і координати');
  { Пізня помилка не публікує навіть два раніше обчислених результати. }
  Calls[2]:=MakeCall(Id,'',False);
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need((not ExecutePacketFile(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]='') and
    (FAnswer.Caption='') and
    (FHistory.Cells[2,FHistoryCount]='пакет відхилено') and
    (Pos('форма 3',FStatus.Caption)>0),
    'пізня відмова третьої форми не витікає у Lazarus грид');
  SetLength(Calls,65);
  for I:=0 to High(Calls) do Calls[I]:=MakeCall(Id,'1');
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need((not ExecutePacketFile(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]=''),
    '65 фізичних форм — відмова без часткового результату');
  SetLength(Calls,3);
  Calls[0]:=MakeCall(Id,'1');
  Calls[1]:=MakeCall(Id,'0');
  Calls[2]:=MakeIdentifier(FRuntime.BindingIdentifier(2));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need(ExecutePacketFile(String(PacketPath)) and (FPacketCount=3),
    'відновлення пакетного LCL-виконання після відмов');
  { G4.19: дві КАНОНІЧНІ фізичні T5M-структури, що мають пізню
    СИНТАКСИЧНУ помилку D2 після двох справжніх викликів.
    Піновані exact назви забезпечують перевірений word31/word33
    і точні тритові та байтові координати від початку файла. }
  Calls[0]:=MakeCall(Id,'1');
  Calls[1]:=MakeCall(Id,'0');
  SetLength(SyntaxWords,1); SyntaxWords[0]:='01';
  Calls[2]:=EncodeT5M(SyntaxWords);
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need((not ExecutePacketFile(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]='') and
    (FAnswer.Caption='') and
    (FHistory.Cells[2,FHistoryCount]='пакет відхилено') and
    (Pos('помилка D2: слово=31 трити=[188,190) байти=[37,38) EOF=ні',
      FStatus.Caption)>0),
    'пізнє D2 закриття: точна координата, без часткових рядків');
  SetLength(SyntaxWords,2);
  SyntaxWords[0]:='10'; SyntaxWords[1]:='1';
  Calls[2]:=EncodeT5M(SyntaxWords);
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need((not ExecutePacketFile(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]='') and
    (FAnswer.Caption='') and
    (FHistory.Cells[2,FHistoryCount]='пакет відхилено') and
    (Pos('помилка D2: слово=33 трити=[192,192) байти=[39,39) EOF=так',
      FStatus.Caption)>0),
    'D2 незавершений список: справжня точка EOF, без рядків');
  Calls[2]:=MakeIdentifier(FRuntime.BindingIdentifier(2));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need(ExecutePacketFile(String(PacketPath)) and
    (FPacketCount=3) and
    (FPacketGrid.Cells[3,3]='000000000000000000000001'),
    'відновлення pinned Core4 після обох синтаксичних відмов');
  Need(LoadAuthority(Root) and (FPacketCount=0) and
    (FPacketGrid.Cells[3,1]=''), 're-load очищає LCL пакет');
  { Архів G5.21: тільки СПРАВЖНІ відповіді вже завантаженого
    pinned Core4 runtime. Немає декодування українських назв у виклик. }
  PacketPath:=IncludeTrailingPathDelimiter(TempDir)+'відповіді.sens';
  SetLength(Calls,3);
  Calls[0]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,'1'));
  Calls[1]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,
    '000000000000000000000001'));
  Calls[2]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,'0'));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need(InspectAnswerArchive(String(PacketPath)) and
    (FPacketCount=3) and (FPacketGrid.RowCount=4) and
    (FPacketGrid.Cells[1,1]='1') and (FPacketGrid.Cells[2,1]='W1') and
    (FPacketGrid.Cells[3,1]='1') and
    (FPacketGrid.Cells[2,2]='W24') and
    (FPacketGrid.Cells[3,2]='000000000000000000000001') and
    (FPacketGrid.Cells[4,1]='трит 0; байт 0') and
    (FPacketGrid.Cells[4,2]='трит 2; байт 0') and
    (FPacketGrid.Cells[4,3]='трит 27; байт 5') and
    (Pos('без виконання',FStatus.Caption)>0) and
    (Pos('D24',FStatus.Caption)=0),
    'збережено всі біти, W24 і початки тритів/байтів з архіву');
  { Зіпсований контейнер не показує жодного раніше видимого слова. }
  SavePhysical(String(PacketPath),Chr(243));
  Need((not InspectAnswerArchive(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]='') and
    (FAnswer.Caption='') and (FResultBits=''),
    'неправильний T5M повністю очищає табличний огляд');
  SetLength(Calls,65);
  for I:=0 to High(Calls) do
    Calls[I]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,'1'));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need((not InspectAnswerArchive(String(PacketPath))) and
    (FPacketCount=0) and (FPacketGrid.Cells[3,1]=''),
    '65 результатів — відхилення без часткового рядка');
  SavePhysical(String(PacketPath),'');
  Need(not InspectAnswerArchive(String(PacketPath)),
    'порожній фізичний архів відхилено');
  Need(not InspectAnswerArchive(IncludeTrailingPathDelimiter(TempDir)+
    'людський.lisp'), 'людська проєкція не є фізичним архівом');
  Need(not InspectAnswerArchive(IncludeTrailingPathDelimiter(TempDir)+
    'невідомий-архів.sens'), 'відсутній архів відхилено');
  SetLength(Calls,3);
  Calls[0]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,'1'));
  Calls[1]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,
    '000000000000000000000001'));
  Calls[2]:=FRuntime.ExecutePhysicalCall(MakeCall(Id,'0'));
  SavePhysical(String(PacketPath),PacketPhysical(Calls));
  Need(InspectAnswerArchive(String(PacketPath)) and
    (FPacketCount=3),'відновлення фізичного огляду після відмови');
  Need(not LoadAuthority(TempDir) and
    InspectAnswerArchive(String(PacketPath)) and
    (FPacketCount=3) and (not FOpen.Enabled) and
    FArchiveButton.Enabled,
    'архів читається навіть без мовного runtime');
  Need(LoadAuthority(Root) and (FPacketCount=0) and
    ExecuteFile(String(Path)),
    'перевірити збереження виконання після повернення authority');
  WriteLn('LCL-CORE4-АРХІВ-ГАРАЗД слів=3 W1-W24-W1 ',
    'координати=точні відмова=атомарно runtime=не-потрібен');
  WriteLn('LCL-CORE4-D2-АДРЕСА-ГАРАЗД close=31 eof=33 трити=точні атомарно=так');
  WriteLn('LCL-CORE4-ПАКЕТ-ГАРАЗД форм=3 атомарно=так межа=64');
  WriteLn('LCL-CORE4-ГРУПА-ГАРАЗД файлів=3 W24=не-домен ',
    'пізня-відмова=атомарно повторне-виконання=так межа=8');
  WriteLn('LCL-CORE4-ГАРАЗД Lazarus=GTK2 pinned=core4.sens ',
    'визначень=3 викликів=5 відмов=4 відновлення=так ',
    'D24=точні-біти Wn=не-домен історія=32 REPL=ні');
end;

begin
  Application.Initialize;
  Application.Title:='SENS — виконання початкового Core4';
  Application.CreateForm(TCore4Window,Window);
  if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>3 then Halt(64);
    try
      Window.Show;Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3));
    except on E:Exception do begin
      WriteLn(StdErr,'LCL-CORE4-ПОМИЛКА ',E.Message);
      Halt(1);
    end end;
  end else begin
    if ParamCount=0 then Window.LoadAuthority(GetCurrentDir)
    else Window.LoadAuthority(ParamStr(1));
    Application.Run;
  end;
end.