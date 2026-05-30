# Measurement Integrity + Graduation 허들 (Level 0)

**발효**: 2026-05-29 (v8.x WS1/2/3, 도훈 mandate "한 번 재설계하고 가자"). **위반 = AX-002 동급**(proxy 수치로 게이트 통과 = 프로세스 우회 = 미래참조).
**근거**: 16-cycle 리서치가 "alpha/risk/optimizer가 proxy 손계산 수치로 graduation PASS 선언"하는 구조결함 노출 (Cycle 5 QVALUE "5/5 PASS"가 전부 proxy). E2E 입증: FLOW proxy portfolio-α t 3.55 → forge 실측 2.35 (Cycle 2 D 4.31→2.31 재현).

## §1 Real-Computation 의무 (alpha/risk/optimizer 공통)
- 성능수치(portfolio-alpha t / SR / IR / active 등) **proxy 손계산 금지** (top-quintile EW + turnover×bps 인라인 근사, `prod(1+r)`/`cumprod` 자체합성).
- 반드시 경유: **`02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt()`** (canonical top-N EW long-only, contract `build_benchmark_compare` 경유 실측) 또는 forge **`build_bt_result()`**.
- **모든 의사결정 수치에 `metric_type` 라벨 의무**: `canonical_screen`(alpha/risk 스크리닝 실측) / `backtested`(forge 최적화 weights = authoritative) / `estimated` / `proxy`. 라벨 없는 "backtested" 주장 금지.

## §2 portfolio-alpha t = forge-authoritative
- **`forge_package.portfolio_alpha_t_nw_lag3`** (build_benchmark_compare `Portfolio_Alpha_t_NW_lag3` row, NW lag-3 net active series). v8.x 신규(기존 contract 미산출 갭).
- **rank-IC t와 명확히 구분** — rank-IC t는 횡단면 순위력, portfolio-alpha t는 실제 long 포트의 실현 초과수익. long-only top-N에선 후자가 권위(rank-IC 강해도 portfolio alpha 약한 경우 흔함). Cycle 2 교훈.

## §3 Graduation 게이트 severity (문턱 완화 X, 게이트 선택 수정)
`constraint_defaults.json::tier_graduation.severity` + `discovery_graduation_gate.sh`:
- **HARD (block)**: `portfolio_alpha_t_nw` ≥ 2.95 (Harvey-Liu-Zhu, 문헌-레벨 다중검정 이미 반영) + **`oos_retention` ≥ 0.7** (활성 Sharpe OOS/IS — 과적합 게이트) + **`calmar` ≥ 0.64** (=16%/25%, CAGR16·MDD25서 도출, 위험조정). **forge-authoritative 값에만** 적용(alpha proxy로 graduation 선언 금지).
- **DSR 조건부 (2026-05-31 도훈 mandate)**: `deflated_sharpe_ratio` ≥ 0.5는 **다중검정 스타일(n_trials>1: ML 스윕/optimizer 서치/앙상블 스윕)에서만 HARD 게이트.** 1논문/1알파 검증(n_trials≈1)엔 **부적용** — PORT_t 2.95가 이미 문헌 다중검정 보정이라 중복이고, n_trials가 무의미. (구 규칙 "DSR 무조건 HARD" 폐기.) 명시적 스윕에서만 적용. 단일전략 과적합은 DSR 아닌 oos_retention이 담당.
- **ADVISORY (warn only)**: rank_ic / icir / harvey_t_stat(rank-IC) / subperiod_stability. long-only 실현 alpha와 어긋나 거짓통과·거짓탈락 유발(16후보 calibration 실증: rank_ic≥0.04가 FLOW 거짓탈락 + NN/TECH 거짓통과, PORT_t는 FLOW 1건만 정확 통과).
- judge Gate C = portfolio-alpha t ≥ 2.95 AND net_IR > 0.2. **Grade 산정 권위 = `02_Infrastructure/contracts/essence_score.R`** (hurdle_gate 18-component은 proxy 진단용 강등).

## §4 Admission = book-marginal (standalone 졸업 아님)
- `portfolio_governor.R::pg1_admission_with_book_context()`: standalone ADMIT 후 **ΔIR = new_book_ir − incumbent_book_ir ≥ 0.05** 충족 시에만 ADMIT(미달 DEFER). `book_optimizer.R` book_information_ratio/book_update 재사용. baseline = `book_state.json::incumbent_book_ir`.
- **governor admit(book_state 쓰기)은 자동화 금지** — 비가역 자본 게이트, Q-Lead + 도훈 수동 confirm. (dossier 워크플로우는 risk→judge까지만 자동, governor 정지.)

## §5 DPL = 구성 레이어 (알파는 피처)
- 실패한 standalone 알파는 폐기 아닌 **DPL(Direct Portfolio Learning) 입력 피처**. DPL: features→weights end-to-end(미분가능 convex layer, long-only/Σw=1/[0,0.20]/15bps native, net Sharpe 직접 최적화). research_philosophy ④. 알파 리서치 = DPL 연료. (pilot 진행 — `02_Infrastructure/ml_pipeline/dpl_portfolio.py`, weight_method_registry "DPL".)

## §6 확립된 전략 진실 (실증, AX-000 정직보고)
- **KR long-only 수익률직교 구조적 불가**: BAB(β-0.04)·VALUE(β-0.074) 둘 다 시장중립인데 return_cor vs STR_1715 0.78/0.76 (covariance 1st eigenmode 지배, no-short로 제거 불가). 16/16 standalone FAIL.
- **SR 2.5 레버 = overlay(β/regime timing, 주역) + DPL(직접 SR 최적화) + uncertainty 선택**. "새 직교 sleeve 사냥"은 한계 효익(IR/MDD)만.

## 참조
- `.claude/rules/backtest-contract.md`(10-component) / `pit.md` / `research_philosophy.md`(④⑤⑥) / `answer-principles.md`(자체합성 금지)
- `02_Infrastructure/contracts/{backtest_result_contract,canonical_screen_bt,registry_writer}.R` · `hooks/discovery_graduation_gate.sh` · `portfolio/portfolio_governor.R`
- 메모리: [[learning-gate-calibration-longonly]] / [[reference-alpha-trends-2024-2026]] / [[reference-str1715-structure]]
- SOT: `02_Infrastructure/docs/qvest_v8_0_upgrade_plan.md`

## Change log
- 2026-05-31 (도훈 mandate): §3 게이트 재설계. DSR≥0.5 "무조건 HARD" 폐기 → **다중검정 스타일(n_trials>1)에서만 HARD**(DSR은 multiple-testing 개념, 1논문/1알파엔 부적용·PORT_t 2.95와 중복). 단일전략 과적합 게이트 = **oos_retention≥0.7**(DSR 대체) + 위험조정 게이트 **calmar≥0.64**(=16%/25%). Grade 권위 = `essence_score.R`(hurdle_gate 18-component proxy 강등). Dual-Mode SOT §3.5 정합.
- 2026-05-29 v8.x: 신규. WS1 real-computation + WS2 graduation severity 재설계 + WS3 book-marginal admission. E2E(FLOW forge 2.35) 입증.
