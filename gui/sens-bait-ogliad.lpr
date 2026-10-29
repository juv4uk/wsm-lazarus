{ Графічний фізичний оглядач байтів SENS. Це транспорт, не семантика. }
program sens_bait_ogliad;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids,
  Dialogs, wsm.t5m, wsm.t5madmission, wsm.d2source, wsm.physloc;
const MaxVisibleBytes = 4096;
type
  TBaitWindow = class(TForm)
  private
    FGrid: TStringGrid;
    FStatus: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FPhysical: RawByteString;
    procedure ClearView;
    procedure OpenClicked(Sender: TObject);
    procedure Require(Condition: Boolean; const Reason: String);
    function ExplainBadT5M(const Physical: RawByteString;
      const Problem: String): String;
    procedure WriteBadFixture(const Path: String;
      const Physical: RawByteString);
    procedure CheckBadFixture(const Path: String;
      const Physical: RawByteString; const Expected: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysical(const Path: String): Boolean;
    procedure SelfCheck(const GoodFile, BadFile, EmptyFile: String);
  end;
var Window: TBaitWindow;

constructor TBaitWindow.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — фізичні байти';
  Width := 690; Height := 640; Position := poScreenCenter;
  FOpen := TButton.Create(Self);
  FOpen.Parent := Self;
  FOpen.SetBounds(12, 12, 270, 36);
  FOpen.Caption := 'Відкрити двійковий файл .sens';
  FOpen.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Виберіть фізичний файл SENS';
  FDialog.Filter := 'Фізична SENS (*.sens)|*.sens';
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(12, 56, 640, 28);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.SetBounds(12, 88, 650, 490);
  FGrid.ColCount := 3;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 2;
  FGrid.ColWidths[0] := 160;
  FGrid.ColWidths[1] := 160;
  FGrid.ColWidths[2] := 220;
  FGrid.Cells[0, 0] := 'Адреса байта (0-based)';
  FGrid.Cells[1, 0] := 'Байт (hex)';
  FGrid.Cells[2, 0] := 'Байт (десятковий)';
  ClearView;
end;

procedure TBaitWindow.Require(Condition: Boolean; const Reason: String);
begin
  if not Condition then raise Exception.Create('перевірка вікна: ' + Reason);
end;

{ Лише якщо чинний T5M codec уже ВІДХИЛИВ байти, отримати
  фізичну адресу від злитого потокового preflight. Додатковий
  D2 parser у цій гілці не дає права визначати викличність.
  Позитивна hex-таблиця ніколи НЕ залежить від D2 admission:
  огляд канонічного T5M не тотожний виконанню програми. }
function TBaitWindow.ExplainBadT5M(const Physical: RawByteString;
  const Problem: String): String;
var
  Input: TMemoryStream;
  Document: TD2Document;
  Spans: TPhysicalWordSpans;
begin
  Result := Problem;
  Input := TMemoryStream.Create;
  Document := nil;
  try
    if Length(Physical)>0 then
      Input.WriteBuffer(Physical[1],Length(Physical));
    Input.Position := 0;
    try
      Document := ReadCheckedD2WideLocatedStream(Input,Spans);
    except
      on E: ET5MAdmissionError do
        Result := 'байт='+IntToStr(E.ByteOffset)+
          ' трит='+IntToStr(E.TritOffset)+
          ' слово='+IntToStr(E.WordIndex)+': '+Problem;
      on E: Exception do begin
        { Якщо інший host-етап зупинився раніше за preflight,
          залишити первинне повідомлення codec, не вигадувати позицію. }
      end;
    end;
  finally
    Document.Free;
    Input.Free;
  end;
end;

{ Лише самоперевірка: Path — тимчасова fixture з shell mktemp,
  не вихід користувача. Звичайне вікно ніколи не записує .sens. }
procedure TBaitWindow.WriteBadFixture(const Path: String;
  const Physical: RawByteString);
var Output: TFileStream;
begin
  Output := TFileStream.Create(Path,fmCreate);
  try
    if Length(Physical)>0 then
      Output.WriteBuffer(Physical[1],Length(Physical));
  finally Output.Free end;
end;

procedure TBaitWindow.CheckBadFixture(const Path: String;
  const Physical: RawByteString; const Expected: String);
begin
  WriteBadFixture(Path,Physical);
  Require(not LoadPhysical(Path),'пошкоджений T5M був прийнятий');
  Require(Pos(Expected,FStatus.Caption)>0,
    'відсутня адреса T5M '+Expected+'; '+FStatus.Caption);
  Require((FPhysical='') and (FGrid.RowCount=2) and
    (FGrid.Cells[0,1]='') and (FGrid.Cells[1,1]='') and
    (FGrid.Cells[2,1]=''),'після T5M-помилки залишено старі байти');
end;

procedure TBaitWindow.ClearView;
var I: Integer;
begin
  FPhysical := '';
  FGrid.RowCount := 2;
  for I := 0 to 2 do FGrid.Cells[I, 1] := '';
  FStatus.Caption := 'Тільки фізичні байти; виконання та мовна викличність не визначаються.';
end;

function TBaitWindow.LoadPhysical(const Path: String): Boolean;
var
  Stream: TFileStream;
  Physical: RawByteString;
  Words: TExactWords;
  I: SizeInt;
begin
  Result := False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(Path)) <> '.sens' then
      raise Exception.Create('потрібен фізичний .sens');
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size < 1) or (Stream.Size > MaxVisibleBytes) then
        raise Exception.Create('фізичний файл порожній або більший за 4096 байтів');
      SetLength(Physical, SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1], Length(Physical));
    finally Stream.Free end;
    DecodeT5M(Physical, Words);
    { Звірено байтову канонічність чинним T5M, до публікації таблиці. }
    if EncodeT5M(Words) <> Physical then
      raise Exception.Create('не канонічне фізичне подання');
    FGrid.RowCount := Length(Physical) + 1;
    for I := 0 to Length(Physical)-1 do begin
      FGrid.Cells[0, I+1] := IntToStr(I);
      FGrid.Cells[1, I+1] := IntToHex(Ord(Physical[I+1]), 2);
      FGrid.Cells[2, I+1] := IntToStr(Ord(Physical[I+1]));
    end;
    FPhysical := Physical;
    FStatus.Caption := 'Перевірено байтів: ' + IntToStr(Length(Physical)) +
      '; точних двійкових слів: ' + IntToStr(Length(Words)) +
      '; семантика не перевірялася.';
    Result := True;
  except
    on E: ET5MError do begin
      ClearView;
      FStatus.Caption := 'Помилка T5M: '+ExplainBadT5M(Physical,E.Message);
    end;
    on E: Exception do begin
      ClearView;
      FStatus.Caption := 'Помилка: ' + E.Message;
    end;
  end;
end;

procedure TBaitWindow.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then LoadPhysical(FDialog.FileName);
end;

procedure TBaitWindow.SelfCheck(const GoodFile, BadFile, EmptyFile: String);
var GoodBytes: RawByteString;
begin
  Require(LoadPhysical(GoodFile), 'допуск канонічного T5M');
  Require(Length(FPhysical) = 4, 'чотири фізичних байти');
  Require(FGrid.RowCount = 5, 'чотири рядки байтів');
  Require((FGrid.Cells[0, 1] = '0') and
    (FGrid.Cells[0, 4] = '3'), 'точні фізичні адреси');
  Require((FGrid.Cells[1, 1] = IntToHex(Ord(FPhysical[1]),2)) and
    (FGrid.Cells[2, 4] = IntToStr(Ord(FPhysical[4]))), 'показ реальних байтів');
  GoodBytes := FPhysical;
  { 01 — цілком канонічний T5M, хоч і неправильне D2 закриття.
    ВІКНО БАЙТІВ не має вимагати D2 AST для позитивного огляду. }
  WriteBadFixture(BadFile,#53);
  Require(LoadPhysical(BadFile),'канонічний байт D2:01 відхилено');
  Require((FPhysical=#53) and (FGrid.Cells[1,1]='35'),
    'оглядач байтів помилково вимагає D2 parser');
  Require(LoadPhysical(GoodFile),'повторне відкриття pinned T5M');
  CheckBadFixture(BadFile,#243,'байт=0 трит=0 слово=1');
  CheckBadFixture(BadFile,GoodBytes+#243,
    'байт=4 трит=20 слово=7');
  CheckBadFixture(BadFile,#242,'байт=0 трит=4 слово=1');
  CheckBadFixture(BadFile,#72,'байт=0 трит=3 слово=2');
  Require(LoadPhysical(GoodFile),'відновлення після фізичних відмов');
  Require((FPhysical=GoodBytes) and (FGrid.RowCount=5),
    'відновлення не відобразило всі чотири фізичні байти');
  Require(not LoadPhysical(EmptyFile), 'відхилити порожній файл');
  Require((FPhysical = '') and (FGrid.Cells[1, 1] = ''), 'очистити порожній ввід');
  Require(not LoadPhysical('відсутній-файл.sens'), 'відхилити відсутній файл');
  Require(FPhysical = '', 'очистити відсутній файл');
  WriteLn('LCL-БАЙТИ-АДРЕСИ-ГАРАЗД GTK2=так T5M=канонічний ',
    'байт/трит/слово=точно пізній-байт=4 ',
    'padding/separator=адресовано D2=не-вимагати ',
    'старі-байти=очищено відновлення=так');
  WriteLn('LCL-БАЙТИ-ГАРАЗД Lazarus=GTK2 фізичних-байтів=4 ',
    'адреси=точні T5M=перевірено помилки=очищено семантика=ні');
end;

begin
  Application.Initialize;
  Application.Title := 'SENS — фізичні байти';
  Application.CreateForm(TBaitWindow, Window);
  if (ParamCount > 0) and (ParamStr(1) = '--самоперевірка') then begin
    if ParamCount <> 4 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2), ParamStr(3), ParamStr(4));
    except on E: Exception do begin
      WriteLn(StdErr, 'LCL-БАЙТИ-ПОМИЛКА ', E.Message);
      Halt(1);
    end end;
  end else begin
    if ParamCount = 1 then Window.LoadPhysical(ParamStr(1));
    Application.Run;
  end;
end.
