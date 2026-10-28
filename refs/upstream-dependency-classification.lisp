;; Source-confirmed dependency-classification snapshot from pinned sens.
;; This is evidence for issue #30, not a second semantic authority.
;; The semantic meaning remains owned by external/sens.
;;
;; Pin kept in sync with refs/tier1-baseline.properties (single authority pin).
(
  (schema . 1)
  (upstream . "juv4uk/sens")
  (pin . "1f1bf676eeac605e065035d9dd2adaae807f1788")
  (generator
    (path . "scripts/build-dependency-classification.lisp")
    (source-blob . "49e85c90b5983f71c3c9a883037f925455497702"))
  (artifact
    (path . "tests/fixtures/dependency-classification.lisp")
    (source-blob . "e6c17dda2ecc263be36186e3d2c0cbeac7346e3b")
    (records . 226))
  (fixture-buckets
    (core . 141)
    (exact-numbers . 59)
    (macro-expanded-core . 85)
    (strings-reader . 40)
    (closure-application . 25)
    (reasoning-world-or-host . 23))
  (world-host-libraries
    ("unify.lisp" . 8)
    ("reason.lisp" . 3)
    ("understand.lisp" . 7)
    ("narrate.lisp" . 2)
    ("persistent-map.lisp" . 2))
  (unknown-symbols
    ("e3") ("1e") ("1e+") ("1e-") ("1.2.3")
    ("1ee3") ("--0.5") ("undefined-symbol"))
  (status . "fixture-dependency evidence only; full reachable *.lisp file classification remains issue #30 work"))
