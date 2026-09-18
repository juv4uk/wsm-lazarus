;; my-lisp substrate mechanism budget — substrate-neutral.
;; Каталог дозволених substrate механізмів проти pinned my-lisp authority.
;; СПІЛЬНИЙ для всіх свідків (wsm-graalvm, wsm-lazarus, …): кожен субстрат
;; реалізує той самий набір IDs; класифікації тут — доказові вказівники,
;; а не семантичні визначення (семантика Lisp-side).
;;
;; PHASE: кандидат на підйом в upstream my-lisp/refs/ як спільний каталог.
;;
;; Класифікація (для обох субстратів):
;;   substrate-required — механізм, що втілює Lisp-визначену семантику на
;;                        даному фізичному субстраті (пам'ять, числа, стрічки);
;;   lisp-defined       — семантика повністю в Lisp (core/macro), субстрат
;;                        лише виконує; такі механізми можуть бути retired.
;;
;; FPC-субстрат починає з підмножини tier-1 (СЕМ 0002..0006, 1001,
;; exact-q 1014..1016, 1043, 1052, 1061) та trampoline-еvaluator.
(
  (schema . 1)
  (max-lisp-defined-substrate-debt . 0)

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
    (note . "removed from substrate table on main before this ledger landed"))

  (retired "1022" lisp-defined
    (meaning-source . "lib/core.lisp")
    (evidence . "contracts/structural-query-inventory.lisp")
    (note . "sandbox mechanism retired after current-main Lisp-owned equal? witness"))

  (mechanism "1043" substrate-required
    (meaning-source . "lib/core.lisp")
    (identity-source . "lib/surface/semantic-registry.lisp")
    (evidence . "NumericHeadRouteContract: 1043 head routes to admitted mechanism")
    (note . "string-append is exercised by Lisp-owned gensym; the substrate supplies only the irreducible string concatenation mechanism"))

  (mechanism "1052" substrate-required
    (identity-source . "lib/surface/semantic-registry.lisp"))

  (mechanism "1061" substrate-required
    (identity-source . "lib/surface/semantic-registry.lisp")
    (law-source . "tests/fixtures/conformance.lisp"))

  (rule . "No new substrate mechanism ID may appear without classification here. Substrate-defined mechanism debt may only shrink.")
)