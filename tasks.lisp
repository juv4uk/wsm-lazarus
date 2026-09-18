;; wsm-lazarus task registry (swarm-node --auto-sync format)
;; Субстрат: Free Pascal / Lazarus. Влада — pinned external/my-lisp (fa9bd875…).
;; Список вертикалей за ADR docs/decisions/2026-09-18-fpc-first-vertical-ADR.md.
(
 ;; M0: очищення спадщини Graal і єдиний authority pin.
 ("FPCLZ-M0-CLEAN-BOOTSTRAP" .
  ((priority . 9.6) (capabilities . (refs substrate-neutral clean pin)) (origin . wsm-lazarus)
   (done . (t . "2026-09-18: refs стають substrate-neutral (без Graal/Java/debt);
     спільні файли позначено кандидатами на підйом в upstream my-lisp/refs/;
     RELEASE-v0.1.0.lisp (Graal) видалено; java-surface-spelling-exceptions.txt
     перейменовано; усі pin-посилання зведено до fa9bd875…"))))

 ("FPCLZ-M0-PIN-AUTHORITY-GATE" .
  ((priority . 9.6) (capabilities . (submodule sparse pin gate ci)) (origin . wsm-lazarus)
   (done . (t . "2026-09-18: scripts/check-pin.sh — PIN-GATE-OK fa9bd875…,
     13 authority paths, sparse-cone; drift → exit 1"))))

 ("FPCLZ-M0-VALUE-REPRESENTATION" .
  ((priority . 9.3) (capabilities . (fpc values arena atom pair abs)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-PIN-AUTHORITY-GATE))
   (issue . 1)
   (description . "wsm.values.pas: nil/symbol/number/string/pair; arena для pair/string;
     no Lisp semantics here. Invariant: exact-rational int64 num/den reduced.
     Test vertical scripts/test-values.pas must go green under fpc 3.2.2.")))

 ("FPCLZ-M0-READER" .
  ((priority . 9.2) (capabilities . (fpc reader quote dotted-numbers strings)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-VALUE-REPRESENTATION))
   (issue . 2)
   (description . "wsm.reader.pas: pinned Lisp syntax (quote, dotted pairs, numbers,
     strings). Reader не знає семантики функцій; Contract 4.0, QUOTE_HEAD.")))

 ("FPCLZ-M0-REGISTRY-BRIDGE-ID" .
  ((priority . 9.2) (capabilities . (fpc registry semantic-id bridge)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-READER))
   (issue . 3)
   (description . "Символьна поверхня → semantic ID з semantic-registry.lisp.
     LCL жодного власного словника семантики: dispatch лише за числовими IDs.")))

 ("FPCLZ-M0-EVAL-DISPATCH-TRAMPOLINE" .
  ((priority . 9.1) (capabilities . (fpc eval id-dispatch trampoline tco error-parity)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-REGISTRY-BRIDGE-ID))
   (issue . 4)
   (description . "wsm.eval.pas: dispatch за ID, мінімальний admitted mechanism set,
     trampoline TCO. Error-identity parity із Graal-свідком (fail-closed
     error-kind/ID: e.g. Type not a callable value: 0104).")))

 ("FPCLZ-M0-CANON-WITNESS" .
  ((priority . 9.0) (capabilities . (fpc canon conforms witness)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-EVAL-DISPATCH-TRAMPOLINE))
   (issue . 5)
   (description . "Рубіж M0: pinned lib/canon.lisp виконується FPC-свідком і дає
     (canon-conforms?) → t. Не «паскаль-лісп працює», а згода з контрактом.")))

 ("FPCLZ-M1-TIER1-GATE" .
  ((priority . 8.8) (capabilities . (conformance tier1 fixtures baseline ci)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M0-CANON-WITNESS))
   (issue . 6)
   (description . "Monotonic tier-1 gate: SELECTED=35, VALUE_PASS_MIN=25,
     ERROR_PASS_MIN=7 за refs/tier1-baseline.properties.")))

 ("FPCLZ-M1-BIGINT-EXACTNESS" .
  ((priority . 8.5) (capabilities . (fpc bigint limbs rational property-test)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M1-TIER1-GATE))
   (issue . 7)
   (description . "TBigInt (32-бітні лімби) → повнота exactness S1 на tier-2
     fixtures; property-тести проти BigInteger з першого дня. Substrate-required,
     semantics-blind.")))

 ("FPCLZ-M2-LCL-GUI-INSPECTOR" .
  ((priority . 7.5) (capabilities . (lazarus lcl gui inspector registry-id)) (origin . wsm-lazarus)
   (depends-on . (FPCLZ-M1-TIER1-GATE))
   (issue . 8)
   (description . "LCL-інспектор поверх headless witness: шлях
     spelling → semantic ID → authority → FPC mechanism → value. GUI не є
     носієм authority; лише вікно в канон.")))
)