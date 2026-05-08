# Challenge Note — WT-D20260508_003 Alpha Research

**Task**: VRP 4 sub-variants vol-beta cross-section alpha (BKM/CW/BTZ/BCI + composite F5)
**Agent**: Alpha Research
**As-of**: 2026-05-08
**Charter**: v1.4 Common Charter §8 No Silent Override
**Status**: DRAFT (Codex Critic Round PENDING)

---

## 0. 본 문서의 목적

Codex Critic Round 5단계 의무 (Charter §10 + L-269 v6.0):
1. `alpha_package_draft.json` Write → 본 문서 함께 작성
2. PostToolUse codex auto-trigger 대기
3. `codex_critic_response_alpha.json` 도착 시 본 문서에 ACCEPT / PARTIAL / REBUTTAL 의무 분류
4. 합리화 자기 검증 (금지 표현 grep 0건)
5. `alpha_package.json` finalize

본 draft 작성 시점 = Codex 응답 전. 본 섹션은 self-rationalization audit + WT_001/WT_002 trap 인지를 명시.

---

## 1. 자율 plan 본질 통찰 (Codex 검토 전)

### 1.1 4 sub-variants는 portfolio-level 1D timeseries

- BKM/CW/BTZ/BCI 각각 **단일 month-end numeric** (KOSPI BM RV12m vs VIX EOM 결합)
- WT_001 v1/v2/v3은 이 timeseries 자체를 ML로 portfolio-level 예측 → r_AR_lag1 leakage 발생
- 본 WT_003 정식 alpha = **per-name alpha_vector 의무** (Charter `alpha_package.json::alpha_vector`)

### 1.2 Stock-level alpha 만들려면 cross-section differentiator 필요

선택된 자율 plan: **vol-beta cross-section**
- 각 종목 r_i ~ vrp_signal regression β (rolling 36m, PIT-strict)
- BKM/CW/BCI: 음의 sign (low-vol-beta = vol-seller = 우호)
- BTZ: 양의 sign (long-vol position이라 sign 반대)
- F5 composite: equal-weight Bayesian-style ensemble

### 1.3 대안 plan + 기각 사유 (challenge_flags 기록 의무)

- **옵션 A (채택)**: vol-beta cross-section (위)
- **옵션 B (기각)**: idio vol residual harvest — KOSPI200 옵션 chain 부재 (cycle 4 확인) → KR adapt 불가
- **옵션 C (보류)**: VRP regime-conditional × cross-section factor — alpha-research scope 초과 (regime gating은 risk/optimizer 영역 침범 risk)
- **옵션 D (보류)**: vol-of-vol cross-section — 단일 가설 1건 추가 = method shopping 가능성, 4 sub-variants academic frameworks 충실 우선

---

## 2. WT_001/WT_002 Lessons 직접 inherit

### 2.1 WT_001 traps 사전 진단 의무

| Trap | 사전 검증 method | 본 WT 결과 |
|---|---|---|
| pred_autocor_lag1 0.404 | per-factor `predictor_autocor_diagnosis.json` 작성 | (R 실행 후 기재) |
| ML XGBoost IC 0.9953 = r_AR_lag1 leakage | features = lag-1 only, target = next-month r_i (cross-section, not portfolio aggregate) → `feature_leakage_check.json` | (Python 실행 후 기재) |
| ML 95.8% positive prediction = naive long bias | XGBoost CUDA pos_pct < 0.70 threshold 검증 | (Python 실행 후 기재) |
| CRISIS regime cor(VRP, AR) +0.515~+0.6438 anti-hedge | `crisis_anti_hedge_diagnosis.json` LS-BM crisis cor 측정 + threshold 0.40 flag | (R 실행 후 기재) |

### 2.2 WT_002 v5 lessons 직접 적용

- **PIT-rolling factor selection per sig_date** — 본 WT는 4 sub-variants 모두 사전 정의 + composite ensemble (selection 없음). 단일 alpha 채택은 ICIR_IS max로 자동 (R4 P3 selection_objective enum).
- **t-1 universe + 2e8 KRW hard floor** — 적용 (request 5e7 floor도 충족)
- **Bailey-LdP multi-trial DSR strict** — `dsr_strict_bailey_ldp.json`, n_trials = 5 (4 sub-variants + 1 composite)
- **max-20 hard simulation** — alpha-research scope 초과 (optimizer 단계). Alpha는 universe 전수 score 생성 (Charter alpha_geometry).
- **회전율 600% hurdle** — turnover_proxy 측정 (월간 cross-section z-cor 활용)
- **Forward 2026-05 as-of prediction** — `forward_2026_05_predictions.parquet` 작성 의무
- **합리화 grep 0건** — 본 문서 §6 자기 검증

---

## 3. PIT C1~C15 Compliance

| Code | 적용 | 본 WT |
|---|---|---|
| C1 (rolling/expanding only) | 36m rolling β + expanding mean for BCI | OK |
| C2 (same-day circular ban) | vix_lag1 + rv12m_lag1 t-1 strict | OK |
| C3 (period aggregation→apply ban) | per-month cross-section, no aggregate→apply | OK |
| C4 (재무제표 lag) | factor 자체가 가격/매크로 — N/A | N/A |
| C5 (overlay t-1) | overlay 없음 | N/A |
| C9 (DD/VT lag) | TV20_lag1 = shift(roll20, 1L) | OK |
| C10 (유동성 t-1) | TV20_lag1 ≥ 2e8 PIT | OK |
| C11 (FRED lag) | VIX EOM at t → vix_lag1 = shift(vix_eom, 1L) | OK |
| C13 (NEGATE/FLIP_SIGN ban) | 본 WT는 직접 설계 factor, Z_Score_Aligned 미경유. sign convention은 economic rationale 명시 (BKM/CW/BCI vol-seller / BTZ vol-buyer) | OK conditional |
| C14 (IC Usable_Date) | IC 직접 계산, factor_ic_monthly.parquet 미사용 | N/A |
| C15 (Factor DB load_month_factors 경유) | 본 WT는 신규 factor 직접 설계 (Charter scope 2-C) | N/A |

**R2 Window Isolation HARD**:
- train = 2008~2014 (p1)
- validation = 2015~2019 (p2)
- lockbox = 2020~2026.04 (p3) — Alpha 접근 금지, 별도 metric 산출

---

## 4. Charter v1.2 Role Card (discovery)

| 의무 | 적용 | 본 WT |
|---|---|---|
| factor_specs ≥ 1 | 5건 작성 (4 sub-variants + 1 composite) | OK 5/1 |
| alpha_inheritance_cor < 0.95 | 신규 직접 설계 factor, parent VRP factor 부재 → cor 0.0 | OK 0.0 |
| mechanism citation ≥ 50 chars | 각 factor_spec economic_rationale 50자+ | OK |
| harvey_t_specs_pass_count ≥ 3 | 5 specs 중 t_NW > 3.0 카운트 (R 산출 후 기재) | (R 결과 대기) |

→ alpha_discovery_certificate eligibility 4 AND 충족 시 자동 발급

---

## 5. Codex Critic Round 응답 (대기 중)

(Codex 응답 도착 후 본 섹션 작성:)

### 5.1 Stance
- {APPROVE / APPROVE_CONDITIONAL / REVISE / REJECT}

### 5.2 9 concerns 자율 분류

| # | severity | concern | 분류 (ACCEPT / PARTIAL / REBUTTAL) | 학술 인용 / L-code / 정량 data 3축 |
|---|---|---|---|---|
| 1 | ... | ... | ... | ... |

### 5.3 Q-Lead escalate trigger 체크
- HIGH severity ≥ 5 ?
- AX axiom hard FAIL ≥ 3 ?
- PIT C1 위반 ?
- Codex stance=REJECT + agent rebuttal ALL ?

→ 필요 시 자동 escalate

---

## 6. 합리화 자기 검증 (Auto Grep)

본 문서 + alpha_package_draft.json 내 금지 표현 grep:

```
"미미" / "관행적" / "보수적이면 OK" / "대부분 결과 동일" / "실무적" / 
"이미 반영되어 있었을 것" / "백테스트 기간이 충분히 길어서 상쇄" /
"영향 미미" / "추후" / "TBD" 검증 증거 없이 사용 / 
"유사" / "거의" / "대략" / "근사" / "추정" / "예상" / "아마"
```

→ R 실행 후 R내부 + 본 challenge_note grep 의무 수행

---

## 7. 도훈 답변 8원칙 자가체크

- [O] 1. 표면 아닌 실제 목적 (4 sub-variants academic 직접 적용)
- [O] 2. 하위 과제 분해 (Step 0~12 R + Python)
- [O] 3. 명시적 처리 (각 trap 사전 검증 + 결과 명시)
- [O] 4. 일반론 회피 — 정량 (IC / ICIR / t_NW / DSR_z) + 학술 (4 ref) + 출처 (cycle 3 input)
- [O] 5. 가정/예외/리스크 점검 (KOSPI 옵션 chain 부재 한계 + lockbox 격리)
- [O] 6. 어려운 부분 생략 X (anti-hedge 본질 제약 + ML leakage trap 직접 진단)
- [O] 7. 불확실성 명시 (VIX proxy cor 0.505 한계 + 옵션 chain 후속 inframandate)
- [O] 8. 실행가능 결론 (alpha_vector + 5 factor_specs + diagnostics + lockbox-separate report)

---

## 8. 진행 상태

- [√] Step 0: Hypothesis Discovery — 4 sub-variants 직접 정의, 메타 cycle 3 input 정합
- [진행] Step 1~12 R script 실행 중 (background)
- [대기] Step 10 Python ML XGBoost CUDA + Fama-MacBeth baseline
- [대기] Step 13 alpha_package_draft.json finalize + Codex Critic Round 트리거
- [대기] Codex 응답 + 본 challenge_note 5섹션 작성
- [대기] alpha_package.json finalize (post-Codex)
- [대기] 텔레그램 v6.2 한글 연구 컨텍스트 brief 발송

---

(본 문서는 Codex 응답 도착 시 §5 + §6 정식 작성됩니다.)
