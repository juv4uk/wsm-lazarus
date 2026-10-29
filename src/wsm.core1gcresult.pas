{ G3.45: GC-керований фізичний РЕЗУЛЬТАТ справжнього Core1 виклику.
  Закони: лише pinned external/sens; виконавець — wsm.core1first;
  життєвий цикл — той самий wsm.gcclosure -> wsm.gc mark-and-sweep.
  Це не повторне створення GC, не другий evaluator і не повний REPL.
  Внутрішній ключ є host-міткою одного слота з першого pinned D7 glyph,
  НЕ юридичною ідентичністю цілого D7-імені або D1-предикатом. }
unit wsm.core1gcresult;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.core1first, wsm.gcclosure, wsm.domain;
type
  ECore1GCResultError=class(Exception);
  TCore1GCResult=class
  private
    FEngine:TCore1FirstRuntime; { owned; must outlive calls }
    FBridge:TGCClosureBridge;   { owned; must outlive capture }
    FLast:TGCClosure;           { owned GC root of last result }
    FSlot:TDomainKey;           { host-local slot, not SENS function ID }
  public
    constructor Create(const PinnedSensRoot,WorkspaceRoot:String);
    destructor Destroy; override;
    { Вхід: одна packed .sens форма виклику першого Core1 DEFINE.
      Вихід: канонічний T5M одного атома (D1 або opaque Wn).
      При відмові попередній результат/root залишається цілим. }
    function ExecutePhysical(const Physical:RawByteString):RawByteString;
    function CurrentPhysical:RawByteString;
    procedure ReleaseCurrent;
    function Collect:SizeInt;
    function LiveCount:SizeInt;
    function RootCount:SizeInt;
    function HeapSlots:SizeInt;
    function MetadataTokens:SizeInt;
  end;
implementation
uses wsm.t5m;

constructor TCore1GCResult.Create(const PinnedSensRoot,WorkspaceRoot:String);
var First:RawByteString;
begin
  inherited Create;
  FEngine:=nil;FBridge:=nil;FLast:=nil;
  try
    FEngine:=TCore1FirstRuntime.Create(PinnedSensRoot,WorkspaceRoot);
    First:=FEngine.FirstIdentifier;
    if (Length(First)<7) or (Length(First) mod 7<>0) then
      raise ECore1GCResultError.Create(
        'перший фізичний Core1 не має точного D7 ідентифікатора');
    { Лише локальна мітка результату. Повне ім'я перевіряє FEngine;
      цей 7-бітний glyph НЕ використовується як SENS callable key. }
    FSlot:=ExactKey(Copy(First,1,7));
    FBridge:=TGCClosureBridge.Create;
  except
    FreeAndNil(FBridge);FreeAndNil(FEngine);
    raise;
  end;
end;

destructor TCore1GCResult.Destroy;
begin
  FLast.Free;
  FBridge.Free;
  FEngine.Free;
  inherited Destroy;
end;

{ Всі тимчасові TD2 є приватними для FEngine. Тут є тільки canonical
  packed T5M, одна локальна scoped activation і один captured root;
  локальний scope знімається незалежно від успіху/помилки.
  Root утримує фізичні байти після звільнення activation, а штатний
  Collect звільняє попередню відповідь після atomically committed swap.
  Питання: чому виконання передує GC-алокації? Чому root після scope?
  Чому slot не є іменем функції? Чому не копіюємо SENS selector?
  Що відбувається, якщо Capture або BindPhysical відхилено? }
function TCore1GCResult.ExecutePhysical(
  const Physical:RawByteString):RawByteString;
var Answer:RawByteString; Words:TExactWords;
    Activation:TGCActivation; Captured:TGCClosure;
begin
  { Справжній виклик, а не відтворення закону в Pascal. }
  Answer:=FEngine.ExecutePhysicalCall(Physical);
  DecodeT5M(Answer,Words);
  if (Length(Words)<>1) or (EncodeT5M(Words)<>Answer) then
    raise ECore1GCResultError.Create(
      'цей GC-зріз допускає лише канонічну одноатомну відповідь');
  Activation:=nil;Captured:=nil;
  try
    Activation:=FBridge.BeginActivation;
    FBridge.BindPhysical(Activation,FSlot,Answer,Length(Words[0]));
    Captured:=FBridge.Capture(Activation,1);
    { Публікуємо ТІЛЬКИ після створення нового захопленого кореня.
      Старе замикання звільняємо після swap, не до першого виконання. }
    FreeAndNil(FLast);
    FLast:=Captured;
    Captured:=nil;
  finally
    Captured.Free;
    Activation.Free;
  end;
  FBridge.Collect; { existing wsm.gc mark-and-sweep, not our GC }
  Result:=CurrentPhysical;
end;

function TCore1GCResult.CurrentPhysical:RawByteString;
begin
  if FLast=nil then
    raise ECore1GCResultError.Create('немає живого GC-результату Core1');
  Result:=FBridge.ResolveClosure(FLast,FSlot);
end;

procedure TCore1GCResult.ReleaseCurrent;
begin
  FreeAndNil(FLast);
  FBridge.Collect;
end;

function TCore1GCResult.Collect:SizeInt;
begin Result:=FBridge.Collect end;
function TCore1GCResult.LiveCount:SizeInt;
begin Result:=FBridge.LiveCount end;
function TCore1GCResult.RootCount:SizeInt;
begin Result:=FBridge.RootCount end;
function TCore1GCResult.HeapSlots:SizeInt;
begin Result:=FBridge.Heap.SlotCount end;
function TCore1GCResult.MetadataTokens:SizeInt;
begin Result:=FBridge.StoredTokens end;
end.
