# Self-Adversarial Challenge — R21 칼만 정확도의 리스크-소비 2종 (WT-D20260713_005 / FQ-034)

**v8.2 Opus 4.8 자체 적대검증** (외부 Codex 없음). Charter §8 No Silent Override. AX-008 3-source 중 1.
finalize 직전 스스로 devil's advocate로 산출물의 약점을 제기·분류(ACCEPT/PARTIAL/REBUTTAL)·근거 기록.

## 측정 요약 (판정 대상)
- **arm A (위기-조건부 저베타 within-sleeve 틸트)**: 현 book(noLayer4) top-20 슬리브 × overlay(m4×β_R05) 공통.
  - base PORT_t −0.50 / armA_K −0.495 / armA_O −0.50 (전부 사실상 동일).
  - **칼만 한계기여 (K vs O) paired_NW_t 0.99** (비유의 — 추정기 무차별 재확인).
  - 틸트 순효과 (K vs base): 전기간 NW_t 0.43(무), **위기구간 NW_t 1.27 (n=18, 비유의·소표본)**.
  - MDD relief (base−K) = **0.0002** (무시가능). 위기구간 active: base −0.0336 / K −0.0330 (둘 다 음).
  - placebo(국면 12m 시프트) vs base NW_t **−1.16** (시프트 틸트는 오히려 악화).
- **arm B (칼만-잔차 IVOL)**: 저-IVOL long top-25 EW canonical.
  - IVOL_K PORT_t **−1.58** / IVOL_O **−1.50** (둘 다 음, cap-w authoritative). EW-uni −2.19.
  - **추정기 한계기여 paired_NW_t −1.01** (비유의). **prediag 랭킹상관 mean 0.999·100%≥0.97 = 추정기 완전 무차별.**
  - **redundancy: D35_RealVol_63d |ρ|0.97 (사실상 동일), D01_IdioVol/R12 0.80, D03_RealVol 0.79.**
  - rank-IC 0.049 / harvey_t **4.57** (advisory 양호) 이나 PORT_t −1.58 = **IC→PORT_t 전이 벽 전형.**

---

## 사전등록 우려 (prereg SC1~4)

### SC1 — arm A 개선이 위기월 소표본 잡음인가?
**분류: ACCEPT (인정)**
- 위기월(regime CRISIS/CAUTION) n=**18**. crisis NW_t 1.27은 |t|<2 비유의 + n=18 소표본. mean_annual 0.81%p의 개선은 잡음 범위. → arm A "위기 개선"은 통계적으로 실재 주장 불가. 정직 라벨: config-scoped negative.

### SC2 — placebo-시프트 틸트와의 구분 실패 시 R3 재판인가?
**분류: REBUTTAL (구분 성공 — R3 재판 아님)**
- placebo(국면 12m 시프트) vs base NW_t **−1.16** (음). 즉 틸트를 *엉뚱한* 월에 적용하면 악화 → 실제 위기월의 미미한 +효과는 순수 시점-무관 스타일 틸트가 아님(R3의 "시점-무관 스타일" 판정과 다름). 단 실제 효과 자체가 너무 작아(MDD relief 0.0002) 운용가치는 없음. → 방향 구분은 성공했으나 크기가 무의미.

### SC3 — arm B가 LowRisk 기존과 중복인가?
**분류: ACCEPT (강하게 인정)**
- IVOL_K는 D35_RealVol_63d와 |ρ|**0.97** (사실상 동일 팩터), D01_IdioVol/R12와 0.80. arm B는 신규 팩터 아님 — 기존 factor_db LowRisk의 재현. R18 AC13(중복성) 교훈 적중. → 신규성 없음 확정.

### SC4 — arm A 저베타 틸트가 book cash-overlay de-risk와 중복인가?
**분류: ACCEPT (인정 — 메커니즘 확증)**
- 현 book은 위기 시 이미 β_R05 cash 오버레이로 exposure를 축소(2008-11 invested ~11%, 2020-03 ~21%)한다. 슬리브-내 저베타 재가중은 이미 현금화된 소액 exposure 위에 얹히는 2차 효과 → MDD relief 0.0002로 소멸. 게다가 슬리브 Defense는 이미 M08_Residual_Mom(저베타 구성)을 보유 → 저베타 축이 book에 이미 포화. **저베타 틸트 = book이 이미 하는 일의 중복.**

---

## 신규 적대 우려 (devil's advocate, ≥3)

### NC1 — arm A base PORT_t −0.50 (음)은 측정 오류/설정 오류 아닌가?
**분류: REBUTTAL**
- 아니다. base는 슬리브×overlay의 **cap-w KOSPI200 대비 active**다. 방어형 cash 오버레이는 강세장서 full-invested cap-w 벤치에 구조적으로 뒤진다(active 음이 정상). 현 book의 운용가치는 절대·위험조정(MDD 축소)이지 cap-w active beat가 아님. arm A의 판정 대상은 level이 아니라 **delta(K−base)이며 그 delta가 ~0**임이 결론. base 음은 arm A 판정에 무관.

### NC2 — 칼만 무차별(arm B rank corr 0.999)은 IVOL을 잔차에만 쓴 탓, β-level 소비였으면 달랐을 것 아닌가?
**분류: PARTIAL/REBUTTAL**
- 잔차 vol에서 idiosyncratic 분산이 β·시장분산을 압도(잔차 = 대부분 개별잡음) → 어느 β를 빼든 sd 거의 불변 = 구조적. β-level 소비(exposure 스케일링)는 이미 현 book의 cash 오버레이(m4×β_R05)로 구현·정착(07-05 settled). 따라서 "β-level이면 달랐을 것"의 소비처는 이미 존재·소진. arm B가 무차별을 확증하는 것은 R19 metric_1(헤지오차 inert)과 정합 — **칼만 정확도는 β-점예측(metric_2)에만 우세하고 잔차·팩터 소비엔 inert.**

### NC3 — 3-채널(R19 저베타 팩터 / arm A 틸트 / arm B IVOL) 전부 negative를 "칼만 무용"으로 과일반화하는 것 아닌가?
**분류: PARTIAL (범위 라벨)**
- 과일반화 방지: 칼만의 β-점예측 정확도(realized-β RMSE −10.3%, R19 metric_2)는 실재하며 **β 자체를 산출물로 쓰는 소비처**(TE 추적·리스크 리포팅·β-타이밍 exposure)엔 여전히 유효할 수 있다. 본 3-채널이 부정하는 것은 좁게 **"칼만 β를 횡단 알파/틸트/잔차 신호로 소비"** — 이 특정 소비 경로가 전이 벽에 막힘. 칼만 자체의 폐기 아님(INV-7 프론티어 표시).

---

## 합리화 자기검증 (auto-detection: 미미/관행/보수적이면 OK/대부분 동일)
- "arm A 개선 미미"를 관행적으로 넘기지 않고 n=18 소표본 + NW_t 1.27 비유의 + MDD relief 0.0002 정량 3축으로 ACCEPT.
- "arm B rank-IC 4.57이 좋으니 통과" 유혹 차단 — PORT_t −1.58 authoritative 채택(measurement-graduation §3: rank-IC advisory). huge-n·advisory 거짓통과 방어.
- "두 arm 대부분 동일하니 칼만 무용"으로 비약하지 않음(NC3 범위 라벨).

## Escalation 판정
- HIGH severity ≥5? **NO** (SC1/SC3/SC4 ACCEPT 3건이나 전부 negative-확증 방향, 자본 admission 아님). AX axiom hard FAIL ≥3? **NO**. PIT C1 위반? **NO** (β dlmFilter 필터값·regime 홀딩월 전 C5·overlay_pit 해당없음(신규 오버레이 아님, 기존 exposure 소비)). → **Q-Lead escalate 불요.** 통상 판정 보고.

## AX-008 Triangulation
self-adversarial(본 문서)=3-source 중 1. arm A는 weighted_screen_bt, arm B는 canonical_screen_bt = build_benchmark_compare 계약 경유 실측(Forge-등가 source). 2/3 PASS 충족(architect 미소집 — estimator/construction 진단, 자본 admission 아님).

## 판정 (lexicon 준수)
**BOTH ARMS = config-scoped negative + 프론티어 표시.** next_probe ≥2/arm 기재(alpha_validation.json).
메타: 칼만 β-정확도(R19 metric_2 −10.3%)는 **리스크-소비 3채널(저베타 팩터·위기틸트·잔차 IVOL) 전이 벽에 inert.** 벽 = 잔차 개별분산 지배(추정기 wash-out) + 저베타=소형주 음-알파 스타일 + book이 이미 cash 오버레이로 위기 de-risk.
