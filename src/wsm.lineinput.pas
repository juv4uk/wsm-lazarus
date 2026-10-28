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
    FPending: RawByteString;
    FDepth: SizeInt;
    FString, FEscaped, FInvalidClose: Boolean;
    FMaxBytes: SizeInt;
    procedure Clear;
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
  Clear;
end;

procedure TLineInput.Clear;
begin
  FPending := '';
  FDepth := 0;
  FString := False;
  FEscaped := False;
  FInvalidClose := False;
end;

procedure TLineInput.Cancel;
begin
  Clear;
end;

function TLineInput.PendingBytes: SizeInt;
begin
  Result := Length(FPending);
end;

function TLineInput.FeedLine(const Line: RawByteString): TSessionReplies;
var
  I: SizeInt;
  C: AnsiChar;
  Comment: Boolean;
begin
  SetLength(Result, 0);
  { An explicit line API: one line is one frame. Never reinterpret a CR/LF
    embedded in caller data, and never emit an incomplete buffer to Execute. }
  if (Pos(#10, Line) <> 0) or (Pos(#13, Line) <> 0) then begin
    Clear;
    raise ELineInputError.Create('line contains newline or carriage return');
  end;
  if Length(Line) >= FMaxBytes - Length(FPending) then begin
    Clear;
    raise ELineInputError.Create('pending source exceeds byte limit');
  end;
  FPending := FPending + Line + #10;
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

  if (FDepth <> 0) or FString then Exit;
  { When input is finished or malformed, pass the WHOLE bounded source to
    the existing strict UTF-8 parser. No partial AST or previous form is
    executed before a multiline input has closed. FInvalidClose prevents
    an unmatched ')' from getting hidden by later opening parentheses. }
  try
    Result := FSession.Submit(FPending);
  finally
    Clear;
  end;
end;

function TLineInput.Finish: TSessionReplies;
begin
  SetLength(Result, 0);
  if FPending = '' then Exit;
  try
    { The actual reader supplies the located EOF/unterminated-string error;
      an interactive EOF never silently executes a truncated list. }
    Result := FSession.Submit(FPending);
  finally
    Clear;
  end;
end;

end.
