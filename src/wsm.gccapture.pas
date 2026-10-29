{ Core1 G3: механічний міст між існуючими wsm.gc та wsm.envframe.
  ЖОДНОГО нового мовного закону, виконання DEFINE або власного GC.
  Купою володіє зовнішній runtime: вона мусить пережити усі ICapturedCode.
  Фізичне представлення: TGCHandle (owner GUID/slot/generation),
  точний TDomainKey і непрозорий host QWord із IEnvFrame. }
unit wsm.gccapture;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.gc, wsm.domain, wsm.envframe;
type
  EGCCaptureError = class(Exception);
  TGCScopedLexical = class
  private
    FHeap: TGCHeap;                 { borrowed; власник — runtime }
    FFrame: IEnvFrame;              { refcounted; незалежне від GC }
    FToken: TGCFrameToken;         { LIFO область активного виклику }
    FAnchor: TGCHandle;            { GC вузол лексичного оточення }
    FScopeOpen: Boolean;
  public
    constructor Create(AHeap:TGCHeap; const Parent:IEnvFrame);
    destructor Destroy; override;
    function LexicalFrame:IEnvFrame;
    function AnchorHandle:TGCHandle;
    procedure BindLocal(const Key:TDomainKey; HostValue:QWord;
      const Cell:TGCHandle);
    procedure LinkAncestorRoot(const Ancestor:TGCHandle);
    function Capture(EntryHandle:QWord):ICapturedCode;
  end;

implementation

type
  { Інтерфейс, переданий runtime, тримає саме GC-корінь замикання.
    Managed FCode тримає захоплене IEnvFrame; корінь звільняється
    тільки коли останнє ICapturedCode знищено. }
  TRootedCapturedCode = class(TInterfacedObject, ICapturedCode)
  private
    FHeap:TGCHeap;
    FAnchor:TGCHandle;
    FCode:ICapturedCode;
  public
    constructor Create(AHeap:TGCHeap; const AAnchor:TGCHandle;
      const ACode:ICapturedCode);
    destructor Destroy; override;
    function LexicalFrame:IEnvFrame;
    function EntryHandle:QWord;
  end;

constructor TRootedCapturedCode.Create(AHeap:TGCHeap;
  const AAnchor:TGCHandle; const ACode:ICapturedCode);
begin
  inherited Create;
  FHeap:=AHeap;
  FAnchor:=AAnchor;
  FCode:=ACode;
end;

destructor TRootedCapturedCode.Destroy;
begin
  { Усі хендли залишаються живими, поки цей root ще встановлений.
    Зовнішня купа мусить пережити цей об'єкт. }
  FHeap.RemoveRoot(FAnchor);
  inherited Destroy;
end;

function TRootedCapturedCode.LexicalFrame:IEnvFrame;
begin
  Result:=FCode.LexicalFrame;
end;

function TRootedCapturedCode.EntryHandle:QWord;
begin
  Result:=FCode.EntryHandle;
end;

constructor TGCScopedLexical.Create(AHeap:TGCHeap; const Parent:IEnvFrame);
begin
  inherited Create;
  if AHeap=nil then
    raise EGCCaptureError.Create('відсутня нативна GC-купа');
  FHeap:=AHeap;
  FScopeOpen:=False;
  FFrame:=NewEnvFrame(Parent);
  FToken:=FHeap.BeginRootScope;
  FScopeOpen:=True;
  try
    FAnchor:=FHeap.Allocate(0);  { тільки host вузол, не D1 або D12 }
    FHeap.RootInScope(FToken,FAnchor);
  except
    FHeap.EndRootScope(FToken);
    FScopeOpen:=False;
    raise;
  end;
end;

destructor TGCScopedLexical.Destroy;
begin
  if FScopeOpen then FHeap.EndRootScope(FToken);
  inherited Destroy;
end;

function TGCScopedLexical.LexicalFrame:IEnvFrame;
begin
  Result:=FFrame;
end;

function TGCScopedLexical.AnchorHandle:TGCHandle;
begin
  Result:=FAnchor;
end;

procedure TGCScopedLexical.BindLocal(const Key:TDomainKey;
  HostValue:QWord; const Cell:TGCHandle);
begin
  { Ніякого перетворення GС slot у QWord. HostValue є непрозорим
    токеном caller, а Cell передано окремо й перевіряється за
    повною ідентичністю купи та поколінням. }
  if not FHeap.IsAlive(Cell) then
    raise EGCCaptureError.Create('чужа або звільнена GC-комірка');
  FHeap.Link(FAnchor,Cell);
  try
    FFrame.InstallLocal(Key,HostValue);
  except
    FHeap.Unlink(FAnchor,Cell);
    raise;
  end;
end;

procedure TGCScopedLexical.LinkAncestorRoot(const Ancestor:TGCHandle);
begin
  { Корінь лексичного предка потрібно передати явно; лише
    refcounted IEnvFrame НЕ тримає GC-комірки живими. }
  FHeap.Link(FAnchor,Ancestor);
end;

function TGCScopedLexical.Capture(EntryHandle:QWord):ICapturedCode;
var Code:ICapturedCode;
begin
  Code:=CaptureCode(FFrame,EntryHandle);
  FHeap.AddRoot(FAnchor);
  try
    Result:=TRootedCapturedCode.Create(FHeap,FAnchor,Code);
  except
    FHeap.RemoveRoot(FAnchor);
    raise;
  end;
end;

end.
