(* test-eval.pas — M0.6 tests for the evaluator skeleton (#8).
 *
 * Builds expressions directly with wsm.values primitives (no reader
 * involved -- the reader is a separate, already-tested layer) against
 * the REAL pinned lib/surface/semantic-registry.lisp, and proves:
 *   1. quote/cons/car/cdr/lambda/cond/atom/eq behave correctly;
 *   2. cond fails closed (explicit error) on clause exhaustion, no
 *      silent fall-through;
 *   3. an unbound variable raises, never resolves to invented semantics;
 *   4. dispatch is genuinely by semantic ID, not spelling: the Ukrainian
 *      alias "як-є" for quote is exercised and must behave identically
 *      to the English spelling "quote";
 *   5. a deep self-application tail-recursion (no `define`, no mutable
 *      global env) completes without a Pascal stack overflow -- the
 *      trampoline's own {expr, env} loop-local pair is doing the actual
 *      tail-call work, not the host call stack.
 *
 * MECHANISM BUDGET (issue #9): the deep-recursion witness walks a
 * pre-built list via cdr/atom instead of counting a number down via
 * arithmetic -- '-'/'=' were audited out of wsm.eval.pas (no upstream-
 * owned witness in Core1's own primitive table), so this test no
 * longer needs them either. *)
program test_eval;

{$mode objfpc}{$H+}

uses
  sysutils, classes,
  wsm.values, wsm.registry, wsm.historical, wsm.eval;

const
  REGISTRY_PATH = 'external/my-lisp/lib/surface/semantic-registry.lisp';
  HISTORICAL_MAP_PATH = 'external/my-lisp/contracts/core1-historical-sid-map.lisp';
  DEEP_N = 300000;

var
  npass, nfail: Int32;
  arena: TArena;
  symbols: TSymbolTable;
  reg: TRegistry;
  histMap: THistoricalMap;
  ctx: TEvalContext;
  env: TValue;

procedure Check(cond: Boolean; const what: RawByteString);
begin
  if cond then
    Inc(npass)
  else
  begin
    Inc(nfail);
    WriteLn('FAIL: ', what);
  end;
end;

function LoadFileVerbatim(const path: RawByteString): RawByteString;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

function Sym(const name: RawByteString): TValue;
begin
  Result := InternSymbol(arena, symbols, PAnsiChar(name), Length(name));
end;

function Num(n: Int64): TValue;
begin
  Result := MakeNumber(n, 1);
end;

function LList(const items: array of TValue): TValue;
var
  i: Integer;
begin
  Result := MakeNil;
  for i := High(items) downto 0 do
    Result := MakePair(arena, items[i], Result);
end;

{ A proper list of n conses, ending in Nil -- for the deep-recursion
  witness below to walk via cdr/atom, matching Core1's own admitted
  primitive set exactly (no arithmetic needed at all). }
function BuildLongList(n: Integer): TValue;
var
  i: Integer;
begin
  Result := MakeNil;
  for i := 1 to n do
    Result := MakePair(arena, Num(i), Result);
end;

var
  source: RawByteString;
  result_: TValue;
  raised: Boolean;
  selfApp: TValue;

begin
  npass := 0;
  nfail := 0;

  ArenaInit(arena);
  SymbolTableReset(symbols);
  source := LoadFileVerbatim(REGISTRY_PATH);
  RegistryLoad(reg, source);
  HistoricalMapLoad(histMap, LoadFileVerbatim(HISTORICAL_MAP_PATH));
  EvalContextInit(ctx, arena, symbols, reg, histMap);
  env := MakeNil;

  { (1) quote: unevaluated passthrough. }
  result_ := Eval(ctx, env, LList([Sym('quote'), Num(42)]));
  Check((result_.kind = kNumber) and (result_.qnum = 42) and (result_.qden = 1),
    'quote returns its argument unevaluated');

  { (1b) same identity via Ukrainian alias "як-є" -- proves dispatch is by
    semantic ID, not by the spelling "quote" itself. }
  result_ := Eval(ctx, env, LList([Sym('як-є'), Num(42)]));
  Check((result_.kind = kNumber) and (result_.qnum = 42),
    'ukrainian alias "як-є" dispatches identically to "quote" (ID, not spelling)');

  { (2) cons/car/cdr. }
  result_ := Eval(ctx, env,
    LList([Sym('cons'), LList([Sym('quote'), Num(1)]), LList([Sym('quote'), Num(2)])]));
  Check(IsPair(result_) and (PairHead(result_).qnum = 1) and (PairTail(result_).qnum = 2),
    'cons builds a pair from its evaluated arguments');

  result_ := Eval(ctx, env,
    LList([Sym('car'), LList([Sym('cons'), Num(7), Num(8)])]));
  Check((result_.kind = kNumber) and (result_.qnum = 7), 'car returns the first element');

  result_ := Eval(ctx, env,
    LList([Sym('cdr'), LList([Sym('cons'), Num(7), Num(8)])]));
  Check((result_.kind = kNumber) and (result_.qnum = 8), 'cdr returns the second element');

  { (3) atom: false on a pair, true on nil and on ordinary atoms --
    the primitive Core1's own C1-APPLY-PRIMITIVE actually admits. }
  result_ := Eval(ctx, env, LList([Sym('atom'), LList([Sym('cons'), Num(1), Num(2)])]));
  Check(IsNil(result_), 'atom is false (nil) on a pair');

  result_ := Eval(ctx, env, LList([Sym('atom'), LList([Sym('quote'), MakeNil])]));
  Check(not IsNil(result_), 'atom is true on nil');

  result_ := Eval(ctx, env, LList([Sym('atom'), Num(5)]));
  Check(not IsNil(result_), 'atom is true on an ordinary number');

  { (9) eq (issue #26): a genuine failing witness from core1.lisp's own
    C1-ERRORP, "(EQ (CAR VALUE) (QUOTE C1-ERROR))" -- same-kind structural
    comparison for atoms, arena identity for pairs. }
  result_ := Eval(ctx, env,
    LList([Sym('eq'), LList([Sym('quote'), Sym('c1-error')]), LList([Sym('quote'), Sym('c1-error')])]));
  Check(not IsNil(result_), 'eq is true on two symbols with the same name');

  result_ := Eval(ctx, env,
    LList([Sym('eq'), LList([Sym('quote'), Sym('c1-error')]), LList([Sym('quote'), Sym('other')])]));
  Check(IsNil(result_), 'eq is false on two distinct symbols');

  result_ := Eval(ctx, env,
    LList([Sym('eq'), LList([Sym('quote'), Num(7)]), LList([Sym('quote'), Num(7)])]));
  Check(not IsNil(result_), 'eq is true on two equal numbers');

  result_ := Eval(ctx, env,
    LList([Sym('eq'), LList([Sym('cons'), Num(1), Num(2)]), LList([Sym('cons'), Num(1), Num(2)])]));
  Check(IsNil(result_), 'eq is false on two distinct pair allocations, even with equal contents');

  { (10) bare NIL (issue #26): a genuine failing witness from core1.lisp's
    own C1-MAKE-ERROR, "(CONS DETAIL NIL)" and C1-ERRORP's "((ATOM VALUE)
    NIL)" -- NIL is not an operator, it evaluates to the empty list by
    SID (bridged through the pinned historical map to the registry's own
    ground empty-list identity), never by matching its spelling. }
  result_ := Eval(ctx, env,
    LList([Sym('cons'), LList([Sym('quote'), Num(5)]), Sym('NIL')]));
  Check(IsPair(result_) and (PairHead(result_).qnum = 5) and IsNil(PairTail(result_)),
    'bare NIL evaluates to the empty list inside cons, matching a real core1.lisp form');

  result_ := Eval(ctx, env, LList([Sym('atom'), Sym('NIL')]));
  Check(not IsNil(result_), 'atom is true on the value bare NIL evaluates to');

  { T has no SID at all (seed-only per the pinned bootstrap contract) and
    is deliberately NOT given invented self-evaluating semantics here --
    it must still raise, exactly like any other unbound variable. }
  raised := False;
  try
    Eval(ctx, env, Sym('T'));
  except
    on E: EEvalError do raised := True;
  end;
  Check(raised, 'bare T is deliberately left unresolved -- unbound variable, no invented semantics');

  { (4) cond: first matching clause wins. }
  result_ := Eval(ctx, env,
    LList([Sym('cond'),
      LList([LList([Sym('atom'), LList([Sym('cons'), Num(1), Num(2)])]), Num(100)]),
      LList([Num(1), Num(200)])
    ]));
  Check((result_.kind = kNumber) and (result_.qnum = 200),
    'cond selects the first clause whose test is truthy');

  { (5) cond fails closed: no matching clause is an explicit error, never
    a silent fall-through to some default value. }
  raised := False;
  try
    Eval(ctx, env,
      LList([Sym('cond'),
        LList([LList([Sym('quote'), MakeNil]), Num(999)])
      ]));
  except
    on E: EEvalError do raised := True;
  end;
  Check(raised, 'cond raises EEvalError on clause exhaustion, no silent fallthrough');

  { (6) unbound variable: never resolves to invented semantics. }
  raised := False;
  try
    Eval(ctx, env, Sym('this-variable-was-never-bound'));
  except
    on E: EEvalError do raised := True;
  end;
  Check(raised, 'unbound variable raises EEvalError');

  { (7) lambda + apply, single call, no recursion. }
  result_ := Eval(ctx, env,
    LList([
      LList([Sym('lambda'), LList([Sym('x')]),
        LList([Sym('cons'), Sym('x'), Sym('x')])]),
      Num(5)
    ]));
  Check(IsPair(result_) and (PairHead(result_).qnum = 5) and (PairTail(result_).qnum = 5),
    'lambda application binds its parameter and evaluates its body');

  { (8) deep tail-call witness: self-application (U-combinator style,
    no `define`/mutable global env needed) walking a pre-built
    DEEP_N-long list down to its Nil tail via cdr/atom -- only
    Core1-admitted primitives, no arithmetic. If COND-branch-selection
    or closure-body application recursed through the host Pascal call
    stack instead of trampolining, this would stack-overflow long
    before reaching the end of the list. }
  selfApp := LList([
    LList([Sym('lambda'), LList([Sym('f'), Sym('lst')]),
      LList([Sym('f'), Sym('f'), Sym('lst')])]),
    LList([Sym('lambda'), LList([Sym('self'), Sym('lst')]),
      LList([Sym('cond'),
        LList([LList([Sym('atom'), Sym('lst')]), Sym('lst')]),
        LList([Num(1),
          LList([Sym('self'), Sym('self'), LList([Sym('cdr'), Sym('lst')])])])
      ])]),
    LList([Sym('quote'), BuildLongList(DEEP_N)])
  ]);
  result_ := Eval(ctx, env, selfApp);
  Check(IsNil(result_),
    'deep self-application tail recursion (N=300000 cdr steps) completes without a Pascal stack overflow');

  WriteLn('EVAL: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
