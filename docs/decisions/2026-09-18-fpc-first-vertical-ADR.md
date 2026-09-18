# ADR: 2026-09-18 — П'ятий субстрат FPC: перша вертикаль свідка

**Статус:** PROPOSED (потребує підпису власника — дизайн-authority належить йому).
**Дотичні:** `my-lisp` (authority), `wsm-graalvm` (еталон гейтів), лінія RAS/WASM/FPGA.
**Pin:** `/contracts/*`, `/lib/canon.lisp`, `/lib/core.lisp`, `/lib/macro.lisp`,
`/lib/surface/semantic-registry.lisp`, `/my-lisp-constitution.lisp`,
`/tests/fixtures/conformance.lisp` при `fa9bd8757983eb0eb8b3228c56ccc53471adde0c`.

## Контекст

Один субстрат показує один зріз ідеї. Graal-witness доводить canon десятьма
тисячами механізмів; FPC-свідок має довести те саме **чистішим** шляхом:
статистична компіляція, детермінована пам'ять без GC, стартап у мілісекундах.
Додатково LCL відкриває те, чого GraalVM не має: десктопний GUI-інспектор
свідчень (пов'язка з `my-idea`, M2).

Гарячі факти, виміряні перед ADR (2026-09-18):
- fpc НЕ встановлений на хості; **жоден маніфест** (`my-lisp`, `wsm-graalvm`)
  його не згадує; `guix shell fpc` життєздатний (46.5 MB сабститутів, без sudo);
  apt-кандидат Kali: `fpc 3.2.2+dfsg`, `lazarus 4.8`.
- У `tests/fixtures/conformance.lisp` (288 рядків) **усі** літерали, що
  перевищують int64 (`12345678901234567890.1234…`, `1e±100`,
  `(+ 123456789012345678901234567890 1)`), мають `tier . 2` (S1).
  Tier-1 раціонали вкладаються в int64-пари num/den із приведенням.

## Рішення

1. **Критерій M0 той самий, буквально:** `(canon-conforms?)` → `t`
   з pinned `canon.lisp` на власному reader-у/eval-у. Не «паскаль-лісп працює».
2. **Представлення значень — A з плямою B + арена.** Атоми — tagged record
   (`case kind of kNil, kPair, kNumber, kSymbol, kString`); конси/стрічки —
   у **арені** (bump-алокатор на життя одного canon-witness запуску).
   Мотивація: witness-рантайм обмежений і детермінований; ручний refcount
   не потрібен; GC-шум відсутній; trampoline тривіальний (керри-фрейми не
   живуть довго).
3. **TCO — trampoline з першого коміту, перманентно.** FPC хвіст-рекурсію
   не гарантує (той самий джунгль, що й JVM); рішення — вузький
   `apply`-цикл/продовження на керри-фреймах арени, без transition-only мостів.
4. **BigInt — послідовність:** M0-SEM на int64-раціоналах з приведенням
   (tier-1 exact essence, S1 boundary = tier-2 gate), потім **окрема вертикаль
   M1-BIGINT** (чистий паскалівський TBigInt, 32-бітні лімби, property-тести
   проти `BigInteger` з першого дня). Повнота exactness S1 закривається M1.
5. **Порядок завантаження влади — той самий:** registry → canon → core →
   macro → (tier-1 conformance), за `refs/lisp-dependency-manifest.lisp`.
6. **Гейти дзеркалюють wsm-graalvm:** `test-tier1.sh`, `run-canon.sh`,
   `check-spelling-firewall.sh`; `refs/tier1-baseline.properties` — той самий
   monotonic baseline (SELECTED=35, VALUE_PASS_MIN=25, ERROR_PASS_MIN=7).

## Відкриті питання (для підпису)

- Встановлення FPC: guix shell (рекомендовано) чи apt через sudo.
- Публікація репо вже зараз (PUBLIC, ВОЛЬНІСТЬ) — проголосовано вручну
  власником; список 19-ти owns оновлюється в ecosystem audit.
- Чи включати `gui/` (LCL) у цю ж M0-вертикаль чи тримати headless
  `wsm.conform.lpr` єдиним носієм authority (рекомендовано: headless спершу).

## Шлях

```
wsm.bigint.pas   → (M1, окремо)
wsm.reader.pas   → Contract 4.0, QUOTE_HEAD, не speллінг
wsm.values.pas   → tagged atoms + arena pairs (це рішення)
wsm.eval.pas     → dispatch за числовими IDs + trampoline
wsm.conform.lpr  → canon → (canon-conforms?) → t
```