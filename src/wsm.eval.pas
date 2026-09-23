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
 * Core1's own primitive table (external/my-lisp/lib/core1.lisp's
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
 * ATOM already uses; this does NOT touch the separate, still-open
 * question of bare NIL/T as self-evaluating McCarthy ground values
 * (paused 2026-09-23 pending broader discussion).
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
    "NIL" string. T is deliberately absent here: it has no SID at all
    (contracts/core1-bootstrap-contract.lisp lists it as "seed-only"),
    and a single fixed "true" answer is exactly what my-lisp's own
    ongoing truth-semantics evolution moves away from -- not this
    evaluator's decision to make. }
  TEvalContext = record
    Arena: PArena;
    Symbols: PSymbolTable;
    Registry: PRegistry;
    HistoricalMap: PHistoricalMap;
    ClosureMarker: TValue;
    IdQuote, IdCons, IdCar, IdCdr, IdCond, IdLambda, IdAtom, IdEq: TSid8;
    IdEmptyList: TSid8;
  end;

procedure EvalContextInit(out ctx: TEvalContext; var arena: TArena;
  var symbols: TSymbolTable; var reg: TRegistry; var histMap: THistoricalMap);

{ env is a plain list of (symbol . value) bindings, innermost first --
  MakeNil is a valid, empty top-level environment. }
function Eval(var ctx: TEvalContext; env: TValue; expr: TValue): TValue;

implementation

const
  CLOSURE_MARKER_NAME: RawByteString = '##wsm-closure##';

type
  TValueArray = array of TValue;

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
  var symbols: TSymbolTable; var reg: TRegistry; var histMap: THistoricalMap);
begin
  ctx.Arena := @arena;
  ctx.Symbols := @symbols;
  ctx.Registry := @reg;
  ctx.HistoricalMap := @histMap;
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

function MakeClosure(var ctx: TEvalContext; params, body, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, ctx.ClosureMarker,
    MakePair(ctx.Arena^, params, MakePair(ctx.Arena^, body, env)));
end;

function IsClosure(var ctx: TEvalContext; v: TValue): Boolean;
begin
  Result := IsPair(v) and IsSymbol(PairHead(v)) and
    (SymbolName(PairHead(v)) = SymbolName(ctx.ClosureMarker));
end;

function ClosureParams(v: TValue): TValue;
begin
  Result := PairHead(PairTail(v));
end;

function ClosureBody(v: TValue): TValue;
begin
  Result := PairHead(PairTail(PairTail(v)));
end;

function ClosureEnv(v: TValue): TValue;
begin
  Result := PairTail(PairTail(PairTail(v)));
end;

function EnvExtend(var ctx: TEvalContext; sym, value, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, MakePair(ctx.Arena^, sym, value), env);
end;

function EnvLookup(env: TValue; sym: TValue): TValue;
var
  node, binding: TValue;
  name: RawByteString;
begin
  name := SymbolName(sym);
  node := env;
  while IsPair(node) do
  begin
    binding := PairHead(node);
    if SymbolName(PairHead(binding)) = name then
    begin
      Result := PairTail(binding);
      Exit;
    end;
    node := PairTail(node);
  end;
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
          { NIL is not a function of this evaluator, it is an ANSWER
            (issue #26, owner: "ніл і т, це не функції мови, це
            відповіді самої мови"): a bare symbol whose HISTORICAL name
            bridges, via the pinned historical map, to the same SID as
            the registry's own ground empty-list identity evaluates to
            MakeNil -- compared by SID, never by matching the symbol's
            spelling against a literal "NIL" string. Every other symbol
            (including "T", which the pinned bootstrap contract lists
            as having no SID at all) falls through to ordinary
            variable lookup exactly as before. }
          haveHistID :=
            HistoricalLookup(ctx.HistoricalMap^, SymbolName(expr), histID);
          if haveHistID and (histID = ctx.IdEmptyList) then
            Result := MakeNil
          else
            Result := EnvLookup(env, expr);
          Exit;
        end;

      kPair:
        begin
          head := PairHead(expr);
          argsList := PairTail(expr);

          haveID := False;
          if IsSymbol(head) then
            haveID := RegistryLookup(ctx.Registry^, SymbolName(head), opID);

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

            env := BindParams(ctx, ClosureParams(fn), argVals, ClosureEnv(fn));
            expr := ClosureBody(fn);
            Continue;
          end;
        end;
    end;
  end;
end;

end.
