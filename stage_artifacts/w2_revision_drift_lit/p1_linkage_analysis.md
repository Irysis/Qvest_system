# 문헌 ↔ P1 실측 연계 분석 (Track B)

**작성**: 2026-07-02 (도훈 지시, W2 근거 확정)
**입력(재실행 아님, 해석)**: `stage_artifacts/pg2_w2_earnings3m/{measure_results.csv, meta_pg2_w2.json, build_meta.json, paired_vs_baseline.csv}`
**metric_type**: 전부 `canonical_screen`(NW lag-3, admission-binding 아님 — forge build_bt_result가 authoritative). PORT_t는 실현 net active t, IC t는 횡단면 진단.

---

## P1 실측 핵심 (재확인)

| 신호 | plain_full PORT_t | band_full PORT_t | paired-NW-t vs base(band) | IC t_full | IC t 2010-15 | IC t 2016-20 | IC t 2021-26 |
|---|---|---|---|---|---|---|---|
| BASE_earn3m | 1.081 | 0.21 | — | 6.59 | 1.88 | 2.56 | 4.51 |
| **S1_innovrev** | 1.012 | 1.191 | +0.165 (ns) | 5.25 | 3.59 | 1.68 | **1.71** |
| **S2_tpsect** | −0.122 | −0.616 | **−2.317** | 5.02 | 2.02 | 1.03 | 2.99 |
| **S3_consensus** | 1.505 | **2.202** | **+2.026** | 5.68 | 4.10 | −0.12 | 3.07 |
| COMP_S3 | 1.701 | 0.741 | −0.814 | 7.35 | 3.69 | 1.79 | 4.46 |
| COMP_ALL | 1.742 | 0.746 | −0.54 | 8.45 | 5.37 | 2.12 | 3.82 |

**best = S3_consensus + 보유밴드**: PORT_t 2.202, absSR 1.039, calmar 0.587, turnover 3.59, paired-NW-t +2.026.
공통: **recent 2021+ PORT_t 전 신호 <0.12(대부분 음)** = cohort-wide decay. **보유밴드는 지속신호(S1/S3)만 개선, 노이즈신호(BASE/S2)는 악화**.

---

## 대조 1 — Da-Schaumburg 섹터상대 TP: 문헌 알파 vs KR 음(S2_tpsect)

| 항목 | 문헌(Da-Schaumburg 2011) | P1 KR(S2_tpsect) | 판정 |
|---|---|---|---|
| 섹터상대 TP 부호 | **+** (월 SR 0.41, α 0.67%/월) | plain −0.122 / band −0.616 / recent −1.30 | **모순(VALIDATED-negative)** |
| raw TP | 무정보(전체 횡단 랭크 시 소멸) | (baseline C06_TP_Gap raw 슬롯) | 정합(raw 약) |
| 구조 | L/S within-sector, S&P500, 1M | **long-only** top-N, K200∪KQ150, 1M | 구조 상이 |

**메커니즘 가설 (KR서 음인 이유 — 억지정합 금지, 가설로 명시)**:
1. **Long-only vs L/S**: Da-Schaumburg 알파는 **섹터 내 long-short 스프레드**. KR은 long-only top-N → 섹터상대의 short-leg 알파(저-TPER underperform)를 못 취함. 섹터중립화는 시장β(long-only 바닥 β≈0.99, [[reference-orthogonality-gross-vs-active]])를 제거하지 못하면서 신호의 시장-드리프트 편승분만 깎을 수 있음.
2. **TP 커버리지·품질 차이**: KR 목표가 데이터는 US(S&P500) 대비 커버리지·갱신빈도·분산이 열위. Da-Schaumburg는 "산업 내 fundamental 이탈 식별력"에 의존 — KR 애널리스트 산업내 변별력이 US보다 약하면 신호 붕괴.
3. **섹터중립 z가 KR 소형주/국면 성분 제거**: WICS 섹터중립이 KR서 알파원(소형·모멘텀 성분)을 우연히 상쇄. IC t_full 5.02로 **횡단 신호력은 존재**하나 long-only 실현 PORT_t로 이전 안 됨 = **IC≠PORT_t의 전형**([[measurement-graduation]] §6).

→ **결론: 섹터상대 TP는 문헌(US L/S)선 알파, KR long-only선 음. 시장구조(L/S 불가)·데이터품질 차이로 비이전. S2 계열 W2 편입 배제 근거 강화.**

---

## 대조 2 — Gleason-Lee 혁신>herding vs S1_innovrev

| 항목 | 문헌(Gleason-Lee 2003) | P1 KR(S1_innovrev) | 판정 |
|---|---|---|---|
| 혁신 리비전 drift 부호 | **+**, herding보다 큼 | IC t_full 5.25(+), plain PORT_t 1.012 | **정합(부호)** |
| 저커버리지 강화 | drift ↑ | (P1 미분해 — 커버리지 상호작용 미측정) | ⚠️ 미검증 |
| recent 유효성 | (문헌 표본 US 1990s-2000s) | **t 2010-15=3.59 → 2016-20=1.68 → 2021-26=1.71** | **부분모순(최근 약화)** |

**정합**: S1의 innovation z(trailing dispersion 대비) 구성은 Gleason-Lee "혁신 리비전 분리"의 직접 사상. **부호 양(+)·IC 유의(5.25)로 메커니즘 실재 확인**. 보유밴드가 S1 PORT_t 개선(1.012→1.191)한 것은 JBFA2020 "revision streak 지속성" 이론과 정합 — 지속신호라 밴드 잔류가 이익.

**모순/주의**: S1 IC가 **2010-15(3.59)에 강하고 2021+(1.71)로 약화**. Gleason-Lee 메커니즘은 실재하나 **최근 감쇠**(아래 대조 3). 또 S1 standalone PORT_t 1.01 < S3 1.51 — **혁신 단일축보다 3-신호 합의(S3)가 KR서 우월**.

---

## 대조 3 — 문헌 drift가 최근에도 유효한가 vs 우리 2021+ decay

| 항목 | 문헌 | P1 KR |
|---|---|---|
| 최근 유효성 | PEAD/revision drift **전반적 감쇠**(arbitrage↑·정보환경 개선). SUE 스프레드 1980-90s ~5% → 2010s ~3%↓. Grinblatt: 대부분 anomaly가 analyst-bias 통제 시 소멸 | **전 신호 recent 2021+ PORT_t <0.12(대부분 음)**. decay-pattern(cohort-wide, 메모리 earnings decay 2015+) |

→ **강하게 정합**. 문헌의 "revision/earnings drift 최근 감쇠"가 우리 2021+ decay와 **독립적으로 일치**. 이는 우리 실측이 아티팩트가 아니라 **글로벌 현상의 KR 발현**임을 뒷받침(신뢰도↑). 단 W2 book-marginal 관점선 **양날의 검**: 메커니즘은 진짜지만 **자본급 최근 alpha는 얇다**.

⚠️ 주의: IC t는 2021+서 오히려 **강함**(BASE 4.51·COMP_S2 4.51·S3 3.07). **IC(횡단 순위력)는 최근 살아있으나 PORT_t(long-only 실현)는 죽음** = IC≠PORT_t가 recent서 극명. 문헌 decay는 주로 L/S 스프레드 기준 → KR long-only PORT_t decay가 더 심한 것과 정합(short-leg 알파 상실 + 시장β 바닥).

---

## 대조 4 — Horizon 정합 (내부 earnings@3M lead)

- 문헌: EPS 리비전 drift = **다음 어닝(≈1분기/3M)까지 지속**(Gleason-Lee/JBFA2020 프레임). TP 섹터상대 = **1M 집중**. recommendation = 6M.
- P1: 신호는 ym말 스냅샷 → **forward 1M(ym+1)** 측정. "earnings@3M lead"는 신호의 정보가 3M horizon서 강건하다는 내부 발견([[project-earnings-revision-3m-horizon-lead]] H3 IR 1.56).
- **정합**: EPS/컨센서스 지속성 신호가 다음-분기(3M)까지 유효하다는 문헌 프레임과 내부 3M lead가 **개념 정합**. 단 P1의 `qtr_rebal_full`(분기 리밸 = 3M native)은 PORT_t < 월간(S3 0.995 vs band 2.202) → **3M을 분기 리밸로 구현하면 착시 손실**([[measurement-graduation]] WS3). **결론: horizon 정합은 "월간 측정+지속신호"로 취하고, 분기 리밸로 native화하지 말 것.**

---

## 정합/모순 종합표

| 대조 | 문헌 | P1 KR 실측 | 정합? | W2 함의 |
|---|---|---|---|---|
| 섹터상대 TP (S2) | 알파(+) US L/S | 음(−) long-only | **모순** | S2 배제 근거 강화 |
| 혁신>herding (S1) 부호 | +, herding보다 큼 | + (IC 5.25, PORT 1.01) | **정합** | S1 메커니즘 실재 |
| S1 최근 유효성 | drift 최근 감쇠 | 2021+ 약화(1.71) | 정합(감쇠) | S1 recent alpha 얇음 |
| 2021+ decay | revision drift 감쇠(글로벌) | recent PORT_t≈0 전신호 | **강정합** | 진짜현상, 자본급 얇음 |
| revision momentum→drift (S3/밴드) | +, streak이 drift 예측 | S3+밴드 PORT_t 2.20↑, 지속신호만 밴드 개선 | **정합** | S3+밴드가 최유망 |
| horizon 3M | EPS 다음분기 지속 | 월간측정 정합, 분기리밸은 착시 | 정합(월간) | 월간측정 유지 |

---

## W2 book-marginal 추진 근거 — 판정

### 근거 **강화** 요인
1. **best = S3_consensus + 보유밴드가 문헌과 3중 정합**: (a) 3-신호 합의 = 상충리비전 제거 → JBFA2020 "underreaction/consistency" 정합, (b) 보유밴드 개선 = revision momentum 지속성 이론 정합, (c) horizon 월간측정이 EPS 다음분기 프레임과 정합. **PORT_t 2.202 + paired-NW-t +2.026(baseline 대비 유의개선)** = 우연 아님, 이론 뒷받침되는 신호.
2. **decay가 아티팩트 아님을 문헌이 독립확인** → 실측 신뢰도↑(잘못 만든 게 아니라 진짜 현상).
3. **S2 배제가 문헌 정합적 정당화**: KR L/S 불가·데이터품질로 섹터상대 TP 비이전 → S2를 뺀 S3 구성이 옳은 선택.

### 근거 **약화** 요인 (정직)
1. **recent 2021+ PORT_t ≈0(대부분 음) = 자본급 최근 alpha 얇음**. 문헌도 최근 감쇠 확인 → **미래 지속성 낮을 위험**. book-marginal은 미래 기여 요구인데 최근이 죽어있음.
2. **PORT_t 2.202 < graduation HARD 2.95**, **calmar 0.587 < 0.64** → **standalone 자본 graduation 미달**(meta 명시). book-marginal(ΔIR≥0.05)은 별도 경로지만, 최근 죽은 신호가 incumbent book(STR_1715_AR_on_M4_R05 IR≈1.575)에 +0.05 순증분을 줄지 **미검증**.
3. **IC≠PORT_t가 recent서 극명**(IC 3.07 vs PORT_t≈0) → 횡단신호는 있으나 long-only 실현 불가. overlay/β 레버 없이 맨몸 S3로는 book 기여 제한적.

### 최종 판정
**W2 book-marginal 추진 근거는 "메커니즘·부호 차원선 강화, 자본급 실현성 차원선 약화" — 순효과 = 조건부 GO(제한적).**

문헌 재검증은 W2의 **이론적 토대를 확정**했다(4 claim 실존·부호 확인, S3/밴드/월간측정이 문헌 정합). 그러나 **최근(2021+) alpha 감쇠가 문헌·실측 양쪽서 확인**되어, "지금 자본을 붙일 근거"로는 약하다. **book-marginal 승부는 S3+밴드 신호를 맨몸이 아니라 overlay/regime과 결합해 최근-생존 여부를 forge에서 검증**해야 성립.

---

## 권고 — KR서 유망한 신호구성

1. **채택 우선 = S3_consensus + 보유밴드** (PORT_t 2.202, turnover 3.59, paired-NW +2.03). 문헌 3중 정합 + 회전 낮음. **다음 스텝: forge build_bt_result로 authoritative 재측정 + book-marginal ΔIR 산출**(canonical_screen은 admission-binding 아님).
2. **배제 확정 = S2_tpsect** (문헌 정합적 VALIDATED-negative). KR long-only 비이전. W2 구성서 제외.
3. **S1_innovrev = 보조축만**. 부호·메커니즘 실재하나 standalone PORT_t 1.01·최근 약화. S3 합의 안의 한 성분으로만(단독 편입 비권장).
4. **horizon = 월간 측정 유지, 분기 리밸 금지**(3M native화는 착시 손실). "earnings@3M lead"는 신호선택·검증 관점서만 활용.
5. **최근 decay 대응 (자본급 필수조건)**: S3+밴드를 **overlay/regime timing과 결합**해 2021+ 생존 검증. 맨몸 standalone은 recent PORT_t≈0이라 자본 부적격. 이것이 book-marginal GO/NO-GO의 실제 관문.
6. **미검증 후속**: (a) Gleason-Lee "저커버리지 강화"를 KR서 커버리지 상호작용으로 분해(미측정) — 저커버리지 KR 종목서 S3 강한지 확인 시 새 alpha 여지. (b) forge 재측정으로 PORT_t 2.202가 authoritative서 유지되는지(canonical_screen 낙관 가능성).
