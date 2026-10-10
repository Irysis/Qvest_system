# MSM 위기확률 C1(전기간 모수) — 연쇄 오염 지도

- **작성**: 2026-10-10 · Q 감사 서브에이전트 (읽기 전용 · 코드·격리 파일·원장 무수정 · git 커밋 없음)
- **근거**: `04_Research/l2_role_rotation/pit_audit.json`(같은 날 작성된 원천 판정) + 이 문서의 소비자 전수 추적 + 라벨 반전 진단(부록 A)
- **pit.md 단계**: 「위반 시 처리」 3단계 **연쇄 오염 파악**. 1·2단계(중단·무효)와 4단계(재실행)는 아래 권고의 결정 사항입니다.

---

## 0. 요약

1. 운영 MSM 위기확률(`.cache/msm_daily_latest.parquet::Crisis_Prob`, `msm_hybrid_latest::Avg_Prob`)은 Hamilton **필터**라 시간축은 인과입니다. 하지만 모수 4개는 1990-01-04~2026-01-16 **전기간 MLE**(`K_Fractal_Master_2026-01-20.xlsx`, Last_Trained 2026-01-18)를 핀으로 씁니다. 따라서 **2026-01-18 이전 날짜의 값은 전부 C1**입니다. 지연(lag)으로는 해소되지 않습니다.
2. 오염은 `unified_regime_signal` 경로로 퍼집니다. MSM은 `Regime_Score`의 Layer1(최대 40/90점)이고, `Category`를 직접 단락합니다(p≥0.9 → CRISIS, p≥0.7 → 최소 CAUTION). 퍼지는 곳은 module_performance 국면별 성과, 2계층 FR·RCMA, **m4 게이트 → BOOK_0001**, pg2 오버레이 15칸, 국면 예측기, 오버레이 스크린 결과입니다.
3. **라이브 소비자 중 등급·BOOK에 닿는 것은 4개**입니다. `build_module_performance.R`(매일), `run_wf_ensemble.R`(2계층 · l2_auto 정지 중이지만 수동 세션은 열려 있음), m4 `factor_engine.R`(BOOK 리밸·월간 예약 트래킹), BOOK 생성기입니다. 나머지는 표시용, 세션용, 또는 레거시입니다.
4. **기존 방어선은 이 위반을 구조적으로 못 봅니다.** `assert_overlay_pit`, lag-1 스트레스, strict-PIT A/B, `regime_label_gate`, C11 epoch 키는 모두 타이밍만 검사합니다. 오버레이 결과 24건이 실제로 `PASS(HARD) · 인플레 0%`를 기록했습니다. 격리 관문(`rf_overlay_admit`)도 MSM을 직접 읽는 생성 arm을 **통과시킵니다**(§4.1 재현).
5. **최소 봉쇄 권고**는 다섯 가지입니다. ① C11과 **분리된** 새 격리 항목 `PITQ-C1-MSM-20261010`을 추가합니다. ② 원장 표식 `pit_c1_msm`을 붙입니다(L1 15칸 + L2 2칸). ③ C11 2단계 재측정(pg2·FR_003·BOOK)을 MSM as-of 수리 때까지 보류해 한 번에 재측정합니다. ④ 결정 항목을 개설합니다. ⑤ 폴백 `msm_daily_refit.R`을 fail-closed로 바꿉니다. 근본 수리는 연말 as-of MLE 재적합 생산자와 국면·m4 원장 재발행(epoch 키에 MSM 추정기 포함)입니다.

> **시점 구분**: 2026-01-18 이후 결정일에 쓰인 MSM 값은 그 시점에 이미 알려진 모수로 계산됐으므로 미래참조가 아닙니다. 해당하는 것은 BOOK 전진 보유(2026-02~), 라이브 표시, regime_current.json입니다. 오염은 그 **이전 이력**을 집계·등급·국면조건부 통계·설계 근거로 쓴 곳에 있습니다.

---

## 1. 원천 사실 (재확인)

| 항목 | 사실 | 근거 |
|---|---|---|
| 주 생산자 | `04_Research/regime_comparison/msm_update.R` → `.cache/msm_daily_latest.parquet`(Date·Price·Vol_Est·Crisis_Prob) · `.cache/msm_hybrid_latest.parquet`(Avg_Prob 월평균) · `outputs/regime/output/MSM_updated_YYYYMMDD.RData` | msm_update.R:283-301 |
| 호출 | `daily_refresh.sh`[4/7] :398-417(예약 `Qvest_DailyRefresh`) · 아침 `morning_steps/self_heal.R`:30-56(stale 시) | |
| 모수 | `02_Infrastructure/ops/msm_param_pin.json` → `05_Production/1.Regime_Def_Model/1-1.MSM/K_Fractal_Master_2026-01-20.xlsx`(m0 1.2869 · σ 0.015454 · b 2.1441 · γ1 0.000253). MSM.R Mode A `estimate_msm_windows`(k̄=10)가 **전기간 디민**(MSM.R:185) 수익으로 적합(NM maxit 1000) | msm_param_pin.json · MSM.R:125-203,546-574 |
| 위기 상태 정의 | `s > σ` — 전기간 σ에 묶임 | msm_update.R C++ `crisis_indices` |
| 오염 크기 | as-of 재추정 대비 결정일 IS(2005-2015) 평균 \|Δ\| 0.117 · 0.5 문턱 반전 12.1% · OOS 0.052 · 6.2% | pit_audit.json |
| 식별 취약 | 같은 자료로 추정한 MLE(σ≈0.0178 · b≈2.75)가 핀보다 음의 우도로 2.8 낫습니다. 즉 핀은 이 절차의 최적점이 아니고, 우도면이 평평합니다. 그래서 추정기 선택만으로 라이브 값도 달라집니다(2026 평균 \|Δ\| 0.099 · 2026-10 월평균 prod 0.943 vs as-of 0.812 → Category CRISIS vs CAUTION). **PIT 문제는 아닙니다** | pit_audit.json PC3 · 부록 A |
| 폴백 | `02_Infrastructure/regime/msm_daily_refit.R`는 `regime_hmm.R` 2-state HMM의 **평활** γ를 쓰고 매 refit마다 전 이력을 덮어씁니다(C1×2). daily_refresh·self_heal에 배선돼 있습니다 | pit_audit.json |
| 폴백 실현 여부 | **성공 0회**(관측 로그 전체)입니다. daily_refresh.log는 msm_update PASS 83 · FAIL 1, 아침 로그는 REFIT PASS 18 · FRESH 37 · FAIL 1이며, 두 FAIL 모두 폴백도 benchmark 부재로 FAIL했습니다. 현 캐시가 msm_update 산출임은 PC2(8.9e-09)로 확인됩니다 | `.cache/scheduler_logs/daily_refresh.log` · `/tmp/qm_morning.log` |
| `msm_signals.parquet` | **파일 없음 · 저장소 참조 0건**(worktree 제외 전수 grep) | — |

---

## 2. 전파 사슬

```
K_Fractal_Master(전기간 MLE, 2026-01-18)
  └─ msm_update.R ─→ msm_daily_latest(Crisis_Prob) · msm_hybrid_latest(Avg_Prob)   [폴백 msm_daily_refit = 평활]
       └─ regime_signal.R  Layer1 = 40·min(1,p/0.8) · Category 단락(p≥0.9 CRISIS / ≥0.7 ≥CAUTION) · Cash_Pct=f(Score, 문턱 45)
            ├─ .cache/unified_regime_signal(.parquet|_daily) ← 06_Registry/regime_published (append-only, epoch = C11 키만)
            │    ├─ build_module_performance.R → 06_Registry/module_performance.json per_regime (65모듈×5국면)
            │    ├─ run_wf_ensemble.R (+RCMA regime_module_admission · regime_label_gate) → FR registry · L2 원장
            │    ├─ regime_forecaster v1~v3 (CrisisP·Category) → .cache/regime_forecast_series* → FR forecast 모드 · RAMP
            │    ├─ overlay_candidate_drain / auto_regime_overlay_ab (uni_cat) + vol/hurst_rate_matched 어댑터 → 오버레이 스크린 결과
            │    └─ regime_current.json · 텔레그램 MRS 브리프 · distilled live_trigger(regime)            [표시·감시]
            └─ m4 factor_engine.R (WT-D20260430_001: Cash_Pct_lag·Regime_Score_lag·MSM_Crisis_Prob_lag)
                 └─ 06_Registry/m4_published (append-only) → weight_str1715
                      ├─ BOOK_0001 게이트 0.70 ⇔ (m4 발화 ∧ AE 발화) — forward_weights_D3_M4gAE.R / 05_Production 2-4
                      ├─ pg2_risk_overlay (L1 B5_31·B4_2x 15칸 — C11로 suspended)
                      ├─ 05_Production STR_1715 2-1 · 2-2 · 2-3(월간 예약 트래킹)
                      └─ AE τ = m4 전기간 발화율 0.12에 맞춤 (ae_regime_backfill.py:79 — 2차 경로)
```

---

## 3. 소비자 지도 — 라이브 vs 레거시

### 3.1 라이브(예약 실행 또는 등급·BOOK·원장에 닿음)

| # | 소비자 | 읽는 것 | 실행 경로 | 산출 → 닿는 곳 | 분류 |
|---|---|---|---|---|---|
| P1 | `04_Research/regime_comparison/msm_update.R` | 핀 모수 + benchmark | `Qvest_DailyRefresh`(daily_refresh [4/7]) · 아침 self_heal | msm_daily/hybrid 캐시 → 전부 | **라이브 생산자(C1 원천)** |
| P2 | `02_Infrastructure/regime/msm_daily_refit.R` | benchmark | P1 실패 시 폴백(daily_refresh:409-416 · self_heal.R:44-51) | 같은 캐시를 평활 이력으로 덮어씀 | **라이브 잠복 폴백(C1×2)** · 실현 0회 |
| P3 | `02_Infrastructure/regime/regime_signal.R` (`load_msm_signal`·`load_msm_daily`·`build_regime_signal_table`) | msm_hybrid(월간) · msm_daily(일간) | daily_refresh [4/7] → 후보 → `regime_append_only.R` · 아침 `fred_regime.R`·self_heal | unified 월간·일간 · regime_current.json · 발행 원장 | **라이브 생산자** |
| C1 | `02_Infrastructure/regime/build_module_performance.R` | unified_daily Category | daily_refresh [8.2](:959) · l2 빌더(rf_l2_lib.R:75) | module_performance.json per_regime → FR·RCMA·2계층 풀 배치 | **라이브(2계층 등급 입력)** |
| C2 | `04_Research/factor_rotation/run_wf_ensemble.R` (+ `regime_module_admission.R` RCMA · `contracts/regime_label_gate.R`) | unified_daily Category(기본 `FR_REGIME_SOURCE=category`) · forecast 모드 시 regime_forecast_series · module_performance | l2_auto 레인(**정지** — `reinforce_auto_config.json` l2_auto.enabled=false, 2026-09-24 C11) · **수동 /strategy-rotation 세션은 열려 있음** | FR registry · L2 원장 · 2계층 등급 → Judge → BOOK | **라이브 가능(레인 정지·수동 개방)** |
| C3 | `qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R` + `02_Infrastructure/regime/m4_append_only.R` | unified 월간 Regime_Score·Cash_Pct·MSM_Crisis_Prob(lag1) | BOOK 리밸 러너 `run_pg2_rebalance_full.sh`(book-rebalance) · 예약 `noLayer4_Monthly_PaperTracking`(월 1회, 다음 11/03 09:00) | m4 패널 · `06_Registry/m4_published` | **라이브(BOOK 경로)** |
| C4 | `02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R` · 05_Production 2-4 생성기 | m4 weight_str1715(+AE) | BOOK 리밸 | BOOK_0001 보유 · 매니페스트 | **라이브 BOOK** (2026-02 이후 결정은 MSM 측면 미래참조 아님) |
| C5 | `02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R` | m4_published + AE | B5 강화 셀 | L1 원장 15칸 | **정지**(overlay_catalog suspended · C11) |
| D1 | `telegram/telegram_notify.R`(MRS 브리프 차트 MSM 층) · `ops/mrs_daily_briefing.sh` · `telegram_commands.R`(/regime) · `boot_lean.sh`·`bootstrap.sh`(신선도) · `axiom/distilled.R`(live_trigger regime) · `morning_steps/freshness_audit.R`·`regime_data_gate.R` | unified·msm 최신값 | 아침 예약 · 온디맨드 | 표시·부활 트리거·신선도 | **라이브 표시/감시**(현재값 — 현재 결정 기준 C1 아님) |

### 3.2 세션·수동 경로(무인 예약 없음 · 결과는 스크린 등급)

| 소비자 | 읽는 것 | 상태 |
|---|---|---|
| `02_Infrastructure/regime/overlay_candidate_drain.R` · `overlay_candidate_ab_lh.R` · `02_Infrastructure/ops/auto_regime_overlay_ab.R` | unified 월간 Category(`uni_cat`, CAT_EXPOSURE 직전월) | improve-drain 스킬(세션)만. `paper_research_dispatch.R` 배터리는 v10 퇴역(morning_run.sh:236), `refresh_screen_queues.R` 마지막 실행은 08-24(kill switch) |
| `02_Infrastructure/methods/adapters/{vol,hurst}_rate_matched_overlay.R` | unified 월간 Category 과거 비율 → 목표 발화율 q | method_registry `VolRateMatched`·`HurstRateMatched` implemented(exposure) · `load_exposure_adapters()` 경유(위 하네스) |
| `02_Infrastructure/regime/regime_forecaster{,_v1tune,_v2,_v3,_v4}.R` | unified CrisisP·Category + regime_daily_v2 | 예약 호출 없음 · 산출 4개는 2026-09-25 11:36 생성(입력은 이후 재빌드) |
| `02_Infrastructure/contracts/regime_label_gate.R` | unified Category(라벨 기준이 unified일 때) | 관문 계약. BOOK 생성기는 `alpha_scores_regime_state`(BM 기반 · MSM 무관)를 씀 |

### 3.3 레거시·진단 전용(예약 없음 · 등급 경로 없음)

- **RAMP(퇴역)**: `02_Infrastructure/ramp/` 16파일. 그중 MSM 캐시를 직접 읽는 파일은 8개(`ramp_wire_canonical`·`run_ramp_{crisis_derisk,recency,regime_bakeoff,regime_multiaxis,regime_strengthen,selfdev_ar}`·`search/build_cache`)입니다. `04_Research/ramp/run_ramp_gate5.R` 포함.
- **v9 퇴역 레인**: `ops/reinforce_ladder.R`(RETIRED 배너) · `ops/alpha_search_queue_run.sh`(RETIRED) · `ops/paper_research_dispatch.R`(morning에서 철거) · `regime/improvement_potential.R`.
- **governor 폐지(v10)**: `portfolio/portfolio_governor.R`(`get_regime_at_date` 동월 라벨) · `portfolio/multi_sleeve_builder.R` · `validation/loo_validator.R`.
- **미등록 훅**: `hooks/covariance_freshness_gate.sh`(regime_current.json · settings.json 13훅에 없음). `hooks/worktask_artifact_validator.sh`(QEPM 동결).
- **연구 스크립트**: `regime/regime_engine_research.R` · `04_Research/factor_rotation/`(regime_study*·fr_regime_search·_diag_*·run_valearn_overlay·regime_jm_* 등) · `04_Research/regime_comparison/`(bcs_*·regime_comparison·derivatives_regime_research 등) · `04_Research/decision_framework/bearish_forecast_v1`·`v2`.
  - **아침 P3 브리프(bearish_forecast_v3 · 613 스크립트)는 MSM·unified 참조 0건**입니다(v1 특성 조립기만 MSM을 "M4 proxy"로 씀).
- **레거시 전략**: `04_Research/strategies/STR_*` 18파일(DD regime 오버레이 등). module_catalog(971)에 **0건**입니다.
- **QEPM 동결**: `qepm/R/regime_scout_wrapper.R` · WT-D20260424_*/0427/0508 등 20파일. 예외는 WT-D20260430_001 m4 엔진(C3, 라이브)입니다.
- **stage_artifacts 일회성 분석** 약 70파일(pg2_hunt 22 · pg2_overlay_gate_composition 5 · live_hygiene 4 · paper_recharge 3(08-09 일회성) · crisis_contrarian · fq* · WT_D202608* 등).
- **2계층 역할 로테이션(진행 중, 타 에이전트)**: `04_Research/l2_role_rotation/mc1_is_selection.R:36`이 운영 MSM·forecast·unified를 이미 **INELIGIBLE**로 묶어 두었습니다. 이 감사는 그 파일을 수정하지 않았습니다.

### 3.4 05_Production (읽기 전용 보고 · 수정 없음)

- `1.Regime_Def_Model/1-1.MSM/MSM.R`: 핀 모수의 출처입니다(Mode A 전기간 적합 → K_Fractal_Master). `MSM_upgrade.R`도 같은 계열입니다.
- `2.Factor_Model` STR_1715 4개 슬롯이 **모두 m4 패널(weight_str1715)을 결정 경로에 씁니다**. MSM은 unified Cash_Pct를 통해 들어옵니다.
  - 2-1 AR(`run_pg2_forward.sh` · `forward_weights_R05_AR.R`)
  - 2-2 FaithTrend
  - 2-3 noLayer4(**예약 작업 `noLayer4_Monthly_PaperTracking`이 월간 실행**)
  - 2-4 M4gAE = **BOOK_0001**
  - 2-x의 β_R05 국면(`alpha_scores regime_state` = cls_thr_q · BM 변동성·수익·낙폭·breadth)은 MSM과 무관합니다.
- `4.Statistical-Technical/4-1.Samsara_Protocol`(`Samsara_MSM.R`·`Step_1_Setting.R`): 자체 MSM(망각계수 가중 적합)입니다. BOOK·예약 경로가 아닙니다.

---

## 4. 무효가 되는 저장 결과 (건수)

라벨 반전 수치는 부록 A의 진단입니다. 운영 MSM을 as-of 원형 패널로 바꾸고 FRED·KTRI·VEA·기타 입력은 고정했습니다. 양성 대조 7/7 통과입니다. **등급 재산정이 아니라 오염 크기의 측정**입니다.

| # | 저장 결과 | 건수 | 오염 경로 | 기존 표식 |
|---|---|---|---|---|
| R1 | **L1 원장** `06_Registry/reinforce_ledger_l1.json` | **15칸**(B 5 · C 10 · B5_31 ×11 + B4_21~24 ×4). A칸 0 · 충실구현 0. 나머지 1,381 시도 / 39 기저 엔진에서 MSM·unified 경로 **0** | pg2_risk_overlay → m4_published weight_str1715 | `pit_c11` consumed만 있음 → **C1 독립 표식 없음** |
| R2 | **L2 원장** `reinforce_ledger_l2.json` | **2칸**(FR_003 base C · cell 1 L2_TSC C) | unified_daily Category · module_performance | `pit_c11`만 |
| R3 | **FR 등재** `06_Registry/factor_rotation_registry.json` | **3/4**(FR_001·FR_003·FR_003_n1, 전부 C)이 unified Category 국면조건부. FR_002(무조건부)의 "국면조건부 변형 열세" 비교도 같은 라벨 | run_wf_ensemble | 없음 |
| R4 | **FR 산출** `04_Research/factor_rotation/output/FR_*_result.json` | **9개** 중 8개 국면조건부(FR_001_fc = forecast 원천 · CrisisP C1) | 위와 같음 | 메모리상 "FR 9건 인용 불가(09-24)" · C1 사유는 미기재 |
| R5 | **module_performance.json** per_regime | **65모듈 × 5국면 = 325 칸**. 매일 재생성되며 `per_regime_pit_c11=avail_annotated`라 C11 소비자에게는 깨끗해 보임. 2005~2026-01 국면 일수 prod→as-of: CRISIS 287→126(−56%) · CAUTION 394→217 · NEUTRAL 693→485 · RISK_OFF 13→40 · RISK_ON 3,805→4,324. 모듈 전기간 등급·역할(PS-bear·CGH36 기반)은 무관 | unified_daily Category | 없음 |
| R6 | `06_Registry/module_regime_admission.json` (RCMA 진단, 2026-06-13) | 1파일(레거시) | unified Category | C11 정규식 |
| R7 | `06_Registry/module_catalog.json` | pg2 모듈 **15개**(이미 fr_eligible=false). 그 밖 971개 중 0 | m4 | C11 contamination |
| R8 | **BOOK_0001** 이력(`06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet` 5,416행 · `d3_gate_history_271m.csv`) | 현 발행 패널 기준 2026-01 이전 AE 가용 217개월 중 게이트 de-risk **14→11개월**(2008-03 · 2009-05 · 2009-06 반전) · m4 weight 14/263행 변경 · m4 발화 38→29. 전진 보유(2026-02~)는 MSM 측면 미래참조 아님 | m4 arm | `PIT-C11-BOOK0001`(C11 미해소 게이트 표기)만 |
| R9 | 05_Production 2-1·2-2·2-3 백테스트 이력 | 슬롯 3개(같은 m4 의존) | m4 | C11 not_in_scope |
| R10 | **발행 원장** `06_Registry/regime_published/`(월간 433 · 일간 9,042행) · `06_Registry/m4_published/`(272행, MSM_Crisis_Prob_lag 내장) | 동결 결정값(Regime_Score·Category·Cash_Pct / weight_str1715)에 C1이 박혀 있음 | — | epoch 키 `c11_avail:2026-09-24.b4:631e4f98`에 MSM 추정기가 **없음** |
| R11 | `.cache/regime_forecast_series{,_v1vix,_v2,_v3}.parquet` | 4파일(441·316·316·285행) | CrisisP·Category 입력 | C11 정규식 `\bregime_forecast` |
| R12 | 오버레이 스크린 | `overlay_candidate_queue.json` 측정 **22** · `06_Registry/overlay_ab_results/` 결과 JSON **24**(STR_AS 21 + LH_D2 3, 전부 uni_cat 시나리오 · `PASS(HARD)`·인플레 0% 기록) · `auto_spawn_queue.json` 판정 **4**("INFERIOR (best uni_cat)") · `book_carrier/h2_regime_overlay_ab.csv`(21행)·`h2_regime_crisis_eval.csv`(2행) | uni_cat · rate-matched q | 없음 |
| R13 | **지식층** | `06_Registry/hypothesis_index.json` **18건**(L-FR 7: FR_002 1·FR_003 계열 6 · L-RAMP-20260619_105903 **PASS·A** · pg2 B5_31 2 · DIST 8) · `distilled_knowledge.json` **19카드**(distilled 8 · proposed 9 · expired 2) · Axiom 승격 **0** · RAMP 등재 1/7(`RAMP_ARMSM_Q_20260619`, B) | 국면 라벨·MSM 직접 | 없음 |
| R14 | 설계 근거 서술 | `regime_signal.R:364-388`("MSM 포화 구간 실제로 위험 p=0.0000, n=271" — 0.8 포화·0.9/0.7 단락의 근거) · 헤더 "Recall 86.5%" | 전기간 모수 표본 내 | 없음 |

**라벨 반전 진단(부록 A · 2026-01-18 이전)**:

- **월간 unified Category**: IS(2005~2015) **22/132** · OOS(2016~2025) **14/120** · 전체(2004~2025) 40/264 반전.
  - 방향은 전부 운영판이 더 "경계" 쪽입니다. CRISIS 12→3개월(7은 CAUTION, 2는 NEUTRAL로) · CAUTION 13→9 · NEUTRAL 29→22.
  - Cash_Pct는 14개월 값이 바뀌고, 그중 0↔양수 9개월(전부 IS)입니다. 이 9개월이 m4 baseline 발화입니다.
- **일간 Category**: 1,116/5,441일(20.5%) 반전. 연도별로 2008년 54% · 2009년 72%입니다.
- **FR·RCMA 홀딩월 결정 라벨**(직전월 말일): **51/253**(20%).

---

## 5. 최소 봉쇄 권고 (권고만 — 이 감사는 아무 파일도 고치지 않았습니다)

### 5.1 왜 새 격리 항목인가 (현 격리의 틈 3개)

1. **직접 경로가 열려 있습니다.** 현 효력 정규식 45개로 생성 arm 등재 관문(`rf_overlay_admit` → `pitq_source_hits`)을 재현했습니다(Python, 같은 정규식·대소문자 무시).
   - **통과(ADMIT)**: `msm_daily_latest` · `msm_hybrid_latest` · `Crisis_Prob` · `MSM_Crisis_Prob` · `source(msm_update.R)` · `msm_daily_refit` · `MSM_updated_*.RData` · `K_Fractal_Master` 8개 변형 전부.
   - **차단(BLOCK)**: unified·m4·forecast 경로만.
   - 아직 그런 arm은 없습니다(`overlay_arm_ledger.jsonl` 33건 중 0). 다만 B5/B1 LLM 설계 레인은 같은 관문만 거칩니다.
2. **C11 해제 시 함께 풀립니다.** unified·m4·module_performance·forecast·RCMA를 막는 정규식은 전부 `PITQ-C11-20260924` 소속입니다. 그런데 C11 수리는 결정상 resolved이고(unified 09-25 가용일 재빌드), 해제는 다음 수순입니다. 해제하는 순간 **MSM-C1 경로가 조용히 다시 열립니다.**
3. **격리 목록을 읽는 곳이 L1 입구뿐입니다.** 판독기는 `rf_factor_arms`·`rf_overlay_admit`·`rf_lineage_flags`·`rf_sleeve`·`remeasure_from_holdings`만 읽습니다. `build_module_performance.R`·`run_wf_ensemble.R`·m4 엔진·drain 하네스는 격리 목록을 읽지 않습니다. 이들은 레인 정지와 결정 항목으로만 막을 수 있습니다.

### 5.2 `06_Registry/pit_quarantine.json`에 추가할 항목 (초안 — 기존 스키마·판독기 규약 그대로)

판독기(`pit_quarantine.R`)는 `status=="active"` 항목의 `factors[].id`·`sources[].regex`만 효력으로 봅니다. `flag`는 `rf_lineage_flags.R:274-276`과 `remeasure_from_holdings.R:393`이 **A 자격·rebase 차단 플래그**로도 씁니다. fail_policy는 기존과 같습니다(파일 부재 = 격리 0 · 파손 = stop).

```jsonc
{
  "id": "PITQ-C1-MSM-20261010",
  "code": "C1", "flag": "pit_c1_msm", "reason": "pit_invalid:C1", "status": "active",
  "opened_at": "<등재 시각>", "opened_by": "<도훈 결정 후 기록 주체>",
  "decision_ref": "06_Registry/decision_register.json#PIT-C1-MSM-PARAMS (개설 필요 · default_until_decided = 봉쇄)",
  "judgment": "04_Research/l2_role_rotation/pit_audit.json · 04_Research/01_reports/msm_c1_chain_audit_20261010/README.md",
  "judgment_summary": "운영 MSM 모수 4개 = 1990~2026-01 전기간 MLE(핀 K_Fractal_Master_2026-01-20) → 2026-01-18 이전 Crisis_Prob 전부 C1. unified Layer1·Category 단락·Cash_Pct → module_performance·FR/RCMA·m4(BOOK_0001·pg2) 상속. 폴백 msm_daily_refit = 평활(C1×2). C11 과 독립 — C11 해제와 무관하게 유지",
  "factors": [],
  "sources": [
    {"regex": "\\bmsm_(daily|hybrid)_latest\\b", "violation": "C1", "why": "운영 MSM 캐시"},
    {"regex": "\\bmsm_update\\b", "violation": "C1", "why": "생산자 04_Research/regime_comparison/msm_update.R"},
    {"regex": "\\b(msm_daily_refit|compute_hmm_daily_signal)\\b", "violation": "C1×2", "why": "폴백 — 평활 γ·전 이력 덮어쓰기"},
    {"regex": "MSM_Crisis_Prob", "violation": "C1", "why": "unified·m4 열(_lag 포함)"},
    {"regex": "(?<![A-Za-z0-9_])Crisis_?Prob(?!_?asof)\\b", "violation": "C1", "why": "msm 캐시 열·C++ CrisisProb (as-of 판 제외)"},
    {"regex": "\\b(extract_msm_path|load_msm_(signal|daily))\\b", "violation": "C1", "why": "핀 모수로 필터를 직접 돌리거나 regime_signal.R 로더 호출"},
    {"regex": "K_Fractal_Master|msm_param_pin|MSM_updated_", "violation": "C1", "why": "전기간 모수 파일·핀·RData 산출"},
    {"regex": "1-1\\.MSM", "violation": "C1", "why": "load_msm_signal RData 폴백 디렉터리(05_Production/1.Regime_Def_Model/1-1.MSM)"},
    {"regex": "\\bunified_regime_signal", "violation": "C1 (상속)", "why": "C11 해제 후에도 유지 — Layer1·Category 단락"},
    {"regex": "\\bREGIME_SIGNAL_CACHE\\b|\\bregime_signal\\.R\\b|\\bbuild_regime_signal_table|\\bregime_current\\b", "violation": "C1 (상속)", "why": "unified 무명 접근·생산자·현재값 파일"},
    {"regex": "module_performance|\\b(module_regime|regime_module)_admission\\b", "violation": "C1 (상속)", "why": "국면별 성과·RCMA"},
    {"regex": "\\bregime_forecast", "violation": "C1 (상속)", "why": "CrisisP·Category 입력 예측기·산출"},
    {"regex": "\\bm4_published\\b|\\bm4_panel|WT[-_]D20260430_001|pg2_risk_overlay|M4gAE", "violation": "C1 (상속)", "why": "m4 Cash_Pct_lag·MSM_Crisis_Prob_lag 경유"}
  ],
  "overlay_arms": [{"id": "pg2_risk_overlay_v1", "violation": "C1 (m4 arm)", "means": "이미 suspended(C11) — 재개 조건에 MSM as-of 수리 추가"}],
  "modules": "PITQ-C11-20260924.modules 와 같은 15개 — contamination 에 C1 사유 병기(fr_eligible 이미 false)",
  "lanes": [{"lane": "l2_auto", "violation": "C1 (module_performance·unified Category)", "means": "enabled=false 유지 — C11 해제만으로 재개 금지"}],
  "not_in_scope": "BOOK_0001(도훈 결정 — PIT-C11-BOOK0001 표기에 C1 병기 권고) · 05_Production STR_1715 2-1~2-4 · RAMP(RAMP_ARMSM_Q_20260619) · 레거시 STR · 표시층(텔레그램·regime_current)",
  "ledger_marks": {"writer": "reinforce_ledger.R::rf_mark_vintage_batch", "flag": "pit_c1_msm",
                    "l1": "15칸 = PITQ-C11 ledger_marks.l1.pg2 목록과 같음", "l2": "FR_003 base · cell 1 (L2_TSC)"}
}
```

**주의 사항**

- `modules`·`ledger_marks`는 지면상 요약했습니다. 실제 등재 때는 PITQ-C11 항목과 같은 배열·객체 스키마로 펼칩니다(판독기는 이 두 필드를 읽지 않으므로 효력은 `sources`·`flag`·`status`에서 나옵니다).
- 정규식 13개는 **양성 대조 없이는 방어선으로 세지 않습니다**(pit.md 존치 교훈). `08_Tests/validation/test_pit_quarantine_c11.R`과 같은 형식의 검사를 함께 둘 것을 권고합니다. 검사 내용은 위반 주입(MSM 캐시를 읽는 생성 arm → REJECT)과 돌연변이 red(정규식 제거 → ADMIT)입니다.
- **초안 점검**(Python 재현 · 대소문자 무시):
  - MSM 탐침 11개(캐시 2 · 열 3 · 생산자 · 폴백 · RData · 모수 파일 · 05_Production 디렉터리 · C++ 커널)가 전부 BLOCK입니다.
  - 음성 대조 4개(`Crisis_Prob_asof` · JM `Bear_Prob_lag` · BM `regime_score` · 일반 `cash_pct`)는 전부 clean입니다.
  - `overlay_arms/` 82파일(pg2 2개 제외) 중 arm 코드(.R·.arm.json) 오탐은 0건입니다. 걸린 것은 LLM 설계 프롬프트 로그 `prompt_gen_*.txt` 7개뿐이고, 이미 C11의 `pg2_risk_overlay` 정규식에 걸리던 것입니다.
- **넣지 말 것**: 맨 `Regime_Score`·`Cash_Pct`·`Category`. STR_1715의 BM 기반 `regime_score`(cls_thr_q)와 대소문자 무시로 충돌합니다.
- as-of 원형(`Crisis_Prob_asof`)은 lookahead 부정으로 제외했습니다.

### 5.3 그 밖의 최소 조치 (우선순위순)

1. **원장 표식**: `rf_mark_vintage_batch`로 L1 15칸과 L2 2칸에 `pit_c1_msm`을 붙입니다(append-only · essence·grade 불변). C11 표식과 **독립된 두 번째 차단**이 되어 C11 해제 뒤에도 A 자격·rebase에서 빠집니다.
2. **C11 2단계 재측정 보류**: 판정서 `PIT_C11_verdict_20260924.md` §④ 측정 설계(:205-210)의 순서(m4 공표판 재산출 → pg2 15칸 → FR_003 T/S/C → BOOK 재현)를 MSM as-of 생산자가 생길 때까지 보류합니다. 그대로 돌리면 C11만 고친 C1 오염판이 "재측정 정본"이 됩니다(세탁). 판정서 자신의 "이중 재측정 회피" 원칙대로 **한 번에** 돌릴 것을 권고합니다.
3. **결정 항목 개설**: `PIT-C1-MSM-PARAMS`(현재 decision_register 120건 모두 resolved · MSM 항목 없음). 선택지는 셋입니다.
   - 안 A: as-of 연말 재적합 생산자 + 원장 재발행
   - 안 B: 수리 전까지 MSM 층을 쓰는 등급 경로 정지(표식만)
   - 안 C: MSM 층을 unified에서 분리
   - default_until_decided는 봉쇄입니다.
4. **폴백 fail-closed**: `msm_daily_refit.R` 호출부(daily_refresh.sh:411-416 · self_heal.R:44-51)가 실패 시 기존 캐시를 보존하게 바꾸거나, 필터 as-of HMM2(`04_Research/l2_role_rotation/build_hmm2_asof.R` 규약)로 교체합니다. 코드 변경이라 승인이 필요합니다.
5. **표식 문서**(코드·산출 무변경, `04_Research/factor_rotation/output/PIT_C1_JM_NOTICE.md` 선례): FR 산출 9개·module_performance per_regime·overlay_ab_results·hypothesis_index 18건에 "C1(MSM 모수) 라벨 위에서 측정 — 결론 근거 인용 금지" 표기. 특히 **"국면 배분은 정적 EW 대비 0/음수"** 같은 negative는 깨끗한 라벨로 재시도할 정당성이 있습니다(AX-000). 2계층 역할 로테이션 판단에서 이를 확정 사실로 읽으면 안 됩니다.
6. **BOOK_0001**: 전진 트래킹은 멈출 필요가 없습니다(2026-02 이후 결정은 MSM 측면 미래참조 아님). `PIT-C11-BOOK0001` 표기를 "C11 + C1(MSM) 미해소 게이트"로 넓히고, 이력(carrier · 271m 게이트)을 근거로 인용하지 말 것을 권고합니다. 재산출·Judge는 2번과 묶습니다.
7. **Judge 점검 추가**(문서 권고): 국면·오버레이 신호의 **모수 추정 창 ≤ 결정일**을 절단 재적합으로 확인하는 항목을 추가합니다. C5 t-1·lag-1·strict-PIT A/B·label gate·append-only 무결성은 이 위반을 통과시킵니다.

---

## 6. 올바른 as-of MSM 요건 (원형 = `04_Research/l2_role_rotation/build_msm_asof.R`)

1. **추정**: Calvet-Fisher binomial MSM k̄=10. 목적함수·벌점 경계·3 초기점(자료 무관 + 창 sd)은 MSM.R `estimate_msm_windows`와 같게 둡니다. 수렴은 변환 모수 NM 재시작에 BFGS 연마를 붙여 보강합니다. 운영 NM maxit 1000은 PC3에서 핀보다 나쁜 점에서 멈췄습니다.
2. **창**: expanding. 매년 마지막 한국 거래일 r_k에 `Date ≤ r_k` 자료로만 재적합하고, θ_k를 (r_k, r_{k+1}]에 전방 적용합니다. 디민은 expanding(현행)이고, 위기 상태는 `s > σ_k`입니다. 필터만 쓰고 평활은 금지합니다.
3. **식별 가드(사전 등록)**: γ1 < 1e-5 또는 σ/sd(창) ∉ [0.8, 1.25]이면 최선의 비퇴화 초기점을 쓰고, 그것도 없으면 직전 유효 θ를 승계합니다. 원형에서는 23회 적합 중 2회(2005-12 · 2011-12)가 best_nondegenerate였고 5,618일 중 495일이 여기에 해당합니다. AUC 등 성과를 보기 전에 고정합니다.
4. **모수 일정 원장**: `{fit_date, data_end, θ, NLL, guard_action, benchmark 해시}`를 append-only로 기록합니다. 해마다 1행씩 추가하고 과거 θ_k는 재기록하지 않습니다. 저장 열은 `Crisis_Prob`(as-of) + `msm_fit_date`이고, 파일 속성은 `msm_estimator = asof_yearly:v1`입니다.
5. **양성 대조**(원형 통과분 승계):
   - PC1 고속 커널 = 운영 커널(1.6e-14)
   - PC2 저장 캐시 = 재계산
   - PC3 전기간 MLE NLL ≤ 핀 NLL
   - PC4 접두 불변
   - 절단 재계산 일치(\|Δ\| ≈ 1e-15)
6. **원장 재발행**: `regime_published`(월간·일간)과 `m4_published`의 epoch 키에 MSM 추정기 id를 넣습니다. 현행 키 `c11_avail:2026-09-24.b4:631e4f98`에는 MSM이 없어서, as-of 재빌드는 **동결 행 재서술(exit 1)로 거부되고 오염 이력이 보존**됩니다. 재발행은 기존 `regime_append_only.R --republish`·m4 재초기화 런북(dry-run → `--execute`)을 따릅니다. pg2 소비자는 epoch 불일치를 거부합니다(설계상 정상).
7. **하류 재빌드 순서**:
   1. module_performance
   2. regime_forecast_series(재생성 또는 퇴역)
   3. pg2 15칸 · FR_003 · BOOK_0001 게이트 이력 — C11 수리와 **한 번에**, 정본 계약으로 등급 산출
   4. Judge
8. **비용**: 전기간 MLE 1회 143~194초(PC3)입니다. 이력 23회 적합은 일회성으로 약 1시간이고, 운영에서는 연 1회 적합만 추가됩니다.
9. **잔여 위험(PIT 아님)**: 우도면이 평평해 추정기 선택만으로 라이브 라벨도 흔들립니다(2026-10 월간 CRISIS↔CAUTION). 단락 문턱 0.9/0.7과 포화 0.8의 근거(R14)는 C1 표본 내 실측이므로 as-of 판으로 다시 재야 합니다.

---

## 7. 그대로 두면 생기는 위험

1. **2계층 A 후보 오염**: 수동 /strategy-rotation 세션이나 l2_auto 재개가 module_performance per_regime과 unified 라벨로 FR 등급을 냅니다. Judge의 2계층 축(C5 t-1·label gate·append-only)은 이를 통과시키므로 C1 오염 A가 BOOK까지 갈 수 있습니다.
2. **생성 arm 우회**: B5/B1 설계 레인이 MSM 캐시를 직접 읽는 arm을 만들면 등재 관문이 통과시킵니다(§5.1-1).
3. **C11 해제 연쇄**: PITQ-C11을 풀면 unified·m4·module_performance·forecast 차단이 함께 사라집니다.
4. **재측정 세탁**: C11 2단계를 그대로 돌리면 C1이 남은 결과가 "수리된 정본"이 됩니다.
5. **원장이 오염을 지킵니다**: epoch 키가 C11뿐이라 as-of 재빌드가 재서술로 거부되고 오염 이력이 보존됩니다.
6. **잠복 폴백**: msm_update만 실패하고 benchmark가 있으면 평활 전 이력이 캐시를 덮습니다.
7. **지식 오염**: 18건의 negative·조건부 카드(FR 시리즈·DIST-RAMP·L-RAMP A)가 깨끗한 라벨의 재시도를 막는 근거로 읽힐 수 있습니다.
8. **BOOK_0001 이력 근거**: de-risk 14개월 중 3개월(2008-03 · 2009-05 · 2009-06)은 전기간 MSM 때문에만 존재합니다.

---

## 부록 A. 라벨 반전 진단 (재현용 · 저장소 쓰기 0)

- **입력**(읽기 전용):
  - `.cache/unified_regime_signal.parquet` · `_daily.parquet` · `.cache/msm_daily_latest.parquet`
  - `04_Research/l2_role_rotation/work/msm_asof_daily.parquet`(원형 as-of · 타 에이전트 산출 · 읽기만)
  - `06_Registry/m4_published/m4_panel_published.parquet`
  - `stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet`
- **방법**:
  - `Regime_Score' = Score − L1(p_prod) + L1(p_asof)`. 일간 L1+L2 행은 ×90/75 재정규화를 반영합니다(regime_signal.R:997-998).
  - Category·Cash는 `classify_regime_category`·`get_cash_allocation`(regime_signal.R:391-462)을 그대로 이식했습니다.
  - m4는 factor_engine.R Stage 7 사다리(baseline + Case B/C/D)를 그대로 이식했습니다.
  - BOOK 게이트 = 0.70 ⇔ (weight<0.999 ∧ AE fire_seq==1, 연월 조인)입니다.
  - 비교 범위는 2026-01-18(핀 적합일) 이전입니다.
- **양성 대조(7/7)**:

| 대조 | 결과 |
|---|---|
| PC1 운영 일간 월평균 = unified MSM | 1.1e-16 |
| PC2 저장 Score → Category 재분류 불일치 | 0 |
| PC3 Cash 재계산 | 0 |
| PC4 일간 unified MSM = 운영 캐시 | 0 |
| PC5 일간 재분류 불일치 | 0 |
| PC6 m4 사다리 재계산 = weight_str1715 | 0 |
| PC7 m4 Cash_Pct_lag = unified 직전월 | 0 |

  - 클램프(0/100) 행 0 → 재구성은 정확합니다.
- **결과**:
  - 월간(2004-01~2025-12): IS 22/132 · OOS 14/120 · 전체 40/264 반전 · Cash 변경 14 · Cash>0 반전 9
  - 일간(2004-01~2026-01-16): 1,116/5,441(20.5%)
  - 홀딩월 결정 라벨: 51/253
  - m4: 14/263 변경 · 발화 38→29
  - BOOK 게이트: 217개월 중 de-risk 14→11, 반전 2008-03·2009-05·2009-06
  - 참고: 저장된 `d3_gate_history_271m.csv`(08-08 판)는 C11 재빌드 전 패널이라 de-risk가 19개월입니다. 현 패널 재계산은 14개월로, 위 수치와 일치합니다.

```python
# 실행: .venv_qvest_ml/Scripts/python.exe -I msm_flip_count.py <ROOT> <out.json>   (요지 — 전문은 세션 스크래치 msm_flip_count.py)
L1 = lambda p: 40*np.minimum(1, np.nan_to_num(p)/0.8)
def classify(s, m):  # regime_signal.R:432-447
    b = np.where(s>=70,"RISK_OFF",np.where(s>=45,"CAUTION",np.where(s>=25,"NEUTRAL","RISK_ON")))
    m = np.nan_to_num(m, nan=-1)
    return np.where(m>=0.9,"CRISIS",np.where((m>=0.7)&np.isin(b,["NEUTRAL","RISK_ON"]),"CAUTION",b))
cash = lambda s: np.where(s>=70,0.5+0.5*np.minimum(1,(s-70)/30),np.where(s>=45,0.15+0.20*(s-45)/25,0.0))
# 월간: msm_asof 월평균(달력월) 대입 → score' = clip(Score - L1(MSM) + L1(asof)) → classify/cash 비교 (Date < 2026-01-18)
# 일간: fac = 90/75 (Active_Layers=='L1+L2') → score' = clip(min(100,(Score/fac - L1 + L1')*fac))
# m4: bc=clip(Cash_Pct_lag'); joint=decay_strong&bocpd_strong(warm=row>=13);
#     w=1-bc; bc==0 → joint 0.75 / extreme 0.80 / strong 0.92   (factor_engine.R:718-741)
# 게이트: 0.70 if (w<0.999 & AE fire_seq==1 [연월 첫 decision_date]) else 1.0
```

## 부록 B. 확인 방법 메모

- **소비자 탐색**: `.git`·`.claude/worktrees`·`.venv_qvest_ml`을 제외하고 `*.R|*.py|*.sh|*.ps1|*.bat`에 대해 전수 grep했습니다. 패턴은 `msm_daily_latest|msm_hybrid_latest|msm_signals|MSM_Crisis_Prob|Crisis_Prob|unified_regime_signal|REGIME_SIGNAL_CACHE|load_(daily_)?regime_signal|get_regime_at_date|Regime_Score|regime_forecast_series|regime_current.json|build_regime_signal_table`입니다. MSM 직접 36파일, 파생 포함 243파일입니다.
- **예약 확인**: `Get-ScheduledTask`에서 Qvest_* 12개(라이브: DailyRefresh·MorningBrief·MorningReboot·ReinforceAutoLoop·WeightCatalogGrow·AxiomReview·MonthlyDistill·WeeklyCleaner·StrandedRepairs·InsiderBackfill)와 `noLayer4_Monthly_PaperTracking`을 확인했습니다. `reinforce_auto_tick.sh` 레인(replication·overlay_propose·b1/b5 design·l2_auto·parallel) 중 MSM·unified를 읽는 것은 l2_auto(정지)뿐입니다.
- **원장 스캔**: L1 68 entries / 1,381 attempts 전수 JSON 토큰 스캔과 39 기저 엔진 파일 본문 스캔을 했습니다. L2 · FR registry · module_catalog(971) · module_performance(65) · overlay_catalog(40) · overlay_arm_ledger(33) · hypothesis_index(2,921) · distilled_knowledge(472) · ramp_registry(7)도 스캔했습니다.
