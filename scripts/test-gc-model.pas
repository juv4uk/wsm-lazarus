{ G3.42: незалежна deterministic model-based перевірка існуючого GC.
  Це host-граф, НЕ визначення SENS/D1/D12, НЕ новий collector.
  Контрольна модель рахує reachable roots/edges без доступу до GC internals. }
program test_gc_model;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.gc;

type
  TModelCell = record
    Handle: TGCHandle;
    Payload: Int64;
    Alive: Boolean;
    Permanent, Scoped: SizeInt;
    Edges: array of SizeInt;
  end;
  TModelCells = array of TModelCell;
  TScopeMembers = array of SizeInt;

const MaxLive = 96; MaxDepth = 4; Steps = 2400;
var
  Heap: TGCHeap;
  Cells: TModelCells;
  Tokens: array[0..MaxDepth-1] of TGCFrameToken;
  ScopeMembers: array[0..MaxDepth-1] of TScopeMembers;
  Depth: SizeInt;
  Rng: Cardinal;
  CollectionCount, Allocations, Rejections: SizeInt;

procedure Need(OK: Boolean; const Why: String);
begin
  if not OK then
    raise Exception.Create('GC-МОДЕЛЬ-ПОМИЛКА: '+Why+
      ' seed='+IntToHex(Rng,8));
end;

{ Локальний xorshift32: відтворюваний порядок дій, не генератор законів.
  Cardinal переповнення модульне; усі вибори — host-індекси.
  Питання: чому фіксований seed? Які незалежні стани моделюємо?
  Чому random дії не змінюють закон SENS? Які операції негативні? }
function NextRandom: Cardinal;
var X: Cardinal;
begin
  X:=Rng;
  X:=X xor (X shl 13);
  X:=X xor (X shr 17);
  X:=X xor (X shl 5);
  Rng:=X;
  Result:=X;
end;

function LiveCountModel: SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=0 to High(Cells) do
    if Cells[I].Alive then Inc(Result);
end;

function PickLive(out Index: SizeInt): Boolean;
var I,N:SizeInt;
begin
  N:=LiveCountModel;
  Result:=N>0;
  if not Result then Exit;
  N:=SizeInt(NextRandom mod Cardinal(N));
  for I:=0 to High(Cells) do
    if Cells[I].Alive then begin
      if N=0 then begin Index:=I; Exit end;
      Dec(N);
    end;
  Need(False,'відсутній живий вузол моделі');
end;

function PickRooted(out Index:SizeInt):Boolean;
var I,N:SizeInt;
begin
  N:=0;
  for I:=0 to High(Cells) do
    if Cells[I].Alive and (Cells[I].Permanent>0) then Inc(N);
  Result:=N>0;
  if not Result then Exit;
  N:=SizeInt(NextRandom mod Cardinal(N));
  for I:=0 to High(Cells) do
    if Cells[I].Alive and (Cells[I].Permanent>0) then begin
      if N=0 then begin Index:=I; Exit end;
      Dec(N);
    end;
  Need(False,'відсутній постійний корінь');
end;

procedure AllocateCell;
var I:SizeInt;
begin
  if LiveCountModel>=MaxLive then Exit;
  I:=Length(Cells);
  SetLength(Cells,I+1);
  Cells[I].Handle:=Heap.Allocate(I+70001);
  Cells[I].Payload:=I+70001;
  Cells[I].Alive:=True;
  Cells[I].Permanent:=0;
  Cells[I].Scoped:=0;
  SetLength(Cells[I].Edges,0);
  Inc(Allocations);
end;

procedure AddPermanent;
var I:SizeInt;
begin
  if not PickLive(I) then Exit;
  Heap.AddRoot(Cells[I].Handle);
  Inc(Cells[I].Permanent);
end;

procedure DropPermanent;
var I:SizeInt;
begin
  if not PickRooted(I) then Exit;
  Heap.RemoveRoot(Cells[I].Handle);
  Dec(Cells[I].Permanent);
end;

procedure LinkRandom;
var A,B,J:SizeInt; Seen:Boolean;
begin
  if not PickLive(A) then Exit;
  if not PickLive(B) then Exit;
  if Length(Cells[A].Edges)>=12 then Exit;
  Seen:=False;
  for J:=0 to High(Cells[A].Edges) do
    if Cells[A].Edges[J]=B then Seen:=True;
  if Seen then Exit;
  Heap.Link(Cells[A].Handle,Cells[B].Handle);
  J:=Length(Cells[A].Edges);
  SetLength(Cells[A].Edges,J+1);
  Cells[A].Edges[J]:=B;
end;

procedure UnlinkRandom;
var A,J,B,K:SizeInt;
begin
  if not PickLive(A) then Exit;
  J:=Length(Cells[A].Edges);
  if J=0 then Exit;
  K:=SizeInt(NextRandom mod Cardinal(J));
  B:=Cells[A].Edges[K];
  Need(Cells[B].Alive,'ребро з живого до звільненого');
  Heap.Unlink(Cells[A].Handle,Cells[B].Handle);
  for J:=K to High(Cells[A].Edges)-1 do
    Cells[A].Edges[J]:=Cells[A].Edges[J+1];
  SetLength(Cells[A].Edges,Length(Cells[A].Edges)-1);
end;

procedure OpenScope;
begin
  if Depth=MaxDepth then Exit;
  Tokens[Depth]:=Heap.BeginRootScope;
  SetLength(ScopeMembers[Depth],0);
  Inc(Depth);
end;

procedure PinRandom;
var I,J:SizeInt;
begin
  if (Depth=0) or (not PickLive(I)) then Exit;
  Heap.RootInScope(Tokens[Depth-1],Cells[I].Handle);
  Inc(Cells[I].Scoped);
  J:=Length(ScopeMembers[Depth-1]);
  SetLength(ScopeMembers[Depth-1],J+1);
  ScopeMembers[Depth-1][J]:=I;
end;

procedure CloseScope;
var I,J:SizeInt;
begin
  if Depth=0 then Exit;
  J:=Depth-1;
  Heap.EndRootScope(Tokens[J]);
  for I:=0 to High(ScopeMembers[J]) do begin
    Need(Cells[ScopeMembers[J][I]].Scoped>0,'від\u2019ємний scoped корінь');
    Dec(Cells[ScopeMembers[J][I]].Scoped);
  end;
  SetLength(ScopeMembers[J],0);
  Dec(Depth);
end;

{ Reference graph traversal: тільки host-модель; незалежна від Heap.Collect.
  Вхід: ті ж явні root counters і направлені edges; результат:
  позначення досяжності для кожної алокації та число звільнених.
  Heap зберігає owner/slot/generation; модель ніколи їх не переписує.
  Питання: чому цикл не призводить до нескінченності?
  Чому мітка D1 не потрібна? Як відрізняємо stale slot? Що таке root? }
procedure CollectAndCompare;
var Marked:array of Boolean; Queue:array of SizeInt;
    I,J,Used,Cursor,Freed,Got,Live:SizeInt;
  procedure Mark(Index:SizeInt);
  begin
    Need((Index>=0) and (Index<Length(Cells)),'неіснуючий сусід');
    Need(Cells[Index].Alive,'досяжне ребро на звільнену клітинку');
    if Marked[Index] then Exit;
    Marked[Index]:=True;
    Queue[Used]:=Index;
    Inc(Used);
  end;
begin
  SetLength(Marked,Length(Cells));
  SetLength(Queue,Length(Cells));
  Used:=0;Cursor:=0;
  for I:=0 to High(Cells) do
    if Cells[I].Alive and ((Cells[I].Permanent>0) or
        (Cells[I].Scoped>0)) then Mark(I);
  while Cursor<Used do begin
    I:=Queue[Cursor];
    Inc(Cursor);
    for J:=0 to High(Cells[I].Edges) do
      Mark(Cells[I].Edges[J]);
  end;
  Freed:=0;
  for I:=0 to High(Cells) do
    if Cells[I].Alive and (not Marked[I]) then Inc(Freed);
  Got:=Heap.Collect;
  Need(Got=Freed,'кількість зібраних клітинок відрізняється від моделі');
  for I:=0 to High(Cells) do
    if Cells[I].Alive and not Marked[I] then Cells[I].Alive:=False;
  Live:=LiveCountModel;
  Need(Heap.LiveCount=Live,'живі клітинки не дорівнюють моделі');
  Need(Heap.FreeCount+Heap.LiveCount=Heap.SlotCount,
    'порушено інваріант free/live slot');
  for I:=0 to High(Cells) do begin
    Need(Heap.IsAlive(Cells[I].Handle)=Cells[I].Alive,
      'неправильна generation/досяжність');
    if Cells[I].Alive then
      Need(Heap.ValueOf(Cells[I].Handle)=Cells[I].Payload,
        'пошкоджений живий payload');
  end;
  Inc(CollectionCount);
end;

procedure CheckRejected;
var I:SizeInt; Rejected:Boolean;
begin
  if (Depth>=2) then begin
    Rejected:=False;
    try Heap.EndRootScope(Tokens[Depth-2]);
    except on E:EGCError do Rejected:=True; end;
    Need(Rejected,'не-LIFO закриття області прийнято');
    Need(Heap.ScopeDepth=Depth,'помилка LIFO змінила стек');
    Inc(Rejections);
  end;
  for I:=High(Cells) downto 0 do
    if not Cells[I].Alive then begin
      Rejected:=False;
      try Heap.AddRoot(Cells[I].Handle);
      except on E:EGCError do Rejected:=True; end;
      Need(Rejected,'stale handle став постійним коренем');
      Rejected:=False;
      try Heap.SetValue(Cells[I].Handle,-1);
      except on E:EGCError do Rejected:=True; end;
      Need(Rejected,'stale handle змінив значення');
      Inc(Rejections,2);
      Exit;
    end;
end;

procedure RunSeed(Seed:Cardinal);
var I,J:SizeInt;
begin
  Rng:=Seed;
  Heap:=TGCHeap.Create;
  SetLength(Cells,0);
  Depth:=0;
  try
    for I:=1 to Steps do begin
      case (NextRandom mod 11) of
        0,1:AllocateCell;
        2:AddPermanent;
        3:DropPermanent;
        4:LinkRandom;
        5:UnlinkRandom;
        6:OpenScope;
        7:PinRandom;
        8:CloseScope;
        9:CollectAndCompare;
        10:CheckRejected;
      end;
      if I mod 29=0 then CollectAndCompare;
    end;
    while Depth>0 do CloseScope;
    for J:=0 to High(Cells) do
      while Cells[J].Alive and (Cells[J].Permanent>0) do begin
        Heap.RemoveRoot(Cells[J].Handle);
        Dec(Cells[J].Permanent);
      end;
    Need(Heap.RootCount=0,'залишені постійні корені');
    Need(Heap.ScopeDepth=0,'залишені стекові області');
    CollectAndCompare;
    Need(Heap.LiveCount=0,'після завершення сеансу витік клітинок');
    CheckRejected;
  finally
    Heap.Free;
  end;
end;

{ Explicit exception path: try/finally має звільнити stack root.
  Це не фіналізація Pascal-managed значень і не автоматичний Core1 GC.
  Питання: чому без finally root залишився б? Чи звільняє EndRootScope
  об'єкт негайно? Чому gen-count захищає повторно зайнятий slot? }
procedure CheckExceptionCleanup;
var H:TGCHeap; A,B,Fresh:TGCHandle; T:TGCFrameToken;
    Rejected,Thrown:Boolean;
begin
  H:=TGCHeap.Create;
  try
    A:=H.Allocate(900); B:=H.Allocate(901);
    H.Link(A,B); H.Link(B,A);
    T:=H.BeginRootScope;
    Thrown:=False;
    try
      H.RootInScope(T,A);
      Need(H.Collect=0,'reachable цикл перед винятком звільнено');
      try
        raise Exception.Create('контрольований виняток сеансу');
      except on E:Exception do Thrown:=True; end;
    finally H.EndRootScope(T) end;
    Need(Thrown,'виняток не виконано');
    Need((H.ScopeDepth=0) and (H.ScopedRootCount=0),
      'корені після винятку залишились');
    Need(H.Collect=2,'цикл після винятку не звільнено');
    Fresh:=H.Allocate(902);
    Need(H.IsAlive(Fresh) and (not H.IsAlive(A)),
      'повторне використання прийняло stale посилання');
    Rejected:=False;
    try H.Link(Fresh,A);
    except on E:EGCError do Rejected:=True; end;
    Need(Rejected,'stale handle можна прив\u2019язати');
    Need(H.Collect=1,'тимчасовий результат не звільнено');
    Inc(Rejections);
  finally H.Free end;
end;

begin
  try
    CollectionCount:=0;Allocations:=0;Rejections:=0;
    CheckExceptionCleanup;
    RunSeed($12345678);
    RunSeed($9E3779B9);
    RunSeed($DEADBEEF);
    RunSeed($0BADCAFE);
    Need(CollectionCount>200,'замало перевірених GC sweep');
    Need(Allocations>100,'замало життєвих циклів клітинок');
    Need(Rejections>4,'негативні перевірки не виконались');
    WriteLn('GC-МОДЕЛЬ-ГАРАЗД seeds=4 кроків=',Steps*4,
      ' збірок=',CollectionCount,' алокацій=',Allocations,
      ' відмов=',Rejections,' root-LIFO=так stale=відхилено');
    WriteLn('GC-МОДЕЛЬ-МЕЖА Core1=НЕ-ВИКОНУЄТЬСЯ GC=існуючий модель=host');
  except
    on E:Exception do begin
      WriteLn(StdErr,'GC-МОДЕЛЬ-БЛОК: ',E.Message);
      Halt(1);
    end;
  end;
end.
