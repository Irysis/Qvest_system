# R35 (FQ-047 P1) Verdict — SP(sales-yield) 소비면 재라우팅 (EW-basis / OVERLAY / 2024+ 강건성)

**부모 체인**: R26..R31(FQ-047 밸류 아크) → R31이 SP를 "유일 2024+ 생존 밸류 정의"로 지목 → **R35(FQ-047 P1)**: 그 유일 생존축을 cap-w 자본 게이트 밖 소비면으로 재라우팅.
**base 권위**: clean recon_panels (WT_D20260714_004, production_parity_verified, off0 T-1) — §7b. READ-ONLY.
**pin**: R28_current_20260714. **prereg sha256**: 7ddd3cb3…
**metric_type**: canonical_screen (EW top-25 long-only, 15bps, liq 2e8) + canonical_screen_diag (EW-universe). **screening-tier only** (dossier 아님, 저EV 재라우팅 라운드).

---

## 판정 요약 (한 줄)

**SP_CONSUMPTION_REROUTE = SCREEN-TIER ROUTED (feature 보존) + config-scoped negative(standalone 배포 · live 오버레이 레버).**
SP EW-basis 트랙은 실신호·PIT-safe이나 **자본 미달**(cap-w PORT_t 2.236 / EW-uni 2.758 둘 다 <2.95, **수용력 0.5억원 micro**). SP 오버레이 한계기여는 **pre-2024-only**(base/incumbent 양쪽 post24 paired ≈0). **★핵심 정정**: R31의 "SP = 2024+ 생존축"은 **cap-w tier-조건부 marginal-vs-붕괴하는-base 프레임에 특이한 아티팩트** — SP의 절대(standalone) 신호는 **pre-2024-지배**(EW-active pre24 NW-t 2.51 vs 2024+ 1.12). SP는 diversifying(P-pure corr<0.5)·PIT-safe·real한 **regime-의존 순환-가치 신호로 OVERLAY_CANDIDATE feature 보존**(자본/live-lever 아님).

---

## 1. Part 1 — EW-basis 배포성 (D3 형식)

| 지표 | cap-w basis | EW-universe basis (D3-relevant) | 판정 |
|---|---|---|---|
| PORT_t (NW lag3) | 2.236 | 2.758 | 둘 다 <2.95 (자본 미달) |
| post2017_t | — | **1.162** | 최근 약함 |
| oos_retention v2 | 0.029 (FAIL) | **0.902** (PASS>0.7) | basis-분기 극명 |
| net SR (ann) | 0.449 | 0.619 | — |
| TE (ann) | 19.5% | 12.6% | — |
| turnover (ann) | 3.9 | — | 저회전 (신호 sticky) |
| **capacity (5% ADV, 최소보유 binding)** | — | **median 0.5억원** | **★micro — 배포 불가** |
| active-corr vs P-pure base / D-2 | — | **0.458 / 0.423** | <0.5 diversifying |
| holding overlap vs P-pure base | — | Jaccard 0.064 (~3/25 shared) | 거의 비중첩 |

- **PIT 재확인**(pure SP EW 프레임 직접): lag1 스트레스 EW-uni 2.758→2.182 **graceful decay**(동월누출 인플레 없음 = PIT-safe), placebo(N=60 within-month shuffle) real 2.758 vs null max −0.276 **p_emp=0.000**(실신호).
- **판독**: SP EW 신호는 **실재·PIT-safe·diversifying**하나 (a) 절대 PORT_t가 자본 게이트 미달 (b) **수용력이 micro**(0.5억원 — 최소보유 종목이 유동성필터 경계 2e8 부근, EW top-25가 소형에 농축) → **standalone EW 배포책 불가**. oos_v2 EW 0.902의 강함은 **2020-23 revival**을 반영(anchored split 2016/2018/2020 기준)이지 2024+ 지속력 아님(post2017_t 1.16).

## 2. Part 2 — OVERLAY feature 자격 (m1-drain 형식, EW-basis 한계기여)

| 오버레이 대상 | paired NW-t (full) | dIR | **pre-2024 paired** | **2024+ paired** | base_EW_pt → ovl_EW_pt |
|---|---|---|---|---|---|
| base clean (0_stored_S7) | 1.882 | +0.394 | **1.959** | **−0.178** | 4.21 → 6.65 |
| incumbent book (score_eff) | 1.127 | +0.298 | 1.174 | **−0.026** | 6.63 → 7.94 |

- **판독**: SP를 0.3-가중 tilt 오버레이로 얹으면 full-period 한계기여는 양(+)이나 **전량 pre-2024**. base·incumbent 양쪽에서 **2024+ 한계기여 ≈0/음** → **live 오버레이 레버로는 감쇠**. SP는 "지금 얹으면 도움되는 신호"가 아니라 "과거엔 도움됐던 신호". OVERLAY_CANDIDATE **feature로 보존**(진단·부활대기)은 정당하나 **현재 배선 대상 아님**.

## 3. Part 3 — 2024+ 강건성 (★R31 서사 정정)

- **SP EW-active 부기간 NW-t**: 2008-14 **2.28** · 2015-19 **−0.24**(사멸) · 2020-23 **2.51** · **2024+ 1.12**.
- **pre-2024 2.508 vs 2024+ 1.119** → **SP 절대 신호는 pre-2024-지배**. 2024+는 양(+)이나 modest이고 과거 강세기보다 약함.
- **rolling-24m EW PORT_t**: last 2.00 · max 5.12 · min −2.09 · 최근12개월 11/12 양 → 현재 양이나 peak(5.12) 대비 하락 국면.
- **★정정**: R31의 "SP=유일 2024+ 생존 밸류 정의"(post24 paired 1.85 > pre24 0.99)는 **cap-w tier-조건부 marginal-vs-base** 측정이었다. 그 프레임에선 cap-w base 자체가 2024+ 붕괴(value-vs-mega 로테이션)했기에 SP의 tier-tilt가 *상대적으로* 덜 나빠 보였을 뿐. **absolute/standalone SP는 어느 basis에서든 pre-2024-지배** — "2024+ 생존"은 **프레임-특이 아티팩트**이지 구조적 매출-yield 프리미엄 아님. (challenge C1·C4 검증됨.)
- **sector 집중 (C3-인접)**: SP top-25 sector HHI pre24 0.099 / post24 0.105 — **broad**(≈10 등가섹터). 상위 = 필수소비재·건설/건축·건강관리 (+post24 철강·화학 = deep-cyclical). **단일-섹터 집중 아님** → 2024+ 우위가 sector-국소 아님(structural이라기보다 순환-가치 광역 틸트).
- **C3 저품질 함정**: SP top-25 median EP(aligned-z) = **−0.016 ≈ 중립** → SP 보유는 적자/저이익 종목으로 계통 편향되지 **않음**(junk-rally 아님). 저품질 함정 concern 미지지.

## 4. governance / prior 정합

- book_state·05_Production·outputs/ramp **무변경**. stage_artifacts만. DART API 미사용(factor_db only). 공분산/weights 미산출(alpha-research 역할경계).
- selection_type = **chain**(단일 팩터 SP 특성화, argmax sweep 아님 → DSR 게이트 부적용, 진단만).
- honest_prior(낮음) 정합: cap-w 자본 미달은 R31에서 예측된 결과. 본 라운드 가치 = **정정 지식**(2024+ 아티팩트) + **feature 보존 자격 확정** + **수용력 벽 실측**(EW 소형 트랙의 배포 불가 정량화 0.5억원).

## 5. next_probe (≥2, config-scoped negative + screen-tier + 프론티어)

1. **P1 (SP regime-conditional 입력 — RAMP/factor-rotation, NOT standalone)**: SP는 regime-의존(2015-19 사멸·2020-23 revival 2.51). value-favorable 레짐에서만 켜는 조건부 sleeve 입력으로 소비 가능(RAMP 모드 module consumer). **단 cross-family regime-conditional FALSIFIED prior**(project-axiom-engine) → 저EV·조건부. feasible now(데이터 게이트 없음).
2. **P2 (value 정의-로테이션 tripwire 정련 — R31 P2 승계 + 정정)**: R31 P2의 "EBIT/EV-vs-SP 상대" tripwire를 **정정된 기준으로 재정의** — SP *절대* rolling-24m EW PORT_t의 **지속 >2 재상향**을 부활 신호로(상대-vs-EBIT/EV만으론 base-붕괴 아티팩트 재발). monitoring 등록 후보.
3. **P3 (수용력 벽 일반화 — deployable cap-tier의 SP 신호 유무)**: 0.5억원 수용력은 EW-소형 농축 산물. deployable tier(MEGA/MID)에 SP 신호가 남는지 diag_cap_tier로 별도 측정 — standalone SP는 OTHER-국소일 가능성 높아 저순위(cap-tier 국소화 벽 재확인 예상).

## 6. 도훈 재라우팅 답 (SP 유일 생존축을 어디에 쓸 것인가)

**standalone 배포책·live 오버레이 레버 = 아님**(자본 미달·수용력 micro·오버레이 한계기여 pre-2024-only). **SP = OVERLAY_CANDIDATE feature 보존**(real·PIT-safe·diversifying) + **정정 지식**(2024+ 생존은 cap-w marginal 프레임 아티팩트, 절대 신호는 순환-가치·pre-2024-지배·regime-의존). 실낱 소비면 = RAMP regime-conditional 입력(P1, 저EV) + 정의-로테이션 monitoring tripwire(P2). **밸류 아크(R26~R35) 최종**: 밸류는 cap-w 자본 레버로 소진, EW-basis SP도 수용력·최근성 벽 — 남은 가치는 monitoring·조건부 feature.
