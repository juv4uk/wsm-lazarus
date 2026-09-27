(* wsm.eval.pas — M0.6 evaluator skeleton: ID dispatch + trampoline (#8).
 *
 * Мета цього модуля (issue #8): побудувати eval/apply механіку так, щоб
 * архітектура вже НЕ МОГЛА повернутися до spelling-driven interpreter.
 * Every semantic branch below switches on a canonical semantic ID
 * (TSid8, an opaque record -- see wsm.registry.pas) obtained from
 * wsm.registry.RegistryLookup -- never on an operator's spelling. The
 * ONLY place an operator spelling ever appears is as the dynamic INPUT
 * to RegistryLookup (SymbolName(head), taken from whatever the
 * expression itself contains); it is converted to a TSid8 before any
 * branching happens. No spelling literal for quote/cond/lambda/cons/
 * car/cdr ever appears in this file's control flow.
 *
 * SID8-ONLY (issue #24, ecosystem#16, 2026-09-23 · owner correction:
 * a bare binary literal "is not our SID, it's a substitution", then
 * that the full identity space cannot be defined as functions of our
 * language without quotes or literals): dispatch itself (opID =
 * IdQuote, etc., via TSid8's
 * overloaded `=`) is plain packed-byte equality, never a string
 * comparison. But this unit no longer hardcodes ANY eight-bit spelling
 * at all, not even as validated construction input -- Pascal has no
 * equivalent of Rust's `sid!(00000001)` (a bare, unquoted token
 * captured and validated at compile time by a real macro system); the
 * two available options, a raw numeric literal (silently collapses
 * width at the lexer, before any validation code could ever run) or a
 * quoted string handed to a validator, both require writing *some*
 * eight-bit-shaped spelling directly into this file's own source.
 *
 * The actual fix removes the need for either: the eight identities
 * this evaluator implements are resolved by ORDINARY SURFACE NAME
 * (RegistryLookup(reg, 'quote', ...), RegistryLookup(reg, 'cons', ...),
 * etc.) -- the exact same mechanism, against the exact same pinned
 * registry, that every interpreted expression's own operator already
 * goes through (SymbolName(head) -> RegistryLookup -> TSid8). No
 * bit-pattern-shaped literal, quoted or bare, exists anywhere in this
 * file. The only strings present are ordinary human surface names,
 * which SID8-ONLY explicitly permits as pre-resolution input ("Surface-
 * імена потрібні лише людині на вході") -- the same role
 * RegistryLookup's own `spelling` parameter already plays for every
 * dynamically-evaluated operator. Resolution happens once, in
 * EvalContextInit, using the caller's already-loaded registry; a
 * pinned registry missing any of these eight names is a hard error at
 * that point, not a guess.
 *
 * Environment variable lookup (EnvLookup) *does* compare symbol spellings
 * -- that is unavoidable and is not the thing #8 forbids: a variable's
 * name is its identity, this is ordinary binding lookup, not semantic
 * operator dispatch. What #8 forbids specifically is "якщо ID невідомий —
 * подивитися ім'я": falling back to spelling-based guessing once ID
 * dispatch has already failed to resolve or implement an operator. This
 * unit never does that -- an unresolved or unimplemented ID is always an
 * explicit EEvalError, never a name-based guess.
 *
 * Minimal continuation/frame representation (#8's own phrase): the
 * trampoline's own {expr, env} loop-local pair IS the continuation this
 * skeleton needs. Every TAIL position (the chosen COND branch, a
 * closure's body after argument binding) overwrites {expr, env} and
 * `Continue`s the same while loop -- no Pascal call-stack growth with
 * recursion depth. Every NON-TAIL position (argument evaluation, COND
 * test evaluation, operator-position evaluation for a computed head)
 * recurses through an ordinary nested Eval call, whose own depth is
 * bounded by expression structure, never by how many tail-calls a
 * program makes.
 *
 * Scope, per #8's "Не робити": this is a skeleton, not a library. Only
 * QUOTE/COND/LAMBDA plus CONS/CAR/CDR/ATOM/EQ are implemented -- exactly
 * Core1's own primitive table (external/sens/lib/core1.lisp's
 * C1-APPLY-PRIMITIVE admits LIST/NOT/ATOM/EQ/CONS/CAR/CDR; nothing
 * arithmetic). No BigInt, no macro system, no full core.
 *
 * EQ admitted (issue #26, 2026-09-23): C1-ERRORP in the real, pinned
 * core1.lisp calls (EQ (CAR VALUE) (QUOTE C1-ERROR)) -- a genuine
 * failing witness from an actual Core1 form, not a synthetic fixture.
 * ValuesEq below compares same-kind atoms structurally (symbol name,
 * number value, string bytes) and pairs by arena identity, mirroring
 * my-lisp's own cross-variant `_ => false` Rust reference (crates/
 * my-lisp/src/value.rs) -- never invented per-kind semantics beyond
 * that. True/false are the same MakeNumber(1,1)/MakeNil convention
 * ATOM already uses; this did NOT touch bare NIL/T as self-evaluating
 * McCarthy ground values at the time -- paused 2026-09-23 pending
 * broader discussion, later resolved (NIL by #26, T by #27) once
 * Core1's own real C1-EVAL forms showed both are unavoidable. See the
 * kSymbol case below for the actual resolution and its full rationale.
 *
 * MECHANISM BUDGET (issue #9, 2026-09-23): an earlier revision of this
 * file also admitted MINUS ('-') and NUMEQ ('=') -- audited and
 * removed. Neither has a failing upstream-owned witness: Core1's own
 * primitive table has no arithmetic at all, so admitting them here had
 * no bootstrap-path justification, only the convenience of this unit's
 * own self-invented deep-recursion test (which has since been
 * rewritten to walk a list via CDR/ATOM instead of counting down a
 * number). See docs/mechanism-budget.md for the full ledger and
 * justification of every ID this unit actually admits.
 *
 * TOP-LEVEL def/define + persistent global environment (issue #30,
 * 2026-09-23): failing witness is lib/canon.lisp (every canon-law-* is a
 * named top-level definition, not a self-application expression) and,
 * more immediately, Core1's own C1-EVAL family (#27), which is
 * genuinely mutually recursive across separate top-level DEFINEs
 * (C1-EVAL calls C1-EVLIS/C1-EVCON/C1-APPLY/C1-LOOKUP, which call
 * C1-EVAL back). TGlobalEnv is a SEPARATE, deliberately mutable
 * structure from the ordinary lexical `env` list above -- it does NOT
 * touch wsm.values.pas's opaque pair representation at all (no new pair
 * mutator, keeping the existing VALUES-BOUNDARY invariant intact).
 * `def`/`define` evaluates its value expression first, THEN inserts the
 * (name, value) binding -- since a `(lambda ...)` value's body is never
 * evaluated at definition time (only at call time, by which point the
 * global entry already exists), this alone gives correct self-recursion
 * for the actual Core1/canon.lisp shape (`(def f (lambda (...) ... (f
 * ...) ...))`) with no placeholder-then-patch trick and no mutation of
 * an existing binding's value. Redefinition is deliberately rejected
 * (#30's own "не допускати мутацію вже визначеного def"): a real
 * failing witness for that would be a new, separate admission, not
 * "про запас". kSymbol resolution order is: historical ground values
 * (NIL) -> lexical env -> global env -> unbound-variable, matching the
 * existing "innermost binding wins, fail closed if none" discipline.
 *)
unit wsm.eval;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values, wsm.registry, wsm.historical;

type
  EEvalError = class(EValueError);

  PArena = ^TArena;
  PSymbolTable = ^TSymbolTable;
  PRegistry = ^TRegistry;
  PHistoricalMap = ^THistoricalMap;

  { The persistent global environment (issue #30). Deliberately NOT the
    same representation as the ordinary lexical `env` list Eval already
    threads through -- that stays a plain immutable list of (symbol
    . value) pairs, used only for lambda-parameter binding. This is a
    separate, mutable, append-only table that `def`/`define` grows and
    every symbol lookup consults after the lexical chain is exhausted. }
  TGlobalBinding = record
    Name: RawByteString;
    Value: TValue;
  end;

  TGlobalEnv = record
    Bindings: array of TGlobalBinding;
  end;
  PGlobalEnv = ^TGlobalEnv;

procedure GlobalEnvInit(out g: TGlobalEnv);

{ Returns False, leaving value undefined, for any name not yet defined
  -- an unresolved global name never guesses, matching RegistryLookup's
  own contract. }
function GlobalEnvLookup(const g: TGlobalEnv; const name: RawByteString;
  out value: TValue): Boolean;

{ Appends a new (name, value) binding. Raises EEvalError if name is
  already defined -- #30's own "не допускати мутацію вже визначеного
  def" until a real failing witness demands redefinition. }
procedure GlobalEnvDefine(var g: TGlobalEnv; const name: RawByteString;
  value: TValue);

type

  { Everything Eval needs to resolve operators (Registry), allocate new
    structure (Arena/Symbols), and recognize its own closure values
    (ClosureMarker) -- passed explicitly, never global state.

    IdQuote..IdEq are this evaluator's own admitted OPERATOR identities,
    resolved once by EvalContextInit from the caller's pinned registry
    by ordinary surface name -- never hardcoded as a bit-pattern
    literal anywhere in this unit (see the file header comment).

    IdEmptyList is NOT an operator -- it is never looked up in
    operator/head position and never appears in the IdQuote..IdEq
    dispatch chain. Owner (2026-09-23): "ніл і т, це не функції мови, це
    відповіді самої мови" (NIL and T are not functions of the language,
    they are the language's own ANSWERS). It is the registry's one
    ground value (Canon 0 / empty-list, SID 00000000), resolved
    structurally via RegistryGroundValueId (that row has no surface
    spelling at all) so a bare symbol whose HISTORICAL name bridges to
    it (see HistoricalMap below) can evaluate to MakeNil -- by SID
    comparison, never by comparing the symbol's spelling to a literal
    "NIL" string. T has no field here at all -- it also has no SID
    (contracts/core1-bootstrap-contract.lisp lists it as "seed-only",
    same as LABEL/FUNCTION), so it is resolved in the kSymbol case below
    by the same contract-authorized spelling exception as LABEL/FUNCTION,
    not through TEvalContext at all (issue #27). }
  TEvalContext = record
    Arena: PArena;
    Symbols: PSymbolTable;
    Registry: PRegistry;
    HistoricalMap: PHistoricalMap;
    GlobalEnv: PGlobalEnv;
    ClosureMarker: TValue;
    IdQuote, IdCons, IdCar, IdCdr, IdCond, IdLambda, IdAtom, IdEq: TSid8;
    IdDefine, IdDef: TSid8;
    IdEmptyList: TSid8;
  end;

procedure EvalContextInit(out ctx: TEvalContext; var arena: TArena;
  var symbols: TSymbolTable; var reg: TRegistry; var histMap: THistoricalMap;
  var globalEnv: TGlobalEnv);

{ env is a plain list of (symbol . value) bindings, innermost first --
  MakeNil is a valid, empty top-level environment. }
function Eval(var ctx: TEvalContext; env: TValue; expr: TValue): TValue;

implementation

const
  { FUNARG (issue #27's own prerequisite), not an arbitrary internal
    string: this is the authentic LISP 1.5 Appendix B closure tag name,
    and Core1's own C1-FUNARGP checks exactly this symbol
    ("(EQ (CAR VALUE) (QUOTE FUNARG))") to recognize a value it can
    apply. Every closure this evaluator builds (LAMBDA or LABEL alike)
    already looks like (FUNARG . (labelName . (params . (body . env)))),
    so nothing else needs to change for Core1's own C1-APPLY to accept
    our closures directly as FUNARG values -- see the FUNCTION passthrough
    below. }
  CLOSURE_MARKER_NAME: RawByteString = 'FUNARG';

type
  TValueArray = array of TValue;

procedure GlobalEnvInit(out g: TGlobalEnv);
begin
  SetLength(g.Bindings, 0);
end;

function GlobalEnvLookup(const g: TGlobalEnv; const name: RawByteString;
  out value: TValue): Boolean;
var
  i: SizeInt;
begin
  for i := 0 to High(g.Bindings) do
    if g.Bindings[i].Name = name then
    begin
      value := g.Bindings[i].Value;
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure GlobalEnvDefine(var g: TGlobalEnv; const name: RawByteString;
  value: TValue);
var
  existing: TValue;
  n: SizeInt;
begin
  if GlobalEnvLookup(g, name, existing) then
    raise EEvalError.CreateFmt(
      'def: "%s" is already defined (redefinition not yet admitted)', [name]);
  n := Length(g.Bindings);
  SetLength(g.Bindings, n + 1);
  g.Bindings[n].Name := name;
  g.Bindings[n].Value := value;
end;

{ Resolves one of this evaluator's admitted identities by its ordinary
  surface name against the caller's own pinned registry -- the exact
  same RegistryLookup an interpreted expression's own operator goes
  through. A pinned registry that has drifted and no longer has an
  entry for one of these eight names is a configuration error, not a
  guess to paper over: fails closed immediately. }
procedure ResolveAdmittedId(const reg: TRegistry; const name: RawByteString;
  out id: TSid8);
begin
  if not RegistryLookup(reg, name, id) then
    raise EEvalError.CreateFmt(
      'EvalContextInit: pinned registry has no entry for admitted ' +
      'operator "%s"', [name]);
end;

procedure EvalContextInit(out ctx: TEvalContext; var arena: TArena;
  var symbols: TSymbolTable; var reg: TRegistry; var histMap: THistoricalMap;
  var globalEnv: TGlobalEnv);
begin
  ctx.Arena := @arena;
  ctx.Symbols := @symbols;
  ctx.Registry := @reg;
  ctx.HistoricalMap := @histMap;
  ctx.GlobalEnv := @globalEnv;
  ctx.ClosureMarker := InternSymbol(
    arena, symbols,
    PAnsiChar(CLOSURE_MARKER_NAME), Length(CLOSURE_MARKER_NAME));

  ResolveAdmittedId(reg, 'quote', ctx.IdQuote);
  ResolveAdmittedId(reg, 'cons', ctx.IdCons);
  ResolveAdmittedId(reg, 'car', ctx.IdCar);
  ResolveAdmittedId(reg, 'cdr', ctx.IdCdr);
  ResolveAdmittedId(reg, 'cond', ctx.IdCond);
  ResolveAdmittedId(reg, 'lambda', ctx.IdLambda);
  ResolveAdmittedId(reg, 'atom', ctx.IdAtom);
  ResolveAdmittedId(reg, 'eq', ctx.IdEq);
  ResolveAdmittedId(reg, 'define', ctx.IdDefine);
  ResolveAdmittedId(reg, 'def', ctx.IdDef);
  ctx.IdEmptyList := RegistryGroundValueId(reg);
end;

{ EQ (issue #26): same-kind structural comparison for atoms, arena
  identity for pairs -- mirrors my-lisp's own cross-variant `_ => false`
  Rust reference (crates/my-lisp/src/value.rs) rather than inventing new
  per-kind rules. Two pairs are EQ only when they are literally the same
  allocation, never by recursive structural comparison (that is Core1's
  own EQUAL-style law to define in Lisp if it ever needs one, not this
  primitive's job). }
function ValuesEq(a, b: TValue): Boolean;
begin
  if a.kind <> b.kind then
  begin
    Result := False;
    Exit;
  end;
  case a.kind of
    kVNil, kUnbound: Result := True;
    kNumber: Result := (a.qnum = b.qnum) and (a.qden = b.qden);
    kSymbol: Result := SymbolName(a) = SymbolName(b);
    kString: Result := (a.strLen = b.strLen) and
      ((a.strLen = 0) or (CompareByte(a.str^, b.str^, a.strLen) = 0));
    kPair: Result := a.pair = b.pair;
  else
    Result := False;
  end;
end;

{ Nth element (0-based) of a proper list, with a clear arity error rather
  than an opaque pair-shape error. }
function NthArg(list: TValue; n: Integer; const opName: RawByteString): TValue;
var
  i: Integer;
begin
  for i := 1 to n do
  begin
    if not IsPair(list) then
      raise EEvalError.CreateFmt('%s: too few arguments', [opName]);
    list := PairTail(list);
  end;
  if not IsPair(list) then
    raise EEvalError.CreateFmt('%s: too few arguments', [opName]);
  Result := PairHead(list);
end;

{ labelName is MakeNil for an ordinary LAMBDA closure, or the symbol
  given to LABEL (issue #27's own prerequisite) for a self-recursive
  one. Kept as one shared representation rather than two closure kinds
  so every other closure-handling site (IsClosure, application) needs
  only one extra check, not a parallel code path. }
function MakeClosure(var ctx: TEvalContext; labelName, params, body, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, ctx.ClosureMarker,
    MakePair(ctx.Arena^, labelName,
      MakePair(ctx.Arena^, params, MakePair(ctx.Arena^, body, env))));
end;

function IsClosure(var ctx: TEvalContext; v: TValue): Boolean;
begin
  Result := IsPair(v) and IsSymbol(PairHead(v)) and
    (SymbolName(PairHead(v)) = SymbolName(ctx.ClosureMarker));
end;

function ClosureLabelName(v: TValue): TValue;
begin
  Result := PairHead(PairTail(v));
end;

function ClosureParams(v: TValue): TValue;
begin
  Result := PairHead(PairTail(PairTail(v)));
end;

function ClosureBody(v: TValue): TValue;
begin
  Result := PairHead(PairTail(PairTail(PairTail(v))));
end;

function ClosureEnv(v: TValue): TValue;
begin
  Result := PairTail(PairTail(PairTail(PairTail(v))));
end;

function EnvExtend(var ctx: TEvalContext; sym, value, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, MakePair(ctx.Arena^, sym, value), env);
end;

{ Non-raising lexical lookup, so callers (the kSymbol case below) can
  fall through to the global environment (#30) before deciding a name
  is genuinely unbound. }
function TryEnvLookup(env: TValue; const name: RawByteString;
  out value: TValue): Boolean;
var
  node, binding: TValue;
begin
  node := env;
  while IsPair(node) do
  begin
    binding := PairHead(node);
    if SymbolName(PairHead(binding)) = name then
    begin
      value := PairTail(binding);
      Result := True;
      Exit;
    end;
    node := PairTail(node);
  end;
  Result := False;
end;

function EnvLookup(env: TValue; sym: TValue): TValue;
var
  name: RawByteString;
begin
  name := SymbolName(sym);
  if not TryEnvLookup(env, name, Result) then
    raise EEvalError.CreateFmt('eval: unbound variable %s', [name]);
end;

function BindParams(var ctx: TEvalContext; params: TValue;
  const argVals: TValueArray; baseEnv: TValue): TValue;
var
  i: Integer;
  p: TValue;
begin
  Result := baseEnv;
  p := params;
  i := 0;
  while IsPair(p) do
  begin
    if i > High(argVals) then
      raise EEvalError.Create('apply: too few arguments');
    Result := EnvExtend(ctx, PairHead(p), argVals[i], Result);
    Inc(i);
    p := PairTail(p);
  end;
  if i <= High(argVals) then
    raise EEvalError.Create('apply: too many arguments');
end;

function Eval(var ctx: TEvalContext; env: TValue; expr: TValue): TValue;
var
  head, argsList, fn: TValue;
  opID, histID: TSid8;
  haveID, haveHistID: Boolean;
  argVals: TValueArray;
  clauses, clause, testVal: TValue;
  matched: Boolean;
  a, b: TValue;
  n: Integer;
  node: TValue;
  lexicalVal, globalVal, defValue: TValue;
  labelLambdaForm, callEnv: TValue;
begin
  while True do
  begin
    case expr.kind of
      kNumber, kString, kVNil:
        begin
          Result := expr;
          Exit;
        end;

      kUnbound:
        raise EEvalError.Create('eval: cannot evaluate the unbound marker');

      kSymbol:
        begin
          { NIL and T are not functions of this evaluator, they are
            ANSWERS (issue #26, owner: "ніл і т, це не функції мови, це
            відповіді самої мови"). NIL: a bare symbol whose HISTORICAL
            name bridges, via the pinned historical map, to the same SID
            as the registry's own ground empty-list identity evaluates
            to MakeNil -- compared by SID, never by matching the
            symbol's spelling against a literal "NIL" string.

            T (issue #27, owner: "так, T самовиконується (той самий
            патерн, що й NIL/LABEL)"): T has NO SID at all
            (contracts/core1-bootstrap-contract.lisp lists it as
            "seed-only", exactly like LABEL/FUNCTION above), so it
            cannot be resolved via RegistryLookup or HistoricalLookup --
            a spelling check on the literal name "T" is the only
            mechanism available, the same contract-authorized exception
            already used for LABEL/FUNCTION. T self-evaluates to itself
            (the symbol), never to a number: C1-EVAL's own body compares
            values against it with EQ ("(EQ EXPR T) T"), and conflating
            T with e.g. the number 1 would make EQ wrongly match an
            ordinary 1. This was deliberately paused on 2026-09-23 ("T
            ... paused pending broader discussion") specifically because
            a single fixed "true" answer is what my-lisp's own truth-
            semantics evolution moves away from -- resolved once #27's
            real C1-EVAL forms showed T is unavoidable for the "apply"
            path (its own COND's final catch-all clause is bare `T`),
            and confirmed this is scoped to Core1's own declared
            historical-t-nil domain, never my-lisp's current semantics.

            Every other symbol falls through to ordinary variable
            lookup: lexical env first (function parameters shadow
            everything), then the persistent global environment (#30),
            then fail closed -- an unresolved symbol never guesses. }
          haveHistID :=
            HistoricalLookup(ctx.HistoricalMap^, SymbolName(expr), histID);
          if haveHistID and (histID = ctx.IdEmptyList) then
            Result := MakeNil
          else if SymbolName(expr) = 'T' then
            Result := expr
          else if TryEnvLookup(env, SymbolName(expr), lexicalVal) then
            Result := lexicalVal
          else if GlobalEnvLookup(ctx.GlobalEnv^, SymbolName(expr), globalVal) then
            Result := globalVal
          else
            raise EEvalError.CreateFmt(
              'eval: unbound variable %s', [SymbolName(expr)]);
          Exit;
        end;

      kPair:
        begin
          head := PairHead(expr);
          argsList := PairTail(expr);

          { LABEL (issue #27's own prerequisite): the ONE deliberate
            exception to "never dispatch by spelling" (#8). LABEL has NO
            my-lisp SID at all -- contracts/core1-bootstrap-contract.lisp
            explicitly lists it as a "seed-only" mechanism alongside T,
            never bridged to a semantic identity, so neither
            RegistryLookup nor HistoricalLookup can ever resolve it; a
            spelling check is the only mechanism available, and this
            pinned contract is what authorizes treating exactly this one
            literal name as meaningful (owner, 2026-09-23: confirmed as
            an explicit, contract-authorized exception, not a precedent
            for spelling dispatch elsewhere). `(LABEL name (LAMBDA params
            body))` builds a closure carrying `name` as its own
            label -- see MakeClosure/ClosureLabelName and the
            application logic below, which is what actually makes
            self-recursion by name work, at call time, with no
            mutation and no global-environment side effect. }
          if IsSymbol(head) and (SymbolName(head) = 'LABEL') then
          begin
            labelLambdaForm := NthArg(argsList, 1, 'label');
            Result := MakeClosure(ctx,
              NthArg(argsList, 0, 'label'),
              NthArg(PairTail(labelLambdaForm), 0, 'label'),
              NthArg(PairTail(labelLambdaForm), 1, 'label'),
              env);
            Exit;
          end;

          { FUNCTION (issue #27's own prerequisite): the SAME
            contract-authorized spelling exception as LABEL above --
            FUNCTION/FUNARG are seed-only mechanisms with no my-lisp SID
            (contracts/core1-bootstrap-contract.lisp). Core1's own
            C1-EVAL builds its LAMBDA-application closures as
            `(FUNCTION (LAMBDA (ARGS GLOBAL) BODY))` so that
            C1-FUNARGP's own "(EQ (CAR VALUE) (QUOTE FUNARG))" check
            recognizes them. Since every closure this evaluator builds
            is already tagged FUNARG (see CLOSURE_MARKER_NAME above),
            FUNCTION needs no wrapping at all -- it is a pure
            passthrough: evaluate the one argument and return it as-is. }
          if IsSymbol(head) and (SymbolName(head) = 'FUNCTION') then
          begin
            Result := Eval(ctx, env, NthArg(argsList, 0, 'function'));
            Exit;
          end;

          { Operator resolution tries the CURRENT my-lisp surface first
            (RegistryLookup), then falls back to the pinned HISTORICAL
            surface (HistoricalLookup) for exactly the same reason NIL
            resolves through it above: Core1's real, pinned source is
            written in McCarthy's historical uppercase spelling (LAMBDA,
            CAR, CDR, CONS, ATOM, EQ, COND, QUOTE), which the CURRENT
            registry deliberately does NOT admit as a surface (owner,
            2026-09-23: "семантична влада має залишатися за нашим
            ліспом, а не перепливати з ліспу 60х" -- semantic authority
            stays with OUR Lisp, never flows in from the 60s Lisp). This
            does NOT mint any new identity or widen the current
            registry's own admitted surfaces -- it only recognizes that
            a historical spelling already, per the pinned
            historical-sid-map's own one-way witness, denotes one of
            THIS evaluator's existing SIDs, then dispatches on that SID
            exactly as if the current spelling had been used. A
            historical name whose bridged SID is not one of this
            evaluator's admitted operators still fails closed below
            ("registered but not implemented"), same as any other
            resolved-but-unimplemented SID. }
          haveID := False;
          if IsSymbol(head) then
          begin
            haveID := RegistryLookup(ctx.Registry^, SymbolName(head), opID);
            if not haveID then
              haveID := HistoricalLookup(ctx.HistoricalMap^, SymbolName(head), opID);
          end;

          if haveID then
          begin
            if opID = ctx.IdQuote then
            begin
              Result := NthArg(argsList, 0, 'quote');
              Exit;
            end
            else if opID = ctx.IdLambda then
            begin
              Result := MakeClosure(ctx,
                MakeNil,
                NthArg(argsList, 0, 'lambda'),
                NthArg(argsList, 1, 'lambda'),
                env);
              Exit;
            end
            else if opID = ctx.IdCond then
            begin
              clauses := argsList;
              matched := False;
              while IsPair(clauses) do
              begin
                clause := PairHead(clauses);
                testVal := Eval(ctx, env, NthArg(clause, 0, 'cond'));
                if not IsNil(testVal) then
                begin
                  expr := NthArg(clause, 1, 'cond');
                  matched := True;
                  Break;
                end;
                clauses := PairTail(clauses);
              end;
              if not matched then
                raise EEvalError.Create('cond: no matching clause (fail-closed)');
              Continue;
            end
            else if opID = ctx.IdCons then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, 'cons'));
              b := Eval(ctx, env, NthArg(argsList, 1, 'cons'));
              Result := MakePair(ctx.Arena^, a, b);
              Exit;
            end
            else if opID = ctx.IdCar then
            begin
              Result := PairHead(Eval(ctx, env, NthArg(argsList, 0, 'car')));
              Exit;
            end
            else if opID = ctx.IdCdr then
            begin
              Result := PairTail(Eval(ctx, env, NthArg(argsList, 0, 'cdr')));
              Exit;
            end
            else if opID = ctx.IdAtom then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, 'atom'));
              if IsPair(a) then
                Result := MakeNil
              else
                Result := MakeNumber(1, 1);
              Exit;
            end
            else if opID = ctx.IdEq then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, 'eq'));
              b := Eval(ctx, env, NthArg(argsList, 1, 'eq'));
              if ValuesEq(a, b) then
                Result := MakeNumber(1, 1)
              else
                Result := MakeNil;
              Exit;
            end
            else if (opID = ctx.IdDefine) or (opID = ctx.IdDef) then
            begin
              { #30: evaluate the value expression FIRST, then insert
                into the global environment. A (lambda ...) value's body
                is never touched until it is actually called, by which
                point this binding already exists -- so self-recursion
                ("(def f (lambda (...) ... (f ...) ...))", Core1's own
                shape via LABEL notwithstanding) and forward visibility
                to every later top-level def work correctly with no
                placeholder-then-patch step and no mutation of an
                existing binding. }
              defValue := Eval(ctx, env, NthArg(argsList, 1, 'def'));
              GlobalEnvDefine(ctx.GlobalEnv^,
                SymbolName(NthArg(argsList, 0, 'def')), defValue);
              Result := defValue;
              Exit;
            end
            else
              raise EEvalError.CreateFmt(
                'eval: semantic id %s is registered but not implemented ' +
                'in this skeleton', [opID.ToBinaryString]);
          end
          else
          begin
            { head is not a registry keyword: an ordinary variable
              reference or a computed operator expression. Evaluate it
              (non-tail) and, if it is a closure, tail-call into its
              body -- this is what lets self-application-style recursion
              (no `define`, no mutable global env) work without any
              spelling-based special-casing. }
            fn := Eval(ctx, env, head);
            if not IsClosure(ctx, fn) then
              raise EEvalError.Create(
                'eval: value in operator position is not applicable');

            SetLength(argVals, 0);
            n := 0;
            node := argsList;
            while IsPair(node) do
            begin
              SetLength(argVals, n + 1);
              argVals[n] := Eval(ctx, env, PairHead(node));
              Inc(n);
              node := PairTail(node);
            end;

            { LABEL self-recursion (issue #27's own prerequisite):
              a closure built by LABEL carries its own name as
              ClosureLabelName. Extending the environment with
              (name -> fn) HERE, at call time, using the closure value
              already in hand, is what lets the body call itself by
              name with no mutation and no global-environment write --
              the binding exists only for the duration of this call,
              exactly matching McCarthy's own LABEL scoping. An
              ordinary LAMBDA closure's label name is MakeNil, so this
              is a no-op for every closure that isn't LABEL-built. }
            if IsNil(ClosureLabelName(fn)) then
              callEnv := ClosureEnv(fn)
            else
              callEnv := EnvExtend(ctx, ClosureLabelName(fn), fn, ClosureEnv(fn));

            env := BindParams(ctx, ClosureParams(fn), argVals, callEnv);
            expr := ClosureBody(fn);
            Continue;
          end;
        end;
    end;
  end;
end;

end.
