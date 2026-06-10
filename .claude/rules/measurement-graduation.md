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
- **DSR 적용경계 = selection operator (2026-05-31 + 2026-06-10 도훈 mandate)**: `deflated_sharpe_ratio` ≥ 0.5 HARD는 **sweep형 selection에서만** — 열거된 trial 집합에서 argmax/threshold-pick으로 최종안을 고르는 구조(ML HPO 스윕 / optimizer 서치 / 앙상블·파라미터 grid / 사전등록 family grid). **"n_trials>1"은 sweep의 신호가 아니다** — 가설주도 순차개선 체인(1가설 1전략, 진단→개선 반복)은 iteration이 몇 번이든 각각 독립 리서치 결과로 보고 **DSR 게이트 부적용**(`selection_type="chain"`). 1논문/1알파(n_trials≈1)도 부적용 (PORT_t 2.95가 문헌-레벨 다중검정 기보정). 단일전략 과적합 방어 주책임 = oos_retention 0.7 + holdout + placebo.
  - **chain 자격요건 (전부 충족 — 미충족 시 sweep 재분류)**: ① iteration별 변경사유 = mechanism 진단 1줄 기록 ② **iteration 중 변형 선택은 IS-only** (OOS 반복조회 = OOS 오염 = oos_retention 게이트 무효화 — valearn IS-only 선택 protocol이 실무 선례) ③ holdout은 최종판 1회만 조회.
  - DSR 수치 자체는 n_trials>1이면 **진단용으로 계속 산출·기록** (게이트 아님). n_iterations/n_trials 기록 의무는 유지 (사후 감사 가능성).
- **oos_retention 통계량 v2 + borderline escalation (2026-06-10 도훈 mandate C1)**: retention = anchored 3분할 {55/65/75} **중앙값** (`essence_score.R oos_stat_version="v2"` 기본 — 단일 절단점 임의성 축소, 실측: 같은 시계열서 splits 0.55/0.59/0.78). 판정: **≥0.7 단독 PASS** / **<0.5 무조건 FAIL**(증거 무관) / **[0.5, 0.7) band = 보강증거 2/3 충족 시 조건부 PASS** (① trailing-subwindow PORT_t>0 ② placebo p<0.05 ③ book-marginal ΔSR>0 ∧ |cor|<0.30. **holdout은 증거 불가** — 봉인 원칙). FAIL 시 overfit-pattern(전략 고유)/decay-pattern(cohort-wide, 예: 327팩터 2017+) 사유 라벨 — decay는 screening tier `screen_route`로 라우팅(자본 graduation 불가는 동일).
- **holdout 규약 (2026-06-10 도훈 mandate C3)**: 18~24개월 Sharpe SE ±0.7~0.8 → 성과 채점 금지. 판정 = **사전등록 예측구간 falsification** (`02_Infrastructure/contracts/holdout_falsification.R`): 채택 시점에 IS+OOS 블록 부트스트랩(block=12)으로 holdout-길이 Sharpe [5%, 95%] **사전 기록**(불변, overwrite 거부) → 실측 < q05 = **FAIL_FALSIFIED** / 구간 내 = **PASS_LOW_INFO**(구간 내 위치로 우열 해석 금지) / > q95 = PASS_PLUS. **소모 규칙**: 열람 후 파라미터 수정 시 `mark_consumed()` — 새 봉인 구간 누적 전 재판정 금지. **라이브 = holdout 자동 연장**: 채택 시 구간을 `06_Registry/live_track/{ID}/holdout_interval.json` 등록 → monitoring이 trailing 실측(페이퍼/실계좌 NAV)을 월간 동일 구간 대조, 하단 침범 시 Telegram alert (자동 퇴출 아님 — 도훈 수동, §4 정합). 1호: STR_1715_AR_on_M4_R05 [0.39, 3.16] 등록(2026-06-10).
- **ADVISORY (warn only)**: rank_ic / icir / harvey_t_stat(rank-IC) / subperiod_stability. long-only 실현 alpha와 어긋나 거짓통과·거짓탈락 유발(16후보 calibration 실증: rank_ic≥0.04가 FLOW 거짓탈락 + NN/TECH 거짓통과, PORT_t는 FLOW 1건만 정확 통과).
- judge Gate C = portfolio-alpha t ≥ 2.95 AND net_IR > 0.2. **Grade 산정 권위 = `02_Infrastructure/contracts/essence_score.R`** (hurdle_gate 18-component은 proxy 진단용 강등).
- **게이트 2계층 (2026-06-10 도훈 mandate P2 — 계층 분리이지 완화 아님)**:
  - **Screening tier (탐색 게이트)**: `hurdle_gate.R` `verdict$screening` — 알파 *신호력*만 평가(`screen_pass` = no-PIT ∧ [SR≥0.7∧CAGR≥12% 또는 score≥40∧SR≥0.5]). MDD·turnover 등 *구조* 사유로 grade C/F여도 신호가 실재하면 `screen_route`(OVERLAY_CANDIDATE / FR_RCMA / DPL_FEATURE)로 후속 소비 경로 라우팅. 근거: alpha-search 탈락 66/66이 MDD>45% 단일 사유(β≈0.8 맨몸 채점 — overlay가 시스템 입증 MDD 레버인데 모듈 단계에서 선기각하는 구조 모순). **PIT 위반만 계층 무관 절대 기각.**
  - **Graduation/자본 tier (불변)**: 위 HARD 3종(PORT_t 2.95·oos_retention 0.7·calmar 0.64) + §4 book-marginal — screening pass는 이 계층에 어떤 면제도 주지 않음. screening은 "버릴 후보"와 "다른 방식으로 쓸 후보"를 구분하는 라벨일 뿐.

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
- 2026-06-10 (도훈 mandate C1~C3): §3 calibration 3건 반영 — **C1** oos_retention v2(3분할 중앙값 + band [0.5,0.7) 보강증거 2/3 escalation + overfit/decay 사유분리, `essence_score.R` 기본 v2) / **C2** RCMA 희소국면 경로(`regime_module_admission.R` rare_mode — n≥6·t≥1.5 OR stress-pool t≥2, ⑤ strict. **기본 OFF**: run_wf_ensemble A/B 비악화 확인 후 활성, 도훈 confirm) / **C3** holdout 사전등록 예측구간 falsification + 소모 규칙 + 라이브 연장(`holdout_falsification.R` 신규, live_track 1호 등록). 기능검증: C1 6케이스·C2 합성 A/B·C3 book 실측 전부 PASS.
- 2026-06-10 (도훈 mandate P2): §3 게이트 2계층 신설 — Screening tier(`hurdle_gate.R verdict$screening`, 신호력 라벨 + screen_route 라우팅) / Graduation·자본 tier(HARD 3종 불변). 탈락 66/66 MDD 단일사유 전멸 구조 해소. PIT만 계층 무관 절대.
- 2026-06-10 (도훈 mandate): §3 DSR 적용경계 정정 — "n_trials>1 = sweep" 휴리스틱 폐기, **selection operator 기준**(sweep = 열거집합 argmax/threshold-pick / chain = 가설주도 순차개선 → 게이트 면제 + 진단산출만). chain 자격요건 ①진단사유 기록 ②IS-only 변형선택 ③holdout 1회. 구현: `essence_score.R` selection_type 파라미터 + `discovery_graduation_gate.sh` HARD 2 sweep-한정(비-sweep advisory 강등).
- 2026-05-31 (도훈 mandate): §3 게이트 재설계. DSR≥0.5 "무조건 HARD" 폐기 → **다중검정 스타일(n_trials>1)에서만 HARD**(DSR은 multiple-testing 개념, 1논문/1알파엔 부적용·PORT_t 2.95와 중복). 단일전략 과적합 게이트 = **oos_retention≥0.7**(DSR 대체) + 위험조정 게이트 **calmar≥0.64**(=16%/25%). Grade 권위 = `essence_score.R`(hurdle_gate 18-component proxy 강등). Dual-Mode SOT §3.5 정합.
- 2026-05-29 v8.x: 신규. WS1 real-computation + WS2 graduation severity 재설계 + WS3 book-marginal admission. E2E(FLOW forge 2.35) 입증.
