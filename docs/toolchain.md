# FPC toolchain boundary

## Supported baseline

M0.2 is developed against **Free Pascal 3.2.2** on Linux x86-64.

The headless witness must remain buildable without Lazarus/LCL. Lazarus is declared
for the later M2 inspector only and is not part of the M0.2 runtime dependency
closure.

## One-command path

After the pinned authority submodule has been synchronized:

```bash
./scripts/sync-authority.sh
./scripts/test.sh
```

`scripts/test.sh` checks the authority pin/sparse boundary, the no-LCL firewall,
builds `src/wsm.headless.lpr`, verifies deterministic CLI exit behavior, and
runs the reusable test skeleton.

## Scope

A GREEN M0.2 gate proves only that the FPC substrate/toolchain is ready. It does
**not** claim that the Lisp reader, evaluator, semantic registry bridge, Canon,
or conformance suite works. Those remain later roadmap gates.
