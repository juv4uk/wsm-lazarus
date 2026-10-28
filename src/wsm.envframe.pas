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
    FCells: array of TFrameCell; { геометричний резерв: тільки перші FUsed видимі }
    FUsed: SizeInt;
    function FindSlot(const Key: TDomainKey): SizeInt;
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
  FUsed := 0;
end;

{ Lower-bound для вже перевіреного exact host-ключа. Лише порядок
  (ширина, біти), не семантичний Dn, числове порівняння чи закон.
  Всі активні комірки [0,FUsed) підтримуються впорядкованими. }
function TEnvFrameImpl.FindSlot(const Key:TDomainKey):SizeInt;
var L,R,M:SizeInt;
begin
  L:=0; R:=FUsed;
  while L<R do begin
    M:=L+(R-L) div 2;
    if (FCells[M].Key.Width<Key.Width) or
       ((FCells[M].Key.Width=Key.Width) and
        (FCells[M].Key.Bits<Key.Bits)) then L:=M+1
    else R:=M;
  end;
  Result:=L;
end;

procedure TEnvFrameImpl.InstallLocal(const Key: TDomainKey; ValueHandle: QWord);
var
  I, Slot, Capacity: SizeInt;
begin
  RequireExactKey(Key);
  Slot:=FindSlot(Key);
  if (Slot<FUsed) and SameKey(FCells[Slot].Key,Key) then
    raise EFrameError.Create('duplicate local physical coordinate');
  { Геометрична місткість: чужий caller не бачить невикористаних комірок.
    TFrameCell не містить керованих полів, зсув робимо присвоєнням.
    FUsed змінюємо лише після повної успішної вставки. }
  if FUsed=Length(FCells) then begin
    Capacity:=Length(FCells);
    if Capacity=0 then Capacity:=8 else Capacity:=Capacity*2;
    SetLength(FCells,Capacity);
  end;
  for I:=FUsed downto Slot+1 do
    FCells[I]:=FCells[I-1];
  FCells[Slot].Key:=Key;
  FCells[Slot].Handle:=ValueHandle;
  Inc(FUsed);
end;

function TEnvFrameImpl.TryResolve(const Key: TDomainKey;
  out ValueHandle: QWord): Boolean;
var
  Slot: SizeInt;
begin
  RequireExactKey(Key);
  Slot:=FindSlot(Key);
  if (Slot<FUsed) and SameKey(FCells[Slot].Key,Key) then begin
    ValueHandle:=FCells[Slot].Handle;
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
