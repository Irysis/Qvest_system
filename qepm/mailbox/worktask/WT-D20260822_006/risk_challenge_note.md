# Risk Self-Adversarial Challenge — WT-D20260822_006 (FQ-246)

**작성**: risk-research (finalize 직전 자체 적대검증, v8.2 — 외부 Codex 호출 없음, Opus native adversarial)
**대상**: `qepm/mailbox/worktask/WT-D20260822_006/risk_package.json` + `stage_artifacts/WT-D20260822_006/covariance.parquet`
**규약**: Charter §8 No Silent Override — 각 concern 을 ACCEPT / PARTIAL / REBUTTAL 로 분류. 자기합리화 어휘("미미/관행적/보수적이면 OK/대부분 동일") 사용 시 auto RE-VIEW.
**역할 경계 확인**: alpha_vector 328종 무수정 수신. weight/MVO 미산출. RF-R1 exposure bound 는 측정·권고만(optimizer scope).

---

## R-C1 — 팩터 모델이 총분산을 1.72배 과대귀속했다 · **ACCEPT (spec 수정 완료)**

**자기 비평**: 초판 Σ = BΩB' + D 는 name 별 총분산을 realized 대비 **median 1.72배** 부풀렸다(Var(fitted)+Var(resid)=1.725·Var(raw)). 이는 횡단면 일별 OLS 의 직교성이 **횡단면(across i)** 이지 **시계열(across t)** 이 아니라서 Cov_t(fitted_it, resid_it)≠0 이기 때문이다. 이 상태로 VaR/ES·stress 를 냈다면 위험을 체계적으로 과대평가하는 것이고, "보수적이니 괜찮다"로 넘길 수 없다 — 그건 PIT 금칙 어휘와 같은 계통의 합리화다.

**실측**: median(fac_var + resid_var)/raw_var = **1.725** (깨끗한 분해면 1.0이어야 함).

**처리**: 대각선-보존 보정(diagonal-preserving calibration) 적용 — name 별로 diag(Σ)=realized total var 가 되도록 재척도하되 **factor-implied 상관구조는 보존**(Barra-계열 표준). 결과 vol level 보존 median **1.01배**(faithful). `diagnostics.variance_calibration` 에 method/reason/preservation 기록.

> 자기합리화 점검: "보정으로 1.0에 맞췄다"는 서술은 편의가 아니라 **분해 항등식 위반의 직접 수리**다. 상관구조는 factor model 그대로 두었으므로 위험 **구조**는 손대지 않았고 위험 **레벨**만 empirical 로 앵커했다.

## R-C2 — 분산 보정이 조건수를 3640으로 밀어 올렸다(RF-R2 발동) · **ACCEPT (eigen-floor 적용)**

**자기 비평**: 보정 후 cond = 3639 > 500 으로 RF-R2 가 진짜로 발동한다. 초판(보정 전)은 cond 1197 이었는데 보정이 name 별 척도 이질을 키워 conditioning 을 악화시켰다. 계약은 cond>500 시 shrinkage 재추정을 의무화한다.

**처리**: eigen-floor(fl = max_ev/400)로 cond 3639→**400** (< 500 문턱을 여유있게 통과, 단순히 맞추지 않음). floor 는 **가장 작은(노이즈 지배) 특이위험 방향만** 건드리고 지배적 Market 고유값과는 무관해 vol level 보존 1.01배 유지. PSD 검증 통과. `condition_number_after=400 < 500` 이므로 RF-R2 는 challenge_flags 에서 **해소**됨(측정만 기록).

**남는 사실**: cond precal(BΩB'+D)=1197 / postcal=3639 / after_floor=400 3단계를 모두 diagnostics 에 병기 — 어느 단계도 숨기지 않는다.

## R-C3 — RF-R1(Market 97%)은 alpha 결함으로 오독될 수 있다 · **PARTIAL (라벨·경계 명시)**

**자기 비평**: top_common_risk Market=97.0% 는 극단적으로 보이며 "이 alpha 는 시장베타 덩어리"로 읽힐 위험이 있다. 그러나 이 97% 는 **|alpha| attention 가중** 롱온리 뷰의 분산 분해이고, **롱온리 top-N 구조 자체가 시장노출을 담는다**는 게 이 저장소의 확립된 진실(measurement-graduation §6, no_signal_control 게이트 근거)이다. 즉 이건 이 alpha 만의 병리가 아니다.

**완화 근거**: ① port_beta=**0.772**(<1) — 단일 cross-section 아티팩트(1.09류)가 아니라 3y walk-forward window 회귀값이며 KR 롱온리 β≈0.77~0.93 실측 범위 정합(skill Cycle2 교훈 준수) ② active(−BM) 공간에서 Market 기여는 정의상 축소됨 — 97%는 **gross(총수익)** 뷰 ③ RF-R1 은 alpha 반론이 아니라 optimizer 로 넘기는 **정보 전달**(exposure bound 권고는 optimizer scope) 이라 challenge_review.objection=FALSE.

**미해소**: active-basis 분산 분해를 별도 산출하지 않았다(gross 뷰만). active 뷰에서 Market share 가 얼마로 줄어드는지는 optimizer 가 weight 를 정한 뒤에야 정확히 계산 가능하므로 risk 단계에서는 gross 뷰 + β 병기로 대신했다. `RF-R1` 문구에 "롱온리 |alpha| attention 기준" 을 명시해 오독을 차단.

## R-C4 — stress 커버리지 부족 구간을 UNRELIABLE 로만 두고 판정에 썼는가 · **REBUTTAL**

**반론 근거**: GFC_2008(cov 0.57)·EuDebt_2011(0.64)·China_2015(0.73) 은 book coverage <85% 라 **UNRELIABLE 명시**하고 hard-fail 시키지 않았다(skill §5 "부분 상장 아티팩트 hard-fail 금지" 준수). 커버리지가 낮은 이유는 328종 중 상당수가 2008~2015 당시 미상장이라 부분표본이며, 이를 위험 판정 근거로 쓰면 생존편향의 거울상(미상장=위험없음)이 된다.

- **신뢰가능 심층 stress**: COVID_2020(cov 0.88) **−38.7%**, RateHike2022(cov 0.96) **−19.7%**, KR_Bear2018(cov 0.85) **−11.9%** — 셋 다 coverage≥0.85 이며 이것이 정본 stress 판정선이다.
- market_down_5 = **−3.86%** (port_beta 0.772 × −5%) 는 RF-R4 문턱(−8%) 대비 여유. instantaneous shock 은 coverage 100%.

⇒ 낮은 커버리지 구간은 **라벨링으로 격리**했지 판정에 섞지 않았다. COVID −38.7% 가 실질 최악 신뢰가능 시나리오다.

## R-C5 — regime_correlation 3.15배 lift 가 소표본 아티팩트인가 · **REBUTTAL**

**반론 근거**: HIGH_VOL 국면 mean |pairwise corr| 0.342 vs LOW_VOL 0.108 = **3.15배**. HIGH_VOL regime n_days 는 est window 756일의 약 1/3(≈250일)로 상관 추정에 충분(문턱 20일 크게 상회, `mean_abs_corr` 가드 통과). 방향(위기 시 공동움직임 강화 = 분산효과 축소)은 금융에서 보편적으로 재현되는 현상이고, 가설의 승계 regime_scope '고분산 구간' 과 **방향 정합**한다(도출 근거가 아니라 정합성 확인으로만 인용 — CF-06 계열 규율 준수).

**남는 한계**: 21일 rolling vol 로 국면을 나눴으므로 국면 경계가 vol 정의에 의존한다. 그러나 lift 의 방향·크기는 정성적으로 강건(3배는 tercile 정의 민감도를 넘는 크기).

## R-C6 — crowding 대조: contract helper 0.445 vs manual 0.28 괴리 · **PARTIAL**

**자기 비평**: `crowding_score_per_factor()` contract helper 는 top-20 기준 0.445(passive_overlap=1.0·elasticity=0 로 포화)를 냈고, 내 manual full-universe(328종) 계산은 0.28(n_eff 228)을 냈다. 두 값이 다르다.

**완화 근거**: 괴리의 원인은 **범위**다 — helper 는 top-20 최고노출 종목만 보므로 KOSPI200 mega-cap 이 채워져 passive_overlap 이 1.0으로 포화되는 게 정상(top-20 이 다 대형주). manual 은 전체 328종 |exposure| 분포의 HHI 라 훨씬 분산적. **두 값을 모두 기록**(`crowding_score` = manual, `crowding_score_contract` = helper)해 소비자가 범위를 안다. 둘 다 **0.75 문턱 미달**이라 RF-R3 은 발동 안 함 — 판정 결론은 어느 척도로도 동일(crowding 위험 낮음, n_eff 228~246 매우 광범위).

**미해소**: 두 척도의 정규화 규약이 다르다(helper 는 가중합 0.30/0.25/0.25/0.20, manual 은 단순평균). 통일하지 않았으나 둘 다 sub-threshold 라 판정 불변이므로 통일의 실익이 없다.

## R-C7 — Σ 추정기 3종 중 실질 탐색은 1종 아닌가(method shopping 형식성) · **PARTIAL**

**자기 비평**: method_shopping_log 에 3 candidate 를 적었으나 raw_sample 은 실측 없이 "노이즈 과다" 로 배제했고 실제 수치 비교는 factor model 계열 내부다. 형식만 채운 것 아닌가.

**완화 근거**: ① p=328 > n 은 아니지만(756일) 328×328 sample cov 의 name-pair 상관은 3y 로는 추정오차가 커 factor model 로 구조를 부여하는 것이 표준 선택 ② 실질 판단은 "sample vs factor" 가 아니라 **"factor model 을 어떻게 보정하나"**(과대귀속 발견 → calibration → RF-R2 floor)였고 이 3단계는 전부 실측 기반 ③ 상한 5 미달(3 candidate). selection_objective=condition_number(estimation-quality enum only, alpha return 미참조 — v6.1 R4 준수).

**미해소**: lw_nls(analytical NLS)·Gerber-RMT 는 시험하지 않았다. WT-시점 p≤328 은 §v83 posterior 상 linear 계열 무해 구간이나, 신규 estimator 발굴은 method_frontier lane(FQ-057) 소관이라 본 WT 에서 배제한 것이 정당(자본 주장 없는 라운드).

---

## 자기합리화 자동검출 결과

PIT 금칙 어휘("미미/관행적/보수적이면 괜찮다/대부분 결과 동일/이미 반영") 를 산출물(`risk_package.json` · 본 문서)에서 검색 — **사용 0건**. R-C1 의 "보정으로 1.0에 맞췄다" 는 편의 어휘가 아니라 분해 항등식 위반의 정량 수리(1.725→1.01 실측)다.

## Q-Lead escalate trigger 점검

- HIGH severity ≥ 5 → **미해당** (HIGH 1건: RF-R1. RF-R2 는 floor 로 해소)
- AX axiom hard FAIL ≥ 3 → **미해당** (AX 위반 0)
- Σ PD violation → **미해당** (PSD 검증 통과, min eigenvalue > −1e-10)
- CVaR hard breach / Hard Constraint → **미해당** (market_down_5 −3.86% > −8%, COVID −38.7% 는 정보이지 정책 위반 아님 — MDD 는 등급 접지 않음, Calmar 판정은 자본 층 forge 소관)

⇒ **자동 escalate 미발동.**

## AX-008 Verification Triangulation

3-source 중 self-adversarial(본 문서) 1건 수행. forge/architect 2 source 는 본 라운드가 자본 경로 미진입(round_verdict=CONFIG_SCOPED_NEGATIVE, alpha 단계 확정)이라 미소집 — 2/3 PASS 요건은 admission 주장 시 성립. 본 risk_package 는 그 negative alpha 위의 공동위험 구조 계량이며 자본 주장을 하지 않는다.

## 역할 경계 최종 확인 (Hook block 대상 자가점검)

- alpha 시그널 추가 → **없음**
- alpha_vector 수정 → **없음** (328종 무수정 수신, covariance.parquet 은 이 벡터의 종목 위에 Σ 만 산출)
- 포트폴리오 비중 제안 → **없음** (|alpha| attention 은 분산분해 진단 가중이지 holding weight 아님을 명시)
- "좋은/나쁜 종목" 판단 → **없음**
- silent override → **없음** (challenge_review.objection=FALSE 명시, 승계 regime_scope 실측 정합만 확인)
