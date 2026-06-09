# FR_002 설계 스펙 — Exposure-Gating 운용체계 (가설서 + 게이트 계획)

| 항목 | 값 |
|---|---|
| **FR id** | FR_002 |
| **모드** | factor-rotation Track2 (allocation) — Track1 산출물(국면신호·forecaster) frozen 소비 |
| **상태** | **DRAFT — 사전등록(pre-registration). 도훈 confirm 후 design freeze → 실행** |
| **작성** | 2026-06-09, Q (Q-Lead 직접 작성 — 서브에이전트 위임 없음) |
| **선행** | FR_001 (Grade C, `06_Registry/factor_rotation_registry.json`) — 본 스펙은 FR_001 부검에서 출발 |
| **WT-id** | 미사용 (FR 트랙은 WorkTask lifecycle 밖, `.claude/rules/factor-rotation.md` §5) |
| **준거 헌법** | `.claude/rules/{factor-rotation,measurement-graduation,backtest-contract,pit,axioms}.md` + `.claude/skills/factor-rotation/SKILL.md` §8~10 |

---

## 0. 한 줄 요약

> **국면 정보를 "무엇을 살까"(selection — FR_001에서 실측 기각)가 아니라 "얼마나 살까"(exposure — STR_1715 AR overlay로 실측 검증)에 사용한다.** 정적 멀티팩터 코어 위에 AR 기반 β 다이얼 + 방어 게이팅을 직렬로 얹고, 각 층의 기여를 ablation으로 분리 측정한다.

---

## 1. 배경 — 왜 FR_002인가 (FR_001 부검 + 실증 교차점)

### 1.1 FR_001 기각 사실 (실측)

FR_001 = 74모듈 broad pool에 대해 국면조건부 IR-shrink dispatch(`compute_regime_module_weights`)로 매월 모듈을 **선택 로테이션**. 결과 (`04_Research/factor_rotation/output/FR_001_result.json`):

| 지표 | 값 | 게이트 | 판정 |
|---|---|---|---|
| net Sharpe | 0.887 | 보고 | — |
| PORT_t (NW lag-3) | 1.864 | ≥ 2.95 | FAIL |
| **OOS retention** | **−0.072** | ≥ 0.7 | **FAIL (부호 반전)** |
| DSR (n_trials=79) | 0.427 | ≥ 0.5 | FAIL |
| Calmar | 0.393 | ≥ 0.64 | FAIL |
| IS active Sharpe / OOS active Sharpe | 1.006 / −0.073 | — | IS에서만 작동 |
| EW baseline SR | 0.798 | — | edge +0.089 (IS 포함 전기간, OOS 미분리) |

**부검 — OOS 붕괴의 3원인**:
1. **국면조건부 모듈 *순위*의 비지속성**: `regime_study_decisive.json` — demeaned rank persistence ρ ≈ 0.08~0.30, head-to-head Rotate_net(1.051/0.98) < Static_net(1.096/1.071) < EW_net(1.115), **verdict = `STATIC_SELECTION_ONLY` ("모듈품질은 지속되나 레짐타이밍 알파 부재")**.
2. **RISK_OFF specialist 공백**: RCMA admitted 23모듈 중 RISK_OFF-admitted **0건** (`06_Registry/module_regime_admission.json` — 전 모듈 c3_oos 부호지속 실패, 국면 중앙값 0.7개월로 희소) → 해당 국면에서 broad-pool fallback → 효율 급락.
3. **74모듈 풀의 약한 prior**: n_trials 79 부담 + 국면×모듈 cell 추정 잡음.

### 1.2 검증된 유일한 타이밍 성공 = STR_1715 AR overlay (exposure 축)

현 book 단독 sleeve STR_1715의 AR overlay (`stage_artifacts/WT_WT-S20260504_007/`, audit 10/10 PASS, L-242):

| 지표 | S0 (overlay 없음) | S1 (AR overlay) | Δ |
|---|---|---|---|
| Sharpe | 1.6399 | 1.7758 | **+0.136** |
| MDD | −30.33% | −29.53% | +0.80pp |
| CAGR | 40.79% | 39.34% | −1.45pp (현금 희석) |
| 위기 alpha | — | GFC **+22.13pp** / COVID +4.25pp / 2022 +2.42pp | 위기 집중 |

메커니즘: AR(Absorption Ratio, Kritzman-Li-Page-Rigobon 2011 FAJ; K=5 고유값, 252일 윈도우, t-1 strict) threshold-step → β ∈ [1.0 / 0.7 / 0.4], 잔여 현금(수익 0) 직렬 (`r = β·r_module + (1−β)·0`).

### 1.3 국면 *정보*는 살아있다 — 죽은 건 selection 채널

- 국면 **예측**: forecaster hit 74.1% vs persistence baseline 69.3%, Brier 0.3994 vs 0.5604, beats_baseline=TRUE (`output/regime_forecast.json`, n_eval 378, walk-forward PIT).
- 국면별 모듈 성과 **판별**: KTRI IR spread 1.024 / VEA 0.701 / MRS 0.515, discriminative=TRUE (`output/regime_discrimination.json`).
- 학술 정합: exposure 타이밍(Moreira & Muir 2017 JF volatility-managed)은 robust, selection 타이밍(Asness et al. 2017 "deceptively difficult")은 취약. 팩터 모멘텀(Gupta & Kelly 2019; Ehsani & Linnainmaa 2022 JF)은 robust하나 KR long-only는 short-leg 의존(AX-004/005/007)으로 transfer 제한 → 모듈 NAV 레벨 + 밴드 tilt로만.

**∴ FR_002 = 국면 정보의 사용처를 selection 채널에서 exposure 채널로 이동.**

---

## 2. 가설 (사전 등록 — RCMA 기준⑤ 경제논리 포함)

| ID | 가설 | 경제논리 (1줄) | 우선순위 |
|---|---|---|---|
| **H1** | 정적 멀티팩터 코어에 AR 기반 β 다이얼(L1)을 얹으면, 코어 단독 대비 **OOS에서 MDD·Calmar 개선 + net SR 비열화**(OOS retention ≥ 0.7 유지) | 시스템 동조화(AR↑) 구간은 분산 소멸 + fat-tail 구간 — 노출 축소가 기대손실을 비대칭적으로 절감 (Kritzman 2011, Moreira-Muir 2017, 1715 실증 GFC +22pp) | **PRIMARY** |
| **H2** | CRISIS/RISK_OFF *예측* 시 코어→사전고정 방어 바스켓으로의 **밴드 제한 게이팅**(L2)이 L1 대비 추가 OOS edge | 방어형 모듈은 위기 국면 조건부로만 가치(AX-001) — '최적 모듈 선택'이 아닌 '사전 고정 바스켓으로의 2-state 전환'은 순위 비지속성(§1.1-1)에 노출되지 않음 | SECONDARY |
| **H3** | 코어 내 12-1 모듈 NAV 모멘텀 ±밴드 tilt(L3)가 정적 가중 대비 추가 OOS edge | 팩터(모듈) 수익률 1~12개월 양(+)의 자기상관 (Gupta-Kelly 2019, Ehsani-Linnainmaa 2022) — 모듈 NAV는 이미 long-only·비용 통과한 시계열이라 transfer 손실 없음 | TERTIARY — 증분 없으면 폐기 |

**비가설 (명시적 제외)**: 국면별 최적 모듈 선택 로테이션 — FR_001 + decisive study로 기각 완료. 재시도하지 않음.

---

## 3. 설계 — 4층 구조 + ablation arms

### 3.0 Ablation 프로토콜 (사전 등록)

각 층의 기여를 분리 측정. **층별 채택 규칙을 사전 고정**해 사후 cherry-pick을 차단:

```
A0 = L0 정적 코어 단독                          ← primary baseline
A1 = A0 + L1 노출 다이얼                        ← H1 검정
A2 = A1 + L2 방어 게이팅                        ← H2 검정
A3 = A2 + L3 모멘텀 tilt                        ← H3 검정
```

**층 채택 규칙**: 층 k는 직전 arm 대비 **OOS-구간** (i) Calmar 개선 AND (ii) net SR 비열화(ΔSR ≥ −0.05) 둘 다 충족 시에만 채택. 미충족 층은 제거하고 마지막 채택 arm이 FR_002 최종형. 이 규칙 자체가 사전등록이므로 선택 과정은 다중검정에 포함하되 사후 재량은 없음 (§7 n_trials 회계).

### 3.1 L0 — 정적 멀티팩터 코어 (로테이션하지 않음)

decisive study 결론("레버는 정적선택+직교화") 그대로 채택.

- **모듈 풀**: RCMA admitted union (walk-forward `compute_rcma(asof)` — 진단 JSON이 아닌 함수 호출이 권위, `02_Infrastructure/portfolio/regime_module_admission.R`).
- **선정 규칙 (walk-forward, IS-only, 사전등록)**: 각 리핏 시점(RCMA_REFIT_MONTHS=12 정합)에 ① IS overall IR 상위 정렬 → ② pairwise **active-return** 상관 < 0.7 제약 하에 greedy 선택 → ③ k개 확정. k ∈ {3, 4, 5} (사전등록 sweep — §7).
- **코어 내 가중**: `compute_regime_module_weights`의 **국면 무조건 버전** — risk-parity 앵커만 사용 (regime_ir 입력에 overall IR, `.FR_HP` 고정: λ_rp=λ_ir=0.5, τ=0.6, k0=36, w_cap=0.25, **하이퍼 재튜닝 금지**).
- **참고 천장 (정직)**: decisive study에서 동급 메커니즘의 net SR ≈ 1.07~1.12. 코어 단독으로는 book 기여 불가 — 코어는 L1/L2의 모재(母材)다.

### 3.2 L1 — 노출 다이얼 (H1, exposure timing)

**1715 AR overlay의 FR-레벨 일반화. 검증된 파라미터를 재사용하고 재튜닝하지 않는다.**

- **신호 (primary)**: AR(K=5, W=252, 유니버스 K200∪KQ150, t-1 strict). threshold = **expanding percentile q70/q90** (PIT C1 — §4.2 검증 항목). β 매핑 (1715 그대로, 재튜닝 금지):
  ```
  β_t = 1.0  if AR_{t-1} < q70_expanding
      = 0.7  if q70 ≤ AR_{t-1} < q90_expanding
      = 0.4  if AR_{t-1} ≥ q90_expanding
  ```
- **신호 (secondary, 사전등록 variant 1건)**: AR + forecaster 보정 — forecaster 예측이 CRISIS일 때 β 한 단계 하향 (1.0→0.7, 0.7→0.4, 0.4 유지). forecaster는 **beats_baseline=TRUE인 현 버전(2026-06-05) frozen** — 사용 조건은 기존 채택 조건(`regime_forecast.json` note) 그대로.
- **적용**: `r_{A1,t} = β_t · r_{A0,t} + (1−β_t) · 0` (현금 수익 0 보수 처리, 1715 컨벤션). 월간, t-1 lag.
- **Σw=1 정합**: w_equity = β_t·w_core (합=β_t), w_cash = 1−β_t → 총합 1, long-only, w∈[0,0.20] book 레벨 충족 (코어 모듈 cap 0.25는 FR 내부 모듈 가중이며 종목 가중 아님 — 종목 레벨 [0,0.20]/max25는 각 모듈이 frozen 상태로 이미 충족).

### 3.3 L2 — 방어 게이팅 (H2, selection이 아닌 게이팅)

**'어느 모듈이 최적인가'를 고르지 않는다.** 사전 고정 바스켓으로의 밴드 전환만.

- **방어 바스켓**: 각 리핏 시점에 walk-forward RCMA의 **CRISIS-admitted cell** (기준 ①~④ 전부: regime_IR ≥ 0.5 ∧ n ≥ 12m ∧ IS·OOS 부호지속 ∧ |t| ≥ 2) 중 IR 상위 3개, **바스켓 내 EW** (최적화 없음). 후보군 참고치(진단 asof 2026-06-01, 성과 매트릭스 기준 — admitted 여부는 실행 시 walk-forward 재산정): STR_1615(CRISIS IR 2.111), STR_1622_M1(1.919), STR_1570(1.733) 등.
- **트리거**: forecaster 예측 ∈ {CRISIS, RISK_OFF} **또는** MSM_Crisis_Prob ≥ 0.9 short-circuit (`regime_signal.R` classify 정합). t-1 lag.
- **전환 폭**: equity 부분의 **δ=30% 고정** (사전등록, sweep 없음)을 코어→방어 바스켓으로 이동. 전량 스위칭 금지.
- **CRISIS-admitted 부재 시**: L2 비활성 (broad-pool fallback **금지** — FR_001 실패 원인 §1.1-2 재발 방지).

### 3.4 L3 — 모듈 모멘텀 slow tilt (H3, 조건부)

- 코어 모듈의 12-1 NAV 모멘텀 z-score → 정적 가중 대비 **±20% 밴드** 내 tilt. 월간. 윈도우·밴드 고정 (sweep 없음).
- §3.0 채택 규칙 미충족 시 폐기 + negative 결과도 L-code 적립.

### 3.5 합성 수익률 (최종형 예시 — A2 채택 가정)

```
r_FR002,t = β_t · [ (1−g_t)·r_core,t + g_t·r_def,t ] + (1−β_t)·0
  β_t  ∈ {0.4, 0.7, 1.0}   (L1, AR_{t-1})
  g_t  ∈ {0, 0.30}          (L2, forecaster_{t-1}/MSM_{t-1})
  r_core = Σ w_i·r_i (정적, 리핏 연 1회), r_def = EW(방어 바스켓)
```

합성은 자체합성 금지 원칙에 따라 `Return.portfolio()` 경유 (가중 행렬 → PerformanceAnalytics, `.claude/rules/python-policy.md` §4 / `answer-principles.md` 정합).

---

## 4. PIT · frozen 규율

| # | 규율 | 구체 |
|---|---|---|
| 4.1 | **모든 신호 t-1 lag** | AR_{t-1}, forecaster_{t-1}, MSM_{t-1}, 국면 Category_{t-1} (C5) |
| 4.2 | **AR threshold C1 검증 (HARD 선행작업)** | 1715 diagnostics의 q70=0.4172/q90=0.4502가 expanding인지 full-sample인지 **실행 전 검증 의무**. full-sample이면 FR_002는 expanding percentile로 재구현하고 1715 parity 차이를 정직 보고 (L-242 audit 10/10 PASS였으나 본 스펙은 독립 재검증을 요구) |
| 4.3 | **모듈 frozen** | 재백테·시그널 수정 금지 (rule §5). 소비만 |
| 4.4 | **classifier/forecaster frozen** | unified_regime_signal_daily Category(2026-06-05 버전) + regime_forecaster(2026-06-05) 고정. 국면 정의 후행 재튜닝 금지 |
| 4.5 | **가중 IS-only** | 코어 선정·RCMA·dispatcher 추정 전부 expanding IS, 리핏 후 forward 적용 (`run_wf_ensemble.R` 기존 구조) |
| 4.6 | **Known-case parity (게이트 진입 전 필수)** | L1 구현을 STR_1715 M4 수익률에 적용 → `posthoc_overlay_result.json` S1 (SR 1.7758, MDD −29.53%) 재현, 허용오차 \|ΔSR\| < 0.02. 불일치 시 하니스 결함 — 게이트 진입 금지 |
| 4.7 | **하이퍼 동결** | β 레벨 [0.4,0.7,1.0] / K=5 / W=252 / `.FR_HP` / δ=0.30 / 모멘텀 12-1·±20% — 전부 기존 검증값 또는 단일 사전등록값. **튜닝 sweep 자체를 두지 않음** (n_trials 최소화 전략) |

---

## 5. 측정 계획

- **하니스**: `run_wf_ensemble.R` 골격 재사용 — MIN_IS_MONTHS=60, MIN_MODULES=3, RCMA_REFIT_MONTHS=12, MIN_BREADTH_OOS=10, OOS 시작 = breadth≥10 첫 달(200203) 컨벤션 유지.
- **측정 체인 (실측-only)**: 모듈 NAV 가중합(Return.portfolio) → 월간 → `build_bt_result`(metric_type=**backtested**) → `audit_bt_result`(11 checks) → `essence_score(bt, n_trials_cumulative=§7)` → `register_fr_result(fr)` (`02_Infrastructure/contracts/factor_rotation_registry.R` — metric_type≠backtested BLOCK).
- **베이스라인 3종**: ① A0 (primary — 층별 기여 분리) ② EW 전모듈 (FR_001 기록 0.798) ③ FR_001 (0.887, OOS ret −0.072) — FR_002의 존재 이유 입증용.
- **보고**: 등급 무관 전 arm 결과 + 2차트(Equity vs BM, 연간수익 vs BM) 텔레그램 `tg_agent_brief()` (실행 세션에서).

---

## 6. 게이트 계획 (사전 등록 — 순서 고정, SKILL §8~9 정합)

### 6.1 게이트 시퀀스

| 순서 | 게이트 | 합격선 | Severity | 판정 데이터 |
|---|---|---|---|---|
| G0 | Known-case parity (§4.6) + AR threshold PIT (§4.2) | 재현 \|ΔSR\|<0.02 / expanding 확인 | **HARD (선행)** | 1715 M4 + posthoc_overlay_result |
| G1 | **OOS retention** | ≥ 0.7 | **HARD** | active Sharpe OOS/IS (essence_score 표준 65/35 split) |
| G2 | **DSR** | ≥ 0.5 | **HARD** (n_trials>1 — FR은 항상 sweep) | §7 누적 n_trials 입력 |
| G3 | **Placebo 국면셔플** (신규 구현 — §6.2) | p < 0.05 | **HARD** | (SR_A1−SR_A0)_OOS vs 셔플 분포 |
| G4 | **Holdout** | 봉인 구간 부호 유지 + Calmar ≥ 0.5 | **HARD** | 최근 18~24월(≈2024-07~2026-06) — design freeze 후 **1회만** 개봉 |
| G5 | edge_vs_EW | OOS edge > 0 | HARD | vs EW 전모듈 OOS 구간 |
| G6 | essence 등급 | PORT_t 2.95 / Calmar 0.64 / SR 0.8 / CAGR 16% (Grade A 기준) | 등급 산정 | `essence_score.R` |
| G7 | Production constraints | long-only / Σw=1 / TO ≤ 11.0/yr / 15bps / LIQ 2e8 | HARD | bt_result audit |

G1~G5 중 하나라도 FAIL → 해당 arm 탈락. 전 arm 탈락 시 §6.4 킬 기준 발동.

### 6.2 Placebo 검정 스펙 (FR_001 미구현 — 본 스펙에서 신규 정의)

- **귀무가설**: L1/L2의 OOS edge는 국면 신호의 정보가 아니라 우연.
- **방법**: 월간 신호 시계열(AR 단계열·forecaster 예측열)을 **국면 지속구조 보존 circular block shuffle** (블록 길이 = 실측 평균 국면 지속기간, 500 permutations) → 각 셔플에 동일 다이얼 적용 → edge\* = (SR_shuffled_arm − SR_A0)_OOS 분포 산출.
- **p-value**: p = P(edge\* ≥ edge_actual). p < 0.05 합격.
- **구현 위치**: `run_wf_ensemble.R` 확장 또는 `04_Research/factor_rotation/fr002_placebo.R` 신규 (PerformanceAnalytics 표준함수만).

### 6.3 성공 기준 (3단계, 사전 등록)

| 단계 | 기준 | 의미 |
|---|---|---|
| **Minimum** | A1이 A0 대비 OOS MDD·Calmar 개선 + OOS retention ≥ 0.7 + placebo p<0.05 | **H1 입증** — exposure 채널 작동. SR 증분이 작아도(1715 전례 +0.14) 위기 alpha 집중이면 성공 |
| **Target** | 최종형 net SR ≥ 1.2 + Calmar ≥ 0.64 + Grade B (PORT_t ≥ 2.0, net_IR > 0.2) + book-marginal ΔIR ≥ 0.05 (vs incumbent 1.5754) **진단 통과** | book 후보 — 도훈 수동 confirm 안건 상정 |
| **Stretch** | Grade A 전 게이트 | 단독 졸업 |

**정직 표기 (AX-000)**: SR 2.5는 FR_002 단독 목표가 **아니다**. FR_002는 book SR 1.78 → 2.0 단계 마일스톤의 부품이며, SKILL §1의 "단일 모듈 천장 ~2.0, 2.5는 앙상블 레벨 발현" 전제 그대로다. 미달 시 수치 그대로 보고.

### 6.4 킬 기준 (사전 등록 — 반증 계획)

| 조건 | 판정 | 후속 |
|---|---|---|
| A1이 A0 대비 OOS에서 MDD·SR 둘 다 비개선 | **H1 기각** | exposure-gating 접근 동결. negative L-code(mode=factor_rotation) + AX 후보 ledger("KR 모듈 앙상블 레벨 AR exposure 타이밍 무효 N=1") |
| placebo p ≥ 0.05 (전 arm) | 국면 신호 무가치 (FR 레벨) | FR 트랙 자원 → Lane1/2 모듈 생산으로 재배분 권고 |
| G4 holdout 부호 반전 | 과적합 판정 | FR_002 폐기, 결과 무효 표기 |

킬 발동 시에도 결과는 `register_fr_result`로 정직 등재 (Grade F 포함).

---

## 7. n_trials 회계 (사전 등록)

DSR 입력. `measurement-graduation.md` §3 "다중검정 스타일 n_trials 누적 상향계상" 정합:

```
n_trials_cumulative = 79 (FR_001 이월: 74모듈 + 5)
                    + n_configs(FR_002)            ← 사전등록 상한: k∈{3,4,5} × signal∈{AR, AR+fc} × arms{A0..A3} = 24
                    + 5 (placebo 설계·threshold 검증 버퍼)
                    ≤ 108
```

- 실제 실행 config 수가 24 미만이면 실측 수로 계상 (상한만 사전 고정).
- **금지**: 사전등록 grid 밖 config 추가 실행. 필요 시 본 스펙 amend(도훈 confirm) 후 n_trials 재누적.

---

## 8. 거버넌스

| 항목 | 규칙 |
|---|---|
| **governor 정지** | FR_002가 전 게이트 통과해도 `book_state.json` 자동 쓰기 **금지**. ΔIR ≥ 0.05 진단 artifact까지만 — 실편입 = Q-Lead + 도훈 수동 confirm (`measurement-graduation.md` §4) |
| dispatcher | `book_optimize` 래퍼 — 직접개조 금지 |
| 등재 | `register_fr_result()` (실측-only BLOCK 게이트 경유) + 등급 무관 등재 |
| L-code | `mode=factor_rotation` 태깅, 성공/의미있는 실패 모두 적립 (`stage_artifacts/l_code/factor_rotation/`) |
| 텔레그램 | `tg_agent_brief()` 단일 진입점 |
| Production constraints | long-only / Σw=1 / w∈[0,0.20](종목) / max25(종목, 모듈 합산) / 15bps / LIQ 2e8 / TO≤11.0 |

---

## 9. 실행 계획 (P0~P5)

| Phase | 내용 | 산출물 | 게이트 |
|---|---|---|---|
| **P0** | AR threshold PIT 검증(§4.2) + L1 하니스 구현 + known-case parity(§4.6) | `fr002_l1_dial.R` + parity 리포트 | **G0 — FAIL 시 전면 중단** |
| **P1** | A0 코어 (walk-forward 선정 k=3/4/5) | A0 bt_result × 3 | baseline 확정 |
| **P2** | A1 (AR primary / AR+fc secondary) | A1 bt_result × 6 | H1 판정 (G1·G3 예비) |
| **P3** | A2 방어 게이팅 (CRISIS-admitted walk-forward) | A2 bt_result | H2 판정 + 층 채택 규칙 적용 |
| **P4** | A3 모멘텀 tilt (조건부) | A3 bt_result | H3 판정 |
| **P5** | placebo 500회(§6.2) → G4 holdout 개봉(1회) → essence_score → register_fr_result → ΔIR 진단 → 텔레그램 보고 + L-code | FR_002 등재 + 진단 artifact | G1~G7 최종 |

실행 환경: Windows-native `Rscript.exe` + `CLAUDE_PROJECT_DIR` (SKILL §12). 본 스펙 confirm 후 별도 실행 세션(`/factor-rotation allocation`)에서 수행.

---

## 10. 리스크 · 한계 (정직 보고)

1. **CAGR 희석**: β<1 + 현금 0% 수익 가정은 CAGR을 깎는다 (1715 실증 −1.45pp). 코어 CAGR이 1715(39%) 대비 낮으므로(모듈 풀 SR ~1.1 수준) **Grade A의 CAGR ≥ 16% 게이트가 binding일 수 있음**. L2(현금 대신 방어 모듈)가 부분 완화 — 그래도 미달이면 수치 그대로 보고.
2. **RISK_OFF specialist 공백** (§1.1-2): L2가 CRISIS-admitted에 의존하는데 walk-forward 초기 구간엔 admitted가 없을 수 있음 → 해당 구간 L2 비활성 (fallback 금지). 근본 해결은 Lane1/2 발주 (§11).
3. **국면 오분류 비용**: forecaster 오경보(hit 74% ≠ 100%)는 β 하향→상승장 미참여 비용. minimum success 기준이 "SR 비열화 + MDD 개선"인 이유.
4. **AR threshold PIT 불확실성**: §4.2 — 검증 전까지 1715 parity 수치는 잠정.
5. **희소국면 통계력**: CRISIS/RISK_OFF 표본 부족(중앙값 0.7개월)으로 H2의 검정력 자체가 낮음 — H2 미입증과 H2 기각을 구분해 보고.
6. **placebo 신규 구현 리스크**: 블록 길이 선택이 p-value에 영향 — 평균 국면 지속기간 기준 1개 사전등록 (민감도는 부록 보고, 판정엔 미사용).

## 11. 의존성 · 후속 발주 (FR_002 범위 밖 — 별도 모드)

- **공격형/방어형 specialist 모듈 생산 발주** (Lane2 alpha-search 우선): ① RISK_ON specialist — KQ150 성장·모멘텀 long-only (RCMA cell 기준 admit 목표, overall 등급 무관) ② RISK_OFF/CRISIS specialist — 저β·quality·현금혼합. FR_003에서 풀 확장 소비.
- **SJM jump-penalty PoC** (Track1, 문헌 리뷰 권고 #2): 국면 과전환 억제 — L1/L2 회전비용 직접 절감. FR_002 frozen 원칙상 본 건에 미반영, FR_003 후보.
- QEPM 신규 산출물은 `register_module()` 경유 시 `run_factor_rotation.R` 신선도 체크로 자동 편입 (SKILL §4).

## 12. 참조

- 계약: `02_Infrastructure/contracts/{register_module,factor_rotation_registry,essence_score,backtest_result_contract}.R`
- 엔진: `02_Infrastructure/portfolio/{module_dispatcher,regime_module_admission}.R` · `02_Infrastructure/regime/{regime_signal,regime_forecaster,apply_regime_overlay}.R` · `04_Research/factor_rotation/run_wf_ensemble.R`
- 실증: `04_Research/factor_rotation/output/{FR_001_result,regime_study_decisive,regime_forecast,regime_discrimination}.json` · `stage_artifacts/WT_WT-S20260504_007/` (1715 AR overlay)
- 문헌: Kritzman-Li-Page-Rigobon 2011 FAJ · Moreira-Muir 2017 JF · Asness et al. 2017 JPM · Gupta-Kelly 2019 JPM · Ehsani-Linnainmaa 2022 JF · Haddad-Kozak-Santosh 2020 RFS · Shu-Mulvey 2024 (arXiv 2402.05272 / 2410.14841) — `regime_model_literature_review.md`
- 헌법: `.claude/rules/{factor-rotation,measurement-graduation,backtest-contract,pit,axioms,answer-principles}.md`

## Change log

- 2026-06-09: 초안 작성 (Q). FR_001 부검 기반 selection→exposure 전환 설계. 사전등록: 가설 H1~H3 / ablation A0~A3 / 게이트 G0~G7 / n_trials ≤ 108 / 킬 기준. **도훈 confirm 대기 — confirm 시 design freeze.**
