---
name: factor-rotation
description: 팩터 로테이션 모드 — QEPM/alpha-search가 생산한 전략 모듈들을 국면(regime) 조건부로 배합해 합성 운용체계(FR_XXXX)를 만드는 제3 리서치 모드. 모듈을 생산하지 않고 소비하는 meta-layer(Lane3). 1모드 2트랙(Track1 레짐엔진 리서치 + Track2 배분 리서치). 모듈 풀 admission은 overall 등급이 아닌 국면조건부 성과(RCMA — 방어형 CRISIS specialist + 공격형 확장 specialist 양방향, 등급무관). 실측-only(build_bt_result)+essence_score(DSR/OOS 게이트). governor 정지(book_state 수동). QEPM 6-에이전트·alpha-search와 구분.
---

# 팩터 로테이션 모드 (factor-rotation)

Qvest 제3 리서치 모드. **신규 알파를 찾지 않고**, 이미 생산된 전략 모듈들을 **국면 조건부로 배합**해 합성 운용체계(`FR_XXXX`)를 만든다. alpha-search(논문 1편 검증)·QEPM(6-에이전트 풀파이프라인)과 별개의 독립 트랙(meta-layer).

## 1. 목적 (왜 만들었나)

도훈 비전: **전략 = 모듈. Governor가 다양한 모듈을 국면에 적재적소 투입해 수익률을 극대화하는 의사결정 체계.**
- 실증 근거: 단일 모듈 long-only **SR 천장 ~2.0**. SR 2.5는 단일 모듈을 키워서가 아니라 **여러 모듈을 국면 조건부로 엮는 앙상블 레벨**에서 발현(국면별 약점구간 회피 → 변동성·낙폭↓ → Sharpe↑).
- **Lane1(QEPM full) / Lane2(alpha-search lean) = 모듈을 *생산*. Lane3(본 모드) = 그 모듈 풀을 국면 함수로 *시간배분*하는 meta-layer**(생성/태깅 없이 소비).

## 2. 구조 — 1 모드, 2 nested 트랙

```
팩터 로테이션 모드 ── 1 mode
├── Track 1: 레짐엔진 리서치   = 국면 정의 + 사전 예측 강화 (토대)
└── Track 2: 팩터 로테이션 리서치 = 모듈 배분 강화 (Track1의 국면 사용)
```
- 독립 아님 — Track1이 국면 인식·예측 강화 → Track2가 그 국면으로 배분 개선. **Track1 → Track2 의존.**
- 공유: 진입점 `/factor-rotation <track∈{regime-engine, allocation}>` · 동일 measurement 계약 · L-code(`mode=factor_rotation|regime_research`).

## 3. 산출물 — FR vs STR (2계층)

- **STR_XXXX = 개별 전략 모듈**(부품; QEPM/alpha-search 생산).
- **FR_XXXX = 운용체계**(신규 ID): {module pool + 레짐엔진 버전 + 국면→모듈 배분정책}. essence_score 등급(A/B/C/F). `factor_rotation_registry.json`(후속).
- **2계층**: ① book 레벨 — sleeve = STR(단일) 또는 **FR(1 sleeve)**. 표준 PG1→PG2→PG3. ② FR sleeve 내부 — 국면→STR 모듈 로테이션.

## 4. ★ 모듈 적재 계약 (표준화 — QEPM·alpha-search 둘 다 소비 가능)

FR이 모듈을 소비하려면 **표준형** 필수:
- `04_Research/strategies/{ID}/sim_result.rds` — `$DAILY_NAV_DT[Date, Strategy_Ret]` + `$bm_xts` (실측 NAV).
- 카탈로그 엔트리(grade/role/origin/sim_result_path).
- **진입점 = 공용 `register_module()`** (`02_Infrastructure/contracts/register_module.R`): sim_result 스키마 검증 → saveRDS(canonical) → upsert `06_Registry/module_catalog.json`. **등급무관 등재**(사용여부는 §6 RCMA가 판단).
- **QEPM** = native 준수(`run_monthly_simulation` 표준 sim_result + grade_a_catalog). **alpha-search** = `register_module` 경유(`run_alpha_search.R` 배선). **`build_module_performance.R`가 grade_a_catalog ∪ module_catalog ∪ 04_Research/strategies/* 전수(validity 필터=데이터깨짐만: MDD≥99%/일간|ret|>50% 제외. ★등급·overall성과로 거르지 않음)를 union 적재** → `module_performance.json`(per-regime).
- **★ 새 모듈 자동 인식**: allocation 단일 진입 `run_factor_rotation.R`이 `module_performance.json` 신선도(mtime vs strategies/·module_catalog 최신) 체크 → 새/변경 모듈 감지 시 pool 자동 rebuild(build_module_performance+RCMA). **QEPM/alpha-search 신규 산출물은 다음 FR 실행에 자동 편입**(`FR_FORCE_REBUILD=1` 강제). 실증: 신규 모듈 등록→stale 감지→풀 80→81 자동 편입.

## 5. ★ 모듈 풀 admission = RCMA (overall 등급 아님 — 국면조건부, 양방향 대칭)

**Grade-A만 쓰지 않는다(도훈 mandate). 어느 국면이든 그 국면에서 압도적이면 차용 — F-overall이어도.**
- **방어형 (CRISIS specialist)**: CRISIS 강·RISK_ON 약 → CRISIS-admitted. **AX-001**(방어형 조건부 평가: crisis_alpha + Core 대비 MDD + bad/normal IC ratio) 정합.
- **공격형 (RISK_ON/확장 specialist)**: 확장기 압도·CRISIS 약 → 해당 국면 admitted. (성장/모멘텀이 확장 지배·위기 급락 → F-overall이어도 RISK_ON-A면 차용. 더 흔한 케이스.)
- 논리: dispatcher가 **각 모듈을 강한 국면에서만 쓰고 약한 국면엔 ~0** → 약점 국면 무관, 강점만 앙상블 기여. **overall 등급(전국면 평균)은 약점이 강점을 상쇄한 잡음** → 게이트 부적합.

**RCMA 6기준** (`02_Infrastructure/portfolio/regime_module_admission.R` → `module_regime_admission.json`):

| # | 기준 | 합격선 |
|---|---|---|
| 1 | 국면 성과 | `regime_IR(m,L) ≥ 0.5` **OR** regime-L 상위 ⅓ (specialist) |
| 2 | 표본 충분 | `n_months(m,L) ≥ 12` floor (`≥36`=high_conf; 희소국면 CRISIS는 36 비현실) |
| 3 | OOS 지속(과적합) | IS·OOS regime IR **둘 다 양수**(부호 지속) |
| 4 | 유의성 | `|t| = |IR·√(n_m/12)| ≥ 2` (소표본일수록 더 높은 IR 요구 — 표본-significance 담당) |
| 5 | 경제논리 | role/regime 메커니즘 1줄(방어형 AX-001 / 공격형 고베타·모멘텀). 데이터마이닝 방지 |
| 6 | 한계기여(권장) | regime-L 앙상블 ΔIR > 0 (median 초과 proxy) |

admitted = ①∧②∧③∧④. m이 ≥1 regime admitted면 풀 진입. `run_wf_ensemble`이 admitted union으로 풀 제한 + regime별 후보 제한.

**★ C2 소표본 셀 완화 경로 (2026-06-10 도훈 mandate — `compute_rcma(rare_mode=)`, v2.1) → 2회 A/B 실측 최종 기각, rare_mode OFF 유지**: ②n≥12 × ④t≥2의 곱이 소표본 specialist 셀을 차단(valearn CRISIS n=7류) → 완화 경로 설계. **v2.0**(rare=국면 base rate<10%)은 A/B 악화였으나 진단 결과 구현 결함(CRISIS 16.7%라 표적 비껴감 + rationale-strict 소급 적용이 legacy 강셀 STR_1622 CAUTION 제거 — 단일 셀 가치 SR 0.043/PORT_t 0.375 실측). **v2.1 재설계**(rare = 위기군 국면 ∧ 셀 n<12, 소급조임 금지 — 순수완화 ON⊇OFF) **재A/B: OFF 0.880/1.871(FR_001 재현) vs ON 0.859/1.624, OOS active SR −0.084→−0.178(2배 악화), 신규입장 4모듈 → 깨끗한 인과로 기각.** 교훈: ① 현 풀에서 소표본(n6~12) 위기군 셀의 측정 IR은 대부분 운 ② dispatcher RP-앵커(λ_rp=0.5)는 IR 무관 inverse-vol 배분이라 **admission이 유일한 품질 게이트** ③ 앙상블은 단일 셀 멤버십에 민감. **재도전 트리거(INV-7)**: 직교 sleeve·진짜 CRISIS specialist 등재 시 v2.1 재실행. 그 전까지 legacy 판정이 권위.

## 6. 작동 메커니즘

- **Track1** — `regime_engine_research.R`(축 t-1 → 판별력 검증 → 채택) · `regime_forecaster.R`(다음국면 사전예측 — 후속).
- **Track2** — `module_performance.json`(per-regime 실측) → `module_dispatcher.R`(`compute_regime_module_weights`: 국면조건부 rp inverse-vol + IR shrink 블렌드, λ/τ/k0 **국면불변 고정**) → `run_wf_ensemble.R`(anchored walk-forward, IS-only 가중, 모듈 frozen, forward 적용, 국면전환 turnover만 15bps).
- **측정**: 모듈 NAV 가중합 → 월간 → `build_bt_result`(PerformanceAnalytics 표준함수만, metric_type=backtested) → `audit_bt_result`(11 checks) → `essence_score`.

## 7. ★ Track1 = 학술 기반 리서치 (국면 정의·예측 강화)

Track1은 **각종 학술논문·헤지펀드 페이퍼를 참고해 국면 정의 및 예측 모델을 강화**하는 리서치 트랙이다. SOT: `04_Research/factor_rotation/regime_model_literature_review.md`.
- **SOTA = Statistical/Sparse Jump Model**(Bemporad 2018 / Nystrup sparse 2021 / Shu-Mulvey 2024) — jump penalty λ로 과전환 명시 차단, HMM 대비 Sharpe·MDD 우위. **✅ PoC 빌드 완료(2026-06-05)** `02_Infrastructure/regime/regime_jump_model.R`(K=2, coordinate-descent+DP, feature=EWM downside-dev/Sortino + log-VIX, PIT online lookback+126d refit+1d delay). **실측: 월 churn 33.2%→7.1%(4.7×↓; λ↑ 단조 2.5%까지), GFC 100%/COVID 94%/2022 100% hit, HMM 73% parity.** 단 **앙상블 OOS SR 로버스트 이득 없음**(SJM_SR_GAIN_NONROBUST — k=3 top-3 집중·seed flip; min-across-k+seed gate로 노이즈 차단) — 신호품질은 크게 개선되나 현 0.70-상관 풀에선 천장이 입력(직교 슬리브)에 의해 결정(regime_study 정합). SJM 실가치는 직교 슬리브 확보 후 §3 Shu-Mulvey 결합 시 발현. 현재는 msm_daily 대체/병렬 신호로 보유. 검증: `04_Research/factor_rotation/regime_jm_{validation,ensemble_ab}.R`.
- **팩터 로테이션 정본 = Shu-Mulvey 2024(arXiv 2410.14841)**: 팩터별 국면(SJM)→Black-Litterman→long-only MVO. 단 SOTA 순효익도 IR~0.5/active~1.5%/turnover 522%(겸손)+Quality(방어) 팩터 최약.
- forecaster 신호: MSM transition matrix + BOCPD changepoint + FRED 선행지표(Claims/Term-spread). KR: **US-VIX가 KR 국면 Granger-cause**(US 신호 1급 feature 의무).
- **신규 국면축/모델은 문헌 economic-rationale 선존 필수**(research_philosophy ① Factor Zoo 축소 정합).

## 8. 평가 지표 (정량 + 합격선)

| 트랙 | 지표 | 합격선 |
|---|---|---|
| T1 판별력 | Kendall τ(low/high bucket 모듈순위) / **OOS rank-persistence Spearman** | τ ≤ 0.5 / ρ > 0.2 / 유의모듈 ≥ 2 / BH-FDR q<0.10 |
| T1 예측 | hit-rate / **Brier score** / ROC-AUC / detection latency | baseline(국면지속) 대비 우위. 채택=앙상블 OOS SR 실개선 시만 |
| T1 신호품질 | monthly transition rate(churn) / avg duration / per-regime n | churn↓ / 셀 ≥ 12개월(≥36 high_conf) |
| T2/FR | **PORT_t(NW lag-3) / DSR / OOS_retention / Calmar** | **2.95 / 0.5 / 0.7 / 0.64 HARD** |
| T2/FR | net Sharpe / CAGR / MDD / net IR | 보고(SR 2.5 목표 — 미달 시 정직 표기) |
| T2/FR | edge vs EW(edge_vs_ew, OOS edge retention) / placebo / turnover | edge > 0 / placebo p<0.05 / TO ≤ 11.0 |
| RCMA | (module×regime) admission | §5 6기준 |

## 9. 측정·과적합 게이트 (SR2.5보다 먼저)

실측-only. ① OOS_retention ≥ 0.7 — **C1 v2 (2026-06-10)**: anchored 3분할{55/65/75} 중앙값, <0.5 무조건 FAIL, [0.5,0.7) band는 보강증거 2/3(trailing PORT_t>0 / placebo / book-marginal ΔSR — holdout 제외) 시 조건부 통과, FAIL 시 overfit/decay 사유 라벨 → ② DSR ≥ 0.5 HARD — **sweep형 selection만**(grid/축탐색/레짐grid/forecaster/hyper sweep, n_trials 누적. 가설주도 chain·단일 A/B는 게이트 면제 `selection_type="chain"` — 도훈 mandate 2026-06-10) → ③ placebo(국면라벨 셔플 앙상블과 통계 구분, p<0.05) → ④ holdout — **C3 (2026-06-10)**: 성과 채점 금지, 채택 시점 사전등록 블록부트스트랩 예측구간 [5%,95%] falsification(`holdout_falsification.R`: <q05 FAIL / 구간내 PASS_LOW_INFO / >q95 PASS_PLUS), 열람 후 수정 시 구간 소모, 라이브 트래킹 = holdout 자동 연장(`06_Registry/live_track/`). `measurement-graduation §3` 정합.

## 10. 거버넌스 · 제약 (반드시 준수)

- **governor 정지** — FR_XXXX가 게이트 통과해도 `book_state.json` 자동 쓰기 금지. book-marginal ΔIR≥0.05 진단까지만, 실편입은 Q-Lead+도훈 수동 confirm(`measurement-graduation §4`).
- **모듈 frozen** — 본 모드는 배분만. 모듈 재백테/시그널 수정 금지(alpha-research/forge 영역).
- **스타일태깅 없음** — 모듈 = 기존 STR 직접. 배분은 각 모듈의 국면조건부 성과로 직접.
- **dispatcher = book_optimize 래퍼** — 직접개조 금지. classifier/forecaster frozen(국면정의 후행 재튜닝 금지).
- Production Constraints: long-only / Σw=1 / w∈[0,0.20] / max 25종목 / 15bps / LIQ 2e8 / turnover ≤ 11.0/yr.
- **WT-id 미사용**(FR 트랙은 WorkTask lifecycle 밖). 텔레그램 `tg_agent_brief()` 단일 진입점.

## 11. 구현 상태 (정직)

- **빌드 완료**: Track2 전부(`module_dispatcher`/`run_wf_ensemble`/`build_module_performance` 광역화) · Track1 판별검증(`regime_engine_research`) · **Track1 SJM PoC(`regime_jump_model.R` — SOTA jump model, churn 33→7%, crisis 신속탐지·신호품질↑·앙상블SR 로버스트이득 無)** · **공용 `register_module`** · **RCMA `regime_module_admission`** · FR_001(grade C 실측).
- **미빌드(후속)**: `regime_forecaster.R`(T1-B 예측 — 지표는 §8 정의) · `/factor-rotation` command · `dispatch-orchestrator` agent · `02_Infrastructure/docs/rules/factor-rotation.md` · 3 hooks · `factor_rotation_registry.json` · L-code mode 태깅 · CLAUDE.md 3-mode 명문화 · QEPM의 register_module 일원화. → **현재는 직접 스크립트 실행**(Q-Lead).

## 12. 참조 · 실행 메모

- 설계 SOT: `C:\Users\User\.claude\plans\curious-sauteeing-hippo.md`(원본 구현 계획) · Track1 학술: `04_Research/factor_rotation/regime_model_literature_review.md`.
- 현 풀 한계·EW 천장 등 **실증 결과는 별도 연구노트**: `04_Research/factor_rotation/output/regime_study*.json` + 메모리 `project-factor-rotation-regime-study`.
- 실행(Windows-native, 재시작 전): `"/c/Program Files/R/R-4.5.2/bin/Rscript.exe"` + env `CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot` `PYTHONUTF8=1`. 레짐/모듈 분석은 R(arrow)로(anaconda python pandas DLL 손상). 참조 메모리 `project-windows-native-migration`.
