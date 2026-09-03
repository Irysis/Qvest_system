# WT-R20260829_006 — Risk 구간 Self-Adversarial Challenge

**작성**: risk-research agent · 2026-08-29
**대상**: `risk_package.json` (Σ = BΩB' + D · tail · stress · 계열집중)
**규약**: v8.2 Self-Adversarial Challenge (외부 Codex Round 대체). 분류 = ACCEPT / PARTIAL / REBUTTAL.
**경계 준수**: alpha_vector 무수정(mtime 18:02:57 불변) · weight 미제안 · 등급 미선언 · 오버레이 미적용.

---

## 1. ACCEPT — as_of 유동성 필터가 첫 판본에서 무효였다 (수정 완료)

**자기비평**: `LIQ_DT` 는 forward 수익이 필요한 앵커까지만 생성돼 마지막 날짜가 2026-07-31 이다.
그런데 나는 as_of(2026-08-28) 노출을 만들면서 `merge(..., all.x=TRUE)` 뒤
`is.na(adv) | adv >= 2e8` 관용구를 썼다. **adv 가 전건 NA 인 상황에서 이 관용구는 결측을 "통과"로
내려앉힌다.** 결과: ①유동성 게이트가 한 종목도 거르지 않았고 ②`x_liq` 노출이 zsc(전건 NA) → 전 종목
0 이 되어 유동성 팩터 노출이 통째로 죽었으며 ③유니버스가 beta 이력 부족 57종을 잘못 탈락시켜 290
으로 좁혀졌다.

**처리(spec 수정)**: `build_adv20_t1(RAW, at_dates=2026-08-28)` 로 as_of adv20 를 원장에서 직접
재계산(C10 shift(1) 준수). 결과 — K200∪KQ150 347종 **전건이 adv≥2e8 통과**(결측 0·FAIL 0),
`x_liq` 실측 복구, Σ 유니버스 = alpha_vector 347 과 정확히 일치. beta 이력<24개월 57종은 탈락이
아니라 Blume 사전값 1.0 대체 + `specific_risk.parquet::beta_fallback` 플래그로 하류에 노출.

**기전 이름**: memory 의 "미스캔을 PASS 로 내려앉히지 말 것"(lookahead_detector 2026-08-02 수리)과
동형이다. 결측을 합격으로 바꾸는 관용구는 게이트를 조용히 무력화한다.

---

## 2. ACCEPT — 추정기 판정이 추정기가 아니라 zero-fill 아티팩트를 재고 있었다 (수정 완료)

**자기비평**: 1차 Ω method shopping 에서 sample −3,926,090 / lw_nls −1.1e10 / gerber_rmt −9.5e7 의
OOS 로그우도가 나왔고 ledoit_wolf 만 +79 였다. 이 표를 그대로 인용했으면 "LW 외에는 쓸 수 없다"는
결론이 나온다. **원인은 추정기가 아니었다.** 섹터 더미 `s_OTHER`(미분류)가 248개월 중 4개월만
추정 가능해 244개월이 0 으로 채워졌고, 그 상수-0 방향이 표본 Ω 를 특이하게 만들어 역행렬을
폭발시켰다.

**처리**: OTHER 를 기준군(IT)에 흡수해 24팩터로 재구성 → NA 계수 0, 네 추정기 전부 정상
(sample 72.07 / LW 75.52 / lw_nls 78.09 / gerber_rmt 75.11). 판정이 뒤집혔다.

**교훈**: 추정기 비교표가 "한 후보만 정상"으로 나오면 후보를 의심하기 전에 **설계행렬**을 의심해야
한다. 세 후보가 동시에 죽는 것은 후보의 성질이 아니라 공통 입력의 결함일 확률이 높다.

---

## 3. PARTIAL — cond(Σ) 399.9 는 500 게이트는 통과하나 200 권고선을 넘는다

**자기비평**: qvest-risk-style 은 cond>200 이면 shrinkage 로 개선하라고 한다. 나는 D winsorization
을 2/98 → 5/95 로만 좁혀 483.5 → 399.9 까지 내렸고 200 아래로 가지 않았다.

**부분 인정 + 보완**: 조건수를 분해하면 cond(Ω)=132.8(lw_nls 축소 후 · 표본 194.7 대비 32% 개선),
cond(D)=9.1 이다. Σ 의 조건수는 **추정잡음이 아니라 347종 특이변동성의 실제 분산**에서 온다.
사다리 전체를 원장에 남겼다 — 2/98: cond 483.5·평균 특이변동성 38.98% / 5/95: 399.9·38.54% /
10/90: 313.4·38.06%. 200 이하로 가려면 특이변동성을 2.4% 이상 왜곡해야 하고, 그건 조건수를 위해
측정 대상을 바꾸는 것이다. **PD 는 확인됐다**(min eigen 3.51e-3 > 0, 대칭성 all.equal 통과).
하류가 다른 판단을 할 수 있도록 `diagnostics.condition_sensitivity_ladder` 로 3단 전부 노출.

★자기합리화 점검: "영향 미미"·"보수적이면 괜찮다" 류 표현을 쓰지 않고 왜곡률을 수치(2.4%)로
명시했다. 판단 근거를 하류가 재계산할 수 있는 형태로만 남긴다.

---

## 4. REBUTTAL — "selection_objective 를 shrinkage_quality 로 고른 건 method shopping 아닌가"

**반론(학술 + L-code + 정량 3축)**:
- **학술**: Ledoit-Wolf(2020) analytical NLS 는 c=p/n 이 작을 때(여기 24/248=0.097) 표본
  고유값의 유한표본 편의를 비선형으로 교정한다. 선택 지표로 쓴 rolling OOS 가우시안 우도는
  공분산 추정기 비교의 표준 손실(Stein loss 계열)이며 성과 지표가 아니다.
- **L-code / SOT**: v8.3.1 posterior 는 "p>n 대형 유니버스는 lw_nls, WT-시점 소규모(p≤25)는
  linear LW 무해"라고 적는다. 여기서 p(24) ≪ n(248) 이라 **LW 의 p>n 퇴화 조건은 비발동**이고,
  posterior 는 "linear LW 가 우월"이 아니라 "무해"를 말한다. 실측으로 우월을 재판정한 것이다.
- **정량**: 후보는 `.get_cor_cov` **등재분 전수 4종**(상한 5 미만). 판정은 매 시점 직전 60개월만
  쓰는 PIT-clean 지표이고, 페어드 DM-t(NW lag3) = **+5.23**(dLL +2.579/월)으로 lw_nls 가
  ledoit_wolf 를 이겼다. **진 후보가 조건수(59.6 vs 132.8)와 분할반쪽 안정성(0.421 vs 0.547)에서
  앞선다는 사실을 은닉하지 않고** method_log 에 병기했다. SR/IR/α 는 선택 과정에서 **한 번도**
  참조하지 않았다(v6.1 R4 P3 준수).

∴ 성과 기반 선택이 아니고, 사전 정의된 estimation-quality 축의 페어드 검정 결과다. 반론 유지.

---

## 5. REBUTTAL — "구간별 Σ(pre/post-2015)를 만든 것은 C1(full-sample) 위반 아닌가"

**반론**: C1 이 금지하는 것은 **과거 시점의 판단에 그 시점 이후의 표본통계를 투입하는 것**이다.
본 산출의 as_of Σ 는 sig_date 까지의 확장창 **하나**로만 만들어졌고, 구간별 Σ 두 개는
**어떤 의사결정에도 투입되지 않는 사후 구조 진단**이며 두 구간 모두 sig_date 이전이다.
추정기 선택조차 rolling-60m(직전 60개월만) OOS 우도로 했다. `detect_lookahead` 는 엔진 12파일에서
위반 0 이고, 위반 주입본은 4/4 적발돼 검사기 생존이 실증됐다. 반론 유지.

---

## 6. REBUTTAL → 계기 결함으로 승격 — "crowding_flags 가 비었으니 군집 위험 없음"

**자기비평이 반론보다 강한 경우다.** 최대 crowding_score 는 0.4159(size)로 게이트 0.75 미달이지만,
본 유니버스에서 composite 의 **구조적 상한이 0.7345** 다: `passive_overlap_proxy` 는 유니버스가
곧 벤치(K200∪KQ150)라 13계열 전부 1.0 고정이고, `vol_concentration` 은 13계열 중 9계열에서
정확히 0 이다(top-25 거래대금 비중이 중립선 25/N 을 넘지 못함). 즉 **RF-R3 은 이 유니버스에서
원리적으로 발화할 수 없다.**

∴ "군집 없음"이 아니라 **"이 계기로는 판정 불가"** 로 보고했고(`crowding_instrument_note`),
대신 원자료(hhi_top 최대 momentum 0.369 · 3개월 델타 최대 +0.0792 < 0.15)를 병기했다.
양성 대조 없는 계기를 방어선으로 세지 않는다.

---

## 7. PARTIAL — EVT 는 소표본이다

**자기비평**: 월간 n=248, 90% 임계 초과 25개로 GPD ξ 를 적합했다. 전기간 ξ=0.0955 vs pre-2025
ξ=0.1615 — 20개월을 빼면 ξ 가 69% 움직인다. 점추정으로 소비하면 위험하다.

**처리**: `tail_risk.json::evt_caveat` 에 명시하고, 꼬리 판단은 GPD 단독이 아니라
①실측 분위 ②Hill α ③t(5) 파라메트릭 세 축을 병기해 넘긴다. 일별 전략 수익 패널이 없어
정밀화는 불가능하다(상류 WT006-08 이 같은 사유로 기전 (d)를 월별 대체 사양으로 냈다).

---

## 8. REBUTTAL — "top-25 EW book 을 만든 것은 weight 제안 아닌가"

**반론**: 전략 사양이 이미 **단일 top-25 EW** 이다. 나는 그 사양을 재현해 위험을 분해했을 뿐
최적화도, 대안 비중도, 종목 선호도 제시하지 않았다. 산출물 어디에도 target_weights 가 없고
`boundary_declaration.weights_proposed=FALSE` 로 못박았다. Σ 는 347종 전건으로 발행해 optimizer 가
자유롭게 비중을 정할 수 있게 했다. 반론 유지.

---

## 자기합리화 자동점검

금지 표현("영향 미미" / "관행적 허용" / "보수적이면 괜찮다" / "대부분 결과 동일" /
"이미 반영되어 있었을 것" / "기간이 충분히 길어서 상쇄") — 본 노트 및 risk_package 전문 대조 결과
**사용 0건**. §3 의 조건수 판단은 정성 표현 대신 왜곡률 2.4% 로, §7 의 EVT 판단은 ξ 변동률 69% 로
대체했다.

## 에스컬레이션

HIGH 5건(RF-R1 · WT006R-01/02/03/04) → 자동 트리거 충족. **Σ PD 위반 없음 · PIT hard 위반 없음**
이므로 ABORTED 아니며, 체인 완주 지시에 따라 하류 소비 가능 상태로 발행하고 Q-Lead 에 보고한다.

## Risk → Alpha 이의 (formal challenge 대신 review-with-objection)

WT006R-07: '비-모멘텀 12계열' 구성이 모멘텀 중립을 뜻하지 않는다 — 진단 book 의 `x_f_momentum`
노출 **+0.469σ**, book 분산 기여 1.63%. `wt_challenge` 는 phase 를 alpha 로 되돌리므로
체인 완주 의무상 사용하지 않고 `wt_record_challenge_review(objection=TRUE)` 로 원장에 기록했다
(governance_log.json). alpha_package 는 무수정.
