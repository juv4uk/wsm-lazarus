{ G5.2: multiline source accumulator for an injected SENS session executor.
  This is an INPUT mechanism; no read/eval/print loop, no language laws,
  no English-name dispatch, and no claimed SENS runtime or REPL parity.
  The session owns actual UTF-8 validation/AST parsing and preserves frames. }
unit wsm.lineinput;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.session;

type
  ELineInputError = class(Exception);

  TLineInput = class
  private
    FSession: TNativeSession;  { borrowed; caller owns its lifetime }
    FPending: RawByteString; { allocated capacity, not logical text length }
    FPendingLen: SizeInt;
    FDepth: SizeInt;
    FString, FEscaped, FInvalidClose: Boolean;
    FMaxBytes: SizeInt;
    FDispatching: Boolean; { відхилити вкладене редагування під час Submit }
    procedure Clear;
    procedure AppendLine(const Line: RawByteString);
  public
    constructor Create(ASession: TNativeSession; AMaxBytes: SizeInt = 16*1024*1024);
    function FeedLine(const Line: RawByteString): TSessionReplies;
    function Finish: TSessionReplies;
    procedure Cancel;
    function PendingBytes: SizeInt;
  end;

implementation

const MAX_DEPTH = 256;

constructor TLineInput.Create(ASession: TNativeSession; AMaxBytes: SizeInt);
begin
  inherited Create;
  if ASession = nil then raise ELineInputError.Create('missing native session');
  if (AMaxBytes < 1) or (AMaxBytes > 16*1024*1024) then
    raise ELineInputError.Create('invalid buffered input limit');
  FSession := ASession;
  FMaxBytes := AMaxBytes;
  FDispatching := False;
  Clear;
end;

procedure TLineInput.Clear;
begin
  FPending := '';
  FPendingLen := 0;
  FDepth := 0;
  FString := False;
  FEscaped := False;
  FInvalidClose := False;
end;

procedure TLineInput.Cancel;
begin
  if FDispatching then
    raise ELineInputError.Create('заборонено скасовувати ввід під час виконання');
  Clear;
end;

function TLineInput.PendingBytes: SizeInt;
begin
  Result := FPendingLen;
end;

procedure TLineInput.AppendLine(const Line: RawByteString);
var
  Wanted, Capacity: SizeInt;
begin
  { Зростання місткості геометричне. FPendingLen — лише фактичні байти;
    резервна пам'ять ніколи не потрапляє до reader/виконавця. }
  Wanted := FPendingLen + Length(Line) + 1;
  if Wanted > Length(FPending) then begin
    Capacity := Length(FPending);
    if Capacity < 64 then Capacity := 64;
    if Capacity > FMaxBytes then Capacity := FMaxBytes;
    while Capacity < Wanted do begin
      if Capacity > FMaxBytes div 2 then Capacity := FMaxBytes
      else Capacity := Capacity * 2;
    end;
    SetLength(FPending, Capacity);
  end;
  if Length(Line) > 0 then
    Move(Line[1], FPending[FPendingLen + 1], Length(Line));
  FPending[Wanted] := #10;
  FPendingLen := Wanted;
end;

function TLineInput.FeedLine(const Line: RawByteString): TSessionReplies;
var
  I: SizeInt;
  C: AnsiChar;
  Comment: Boolean;
begin
  { Callback виконавця може повернутись сюди, поки зовнішній Submit
    ще використовує попередню форму. Відмовити ДО зміни FPending. }
  if FDispatching then
    raise ELineInputError.Create('заборонено вкладений ввід під час виконання');
  SetLength(Result, 0);
  { An explicit line API: one line is one frame. Never reinterpret a CR/LF
    embedded in caller data, and never emit an incomplete buffer to Execute. }
  if (Pos(#10, Line) <> 0) or (Pos(#13, Line) <> 0) then begin
    Clear;
    raise ELineInputError.Create('line contains newline or carriage return');
  end;
  if Length(Line) >= FMaxBytes - FPendingLen then begin
    Clear;
    raise ELineInputError.Create('pending source exceeds byte limit');
  end;
  AppendLine(Line);
  Comment := False;
  for I := 1 to Length(Line) do begin
    C := Line[I];
    if FString then begin
      if FEscaped then FEscaped := False
      else if C = #92 then FEscaped := True
      else if C = '"' then FString := False;
      Continue;
    end;
    if Comment then Continue;
    case C of
      ';': Comment := True;
      '"': FString := True;
      '(': begin
        Inc(FDepth);
        if FDepth > MAX_DEPTH then begin
          { Syntax-depth is a mechanical bound, not a SENS semantics gate. }
          Clear;
          raise ELineInputError.Create('pending nesting exceeds bound');
        end;
      end;
      ')': begin
        if FDepth = 0 then FInvalidClose := True
        else Dec(FDepth);
      end;
    end;
  end;

  { Після фізичного рядка ми вже додали #10 до FPending. Якщо
    попередній байт рядка був escape (#92) усередині лапок, його
    ціллю є саме вставлений #10, а НЕ перший байт наступного рядка.
    Інакше читач та фреймер розходяться і закрита форма зависає. }
  if FString and FEscaped then FEscaped := False;

  if ((FDepth <> 0) or FString) and not FInvalidClose then Exit;
  { When input is finished or malformed, pass the WHOLE bounded source to
    the existing strict UTF-8 parser. No partial AST or previous form is
    executed before a multiline input has closed. FInvalidClose prevents
    an unmatched ')' from getting hidden by later opening parentheses. }
  FDispatching := True;
  try
    Result := FSession.Submit(Copy(FPending, 1, FPendingLen));
  finally
    FDispatching := False;
    Clear;
  end;
end;

function TLineInput.Finish: TSessionReplies;
begin
  if FDispatching then
    raise ELineInputError.Create('заборонено завершувати ввід під час виконання');
  SetLength(Result, 0);
  if FPendingLen = 0 then Exit;
  { Реентрантні FeedLine/Finish/Cancel не можуть змінити або стерти
    непублічний буфер, доки виконавець читає його повну копію. }
  FDispatching := True;
  try
    { The actual reader supplies the located EOF/unterminated-string error;
      an interactive EOF never silently executes a truncated list. }
    Result := FSession.Submit(Copy(FPending, 1, FPendingLen));
  finally
    FDispatching := False;
    Clear;
  end;
end;

end.
