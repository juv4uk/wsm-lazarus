;; Посилання на upstream authority замість копій.
;;
;; external/my-lisp — pinned Git submodule. Його working tree навмисно
;; Lisp-only: non-cone sparse-checkout з єдиним рекурсивним pattern *.lisp.
;; Це зберігає структуру my-lisp і автоматично підхоплює нові Lisp-файли,
;; але не матеріалізує Rust, Markdown, workflow/tooling та інші host-файли.
;;
;; Semantic authority залишається в my-lisp; цей файл містить лише шляхи
;; до потрібних runtime witnesses усередині pinned submodule.
(
 (dependency-manifest . "refs/lisp-dependency-manifest.lisp")
 (dependency-classification . "refs/upstream-dependency-classification.lisp")
 (registry     . "external/my-lisp/lib/surface/semantic-registry.lisp")
 (canon        . "external/my-lisp/lib/canon.lisp")
 (core         . "external/my-lisp/lib/core.lisp")
 (macro        . "external/my-lisp/lib/macro.lisp")
 (meta-eval    . "external/my-lisp/lib/meta-eval.lisp")
 (authority-boundary . "external/my-lisp/lib/machine/authority-boundary.lisp")
 (conformance  . "external/my-lisp/tests/fixtures/conformance.lisp")
 (constitution . "external/my-lisp/my-lisp-constitution.lisp")
 (contract     . "external/my-lisp/language-contract.lisp")
)
