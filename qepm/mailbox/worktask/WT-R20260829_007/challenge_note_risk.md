# challenge_note_risk.md — WT-R20260829_007 (risk-research)

**Self-Adversarial Challenge** (v8.2 규약 · Charter §8 No Silent Override).
`risk_package.json` 발행 직전 자기 적대검증. 각 concern = ACCEPT / PARTIAL / REBUTTAL + 근거 + 합리화 자기검증.
★정량 근거는 **진술이 아니라 재도출**했다 → `stage_artifacts/WT_R20260829_007/rk11_adversarial.R`.
★alpha 산출물은 한 글자도 수정하지 않았다(alpha_vector / confidence_vector / factor_specs read-only). 비중 제안 0건. 등급 선언 0건. 오버레이 0건.

---

## R1 — "특이위험 바닥 p10 은 조건수 정책(<500)을 통과시키려고 사후에 고른 값 아닌가"

**분류: ACCEPT**

인정한다. 발견 순서는 ①LW-Ω + Bayes-D 로 조건수 **556.8** 측정 → ②정책 문턱 500 초과 확인 → ③바닥 p10 도입 → ④301.9 로 통과다. **숫자를 본 뒤에 정규화 강도가 정해졌다.**

재도출(바닥 분위 6수준 전수):

| floor_q | 바닥 연율 | cond | book vol | TE(vs cap-w) | beta | pass<500 |
|---|---|---|---|---|---|---|
| 0.00 | – | 556.82 | 23.638% | 25.883% | 0.4409 | ✗ |
| 0.02 | 18.52% | 551.24 | 23.638% | 25.883% | 0.4409 | ✗ |
| 0.05 | 20.92% | 431.97 | 23.646% | 25.887% | 0.4410 | ✓ |
| **0.10** | **25.03%** | **301.91** | **23.674%** | **25.907%** | **0.4411** | ✓ |
| 0.20 | 29.04% | 224.16 | 23.717% | 26.215% | 0.4347 | ✓ |
| 0.30 | 31.80% | 186.97 | 23.771% | 26.558% | 0.4278 | ✓ |

정책 통과 최소치는 **p05(431.97)** 이고 나는 그보다 강하게 눌렀다.

**처리**: `diagnostics.specific_risk_floor_sensitivity` 에 표 전량 + "사후 선택" 문장을 먼저 적었다. challenge_flags 에도 동일 문구를 실었다.
**합리화 자기검증**: 보고 수치가 바닥 0 대비 상대 0.15% 이내로만 움직인다는 사실이 있다. 그러나 **그것을 면죄부로 쓰지 않는다** — "영향 미미하니 괜찮다"는 금지 표현이고, 실제 부작용은 다른 곳에 있다: **347종 중 35종의 특이위험이 인위적으로 상향**되어 최소분산·위험예산형 목적함수가 그 35종을 덜 선호하게 된다. 이건 optimizer 에게 보이는 실제 왜곡이므로 handoff 의 known_weaknesses 에 명시했다.

---

## R2 — "walk-forward bias 에서 direct_sample(1.066)이 선택 추정기(0.858)보다 1 에 가깝다. 추정품질으로 졌는데 왜 골랐나"

**분류: REBUTTAL**

재도출(199개월 walk-forward, 보유 25종 EW book):

| 추정기 | bias = sd(z) | \|bias−1\| |
|---|---|---|
| direct_sample | 1.0659 | **0.0659** |
| direct_lw_nls | 1.1069 | 0.1069 |
| struct_sample_omega | 0.8726 | 0.1274 |
| **struct_lw_omega (선택)** | **0.8575** | 0.1425 |
| direct_lw_linear | 2.1939 | 1.1939 |

숫자는 인정한다 — **25종 고정 도메인에서는 direct_sample 이 이긴다.** 그러나 이 검증의 도메인과 **결정의 도메인이 다르다**. optimizer 가 선택할 수 있는 자산은 alpha_vector 전량 **347종**이고, 거기서 direct_sample 은 min_eig **−2.574e-17** 로 PD 가 아니다(cond 5.59e+15). 즉 "더 나은 추정기"가 아니라 **존재하지 않는 추정기**다. direct 계열이 347 도메인을 못 덮는다는 것은 코드 사정이 아니라 표본 사정이다 — 완전이력 종목이 **139/347(40.1%)** 뿐이고 창은 120개월이라 p>n 이 구조적이다.

세 가지 부수 실측을 함께 기록한다:
- linear LW 는 347 도메인에서 `.get_cor_cov` 자체 가드가 발화한다(rho=1.000 cap binding → cond 1.000, 상관구조 전멸).
- **v8.3.1 posterior 의 "WT-시점 소규모(p≤25) Σ = linear LW 무해"는 본 book 에서 반증된다** — p=25·n=60 에서 bias 2.194 로 위험을 2.2배 **과소**예측한다. 무해가 아니라 유해다. (posterior 를 뒤집자는 제안이 아니라, 본 후보 소비 시 예외를 기록한다.)
- 반대로 **FQ-057 P1c 의 "lw_nls 가 총분산 채널에서 강건 우월"은 재현된다**(1.107 vs 2.194).

**처리**: `diagnostics.methods_tried` 5건 전부에 도메인·조건수·bias·기각사유를 적었고, `walkforward_bias_test.verdict` 에 위 반증/재현을 병기했다.
**합리화 자기검증**: 선택 추정기가 위험을 14% **과대**예측하는 것을 "보수적이니 안전하다"로 넘기지 않는다. 과대예측은 평균-분산 목적함수에서 **위험자산 비중을 체계적으로 낮추고 종목 간 상대 순위를 왜곡**한다. bias 0.858 은 통과가 아니라 **기록된 오차**다.

---

## R3 — "구간별 Ω(2005-14 / 2015-19 / 2020-26)는 사후 라벨이다. C1 위반 아닌가"

**분류: REBUTTAL (경계 명시 조건부)**

두 층으로 분리했다. **발행 Σ 는 확장창 단일 추정(2005-02~2026-08, LW-Ω)이고 구간 Ω 를 소비하지 않는다** — `model.omega` 가 그 사실을 못박는다. 구간 Ω 는 `risk_summary.regime_heterogeneity` 안에만 있고 `measurement_note` 에 "후향적 구조 진단"이라고 먼저 적었다.

그리고 절단점 자체가 결과를 만든 것 아닌지 **라벨 없는 창으로 재확인**했다(rolling 36개월):

| 축 | 라벨 없는 rolling36 | 절단점판 |
|---|---|---|
| book 변동성 max/min | 26.92% / 14.99% = **1.80배** | 27.72% / 17.34% = 1.60배 |
| 평균 pairwise 상관 max/min | 0.2212 / 0.0895 = **2.47배** | 0.1691 / 0.1127 = 1.50배 |

라벨을 없애면 이질성이 **더 커진다**. 절단점의 산물이 아니다.

**★이 재확인이 새 결손을 하나 드러냈다**: rolling36 book 변동성의 **표본 최댓값이 바로 지금**이다(2026-08 = 26.92%, 2026-07 = 26.66%). 확장창 Σ 는 정의상 전 구간 평균이므로 **현재 국면 위험을 과소 표시한다.** 이건 수리한 게 아니라 남은 결손이고, PIT-청정 국면 분류기 없이는 메울 수 없다.

**처리**: `regime_heterogeneity.label_free_cross_check` 신설 + `current_regime_warning` + challenge_flags 3번째 자기적대 항목.

---

## R4 — "전략 신호(SIGNAL)를 위험요인에 넣었다. alpha 를 위험으로 재해석한 경계 위반 아닌가"

**분류: PARTIAL**

인정할 사실: **정의 선택이 위험 수치를 바꾼다.** 재도출(SIGNAL 제외 재구성, D 고정):

| | 포함(발행판) | 제외 |
|---|---|---|
| condition number | 301.91 | 295.71 |
| 예측 book 변동성 | 23.674% | **25.452%** |
| 요인 설명분 | 89.41% | 90.83% |
| TE vs cap-w | **25.907%** | 23.262% |
| 예측 beta vs cap-w | **0.441** | **0.555** |

기전은 특정된다: corr(MKT, SIGNAL)이 구간별 **−0.219 ~ −0.534** 로 음(−)이고 book 의 SIGNAL 노출이 **+1.72σ** 라, 신호 노출이 시장위험을 상쇄한다. 그래서 요인으로 실으면 총변동성이 1.78%p 내려가고 TE 는 2.65%p 올라간다.

반론 근거: (a) SIGNAL 요인수익은 **단면회귀에서 기계적으로 나온 값**이지 내가 α̂ 를 해석해 만든 값이 아니다. (b) book 이 실제로 +1.72σ 실린 **공통 노출**을 위험모형에서 빼면 그 분산이 D 로 위장되어 "독립 잡음"으로 오인된다 — 그게 더 위험하다. (c) BARRA 계열 다요인 모형의 표준 관행이다.

**처리**: `diagnostics.sensitivity_signal_as_risk_factor` 에 양쪽 수치 전량 + "무해하지 않다" 판정을 적고, handoff 에 "TE 예산 2.65%p 가 이 정의 선택에 걸려 있다"를 명시했다. alpha_vector 는 손대지 않았다.
**합리화 자기검증**: "표준 관행이니까 괜찮다"로 끝내지 않았다 — 관행 여부와 무관하게 수치가 갈리므로 갈린 양을 그대로 실었다.

---

## R5 — "crowding flag 0 건이다. 군집 위험 없음인가"

**분류: ACCEPT**

아니다. 5개 팩터 crowding_score 는 0.252~0.419 로 전부 0.75 미만이고 3M delta 최대 +0.078(<0.15)이라 flag 가 0 이지만, **합성점수의 4개 성분 중 2개가 퇴화했다**:
- `vol_concentration` = **0.000 (5/5 팩터 전부)** — 함수의 중립 기준선이 n_universe = **3,925**(RAWDATA 전 종목)로 잡혀 mandate 유니버스 347종 대비 희석된다. top-25 거래대금 점유가 25/3925 = 0.64% 를 못 넘으면 0 으로 클립된다.
- `passive_overlap_proxy` = **1.000 (포화)** — mandate 유니버스가 곧 K200∪KQ150 이라 top-25 가 항상 벤치 구성원이다.

즉 실질 변별은 HHI·elasticity **2축뿐**이다. 낮은 점수를 "군집 없음"의 강한 증거로 읽으면 안 된다.

**처리**: challenge_flags 9번째 항목에 성분별 퇴화를 명시. 점수 자체는 계약대로 `crowding_score_per_factor` 에 전량 기재(5팩터 × 6성분 + 3M delta).

---

## R6 — "RF-R1(top risk > 40%)이 72.4% 로 발화했다. 이건 실패 아닌가"

**분류: PARTIAL**

발화는 사실이다(총위험 기준 MKT 72.37%). 그러나 **롱온리·w≥0·Σw=1 인 25종 book 의 총위험에서 시장을 뺄 방법이 없다** — 형태가 그 노출을 담는다(measurement-graduation §3 의 무신호 대조 논리와 같은 자리). 같은 Σ 로 **active(vs cap-w)** 를 재면 top 은 SECTOR **26.24%**, 그 다음 SIZE 19.03%, SIGNAL 17.84% 이고 **MKT 는 0.00%**(active 시장노출이 정의상 0)다. 40% 문턱은 active 축에서만 의미를 갖는다.

**처리**: `top_common_risks` 를 총위험·active(cap-w)·active(EW-uni) **3기준 전량** 기재. challenge_flags 첫 항목에 "40% 문턱은 active 축에서만 의미가 있다"를 적었다. **문턱을 낮춰달라고 요구하지 않았다**(INV-7).

---

## R7 — "조건수 301.9 < 500 통과를 안전 신호로 읽는가"

**분류: REBUTTAL (문턱의 성질 정정)**

Σ = BΩB' + D 의 조건수는 **자산수 N 에 선형으로 커진다** — 공통 시장요인 방향의 최대 고유값이 ≈ N·σ²_MKT 이고 최소 고유값은 특이위험 바닥에 묶이기 때문이다. 실측이 그대로 보여준다: 동일 추정기가 **25종 walk-forward 에서는 조건수 중앙 42.2**, 347종에서는 301.9 다. 500 은 N-불변 상수가 아니다.

**처리**: challenge_flags 2번째 항목에 "문턱을 N-불변 상수로 읽지 말 것"을 명시.

---

## R8 — "상류 handoff 수치가 alpha 자신의 diagnostics 와 다르다. 조용히 지나갈 것인가"

**분류: ACCEPT (No Silent Override)**

`handoff_to_risk.known_weaknesses_for_downstream` 는 "편도 **768%**/yr · beta **0.766**" 을 싣고 있으나, 같은 패키지의 diagnostics 는 `turnover_proxy` 15.2326(= 편도 **761.6%**/yr) · `beta` **0.73724** 다. alpha 자신의 challenge_flags[11] 이 762%/yr 로 정정했으므로 handoff 블록이 **정정 전 값을 남긴 것**으로 보인다.

**처리**: 본 패키지는 diagnostics + 원장(`period_returns_production.csv::traded_notional`)에서 재도출한 값(two-way 1523.6%/yr · 편도 761.8%/yr · 손익분기 편도 **40.5bps**)을 썼다. **alpha 산출물은 수정하지 않았다.** 불일치는 challenge_flags 7번째 항목에 기록하고 `wt_record_challenge_review(objection=TRUE)` 로 governance_log 에 남겼다.

같은 범주로 **cap-tier 정의 갈림**도 기록했다: 본 패키지 tier = 월별 유니버스 Size 3분위(MEGA 비중 0.459), alpha 의 `diag_cap_tier` = rank 기반(MEGA=top10 / MID=11-30 / OTHER, 비중 0.838). **값 충돌이 아니라 정의 차이**이며 두 정의를 모두 기재했다.

---

## R9 — "detect_lookahead 가 1건 발화했다"

**분류: ACCEPT (기록) / 영향 REBUTTAL**

risk 스크립트 12개 전량 스캔 결과 11개 0건, `rk8_tail_stress.R:74` 에서 C1 1건 — 회전 비용격자의 **사후 SR 요약**(`sd(rn)*sqrt(12)`)이다. 이 값은 Σ·노출·특이위험·선별·비중 어디에도 입력되지 않는다(비용 민감도 표의 서술 열). **위반 주입 없이 발화한 것은 검출기 생존의 양성 대조**이며, alpha 층의 2건과 같은 범주다.

**처리**: `pit.checks.detect_lookahead` 에 파일·줄·문구·미소비 경로를 명시.

---

## 합리화 자기검증 (금지 표현 스캔)

`risk_package.json` + 본 노트에서 "영향 미미 / 관행적 허용 / 보수적이면 괜찮다 / 대부분 결과 동일 / 이미 반영되어 있었을 것 / 백테스트 기간이 충분히 길어서 상쇄" 를 판정 근거로 쓴 자리 **0건**.
가장 위험했던 두 자리를 명시적으로 뒤집었다:
1. R1 의 "수치가 0.15% 밖에 안 움직인다" → 면죄부가 아니라 **35종 특이위험 상향이라는 실제 왜곡**을 대신 적었다.
2. R2 의 "bias 0.858 은 보수 방향" → 안전이 아니라 **기록된 14% 과대예측 오차**로 서술하고 목적함수에 미치는 방향(위험자산 비중 하향·상대순위 왜곡)을 적었다.

## Escalate trigger 점검

| 조건 | 상태 |
|---|---|
| HIGH ≥ 5 | RF-R1 1건(총위험 축). RF-R2 해소·RF-R3/R4/R5 미발동 → **미달** |
| AX axiom hard FAIL ≥ 3 | 0 |
| PIT hard violation | 0 (C1 발화 1건은 미소비 사후요약 — hard 아님) |
| **Σ PD violation** | **없음** — min eigenvalue 5.219e-03 > 0, 347×347 전역 PD |

→ **Q-Lead escalate 불요.** 체인은 optimizer 로 진행한다(음성 위에서도 완주 — 도훈 지시 2).

## AX-008 Verification Triangulation

본 self-adversarial 은 3-source 중 1개다. 나머지 2개(Forge 재현 · Architect/optimizer 소비 검증)는 하류에서 채워진다. 본 라운드의 자체 재현 대조는 **일간 book 재구성 → 월 집계 vs `period_returns_production.csv::ret_gross` 최대오차 0.00000 (259/259 월 일치)** 이다.
