;; SENS consumer manifest — active exact-domain and Core4 sources
;; (wsm-graalvm, wsm-lazarus, …).
;;
;; This declares the current M0/M1 runtime slice. It is not a copy of Lisp
;; semantics. Semantic identity, laws, and source meaning remain upstream.

(
  (schema . 1)
  (upstream . "juv4uk/sens")
  (pin . "2c498b35af53c085450eac6f51b87facf7f9aa47")

  (authority
    ("language-contract.lisp")
    ("my-lisp-constitution.lisp")
    ("lib/surface/semantic-registry.lisp"))

  (bootstrap-required
    ("lib/canon.lisp" . (gate M0))
    ("lib/macro.lisp" . (gate M1))
    ("lib/core.lisp" . (gate M1))
    ("lib/core4.lisp" . (gate M1 core4-profile)))

  (load-order
    ("lib/surface/semantic-registry.lisp")
    ("lib/canon.lisp")
    ("lib/macro.lisp")
    ("lib/core.lisp")
    ("lib/core4.lisp"))

  (witness
    ("tests/fixtures/conformance.lisp" . (gate M1))
    ("tests/fixtures/conformance-transition-witness.lisp" . (gate M1 current-outcomes))
    ("contracts/core-profile-contract.lisp" . (profile-authority))
    ("contracts/answer-contract.lisp" . (mechanism-budget canon-results))
    ("contracts/exact-q-binary-contract.lisp" . (mechanism-budget numeric-comparisons))
    ("lib/machine/authority-boundary.lisp" . (guard))
    ("knowledge/guard-reference.lisp" . (guard)))

  (not-bootstrap-by-default
    ("lib/meta-eval.lisp" . "explicit later self-hosting witness")
    ("contracts/core1-bootstrap-contract.lisp" . "Core1's own bootstrap contract; not part of default M0/M1 bootstrap chain")
    ("lib/machine/**" . "machine-specific witness/evidence")
    ("lib/generated/**" . "generated projection; never semantic authority")
    ("evidence/**" . "evidence artifacts")
    ("docs/research/**" . "research material")
    ("prototype/**" . "experimental material"))

  (rule
    . "A new bootstrap source requires a source-confirmed dependency edge plus a witness that needs it. Directory presence alone is not admission."))
