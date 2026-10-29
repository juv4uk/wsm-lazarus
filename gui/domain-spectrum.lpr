{ Lazarus/LCL: фізичний спектр точних двійкових доменів SENS.
  Лише візуалізація вже допущених wsm.t5m / wsm.d2source / wsm.binarybind.
  Частота слова не дає мовного закону, викличності або значення. }
program domain_spectrum;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Dialogs, Graphics, Types,
  wsm.t5m, wsm.d2source, wsm.domain, wsm.bind, wsm.bindindex,
  wsm.binarybind, wsm.ukroundtrip, wsm.physloc;

const
  MaxVisibleWords = 16384;
  LeftInset = 32;
  BottomInset = 38;
type
  TSpectrumForm = class(TForm)
  private
    Graph: TPaintBox;
    Details: TListBox;
    Status: TLabel;
    OpenButton: TButton;
    SearchField: TEdit;
    SearchButton: TButton;
    FullSearchButton: TButton;
    ExactSearchButton: TButton;
    Dialog: TOpenDialog;
    Words: TBinaryWords;
    Spans: TPhysicalWordSpans; { лише перевірена карта original T5M }
    SearchKey: TDomainKey;
    HasSearch: Boolean;
    SearchMatches: SizeInt;
    Counts: array[1..9] of SizeInt;
    Selected: Integer;
    procedure ResetData;
    procedure Failure(const Reason: String);
    procedure OpenClick(Sender: TObject);
    procedure SearchClick(Sender: TObject);
    procedure FullSearchClick(Sender: TObject);
    procedure ExactSearchClick(Sender: TObject);
    function FindExactPhysical(const Coordinate: RawByteString): Boolean;
    function FindUkrainianPhysical(const SurfaceName: RawByteString;
      FullName: Boolean = False): Boolean;
    procedure GraphPaint(Sender: TObject);
    procedure GraphMouse(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PickDomain(Domain: Integer);
    function PhysicalSuffix(WordIndex: SizeInt): String;
    function DomainAt(X, AWidth: Integer): Integer;
    procedure PaintSpectrum(Target: TCanvas; AWidth, AHeight: Integer);
    procedure Demand(TestOK: Boolean; const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysical(const FileName: String): Boolean;
    procedure SelfTest(const GoodFile, BadT5M, BadD2, FullFile: String);
  end;

var Window: TSpectrumForm;

constructor TSpectrumForm.Create(AOwner: TComponent);
var TopBar, BottomBar: TPanel; HelpLabel: TLabel;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — спектр точних двійкових доменів';
  Width := 1000;
  Height := 700;
  Position := poScreenCenter;

  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 88;
  TopBar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := TopBar;
  OpenButton.SetBounds(12, 8, 220, 32);
  OpenButton.Caption := 'Відкрити двійковий .sens…';
  OpenButton.OnClick := @OpenClick;

  SearchField := TEdit.Create(Self);
  SearchField.Parent := TopBar;
  SearchField.SetBounds(244, 8, 220, 32);
  SearchField.TextHint := 'Назва ук/укр або D3:111';
  SearchButton := TButton.Create(Self);
  SearchButton.Parent := TopBar;
  SearchButton.SetBounds(476, 8, 236, 32);
  SearchButton.Caption := 'Знайти точне слово';
  SearchButton.OnClick := @SearchClick;

  { Повна "укр" не еквівалентна скороченій "ук": окремий явний режим. }
  FullSearchButton := TButton.Create(Self);
  FullSearchButton.Parent := TopBar;
  FullSearchButton.SetBounds(728, 8, 242, 32);
  FullSearchButton.Caption := 'Знайти повну укр';
  FullSearchButton.OnClick := @FullSearchClick;

  { Координата — лише запит до вже допущених фізичних слів.
    Це не текстовий SENS dispatch і не нова мовна тотожність. }
  ExactSearchButton := TButton.Create(Self);
  ExactSearchButton.Parent := TopBar;
  ExactSearchButton.SetBounds(244, 50, 220, 30);
  ExactSearchButton.Caption := 'Знайти двійкове слово';
  ExactSearchButton.OnClick := @ExactSearchClick;
  HelpLabel := TLabel.Create(Self);
  HelpLabel.Parent := TopBar;
  HelpLabel.SetBounds(476, 56, 480, 24);
  HelpLabel.Caption := 'Введіть, наприклад, D3:111 — без мовного тлумачення';

  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Виберіть фізичний SENS';
  Dialog.Filter := 'Двійковий SENS (*.sens)|*.sens';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 40;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 10, 950, 24);

  Graph := TPaintBox.Create(Self);
  Graph.Parent := Self;
  Graph.Align := alTop;
  Graph.Height := 320;
  Graph.OnPaint := @GraphPaint;
  Graph.OnMouseDown := @GraphMouse;

  Details := TListBox.Create(Self);
  Details.Parent := Self;
  Details.Align := alClient;
  Details.IntegralHeight := False;

  ResetData;
end;

procedure TSpectrumForm.ResetData;
var D: Integer;
begin
  SetLength(Words, 0);
  SetLength(Spans, 0);
  HasSearch := False;
  SearchMatches := 0;
  SearchKey.Width := 0;
  SearchKey.Bits := 0;
  SearchField.Text := '';
  for D := 1 to 9 do Counts[D] := 0;
  Selected := 0;
  Details.Items.Clear;
  Status.Caption := 'Виберіть фізичний .sens. Графік показує кількість слів, а не семантику.';
  Graph.Invalidate;
end;

procedure TSpectrumForm.Failure(const Reason: String);
begin
  ResetData;
  Status.Caption := 'Помилка: ' + Reason;
end;

function TSpectrumForm.LoadPhysical(const FileName: String): Boolean;
var
  F: TFileStream;
  Physical: RawByteString;
  Tables: TDomainSet;
  Candidate: TBinaryWords;
  CandidateSpans: TPhysicalWordSpans;
  PhysicalWords: TExactWords;
  At: TPhysicalWordSpan;
  TempCounts: array[1..9] of SizeInt;
  I, D: SizeInt;
begin
  Result := False;
  ResetData;
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise Exception.Create('потрібен фізичний двійковий файл .sens');
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('файл порожній або перевищує 4 МіБ');
      SetLength(Physical, SizeInt(F.Size));
      F.ReadBuffer(Physical[1], Length(Physical));
    finally
      F.Free;
    end;
    LoadPinnedDomains('external/sens', Tables);
    BindT5MBinary(Physical, Tables, Candidate);
    { Один і той самий ОРИГІНАЛЬНИЙ байтовий T5M є джерелом адреси.
      Другий фізичний decoder не визначає семантику: тільки word spans.
      Не допускаємо показувати чужі координати від іншого документа. }
    DecodeT5MWithLocations(Physical, PhysicalWords, CandidateSpans);
    if (Length(Candidate) = 0) or (Length(Candidate) > MaxVisibleWords) then
      raise Exception.Create('перевищена межа 16384 фізичних слів або немає даних');

    for D := 1 to 9 do TempCounts[D] := 0;
    for I := 0 to High(Candidate) do begin
      D := Candidate[I].Key.Width;
      if (D < 1) or (D > 9) or (D = 2) then
        raise Exception.Create('недопущена ширина фізичного слова');
      At := LocatePhysicalWord(Physical, CandidateSpans,
        Candidate[I].WordIndex);
      if At.IsEOF or
         (PhysicalWords[Candidate[I].WordIndex - 1] <>
          KeyBits(Candidate[I].Key)) then
        raise Exception.Create('фізичне слово не збігається з pinned binder');
      { D1:0 і D3:000 навмисно належать різним стовпчикам. }
      Inc(TempCounts[D]);
    end;

    { Атомарно публікуємо результат лише після повного допуску. }
    Words := Candidate;
    Spans := CandidateSpans;
    for D := 1 to 9 do Counts[D] := TempCounts[D];
    Status.Caption := 'Допущено слів: ' + IntToStr(Length(Words)) +
      ' · натисніть D1–D9 · викличність не доведено';
    Graph.Invalidate;
    Result := True;
  except
    on E: ED2SourceError do
      Failure('фізичне слово ' + IntToStr(E.WordIndex) + ': ' + E.Message);
    on E: Exception do Failure(E.Message);
  end;
end;

function TSpectrumForm.DomainAt(X, AWidth: Integer): Integer;
var Step, D: Integer;
begin
  Result := 0;
  if AWidth < 180 then Exit;
  Step := (AWidth - LeftInset - 16) div 9;
  for D := 1 to 9 do
    if (X >= LeftInset + (D-1)*Step + Step div 4) and
       (X < LeftInset + (D-1)*Step + 3*Step div 4) then
      Exit(D);
end;

{ Host-only відображення. Spans — напіввідкриті фізичні інтервали з
  перевіреного DecodeT5MWithLocations; немає повторного T5M pack,
  ніякого припущення про семантику D12+ чи проєкцію ук/укр.
  Два сусідні слова можуть мати однаковий фізичний індекс байта. }
function TSpectrumForm.PhysicalSuffix(WordIndex: SizeInt): String;
var At: TPhysicalWordSpan;
begin
  if (WordIndex < 1) or (WordIndex > Length(Spans)) then
    raise Exception.Create('немає фізичної адреси допущеного слова');
  At := Spans[WordIndex - 1];
  if At.IsEOF or (At.WordIndex <> WordIndex) or
     (At.TritStart >= At.TritEnd) or (At.ByteStart >= At.ByteEnd) then
    raise Exception.Create('некоректний фізичний інтервал слова');
  Result := ' · трити [' + IntToStr(At.TritStart) + ',' +
    IntToStr(At.TritEnd) + ') · байти [' +
    IntToStr(At.ByteStart) + ',' + IntToStr(At.ByteEnd) + ')';
end;

procedure TSpectrumForm.PickDomain(Domain: Integer);
var
  I: SizeInt;
  Row, Surface: RawByteString;
begin
  if (Domain < 1) or (Domain > 9) then Exit;
  HasSearch := False;
  SearchMatches := 0;
  SearchField.Text := '';
  Selected := Domain;
  Details.Items.Clear;
  for I := 0 to High(Words) do
    if Words[I].Key.Width = Domain then begin
      Surface := Words[I].Ukrainian;
      if Surface = '' then Surface := '—';
      Row := '№ ' + IntToStr(Words[I].WordIndex) +
        ' · D' + IntToStr(Domain) + ' · ' +
        KeyBits(Words[I].Key) + ' · ' + Surface +
        RawByteString(PhysicalSuffix(Words[I].WordIndex));
      Details.Items.Add(String(Row));
    end;
  Status.Caption := 'D' + IntToStr(Domain) +
    ': фізичних слів ' + IntToStr(Counts[Domain]) +
    ' · точні біти та проєкція ук; не семантичний закон';
  Graph.Invalidate;
end;

procedure TSpectrumForm.PaintSpectrum(Target: TCanvas; AWidth, AHeight: Integer);
var
  D, Step, X, TopY, PlotBottom, MaxCount, PlotHeight, BarHeight: Integer;
begin
  Target.Brush.Color := clWhite;
  Target.FillRect(Rect(0, 0, AWidth, AHeight));
  if (Length(Words) = 0) or (AWidth < 180) or (AHeight < 100) then Exit;

  MaxCount := 1;
  for D := 1 to 9 do
    if Counts[D] > MaxCount then MaxCount := Counts[D];
  Step := (AWidth - LeftInset - 16) div 9;
  PlotBottom := AHeight - BottomInset;
  PlotHeight := PlotBottom - 28;
  Target.Font.Color := clBlack;
  Target.Font.Size := 10;
  Target.Pen.Style := psClear;
  for D := 1 to 9 do begin
    X := LeftInset + (D-1)*Step + Step div 4;
    BarHeight := Trunc((Int64(PlotHeight) * Counts[D]) div MaxCount);
    TopY := PlotBottom - BarHeight;
    if Counts[D] > 0 then begin
      if Selected = D then Target.Brush.Color := clRed
      else Target.Brush.Color := clNavy;
      Target.FillRect(Rect(X, TopY, X + Step div 2, PlotBottom));
    end;
    Target.Brush.Color := clWhite;
    Target.TextOut(X, PlotBottom + 5, 'D' + IntToStr(D));
    Target.TextOut(X, 8, IntToStr(Counts[D]));
  end;
  Target.Pen.Style := psSolid;
end;

procedure TSpectrumForm.GraphPaint(Sender: TObject);
begin
  PaintSpectrum(Graph.Canvas, Graph.Width, Graph.Height);
end;

procedure TSpectrumForm.GraphMouse(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var D: Integer;
begin
  if Button <> mbLeft then Exit;
  if (Y < 0) or (Y > Graph.Height) then Exit;
  D := DomainAt(X, Graph.Width);
  if D > 0 then PickDomain(D);
end;

procedure TSpectrumForm.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadPhysical(Dialog.FileName);
end;

{ Пошук тільки pinned `ук` або `укр` (режими не змішуються).
  Boolean — успіх host-механізму, НЕ D1. Для "укр" наявний
  UkrainianToPhysical перевіряє ВСІ повні назви D1–D9 через індекс,
  упаковує фізичний T5M; приймаємо лише ОДНЕ exact бінарне слово.
  Навіть `()` не можна перетворити на вигаданий D3:000.
  Локальні Tables, Longs, Index, NameWords і Lines мають FPC-managed
  lifetime; лише після повної перевірки публікуються LCL віджети.
  П'ятий принцип SENS: сучасний Lazarus UI без нової мовної семантики. }
function TSpectrumForm.FindUkrainianPhysical(const SurfaceName: RawByteString;
  FullName: Boolean): Boolean;
var
  Tables: TDomainSet;
  Index: TBindIndex;
  Longs: TLongProjection;
  NamePhysical: RawByteString;
  NameWords: TExactWords;
  Key: TDomainKey;
  I, Matches: SizeInt;
  Lines: TStringList;
  KeyText, LineText: RawByteString;
  SurfaceKind: String;
begin
  Result := False;
  HasSearch := False;
  SearchMatches := 0;
  SearchKey.Width := 0;
  SearchKey.Bits := 0;
  Selected := 0;
  Details.Items.Clear;
  Graph.Invalidate;
  Lines := TStringList.Create;
  try
    try
      if Length(Words) = 0 then
        raise Exception.Create('спочатку відкрийте фізичний .sens');
      if SurfaceName = '' then
        raise Exception.Create('порожня українська назва');
      LoadPinnedDomains('external/sens', Tables);
      if FullName then begin
        { Наявний pinned механізм G2.20, не ще один індекс/reader.
          Фізично упаковуємо і знову декодуємо байти лише для
          встановлення exact координати єдиного атома. }
        LoadPinnedLongProjection('external/sens', Tables, Longs);
        NamePhysical := UkrainianToPhysical(SurfaceName, Tables, Longs);
        DecodeT5M(NamePhysical, NameWords);
        if Length(NameWords) <> 1 then
          raise Exception.Create('повна укр назва має бути одним фізичним атомом');
        Key := ExactKey(NameWords[0]);
        if (Key.Width < 1) or (Key.Width > 9) or (Key.Width = 2) then
          raise Exception.Create('повна укр назва не має допустимого домену');
        SurfaceKind := 'укр';
      end else begin
        BuildBindIndex(Tables, Index);
        Key := IndexedUkrainian(Index, SurfaceName);
        SurfaceKind := 'ук';
      end;
      KeyText := KeyBits(Key);
      Matches := 0;
      for I := 0 to High(Words) do
        if SameKey(Words[I].Key, Key) then begin
          Inc(Matches);
          LineText := '№ ' + IntToStr(Words[I].WordIndex) +
            ' · D' + IntToStr(Key.Width) + ' · ' + KeyText + ' · ' +
            SurfaceName +
            RawByteString(PhysicalSuffix(Words[I].WordIndex));
          Lines.Add(String(LineText));
        end;
      { Єдина публікація: після pinned індексу та повного обходу. }
      Details.Items.Assign(Lines);
      SearchKey := Key;
      HasSearch := True;
      SearchMatches := Matches;
      if Key.Width <= 9 then Selected := Key.Width;
      Status.Caption := 'Точне ' + SurfaceKind + ': D' + IntToStr(Key.Width) + ':' +
        String(KeyText) + ' · фізичних входжень: ' + IntToStr(Matches) +
        ' · це не викличність';
      if Key.Width > 9 then
        Status.Caption := Status.Caption +
          ' · D10 поза фізичним D1–D9 оглядачем';
      Graph.Invalidate;
      Result := True;
    except
      on E: Exception do begin
        { Ні попередня вибірка, ні часткові збіги не видимі після відмови. }
        HasSearch := False;
        SearchMatches := 0;
        Selected := 0;
        Details.Items.Clear;
        Status.Caption := 'Помилка пошуку: ' + E.Message;
        Graph.Invalidate;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TSpectrumForm.SearchClick(Sender: TObject);
begin
  FindUkrainianPhysical(RawByteString(SearchField.Text), False);
end;

procedure TSpectrumForm.FullSearchClick(Sender: TObject);
begin
  FindUkrainianPhysical(RawByteString(SearchField.Text), True);
end;



{ Фізичний пошук не здійснює lookup за назвою: тільки точні width/bits.
  Coordinate — локальна ASCII-нотація для GUI, НЕ .sens, НЕ opcode.
  Результат Boolean означає успіх host-операції, не SENS D1.
  Lines (FPC-managed) живе лише до публікації, Words зберігає
  попередній перевірений T5M admission, граф не одержує часткових даних. }
function TSpectrumForm.FindExactPhysical(
  const Coordinate: RawByteString): Boolean;
var
  Colon, Domain: LongInt;
  I, Matches: SizeInt;
  Bits, Surface, LineText: RawByteString;
  Key: TDomainKey;
  Lines: TStringList;
begin
  Result := False;
  HasSearch := False;
  SearchMatches := 0;
  SearchKey.Width := 0;
  SearchKey.Bits := 0;
  Selected := 0;
  Details.Items.Clear;
  Graph.Invalidate;
  Lines := TStringList.Create;
  try
    try
      if Length(Words) = 0 then
        raise Exception.Create('спочатку відкрийте фізичний .sens');
      if (Length(Coordinate) < 4) or (Length(Coordinate) > 14) or
         (Coordinate[1] <> 'D') then
        raise Exception.Create('очікується точна координата D3:111');
      Colon := Pos(':', String(Coordinate));
      if (Colon <> 3) or
         (not TryStrToInt(Copy(Coordinate, 2, Colon - 2), Domain)) then
        raise Exception.Create('неправильний номер домену');
      if (Domain < 1) or (Domain > 9) or (Domain = 2) then
        raise Exception.Create('цей фізичний оглядач допускає D1–D9, крім D2');
      if Copy(Coordinate, 2, Colon - 2) <> RawByteString(IntToStr(Domain)) then
        raise Exception.Create('неоднозначний запис домену');
      Bits := Copy(Coordinate, Colon + 1, Length(Coordinate) - Colon);
      if Length(Bits) <> Domain then
        raise Exception.Create('ширина координати не збігається з бітами');
      Key := ExactKey(Bits); { Відхиляє кожний небінарний байт. }
      Matches := 0;
      for I := 0 to High(Words) do
        if SameKey(Words[I].Key, Key) then begin
          Inc(Matches);
          Surface := Words[I].Ukrainian;
          if Surface = '' then Surface := '—';
          LineText := '№ ' + IntToStr(Words[I].WordIndex) +
            ' · D' + IntToStr(Domain) + ' · ' + Bits + ' · ' + Surface +
            RawByteString(PhysicalSuffix(Words[I].WordIndex));
          Lines.Add(String(LineText));
        end;
      { Атомарно публікуємо тільки повністю перевірену вибірку. }
      Details.Items.Assign(Lines);
      SearchKey := Key;
      SearchMatches := Matches;
      HasSearch := True;
      Selected := Domain;
      Status.Caption := 'Точна фізична координата D' + IntToStr(Domain) +
        ':' + String(Bits) + ' · фізичних входжень: ' + IntToStr(Matches) +
        ' · це не викличність або числова семантика';
      Graph.Invalidate;
      Result := True;
    except
      on E: Exception do begin
        HasSearch := False;
        SearchMatches := 0;
        SearchKey.Width := 0;
        SearchKey.Bits := 0;
        Selected := 0;
        Details.Items.Clear;
        Status.Caption := 'Помилка координати: ' + E.Message;
        Graph.Invalidate;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TSpectrumForm.ExactSearchClick(Sender: TObject);
begin
  FindExactPhysical(RawByteString(SearchField.Text));
end;

procedure TSpectrumForm.Demand(TestOK: Boolean; const Reason: String);
begin
  if not TestOK then raise Exception.Create('фізична перевірка LCL: ' + Reason);
end;

procedure TSpectrumForm.SelfTest(const GoodFile, BadT5M, BadD2,
  FullFile: String);
const
  BadCoordinates: array[0..7] of RawByteString =
    ('D2:10', 'D3:11', 'D3:11x', 'D03:111',
     'D10:0000000000', 'D12:000000000000', 'cons', '');
var Bitmap: TBitmap; Step, X3, I: Integer;
begin
  Demand((Graph.Parent = Self) and (Details.Parent = Self) and
    (SearchField.Parent <> nil) and (SearchButton.Parent <> nil) and
    (FullSearchButton.Parent <> nil) and (ExactSearchButton.Parent <> nil),
    'справжні LCL віджети пошуку не створено');
  Demand(not FindExactPhysical('D3:111'),
    'точна координата без фізичного .sens стала результатом');
  Demand(not FindUkrainianPhysical('так'),
    'пошук без фізичного .sens опублікував координати');
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'пошук без фізичного джерела залишив старі дані');
  Demand(LoadPhysical(GoodFile), 'позитивний T5M не допущено');
  Demand(Length(Words) = 3, 'потрібні три точні слова');
  Demand((Length(Spans) = 6) and
    (Spans[1].WordIndex = 2) and
    (Spans[1].TritStart = 3) and (Spans[1].TritEnd = 6) and
    (Spans[1].ByteStart = 0) and (Spans[1].ByteEnd = 2) and
    (Spans[3].WordIndex = 4) and
    (Spans[3].TritStart = 10) and (Spans[3].TritEnd = 11) and
    (Spans[3].ByteStart = 2) and (Spans[3].ByteEnd = 3) and
    (Spans[4].WordIndex = 5) and
    (Spans[4].TritStart = 12) and (Spans[4].TritEnd = 15) and
    (Spans[4].ByteStart = 2) and (Spans[4].ByteEnd = 3),
    'оригінальні фізичні слова W2/W4/W5 мають точні адреси');
  Demand((Counts[1] = 1) and (Counts[3] = 2) and (Counts[2] = 0),
    'точні D1/D3 домени змішані');

  Step := (Graph.Width - LeftInset - 16) div 9;
  X3 := LeftInset + 2*Step + Step div 2;
  GraphMouse(Graph, mbLeft, [], X3, Graph.Height div 2);
  Demand(Selected = 3, 'миша не обрала D3');
  Demand(Details.Items.Count = 2, 'D3 не містить двох фізичних слів');
  Demand((Pos('111', Details.Items[0]) > 0) and
         (Pos('000', Details.Items[1]) > 0),
    'утрачено точні біти D3 або порядок фізичних слів');
  Demand(Pos('сполучити', Details.Items[0]) > 0,
    'утрачено pinned українську проєкцію ук для D3:111');
  Demand((Pos('трити [3,6)', Details.Items[0]) > 0) and
    (Pos('байти [0,2)', Details.Items[0]) > 0),
    'графічний список D3 не показує точні межі вихідного слова');

  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(Graph.Width, Graph.Height);
    PaintSpectrum(Bitmap.Canvas, Bitmap.Width, Bitmap.Height);
    Demand(Bitmap.Canvas.Pixels[X3, Bitmap.Height - BottomInset - 12] = clRed,
      'справжній Canvas не зафарбував вибраний стовпчик D3');
  finally Bitmap.Free; end;

  GraphMouse(Graph, mbLeft, [],
    LeftInset + Step div 2, Graph.Height div 2);
  Demand((Selected = 1) and (Details.Items.Count = 1) and
    (Pos('D1', Details.Items[0]) > 0) and
    (Pos('1', Details.Items[0]) > 0) and
    (Pos('так', Details.Items[0]) > 0),
    'D1 помилково змішано з D3');

  { Тільки pinned "ук" індекс, не англійська назва чи індекс ключа за
    довжиною. Чинний фізичний список: D3:111 слово 2; D1:1 слово 4;
    D3:000 слово 5. }
  SearchField.Text := 'сполучити';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchKey.Width = 3) and
    (KeyBits(SearchKey) = '111') and (SearchMatches = 1) and
    (Details.Items.Count = 1) and
    (Pos('№ 2', Details.Items[0]) > 0) and
    (Pos('трити [3,6)', Details.Items[0]) > 0) and
    (Pos('байти [0,2)', Details.Items[0]) > 0),
    'українське ук не вибрало точне фізичне D3:111');
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(Graph.Width, Graph.Height);
    PaintSpectrum(Bitmap.Canvas, Bitmap.Width, Bitmap.Height);
    Demand(Bitmap.Canvas.Pixels[X3, Bitmap.Height - BottomInset - 12] = clRed,
      'пошук ук не виділив Canvas D3');
  finally Bitmap.Free; end;

  SearchField.Text := 'так';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchKey.Width = 1) and
    (KeyBits(SearchKey) = '1') and (SearchMatches = 1) and
    (Details.Items.Count = 1) and
    (Pos('№ 4', Details.Items[0]) > 0) and
    (Pos('трити [10,11)', Details.Items[0]) > 0) and
    (Pos('байти [2,3)', Details.Items[0]) > 0),
    'точне D1:1 підмінено іншим фізичним словом');
  SearchField.Text := 'ні';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchKey.Width = 1) and
    (KeyBits(SearchKey) = '0') and (SearchMatches = 0) and
    (Details.Items.Count = 0) and
    (Pos('входжень: 0', Status.Caption) > 0),
    'відсутня D1:0 координата не може стати вигаданим входженням');
  SearchField.Text := 'за-умовою';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchKey.Width = 3) and
    (KeyBits(SearchKey) = '110') and (SearchMatches = 0),
    'пошук D3:110 не відрізняє ключ від присутності у файлі');

  SearchField.Text := 'cons';
  SearchClick(SearchButton);
  Demand((not HasSearch) and (SearchMatches = 0) and
    (Details.Items.Count = 0) and (Selected = 0) and
    (Length(Words) = 3) and
    (Pos('Помилка пошуку:', Status.Caption) = 1),
    'англійський dispatch або стара вибірка пережили відмову');
  SearchField.Text := 'невідома-назва';
  SearchClick(SearchButton);
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'невідома ук назва пройшла');
  SearchField.Text := 'так';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchMatches = 1),
    'відновлення пошуку ук після помилки не працює');
  { Новий справжній GUI-зріз: координата ніколи не визначає закон,
    лише порівнюється з фізичними словами вже допущеного .sens. }
  SearchField.Text := 'D3:111';
  ExactSearchClick(ExactSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and (Selected = 3) and
    SameKey(SearchKey, ExactKey('111')) and
    (Details.Items.Count = 1) and
    (Pos('№ 2', Details.Items[0]) > 0) and
    (Pos('сполучити', Details.Items[0]) > 0),
    'точний фізичний D3:111 або pinned ук проєкція втрачена');
  SearchField.Text := 'D3:000';
  ExactSearchClick(ExactSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and (Selected = 3) and
    (Pos('№ 5', Details.Items[0]) > 0) and
    (Pos('трити [12,15)', Details.Items[0]) > 0) and
    (Pos('байти [2,3)', Details.Items[0]) > 0),
    'D3:000 не знайшов своє фізичне слово');
  SearchField.Text := 'D1:1';
  ExactSearchClick(ExactSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and (Selected = 1) and
    (Pos('№ 4', Details.Items[0]) > 0),
    'D1:1 змішано з D3 або втрачено координату');
  SearchField.Text := 'D1:0';
  ExactSearchClick(ExactSearchButton);
  Demand(HasSearch and (SearchMatches = 0) and
    (Details.Items.Count = 0) and (Length(Words) = 3),
    'відсутній D1:0 не можна домислити з назви');
  for I := Low(BadCoordinates) to High(BadCoordinates) do begin
    SearchField.Text := String(BadCoordinates[I]);
    ExactSearchClick(ExactSearchButton);
    Demand((not HasSearch) and (SearchMatches = 0) and
      (SearchKey.Width = 0) and (Selected = 0) and
      (Details.Items.Count = 0) and (Length(Words) = 3) and
      (Pos('Помилка координати:', Status.Caption) = 1),
      'некоректна координата пройшла або залишила стару вибірку');
  end;
  SearchField.Text := 'D3:111';
  ExactSearchClick(ExactSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and (Selected = 3) and
    (Details.Items.Count = 1),
    'після негативів точний пошук не відновився');
  WriteLn('LCL-ТОЧНА-КООРДИНАТА-ГАРАЗД D3:111=№2 D3:000=№5',
    ' D1:1=№4 D1:0=відсутній негативних=8 відновлення=так',
    ' Lazarus=справжній-інтерфейс семантика=не-визначається');

  WriteLn('LCL-УК-ПОШУК-ГАРАЗД pinned=D1-D10 exact=так',
    ' D1=1 D3=1 нуль=так англійська=відхилено Canvas=справжній');

  { Новий незалежний pinned фізичний свідок з окремою D4:0101,
    яка має РІЗНІ назви ук=порожнє? і укр=порожній?.
    Відмінність проєкцій встановлює upstream d4.lisp, не Pascal. }
  Demand(LoadPhysical(FullFile), 'додатковий D4 T5M не допущено');
  Demand(Length(Words) = 4, 'D4 фізичне слово втрачено');
  Demand((Length(Spans) = 7) and (Spans[6].WordIndex = 7) and
    (Spans[6].TritStart = 19) and (Spans[6].TritEnd = 23) and
    (Spans[6].ByteStart = 3) and (Spans[6].ByteEnd = 5),
    'точна фізична адреса D4 з окремого pinned свідка втрачена');
  Demand((Words[3].WordIndex = 7) and (Words[3].Key.Width = 4) and
    (KeyBits(Words[3].Key) = '0101'), 'точний D4:0101 не збережено');
  SearchField.Text := 'порожній?';
  FullSearchClick(FullSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and (Selected = 4) and
    (SearchKey.Width = 4) and (KeyBits(SearchKey) = '0101') and
    (Details.Items.Count = 1) and
    (Pos('№ 7', Details.Items[0]) > 0) and
    (Pos('трити [19,23)', Details.Items[0]) > 0) and
    (Pos('байти [3,5)', Details.Items[0]) > 0) and
    (Pos('Точне укр:', Status.Caption) > 0),
    'повна pinned укр назва не знайшла власну D4 координату');
  SearchField.Text := 'порожнє?';
  SearchClick(SearchButton);
  Demand(HasSearch and (SearchMatches = 1) and
    SameKey(SearchKey, ExactKey('0101')),
    'чинний короткий ук пошук D4 регресував');

  SearchField.Text := 'порожнє?';
  FullSearchClick(FullSearchButton);
  Demand((not HasSearch) and (SearchMatches = 0) and
    (Selected = 0) and (Details.Items.Count = 0),
    'коротке ук підмінило повну укр назву');
  SearchField.Text := 'порожній?';
  SearchClick(SearchButton);
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'повне укр підмінило коротке ук');

  SearchField.Text := 'сполучити';
  FullSearchClick(FullSearchButton);
  Demand(HasSearch and (Selected = 3) and (SearchMatches = 1) and
    SameKey(SearchKey, ExactKey('111')) and
    (Pos('№ 2', Details.Items[0]) > 0),
    'пошук укр не підтвердив фізичне D3:111');

  SearchField.Text := '()';
  FullSearchClick(FullSearchButton);
  Demand((not HasSearch) and (SearchMatches = 0) and
    (Details.Items.Count = 0) and
    (Pos('Помилка пошуку:', Status.Caption) = 1),
    'порожню D2 структуру помилково прийнято за фізичний D3 атом');
  SearchField.Text := 'null?';
  FullSearchClick(FullSearchButton);
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'англійська назва пройшла через повне укр');
  SearchField.Text := 'немає-назви';
  FullSearchClick(FullSearchButton);
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'невідоме повне укр пройшло');
  SearchField.Text := '';
  FullSearchClick(FullSearchButton);
  Demand((not HasSearch) and (Details.Items.Count = 0),
    'порожня назва пройшла');
  SearchField.Text := 'порожній?';
  FullSearchClick(FullSearchButton);
  Demand(HasSearch and (SearchMatches = 1) and
    (Selected = 4) and (Details.Items.Count = 1),
    'пошук укр не відновився після кількох відмов');

  WriteLn('LCL-ПОВНА-УКР-ГАРАЗД pinned=D4:0101',
    ' ук=порожнє? укр=порожній? bit-exact=так',
    ' D3=111 структура=відхилено англійська=відхилено',
    ' після-відмови=відновлено');

  Demand(not LoadPhysical(BadT5M), 'поганий T5M пройшов');
  Demand((Length(Words) = 0) and (Length(Spans) = 0) and
    (Details.Items.Count = 0) and
    (Counts[1] = 0) and (Counts[3] = 0) and (Selected = 0) and
    (not HasSearch) and (SearchField.Text = ''),
    'після T5M-помилки залишились дані');
  Demand(Pos('Помилка:', Status.Caption) = 1,
    'немає статусу фізичної помилки');
  Demand(not LoadPhysical(BadD2), 'незакрита D2 форма пройшла');
  Demand((Length(Words) = 0) and (Length(Spans) = 0) and
    (Details.Items.Count = 0),
    'після D2-помилки залишився граф');
  Demand(not LoadPhysical('немає-такого-файлу.sens'),
    'відсутній файл пройшов');
  Demand((Length(Words) = 0) and (Details.Items.Count = 0),
    'відсутній файл залишив попередні слова');

  WriteLn('LCL-ФІЗИЧНІ-МЕЖІ-ГАРАЗД W2=[3,6) W4=[10,11)',
    ' W5=[12,15) W7=[19,23) байти=точні очищення=атомарно',
    ' пошук=ук/укр/Dn');
  WriteLn('LCL-СПЕКТР-ГАРАЗД Lazarus=справжній Canvas=намальовано',
    ' вибір-мишею=так D1_не_дорівнює_D3=так UTF8=проєкція',
    ' пошкоджені=відхилено виконання=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — спектр двійкових доменів';
    Application.CreateForm(TSpectrumForm, Window);
    if (ParamCount >= 1) and (ParamStr(1) = '--selftest') then begin
      if ParamCount <> 5 then
        raise Exception.Create('самоперевірка потребує чотири фізичні файли');
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5));
    end else if (ParamCount = 0) then
      Application.Run
    else if ParamCount = 1 then begin
      Window.LoadPhysical(ParamStr(1));
      Application.Run;
    end else
      raise Exception.Create('некоректна кількість аргументів');
  except
    on E: Exception do begin
      WriteLn(StdErr, 'LCL-СПЕКТР-ПОМИЛКА: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
