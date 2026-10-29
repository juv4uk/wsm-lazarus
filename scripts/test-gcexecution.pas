{ Фізичний executor справді виконує D1/D3, TGCHeap справді робить GC;
  тест НЕ вдає бібліотечне виконання Core1 або GC приватного evaluator. }
program test_gcexecution;
{$mode objfpc}{$H+}
uses SysUtils, wsm.gc, wsm.gcexecution, wsm.t5m, wsm.binaryexec;
var
  A,B,C,D:TGCHandle;
  Outer, Inner, ShortScope, Foreign:TGCFrameToken;
  G, Other:TGCExecution;
  I, Checks: SizeInt;
  Failed: Boolean;

procedure Check(OK:Boolean; const Why:String);
begin
  Inc(Checks);
  if not OK then begin WriteLn(StdErr,'CORE1-GC-ПРОВАЛ: ',Why); Halt(1); end;
end;

function Physical(const Inputs: array of RawByteString): RawByteString;
var W: TExactWords; K: SizeInt;
begin
  SetLength(W,Length(Inputs));
  for K:=0 to High(Inputs) do W[K]:=Inputs[K];
  Result:=EncodeT5M(W);
end;

procedure RejectStale(const H:TGCHandle);
var Refused: Boolean;
begin
  Refused:=False;
  try G.PhysicalOf(H); except on E:EGCExecution do Refused:=True; end;
  Check(Refused,'дозволено читати stale або чужу фізичну відповідь');
end;

begin
  Checks:=0;
  G:=TGCExecution.Create('external/sens');
  Other:=TGCExecution.Create('external/sens');
  try
    Outer:=G.BeginScope;
    try
      A:=G.ExecutePhysical(Physical(['1']),Outer);
      Check(G.PhysicalOf(A)=Physical(['1']),
        'справжнє фізичне виконання D1:1 не зберегло байти');
      Check((G.LiveCount=1) and (G.ScopeDepth=1) and
        (G.ScopedRoots=1),'GC не зареєстрував корінь активного стеку');
      Inner:=G.BeginScope;
      try
        B:=G.ExecutePhysical(
          Physical(['10','001','10','0','11','1','01','01']),Inner);
        Check(G.PhysicalOf(B)=
          Physical(['10','0','11','1','01']),
          'цитування фізичної D2 пари не виконано');
        Check((G.Collect=0) and (G.LiveCount=2),
          'вкладені корені не втримали фізичні значення');
        G.Link(A,B);
        G.Link(B,A);
        Check((G.ScopedRoots=2) and (G.ScopeDepth=2),
          'вкладена область коренів неактивна');
      finally G.EndScope(Inner); end;
      Check((G.ScopedRoots=1) and (G.Collect=0) and
        G.IsAlive(B),'доступний через closure-like граф вузол зник');
      Check(G.PhysicalOf(B)=Physical(['10','0','11','1','01']),
        'досяжна через edge фізична D2-пара пошкоджена');

      Failed:=False;
      try G.ExecutePhysical(Physical(['10','000','000','01']),Outer);
      except on E:EBinaryExecutionError do
        Failed:=(E.WordIndex>0); end;
      Check(Failed and (G.LiveCount=2) and
        (G.PhysicalOf(A)=Physical(['1'])),
        'невиклична голова D3 не відхилена / втрачено попередню відповідь');
      Failed:=False;
      try G.ExecutePhysical(#243,Outer);
      except on E:EBinaryExecutionError do Failed:=True; end;
      Check(Failed and (G.LiveCount=2),'пошкоджений фізичний T5M не відхилено');
      Foreign:=Other.BeginScope;
      try
        Failed:=False;
        try G.ExecutePhysical(Physical(['1']),Foreign);
        except on E:EGCExecution do Failed:=True; end;
        Check(Failed and (G.LiveCount=2),
          'токен чужої купи не відхилено перед виконанням');
        D:=Other.ExecutePhysical(Physical(['0']),Foreign);
        Check((Other.PhysicalOf(D)=Physical(['0'])) and
          (not G.IsAlive(D)),
          'фізичні значення різних GC-куч ототожнено');
        RejectStale(D);
      finally Other.EndScope(Foreign); end;
    finally G.EndScope(Outer); end;

    Check((G.ScopeDepth=0) and (G.ScopedRoots=0) and
      (G.Collect=2) and (G.LiveCount=0),
      'недосяжний цикл не зібрано штатним mark/sweep');
    RejectStale(A); RejectStale(B);

    ShortScope:=G.BeginScope;
    try
      C:=G.ExecutePhysical(Physical(['0']),ShortScope);
      Check(G.PhysicalOf(C)=Physical(['0']),
        'повторно використана GC-комірка пошкодила фізичний нуль');
      Check((not G.IsAlive(A)) and (not G.IsAlive(B)) and
        (G.SlotCount=2), 'reuse втратив покоління або виростив heap');
      RejectStale(A); RejectStale(B);
    finally G.EndScope(ShortScope); end;
    Check((G.Collect=1) and (G.LiveCount=0),
      'корінь після завершення області лишився');
    RejectStale(C);

    for I:=1 to 512 do begin
      ShortScope:=G.BeginScope;
      try
        if Odd(I) then A:=G.ExecutePhysical(Physical(['1']),ShortScope)
        else A:=G.ExecutePhysical(Physical(['0']),ShortScope);
        Check((G.LiveCount=1) and (G.Collect=0) and
          G.IsAlive(A),'довгий сеанс загубив корінь');
      finally G.EndScope(ShortScope); end;
      Check((G.Collect=1) and (G.LiveCount=0) and
        (G.SlotCount=2),'довгий сеанс не відновлює GC пам’ять');
      RejectStale(A);
    end;

    Check(Other.Collect=1,'інша незалежна GC купа не відновлена');
    WriteLn('CORE1-GC-МЕЖА-ГАРАЗД checks=',Checks,
      ' real-binary=D1/D3 exact-T5M=так cycles=2 reused=512 ',
      'scope=stack stale=відхилено foreign=відхилено ',
      'Core1=НЕ_ВИКОНАНО GC-evaluator=НЕ_ІНТЕГРОВАНО');
  finally Other.Free; G.Free; end;
end.
{ Питання: (1) Чому цей тест доводить реальне D3 виконання, але НЕ Core1?
  (2) Навіщо два незалежні heap GUID? (3) Чому D2:000 не є D1:0?
  (4) Чому два недосяжні вузли циклу GC збирає разом?
  (5) Чому slot reuse не дозволяє старому handle зчитати нові байти? }
