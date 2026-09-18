;; Source-confirmed dependency-classification snapshot from pinned my-lisp.
;; This is evidence for issue #30, not a second semantic authority.
;; The semantic meaning remains owned by external/my-lisp.
;;
;; Pin kept in sync with refs/tier1-baseline.properties (single authority pin).
(
  (schema . 1)
  (upstream . "juv4uk/my-lisp")
  (pin . "fa9bd8757983eb0eb8b3228c56ccc53471adde0c")
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
    ("unify.my" . 8)
    ("reason.my" . 3)
    ("understand.my" . 7)
    ("narrate.my" . 2)
    ("persistent-map.my" . 2))
  (unknown-symbols
    ("e3") ("1e") ("1e+") ("1e-") ("1.2.3")
    ("1ee3") ("--0.5") ("undefined-symbol"))
  (status . "fixture-dependency evidence only; full reachable *.lisp file classification remains issue #30 work"))
)
