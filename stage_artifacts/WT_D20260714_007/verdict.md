# R31 (FQ-047) Verdict — 밸류 정의 스펙트럼 확장 × B2 tier-조건부 (밸류 아크 완결 라운드)

**부모 체인**: R26..R30(FQ-045) → FQ-046 dossier(judge REJECT·incumbent RETAIN) → **R31(FQ-047)**.
**base 권위**: clean `0_stored_S7` (WT_004 recon_panels, production_parity_verified, off0 T-1) — §7b. READ-ONLY.
**pin**: R28_current_20260714. **prereg sha256**: 6e4d278c…
**metric_type**: weighted_screen (cap-w top-25 paired NW-t lag3 vs clean base). **screening-tier only** (dossier 아님, 저EV 완결 라운드).

---

## 판정 요약 (한 줄)

**VALUE_DEFINITION_AXIS = CONFIG-SCOPED NEGATIVE (screening/cap-w) + 프론티어 표시.**
EBIT/EV(V14+V07)는 cap-w screening AND-게이트를 통과하는 **유일한** 밸류 정의 — 나머지 6종(BM·EP·CFP·FCF·SP·SHY)은 전부 paired < 2.0 미달. "밸류 추가 방향"(cap-w book-marginal)은 config-scoped 소진. **단 2건의 정보성 결과**: ① 2024+ 감쇠는 **정의-특이**이지 value-보편이 아님(SP·EP·CFP는 오히려 2024+ 개선) ② incumbent 잉여는 **구성-바운드**(정의 무관 cor~0.9) → "실낱 EV"(덜 중복되는 정의) 반증.

---

## 1. 하위축 전수표 (cap-w authoritative, base clean 0_stored_S7 PORT_t 3.058)

| 정의 | var_pt | paired | pre-24 | **post-24** | dIR | dIR_post | post17 | cor_act | EW-uni | oos | AND |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **EBIT_EV** (control=R30) | 4.23 | **2.378** | 2.21 | 0.92 | 0.232 | −0.086 | 1.73 | 0.859 | 6.59 | 0.51 | **PASS** |
| SP (sales-yield) | 3.83 | 1.523 | 0.99 | **1.85** | 0.133 | **+0.104** | 1.88 | 0.899 | 6.60 | 0.61 | FAIL |
| SHY (shareholder) | 3.83 | 1.275 | 0.97 | 0.91 | 0.136 | +0.027 | 1.44 | 0.929 | 5.15 | 0.46 | FAIL |
| BM (book-to-market) | 3.70 | 1.291 | 1.01 | 1.17 | 0.111 | −0.022 | 0.97 | 0.886 | 6.73 | 0.49 | FAIL |
| EP (earnings-yield) | 3.42 | 1.229 | 0.77 | 1.33 | 0.051 | −0.004 | 1.27 | 0.925 | 5.44 | 0.38 | FAIL |
| CFP (cash-flow) | 3.33 | 0.332 | −0.03 | 0.79 | 0.032 | −0.065 | 0.79 | 0.913 | 5.52 | 0.30 | FAIL |
| FCF (free-cash-flow) | 3.10 | −0.214 | 0.00 | −0.52 | −0.022 | −0.377 | 0.36 | 0.928 | 4.64 | 0.29 | FAIL |

**parity 확인**: EBIT_EV B2가 R30을 정확 재현(paired 2.378·dIR 0.232·var_pt 4.23·EW-uni 6.59). 하네스·base·B2 구성 verbatim 승계 확증 — 신규 하위축과 동일 프레임 비교 성립.

## 2. 세 가지 판독

**(a) 게이트 = EBIT/EV 유일** — R30의 cap-w screening 관통은 밸류 정의축으로 **일반화되지 않는다**. EBIT/EV는 base 잔차공간에서 가장 강한 밸류 정의였기에 통과했고, 나머지는 신호가 약해 non-mega 틸트로도 paired 2.0을 못 넘긴다. SP(1.52)가 최강 신규이나 여전히 미달.

**(b) 2024+ 감쇠 = 정의-특이 (value-보편 아님, FQ-046 서사 정련)** — FQ-046은 EBIT/EV로 "2024+ value-vs-mega 역전"을 확정했는데, R31 전수는 이 감쇠가 **정의마다 다르다**를 보인다: EBIT/EV(2.21→0.92)·FCF(0.00→−0.52)는 감쇠하나, **SP(0.99→1.85)·EP(0.77→1.33)·CFP(−0.03→0.79)는 2024+ 개선**. 즉 "밸류 전체가 2024+ 죽었다"가 아니라 "**기업가치배수(EBIT/EV) 계열이 죽고 매출/이익 yield 계열은 살아있다**" — 밸류 정의축 안에서 스타일 로테이션이 일어남. (단 개선 계열은 full-period 신호가 약해 게이트 미달.)

**(c) incumbent 잉여 = 구성-바운드 (정의-바운드 아님) → "실낱 EV" 반증** — cor_active(variant active vs base)가 **전 정의 0.86~0.93 균일**. 밸류 신호가 EBIT/EV와 거의 직교(cross-corr 0.07)인 **FCF조차 cor 0.928**. 이는 cap-w tier-조건부 0.3-가중 틸트가 구조적으로 base와 근-중복이기 때문 — 잉여는 **밸류 정의의 문제가 아니라 소비 구성(cap-w top-25 틸트)의 문제**. FQ-046의 "다른 정의는 덜 중복될 수 있다(실낱 EV)"는 반증됨. (⚠ caveat: cor_active는 screening 프록시; risk-단계 realized corr vs STR_1715(EBIT/EV 0.98)이 권위이나 본 라운드는 screening only — 어차피 게이트 통과 정의가 EBIT/EV뿐이라 moot.)

## 3. 특성화 (게이트 미달분 진단 — SP/EP)
- **SP**(sales-yield): actual paired 1.523, placebo(N=40 셔플) null max 2.002·p_emp **0.025**(실신호, borderline), lag1 **2.147**(붕괴 없음 → 동월 look-ahead 부재). 2024+ 개선·EW-uni 6.60·oos 0.61(신규 최고)·dIR_post +0.104(신규 유일 양). = **실재하나 cap-w 약한 신호**.
- **EP**(earnings-yield): actual 1.229, placebo p_emp **0.000**(실신호), lag1 1.006(안정). PIT-safe.
- 둘 다 **실신호·PIT-safe이나 cap-w AND-게이트 미달**.

## 4. 하위축 상관 (concern #1 — 중복 trial 여부)
EBIT_EV 기준 median cross-sectional corr: BM 0.64·EP 0.57·SP 0.61·SHY 0.47·CFP 0.30·**FCF 0.07**. 정의들은 **진짜로 다르다**(사실상 1테스트 아님) — 특히 FCF·EP·CFP는 EBIT/EV와 독립축. 7종은 유효 독립 검정 ~4~5개 상당(FCF/EP 독립 + BM-SP-SHY 군집 + CFP-FCF 군집).

## 5. governance / prior 정합
- book_state·05_Production·outputs/ramp 무변경. 02:00 insider crawl + R9 자동발사 무접촉(R31 산출 stage_artifacts만). DART API 미사용(factor_db only). 공분산/weights 미산출(alpha-research 역할경계).
- n_trials_r31=7(chain — 각 독립 밸류 정의, argmax 아님 → DSR 게이트 부적용·진단만). value family 누적 ~15 trial(R26~R31) — 저EV 다중검정 challenge_note 명시.
- honest_prior(낮음) 정합: KR value 24/24 감쇠·EBIT/EV 확정 → 신규 정의 게이트 미통과는 예측된 결과. AX-000: 소진을 dead-end로 접지 않고 next_probe로 SP EW-basis 프론티어 + 정의-로테이션 monitoring 도출.

## 6. next_probe (≥2, 종결 어휘 미사용 — config-scoped negative + 프론티어)
1. **P1 (SP sales-yield → EW-basis / OVERLAY_CANDIDATE 재라우팅)**: SP는 2024+ 개선하는 유일 정의(post24 1.85·post17 1.88·EW-uni 6.60·oos 0.61·placebo p=0.025·lag1 2.147 PIT-safe). cap-w 게이트 미달 = cap-w 국소화(EW-uni 강함)이지 신호 사멸 아님 — V02_EP(FQ-008/009)와 동일 경로로 RAMP/factor-rotation EW-relative sleeve 또는 OVERLAY_CANDIDATE 라우팅. **데이터 게이트 없음(feasible now).**
2. **P2 (밸류 정의-로테이션 monitoring tripwire)**: EBIT/EV 감쇠 ↔ sales-yield 강화 = 밸류 정의축 내부 스타일 로테이션 실증. FQ-046 부활조건(value-vs-mega 로테이션 반전)을 **EBIT/EV-vs-sales-yield 상대성과 tripwire**로 정련해 monitoring 등록 — value 아크 부활신호의 조기감지. (standalone alpha로는 저EV — cross-family regime-conditional FALSIFIED prior 정합; monitoring 신호로만.)
3. **P3 (구성-바운드 잉여 우회 — 비-cap-w 밸류 소비, 저순위)**: incumbent 잉여가 cap-w 틸트 구성의 산물이므로, 밸류를 top-25 cap-w 틸트가 아닌 EW/벤치-상대 sleeve로 소비하면 잉여가 낮아질 수 있음 — RAMP 모드 소비면(QEPM 아님). SP·BM(EW-uni 6.60/6.73)이 후보.

## 7. 밸류 아크 완결 답 (도훈 "밸류 추가 방향 끝났나")
**QEPM cap-w book-marginal 관점 = 예(config-scoped 소진)**: 밸류 정의 전 스펙트럼(book·earnings·cashflow·FCF·sales·shareholder·enterprise-multiple) 중 cap-w screening AND-게이트를 통과하는 건 EBIT/EV뿐이고, 그마저 forge/judge에서 자본 REJECT(FQ-046). incumbent 잉여는 정의 무관 구성-바운드. **단 "밸류 자체가 죽었다"는 아님** — sales/earnings-yield 계열은 2024+ 살아있고 EW-basis에서 강함(SP EW-uni 6.60). 남은 밸류 가치는 (a) EW/벤치-상대 소비(RAMP), (b) 정의-로테이션 monitoring 신호 — QEPM 신규 cap-w 밸류 팩터 사냥은 아님.
