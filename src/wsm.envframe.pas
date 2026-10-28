{ G3.1 physical lexical frame storage for future native SENS runtime.
  No semantic evaluation, callable decisions or authority tables here.
  All keys come from an upstream-approved binder; width + bits are not laws.
  A QWord cell is an opaque *host storage handle*, never a SENS D1 truth bit. }
unit wsm.envframe;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain;
type
  EFrameError = class(Exception);
  IEnvFrame = interface
    ['{C4F74145-7819-440D-BE7E-C401442CC3B1}']
    procedure InstallLocal(const Key: TDomainKey; ValueHandle: QWord);
    function TryResolve(const Key: TDomainKey; out ValueHandle: QWord): Boolean;
    function Resolve(const Key: TDomainKey): QWord;
  end;

  ICapturedCode = interface
    ['{063C6B86-FB7F-49A3-9268-A15CCF718AB6}']
    function LexicalFrame: IEnvFrame;
    function EntryHandle: QWord;
  end;

function NewEnvFrame(const Parent: IEnvFrame): IEnvFrame;
function CaptureCode(const Frame: IEnvFrame; EntryHandle: QWord): ICapturedCode;

implementation
type
  TFrameCell = record
    Key: TDomainKey;
    Handle: QWord;
  end;
  TEnvFrameImpl = class(TInterfacedObject, IEnvFrame)
  private
    FParent: IEnvFrame;
    FCells: array of TFrameCell;
  public
    constructor Create(const Parent: IEnvFrame);
    procedure InstallLocal(const Key: TDomainKey; ValueHandle: QWord);
    function TryResolve(const Key: TDomainKey; out ValueHandle: QWord): Boolean;
    function Resolve(const Key: TDomainKey): QWord;
  end;
  TCapturedCodeImpl = class(TInterfacedObject, ICapturedCode)
  private
    FFrame: IEnvFrame;
    FEntry: QWord;
  public
    constructor Create(const Frame: IEnvFrame; EntryHandle: QWord);
    function LexicalFrame: IEnvFrame;
    function EntryHandle: QWord;
  end;

procedure RequireExactKey(const Key: TDomainKey);
begin
  { Reuse the existing coordinate mechanism: never reconstruct authority. }
  try
    if KeyBits(Key) = '' then
      raise EFrameError.Create('empty physical coordinate');
  except
    on E: EDomainError do
      raise EFrameError.Create('invalid physical coordinate');
  end;
end;

constructor TEnvFrameImpl.Create(const Parent: IEnvFrame);
begin
  inherited Create;
  FParent := Parent; // reference counted: lexical parent survives scope exit
  SetLength(FCells, 0);
end;

procedure TEnvFrameImpl.InstallLocal(const Key: TDomainKey; ValueHandle: QWord);
var
  I, N: SizeInt;
begin
  RequireExactKey(Key);
  for I := 0 to High(FCells) do
    if SameKey(FCells[I].Key, Key) then
      raise EFrameError.Create('duplicate local physical coordinate');
  N := Length(FCells);
  SetLength(FCells, N + 1);
  FCells[N].Key := Key;
  FCells[N].Handle := ValueHandle;
end;

function TEnvFrameImpl.TryResolve(const Key: TDomainKey;
  out ValueHandle: QWord): Boolean;
var
  I: SizeInt;
begin
  RequireExactKey(Key);
  for I := High(FCells) downto 0 do
    if SameKey(FCells[I].Key, Key) then
    begin
      ValueHandle := FCells[I].Handle;
      Exit(True);
    end;
  if FParent <> nil then
    Exit(FParent.TryResolve(Key, ValueHandle));
  ValueHandle := 0; // only when Result=False: zero itself is valid in a cell
  Result := False;
end;

function TEnvFrameImpl.Resolve(const Key: TDomainKey): QWord;
begin
  if not TryResolve(Key, Result) then
    raise EFrameError.Create('unknown physical coordinate');
end;

constructor TCapturedCodeImpl.Create(const Frame: IEnvFrame; EntryHandle: QWord);
begin
  inherited Create;
  FFrame := Frame;
  FEntry := EntryHandle;
end;

function TCapturedCodeImpl.LexicalFrame: IEnvFrame;
begin
  Result := FFrame;
end;

function TCapturedCodeImpl.EntryHandle: QWord;
begin
  Result := FEntry;
end;

function NewEnvFrame(const Parent: IEnvFrame): IEnvFrame;
begin
  Result := TEnvFrameImpl.Create(Parent);
end;

function CaptureCode(const Frame: IEnvFrame; EntryHandle: QWord): ICapturedCode;
begin
  if Frame = nil then
    raise EFrameError.Create('cannot capture missing lexical frame');
  Result := TCapturedCodeImpl.Create(Frame, EntryHandle);
end;
end.
