;; wsm-lazarus task registry (swarm-node --auto-sync format)
;; Субстрат: Free Pascal / Lazarus.
;; Authority: pinned external/my-lisp @ fa9bd8757983eb0eb8b3228c56ccc53471adde0c.
;; GitHub roadmap: #1. Номери issue нижче — реальні GitHub issues цього repo.
(
 ("FPCLZ-M0-CLEAN-BOOTSTRAP" .
  ((priority . 9.6) (capabilities . (refs substrate-neutral clean pin)) (origin . wsm-lazarus)
   (issue . 2)
   (done . (t . "2026-09-18: Graal/Java release claims removed from active FPC refs;
     substrate-neutral consumer metadata; active pins aligned to fa9bd875…"))))

 ("FPCLZ-M0-PIN-AUTHORITY-GATE" .
  ((priority . 9.6) (capabilities . (submodule sparse pin gate ci)) (origin . wsm-lazarus)
   (issue . 3)
   (depends-on . (FPCLZ-M0-CLEAN-BOOTSTRAP))
   (done . (t . "2026-09-18: exact fail-closed pin/gitlink/submodule/non-cone
     sparse/materialized-set gate; scripts/sync-authority.sh + check-pin.sh."))))

 ("FPCLZ-M0-HEADLESS-HARNESS" .
  ((priority . 9.5) (capabilities . (fpc headless build test ci)) (origin . wsm-lazarus)
   (issue . 4)
   (depends-on . (FPCLZ-M0-PIN-AUTHORITY-GATE))
   (done . (t . "2026-09-18: semantics-free FPC 3.2.2 headless build/test harness
     and GitHub Actions lane merged."))))

 ("FPCLZ-M0-VALUE-REPRESENTATION" .
  ((priority . 9.3) (capabilities . (fpc values arena atom pair rational)) (origin . wsm-lazarus)
   (issue . 5)
   (depends-on . (FPCLZ-M0-HEADLESS-HARNESS))
   (done . (t . "2026-09-18: mechanism-only TValue + arena hardened;
     kVNil/kUnbound distinct, PairHead/PairTail structural API, exact Int64
     rational normalization, invalid handles fail safely, tests in main gate."))))

 ("FPCLZ-M0-READER" .
  ((priority . 9.2) (capabilities . (fpc reader quote dotted rational strings)) (origin . wsm-lazarus)
   (issue . 6)
   (depends-on . (FPCLZ-M0-VALUE-REPRESENTATION))
   (description . "wsm.reader.pas: pinned syntax only. Reader builds structural
     TValue data, never resolves semantic IDs or evaluator meaning.")))

 ("FPCLZ-M0-REGISTRY-BRIDGE-ID" .
  ((priority . 9.2) (capabilities . (fpc registry semantic-id bridge)) (origin . wsm-lazarus)
   (issue . 7)
   (depends-on . (FPCLZ-M0-READER))
   (description . "Pinned semantic-registry.lisp is read as data; surface spelling
     resolves to numeric semantic identity. No second Pascal authority table.")))

 ("FPCLZ-M0-EVAL-DISPATCH-TRAMPOLINE" .
  ((priority . 9.1) (capabilities . (fpc eval id-dispatch trampoline tco)) (origin . wsm-lazarus)
   (issue . 8)
   (depends-on . (FPCLZ-M0-REGISTRY-BRIDGE-ID))
   (description . "Eval/apply control loop dispatches by semantic ID only;
     trampoline is permanent; spelling fallback is forbidden.")))

 ("FPCLZ-M0-MECHANISM-BUDGET" .
  ((priority . 9.05) (capabilities . (fpc mechanism budget evidence fail-closed)) (origin . wsm-lazarus)
   (issue . 9)
   (depends-on . (FPCLZ-M0-EVAL-DISPATCH-TRAMPOLINE))
   (description . "Admit substrate mechanisms one ID at a time only from an
     upstream identity/law source plus a failing witness. Lisp-defined host debt=0.")))

 ("FPCLZ-M0-CANON-WITNESS" .
  ((priority . 9.0) (capabilities . (fpc canon conforms witness)) (origin . wsm-lazarus)
   (issue . 10)
   (depends-on . (FPCLZ-M0-MECHANISM-BUDGET))
   (description . "Pinned lib/canon.lisp is executed by the FPC witness itself.
     At fa9bd875… the authority-owned self-verdict is
     (canon-conformance satisfied), not host boolean t.")))

 ("FPCLZ-M1-TIER1-GATE" .
  ((priority . 8.8) (capabilities . (conformance tier1 fixtures baseline ci)) (origin . wsm-lazarus)
   (issue . 11)
   (depends-on . (FPCLZ-M0-CANON-WITNESS))
   (description . "Monotonic Tier-1 gate from refs/tier1-baseline.properties;
     any already-green regression fails closed.")))

 ("FPCLZ-M1-BIGINT-EXACTNESS" .
  ((priority . 8.5) (capabilities . (fpc bigint limbs rational property-test)) (origin . wsm-lazarus)
   (issue . 12)
   (depends-on . (FPCLZ-M1-TIER1-GATE))
   (description . "BigInt/exactness is a separate post-Tier-1 vertical;
     no floating fallback and no retroactive weakening of M0.")))

 ("FPCLZ-M2-LCL-GUI-INSPECTOR" .
  ((priority . 7.5) (capabilities . (lazarus lcl gui inspector registry-id)) (origin . wsm-lazarus)
   (issue . 13)
   (depends-on . (FPCLZ-M1-BIGINT-EXACTNESS))
   (description . "Thin LCL inspector over the same headless runtime:
     source → structural value → semantic ID → mechanism/Lisp path → result.
     GUI owns no evaluation semantics.")))
)
