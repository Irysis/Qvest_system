# Smart Beta (5-factor) — BL + JM + 3방법 측정 결과 · NO-GO

**작성**: 2026-07-01 (어제 원격 끊김 세션 계승·완주, 도훈 mandate)
**모드**: factor-rotation (Lane3 모듈 배합) — 5 스마트베타 팩터를 국면/BL로 배합
**측정엔진**: `02_Infrastructure/contracts/weighted_screen_bt.R` (NW lag-3 portfolio-α t, active vs cap-w KOSPI200, 15bps delta-cost)
**metric_type**: `weighted_screen` (contract build_benchmark_compare 경유 실측 — proxy 아님)
**기간**: 2015-01 ~ 2026-05 (137개월, top-20 EW long-only, 유동성 ADV≥2e8 floor)
**벤치마크**: `.cache/benchmark.parquet` KOSPI200 — 2015-2026 cum **+231%** (2025-26 강세장 포함, full valid)

---

## 1. 파이프라인 (복원·검증)

5 팩터 z-score (`panel_5factor_composite.parquet::f_*_z`) → **팩터 가중 배합** → top-20 EW.

- **5 팩터** = `value, quality, mom, lowvol, size` (panel `f_value_z … f_size_z`, NA 0건). `w_bl.parquet`엔 `growth`도 있으나(평균 5.5%) **scored panel엔 부재 → 운용 유니버스는 5팩터 확정**.
- **3 방법 = 팩터를 배합하는 3가지 가중**:
  - `ew` = 5 z-score 단순평균 (검증: `score_ew == mean(5z)` cor=1.000, max|Δ|=0)
  - `fm` = Fama-MacBeth 팩터가중 배합 (`score_fm`, 시변·추정)
  - `rc` = 국면조건부 팩터가중 (`regime_weights_composite.parquet`, 4국면 V0/V1×T0/T1. 검증: `score_rc == regime-blend` cor=1.000)
- **BL** = 4번째 배합법: `w_bl.parquet` 월별 팩터배분(EW prior reverse-opt π=δΣw + score-view Q, τ=0.05)으로 5 z 배합 → top-20 EW.
- **JM (Jagannathan-Ma)** = 제약 minvar — BL이 고른 top-20에 trailing-36m Ledoit-Wolf Σ로 long-only Σw=1 [0,0.20] minvar 가중 (JM 핵심 = no-short 제약이 곧 shrinkage).

**스코어→view 스케일 (§3 확인)**: BL view Q = score를 월 기대초과수익으로 0.02×z-정규화(`_wadv_blacklitterman.R` L65 동일). `w_bl` 배분은 **value 평균 53.5%** 집중(effective #factors=2.75) — KR value 팩터 후술.

---

## 2. 방법별 측정 (vs Book pt2.64 / SR1.36 / calmar1.33)

| 방법 | n | **pt(NW3)** | oos | SR(abs) | calmar | TO | SR(active) | IR |
|---|---|---|---|---|---|---|---|---|
| FM-blend (top20 EW) | 137 | **+0.59** | -1.04 | 0.81 | 0.42 | 10.5 | +0.21 | +0.21 |
| RC-regime (top20 EW) | 137 | -0.01 | -0.88 | 0.73 | 0.41 | 14.0 | -0.00 | -0.00 |
| BL (top20 EW) | 137 | **-0.57** | NA | 0.40 | 0.10 | 7.9 | -0.18 | -0.18 |
| JM = minvar (top20 BL-sel) | 137 | **-0.77** | NA | 0.31 | 0.07 | 9.9 | -0.23 | -0.23 |
| EW-blend (top20 EW) [baseline] | 137 | -0.85 | -3.79 | 0.40 | 0.15 | 11.8 | -0.24 | -0.24 |

- **벤치(KOSPI200) 자체 SR = 0.65** (ann 15.5%). top-20 팩터포트 대부분이 **벤치보다 risk-adjusted 열위** → active SR/IR 음수.
- **Paired NW-t (타이밍 실재성)**: BL vs EW-blend = **+0.29** (무의미) · JM vs BL-EW = **-0.77** (minvar이 오히려 악화).
- 재현 검증: 본 ew/fm/rc는 기존 `bt_3methods_composite.rds`(어제 10:56)와 정합 (fm pt 0.59 vs 0.597, rc -0.01 vs -0.060; ew는 유동성 floor 적용 차이로 -0.85 vs -1.385).

---

## 3. 결론 — NO-GO (capital-grade 아님, screen-tier 미만)

**Book(STR_1715, pt2.64/SR1.36/calmar1.33) 초과 = 0개. 졸업 HARD(pt2.95·oos0.7·calmar0.64) 통과 = 0개.**

1. **BL/JM이 가장 나쁨**. BL pt **-0.57**, JM pt **-0.77** — 단순 FM 배합(pt +0.59)보다도 못함. 어떤 게이트(Book·HARD·screen pt≥2)도 미통과.
2. **BL 실패 메커니즘 (명확)**: `w_bl`가 **value에 평균 53.5% 집중**. KR value는 post-2015 secular decay 입증완료([[reference-kr-value-factor-decay]] V01~24 24/24 감쇠, value 프리미엄 死). BL의 reverse-opt + score-view가 **죽은 팩터로 북을 집중** → EW 배합보다 열위. (effective #factors 2.75 = 과집중.)
3. **JM(minvar) 역효과**: 이미 빈약한 BL 선택 위에 low-vol 틸트를 더해 underperformance 가중 (paired-t -0.77).
4. **타이밍 실재성 없음**: BL 팩터-타이밍이 naive EW 배합 대비 paired-NW-t +0.29(무의미) → **정적틸트 대비 타이밍 알파 부재**. Shu-Mulvey(`_smv_lcode.R`: TE4 pt **3.90**, placebo p<0.001로 **타이밍 실재**·calmar 0.73, 단 oos 0.42 screen-tier)와 **질적으로 대비** — Shu-Mulvey는 다피처 SJM+BL로 타이밍이 실재했으나 KR decay가 졸업만 차단했고, 본 smart-beta BL은 **타이밍 자체가 없고 + value 과집중으로 음수 알파**까지 감.

**측정 integrity 검증 (자체 적대검증, AX-008)**:
- 벤치 정렬: all-stock EW(fwd_1m) raw cor 0.069는 micro-cap 극단치(max +2450%, 683건>100%) 탓 — **winsor 후 cor 0.47·mean 0.0098≈BM 0.0128**로 fwd_1m forward-정렬 정상 확인(off-by-one 없음).
- top-20 포트는 outlier 무오염: BL top20 월수익 [-21%,+47%], **50%+ 월 0건**(score-selection + 20종 분산이 tail 차단). BL cum +139% vs 벤치 +331% = 강세장에 크게 뒤짐 — 아티팩트 아닌 실재 열위.

**판정**: Smart Beta 5팩터(BL/JM/3방법) 전부 **NO-GO**. screen-tier(pt≥2 신호력)에도 미달. KR value-heavy BL 배분이 구조적 패인. 후속 가치 낮음 — value 비중을 강제로 빼면 5팩터 중 2개(value/quality) 무력화되어 사실상 mom/lowvol/size 3팩터 문제로 축소되며, 이는 기존 RAMP M-code(cap-w pt 2.37)·momentum-centric(pt 2.21) 결과로 이미 천장 입증.

---

## 산출물
- `smv_measure_result.rds` / `smv_measure_result.csv` (방법별 pt/oos/SR/calmar/TO/IR)
- 측정 스크립트: scratchpad `_smv_measure.R` (재현 가능, weighted_screen_bt 경유)
- 입력(어제 빌드 retain): `panel_5factor_composite.parquet`(5팩터 z) · `scores_3methods_composite.parquet`(ew/fm/rc) · `regime_weights_composite.parquet`(4국면) · `w_bl.parquet`(BL 팩터배분)

## 참조
- 게이트: `.claude/rules/measurement-graduation.md` (HARD 3종 · screen-tier · paired-NW-t)
- [[reference-kr-value-factor-decay]] · [[project-ramp-shumulvey-faithful]] · [[reference-kr-sr-ceiling-overlay]] (25종 천장 ~1.1)
- Book: STR_1715_AR_on_M4_R05 (`06_Registry/live_track/`)
