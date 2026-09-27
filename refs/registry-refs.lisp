;; Посилання на upstream authority замість копій.
;;
;; external/sens — pinned Git submodule. Його working tree навмисно
;; Lisp-only: non-cone sparse-checkout з єдиним рекурсивним pattern *.lisp.
;; Це зберігає структуру sens і автоматично підхоплює нові Lisp-файли,
;; але не матеріалізує Rust, Markdown, workflow/tooling та інші host-файли.
;;
;; Semantic authority залишається в sens; цей файл містить лише шляхи
;; до потрібних runtime witnesses усередині pinned submodule.
(
  (dependency-manifest . "refs/lisp-dependency-manifest.lisp")
  (dependency-classification . "refs/upstream-dependency-classification.lisp")
  (registry     . "external/sens/lib/surface/semantic-registry.lisp")
  (canon        . "external/sens/lib/canon.lisp")
  (core         . "external/sens/lib/core.lisp")
  (macro        . "external/sens/lib/macro.lisp")
  (meta-eval    . "external/sens/lib/meta-eval.lisp")
  (authority-boundary . "external/sens/lib/machine/authority-boundary.lisp")
  (conformance  . "external/sens/tests/fixtures/conformance.lisp")
  (constitution . "external/sens/sens-constitution.lisp")
  (contract     . "external/sens/language-contract.lisp")
)
