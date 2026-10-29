{ G1.49 — справжній Lazarus-огляд pinned фізичного Core1.
  Це ТІЛЬКИ структурний T5M/D2 + source projection, без evaluator.
  Ідентичність і закон належать external/sens Contract 12.
  Українська укр назва є окремою позиційною проєкцією, не dispatch. }
program core1_fizychni_koreni;
{$mode objfpc}{$H+}{$codepage utf8}

uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Grids,
  wsm.t5m, wsm.d2source, wsm.physloc, wsm.source;

const MaxCore1Bytes = 4 * 1024 * 1024;
      MaxDisplayWords = 20;
type
  ECore1Visual = class(Exception);
  TRootEvidence = record
    Span:TPhysicalNodeSpan;
    Ukrainian:RawByteString; { лише позиційна укр проєкція для людини }
  end;
  TRootEvidences = array of TRootEvidence;

  TCore1Window = class(TForm)
  private
    FReload:TButton;
    FStatus:TLabel;
    FRows:TStringGrid;
    FDetails:TMemo;
    FRepository:String;
    FPhysical:RawByteString;
    FWords:TExactWords;
    FEvidence:TRootEvidences;
    FReady:Boolean;
    procedure ClearEvidence;
    procedure ReloadClick(Sender:TObject);
    procedure SelectCell(Sender:TObject; ACol,ARow:Integer;
      var CanSelect:Boolean);
    procedure ShowRoot(Index:SizeInt);
    function ReadBounded(const Filename:String):RawByteString;
    function HasD7Identifier(Node:TD2Node):Boolean;
  public
    constructor Create(AOwner:TComponent); override;
    function LoadPaths(const PhysicalPath,ProjectionPath:String):Boolean;
    procedure LoadRepository(const Root:String);
    procedure SelfTest(const Root,BadPhysical,BadProjection:String);
  end;
var Window:TCore1Window;

procedure Need(Condition:Boolean;const Problem:String);
begin
  if not Condition then raise ECore1Visual.Create(Problem);
end;

constructor TCore1Window.Create(AOwner:TComponent);
var Intro:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Width:=1360;Height:=760;Position:=poScreenCenter;
  Caption:='SENS — фізичні визначення Core1';
  FRepository:='';FReady:=False;
  Intro:=TLabel.Create(Self);Intro.Parent:=Self;
  Intro.SetBounds(14,12,1310,64);Intro.AutoSize:=False;Intro.WordWrap:=True;
  Intro.Caption:='Фізична бібліотека Core1: канонічний .sens із pinned SENS. '+
    'Людські назви укр показано поруч за порядком форм: це не доказ '+
    'тотожності, викличності або закону. Числа індексів — host, не D12+.';
  FReload:=TButton.Create(Self);FReload.Parent:=Self;
  FReload.SetBounds(14,80,320,35);
  FReload.Caption:='Перевірити pinned Core1';
  FReload.OnClick:=@ReloadClick;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(350,82,976,70);
  FStatus.AutoSize:=False;FStatus.WordWrap:=True;
  FRows:=TStringGrid.Create(Self);FRows.Parent:=Self;
  FRows.SetBounds(14,160,1310,360);
  FRows.ColCount:=5;FRows.RowCount:=2;
  FRows.FixedCols:=0;FRows.FixedRows:=1;
  FRows.Options:=FRows.Options-[goEditing];
  FRows.ColWidths[0]:=85;
  FRows.ColWidths[1]:=300;
  FRows.ColWidths[2]:=225;
  FRows.ColWidths[3]:=105;
  FRows.ColWidths[4]:=555;
  FRows.Cells[0,0]:='№ кореня';
  FRows.Cells[1,0]:='укр (позиційна проєкція)';
  FRows.Cells[2,0]:='Слова [від,до)';
  FRows.Cells[3,0]:='Слів';
  FRows.Cells[4,0]:='Трити й байти [від,до)';
  FRows.OnSelectCell:=@SelectCell;
  FDetails:=TMemo.Create(Self);FDetails.Parent:=Self;
  FDetails.SetBounds(14,530,1310,165);
  FDetails.ReadOnly:=True;
  FDetails.ScrollBars:=ssVertical;
  ClearEvidence;
end;

procedure TCore1Window.ClearEvidence;
var I,J:SizeInt;
begin
  FReady:=False;
  FPhysical:='';
  SetLength(FWords,0);
  SetLength(FEvidence,0);
  for I:=1 to FRows.RowCount-1 do
    for J:=0 to FRows.ColCount-1 do FRows.Cells[J,I]:='';
  FRows.RowCount:=2;
  FDetails.Clear;
  FStatus.Caption:='Немає перевірених фізичних форм Core1; виконання=НІ.';
end;

function TCore1Window.ReadBounded(const Filename:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxCore1Bytes) then
      raise ECore1Visual.Create('порожній або надмірний файл Core1');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function TCore1Window.HasD7Identifier(Node:TD2Node):Boolean;
var I:SizeInt;
begin
  Result:=(Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=256);
  if not Result then Exit;
  for I:=0 to High(Node.Children) do
    if (Node.Children[I]=nil) or
       (Node.Children[I].Kind<>dkIdentity) or
       (Node.Children[I].Width<>7) then Exit(False);
end;

{ G1.49: source і physical є двома НЕЗАЛЕЖНИМИ власними byte buffers.
  Words, Spans, Doc і UkrDoc — тимчасові; TForm бере тільки копії
  exact TExactWords, позиційних імен та TPhysicalNodeSpan, не TD2Node*.
  Ключ першого D7 перевіряється як точний W7 список; сам напис укр
  не визначає закон та не використаний як dispatch.
  Вихід — лише UI-доказ після ПОВНОГО допуску обох файлів.
  Питання: 1) Чому ширина W7 не визначає викличність?
  2) Чому тритові координати точніші за байтові межі T5M?
  3) Хто звільняє TD2Document у разі пізньої помилки?
  4) Чому укр назву в таблиці позначено позиційною, а не законом? }
function TCore1Window.LoadPaths(const PhysicalPath,
  ProjectionPath:String):Boolean;
var
  Physical,Projection:RawByteString;
  Words:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  UkrDoc:TSourceDocument;
  Candidate:TRootEvidences;
  I:SizeInt;
  Root,Lambda,Parameters:TD2Node;
  SourceRoot:TSourceNode;
begin
  ClearEvidence;
  Result:=False;Doc:=nil;UkrDoc:=nil;
  try
    try
      Physical:=ReadBounded(PhysicalPath);
      Projection:=ReadBounded(ProjectionPath);
      DecodeT5MWithLocations(Physical,Words,Spans);
      Need(EncodeT5M(Words)=Physical,
        'фізичний T5M не проходить побайтовий перепис');
      Doc:=ParseD2WordsWide(Words);
      UkrDoc:=ReadUkrainianSource(Projection);
      Need((Length(Doc.Roots)>0) and (Length(Doc.Roots)<=1024),
        'кількість фізичних D2 форм поза межею інспектора');
      Need(Length(Doc.Roots)=Length(UkrDoc.Forms),
        'кількість фізичних і укр форм не збігається');
      Root:=Doc.Roots[0];
      Need((Root<>nil) and (Root.Kind=dkList) and
        (Length(Root.Children)=3),
        'перший фізичний корінь Core1 не є визначенням');
      Need((Root.Children[0]<>nil) and
        (Root.Children[0].Kind=dkIdentity) and
        (Root.Children[0].Width=4) and
        (Root.Children[0].Bits='0011'),
        'немає pinned D4:0011 першого визначення');
      Need(HasD7Identifier(Root.Children[1]),
        'ім’я першого визначення не складається з exact D7');
      Lambda:=Root.Children[2];
      Need((Lambda<>nil) and (Lambda.Kind=dkList) and
        (Length(Lambda.Children)=3),
        'перший Core1 lambda має некоректну рамку');
      Need((Lambda.Children[0]<>nil) and
        (Lambda.Children[0].Kind=dkIdentity) and
        (Lambda.Children[0].Width=4) and
        (Lambda.Children[0].Bits='0010'),
        'немає pinned D4:0010 першого замикання');
      Parameters:=Lambda.Children[1];
      Need((Parameters<>nil) and (Parameters.Kind=dkList) and
        (Length(Parameters.Children)=1) and
        HasD7Identifier(Parameters.Children[0]),
        'перший параметр Core1 не exact D7');
      SetLength(Candidate,Length(Doc.Roots));
      for I:=0 to High(Doc.Roots) do begin
        Need((Doc.Roots[I]<>nil) and
          (Doc.Roots[I].WordIndex>=1) and
          (Doc.Roots[I].EndWordIndexExclusive>
            Doc.Roots[I].WordIndex),
          'порожня або пошкоджена фізична рамка');
        Candidate[I].Span:=LocatePhysicalNodeSpan(Physical,Spans,
          Doc.Roots[I]);
        SourceRoot:=UkrDoc.Forms[I];
        Candidate[I].Ukrainian:='(без атомного імені)';
        if (SourceRoot<>nil) and (SourceRoot.Kind=skList) and
           (Length(SourceRoot.Children)>=2) and
           (SourceRoot.Children[1]<>nil) and
           (SourceRoot.Children[1].Kind=skAtom) then
          Candidate[I].Ukrainian:=SourceRoot.Children[1].Text;
      end;
      { Коміт результату — лише після останньої фізичної і
        текстової перевірки: невдалий ввід не залишає пів таблиці. }
      FPhysical:=Physical;
      FWords:=Words;
      FEvidence:=Candidate;
      FRows.RowCount:=Length(FEvidence)+1;
      for I:=0 to High(FEvidence) do begin
        FRows.Cells[0,I+1]:=IntToStr(I+1);
        FRows.Cells[1,I+1]:=String(FEvidence[I].Ukrainian);
        FRows.Cells[2,I+1]:='['+
          IntToStr(FEvidence[I].Span.WordStart)+','+
          IntToStr(FEvidence[I].Span.WordEndExclusive)+')';
        FRows.Cells[3,I+1]:=IntToStr(
          FEvidence[I].Span.WordEndExclusive-
          FEvidence[I].Span.WordStart);
        FRows.Cells[4,I+1]:='трит ['+
          IntToStr(FEvidence[I].Span.TritStart)+','+
          IntToStr(FEvidence[I].Span.TritEnd)+') байт ['+
          IntToStr(FEvidence[I].Span.ByteStart)+','+
          IntToStr(FEvidence[I].Span.ByteEnd)+')';
      end;
      FReady:=True;
      FStatus.Caption:='Core1 допущено: коренів='+IntToStr(Length(FEvidence))+
        ', точних слів='+IntToStr(Length(FWords))+
        ', T5M=побайтово. Виконання=НІ.';
      ShowRoot(0);
      Result:=True;
    except
      on E:Exception do begin
        ClearEvidence;
        FStatus.Caption:='CORE1-ВІДХИЛЕНО: '+E.Message+
          '. Виконання=НІ.';
      end;
    end;
  finally
    Doc.Free;
    UkrDoc.Free;
  end;
end;

procedure TCore1Window.ShowRoot(Index:SizeInt);
var I,Finish:SizeInt; Span:TPhysicalNodeSpan;
begin
  FDetails.Clear;
  if not FReady or (Index<0) or (Index>=Length(FEvidence)) then Exit;
  Span:=FEvidence[Index].Span;
  FDetails.Lines.Add('Фізичний корінь '+IntToStr(Index+1)+
    ' | укр (лише позиційна проєкція): '+String(FEvidence[Index].Ukrainian));
  FDetails.Lines.Add('Слова ['+IntToStr(Span.WordStart)+','+
    IntToStr(Span.WordEndExclusive)+') — точно; трити ['+
    IntToStr(Span.TritStart)+','+IntToStr(Span.TritEnd)+') — точно.');
  FDetails.Lines.Add('Байти ['+IntToStr(Span.ByteStart)+','+
    IntToStr(Span.ByteEnd)+') — фізична оболонка.');
  Finish:=Span.WordStart+MaxDisplayWords-1;
  if Finish>=Span.WordEndExclusive then
    Finish:=Span.WordEndExclusive-1;
  for I:=Span.WordStart to Finish do
    FDetails.Lines.Add(IntToStr(I)+': W'+
      IntToStr(Length(FWords[I-1]))+':'+String(FWords[I-1]));
  if Finish+1<Span.WordEndExclusive then
    FDetails.Lines.Add('Показано лише перші '+
      IntToStr(MaxDisplayWords)+' точних слів; без втрати у FWords.');
end;

procedure TCore1Window.SelectCell(Sender:TObject; ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  if FReady and (ARow>=1) and (ARow<=Length(FEvidence)) then
    ShowRoot(ARow-1);
end;

procedure TCore1Window.ReloadClick(Sender:TObject);
begin
  if FRepository<>'' then LoadRepository(FRepository);
end;

procedure TCore1Window.LoadRepository(const Root:String);
var Prefix:String;
begin
  FRepository:=Root;
  Prefix:=IncludeTrailingPathDelimiter(ExpandFileName(Root))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim;
  LoadPaths(Prefix+'core1.sens',Prefix+'core1.lisp');
end;

procedure TCore1Window.SelfTest(const Root,BadPhysical,
  BadProjection:String);
var SourcePhysical,SourceProjection,Prefix:String;
    N,WordCount,FirstStart,LastEnd:SizeInt;
begin
  Prefix:=IncludeTrailingPathDelimiter(ExpandFileName(Root))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim;
  SourcePhysical:=Prefix+'core1.sens';
  SourceProjection:=Prefix+'core1.lisp';
  Need(LoadPaths(SourcePhysical,SourceProjection),
    'не допущено справжній pinned Core1');
  N:=Length(FEvidence);WordCount:=Length(FWords);
  Need((N=96) and (WordCount=31569),
    'очікуваний pinned фізичний Core1 змінився — оновіть докази');
  Need((FEvidence[0].Span.WordStart=1) and
    (FEvidence[N-1].Span.WordEndExclusive=WordCount+1),
    'втрачені 1-based фізичні межі першого/останнього кореня');
  Need(FEvidence[0].Ukrainian='ядро1-другий-елемент',
    'не відображено українську назву першої форми');
  Need(Pos('0011',FDetails.Text)>0,
    'перший реальний D4 DEFINE не показано у деталях');
  ShowRoot(N-1);
  Need(Pos('Фізичний корінь 96',FDetails.Text)>0,
    'вибір останнього кореня не оновив вікно');
  Need(not LoadPaths(BadPhysical,SourceProjection) and
    (not FReady) and (Length(FWords)=0) and
    (Length(FEvidence)=0) and (FDetails.Text='') and
    (FRows.Cells[1,1]=''),
    'зіпсований T5M залишив часткові GUI-дані');
  Need(not LoadPaths(SourcePhysical,BadProjection) and
    (not FReady) and (Length(FWords)=0) and
    (Length(FEvidence)=0) and (FDetails.Text=''),
    'зіпсована укр проєкція залишила фізичний snapshot');
  Need(not LoadPaths(BadPhysical+'.немає',SourceProjection) and
    (not FReady) and (Length(FEvidence)=0),
    'відсутній .sens не відхилено');
  Need(LoadPaths(SourcePhysical,SourceProjection) and
    (Length(FEvidence)=N) and (Length(FWords)=WordCount),
    'повторний повний фізичний допуск Core1 не відновився');
  WriteLn('LCL-CORE1-КОРЕНІ-ГАРАЗД pinned=так Lazarus=GTK2 ',
    'коренів=',N,' слів=',WordCount,
    ' D4=0011/0010 D7=exact укр=позиційна T5M=побайтово ',
    'негативні=3 очищення=так відновлення=так виконання=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — огляд фізичних коренів Core1';
    Application.CreateForm(TCore1Window,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>4 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>1 then
      raise ECore1Visual.Create(
        'використання: core1-fizychni-koreni КОРІНЬ або --самоперевірка');
    Window.LoadRepository(ParamStr(1));
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-CORE1-КОРЕНІ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
