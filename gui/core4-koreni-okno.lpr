{ G4.35 — Lazarus-огляд РЕАЛЬНО виконаних змішаних Core4 D2-коренів.
  Закони — pinned SENS; єдиний виконавець — wsm.core4multiroot.
  W24 лише фізична ширина, НЕ автоматичний числовий D24. }
program core4_koreni_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  Dialogs, Grids, ComCtrls, wsm.core4runtime, wsm.core4multiroot, wsm.t5m,
  wsm.d2source{$IFDEF UNIX},cwstring{$ENDIF};

type
  TRootView=record
    LabelText, CountText, ExactText: String;
  end;
  TRootViews=array of TRootView;
  { Лише pending відображення перевірених вузлів із локального Doc.
    Ні TTreeNode, ні pending stack не володіє TD2Node. }
  TTreePending=record
    Value:TD2Node;
    Parent:TTreeNode;
  end;

  TCore4RootsWindow=class(TForm)
  private
    FRuntime:TCore4Runtime; { власне довгоживуче pinned середовище }
    FInput:TEdit;
    FPick,FExecute:TButton;
    FStatus:TLabel;
    FResults:TStringGrid;
    FTree:TTreeView; { повна фізична вкладеність D2 }
    FDetails:TMemo; { лише пояснення вибраного вузла }
    FDialog:TOpenDialog;
    FAnswer:RawByteString; { власні канонічні T5M-байти останньої відповіді }
    FRows:SizeInt;
    procedure Need(OK:Boolean;const Why:String);
    procedure ClearResults;
    procedure InputChanged(Sender:TObject);
    procedure PickClick(Sender:TObject);
    procedure ExecuteClick(Sender:TObject);
    procedure TreeChanged(Sender:TObject;Node:TTreeNode);
    procedure RenderExactTree(const Doc:TD2Document);
    function ReadPhysical(const Path:String):RawByteString;
    function ExecuteFile(const Path:String):Boolean;
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const Root:String);
    procedure SelfTest(const Good,Expected,Late,Broken:String);
  end;

var Window:TCore4RootsWindow;

constructor TCore4RootsWindow.Create(AOwner:TComponent);
var Intro:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Width:=1440;Height:=750;Position:=poScreenCenter;
  Caption:='SENS — виконані складені корені Core4';
  FRuntime:=nil;FRows:=0;FAnswer:='';
  Intro:=TLabel.Create(Self);Intro.Parent:=Self;
  Intro.SetBounds(16,14,1400,46);Intro.AutoSize:=False;Intro.WordWrap:=True;
  Intro.Caption:='Реальне виконання canonical .sens через pinned Core4: '+
    'кожний результат — один повний незалежний D2-корінь. '+
    'Ширина Wn не задає домен Dn, а D7 є лише даними/ідентифікатором.';
  FInput:=TEdit.Create(Self);FInput.Parent:=Self;
  FInput.SetBounds(16,70,900,30);FInput.OnChange:=@InputChanged;
  FPick:=TButton.Create(Self);FPick.Parent:=Self;
  FPick.SetBounds(930,70,144,30);FPick.Caption:='Обрати .sens';
  FPick.OnClick:=@PickClick;
  FExecute:=TButton.Create(Self);FExecute.Parent:=Self;
  FExecute.SetBounds(1082,70,170,30);FExecute.Caption:='Виконати Core4';
  FExecute.OnClick:=@ExecuteClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичні програми SENS (*.sens)|*.sens';
  FResults:=TStringGrid.Create(Self);FResults.Parent:=Self;
  FResults.SetBounds(16,117,780,464);
  FResults.ColCount:=4;FResults.RowCount:=2;
  FResults.FixedCols:=0;FResults.FixedRows:=1;
  FResults.ColWidths[0]:=85;
  FResults.ColWidths[1]:=190;
  FResults.ColWidths[2]:=110;
  FResults.ColWidths[3]:=505;
  FResults.Options:=FResults.Options-[goEditing];
  FResults.Cells[0,0]:='Корінь';
  FResults.Cells[1,0]:='Фізична форма D2';
  FResults.Cells[2,0]:='Слів';
  FResults.Cells[3,0]:='Повні двійкові слова з D2-рамкою';
  FTree:=TTreeView.Create(Self);FTree.Parent:=Self;
  FTree.SetBounds(812,117,606,308);
  FTree.ReadOnly:=True; FTree.OnChange:=@TreeChanged;
  FDetails:=TMemo.Create(Self);FDetails.Parent:=Self;
  FDetails.SetBounds(812,433,606,148);
  FDetails.ReadOnly:=True; FDetails.ScrollBars:=ssVertical;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(16,592,1400,100);
  FStatus.AutoSize:=False;FStatus.WordWrap:=True;
  ClearResults;
end;

destructor TCore4RootsWindow.Destroy;
begin
  FreeAndNil(FRuntime);
  inherited Destroy;
end;

procedure TCore4RootsWindow.Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('LCL-КОРЕНІ-ПОМИЛКА: '+Why);
end;

procedure TCore4RootsWindow.ClearResults;
var I,J:Integer;
begin
  FRows:=0;FAnswer:='';
  FTree.Items.Clear;FDetails.Clear;
  for I:=1 to FResults.RowCount-1 do
    for J:=0 to FResults.ColCount-1 do FResults.Cells[J,I]:='';
  FResults.RowCount:=2;
  FStatus.Caption:='Немає допущеної фізичної відповіді.';
end;

{ G5.53: тільки структурне дерево ВЖЕ ВИКОНАНОЇ canonical D2 відповіді.
  Стек явний, без рекурсії на похідних крапкових парах (можуть мати
  тисячі послідовних вузлів). Тип, точні біти та 1-based інтервали
  беремо з чинного ParseD2WordsWide, НЕ із написів чи host чисел.
  Doc позичений і живий до кінця ExecuteFile; TTreeNode містить ЛИШЕ
  власний скопійований String, жодного dangling Node.Data. }
procedure TCore4RootsWindow.RenderExactTree(const Doc:TD2Document);
const MaxTreeNodes=20000;
var
  Work:array of TTreePending;
  Used,Count,I,J:SizeInt;
  Item:TTreePending;
  RootNode,Shown:TTreeNode;
  LabelText:String;

  procedure Push(const Value:TD2Node; Parent:TTreeNode);
  var Capacity:SizeInt;
  begin
    Need(Value<>nil,'неприпустимий nil-вузол відповіді D2');
    Need(Used<MaxTreeNodes,'перевищено бюджет вузлів дерева LCL');
    if Used=Length(Work) then begin
      Capacity:=Length(Work);
      if Capacity=0 then Capacity:=16 else Capacity:=Capacity*2;
      if Capacity>MaxTreeNodes then Capacity:=MaxTreeNodes;
      SetLength(Work,Capacity);
    end;
    Work[Used].Value:=Value; Work[Used].Parent:=Parent;
    Inc(Used);
  end;
begin
  Need((Doc<>nil) and (Length(Doc.Roots)>0) and
    (Length(Doc.Roots)<=64),'відсутня структурна відповідь 1..64 D2');
  Used:=0;Count:=0;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    for I:=0 to High(Doc.Roots) do begin
      RootNode:=FTree.Items.AddChild(nil,'Форма '+IntToStr(I+1));
      Push(Doc.Roots[I],RootNode);
      while Used>0 do begin
        Dec(Used);
        Item:=Work[Used];
        Work[Used].Value:=nil;
        Need(Count<MaxTreeNodes,'перевищено бюджет вузлів дерева LCL');
        Inc(Count);
        case Item.Value.Kind of
          dkIdentity:
            LabelText:='W'+IntToStr(Item.Value.Width)+':'+
              String(Item.Value.Bits);
          dkEmpty: LabelText:='W3:000 (точний порожній атом)';
          dkList: LabelText:='D2-список (елементів='+
              IntToStr(Length(Item.Value.Children))+')';
          dkPair: LabelText:='D2-пара (структурний D2:11)';
          else raise Exception.Create('недопущений тип D2 у дереві');
        end;
        LabelText:=LabelText+' слова=['+
          IntToStr(Item.Value.WordIndex)+','+
          IntToStr(Item.Value.EndWordIndexExclusive)+')';
        Shown:=FTree.Items.AddChild(Item.Parent,LabelText);
        for J:=High(Item.Value.Children) downto 0 do
          Push(Item.Value.Children[J],Shown);
      end;
      RootNode.Expand(False);
    end;
  finally FTree.Items.EndUpdate end;
end;

procedure TCore4RootsWindow.TreeChanged(Sender:TObject;Node:TTreeNode);
begin
  FDetails.Clear;
  if Node=nil then Exit;
  FDetails.Lines.Add('Перевірений фізичний вузол після Core4:');
  FDetails.Lines.Add(Node.Text);
  FDetails.Lines.Add('Інтервал слів — 1-based [початок, кінець).');
  FDetails.Lines.Add('Wn — фізична ширина, не закон Dn.');
  FDetails.Lines.Add('Дані D7 і числа D12+ тут не обчислюються.');
end;

procedure TCore4RootsWindow.InputChanged(Sender:TObject);
begin
  ClearResults; { жодного старого snapshot після редагування входу }
end;

procedure TCore4RootsWindow.PickClick(Sender:TObject);
begin
  if FDialog.Execute then FInput.Text:=FDialog.FileName;
end;

procedure TCore4RootsWindow.ExecuteClick(Sender:TObject);
begin
  ExecuteFile(FInput.Text);
end;

procedure TCore4RootsWindow.Connect(const Root:String);
begin
  ClearResults;
  FreeAndNil(FRuntime);
  FRuntime:=TCore4Runtime.Create(Root);
end;

{ Тільки фізичний packed .sens, жодного неявного читання укр .lisp.
  FileStream локальний; текстове ім'я — host шлях, не D7 ідентичність. }
function TCore4RootsWindow.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (LowerCase(ExtractFileExt(Path))<>'.sens') then
    raise Exception.Create('потрібен шлях до фізичного .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('фізичний файл поза межею T5M');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Runtime borrowed, фізичні байти та локальні D2-документи керовані FPC.
  Candidate — неоприлюднений масив рядків; жодна помилка виконання,
  декодера або формування GUI не лишає застарілий результат у таблиці. }
function TCore4RootsWindow.ExecuteFile(const Path:String):Boolean;
const MaxUIWords=8192;MaxUIBytes=65536;
var Source,Answer,Joined:RawByteString;
    Words:TExactWords; Doc:TD2Document;
    Candidate:TRootViews;
    I,J,First,Finish,TotalWords:SizeInt;
begin
  Result:=False;ClearResults;Doc:=nil;
  try
    if FRuntime=nil then raise Exception.Create('не завантажено pinned Core4');
    Source:=ReadPhysical(Path);
    Answer:=ExecuteCore4Roots(FRuntime,Source);
    DecodeT5M(Answer,Words);
    if (Length(Words)<1) or (Length(Words)>MaxUIWords) or
       (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('відповідь поза бюджетом огляду або неканонічна');
    Doc:=ParseD2WordsWide(Words);
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>64) then
      raise Exception.Create('відповідь не містить 1..64 коренів');
    SetLength(Candidate,Length(Doc.Roots));
    TotalWords:=0;
    for I:=0 to High(Doc.Roots) do begin
      First:=Doc.Roots[I].WordIndex-1;
      Finish:=Doc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(Words)) then
        raise Exception.Create('некоректна точна межа кореня');
      Inc(TotalWords,Finish-First);
      Joined:='';
      for J:=First to Finish-1 do begin
        if J>First then Joined:=Joined+' | ';
        if Length(Joined)+Length(Words[J])>MaxUIBytes then
          raise Exception.Create('перевищено бюджет текстового огляду кореня');
        Joined:=Joined+Words[J];
      end;
      if Doc.Roots[I].Kind=dkList then
        Candidate[I].LabelText:='D2-список'
      else if (Doc.Roots[I].Kind=dkIdentity) then
        Candidate[I].LabelText:='атом W'+IntToStr(Length(Words[First]))
      else
        raise Exception.Create('непідтриманий тип D2-кореня в огляді');
      Candidate[I].CountText:=IntToStr(Finish-First);
      Candidate[I].ExactText:=String(Joined);
    end;
    if TotalWords<>Length(Words) then
      raise Exception.Create('втрата фізичного слова між D2-коренями');
    FResults.RowCount:=Length(Candidate)+1;
    for I:=0 to High(Candidate) do begin
      FResults.Cells[0,I+1]:=IntToStr(I+1);
      FResults.Cells[1,I+1]:=Candidate[I].LabelText;
      FResults.Cells[2,I+1]:=Candidate[I].CountText;
      FResults.Cells[3,I+1]:=Candidate[I].ExactText;
    end;
    RenderExactTree(Doc);
    FRows:=Length(Candidate);
    FAnswer:=Answer;
    FStatus.Caption:='Виконано pinned Core4: '+IntToStr(FRows)+
      ' незалежних D2-коренів, '+IntToStr(Length(Words))+
      ' точних фізичних слів. W24 непрозорий, це НЕ загальний REPL.';
    Result:=True;
  except on E:Exception do begin
    ClearResults;
    FStatus.Caption:='Відмовлено без часткової відповіді: '+E.Message;
  end end;
  Doc.Free;
end;

procedure TCore4RootsWindow.SelfTest(const Good,Expected,Late,Broken:String);
const Zero24='000000000000000000000000';
var I:SizeInt;FoundNested:Boolean;
begin
  Need(ExecuteFile(Good),'три справжні Core4-корені не виконалися');
  Need(FRows=3,'втрачено фізичні корені');
  Need(FAnswer=ReadPhysical(Expected),'байти відповіді відрізняються від свідка');
  Need((FResults.Cells[1,1]='атом W1') and
       (FResults.Cells[3,1]='1'),'точний атом першого кореня');
  Need((FResults.Cells[1,2]='D2-список') and
       (FResults.Cells[2,2]='4') and
       (Pos('10 | 1 | '+Zero24+' | 01',FResults.Cells[3,2])>0),
       'список утратив рамку, атом або W24');
  Need((FResults.Cells[1,3]='атом W24') and
       (FResults.Cells[3,3]=Zero24),'opaque W24 глобал');
  { Ієрархія відображає не лише плоскі 4 слова другого кореня,
    а ДВА дочірні значення під D2 списком, включно з exact W24. }
  Need(FTree.Items.Count>=8,'ієрархічне дерево втратило D2 корені');
  FoundNested:=False;
  for I:=0 to FTree.Items.Count-1 do
    if (Pos('W24:'+Zero24,FTree.Items[I].Text)=1) and
       (FTree.Items[I].Parent<>nil) and
       (Pos('D2-список',FTree.Items[I].Parent.Text)=1) then begin
      Need(Pos('слова=[',FTree.Items[I].Text)>0,
        'вкладений W24 не зберіг точну фізичну адресу');
      FTree.Selected:=FTree.Items[I];
      TreeChanged(FTree,FTree.Items[I]);
      Need(Pos(Zero24,FDetails.Text)>0,
        'вибраний непрозорий W24 не видно в деталях');
      FoundNested:=True;
      Break;
    end;
  Need(FoundNested,'список не має вкладеного W24 у справжньому дереві');
  FInput.Text:=Good; { реальна подія зміни тексту очищає snapshot }
  Need((FRows=0) and (FAnswer='') and
       (FResults.Cells[3,1]='') and (FTree.Items.Count=0) and
       (FDetails.Text=''),'вхідне редагування зберегло старий результат');
  Need(not ExecuteFile(Broken),'пошкоджений T5M виконано');
  Need((FRows=0) and (FAnswer='') and
       (FResults.Cells[3,1]='') and (FTree.Items.Count=0) and
       (FDetails.Text=''),'пошкоджений T5M лишив дерево/рядок');
  Need(not ExecuteFile(Late),'пізню невикличну форму виконано');
  Need((FRows=0) and (FAnswer='') and
       (FResults.Cells[3,1]='') and (FTree.Items.Count=0) and
       (FDetails.Text=''),'пізня відмова лишила складений результат');
  Need(ExecuteFile(Good) and (FRows=3) and
       (FAnswer=ReadPhysical(Expected)) and (FTree.Items.Count>=8),
       'після відмови не відновлено виконання та D2 дерево');
  WriteLn('LCL-CORE4-КОРЕНІ-ГАРАЗД pinned=так D2=3 складені=так W24=opaque відмови=очищено GTK2=так дерево=вкладений-W24-адресований відновлення=так');
end;

begin
  Application.Initialize;
  Application.CreateForm(TCore4RootsWindow,Window);
  try
    if (ParamCount=6) and (ParamStr(1)='--самоперевірка') then begin
      Window.Connect(ParamStr(2));
      Window.SelfTest(ParamStr(3),ParamStr(4),ParamStr(5),ParamStr(6));
    end else if ParamCount=1 then begin
      Window.Connect(ParamStr(1));
      Application.Run;
    end else begin
      WriteLn(StdErr,'Виклик: core4-koreni-okno КОРІНЬ або --самоперевірка КОРІНЬ good.sens expected.sens late.sens broken.sens');
      Halt(64);
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-CORE4-КОРЕНІ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
