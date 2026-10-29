{ G3.39 — справжній Lazarus/LCL числовий оглядач фізичних T5M слів.
  Числовий закон — тільки pinned SENS Contract 12; не виводити його з Wn.
  Тут немає арифметики, Core4, REPL або другої реалізації кодека. }
program sens_chysla_ogliad;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids,
  Dialogs, wsm.t5m, wsm.physloc, wsm.numericplane;

const
  MaxViewBytes = 65536;
  MaxViewWords = 256;

type
  TDecimals = array of RawByteString;
  TChyslaWindow = class(TForm)
  private
    FDomain: TComboBox;
    FPath: TEdit;
    FOpen, FChoose: TButton;
    FPicker: TOpenDialog;
    FGrid: TStringGrid;
    FDetails: TMemo;
    FStatus: TLabel;
    FPhysical: RawByteString;
    FWords: TExactWords;
    FSpans: TPhysicalWordSpans;
    FDecimals: TDecimals;
    FWidth: SizeInt;
    FCount: SizeInt;
    procedure ResetView;
    procedure DomainChanged(Sender:TObject);
    procedure PathChanged(Sender:TObject);
    procedure OpenClicked(Sender:TObject);
    procedure ChooseClicked(Sender:TObject);
    procedure GridSelected(Sender:TObject; ACol, ARow:Integer;
      var CanSelect:Boolean);
    procedure ShowWord(Index:SizeInt);
    procedure Need(Test:Boolean; const Why:String);
    function ReadFile(const Path:String):RawByteString;
  public
    constructor Create(AOwner:TComponent);override;
    function LoadPhysical(const Path:String):Boolean;
    procedure SelfTest(const Good12,Good24,Late,Bad,Projection:String);
  end;

var Window:TChyslaWindow;

constructor TChyslaWindow.Create(AOwner:TComponent);
var L:TLabel; I:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — точні фізичні числа D12+';
  Width:=1190; Height:=735; Position:=poScreenCenter;
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(18,12,1130,38); L.AutoSize:=False;
  L.WordWrap:=True;
  L.Caption:='Фізичні слова .sens та українська числова проєкція. '+
    'Домен задає людина ЯВНО; однакова ширина без закону не означає число.';
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(18,58,125,25); L.Caption:='Числовий домен:';
  FDomain:=TComboBox.Create(Self); FDomain.Parent:=Self;
  FDomain.SetBounds(150,53,135,31);FDomain.Style:=csDropDownList;
  for I in [12,24,48,96,192] do FDomain.Items.Add('D'+IntToStr(I));
  FDomain.ItemIndex:=0;
  FDomain.OnChange:=@DomainChanged;
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(300,53,590,31);
  FPath.OnChange:=@PathChanged;
  FOpen:=TButton.Create(Self);FOpen.Parent:=Self;
  FOpen.SetBounds(903,53,135,31);
  FOpen.Caption:='Переглянути'; FOpen.OnClick:=@OpenClicked;
  FChoose:=TButton.Create(Self);FChoose.Parent:=Self;
  FChoose.SetBounds(1045,53,125,31);
  FChoose.Caption:='Обрати .sens';
  FChoose.OnClick:=@ChooseClicked;
  FPicker:=TOpenDialog.Create(Self);
  FPicker.Title:='Обрати фізичний числовий T5M';
  FPicker.Filter:='Канонічний фізичний SENS (*.sens)|*.sens';
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(18,100,1152,364);
  FGrid.ColCount:=6;FGrid.RowCount:=2;
  FGrid.FixedCols:=0; FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=74;FGrid.ColWidths[1]:=86;
  FGrid.ColWidths[2]:=190;FGrid.ColWidths[3]:=450;
  FGrid.ColWidths[4]:=166;FGrid.ColWidths[5]:=166;
  FGrid.Options:=FGrid.Options+[goRowSelect,goColSizing]-[goEditing];
  FGrid.Cells[0,0]:='Слово';
  FGrid.Cells[1,0]:='Домен';
  FGrid.Cells[2,0]:='укр (число)';
  FGrid.Cells[3,0]:='Точні біти Wn';
  FGrid.Cells[4,0]:='Трити [від,до)';
  FGrid.Cells[5,0]:='Байти [від,до)';
  FGrid.OnSelectCell:=@GridSelected;
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,477,1140,24);
  L.Caption:='Вибране слово: фізичне представлення та його явно обрана числова проєкція';
  FDetails:=TMemo.Create(Self);FDetails.Parent:=Self;
  FDetails.SetBounds(18,504,1152,155);
  FDetails.ReadOnly:=True; FDetails.WordWrap:=False;
  FDetails.ScrollBars:=ssBoth;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,670,1150,46);
  FStatus.AutoSize:=False; FStatus.WordWrap:=True;
  ResetView;
end;

{ FPhysical: власні канонічні байти .sens, FWords/FSpans/Decimals —
  керовані FPC масиви, живуть рівно до зміни вхідного файлу/домену.
  Всі елементи таблиці — копії допущених даних, не джерело законів.
  Питання: чому зміна поля вводу скидає значення? Чому домен
  не визначається шириною? Чому тритові інтервали точніші за байти?
  Чому помилка на останньому слові скасовує ВСЮ таблицю? }
procedure TChyslaWindow.ResetView;
var J:Integer;
begin
  FPhysical:='';
  FWords:=nil; FSpans:=nil; FDecimals:=nil;
  FWidth:=0; FCount:=0;
  FGrid.RowCount:=2;
  for J:=0 to FGrid.ColCount-1 do FGrid.Cells[J,1]:='';
  FDetails.Clear;
  FStatus.Caption:='Фізичні дані ще не допущено.';
end;

procedure TChyslaWindow.DomainChanged(Sender:TObject);
begin
  ResetView;
end;

procedure TChyslaWindow.PathChanged(Sender:TObject);
begin
  ResetView;
end;

procedure TChyslaWindow.Need(Test:Boolean;const Why:String);
begin
  if not Test then raise Exception.Create('LCL-ЧИСЛА-ПОМИЛКА: '+Why);
end;

{ Позичений host-шлях; результат — власний RawByteString максимум 65536
  фізичних байтів, який повністю звільняє FPC. Текст .lisp відхиляємо.
  Питання: чому не можна читати .lisp як .sens? Чому є межа на файл?
  Чому перевірку довжини робимо перед алокацією? }
function TChyslaWindow.ReadFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('очікується фізичний файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxViewBytes) then
      raise Exception.Create('порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

{ На вході виключно canonical packed .sens і явний обраний Dn.
  DecodeT5MWithLocations — єдиний фізичний reader; numericplane —
  єдиний наявний перевірювач/проєктор two's-complement для цього Dn.
  Весь candidate локальний і тільки після успішного 256-го слова
  публікується в LCL, тобто пізній fail-closed прибирає старий стан.
  Питання: чому EncodeT5M(One) не виводить домен автоматично?
  Чому порівнюємо ExactBits і DomainWidth? Чому .sens залишається
  власним байтовим буфером, а не текстом таблиці? }
function TChyslaWindow.LoadPhysical(const Path:String):Boolean;
var
  Physical:RawByteString;
  Words,One:TExactWords;
  Spans:TPhysicalWordSpans;
  Decimals:TDecimals;
  N:TExplicitNumeric;
  DomainWidth,I:SizeInt;
  S:TPhysicalWordSpan;
begin
  Result:=False;
  ResetView;
  FPath.Text:=Path;
  try
    DomainWidth:=SelectedNumericDomain(RawByteString(FDomain.Text));
    Physical:=ReadFile(Path);
    DecodeT5MWithLocations(Physical,Words,Spans);
    if (Length(Words)<1) or (Length(Words)>MaxViewWords) or
       (Length(Spans)<>Length(Words)) then
      raise Exception.Create('неприпустима кількість фізичних слів');
    SetLength(Decimals,Length(Words));
    SetLength(One,1);
    for I:=0 to High(Words) do begin
      if Length(Words[I])<>DomainWidth then
        raise Exception.Create('слово '+IntToStr(I+1)+
          ': ширина не відповідає явно обраному D'+IntToStr(DomainWidth));
      One[0]:=Words[I];
      N:=ReadNumericPhysical(EncodeT5M(One),DomainWidth);
      if (N.DomainWidth<>DomainWidth) or (N.ExactBits<>Words[I]) then
        raise Exception.Create('втрачено точне числове слово '+IntToStr(I+1));
      Decimals[I]:=RenderNumericDecimal(N);
      S:=LocatePhysicalWord(Physical,Spans,I+1);
      if (S.WordIndex<>I+1) or S.IsEOF then
        raise Exception.Create('пошкоджено фізичну адресу слова');
    end;
    FPhysical:=Physical; FWords:=Words; FSpans:=Spans;
    FDecimals:=Decimals; FWidth:=DomainWidth; FCount:=Length(Words);
    FGrid.RowCount:=FCount+1;
    for I:=0 to FCount-1 do begin
      S:=FSpans[I];
      FGrid.Cells[0,I+1]:=IntToStr(S.WordIndex);
      FGrid.Cells[1,I+1]:='D'+IntToStr(FWidth);
      FGrid.Cells[2,I+1]:=String(FDecimals[I]);
      FGrid.Cells[3,I+1]:=String(FWords[I]);
      FGrid.Cells[4,I+1]:='['+IntToStr(S.TritStart)+','+
        IntToStr(S.TritEnd)+')';
      FGrid.Cells[5,I+1]:='['+IntToStr(S.ByteStart)+','+
        IntToStr(S.ByteEnd)+')';
    end;
    FGrid.Row:=1;
    ShowWord(1);
    FStatus.Caption:='Допущено '+IntToStr(FCount)+' фізичних слів D'+
      IntToStr(FWidth)+'. Проєкція укр не змінює машинного SENS.';
    Result:=True;
  except
    on E:Exception do begin
      ResetView;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

procedure TChyslaWindow.ShowWord(Index:SizeInt);
var S:TPhysicalWordSpan;
begin
  if (Index<1) or (Index>FCount) then begin
    FDetails.Clear;
    Exit;
  end;
  S:=FSpans[Index-1];
  FDetails.Text:='Фізичне слово '+IntToStr(Index)+LineEnding+
    'D'+IntToStr(FWidth)+':'+String(FWords[Index-1])+LineEnding+
    'укр: '+String(FDecimals[Index-1])+LineEnding+
    'Трити ['+IntToStr(S.TritStart)+','+IntToStr(S.TritEnd)+')'+LineEnding+
    'Байти ['+IntToStr(S.ByteStart)+','+IntToStr(S.ByteEnd)+')'+LineEnding+
    'Тільки проєкція: не виклик, не результат арифметики.';
end;

procedure TChyslaWindow.GridSelected(Sender:TObject;ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  CanSelect:=True;
  if FCount>0 then ShowWord(ARow);
end;

procedure TChyslaWindow.OpenClicked(Sender:TObject);
begin
  LoadPhysical(FPath.Text);
end;

procedure TChyslaWindow.ChooseClicked(Sender:TObject);
begin
  if FPicker.Execute then LoadPhysical(FPicker.FileName);
end;

procedure TChyslaWindow.SelfTest(
  const Good12,Good24,Late,Bad,Projection:String);
begin
  FDomain.ItemIndex:=0;
  FPath.Text:=Good12;FOpen.Click;
  Need((FCount=3) and (FGrid.RowCount=4),'не завантажено три W12');
  Need((FGrid.Cells[2,1]='-2048') and
       (FGrid.Cells[2,2]='0') and
       (FGrid.Cells[2,3]='2047'),'неправильна signed D12 укр');
  Need((FGrid.Cells[3,1]='100000000000') and
       (FGrid.Cells[3,3]='011111111111'),'втрачено точні біти');
  Need((FGrid.Cells[4,2]='[13,25)') and
       (FGrid.Cells[5,2]='[2,5)'),'неточні фізичні адреси другого слова');
  FGrid.Row:=3;ShowWord(3);
  Need(Pos('D12:011111111111',FDetails.Text)>0,
    'вибраний рядок не показує точний фізичний атом');
  FDomain.ItemIndex:=1;DomainChanged(FDomain);
  Need((FCount=0) and (FGrid.Cells[2,1]='') and (FDetails.Text=''),
    'зміна явного D12→D24 залишила старий snapshot');
  Need(not LoadPhysical(Good12),'мовчазне вгадування D12 за шириною');
  Need(LoadPhysical(Good24),'не прийнято явні W24');
  Need((FCount=2) and (FGrid.Cells[2,1]='-8388608') and
       (FGrid.Cells[2,2]='8388607') and
       (FGrid.Cells[4,2]='[25,49)'),
       'некоректні D24 або фізична адреса');
  FDomain.ItemIndex:=0;DomainChanged(FDomain);
  Need(not LoadPhysical(Late),'пізнє W24 у D12 потрапило до таблиці');
  Need((FCount=0) and (FGrid.RowCount=2) and
       (FDetails.Text='') and (FGrid.Cells[3,1]=''),
       'пізній збій не очистив уже відображене число');
  Need(not LoadPhysical(Bad),'неканонічний T5M прийнято');
  Need(not LoadPhysical(Projection),'текстову .lisp підмінено як .sens');
  Need(not LoadPhysical(Good24),'D24 прийнято як D12');
  Need(LoadPhysical(Good12) and (FCount=3),
    'після відмов не відновлено точні фізичні дані');
  FPath.Text:=Projection;
  Need((FCount=0) and (FDetails.Text='') and
       (FGrid.Cells[2,1]=''),'зміна шляху залишила старий стан');
  Need(LoadPhysical(Good12),'не відновлено після зміни шляху');
  WriteLn('LCL-ЧИСЛА-ГАРАЗД GTK2=так D12-D24=явні ',
    'укр=проєкція T5M=точний адреси=трит-байт ',
    'пізня-відмова=очищено відновлення=так арифметика=НЕ-ДОВЕДЕНА');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — точні фізичні числа D12+';
    Application.CreateForm(TChyslaWindow,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>6 then Halt(64);
      Window.Show;Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6));
      Window.Free;
      Halt(0);
    end;
    if ParamCount>1 then Halt(64);
    if ParamCount=1 then Window.LoadPhysical(ParamStr(1));
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ЧИСЛА-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
