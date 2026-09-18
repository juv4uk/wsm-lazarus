;; GraalVM host mechanism budget against pinned my-lisp authority.
;; Classifications are evidence pointers, not semantic definitions.
(
  (schema . 1)
  (max-lisp-defined-java-debt . 0)

  (mechanism "0002" substrate-required
    (meaning-source . "lib/canon.lisp")
    (evidence . "contracts/answer-contract.lisp"))
  (mechanism "0003" substrate-required
    (meaning-source . "lib/canon.lisp")
    (evidence . "contracts/answer-contract.lisp"))
  (mechanism "0004" substrate-required
    (meaning-source . "lib/canon.lisp"))
  (mechanism "0005" substrate-required
    (meaning-source . "lib/canon.lisp"))
  (mechanism "0006" substrate-required
    (meaning-source . "lib/canon.lisp"))

  (mechanism "1001" substrate-required
    (meaning-source . "tests/fixtures/conformance.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp")
    (evidence . "tests/fixtures/conformance.lisp")
    (note . "Exact-rational subtraction/negation is a numeric substrate mechanism; Lisp-owned S1 fixtures define the observable results."))

  (mechanism "1014" substrate-required
    (meaning-source . "contracts/exact-q-binary-contract.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp"))
  (mechanism "1015" substrate-required
    (meaning-source . "contracts/exact-q-binary-contract.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp"))
  (mechanism "1016" substrate-required
    (meaning-source . "contracts/exact-q-binary-contract.lisp")
    (evidence . "contracts/structural-query-inventory.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp"))

  (retired "1017" lisp-defined
    (meaning-source . "lib/core.lisp")
    (evidence . "contracts/exact-q-binary-contract.lisp")
    (note . "removed from Java table on main before this ledger landed"))

  (retired "1022" lisp-defined
    (meaning-source . "lib/core.lisp")
    (evidence . "contracts/structural-query-inventory.lisp")
    (note . "Java mechanism retired after current-main Lisp-owned equal? witness"))

  (mechanism "1043" substrate-required
    (meaning-source . "lib/core.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp")
    (evidence . "NumericHeadRouteContract: 1043 head routes to admitted mechanism")
    (note . "string-append is exercised by Lisp-owned gensym; Java supplies only the irreducible string concatenation mechanism"))

  (mechanism "1052" substrate-required
    (identity-source . "lib/surface/semantic-registry.lisp"))

  (mechanism "1061" substrate-required
    (identity-source . "lib/surface/semantic-registry.lisp")
    (law-source . "tests/fixtures/conformance.lisp"))

  (rule . "No new Java mechanism ID may appear without classification here. Lisp-defined Java debt may only shrink.")
)
