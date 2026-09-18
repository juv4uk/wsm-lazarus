;; RELEASE v0.1.0 evidence bundle — Truffle substrate vertical day.
;; Owner-committed release issue: wsm-graalvm#147 (assignee anviksiki).
;; Every value below is a *pointer* into pinned evidence, never a semantic copy.
(
  (schema . 1)
  (release . "v0.1.0")

  ;; upstream semantic authority
  (authority
    (manifest . "refs/lisp-dependency-manifest.lisp")
    (manifest-load-order . ("lib/surface/semantic-registry.lisp" "lib/canon.lisp" "lib/core.lisp" "lib/macro.lisp"))
    (my-lisp-pin . "9ce5101853c0a9f43aacb32a98bb2bc9ab2eec3b")
    (pin-source . "refs/sparse-authority-paths.txt via scripts/sync-authority.sh"))

  ;; substrate
  (substrate
    (distribution . "graalvm-community-25.3.4.1+1.1 (linux-x64)")
    (maven-line . "truffle-api / polyglot / truffle-runtime / dsl-processor @ 25.3.4.1")
    (approach . "language implementation against Truffle, NOT a polyglot-side interpreter"))

  ;; observable self-verdict on both execution modes
  (self-verdict
    (jvm . "(canon-conformance satisfied) via scripts/run-canon.sh lane")
    (native-image . "same verdict reproduced in .github/workflows/native-image.yml CI on main"))

  ;; RED/green contract set, all GREEN at release tag moment
  (contracts
    (readers-string         . "READER-STRING-CONTRACT-OK")
    (conformance-inventory  . "CONFORMANCE-INVENTORY-CONTRACT-OK selected=2")
    (real-tier1-inventory   . "REAL-TIER1-INVENTORY-CONTRACT-OK selected=35")
    (truffle-frame          . "TRUFFLE-FRAME-CONTRACT-OK")
    (tier1-error-parity     . "TIER1-ERROR-PARITY-SUMMARY total=8 pass=7 blocked=1 fail=0")
    (variadic-lambda        . "VARIADIC-LAMBDA-CONTRACT-OK F25/F26/F27")
    (quote                  . "QUOTE-CONTRACT-OK surfaces=3 apostrophe=leading/internal dotted=preserved")
    (write-to-string        . "WRITE-TO-STRING-1061-CONTRACT-OK")
    (macro-peer-installer   . "MACRO-PEER-INSTALLER-OK peers=3")
    (bootstrap-closure-transport . "BOOTSTRAP-CLOSURE-TRANSPORT-OK")
    (numeric-head-route     . "NUMERIC-HEAD-ROUTE-CONTRACT-OK (issue #47 rule: registry-only admitted head)"))

  ;; what is intentionally NOT gates in v0.1.0 (owner directive release scope)
  (out-of-scope
    tier-2-conformance-S1-exact-rational ; VALUE_PASS_MIN lane stays baseline only
    polyglot-interop                     ; reserved to M2 per issue #79
    tail-calls-ADR                       ; reserved to M2 (issue #98 trail)
    pair-representation-ADR)

  ;; mechanism budget at release moment (issue #77 firewall)
  (mechanism-budget . "refs/lisp-mechanism-budget.lisp (substrate-required only; no unclassified entries)")

  ;; migration narrative that makes this release *understandable*
  (substrate-story
    (rust-core     . "lib/canon.lisp executed once by main my-lisp engine on same pin")
    (graal-substrate . "same pinned canon, self-verdict computed again here — same observable result")
    (witness-line  . "(canon-conformance satisfied) == '(the substrate reads its own authority)"))
)
