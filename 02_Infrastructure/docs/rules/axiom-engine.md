# Axiom Engine — 4-Mode 2-Tier (Level 0 SOT)

**v8.0 (2026-06-05, 2026-07-03 현행화 — 4-mode + Self-Adversarial). 원전 r7(`00_Lawbook/Axiom_아키텍처/r7_axiom_design.md`) 복원 + 4-mode 2-tier + 완전자동 + 사후 안전망.**
**위반 = AX-002 동급.** 상위 헌법: `.claude/rules/axioms.md`(global 공리 본문) / `measurement-graduation.md`(metric_type).

## 1. 파이프라인

```
L-code(모드별 적립) → harvest → cluster(mode-partition) → CAND
   → promote(mode-local AX-<MODE>-NNN) → promote_global(AX-NNN) → inject
                                          ↘ review(NARROW/deprecate) · rollback · weekly_report
```

- **4 모드** (2026-06-17 RAMP 추가): alpha_search(**proxy** — run_hurdle_gate → mode-local 한정) / QEPM(**backtested** forge) / factor_rotation(**backtested** build_bt_result+essence_score) / RAMP(**backtested** canonical_screen_bt/build_bt_result — `docs/rules/ramp.md`). modecode AS/QPM/FR/RAMP (`lcode_emit.R::.LCODE_MODE_PREFIX` = `promote.R::.MODE_PREFIX` 정합).
- **2-tier**: mode-local `active/modes/<mode>/AX-<MODE>-NNN.json` + global `active/AX-NNN.json`.

## 2. 안전 불변식 (절대 위반 금지)

- **INV-1 metric_type 게이트**: proxy/estimated → mode-local까지. global은 supporting 전부 `backtested`(essence_score §3 HARD).
- **INV-2 생성≠강제**: 자동 승격 = `enforcement_mode=documented`/`enforcement=""`. hook block은 주간 리포트 human confirm만.
- **INV-3 안전망 실작동**: 롤백 = 마커 블록 삭제(simulated diff 금지). 주간 리포트 = proxy/global 전건 human-review 플래그.
- **INV-4 r7 5축 무결성**: 승격 = 5축 각 min-hurdle 동시 충족(boolean AND). weighted는 랭킹용.
- **INV-5 AX-008**: 자동 global 승격 = Forge+Self-Adversarial+Architect 2/3 verification (v8.2 — Codex Round 제거, Opus 자체 적대검증으로 치환. 2/3 불변).
- **INV-6 statement 정제**: cluster 초안 텍스트 active화 금지.
- **INV-7 negative asymmetry**: negative = **provisional failure-ledger**(불변 법칙 아님). positive보다 높은 burden(construction↑) + expiry + 재도전 트리거(kr-inverse-pattern-miner). 현 negative auto-bonus 폐기.

## 3. 5축 (r7 — `promote.R`)

| 축 | hurdle | 비고 |
|---|---|---|
| Independence | distinct construction ≥ 2 (negative ≥ 3) + direction ≥ 0.8 | strategy_id 착시 폐기 |
| Rigor | backtested: weakest port_t ≥ 2.95 / negative: backtested frac_fail ≥ 0.8 | proxy=mode-local 관대 |
| Falsification | 적극 반증 attempts ≥ 1 + none_falsified + retained ≥ 0.5 | negative +0.5 폐기 |
| External | supporting L-code oos_retention 실값 존재 + cluster median ≥ 0.5 | 2026-07-03 재정의(GOV-01). 문턱 0.5 = measurement-graduation §3 '<0.5 무조건 FAIL' 하한 정합. oos_months는 가산 증거로 강등(실값 ≥3m 시 score +0.2, hurdle 무관). corpus 실값 0건 시 draft oos_effect_vs_is(=extractor oos_retention median) 폴백 |
| Mechanism | economic_explanation present + type ≠ unknown | |

## 4. 파일

- 엔진: `02_Infrastructure/axiom/{lcode_schema,lcode_emit,lcode_harvester.py,cluster_extractor.py,promote,promote_global,review,inject,axiom_rollback,axiom_weekly_report}.R`
- 파이프라인: `02_Infrastructure/ops/axiom_weekly.sh`(cron) · bootstrap(harvest)
- consumer: `hooks/{axiom_context_inject,axiom_enforcement_hook}.sh` · `memory/memory_knowledge_health.R` · `qepm/R/axiom_dashboard.R` (전부 recursive)
- 데이터: `qepm/memory/axioms/{active/,active/modes/<mode>/,candidates/,deprecated/,review_log/,axiom_sot_map.json}`
- 실행(Windows): `PY=%QVEST_PY% (User env: C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe)` · `RS=C:/Program Files/R/R-4.5.2/bin/Rscript.exe` · `CLAUDE_PROJECT_DIR` + `PYTHONUTF8=1`

## 5. 운영 규칙

- mode-local 자동 승격(documented). global 승격 + hook block = 주간 리포트 도훈 confirm(비가역).
- 기존 AX-003/004/005/007 = provisional(N=2~3 잠정, 재도전 대상). 추측 폐기 금지 — 엔진 asymmetric 재검증 경유.

## Change log
- 2026-07-03 (도훈 confirm, 감사 GOV-01): External 축 측정가능 재정의 — hurdle을 oos_months(corpus 실값 0건 = 영구 불충족) 기반에서 **oos_retention 실값 존재 ∧ cluster median ≥ 0.5**(corpus 457/594건 실값)로 교체. '요건 완화가 아니라 측정 불가능 지표의 측정 가능 지표 교체'. 문턱 0.5는 구 vs_is 0.5 개념 유지 + measurement-graduation §3 '<0.5 무조건 FAIL' 하한 정합. oos_months는 가산 증거로 강등. (`promote.R .HURDLE/.axis_external`)
- 2026-07-03 현행화 (승격 배관 수리 — hurdle 정의 불변): ① 3-mode → **4-mode**(AS/QPM/FR/**RAMP**, 2026-06-17 RAMP 모드 추가 반영 — `promote.R::.MODE_PREFIX`에 ramp 등재로 RAMP 승격 crash 해소) ② INV-5 Codex → **Self-Adversarial**(v8.2 AX-008 치환, `promote_global.R` verification 필드명 `codex`→`self_adversarial`, 구 필드명 back-compat 유지) ③ cluster_extractor `oos_months` 하드코딩 None → L-code 실값 매핑(실값 없으면 None 유지 — 요건 완화 없음).
- 2026-06-05 v8.0: 신규. r7 복원 + 3-mode 2-tier + INV-1~7 + 안전망. E2E 10/10 PASS.
