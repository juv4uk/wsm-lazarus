;; GraalVM consumer manifest for the pinned my-lisp Lisp authority.
;;
;; This declares the current M0/M1 runtime slice. It is not a copy of Lisp
;; semantics. Semantic identity, laws, and source meaning remain upstream.

(
  (schema . 1)
  (upstream . "juv4uk/my-lisp")
  (pin . "fa9bd8757983eb0eb8b3228c56ccc53471adde0c")

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
    ("lib/machine/**" . "machine-specific witness/evidence")
    ("lib/generated/**" . "generated projection; never semantic authority")
    ("evidence/**" . "evidence artifacts")
    ("docs/research/**" . "research material")
    ("prototype/**" . "experimental material"))

  (rule
    . "A new bootstrap source requires a source-confirmed dependency edge plus a witness that needs it. Directory presence alone is not admission."))
