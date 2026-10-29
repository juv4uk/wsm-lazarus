{ G3.32: справжня Lazarus/LCL лабораторія виконаного D3:101.
  Лише точні D1 або ЦИТОВАНІ D7, обидві цитати фізично T5M.
  Закони та шість людських проєкцій — тільки pinned SENS Contract 12.0.
  Це не повний REPL, loader Core4, арифметика D12+ чи компілятор. }
program sens_d7_totozhnist;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  wsm.domain, wsm.proektsii, wsm.t5m, wsm.binaryexec;

type
  TD7EqualityForm = class(TForm)
  private
    FDomains:array[0..1] of TComboBox;
    FBits:array[0..1] of TEdit;
    FRun:TButton;
    FLog:TMemo;
    FStatus:TLabel;
    FCatalog:TProektsiiCatalog;
    FExecutor:TBinaryExecutor;
    FSource,FAnswer:RawByteString;
    procedure ClearSnapshot;
    procedure Changed(Sender:TObject);
    procedure RunClick(Sender:TObject);
    procedure Demand(OK:Boolean; const Why:String);
    function InputKey(Index:Integer):TDomainKey;
    procedure AddAtom(var Words:TExactWords; const Key:TDomainKey);
    function LoadBytes(const Path:String):RawByteString;
    procedure SelectOperand(Index,Domain:Integer;const Bits:String);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure ConnectPinned(const Root:String);
    procedure SelfTest(const Same,Other:String);
  end;

var Window:TD7EqualityForm;

constructor TD7EqualityForm.Create(AOwner:TComponent);
var I:Integer; Help:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — виконана двійкова тотожність D1 / D7';
  Width:=1020;Height:=740;Position:=poScreenCenter;
  FExecutor:=nil;FSource:='';FAnswer:='';
  Help:=TLabel.Create(Self);Help.Parent:=Self;
  Help.SetBounds(16,12,970,40);
  Help.Caption:='Рівність визначають точний домен і біти. D7 — тільки цитовані дані; D12+ не є D1.';
  for I:=0 to 1 do begin
    FDomains[I]:=TComboBox.Create(Self);
    FDomains[I].Parent:=Self;
    FDomains[I].SetBounds(16+I*498,68,130,30);
    FDomains[I].Style:=csDropDownList;
    FDomains[I].Items.Add('D1');
    FDomains[I].Items.Add('D7');
    FDomains[I].ItemIndex:=1;
    FDomains[I].OnChange:=@Changed;
    FBits[I]:=TEdit.Create(Self);
    FBits[I].Parent:=Self;
    FBits[I].SetBounds(154+I*498,68,335,30);
    FBits[I].Text:='0010110';
    FBits[I].OnChange:=@Changed;
  end;
  FRun:=TButton.Create(Self);FRun.Parent:=Self;
  FRun.SetBounds(16,120,972,43);
  FRun.Caption:='Виконати фізичний D3:101 над двома точними атомами';
  FRun.Enabled:=False;
  FRun.OnClick:=@RunClick;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(16,177,976,30);
  FStatus.Caption:='Немає перевіреного виконання.';
  FLog:=TMemo.Create(Self);FLog.Parent:=Self;
  FLog.SetBounds(16,213,970,472);
  FLog.ReadOnly:=True;FLog.WordWrap:=False;
  FLog.ScrollBars:=ssBoth;
end;

destructor TD7EqualityForm.Destroy;
begin
  FreeAndNil(FExecutor);
  inherited Destroy;
end;

procedure TD7EqualityForm.Demand(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ДВІЙКОВА-ТОТОЖНІСТЬ: '+Why);
end;

{ Snapshot — лише ref-counted фізичні байти T5M, збережені на життя
  форми. Очищаємо ДО кожного запуску, щоби жоден провал не показував
  старий результат. D1:0 тут не host False.
  Питання: хто володіє FAnswer? Коли зникає старий snapshot?
  Чи має FStatus право бути мовним результатом SENS? }
procedure TD7EqualityForm.ClearSnapshot;
begin
  FSource:='';FAnswer:='';
  FLog.Clear;
  FStatus.Caption:='Немає перевіреного фізичного виконання.';
end;

procedure TD7EqualityForm.Changed(Sender:TObject);
begin
  ClearSnapshot;
end;

procedure TD7EqualityForm.ConnectPinned(const Root:String);
begin
  Demand(FExecutor=nil,'підключення pinned SENS повторно заборонено');
  LoadPinnedProjections(Root,FCatalog);
  FExecutor:=TBinaryExecutor.Create(RawByteString(Root));
  FRun.Enabled:=True;
  ClearSnapshot;
end;

{ InputKey: тільки два явно обрані домени D1/D7; кожна координата
  проходить вже злитий ExactKey і повний pinned-каталог. Параметр
  Index — індекс host-віджета, НЕ SENS слот. Result — TDomainKey
  (Width,Bits), без алокації та без text-dispatch.
  Питання: чому D7:0000001 <> D1:1? Що перевіряє ExactKey?
  Чи може Unicode-напис визначити викличність? }
function TD7EqualityForm.InputKey(Index:Integer):TDomainKey;
var Width:SizeInt;
begin
  Demand((Index>=0) and (Index<2),'відсутній операнд');
  case FDomains[Index].ItemIndex of
    0:Width:=1;
    1:Width:=7;
    else raise Exception.Create('Виберіть D1 або D7 без неявного D12');
  end;
  Result:=ExactKey(RawByteString(FBits[Index].Text));
  Demand(Result.Width=Width,'неправильна точна ширина D'+IntToStr(Width));
  Demand(Length(FCatalog[Width])=(SizeInt(1) shl Width),
    'pinned таблиця неповна');
  Demand(SameKey(Result,FCatalog[Width][Result.Bits].Key),
    'pinned домен не підтвердив точну координату');
end;

{ AddAtom: вхід — уже pinned exact-key; D7 завжди додається як
  фізична цитата (D2:10 D3:001 D7:bbbbbbb D2:01).
  Двійкові слова належать тимчасовому динамічному масиву Words;
  повернення не містить .lisp чи нового правила EQ.
  Питання: навіщо D7 цитувати? Чому D1 залишається атомом?
  Де D12 був би явно відхилений? }
procedure TD7EqualityForm.AddAtom(var Words:TExactWords;const Key:TDomainKey);
  procedure Put(const Bits:RawByteString);
  var N:SizeInt;
  begin
    N:=Length(Words);SetLength(Words,N+1);Words[N]:=Bits;
  end;
begin
  if Key.Width=1 then Put(KeyBits(Key))
  else if Key.Width=7 then begin
    Put('10');Put('001');Put(KeyBits(Key));Put('01');
  end else Demand(False,'непідтверджений домен операнда');
end;

{ Реальне виконання: canonical T5M -> чинний TBinaryExecutor ->
  canonical T5M D1:0/1. Усі allocations: Words та ResultWords — власні
  короткоживучі масиви; CandidateSource/Answer — ref-counted bytes;
  публікуємо FSource/FAnswer і UI лише ПІСЛЯ повної валідації.
  Текст шести проєкцій береться тільки з pinned таблиці.
  Питання: хто обчислює D3:101? Чому шість spelling не є законами?
  Як перевірено один D1 результат? Де атомарна межа UI?
  Чи може SYN бути виконаний як голова? }
procedure TD7EqualityForm.RunClick(Sender:TObject);
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var Keys:array[0..1] of TDomainKey;Words,OutWords:TExactWords;
    CandidateSource,CandidateAnswer:RawByteString;
    I,J:Integer; Width:SizeInt; Lines:TStringList; LabelText:String;
begin
  ClearSnapshot;
  Lines:=TStringList.Create;
  try
    try
      Demand(FExecutor<>nil,'немає підключеного pinned SENS');
      Keys[0]:=InputKey(0);Keys[1]:=InputKey(1);
      Words:=nil;
      SetLength(Words,2);Words[0]:='10';Words[1]:='101';
      AddAtom(Words,Keys[0]);AddAtom(Words,Keys[1]);
      SetLength(Words,Length(Words)+1);Words[High(Words)]:='01';
      CandidateSource:=EncodeT5M(Words);
      Demand(Length(CandidateSource)>0,'втрачені фізичні байти D3');
      CandidateAnswer:=FExecutor.ExecutePhysicalT5M(CandidateSource);
      DecodeT5M(CandidateAnswer,OutWords);
      Demand((Length(OutWords)=1) and
             ((OutWords[0]='0') or (OutWords[0]='1')),
        'результат повинен бути рівно D1:0 або D1:1');
      Demand(EncodeT5M(OutWords)=CandidateAnswer,
        'необоротна фізична відповідь T5M');
      Lines.Add('Виконано фізичний D3:101: '+String(OutWords[0]));
      Lines.Add('Канонічне джерело .sens: '+IntToStr(Length(CandidateSource))+' байтів');
      Lines.Add('Канонічна відповідь .sens: '+IntToStr(Length(CandidateAnswer))+' байтів');
      for I:=0 to 1 do begin
        Width:=Keys[I].Width;
        if I=0 then LabelText:='Лівий' else LabelText:='Правий';
        Lines.Add(LabelText+': D'+IntToStr(Width)+':'+String(KeyBits(Keys[I])));
        for J:=0 to 5 do
          Lines.Add('  '+Names[J]+': '+
            SurfaceForDisplay(FCatalog[Width][Keys[I].Bits].Surface[J]));
      end;
      FSource:=CandidateSource;FAnswer:=CandidateAnswer;
      FLog.Lines.Assign(Lines);
      FStatus.Caption:='Фізична D3:101 підтверджена; результат D1:'+String(OutWords[0]);
    except on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end; end;
  finally Lines.Free end;
end;

function TD7EqualityForm.LoadBytes(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Demand((F.Size>0) and (F.Size<=65536),'пошкоджений тестовий .sens');
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure TD7EqualityForm.SelectOperand(Index,Domain:Integer;const Bits:String);
begin
  FDomains[Index].ItemIndex:=Domain;
  FBits[Index].Text:=Bits;
end;

procedure TD7EqualityForm.SelfTest(const Same,Other:String);
begin
  Demand(FExecutor<>nil,'self-test потребує pinned SENS');
  { SYN — точні дані D7 з шістьма pinned проєкціями, не callable. }
  SelectOperand(0,1,'0010110');
  SelectOperand(1,1,'0010110');
  FRun.Click;
  Demand((FAnswer=EncodeT5M(['1'])) and (FSource=LoadBytes(Same)),
    'реальні кліки LCL не виконали однаковий D7 SYN з фізичного свідка');
  Demand((Pos('san:',FLog.Text)>0) and (Pos('LISP:',FLog.Text)>0)
    and (Pos('укр:',FLog.Text)>0),
    'не показано всіх pinned поверхонь D7');
  SelectOperand(1,1,'0000000');FRun.Click;
  Demand((FAnswer=EncodeT5M(['0'])) and (FSource=LoadBytes(Other)),
    'різні D7 фізичні слова були помилково зрівняні');
  { D1:1 та D7:0000001 чисельно схожі, але домени РІЗНІ. }
  SelectOperand(0,0,'1');SelectOperand(1,1,'0000001');FRun.Click;
  Demand((FAnswer=EncodeT5M(['0'])) and
    (Pos('Лівий: D1:1',FLog.Text)>0) and
    (Pos('Правий: D7:0000001',FLog.Text)>0),
    'колізія D1/D7 за числовим змістом бітів');
  SelectOperand(1,0,'1');FRun.Click;
  Demand(FAnswer=EncodeT5M(['1']),'старий D1/D1 результат зламано');
  SelectOperand(0,1,'001011');FRun.Click;
  Demand((FAnswer='') and (FSource='') and (FLog.Lines.Count=0),
    'коротке D7 залишило попередній snapshot');
  SelectOperand(0,1,'00101x0');FRun.Click;
  Demand((FAnswer='') and (FSource='') and
    (Pos('ВІДХИЛЕНО',FStatus.Caption)>0),
    'небінарне D7 було прийняте');
  SelectOperand(0,1,'000000000000');FRun.Click;
  Demand((FAnswer='') and (FSource=''),'D12 стало D7');
  SelectOperand(0,1,'0010110');SelectOperand(1,1,'0010110');FRun.Click;
  Demand((FAnswer=EncodeT5M(['1'])) and (FSource=LoadBytes(Same)),
    'немає відновлення після послідовних негативних запитів');
  WriteLn('LCL-Д3-Д7-ТОТОЖНІСТЬ-ГАРАЗД ',
    'FPC=справжній Lazarus=GTK2 T5M=точний ',
    'SYN=дані шість-проєкцій=pinned D1/D7=без-колізії ',
    'негативи=так recovery=так Core4=НЕ_ВИКОНУЄТЬСЯ');
end;

begin
  Application.Initialize;
  Window:=TD7EqualityForm.Create(nil);
  try
    Window.ConnectPinned('external/sens');
    if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then
      Window.SelfTest(ParamStr(2),ParamStr(3))
    else if ParamCount<>0 then begin
      WriteLn(StdErr,'Виклик: sens-d7-totozhnist [--самоперевірка same.sens other.sens]');
      ExitCode:=64;
    end else begin
      Application.MainForm:=Window;
      Application.Run;
    end;
  finally Window.Free end;
end.
