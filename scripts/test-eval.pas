(* test-eval.pas — M0.6 tests for the evaluator skeleton (#8).
 *
 * Builds expressions directly with wsm.values primitives (no reader
 * involved -- the reader is a separate, already-tested layer) against
 * the REAL pinned lib/surface/semantic-registry.lisp, and proves:
 *   1. quote/cons/car/cdr/lambda/cond/atom/eq/def/define behave correctly;
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
  wsm.values, wsm.registry, wsm.historical, wsm.reader, wsm.eval;

const
  REGISTRY_PATH = 'external/sens/lib/surface/semantic-registry.lisp';
  HISTORICAL_MAP_PATH = 'external/sens/contracts/core1-historical-sid-map.lisp';
  CORE1_PATH = 'external/sens/lib/core1.lisp';
  DEEP_N = 300000;

var
  npass, nfail: Int32;
  arena: TArena;
  symbols: TSymbolTable;
  reg: TRegistry;
  histMap: THistoricalMap;
  globalEnv: TGlobalEnv;
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

function Nth(v: TValue; n: Integer): TValue;
begin
  while n > 0 do
  begin
    v := PairTail(v);
    Dec(n);
  end;
  Result := PairHead(v);
end;

{ Reads every top-level (DEFINE name (LAMBDA ...)) form from the REAL,
  pinned lib/core1.lisp -- via the general reader, on core1.lisp's own
  actual uppercase historical surface, not a hand-copied excerpt -- and
  returns the LAMBDA form for the one whose name matches. Raises if not
  found: a stale expectation must fail loudly, never silently miss. }
function FindCore1Lambda(const core1Source: RawByteString;
  const defineName: RawByteString): TValue;
var
  r: TReader;
  form: TValue;
begin
  ReaderInit(r, core1Source, arena, symbols);
  while not ReaderAtEnd(r) do
  begin
    form := ReadOne(r);
    if IsPair(form) and IsSymbol(PairHead(form)) and
       (SymbolName(PairHead(form)) = 'DEFINE') and
       IsSymbol(Nth(form, 1)) and (SymbolName(Nth(form, 1)) = defineName) then
    begin
      Result := Nth(form, 2);
      Exit;
    end;
  end;
  raise Exception.CreateFmt(
    'FindCore1Lambda: no (DEFINE %s (LAMBDA ...)) found in the real pinned core1.lisp',
    [defineName]);
end;

{ Issue #27: loads every REAL, pinned top-level (DEFINE ...) form from
  core1.lisp, IN FILE ORDER, by actually running each one through this
  evaluator's own `def`/`define` dispatch (no manual lambda extraction --
  #26's own hand-wiring is no longer needed now that #30/LABEL/FUNCTION
  exist). Stops once stopAfterName has been defined, inclusive -- C1-EVAL
  and everything it transitively needs (through C1-BIND) sit in the
  file's first ~315 lines; C1-MAKE-WORLD onward is M3.2's own
  self-interpretation territory (#27's "не робити"), not loaded here. }
procedure LoadCore1DefinesUpTo(const core1Source: RawByteString;
  const stopAfterName: RawByteString);
var
  r: TReader;
  form: TValue;
  definedName: RawByteString;
begin
  ReaderInit(r, core1Source, arena, symbols);
  while not ReaderAtEnd(r) do
  begin
    form := ReadOne(r);
    Eval(ctx, env, form);
    if IsPair(form) and IsSymbol(PairHead(form)) and
       (SymbolName(PairHead(form)) = 'DEFINE') and IsSymbol(Nth(form, 1)) then
    begin
      definedName := SymbolName(Nth(form, 1));
      if definedName = stopAfterName then Exit;
    end;
  end;
  raise Exception.CreateFmt(
    'LoadCore1DefinesUpTo: "%s" was never defined in the real pinned core1.lisp',
    [stopAfterName]);
end;

{ Issue #28: reads every REAL, pinned top-level form from core1.lisp, IN
  FILE ORDER, WITHOUT evaluating any of them -- collected as one plain
  Lisp list of DATA, for handing to Core1's OWN C1-EVAL-PROGRAM (loaded
  into Pascal's global env by #27's machinery) as its FORMS argument.
  This is what makes the self-interpretation fixed point genuine: the
  list this function builds is core1.lisp's own text, read once here
  purely as syntax, then handed to Core1's own Lisp-level loader to
  build ITS OWN internal (alist) representation of C1-BIND et al.,
  completely independent of Pascal's own def/TGlobalEnv. Stops once
  stopAfterName has been read, inclusive. }
function ReadCore1FormsList(const core1Source: RawByteString;
  const stopAfterName: RawByteString): TValue;
var
  r: TReader;
  form: TValue;
  forms: array of TValue;
  n: Integer;
  i: Integer;
begin
  SetLength(forms, 0);
  ReaderInit(r, core1Source, arena, symbols);
  while not ReaderAtEnd(r) do
  begin
    form := ReadOne(r);
    n := Length(forms);
    SetLength(forms, n + 1);
    forms[n] := form;
    if IsPair(form) and IsSymbol(PairHead(form)) and
       (SymbolName(PairHead(form)) = 'DEFINE') and IsSymbol(Nth(form, 1)) and
       (SymbolName(Nth(form, 1)) = stopAfterName) then
    begin
      Result := MakeNil;
      for i := High(forms) downto 0 do
        Result := MakePair(arena, forms[i], Result);
      Exit;
    end;
  end;
  raise Exception.CreateFmt(
    'ReadCore1FormsList: "%s" was never read from the real pinned core1.lisp',
    [stopAfterName]);
end;

var
  source, core1Source: RawByteString;
  result_: TValue;
  raised: Boolean;
  selfApp, c1Second, c1MakeError, c1ErrorP: TValue;
  formsAsData: TValue;

begin
  npass := 0;
  nfail := 0;

  ArenaInit(arena);
  SymbolTableReset(symbols);
  source := LoadFileVerbatim(REGISTRY_PATH);
  RegistryLoad(reg, source);
  HistoricalMapLoad(histMap, LoadFileVerbatim(HISTORICAL_MAP_PATH));
  GlobalEnvInit(globalEnv);
  EvalContextInit(ctx, arena, symbols, reg, histMap, globalEnv);
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

  { (3) atom?: use the current pinned registry's exact spelling;
    historical uppercase ATOM remains separately mapped by the pinned
    historical bridge, never an invented lowercase alias.
    False on a pair, true on nil and on ordinary atoms --
    the primitive Core1's own C1-APPLY-PRIMITIVE actually admits. }
  result_ := Eval(ctx, env, LList([Sym('atom?'), LList([Sym('cons'), Num(1), Num(2)])]));
  Check(IsNil(result_), 'atom is false (nil) on a pair');

  result_ := Eval(ctx, env, LList([Sym('atom?'), LList([Sym('quote'), MakeNil])]));
  Check(not IsNil(result_), 'atom is true on nil');

  result_ := Eval(ctx, env, LList([Sym('atom?'), Num(5)]));
  Check(not IsNil(result_), 'atom is true on an ordinary number');

  { (9) eq (issue #26): a genuine failing witness from core1.lisp's own
    C1-ERRORP, "(EQ (CAR VALUE) (QUOTE C1-ERROR))" -- same-kind structural
    comparison for atoms, arena identity for pairs. }
  result_ := Eval(ctx, env,
    LList([Sym('eq?'), LList([Sym('quote'), Sym('c1-error')]), LList([Sym('quote'), Sym('c1-error')])]));
  Check(not IsNil(result_), 'eq is true on two symbols with the same name');

  result_ := Eval(ctx, env,
    LList([Sym('eq?'), LList([Sym('quote'), Sym('c1-error')]), LList([Sym('quote'), Sym('other')])]));
  Check(IsNil(result_), 'eq is false on two distinct symbols');

  result_ := Eval(ctx, env,
    LList([Sym('eq?'), LList([Sym('quote'), Num(7)]), LList([Sym('quote'), Num(7)])]));
  Check(not IsNil(result_), 'eq is true on two equal numbers');

  result_ := Eval(ctx, env,
    LList([Sym('eq?'), LList([Sym('cons'), Num(1), Num(2)]), LList([Sym('cons'), Num(1), Num(2)])]));
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

  result_ := Eval(ctx, env, LList([Sym('atom?'), Sym('NIL')]));
  Check(not IsNil(result_), 'atom is true on the value bare NIL evaluates to');

  { T has no SID at all (seed-only per the pinned bootstrap contract,
    same as LABEL/FUNCTION) and self-evaluates to itself (issue #27,
    resolved after #26's initial pause): never to a number, so EQ
    against T can never be confused with EQ against an ordinary 1. }
  result_ := Eval(ctx, env, Sym('T'));
  Check(IsSymbol(result_) and (SymbolName(result_) = 'T'),
    'bare T self-evaluates to itself, the symbol, never to a number');

  result_ := Eval(ctx, env, LList([Sym('eq?'), Sym('T'), LList([Sym('quote'), Num(1)])]));
  Check(IsNil(result_), 'T is never EQ to the ordinary number 1');

  { (4) cond: first matching clause wins. }
  result_ := Eval(ctx, env,
    LList([Sym('cond'),
      LList([LList([Sym('atom?'), LList([Sym('cons'), Num(1), Num(2)])]), Num(100)]),
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
        LList([LList([Sym('atom?'), Sym('lst')]), Sym('lst')]),
        LList([Num(1),
          LList([Sym('self'), Sym('self'), LList([Sym('cdr'), Sym('lst')])])])
      ])]),
    LList([Sym('quote'), BuildLongList(DEEP_N)])
  ]);
  result_ := Eval(ctx, env, selfApp);
  Check(IsNil(result_),
    'deep self-application tail recursion (N=300000 cdr steps) completes without a Pascal stack overflow');

  { (11) real Core1 forms, read directly, not hand-copied (issue #26's
    own acceptance gate): C1-SECOND, C1-MAKE-ERROR and C1-ERRORP are
    extracted from the REAL, pinned lib/core1.lisp on its own actual
    uppercase historical surface (LAMBDA/CAR/CDR/CONS/ATOM/EQ/COND/QUOTE)
    and applied directly -- no DEFINE/global-env needed, since the
    extracted (LAMBDA ...) form is applied as an anonymous closure. This
    is the concrete proof that the historical operator fallback above
    (owner: "семантична влада має залишатися за нашим ліспом, а не
    перепливати з ліспу 60х") actually lets this evaluator run Core1's
    real source, not just a lowercase-translated simulation of it. }
  core1Source := LoadFileVerbatim(CORE1_PATH);

  c1Second := FindCore1Lambda(core1Source, 'C1-SECOND');
  result_ := Eval(ctx, env,
    LList([c1Second, LList([Sym('QUOTE'), LList([Num(1), Num(2), Num(3)])])]));
  Check((result_.kind = kNumber) and (result_.qnum = 2),
    'real core1.lisp C1-SECOND, applied directly, returns the second element');

  c1MakeError := FindCore1Lambda(core1Source, 'C1-MAKE-ERROR');
  result_ := Eval(ctx, env,
    LList([c1MakeError, LList([Sym('QUOTE'), Sym('ARITY')]), LList([Sym('QUOTE'), Sym('TOO-MANY-ARGUMENTS')])]));
  Check(IsPair(result_) and IsSymbol(PairHead(result_)) and
    (SymbolName(PairHead(result_)) = 'C1-ERROR'),
    'real core1.lisp C1-MAKE-ERROR, applied directly, tags its result C1-ERROR (uses bare NIL internally)');

  c1ErrorP := FindCore1Lambda(core1Source, 'C1-ERRORP');
  result_ := Eval(ctx, env, LList([c1ErrorP, LList([Sym('QUOTE'), Num(42)])]));
  Check(IsNil(result_),
    'real core1.lisp C1-ERRORP, applied directly, is false (NIL) on an ordinary non-error value');

  { C1-ERRORP's TRUE branch returns bare T directly -- now resolved
    (issue #27, T self-evaluates). }
  result_ := Eval(ctx, env,
    LList([c1ErrorP,
      LList([c1MakeError, LList([Sym('QUOTE'), Sym('ARITY')]), LList([Sym('QUOTE'), Sym('X')])])]));
  Check(IsSymbol(result_) and (SymbolName(result_) = 'T'),
    'real core1.lisp C1-ERRORP, applied directly, is true (T) on a real C1-MAKE-ERROR result (uses EQ internally)');

  { (12) def/define + persistent global environment (issue #30).
    Acceptance gate's own shape: several sequential top-level defs,
    later ones seeing earlier ones. }
  result_ := Eval(ctx, env, LList([Sym('define'), Sym('f1'),
    LList([Sym('lambda'), LList([Sym('x')]), LList([Sym('cons'), Sym('x'), Sym('x')])])]));
  Check(True, 'define f1 succeeds (result is the bound closure, not checked further)');

  result_ := Eval(ctx, env, LList([Sym('def'), Sym('f2'),
    LList([Sym('lambda'), LList([Sym('x')]), LList([Sym('f1'), Sym('x')])])]));
  Check(True, 'def f2 (referencing already-defined f1) succeeds');

  result_ := Eval(ctx, env, LList([Sym('f2'), Num(5)]));
  Check(IsPair(result_) and (PairHead(result_).qnum = 5) and (PairTail(result_).qnum = 5),
    'f2, defined via def and calling f1 by global lookup, applies correctly after both are defined');

  { self-recursion via def -- no self-application trick needed, matching
    Core1's own (LABEL name (LAMBDA ...)) shape for the ordinary,
    non-mutual case: a def'd function can call itself by its own name. }
  result_ := Eval(ctx, env, LList([Sym('def'), Sym('walk-to-nil'),
    LList([Sym('lambda'), LList([Sym('lst')]),
      LList([Sym('cond'),
        LList([LList([Sym('atom?'), Sym('lst')]), Sym('lst')]),
        LList([Num(1), LList([Sym('walk-to-nil'), LList([Sym('cdr'), Sym('lst')])])])
      ])])]));
  result_ := Eval(ctx, env,
    LList([Sym('walk-to-nil'), LList([Sym('quote'), BuildLongList(1000)])]));
  Check(IsNil(result_), 'a def''d function calls itself by name (self-recursion) without any self-application trick');

  { redefinition is deliberately rejected (#30's own "не допускати
    мутацію вже визначеного def"). }
  Eval(ctx, env, LList([Sym('def'), Sym('dup-def'),
    LList([Sym('quote'), Num(1)])]));
  raised := False;
  try
    Eval(ctx, env, LList([Sym('def'), Sym('dup-def'),
      LList([Sym('quote'), Num(2)])]));
  except
    on E: EEvalError do raised := True;
  end;
  Check(raised, 'redefining an already-def''d name is rejected, not silently overwritten');

  { a lexical (parameter) binding shadows a global def of the same name. }
  Eval(ctx, env, LList([Sym('def'), Sym('shadow-me'), LList([Sym('quote'), Num(100)])]));
  result_ := Eval(ctx, env,
    LList([LList([Sym('lambda'), LList([Sym('shadow-me')]), Sym('shadow-me')]), Num(1)]));
  Check((result_.kind = kNumber) and (result_.qnum = 1),
    'a lexical parameter binding shadows a global def of the same name');

  { (13) LABEL (issue #27's own prerequisite, matching Core1's own
    (LABEL name (LAMBDA ...)) shape exactly): self-recursion by the
    closure's own name, no self-application trick, no def/global env
    at all. }
  result_ := Eval(ctx, env,
    LList([
      LList([Sym('LABEL'), Sym('COUNT-DOWN'),
        LList([Sym('LAMBDA'), LList([Sym('LST')]),
          LList([Sym('cond'),
            LList([LList([Sym('atom?'), Sym('LST')]), Sym('LST')]),
            LList([Num(1), LList([Sym('COUNT-DOWN'), LList([Sym('cdr'), Sym('LST')])])])
          ])])]),
      LList([Sym('quote'), BuildLongList(500)])
    ]));
  Check(IsNil(result_), 'LABEL gives self-recursion by name directly, no self-application trick needed');

  { LABEL's own name is scoped to calls of that closure only -- it must
    not leak into the surrounding/global environment. }
  raised := False;
  try
    Eval(ctx, env, Sym('COUNT-DOWN'));
  except
    on E: EEvalError do raised := True;
  end;
  Check(raised, 'a LABEL name does not leak outside calls of its own closure');

  { Core1's own real shape: DEFINE wrapping a LABEL of the SAME name
    (external/sens/lib/core1.lisp's own C1-EVLIS/C1-EVCON/C1-EVAL
    convention) -- proves LABEL and def/global-env compose without
    conflict (LABEL never touches the global env, so DEFINE defining
    the same name right afterward never hits the redefinition guard).
    No arithmetic is admitted (issue #9), so this walks to the base
    case via cdr/atom exactly like COUNT-DOWN above, rather than
    counting a length. }
  Eval(ctx, env,
    LList([Sym('DEFINE'), Sym('C1-STYLE-WALK'),
      LList([Sym('LABEL'), Sym('C1-STYLE-WALK'),
        LList([Sym('LAMBDA'), LList([Sym('LST')]),
          LList([Sym('cond'),
            LList([LList([Sym('atom?'), Sym('LST')]), Sym('LST')]),
            LList([Num(1), LList([Sym('C1-STYLE-WALK'), LList([Sym('cdr'), Sym('LST')])])])
          ])])])]));
  result_ := Eval(ctx, env,
    LList([Sym('C1-STYLE-WALK'), LList([Sym('quote'), BuildLongList(37)])]));
  Check(IsNil(result_),
    'DEFINE wrapping a same-named LABEL (Core1''s own convention) composes correctly with the global environment');

  { (14) issue #27: Core1's OWN meta-evaluator (C1-EVAL/C1-EVCON/
    C1-EVLIS/C1-APPLY/C1-LOOKUP/C1-BIND, mutually recursive across
    separate top-level DEFINEs) runs on top of this Pascal evaluator --
    Pascal interpreting Lisp code that itself interprets Lisp code, two
    layers. Every DEFINE up to and including C1-EVAL is loaded from the
    REAL, pinned core1.lisp, not hand-copied; C1-MAKE-WORLD onward
    (M3.2's self-interpretation territory) is deliberately not loaded. }
  { Loads through C1-EVAL-PROGRAM-THEN (the file's last DEFINE), not just
    C1-EVAL -- #28 needs C1-EVAL-PROGRAM/C1-MAKE-WORLD/C1-WORLD-EVAL/
    C1-EVAL-PROGRAM-THEN too, and loading them here does not change any
    of #27's own tests below (they only require C1-EVAL to exist). }
  LoadCore1DefinesUpTo(core1Source, 'C1-EVAL-PROGRAM-THEN');

  { quote, via C1-EVAL's own C1-QUOTE-NAMEP path. }
  result_ := Eval(ctx, env,
    LList([Sym('C1-EVAL'),
      LList([Sym('quote'), LList([Sym('QUOTE'), Num(42)])]),
      Sym('NIL'), Sym('NIL')]));
  Check((result_.kind = kNumber) and (result_.qnum = 42),
    'Core1''s own C1-EVAL, run by this Pascal evaluator, evaluates (QUOTE 42) to 42');

  { cond, via C1-EVAL's own C1-COND-NAMEP path -- calls C1-EVCON, which
    calls C1-EVAL back: genuine mutual recursion across separate
    top-level DEFINEs, exactly what #30/def+global-env exists for. }
  result_ := Eval(ctx, env,
    LList([Sym('C1-EVAL'),
      LList([Sym('quote'),
        LList([Sym('COND'),
          LList([LList([Sym('QUOTE'), Num(1)]), LList([Sym('QUOTE'), Sym('YES')])])
        ])]),
      Sym('NIL'), Sym('NIL')]));
  Check(IsSymbol(result_) and (SymbolName(result_) = 'YES'),
    'Core1''s own C1-EVAL evaluates (COND ((QUOTE 1) (QUOTE YES))) to YES via mutually recursive C1-EVCON');

  { lambda-application, via C1-EVAL's own LAMBDA-NAMEP path -- exercises
    C1-EVLIS, C1-APPLY, C1-BIND, C1-LOOKUP, and FUNCTION/FUNARG
    (issue #27's own remaining prerequisites) together. }
  result_ := Eval(ctx, env,
    LList([Sym('C1-EVAL'),
      LList([Sym('quote'),
        LList([
          LList([Sym('LAMBDA'), LList([Sym('X')]), Sym('X')]),
          LList([Sym('QUOTE'), Num(42)])
        ])]),
      Sym('NIL'), Sym('NIL')]));
  Check((result_.kind = kNumber) and (result_.qnum = 42),
    'Core1''s own C1-EVAL evaluates ((LAMBDA (X) X) (QUOTE 42)) to 42 via mutually recursive C1-APPLY/C1-EVLIS/C1-BIND/C1-LOOKUP');

  { (15) issue #28: self-interpretation fixed point. core1.lisp's OWN
    text, read here purely as syntax (never evaluated directly by this
    Pascal test), is handed as DATA to Core1's OWN C1-EVAL-PROGRAM-THEN
    -- itself running under Pascal via #27's machinery -- which builds
    its OWN, entirely separate (alist) global environment by
    self-interpreting that data. Three genuine layers: Pascal -> C1-EVAL
    (Lisp code, run by Pascal) -> core1.lisp-as-data (interpreted by that
    same C1-EVAL).

    IMPORTANT, empirically discovered scope boundary: C1-BIND (the
    acceptance gate's own suggested example) does NOT self-interpret --
    verified directly. Core1's own C1-EVAL has no case at all for LABEL
    (only QUOTE/COND/LAMBDA/DEFINE are recognized by name), so when it
    self-interprets a LABEL form it treats "LABEL" as an ordinary
    function name, looks it up, and gets UNBOUND. This is not a Pascal
    bug: LABEL and bare-number self-evaluation are both listed as
    "seed-only" mechanisms in contracts/core1-bootstrap-contract.lisp --
    conveniences the HOST provides, never reimplemented by C1-EVAL
    itself. That same contract's own acceptance criteria for Core1's
    real consumer (wsm-my-lisp-issue-39, compiler.lisp) requires generic
    "recursion", not "LABEL" specifically -- and ordinary DEFINE-based
    recursion (a name resolved through C1-LOOKUP against the explicitly
    GLOBAL-threaded environment, exactly matching #30's own Pascal-side
    "evaluate then bind" design) self-interprets correctly, verified
    below. LABEL is a Core1-INTERNAL bootstrapping detail (used only by
    C1-EVAL/C1-BIND/etc. themselves), not something Core1 "user"
    programs like a compiler need to write themselves. }
  formsAsData := ReadCore1FormsList(core1Source, 'C1-MAKE-ERROR');
  result_ := Eval(ctx, env,
    LList([Sym('C1-EVAL-PROGRAM-THEN'),
      LList([Sym('quote'), formsAsData]),
      LList([Sym('quote'),
        LList([Sym('C1-MAKE-ERROR'),
          LList([Sym('QUOTE'), Sym('ARITY')]),
          LList([Sym('QUOTE'), Sym('X')])])]
      )]));
  Check(IsPair(result_) and IsSymbol(PairHead(result_)) and
    (SymbolName(PairHead(result_)) = 'C1-ERROR'),
    'self-interpreted C1-MAKE-ERROR -- real core1.lisp text (C1-SECOND..C1-MAKE-ERROR, all non-LABEL), read purely as syntax and handed to Core1''s own C1-EVAL-PROGRAM-THEN as data -- tags its result C1-ERROR exactly like direct execution');

  { A genuinely self-recursive DEFINE'd function -- representing the kind
    of "user" Core1 program a compiler (wsm-my-lisp-issue-39) would
    actually contain -- self-interprets correctly: no LABEL anywhere,
    self-reference resolved purely through Core1's own GLOBAL-threaded
    C1-LOOKUP. Catch-all guard is T, not a bare number: core1.lisp's own
    C1-EVAL has no "numbers self-evaluate" shortcut either (another
    faithful-to-McCarthy-1960 detail; a bare number in operator-test
    position would itself hit C1-LOOKUP and come back UNBOUND). }
  result_ := Eval(ctx, env,
    LList([Sym('C1-EVAL-PROGRAM-THEN'),
      LList([Sym('quote'),
        LList([
          LList([Sym('DEFINE'), Sym('MY-WALK-TO-NIL'),
            LList([Sym('LAMBDA'), LList([Sym('LST')]),
              LList([Sym('COND'),
                LList([LList([Sym('ATOM'), Sym('LST')]), Sym('LST')]),
                LList([Sym('T'),
                  LList([Sym('MY-WALK-TO-NIL'), LList([Sym('CDR'), Sym('LST')])])])
              ])])])
        ])]),
      LList([Sym('quote'),
        LList([Sym('MY-WALK-TO-NIL'),
          LList([Sym('QUOTE'), LList([Num(1), Num(2), Num(3)])])])]
      )]));
  Check(IsNil(result_),
    'a genuinely self-recursive DEFINE''d function (no LABEL, self-reference via Core1''s own GLOBAL-threaded C1-LOOKUP) self-interprets correctly -- the actual fixed-point proof #25 exists for, scoped to the "recursion" contracts/core1-bootstrap-contract.lisp requires, not Core1-internal LABEL');

  WriteLn('EVAL: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
