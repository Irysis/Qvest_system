# 외부 제안 검토 — "Sharpe 2.5 System (Static Core + Dynamic Tilt + Risk Governor)" 

**작성**: 2026-06-10 (Q-Lead) · **검토 대상**: 도훈 전달 외부 분석 (KR long-only 멀티팩터 SR 2.5 아키텍처 제안)
**방법**: 제안의 주장 각각을 Qvest 기실측 결과(2026-06 기준)와 수치 대조. 분류 = [수렴(기구현/기실증)] / [기각·수정(실측이 반박)] / [신규 채택(실험 큐)].
**핵심 결론 1줄**: 제안의 최종 결론("로테이션 = 알파 엔진이 아니라 리스크 장치")은 Qvest가 이미 실측으로 도달한 결론과 일치. 신규 가치는 **팩터 밸류에이션 스프레드 타이밍(E1) · soft 국면확률 배분(E2) · crowding의 FR 배선(E3)** 3건 + 보조 2건 + **E6 Family Fair-Trial(2026-06-10 도훈 반박 수용으로 추가)**.
**개정 이력**: 2026-06-10 v1.1 — 도훈 반박("팩터군을 제대로 정의해서 테스트했는가? 한정된 횟수로 결론낸 것 아닌가") 수용. 기각 #2를 잠정 강등(§2.1) + E6 신설.

---

## 1. 수렴 — 제안이 맞고, Qvest는 이미 그렇게 하고 있음 (9건)

| # | 제안 주장 | Qvest 기실측/기구현 근거 |
|---|---|---|
| 1 | SR 2.5는 알파 증대가 아니라 변동성·꼬리 압축 문제 | `measurement-graduation.md §6` "SR 2.5 레버 = overlay(β/regime timing 주역) + DPL + uncertainty 선택". 실측: book base SR 1.54 → overlay 후 1.95 (**overlay 기여 +0.41 SR**, `project_sr25_autonomous_program` four_layer_returns_path 256m) |
| 2 | 팩터 로테이션은 알파 엔진이 아니라 리스크 조절 장치 | `regime_study_decisive.json` verdict **STATIC_SELECTION_ONLY**: Rotate−Static net SR = −0.045/−0.091/−0.071 (k=3/4/5 전부 음수), rho_demeaned 0.078~0.297. 반면 tail 레버는 실증: `valearn_overlay_result.json` CAUTION-off MDD 45.6%→**34.4%** (−11.2pp), SR 0.713→0.881, leave-crash-out robust |
| 3 | 팩터 모멘텀 단독 로테이션(trend-chasing) 위험 | `tsmom_timing_probe.json` grade **F** (port_t 1.18, oos_retention −0.17). RCMA는 이미 모멘텀이 아닌 국면조건부 IR 기반 |
| 4 | 틸트는 완만하게, 비중 급변 금지 | `module_dispatcher.R:12` 국면불변 고정 하이퍼 (λ_rp=λ_ir=0.5, k0=36 shrink, w_cap=0.25), softmax 온도 τ=0.6 |
| 5 | 국면을 팩터 상위 레이어로 | factor-rotation 모드 그 자체 (Lane3 meta-layer, RCMA 양방향 specialist 차용) |
| 6 | hard classification보다 soft probability | 방향 동의 — 단 §3 E2 참조 (forecaster 내부 p-vector 기산출, dispatch만 hard label). v4 실측 경고: SJM override 선제신호는 hit 0.841→0.670으로 **악화** (`regime_forecast_v4.json` adopt=false) — soft화도 A/B 실측으로만 채택 |
| 7 | 단계적 목표 (1.3~1.6 → 1.8~2.0 → 2.2+ → 2.5 근접) | 2026-06-10 역량평가 권고와 동일: book 실측 1.709(256m full)~1.95(admit window), +전종목 value 1.989 검증, overlay robust화 포함 ~2.2 추정(라벨: estimated). 1차 목표 "book SR 2.0 백테 + CAGR16 + MDD<25" 권고 기존재 |
| 8 | Static Core 팩터군 구성 (earnings revision 핵심 + quality 방어 + value w/ distress + residual momentum + low-vol) | STR_1715 구조와 사실상 동형: Core = C01_SUE/C02_EPS_Chg/C04_ESBR/C06_TP_Gap, Defense = Q07/M08_ResidMom/Q25_Ohlson, low-vol은 overlay β 0.4~1.0으로 구현 (`reference_str1715_structure`) |
| 9 | 데이터마이닝 방지 (DSR, walk-forward, nested OOS) | measurement-graduation §3 기구현: PORT_t≥2.95 / oos_retention≥0.7 / calmar≥0.64 HARD + DSR(n_trials 누적) + placebo + holdout |

**판정**: 제안의 골격은 검증된 방향이며, Qvest는 이미 그 골격 위에 있고 상당 부분은 제안보다 한 단계 더 나아가 *실측으로 한계까지 확인*한 상태.

---

## 2. 기각·수정 — 실측이 제안을 반박하는 지점 (확정 5건 + 잠정 1건)

| # | 제안 주장 | 반박 실측 | 처리 |
|---|---|---|---|
| 1 | 팩터군 분산이 변동성을 압축한다 | KR long-only는 β 공통항(1st eigenmode)을 팩터 믹스로 제거 불가: 모듈 상관 0.73~0.80, 직교 sleeve 16/16 FAIL (`measurement-graduation §6`). vol 압축의 실레버는 **overlay β scaling** | 채택 안 함 — overlay 우선순위 유지. **각주(v1.1)**: 현 풀 상관 0.73~0.80은 풀 *구성 이력*의 산물 — 전종목 value sleeve cor 0.005~0.03이 직교 sleeve 달성가능성을 입증(α-분산은 유효, β-압축만 overlay 영역) |
| 2 | 6개 팩터군 모두 핵심 알파 | Cycle 6 기록: value만 SR 0.849, profitability 0.49/OOS −1.28, dividend 0.36/OOS −1.95 (`_census_v2/cycle6_sleeves.csv` — **원 CSV 이 머신 미동기화, 메모리 기록 기준**) | **잠정 강등 (v1.1, 도훈 반박 수용)** — "value만 유효"가 아니라 "value만 충분한 탐색을 받고 생존". §2.1 + E6 |
| 3 | 종목수 25~50개 권장 | Production Constraint max 25 (hook 강제, 도훈 mandate 2026-05-29). 분산 효과는 종목수가 아닌 **유니버스 확장**(K200∪KQ150 348 → 전종목 LIQ≥2e8 2005종목)이 이미 더 크게 제공: 2017+ value PORT_t −0.74 → **+1.41** | 기각. 전종목 확장(기허용)으로 대체 |
| 4 | 알파모델 기준 = 월간 IC 3~5% | rank-IC는 ADVISORY 강등 — 16후보 calibration에서 rank_ic≥0.04가 FLOW 거짓탈락 + NN/TECH 거짓통과 (`measurement-graduation §3`). 권위 = portfolio-alpha t (NW lag-3) ≥ 2.95 | 기각. PORT_t 유지 |
| 5 | Turnover 연 400~700% 캡 | Qvest 단위 TO ≤ 11.0/yr (도훈 mandate 2026-05-29, KR alpha turnover-intensive 반영 + net>cost 입증 의무) | 기각 — 단위 체계 다름. 기존 캡 유지 |
| 6 | 국면판단 soft화 = 무조건 더 안정 | `regime_forecast_v4.json`: 선제/soft 신호(v4o)가 hit-rate 0.841→0.670, Brier 0.276→0.517로 악화. v1(expanding 전이행렬+stress nudge)만 persistence baseline(0.78) 우위 | 방향은 E2로 채택하되 "A/B 실측 우위 시만" 조건부 |

### 2.1 기각 #2 잠정 강등 — 탐색 깊이 비대칭 (2026-06-10 도훈 반박 수용)

**도훈 반박**: "팩터군을 제대로 정의해서 테스트했는가? 한정된 횟수로 결론낸 것 아닌가. STR_1715도 ~1715개 전략 테스트 끝에 나온 것."

**검증 결과 — 반박 타당.** family별 *처치(treatment) 수준*이 비대칭:

| Family | 명명 기반 STR 수¹ | 현행 표준처치² 횟수 | 결과 |
|---|---|---|---|
| earnings-revision | 23 + production 계보(1715 lineage: Iter5 2-sleeve·λ-tilt·M4/AR/R05 sweep) | 누적 O(10²~10³) 구성 | book SR 1.95 (유일 성공) |
| value | 9 + census curated composite(val_rd_wc lineage) + Cycle 1~9 | **~9 cycle** | PASS (+0.127 book SR 검증) |
| quality/profitability | 22 — 단 **전부 구프레임**(K200∪KQ150 + standalone 채점 + single/dual-signal) | **1 spec** (Cycle 6, return-level) | OOS −1.28 (잠정) |
| dividend/income | 2 | **1 spec** (Cycle 6) | OOS −1.95 (잠정) |
| liquidity | 4 | **≤1 spec** | ~0 α (잠정) |

¹ `04_Research/strategies/` 224 dirs 이름 키워드 분류 (근사 라벨 — 중복/누락 가능). ² 표준처치 = 전종목(2026-06-02 허용) + curated 다신호 composite + book-marginal 프레임(06-02 시작) + production-fidelity 구성.

**도훈 논지를 실증하는 기존 선례 2건** (얕은 결론이 깊은 시험에서 뒤집힌 사례):
1. "327팩터 2017+ 0 유의 (최고 1.08)" → 전종목 전환 하나로 value PORT_t **−0.74 → +1.41** (Cycle 4). 결론이 "large-cap 한정"으로 공식 수정됨.
2. "수익률 직교 구조 불가 (16/16 FAIL)" → 전종목 value sleeve cor 0.005~0.03으로 반례 (Cycle 1/5).

**헌법 정합**: 1-spec 음수 결과는 INV-7 negative 승격 기준(distinct construction ≥ 3) 자체를 미충족 — 애초에 "기각" 권위가 없는 L-code 수준 관찰. AX-004도 quality의 EXCLUSION 경로(multi-axis composite + multi-sleeve)를 명시 — 공리 체계 스스로가 "깊은 처치 미시도" 상태를 인정.

**1715 숫자 보정 (정직)**: STR ID는 전 family 합산 일련번호라 "1715회 전부 revision 시도"는 아님 (현존 224 dirs, census 1주에만 ~500 구성). 단 논지 유지 — 유일한 production 성공은 최다 반복 축에서 나왔고, 그 반복이 frame 발견(전종목·book-marginal·overlay)을 가능케 했음.

**양날 명시**: ① 깊은 탐색 = 다중검정 — 1715-trial 끝 승자 선택이 바로 admit window 1.95가 DSR로 1.1~1.5까지 deflate되는 이유. 사전등록 spec grid + n_trials 누적 회계 없는 깊은 탐색은 금지. ② 비용 반론은 약화 — frame이 확립된 지금 fair trial 비용은 1715가 아니라 **value 선례 기준 ~9 cycle** (revision의 1715에는 frame 발견 비용이 포함).

---

## 3. 신규 채택 — 실험 큐 (제안에서 Qvest에 없는 것)

> 공통 거버넌스: factor-rotation 모드 규율 그대로 — 모듈 frozen / 국면 t-1 lag / IS-only 가중 / `build_bt_result`(metric_type=backtested) / essence_score 게이트 / governor 정지 / n_trials 누적 (현 FR 누적 97, `FR_001_fc_result.json`) / WT-id 미사용.

### E1. 팩터 밸류에이션 스프레드 타이밍 (contrarian tilt) — 우선순위 1
- **내용**: 제안의 Z^valuation. 모듈(또는 모듈 기저 팩터)의 보유종목 밸류에이션 스프레드(예: 모듈 top-bucket vs universe B/M·E/P 스프레드의 expanding percentile, t-1)를 dispatcher 점수에 contrarian 항으로 추가. **현 시스템에서 유일하게 안 해본 타이밍 축** (국면 IR ✅ 기각, 팩터 모멘텀 ✅ 기각, 밸류에이션 ❌ 미시도).
- **문헌**: Research Affiliates contrarian factor timing (Arnott et al.) — trend-chasing 대비 우위 보고. Track1 규율 "신규 축은 문헌 economic-rationale 선존" 충족.
- **구현**: `build_module_performance.R`에 module×month valuation spread 컬럼 추가 → `module_dispatcher.R` score에 λ_val 항 (국면불변 고정, bounded). A/B vs 현 dispatcher in `run_wf_ensemble.R`.
- **사전확률 (정직)**: 낮음. 동일 풀에서 국면 타이밍이 STATIC_SELECTION_ONLY로 기각된 전례 — 모듈 상관 0.73~0.80 풀에서는 어떤 타이밍도 천장이 낮다는 게 기존 패턴(SJM_SR_GAIN_NONROBUST 동일 구조). 기대 산출물은 SR 개선보다 **기각이면 "타이밍 3축 전멸" L-code 확정**이라는 정보가치.
- **게이트**: edge_vs_ew > 0 + OOS edge retention + placebo(스프레드 셔플). PIT: expanding percentile, C1/C2 준수.

### E2. Soft 국면확률 배분 (hard label → 확률가중) — 우선순위 2
- **내용**: 제안 §6. dispatch를 `w = Σ_L P(L|info_{t-1}) · w_m(L)`로. `regime_forecaster.R:42-50`이 이미 p-vector(Laplace-smoothed 전이행렬 + stress nudge)를 내부 산출 — emit만 argmax. p-vector를 `.cache/regime_forecast_series.parquet`에 함께 emit하고 `run_wf_ensemble.R`에서 A/B.
- **기대효과 (정직)**: SR 개선 기대 낮음 (regime 타이밍 알파 부재 실증). 실효 기대는 **국면전환 turnover 감소 + 경계월 tail smoothing** (현재 국면전환 시 15bps 발생). 비용 절감 경로로 평가.
- **게이트**: 동일 + turnover 비교 명시. v4 교훈에 따라 hit/Brier 악화 시 즉기각.

### E3. Crowding penalty의 FR 배선 — 우선순위 3
- **내용**: 제안의 Z^crowding. research_philosophy ⑤ `crowding_score_per_factor`는 QEPM risk 단계에만 존재 — FR dispatch에 미배선. 모듈 레벨 KR proxy 설계 필요: 모듈 보유종목의 거래대금 집중도 / 외국인·기관 수급 쏠림 / 모듈 간 보유 중첩(pairwise holdings overlap).
- **구현**: module_performance에 crowding proxy 추가 → dispatcher 감점항. E1과 입력 파이프 공유 (한 사이클로 묶어 n_trials 절약).
- **사전확률**: 중하. 단 모듈 간 보유 중첩은 상관 0.73~0.80 문제의 *원인 진단* 도구로서 부가가치 있음 (admission 단계 중복 차단에 전용 가능).

### E4. Target-vol overlay 변형 (R05 교체 후보) — FR 모드 밖, book overlay 영역
- **내용**: 제안 §7 "예상 변동성 한도". 현 R05 = AR-threshold β∈{0.4,0.7,1.0} 이산 스케일링, DSR-fragile (역량평가 레버 ②, 입증 가치 +0.2~0.41 SR). target-vol(예: trailing EWM vol → β = σ_target/σ̂, cap [0.4,1.0])은 연속형 대안으로 robust화 후보군에 정식 추가.
- **거버넌스**: 이건 FR 모드가 아니라 **QEPM forge/overlay 영역** — overlay robust화 사이클에서 후보 비교군(AR-threshold vs target-vol vs blend)으로 처리. C9 (VT same-day 금지, t-1 lag) 준수.

### E5. 섹터 캡 advisory 실험 — 우선순위 5 (저)
- **내용**: 제안 §7 섹터 한도 BM±10~15%p. 현 production tilt(λ=1.5, top-20/25)에 섹터 제약 부재 — KR 반도체 쏠림 구조 고려 시 tail 개선 가능성.
- **리스크 (정직)**: book CAGR 44.6%의 일부가 집중에서 옴 — 캡이 CAGR를 깎을 수 있어 Calmar 게이트로 순효과 판단. advisory로만, optimizer-research 사이클에서.

### E6. Family Fair-Trial Protocol — 팩터군 공정심리 (2026-06-10 도훈 반박 수용, §2.1 귀결)
- **목적**: "팩터군이 죽었다" 판정에 *판정 권위*를 부여하는 표준 처치. 현재 profitability/dividend/liquidity의 음수 판정은 표준처치 1-spec 관찰에 불과(§2.1) — fair trial 통과 전엔 영구기각 금지, 전멸 시에만 INV-7 ledger 승격.
- **처치 정의 (value 선례 = 통과한 유일한 fair trial을 표준화)**:
  - **Stage A (스크린)**: family당 **사전등록 spec grid 6~10개** — curated 다신호 composite 2~4종(예: profitability = GP/A·OP/B·CFO/A·accrual·margin·asset-growth 조합) × distress/junk 필터 on/off × 전종목 LIQ≥2e8. `canonical_screen_bt` 채점. **통과**: 어느 spec이든 screen PORT_t ≥ 1.96 **AND** 2017+ 서브윈도우 PORT_t > 0 (front-loaded alpha 차단 — census A-push 교훈).
  - **Stage B (정밀, A 통과 시만)**: production-fidelity 구성(λ-tilt·top-N·buffer) + `build_bt_result` 정식 채점 + **book-marginal 게이트**(vanilla 1715 대비 cor < 0.30 + blend ΔSR > 0 — value 선례와 동일).
  - **Stage C (편입 심사, B 통과 시만)**: 정식 forge + ΔIR ≥ 0.05 + DSR(누적 n_trials) — `measurement-graduation §4`. governor admit = 도훈 수동.
- **종료 기준 (비용 통제)**: Stage A 전멸 → 해당 family "**공정심리 후 잠정기각**"으로 L-code 적립 + INV-7 expiry/재도전 트리거 부착(예: 신규 팩터 등록·데이터 연장·전략구조 신규 예외 발생 시 재심). family당 budget 상한 = Stage A 10 spec (초과 탐색은 도훈 confirm).
- **후보 우선순위 (근거 순)**: ① **profitability/q-investment** — 문헌 최강(HXZ q-factor·Novy-Marx) + AX-004가 composite+multi-sleeve 경로를 명시적 EXCLUSION으로 보존 + legacy 22건 전부 구프레임이라 정보가치 최대. ② **dividend/buyback(shareholder yield)** — 누적 시도 2회로 최소 탐색 + book 직교 개구부 "전무" 축(`reference_str1715_structure`) + KR 밸류업 정책(2024~) 카탈리스트(factor DB 내 구현 가능 여부 선확인 필요 — alt-data 금지 준수). ③ **liquidity provision** — 전종목 확장과 구조 시너지(small-cap 프리미엄), 단 capacity 주의.
- **n_trials**: 사전등록 grid 전체를 시행 *전에* 누적 계상(사후 cherry-pick 차단).
- **자원 배분 (도훈 결정)**: 기존 검증 레버(① 전종목 정식 forge ② overlay robust화)와 병렬 여부·착수 시점은 도훈 confirm 사안. Q 권고: 레버 ① 완료 후 E6-①(profitability)부터.

### 채택 보류
- **모듈 IR 음전 시 suspend (생존필터의 동적 버전)**: RCMA 기준③(IS·OOS 부호 지속)이 admission 레벨에서 이미 수행. 월중 동적 suspend는 사실상 타이밍이라 E1/E2 결과 본 후 판단.

---

## 4. 목표 체계 관련 (도훈 결정 사항 — Q 권고만)

제안의 단계적 목표(§8)는 2026-06-10 역량평가 권고("1차 목표 book SR 2.0 백테 + CAGR16 + MDD<25, SR 2.5는 제약완화 전제 stretch 분리")와 수렴. 현 위치 실측: book 1.709(full 267m)~1.95(admit window), +전종목 value 1.989(governor admit 대기), overlay robust화 포함 ~2.2 (estimated). **CLAUDE.md 제2목표(SR 2.5) 개정 여부는 도훈 confirm 사안** — 본 문서는 권고 기록만.

## 5. 실행 전제 (P0 — `project-architecture-audit-2026-06-10`)

현 머신은 미프로비저닝 클론: hook 0/46, Python 부재, 메모리 5종 미복원. **E1~E3는 R+arrow만으로 실행 가능**(arrow 06-10 설치 완료)하나, 착수 전 확인 필수: ① `.cache/unified_regime_signal_daily.parquet` / `regime_daily_v2.parquet` / module sim_result.rds 존재·신선도 ② QM_ROOT/CLAUDE_PROJECT_DIR 경로 (코드 기본값 `G:/Quant_Module_Moltbot` = 구 머신) ③ hook 수리 전이라 FR 모드(원래 hook 의존 낮음, governor 수동)만 안전.

## 6. n_trials 회계 (v1.2 — DSR selection_type 개정 반영)

n_trials/n_iterations **기록**은 전 실험 의무 유지. DSR **게이트**는 selection operator 기준 (`measurement-graduation §3` 2026-06-10 도훈 mandate):
- **sweep (DSR HARD 유지)**: E6 Stage A 사전등록 grid · FR 레짐grid/hyper sweep — 시행 전 grid 전량 계상.
- **chain (DSR 게이트 면제, 진단산출만)**: E1/E2/E3 단일 설계 A/B · 가설주도 순차개선 — 자격요건(IS-only 변형선택 + holdout 최종 1회 + iteration 사유 기록) 충족 시 `selection_type="chain"`.

## 7. 게이트 Calibration 백로그 C1~C3 (2026-06-10 적립 — 도훈 confirm 대기, 수치개정은 헌법 사안)

게이트 점검(도훈 질의)에서 확인된 긴장 3건의 수정 설계. 공통 원칙: **문턱을 낮추지 않고 통계량/결합구조를 고친다.**

### C1. oos_retention — 통계량 보강 + 사유 분리 (긴장: 비율 노이즈 ±0.4 + 과적합·decay 혼동)
- **(a) 다중 분할 중앙값**: 단일 65/35 → anchored 3분할 {55/45, 65/35, 75/25} retention의 **중앙값** (임의 절단점 노이즈 축소. 표본 노이즈 자체는 정보이론적 한계 — 제거 불가 명시).
- **(b) Borderline band + 보강증거 escalation**: retention ≥ 0.7 단독 PASS(불변) / **< 0.5 무조건 FAIL**(band 남용 차단) / **[0.5, 0.7) = 보강증거 2/3 충족 시 조건부 PASS**: ① trailing-subwindow(최근 40% 또는 2017+) PORT_t > 0 ② placebo p < 0.05 ③ book-marginal ΔSR > 0 (직교 cor < 0.30 동시). **holdout은 escalation 증거에서 제외**(최종 1회 봉인 원칙 위반 금지). — 전종목 value 0.601 판단(도훈 기허용 + 2017+ +1.41 + cor 0.005)을 규칙으로 성문화한 것.
- **(c) FAIL 사유 라벨 의무**: overfit-pattern(전략 고유 붕괴 — cohort 대비 특이) vs **decay-pattern**(동일 구간 cohort-wide 붕괴 — 예: 327팩터 2017+ 전멸) 진단 동봉. decay-pattern은 measurement-graduation §3 screening tier `screen_route`(FR_RCMA/era-limited)로 라우팅 — 자본 graduation은 여전히 불가, 단 "정직한 전략의 시대 탈락"과 "체리픽 탈락"을 같은 사형으로 처리하지 않음.
- **채택 전 검증**: 16후보 calibration + census 데이터 재채점 — value 0.601 구제 & false-accept 무증가 확인.

### C2. RCMA 희소국면 차단 해소 (긴장: ②n≥12 × ④t≥2 곱 → CRISIS 셀 IR≥1.4~2.0 요구, specialist 수학적 차단)
- **희소국면 정의**: regime base rate < 10% (실측 CRISIS·RISK_OFF).
- **완화 경로 (희소국면 셀 한정)**: ② n≥12 → **n≥6** / ④ t≥2 → **t≥1.5**, **OR 대체경로 = stress-pool 합산**(CRISIS∪RISK_OFF∪CAUTION 셀 합산 t ≥ 2 — admission 증거용만, dispatch는 세분 국면 유지).
- **강화 조건**: ⑤ 경제논리(AX-001 방어 메커니즘 명시)를 이 경로에선 의무-strict. ③ 부호지속 불변.
- **이중 방어 논거**: admission은 저위험 결정 — dispatcher shrink n/(n+36)이 n=6 specialist를 자동 저비중(≤14% 신호반영) + w_cap 0.25. 엄격 admission과 강 shrink의 이중 게이트가 차단의 원인이었으므로 한쪽(admission)만 완화.
- **채택 전 검증**: admission 재계산 → `run_wf_ensemble` A/B(변경 전후) — ensemble OOS 개선/불변이면 채택, 악화면 기각.

### C3. holdout — 해석 규율 명문화 (긴장: 18~24m SR SE ±0.7~0.8 → 유의성 검정 무력)
- 길이 불변(연장은 IS/OOS 잠식 trade-off). **판정 기준을 성과 기준 → 사전등록 예측구간 falsification으로 전환**: 채택 시점에 IS+OOS 블록 부트스트랩으로 holdout-길이 Sharpe **예측구간 [5%, 95%]를 사전 기록** → 실측이 5% 하단 미만 = FAIL / 구간 내 = PASS(저정보 명시) / 95% 초과 = PASS+.
- **소모 규칙**: holdout 조회 후 파라미터 재조정 시 그 holdout은 소모 — 새 봉인 구간 누적 전까지 재판정 금지. (chain 자격요건 ③과 정합.)
- **연장 개념**: 채택 후 페이퍼/라이브 트래킹 = holdout의 자동 연장 — monitoring agent가 동일 예측구간 대비 drift 추적 (라이브 0개월 공백 보완 경로).

**우선순위 권고**: C2(FR 모드 존재이유 직결) > C1(binding 게이트) > C3(문구·헬퍼만). 구현은 도훈 confirm 후 — C1/C2는 essence_score·regime_module_admission 코드 + A/B 실측 의무, C3는 규칙 문서 + 부트스트랩 헬퍼.

### 반영 상태 (2026-06-10 도훈 confirm "모두 반영" — 동일자 구현)
| 항목 | 상태 | 비고 |
|---|---|---|
| C1 | ✅ **반영·활성** — `essence_score.R` `oos_stat_version="v2"` 기본 + band escalation + `oos_fail_pattern` | 기능검증 6케이스 PASS (band 미증거 B / 2-of-3 A / 1-of-3 B / <0.5 증거무관 FAIL / 고retention A / v1 재현). splits 실측 [0.55,0.59,0.78] — 절단점 노이즈 실증. 16후보·census 재채점은 `_census_v2` 데이터(구 머신) 필요 — 후속 |
| C2 | ✅ **코드 반영, 기본 OFF** — `compute_rcma(rare_mode=)` + `RCMA_RARE_MODE` env | 합성 검증 PASS (CRISIS n=5.5m·IR 4.22: OFF 차단 → ON pool-path t 5.55 진입 / noise 차단 유지 / 비희소 판정 불변). **활성화 = run_wf_ensemble A/B 비악화 + 도훈 confirm** — 현 머신 `module_performance.json`·sim_result 부재로 A/B 불가, P0 수리 후 |
| C3 | ✅ **반영·활성** — `02_Infrastructure/contracts/holdout_falsification.R` 신규 (build/save/judge/mark_consumed) | book 실측 demo: 246m 기준 구간 [0.33,3.11], 최근 21m SR 2.92 → PASS_LOW_INFO (정확 분류). 불변성·소모 규칙 검증 PASS. **라이브 1호 사전등록**: `06_Registry/live_track/STR_1715_AR_on_M4_R05_overlay_PG2/holdout_interval.json` — 267m 기준 trailing-21m 구간 **[0.39, 3.16]** |
