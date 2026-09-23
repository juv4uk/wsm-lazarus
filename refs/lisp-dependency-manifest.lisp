;; my-lisp consumer manifest — substrate-neutral, спільний для всіх свідків
;; (wsm-graalvm, wsm-lazarus, …).
;;
;; This declares the current M0/M1 runtime slice. It is not a copy of Lisp
;; semantics. Semantic identity, laws, and source meaning remain upstream.

(
  (schema . 1)
  (upstream . "juv4uk/my-lisp")
  (pin . "0a89a03b2565c5e2f7723e6ceaf4878eaeb6844c")

  (authority
    ("language-contract.lisp")
    ("my-lisp-constitution.lisp")
    ("lib/surface/semantic-registry.lisp"))

  (bootstrap-required
    ("lib/canon.lisp" . (gate M0))
    ("lib/macro.lisp" . (gate M1))
    ("lib/core.lisp" . (gate M1)))

  (load-order
    ("lib/surface/semantic-registry.lisp")
    ("lib/canon.lisp")
    ("lib/macro.lisp")
    ("lib/core.lisp"))

  (witness
    ("tests/fixtures/conformance.lisp" . (gate M1))
    ("tests/fixtures/conformance-transition-witness.lisp" . (gate M1 current-outcomes))
    ("contracts/answer-contract.lisp" . (mechanism-budget canon-results))
    ("contracts/exact-q-binary-contract.lisp" . (mechanism-budget numeric-comparisons))
    ("contracts/structural-query-inventory.lisp" . (mechanism-budget producer-ownership))
    ("lib/machine/authority-boundary.lisp" . (guard))
    ("knowledge/guard-reference.lisp" . (guard)))

  (not-bootstrap-by-default
    ("lib/meta-eval.lisp" . "explicit later self-hosting witness")
    ("lib/core1.lisp" . "explicit later Core1 S0-seed witness; historical S0 surface, does not depend on Contract 6/7/8 (own minimal semantics, no canonical three-part COND fail-closed dependency)")
    ("tests/fixtures/core1-s0-witness.lisp" . "witness fixture for lib/core1.lisp, needed once a Core1 gate exists")
    ("contracts/core1-bootstrap-contract.lisp" . "Core1's own bootstrap contract; not part of default M0/M1 bootstrap chain")
    ("lib/machine/**" . "machine-specific witness/evidence")
    ("lib/generated/**" . "generated projection; never semantic authority")
    ("evidence/**" . "evidence artifacts")
    ("docs/research/**" . "research material")
    ("prototype/**" . "experimental material"))

  (rule
    . "A new bootstrap source requires a source-confirmed dependency edge plus a witness that needs it. Directory presence alone is not admission."))
